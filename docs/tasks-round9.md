# Task List — Round 9 (UI/UX Overhaul: Modern Lifestyle & Human-First)

อ้างอิง: docs/requirements-round9.md
ขอบเขต: UI/UX-only overhaul, 5 หน้าหลัก + design tokens + badge display change — ไม่มี schema/API/endpoint ใหม่
โปรเจกต์ไม่มี git repo — ห้ามสั่งใช้คำสั่ง git ใดๆ
Pipeline ถัดไป: UIUX (docs/design-spec-round9.md) → Programmer. **Architect step ถูกข้าม** (เหตุผลดูหัวข้อ "คำตัดสิน PM" ด้านล่าง)

---

## P0 (ต้องมี)

### T1: US-7 — Design System Tokens & Polish (ทำก่อนสุด เป็นฐานของทุกหน้า)
- ถอด `BorderSide(color: AppColors.border)` ออกจาก `AppCard` และ container ตกแต่งทั่วไปทุกจุด — คงไว้เฉพาะจุด semantic border (เช่น error state ของ text field) ให้ programmer แยกแยะและ comment กำกับว่าทำไมคงไว้
- ตั้งพื้นหลังหลัก `#F8F9FC` + การ์ดขาว `#FFFFFF` + soft ambient shadow (blur 16-24px, opacity 4-6%) เป็นค่า default ของ `AppCard`/container ที่ใช้ระบบนี้ ใน `lib/core/theme/tokens.dart` / `app_theme.dart`
- นิยาม dark-mode equivalent ของพื้นหลัง/การ์ดขาว ให้ผูกกับ `ToneColors.riderDark`/`driverDark` เดิม (round 7) — ห้าม hardcode สีสว่างตายตัวในโหมดมืด
- `flutter analyze` ต้องผ่านไม่มี error/warning ใหม่, `flutter test` ชุดเดิมต้องผ่าน (อัปเดต assert ที่ผูกกับสี/border/ข้อความเดิมให้ตรงพฤติกรรมใหม่ ห้ามลบ test ทิ้งเฉยๆ)
- **ไฟล์:** `lib/core/theme/tokens.dart`, `app_theme.dart`, `AppCard` และ component ส่วนกลางที่อ้างอิง `AppColors.border`
- **Dependency:** ไม่มี — แต่ T3–T7 (5 หน้าหลัก) ทั้งหมดใช้ tokens/shadow ชุดนี้ ดังนั้นควรทำ T1 เสร็จ/เสถียรก่อนเริ่ม UI งานหน้าอื่นจริงจัง แม้จะ parallel กันได้ระดับ branch งานถ้าทีมใหญ่พอ

### T2: US-6 — Global Verified Badge (shared component, ตัดสถาบัน/องค์กรออกจากการแสดงผลทุกจุด)
- สร้าง helper/widget กลาง (เช่น `verifiedBadgeFrom(List<Badge> badges)`) ที่: (1) กรอง badge `kind == 'organization'` ทิ้งเสมอ ไม่ส่งต่อให้ UI จุดใดเห็น `orgName`, (2) ถ้ามี `email` และ/หรือ `phone` อย่างน้อย 1 อย่าง → คืนป้ายเดียว "✓ ยืนยันตัวตนแล้ว" สีฟ้าอ่อน, (3) ถ้าไม่มีทั้ง `email`/`phone` เลย → คืน null/ไม่แสดงป้าย (ห้ามปลอมสถานะยืนยัน)
- ยืนยันด้วย grep ทุกจุดที่ render `VerificationBadge`/`VerifiedBadge`/`parseBadges()`/`myBadgesProvider` ทั่วแอป (ไม่ใช่แค่ 2 หน้าที่ overhaul) ว่าเปลี่ยนมาใช้ helper กลางนี้ครบ — ถ้าเจอจุดอื่นนอก scope 5 หน้า (เช่น bottom sheet รายละเอียดผู้สมัคร) ก็ต้องแก้ด้วยเพราะ AC ของ US-6 ระบุ "ทุกจุดในแอป"
- **ไม่แตะ** `verifications`/`org_domains` table หรือ backend logic การคำนวณ badge ใดๆ — เป็นงานชั้น presentation ล้วน
- ทบทวน/อัปเดต unit/widget test เดิมที่ assert หา organization badge หรือ badge แยกทีละตัว ให้ตรงพฤติกรรมใหม่
- **ไฟล์:** จุดที่ render badge ทั่วแอป โดยเฉพาะ `lib/features/matching/presentation/`, `lib/features/profile/presentation/me_tab.dart` (`myBadgesProvider` ที่ L35,61,67)
- **Dependency:** ไม่มี (ไม่ต้องรอ T1) — แต่เป็น dependency ของ T3 (US-1) และ T7 (US-5) เพราะทั้งสองหน้าต้องใช้ widget นี้แสดงป้ายยืนยันตัวตน

