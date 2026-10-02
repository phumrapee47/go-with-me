# Task List — Round 8 (Bug Fixes: หน้าสร้างทริป)

อ้างอิง: docs/requirements-round8.md
ขอบเขต: bug fix ล้วน ไม่มี UI ใหม่/schema ใหม่/endpoint ใหม่ ข้าม Architect/UIUX แล้ว
ทั้ง 3 บั๊กเป็น **P0 เท่ากันหมด** (บล็อก flow หลัก) — ลำดับด้านล่างจัดตามความสะดวกในการ implement (ง่าย/แยกส่วนชัดเจนก่อน → ต้องแก้ cross-widget state ทีหลัง) ไม่ได้แปลว่าตัวหลังสำคัญน้อยกว่า
โปรเจกต์ไม่มี git repo — ห้ามสั่งใช้คำสั่ง git ใดๆ

---

## T1: BUG-1 — Dedup ผลลัพธ์ค้นหาสถานที่ก่อน render (แก้ duplicate-key crash)

**Root cause ที่ยืนยันแล้วจากโค้ดจริง:**
- `lib/features/geo/presentation/place_search_field.dart:147` — `ListTile(key: ValueKey('place-${s.label}'), ...)` สร้างจาก `_search.results` (L145) แบบไม่ dedup ถ้า Nominatim ส่ง label ซ้ำ → key ซ้ำใน `Column` (L143-154) → Flutter crash
- `PlaceSuggestion` (`lib/features/geo/domain/geo_services.dart:5-9`) มีแค่ `label` + `point` ไม่มี id ใดๆ จาก Nominatim (ไม่มี `place_id` เก็บไว้เลยในโมเดลปัจจุบัน) ดังนั้นตัวระบุที่ใช้ dedup ได้จริงคือ `label` + `point` (lat/lng) รวมกัน
- ผลลัพธ์ที่ dedup แล้วถูกเก็บ/ส่งต่อที่ `lib/features/geo/presentation/place_search_controller.dart` (ดู field `results` L27, ถูก set ที่ L70 จาก `search()`)

**งานที่ต้องทำ:**
1. เพิ่มการ dedup ใน `place_search_controller.dart` ตอน set `results` (บรรทัดประมาณ L70) — dedup ตาม key ผสม `label + point.latitude + point.longitude` (ใช้ `LinkedHashSet`/`Map` เพื่อรักษาลำดับเดิมของผลลัพธ์แรกที่เจอ ไม่ใช่ sort ใหม่) เพื่อไม่ให้ query ปกติที่ผลลัพธ์ไม่ซ้ำเปลี่ยนพฤติกรรม
   - ทำที่ controller layer (ไม่ใช่ใน widget) เพื่อให้ logic ทดสอบได้ตรงไปตรงมาแบบ unit test และป้องกัน bug ซ้ำถ้ามีจุดเรียกอื่นในอนาคต
2. (defensive, ทำคู่กันได้) ใน `place_search_field.dart:147` เปลี่ยน key จาก `'place-${s.label}'` เป็น key ที่รวม index ด้วย เช่น `ValueKey('place-$index-${s.label}-${s.point.latitude}-${s.point.longitude}')` เป็น safety net ชั้นสอง เผื่อมี edge case dedup ชั้น controller หลุด — ไม่ใช่การแก้แทน dedup แต่เสริมกัน

**ไฟล์ที่ต้องแก้:**
- `lib/features/geo/presentation/place_search_controller.dart`
- `lib/features/geo/presentation/place_search_field.dart`

**เทสต์ที่ต้องเพิ่ม** (ดู pattern mock http client จาก `test/features/geo/services_test.dart` และ `test/features/geo/osrm_road_snap_test.dart`, มี test เดิมของ controller ที่ `test/features/geo/place_search_controller_test.dart` — เพิ่ม case ในไฟล์นี้):
- Mock geocoding service/http response ให้ส่งผลลัพธ์ที่ label+point ซ้ำกัน 2-3 รายการ → assert ว่า `controller.results` ไม่มีรายการซ้ำ (length ลดลงตามที่ dedup ควรเป็น) และไม่ throw/crash
- Regression: mock ผลลัพธ์ปกติที่ไม่ซ้ำ (เช่น 5 รายการ label ต่างกัน) → assert ว่า `results` ยังคงครบทุกรายการ ลำดับไม่เปลี่ยน (ป้องกันไม่ให้ dedup logic กิน record ที่ไม่ได้ซ้ำจริง)
- ถ้าเป็นไปได้เพิ่ม widget test เบาๆ ยืนยันว่า `place_search_field.dart` render โดยไม่ throw duplicate-key assertion เมื่อ controller คืนผลซ้ำ (ใช้ fake controller/provider override ตาม pattern ที่มีอยู่)