### T3: US-1 — Tinder-Style Commute Card Deck
- สร้างการ์ดเต็มพื้นที่ 80-85% squircle 24dp (ใช้ `AppShape`/`AppRadius` เดิม), story indicator bar แบบ Instagram (จำนวนขีด = จำนวนภาพจริง, แตะซ้าย/ขวาสลับภาพ ไม่ชนกับ gesture ปัดซ้าย-ขวาเดิม)
- ภาพที่ 1: vector avatar ตัวอักษรชื่อ (fallback ถาวร ตามคำตัดสิน PM ข้อ (a) ด้านล่าง — ไม่ใช่รูปถ่ายจริง), ภาพที่ 2: vector รถ 3D มินิมอล (เฉพาะ `role == TripRole.driver`; ซ่อนถ้าเป็น rider/peer mode), ภาพที่ 3: mini route snapshot
  - **คำตัดสิน implementation สำหรับภาพที่ 3:** ในโค้ดปัจจุบันไม่มี static-map-image-rendering service (ตรวจสอบแล้ว ไม่พบ snapshot/staticMap utility ใดๆ ในโปรเจกต์) มีแต่ widget แผนที่แบบ interactive (`lib/core/map/app_map.dart`) — ให้ programmer/UIUX ใช้วิธี **ฝัง mini non-interactive map widget** (reuse `app_map.dart` เดิม ปิด gesture, fit bounds ให้เห็น origin→dest พร้อม marker) แทนการ rasterize เป็นรูปภาพจริง เพราะการเพิ่ม image-snapshot service ใหม่จะเป็นการเพิ่ม dependency/API ใหม่ ซึ่งอยู่นอก scope UI-only ของรอบนี้ — ยังคงเป็นการอ่านข้อมูล origin/dest ที่มีอยู่แล้วเท่านั้น ไม่มี backend call ใหม่
- gradient ดำโปร่งแสงด้านล่างการ์ด, ข้อมูล 4 บรรทัดตาม AC (ชื่อ+อายุ+badge+rating แบบมีเงื่อนไข / ข้อมูลรถเฉพาะ driver / route+เวลา+overlapPct / vibe tags frosted chip ซ่อนถ้าว่าง)
- ใช้ badge widget จาก **T2** สำหรับป้าย "✓ ยืนยันตัวตนแล้ว" — ห้ามมี badge องค์กรหลุดมา
- ปุ่มลอย 3 ปุ่ม (✕ / 💚 เด่น / ℹ️) เรียก action เดิม (skip/request match/view detail) ห้ามเปลี่ยน business logic
- 4 ธีม (rider/driver × light/dark), `flutter analyze`/`flutter test` ที่เกี่ยวกับ matching ต้องผ่านไม่ regression
- **ไฟล์:** `lib/features/matching/presentation/commute_card_deck.dart` และ component ย่อย
- **Dependency:** T1 (tokens/shadow), T2 (badge widget)

### T4: US-2 — หน้าแรก (Home Screen & Map Zoom)
- Camera animate ไป GPS จริงที่ zoom 15.0-15.5 (transition นุ่มนวล) เมื่อ permission granted; pulse dot ตำแหน่งผู้ใช้; fallback zoom level ที่สมเหตุสมผลเมื่อ permission ถูกปฏิเสธ/อ่านตำแหน่งไม่ได้ **โดยไม่ regress กับ fix BUG-2 (round 8, timeout การขอตำแหน่ง)** — ต้อง re-test flow ที่ timeout เคยแก้ไปแล้วร่วมกับงานนี้
- ปุ่ม recenter 🧭 มุมขวาล่าง, แผนที่เต็มจอไม่มีกรอบ/การ์ดครอบ
- Header ลอย: "สวัสดี, [ชื่อเล่น]" ไม่มีพื้นหลังทึบ + สวิตช์แคปซูล [🚗|🎒] (คง logic สลับ role เดิม)
- การ์ดค้นหาด้านล่าง: ลบโครงสร้างกล่องซ้อนกล่องเดิมทั้งหมด → การ์ดขาวลอยเงาจาง ไม่มีเส้นขอบเทา, ช่องค้นหา + ชิป [🏠][🏢] + ปุ่มแคปซูล "หาเพื่อนร่วมทาง" (action เดิมทั้งหมด)
- Regression ครบทุก action เดิม (ค้นหา, สร้างทริป, สลับ role, ทางลัดบ้าน/ที่ทำงาน), 4 ธีม + เข้ากับ CartoDB Dark Matter tiles เดิม
- **ไฟล์:** `lib/features/home/presentation/home_tab.dart`, `quick_home_card.dart`, `lib/core/map/app_map.dart`
- **Dependency:** T1 (tokens/shadow ของการ์ดค้นหา)

### T5: US-3 — หน้ารายการแชท (Chat Tab)
- Borderless list คั่นด้วย spacing/hairline divider แทนกล่องขาวตีกรอบเทาเดิม
- อวาตาร์วงกลม 56dp + ไอคอนรถเล็กมุมขวาล่างถ้าคู่สนทนาเป็น driver
- ชื่อตัวหนา, เวลาสีเทาอ่อนชิดขวา, ข้อความล่าสุด 1 บรรทัด ellipsis สีเทานุ่มกว่าชื่อ
- แบดจ์ unread ตำแหน่งเดิม ค่าต้องตรงกับ state เดิม (ห้ามแก้ logic นับ unread)
- Regression: แตะแถวเข้าหน้าสนทนา, swipe action เดิม (ถ้ามี) ต้องทำงานเหมือนเดิม, 4 ธีม
- **ไฟล์:** `lib/features/chat/presentation/chats_tab.dart`
- **Dependency:** T1 (tokens/divider style)

### T6: US-4 — หน้าทริปของฉัน (Ride Pass Card)
- แทนที่การ์ดพื้นหลังกรมท่าทึบเดิมด้วย Ride Pass Card ขาวนวล squircle (`AppRadius.card`) ลอยบนพื้นหลัง `#F8F9FC` + soft ambient shadow
- **ห้ามแสดงพิกัด lat/lng ดิบทุกกรณี** — ใช้ `labelFor()`/`GeocodingService.reverse()` ที่มีอยู่แล้ว (`lib/features/geo/presentation/current_location.dart:59`, ยืนยันแล้วว่ามี fallback ข้อความสั้นในตัวอยู่แล้วเมื่อ geocode ล้มเหลว — ต่อยอด fallback message ให้เป็นข้อความมิตร เช่น "ตำแหน่งที่ปักหมุด" แทน short-coordinates fallback เดิมถ้าจำเป็นตาม AC)
- เส้นทาง 🟢───🔴 พร้อมชื่อสถานที่กำกับ, pill สถานะ (เขียวมินต์ "กำลังเดินทาง" / เทา "เสร็จสิ้น") ต้องแยกแยะได้ชัดทั้ง 4 ธีม ครอบคลุมทุกสถานะเดิม (รอยืนยัน/ยกเลิก ถ้ามี) ไม่มีสถานะตกหล่นจาก mapping เดิม
- ปุ่ม "เดินทางซ้ำ" มุมขวาล่าง เรียก action เดิม
- **ไฟล์:** `lib/features/trip/presentation/trips_tab.dart`
- **Dependency:** T1 (tokens/shadow)

### T7: US-5 — หน้าโปรไฟล์ (Profile / Me Tab)
- Profile Hero Card: avatar วงกลม 84dp (หรือ vector ตัวอักษรชื่อ ตามคำตัดสิน (a)), ชื่อเล่นตัวหนา, badge จาก **T2**, สถิติ 3 คอลัมน์ (rating/จำนวนทริป/CO₂) — ค่าไม่มีข้อมูลต้องมี placeholder สื่อความหมาย ห้ามแสดง 0 ลวงตา
- `myBadgesProvider` (`me_tab.dart:35,61,67`) ต้องใช้ helper จาก T2 — filter organization ออกทุกจุดที่ใช้ list badge เดิม
- เมนูตั้งค่าจัดเป็น 3 การ์ด (การเดินทาง/ความปลอดภัย/ระบบ) ครบทุกเมนูเดิมไม่ตกหล่น, ไอคอนในวงกลม soft tinted container ตามธีม
- Regression: ทุก action เมนูเดิม (แก้ข้อมูลรถ, ผู้ติดต่อฉุกเฉิน, สวิตช์ธีม ฯลฯ) ต้องนำทาง/ทำงานเหมือนเดิม
- **ไฟล์:** `lib/features/profile/presentation/me_tab.dart`
- **Dependency:** T1, T2