**Dependency:** ไม่มี ทำได้อิสระจาก T2/T3

---

## T2: BUG-2 — Timeout ครบทุกขั้นของ location request + ไม่บล็อก UI (แก้ ANR)

**สิ่งที่ตรวจสอบแล้วจากโค้ดจริง:**
- `lib/features/geo/data/geolocator_location_service.dart:30-42` (`currentPosition()`) **มี `timeLimit: Duration(seconds: 10)` อยู่แล้ว** ใน `Geolocator.getCurrentPosition` — จุดนี้ไม่ใช่ต้นตอหลักของ ANR
- แต่ `permission()` (L18-21) และ `request()` (L24-27) เรียก `Geolocator.isLocationServiceEnabled()`, `Geolocator.checkPermission()`, `Geolocator.requestPermission()` **โดยไม่มี timeout ใดๆ เลย** — เป็น known issue ของ geolocator บางอุปกรณ์/บาง GPS state ที่ค้างไม่ return ค่าเลย ซึ่งตรงกับอาการ ANR ที่ QA เจอ (เพราะ flow `obtainCurrentLocation` ใน `current_location.dart:18-46` เรียก `loc.permission()`/`loc.request()` ก่อน `loc.currentPosition()` เสมอ)
- ต้องยืนยันเพิ่มเติมด้วยตัวเอง (grep/ลอง reproduce) ว่ามีจุดอื่นที่เรียก native plugin แบบไม่มี timeout ปนอยู่หรือไม่ (เช่นใน `pick_point_screen.dart:242`, `preset_screens.dart:191` ที่เรียก `obtainCurrentLocation` เหมือนกัน — จุดเรียกใช้ shared function เดียวกันอยู่แล้ว น่าจะได้ fix ครอบคลุมถ้าแก้ที่ `current_location.dart`/`geolocator_location_service.dart`)

**งานที่ต้องทำ:**
1. ใน `geolocator_location_service.dart` ครอบ `permission()` และ `request()` ด้วย `.timeout(Duration(seconds: ...))` (เลือกค่าที่เหมาะสมตาม AC เช่น 10-15 วินาที) และ catch `TimeoutException` ให้คืนค่าที่สื่อความหมาย (เช่น map เป็น `LocationPermissionState` ที่เหมาะสม หรือถ้า interface ปัจจุบันไม่รองรับให้ throw/ส่งต่อเป็น failure ที่ `currentPosition()`/เรียกจุดบนสุดจับได้)
   - ดู `LocationPermissionState` และ `LocationService` interface ที่ `lib/features/geo/domain/location_service.dart` ก่อนตัดสินใจ ว่าจะเพิ่ม state ใหม่ (เช่น `timeout`) หรือ map เข้ากับ `denied`/error ที่มีอยู่แล้ว — เลือกทางที่ไม่ต้องแก้ schema/UI ใหม่ (นอก scope รอบนี้) จึงควร map เข้า state/Result ที่มีอยู่แล้วเป็นหลัก
2. ใน `currentPosition()` (L30-42) เพิ่ม `.timeout(...)` ครอบ `Geolocator.getCurrentPosition(...)` เป็นชั้นป้องกันซ้อน (defense in depth) เผื่อ `timeLimit` ภายในปลั๊กอินไม่ทำงานตามสัญญาบนบางอุปกรณ์ — timeout ที่ระดับ Dart future ควรตั้งนานกว่า `timeLimit` ภายในเล็กน้อยหรือเท่ากัน (เช่น 12 วินาที) แล้ว catch แล้วคืน `Err(AppFailure(...))` ที่มี error message สื่อความหมายชัดเจนกว่าปัจจุบัน (ปัจจุบัน catch (_) เหมารวมทุก error เป็น `locationUnavailable` — ตรวจสอบว่ามี failure code เฉพาะสำหรับ timeout อยู่แล้วใน `core/error/app_failure.dart` หรือไม่ ถ้าไม่มีให้ใช้ตัวที่ใกล้เคียงที่สุดที่มีอยู่ เพื่อไม่ต้องเพิ่ม schema/contract ใหม่)
3. ตรวจสอบ `current_location.dart` (`obtainCurrentLocation`, L17-55) ว่าเมื่อ error/timeout เกิดขึ้น ผู้ใช้เห็น snackbar ทันที (ดูเหมือนโค้ดปัจจุบันรองรับผ่าน `_snack(context, failureMessage(f))` ที่ L51 อยู่แล้ว — ให้ยืนยันว่า path timeout ใหม่ไหลเข้ามาที่ error branch นี้ได้จริง ไม่ค้างอยู่ก่อนถึงจุดนี้)
4. ตรวจสอบว่าไม่มีการเรียก location API แบบ sync-blocking บน UI thread จุดอื่น (grep `Geolocator.` ทั้งโปรเจกต์) — ถ้าเจอจุดอื่นที่ไม่ผ่าน `LocationService` interface นี้ ให้รายงานกลับ ไม่ต้องแก้เพิ่มถ้าไม่อยู่ในหน้าสร้างทริป (out of scope ตาม requirements-round8.md)

**ไฟล์ที่ต้องแก้:**
- `lib/features/geo/data/geolocator_location_service.dart`
- อาจต้องแตะ `lib/features/geo/domain/location_service.dart` ถ้าต้องปรับ state/enum เล็กน้อย (เลี่ยงถ้าเป็นไปได้)
- ตรวจสอบ (อาจไม่ต้องแก้) `lib/features/geo/presentation/current_location.dart`

**เทสต์ที่ต้องเพิ่ม** (ดู pattern mock จาก `test/features/geo/services_test.dart`):
- Mock/fake `LocationService` หรือ platform channel ให้ `permission()`/`request()`/`currentPosition()` ค้างเกินเวลาที่ตั้ง (ใช้ `Completer` ที่ไม่ complete หรือ `Future.delayed` นานเกิน timeout) → assert ว่าฟังก์ชันคืนค่า error/failure ภายในเวลาที่คาดไว้ (ใช้ `fakeAsync` หรือจำกัดเวลาด้วย `expectLater(..., timeout: ...)`) ไม่ hang ทดสอบค้าง
- Regression: mock ให้ตอบเร็วปกติ (ภายใน timeout) → assert ว่ายังคืนตำแหน่งถูกต้องเหมือนเดิม ไม่ error ปลอมจาก timeout logic ใหม่
- Regression: mock permission denied / service off ระหว่างรอ → assert ว่าได้ error message ที่สื่อความหมายทันที (ไม่ใช่ timeout error ปนกัน)

**Dependency:** ไม่มี ทำได้อิสระจาก T1/T3

---

## T3: BUG-3 — Validation flag ไม่อัปเดตหลังปักหมุดจุดเริ่มต้นบนแผนที่

**สิ่งที่ตรวจสอบแล้วจากโค้ดจริง (`lib/features/trip/presentation/create_trip_step1_screen.dart`):**
- Error message ที่แสดง (`_issueText()`, L82-87) มาจาก field state `_issue` (L29) ซึ่ง**ถูกคำนวณใหม่เฉพาะตอนกดปุ่ม "ถัดไป" ใน `_next()` (L75-80)** เท่านั้น — ไม่มี logic ใดใน widget นี้ที่ recompute `_issue` ทันทีเมื่อ `origin`/`dest` ใน `tripFormProvider` เปลี่ยนค่า (ไม่มี `ref.listen` หรือจุดอื่นที่ set `_issue`)
- `_pick({required bool origin})` (L59-73) เรียก `PickPointScreen` แบบ push แล้ว pop กลับมาพร้อม `Place` แล้วเรียก `ctrl.setOrigin(place)`/`ctrl.setDest(place)` (L72) — จุดนี้**ไม่แตะ `_issue` เลย** เหมือนกับ `_useCurrent()` (L51-57) และ `onSelected: ctrl.setOrigin` ของช่องค้นหา (L114/L123)
- สรุปคือทั้ง 3 flow (พิมพ์ค้นหา / GPS / ปักหมุด) **ล้วนไม่ recompute `_issue` แบบ reactive** จากโค้ดที่อ่านได้ในไฟล์นี้ — ให้ programmer ตรวจสอบเพิ่มเติมด้วยตัวเอง (รัน repro บน emulator ตาม step ที่ QA/requirement ระบุ) ว่าทำไมในทางปฏิบัติ 2 flow แรกดูเหมือนไม่มีปัญหา (เช่น ผู้ใช้มักไม่กด "ถัดไป" ก่อนแล้วค่อยแก้ผ่าน search/GPS ในการทดสอบเดิม จึงไม่เคยเห็น error ค้างจริงๆ) ก่อนเลือกวิธีแก้ — ถ้า repro ยืนยันว่าปัญหาเกิดกับทุก flow เท่ากัน ให้แก้ที่ root cause เดียว (ตาม AC ข้อ 3 ที่ต้องยังไม่พัง 2 flow เดิมอยู่แล้ว การแก้ให้ reactive ทั้งหมดจะ satisfy ทั้ง 3 AC พร้อมกัน)