---

## P1 (ควรมี)
- T8: เพิ่ม/ทบทวน widget test ครอบคลุม 4 ธีม (rider/driver × light/dark) แบบ snapshot-lite หรือ golden-ish assertion (ไม่มี CI/visual regression infra ตาม out-of-scope — ทำเท่าที่ unit/widget test framework เดิมรองรับ) สำหรับ T3–T7 เพื่อลดความเสี่ยง regression เชิงสี/ธีมที่ตรวจด้วยตาอย่างเดียวไม่พอ
- T9: Manual QA checklist เฉพาะจุดเสี่ยง regression สูง: BUG-2 timeout flow (US-2 ร่วมกับ T4), unread count (US-3), trip status mapping ครบทุกสถานะ (US-4) — เตรียม checklist ให้ QA ใช้ตรงจากรอบนี้

## P2 (ดีถ้ามี)
- T10: ปรับ micro-animation เพิ่มเติม (เช่น spring bounce ตอนปัดการ์ด US-1, transition ปุ่ม recenter US-2) ถ้าเวลาเหลือหลัง P0 เสร็จและผ่าน QA แล้วเท่านั้น — ห้ามเริ่มก่อน P0 เสร็จ

---

## สรุปลำดับ implement แนะนำ
T1 → T2 → (T3, T4, T5, T6, T7 ขนาน กันได้ตามทีม/เวลาที่มี เพราะแก้คนละไฟล์คนละหน้า ไม่ชน) → T8/T9 → T10

**จุดเสี่ยง timeline:**
- T3 (US-1) มีความซับซ้อนสูงสุด (gesture ซ้อนกัน, 3 ภาพ/vector/mini-map ที่ต้องมีเงื่อนไข role, badge merge) — เสี่ยงใช้เวลาเกินประมาณการมากที่สุดในกลุ่ม P0
- T4 (US-2) เสี่ยง regression กับ BUG-2 (timeout location) ที่เพิ่งแก้ใน round 8 — ต้อง regression test คู่กันเสมอ ไม่ใช่แค่ verify UI ใหม่เฉยๆ
- T1 เป็น blocking foundation ทางคุณภาพ (ไม่ blocking ทางไฟล์) — ถ้า dark-mode token ของ T1 นิยามผิด/ไม่ครบ จะกระทบ QA รอบ 4-ธีมของทุกหน้าพร้อมกัน แนะนำให้ T1 เสร็จและ verify ครบ 4 ธีมก่อนที่ T3–T7 จะเข้าสู่ QA

---

## คำตัดสิน PM

### ประเด็น (a): ขอบเขตรูปภาพใน US-1 (สมมติฐาน A ของ BA)
**คำตัดสิน:** เห็นด้วยกับสมมติฐาน A ที่ BA เขียนไว้ — รอบนี้ใช้ **vector/illustration placeholder เท่านั้น** (vector avatar ตัวอักษรชื่อ สำหรับภาพที่ 1, vector รถ 3D มินิมอล สำหรับภาพที่ 2, embedded mini non-interactive map widget สำหรับภาพที่ 3) ไม่เพิ่ม photo upload/storage/schema ใดๆ ในรอบนี้ การตัดสินใจเรื่อง photo infra จริง (เพิ่ม field + storage bucket + upload flow) ให้ยกเป็นหัวข้อพิจารณาของรอบถัดไปแยกต่างหาก ไม่ผูกกับรอบนี้
**เหตุผล:** รอบนี้ประกาศ scope ชัดเจนว่าเป็น UI/UX-only ไม่แตะ schema/backend (ดู requirements-round9.md บรรทัด 4, 165) การเพิ่ม photo field เป็นงาน cross-cutting ที่กระทบ data model, storage, permission, upload UX เต็มรูปแบบ ควรเป็นรอบของตัวเองที่มี Architect เข้าร่วมออกแบบ schema/storage ไม่ใช่แทรกเข้ามาครึ่งๆ กลางรอบที่ตั้งใจเป็น visual overhaul ล้วน — ทำแบบ vector-only วันนี้ยัง deliver คุณค่า "รู้สึกไลฟ์สไตล์สมัยใหม่" ได้ตาม user story หลักได้เพียงพอ โดยไม่เพิ่มความเสี่ยง scope creep