**แนวทางแก้ที่แนะนำ:**
1. เปลี่ยนให้ `_issue` recompute ทันทีทุกครั้งที่ `origin`/`dest` เปลี่ยน แทนที่จะ cache แค่ตอนกด next เช่น เพิ่ม `ref.listen<TripForm>(tripFormProvider, (prev, next) { if (prev?.origin != next.origin || prev?.dest != next.dest) setState(() => _issue = TripFormValidator.validatePlaces(next.origin, next.dest)); })` ใน `build()` — แต่ต้องระวัง**ไม่ให้ error message โผล่ก่อนผู้ใช้เคยกด "ถัดไป"** (เช่น หน้าเพิ่งเปิดมา origin/dest ยังว่าง ไม่ควรมี error ค้างโชว์ทันที) — เพิ่ม flag `bool _touched = false` ตั้งเป็น `true` ตอนกด `_next()` ครั้งแรก แล้วให้ `ref.listen` recompute เฉพาะเมื่อ `_touched == true`
2. คง `_next()` เดิมไว้ (ยัง validate + set `_touched = true` + navigate ถ้า `issue == null`)

**ไฟล์ที่ต้องแก้:**
- `lib/features/trip/presentation/create_trip_step1_screen.dart`

**เทสต์ที่ต้องเพิ่ม:**
- ให้ programmer หาไฟล์ widget test ที่เกี่ยวข้องเองจากการ grep (เช่น หา `create_trip_step1` หรือ `CreateTripStep1Screen` ใน `test/`) ถ้ายังไม่มีไฟล์ทดสอบสำหรับหน้านี้ ให้สร้างใหม่ตาม pattern widget test ที่มีอยู่ในโปรเจกต์
- Case บั๊กหลัก: กด "ถัดไป" ทั้งที่ยังไม่มี origin → เห็น error "เลือกจุดเริ่มต้น" → จำลอง flow ปักหมุดบนแผนที่ (mock `PickPointScreen`/`Navigator` return `Place` หรือเรียก `ctrl.setOrigin` ตรงๆ ผ่าน provider override) → assert ว่า error text หายไปทันทีโดยไม่ต้องกด "ถัดไป" ซ้ำ
- Regression: ทำ case เดียวกันซ้ำสำหรับ flow พิมพ์ค้นหา (`ctrl.setOrigin` ผ่าน `onSelected`) และ flow GPS (`_useCurrent`) → assert ว่า error หายไปทันทีเหมือนกัน (ต้องไม่ regress)
- Regression: หน้าเปิดใหม่ ยังไม่กด "ถัดไป" เลย และยังไม่ได้เลือก origin/dest → assert ว่า**ไม่มี** error text แสดงค้างตั้งแต่แรก (กัน false-positive จากการทำ reactive validation)
- Regression: กด "ถัดไป" เมื่อ origin+dest ถูกต้องครบ (ไม่ว่าจะมาจาก flow ไหน) → assert ว่า navigate ไปหน้าถัดไปสำเร็จ

**Dependency:** ไม่มี ทำได้อิสระจาก T1/T2 แต่ถ้าจะรัน manual regression test บน emulator ร่วมกับ T2 ควรแก้ T2 (ANR) ก่อนเพื่อไม่ให้ emulator ค้างระหว่างเทส flow GPS ของ T3

---

## สรุปลำดับความสำคัญ

ทั้ง T1, T2, T3 เป็น **P0 เท่ากัน** — ไม่มีตัวไหนรอฟีเจอร์ตัวอื่นทาง requirement แต่แนะนำลำดับ implement: **T1 → T2 → T3** เพราะ T1/T2 เป็นบั๊กเชิง isolated (widget/service เดียว, ผลกระทบชัดเจน, เทสต์เขียนตรงไปตรงมา) ส่วน T3 ต้องแก้ state management ข้าม 3 entry point พร้อมกันและต้องระวัง regression 2 flow เดิม จึงเสี่ยง regression มากกว่าถ้าทำก่อนโดยยังไม่เข้าใจ pattern การ validate ทั้งหมด — ทำ T1/T2 ให้เสร็จและมั่นใจก่อนจะช่วยให้ manual test ของ T3 (ที่ต้องใช้ทั้ง search/GPS/pin) ราบรื่นกว่า

## คำตัดสิน PM (ถ้ามี)
ไม่มีประเด็นขัดแย้งหรือ scope change ในรอบนี้ — ทั้ง 3 บั๊กเป็นการแก้ให้ตรงกับพฤติกรรมที่ตั้งใจไว้เดิม ไม่กระทบ `docs/requirements.md` หลัก ไม่ต้องอัป requirements