### ประเด็น (b): ขอบเขตการ "ตัดระบบยืนยันสถาบัน" (สมมติฐาน B)
**คำตัดสิน:** ยืนยันตามสมมติฐาน B — ขอบเขตคือ **UI-display-only**: ซ่อน badge/label `organization` และ `orgName` ทุกจุดที่ผู้ใช้เห็น (การ์ดจับคู่, โปรไฟล์, bottom sheet รายละเอียด ถ้ามี) **ไม่แตะ** `verifications`/`org_domains` table, ไม่ลบ flow การยืนยันสถาบัน/กรอกอีเมลองค์กรฝั่ง backend หรือหน้าจอยืนยันตัวตน (ถ้ามีหน้าแยกสำหรับ flow นี้อยู่นอก 5 หน้าที่ระบุ ให้คงไว้ตามเดิม ไม่อยู่ใน scope รอบนี้)
**เหตุผล:** ผู้ใช้ (product owner) ยืนยันโดยตรงในรอบนี้แล้วว่าไม่ต้องการให้เรื่องสถาบันเข้ามาเกี่ยวข้องกับ scope ตอนนี้เลย ตีความเป็น "อย่าแตะ/อย่าเปลี่ยน backend หรือ flow การยืนยันสถาบันเลยแม้แต่น้อย" สอดคล้องกับหลัก UI-only ของทั้งรอบ — ถ้าทำเกินไปถึงลบ flow จริงจะเป็นการเปลี่ยน business capability ที่ควรผ่านการตัดสินใจแยกชัดเจนกว่านี้

### ประเด็น (c): "Global Verified" badge เป็น presentation merge เท่านั้น (สมมติฐาน C)
**คำตัดสิน:** ยืนยันตามสมมติฐาน C — เป็นการ merge badge kind `email`/`phone` ที่มีอยู่แล้วจาก `parseBadges()` ที่ชั้น UI (ดู T2) เท่านั้น **ไม่เพิ่ม field/table ใหม่ฝั่ง backend**
**เหตุผล:** ข้อมูลที่ต้องใช้ (มี/ไม่มี email badge, มี/ไม่มี phone badge) มีอยู่แล้วครบในระบบปัจจุบัน การรวมแสดงผลเป็น 1 ป้ายคือ pure UI transformation ไม่มีเหตุผลทางเทคนิคที่ต้องเพิ่ม backend field ให้ซับซ้อนเกินจำเป็น

### ประเด็น: ควรข้าม Architect step หรือไม่
**คำตัดสิน:** **เห็นด้วยกับ orchestrator — ข้าม Architect step ได้** สำหรับรอบนี้ทั้งหมด รวมถึงประเด็น (a) ที่ตรวจสอบแล้วว่าไม่ต้องใช้ image-snapshot service ใหม่ (ดูรายละเอียดใน T3 — ใช้วิธี reuse `app_map.dart` แบบฝัง widget แทน แก้ปัญหาโดยไม่ต้องเพิ่ม service/dependency ใหม่ จึงยังคงเป็น presentation-layer ล้วน)
**เหตุผล:** ตรวจสอบ requirements-round9.md และ codebase ที่เกี่ยวข้อง (geo reverse-geocoding, map widget, badge parsing) แล้วยืนยันว่าทุก AC ของทั้ง 7 user story ทำได้ด้วยการอ่าน/จัดเรียง/แสดงผลข้อมูลที่มีอยู่แล้วในระบบปัจจุบันทั้งหมด ไม่มีจุดใดต้องการ schema ใหม่, API endpoint ใหม่, external dependency ใหม่, หรือ trust boundary ใหม่ — ไม่มีสิ่งที่ orchestrator มองข้าม

### หมายเหตุสำคัญ: ไม่ต้องอัป requirements
คำตัดสินทั้งหมดข้างต้นเป็นการ **ยืนยัน (ratify)** สมมติฐาน A/B/C ที่ BA เขียนไว้แล้วใน requirements-round9.md ตรงตามที่เขียนไว้ทุกประการ ไม่มีจุดใดที่คำตัดสินของ PM เปลี่ยน scope ไปจากที่ requirements-round9.md ระบุไว้ — **ไม่ต้องอัป requirements**
