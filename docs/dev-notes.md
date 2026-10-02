# Dev Notes

## Task ที่ implement แล้ว (Phase 1-2)
- [x] T1.1 — `pubspec.yaml`, `analysis_options.yaml` (strict-casts/raw-types, unawaited_futures, avoid_print) — org `com.gowithme`, iOS+Android. Dependencies: flutter_riverpod, go_router, supabase_flutter, flutter_secure_storage, google_fonts, shared_preferences, url_launcher, flutter_localizations. ยังไม่เพิ่ม flutter_map/geolocator/share_plus (ยังไม่มีโค้ดใช้; เพิ่มใน Phase 3+)
- [x] T1.2 — โครง `lib/core/*` และ `lib/features/{auth,profile,trip,matching,chat,safety,sharing,privacy,home,onboarding,shell}` (feature ที่ยังว่างมี `.gitkeep`)
- [x] T1.3 — `core/config/app_config.dart` (`evaluateConfig` pure + `loadConfigFromEnvironment`), `env.example.json`, `.gitignore` (`.env*`, `env/*.json`, keystore) — ไม่มีค่า/ค่าไม่ถูก -> `/config-error` ไม่ crash ไม่แสดง URL/key
- [x] T1.4 — ProviderScope + `configProvider`/`sharedPrefsProvider`, go_router + guard, `AppFailure`/`Result`/`mapError`/`failureMessage` (ไทย, ครบ 26 GWM_* + auth/postgrest/network)
- [x] T1.5 — `core/logging/log.dart` (no-op ใน release; ส่งได้แค่ code); `Supabase.initialize(debug:false)`
- [x] T1.6 — Android: INTERNET, location (foreground), `allowBackup=false`, `usesCleartextTraffic=false`, label ไทย; iOS: `NSLocationWhenInUseUsageDescription` ไทย, ชื่อแอปไทย
- [x] T1.7 — `core/config/app_constants.dart` (limits + endpoint OSM/Nominatim/OSRM) ยังไม่ถูกใช้จนถึง Phase 3
- [~] T1.8 — ใช้ `core/l10n/strings.dart` (class `S`) แทน ARB ดูหัวข้อ deviation
- [x] T2.1 — `core/theme/tokens.dart` + `app_theme.dart` (สี/typography Prompt + Noto Sans Thai ผ่าน google_fonts, line-height 1.4-1.5, ไม่ fix ความสูงปุ่ม/การ์ด)
- [x] T2.2 — `core/widgets/`: AppButton (6 variants + loading), AppTextField, StateView (loading/empty/error/failure), AppCard (tone), VerifiedBadge (แบบย่อ), ConfirmDialog
- [x] T2.3 — Splash (min 1.5 วิ ตั้งค่าได้), Onboarding 3 สไลด์ข้ามได้ + first-run flag (SharedPreferences), เคารพ `disableAnimations`
- [~] T2.4 — ยังไม่ทำ (widget แผนที่/flutter_map) ไม่อยู่ใน scope ที่ orchestrator สั่ง Phase 1-2 ครั้งนี้ ดู open items
- [x] T2.5 — `HomeShell` (NavigationBar 5 แท็บ label แสดงตลอด) + placeholder ของ home/nearby/chats/trips/me (หน้า /me มีออกจากระบบ + ConfirmDialog)
- [x] T2.6 — `core/router/redirect.dart` (`computeRedirect` pure, ทดสอบแล้ว) ผูกกับ auth จริงเลย (ไม่ใช่ stub): config -> booting/splash -> onboarding -> sign-in -> verify-email -> setup/profile -> home
- [x] T3.4/T3.5 (ส่วน client เท่านั้น) + T4.28 — sign-up (ชื่อ, อีเมล, รหัสผ่าน >= 8, checkbox 18+ และยอมรับนโยบาย/ข้อกำหนด, ปุ่มปิดจนกว่าครบ, error ใต้ช่องอีเมล/รหัสผ่าน, banner เครือข่าย), sign-in (ข้อความทั่วไปเดียว ล้างเฉพาะรหัสผ่าน), verify-email (ส่งซ้ำ + cooldown 60 วิ, ใช้ได้ทั้งก่อน/หลังมี session), profile setup stub, `/policy` `/terms` placeholder พร้อมป้ายร่าง
- [x] Tests: 29 เทสต์ (`test/core/*`: config, error mapper, redirect; `test/features/app_flow_test.dart`: config error, onboarding, session restore, sign-in error, sign-up + 18+/consent + verify-email + cooldown, duplicate email, profile setup) — `flutter analyze` ไม่มี issue, `flutter test` ผ่านทั้งหมด

## การตัดสินใจทางเทคนิค
- Config: รองรับ key แบบใหม่ `sb_publishable_` (ไม่ใช่ JWT) นอกเหนือจาก JWT `role=anon`; `sb_secret_` และ JWT `role != anon` ถูกปฏิเสธ. URL ต้อง https ยกเว้น `ALLOW_INSECURE_LOCAL=true` + debug build
- ใช้ `Supabase.initialize(publishableKey: ...)` (`anonKey` deprecated ใน supabase_flutter 2.17; ค่า JWT anon เดิมใช้ได้)
- Session เก็บด้วย `SecureLocalStorage` (implements `LocalStorage`; iOS `first_unlock_this_device`)
- Router: `computeRedirect` เป็นฟังก์ชัน pure แยกจาก GoRouter เพื่อเทสต์; `refreshListenable` ผูกกับ auth/onboarding/profile-setup/splash providers. Sign-out = auth stream ส่ง null -> guard `go` ไป sign-in (แทน stack)
- Repository คืน `Result<T>`; `PostgrestException`/`AuthException` ไม่หลุดออกนอก data layer (`mapError` เรียกที่ repository เท่านั้น)
- ข้อความ error ที่ผู้ใช้เห็นมาจาก `failureMessage` เท่านั้น ไม่ใช้ `message` ของเซิร์ฟเวอร์; unknown `GWM_*` -> ข้อความทั่วไป
- ลำดับ guard ตาม P-4: ผู้ใช้ที่มี session แต่ `emailConfirmed=false` ถูกกักที่ `/auth/verify-email` (กันกรณีตั้ง Confirm email ปิดแล้วกลับมาเปิด)
- Profile setup done flag เป็น per-user ใน SharedPreferences (stub) เพราะยังไม่มีตาราง profile ฝั่ง client; ชื่อที่แสดงอัปเดตผ่าน `auth.updateUser(data.display_name)`
- Signup ส่ง `display_name`, `adult_confirmed: true`, `policy_version` ใน `data` ตาม design-api section 5

## จุดที่ทำไม่ได้ตาม spec 100% (ถ้ามี)
- ไม่มีที่ต้องให้ PM ตัดสิน. ส่วนเบี่ยงเบนเชิงเทคนิค (ไม่เปลี่ยน scope requirement):
  - T1.8: ใช้ Dart constants (`S`) แทน ARB/gen-l10n — แยกข้อความจากตรรกะแล้ว ย้ายเป็น ARB ทีหลังได้ทางกล (P1)
  - Thai fonts: ใช้ `google_fonts` (โหลดตอนรันไทม์) ยังไม่ bundle เป็น asset ตามข้อเสนอแนะ spec 1.2 — เปิดแอปครั้งแรกตอนออฟไลน์จะ fallback เป็นฟอนต์ระบบ
  - `VerifiedBadge` ทำแค่ variant verified/unverified ยังไม่มี org/phone/mock และ sheet อธิบาย

## Open items / สิ่งที่ต้องทำต่อ
- ตรวจ build บนเครื่องจริง/emulator: เครื่องนี้ไม่มี Android SDK (`flutter build apk` ไม่ผ่านขั้นตรวจ SDK) และไม่ได้รัน iOS; ตรวจได้แค่ `flutter analyze` + `flutter test`. ยังไม่ได้ทดสอบกับ Supabase จริง (auth flow ทดสอบด้วย fake repository)
- Email verification link: ยังไม่ตั้ง deep link/redirect URL กลับเข้าแอป (ผู้ใช้กดยืนยันในเบราว์เซอร์แล้วกลับมาเข้าสู่ระบบเอง ตามปุ่ม "ยืนยันแล้ว เข้าสู่ระบบ"). ควรกำหนด scheme + Redirect URLs ใน Supabase ใน Phase 3/4
- Supabase Auth ต้องตั้ง Confirm email = ON และ custom SMTP (T5.10); ถ้า Confirm email ปิด signUp จะได้ session ทันทีและ guard พา ไป /setup/profile
- T2.4 (AppMap + flutter_map + attribution) และ C-5 OfflineBanner, C-6..C-30 ส่วนที่เหลือ ทำใน Phase 3-4 ตามหน้าจอที่ใช้
- `/policy` `/terms` เป็นข้อความตัวอย่าง รอฝ่ายกฎหมาย; `policy_version` = `0.1-draft` ต้องตรงกับที่ trigger ฝั่ง DB ยอมรับ (T3.19)
- Forgot password (S-06, P1) ยังไม่ทำ; ลิงก์ในหน้า sign-in ยังไม่แสดง
- ตาราง `profiles`/emergency contacts ผูกกับ profile setup แทน stub เมื่อทำ T3.x
- Android debug กับ Supabase local (http) ต้องเปิด cleartext เอง
- README ครั้งแรกอยู่ที่ `README.md`

## ประวัติการแก้บั๊ก (ถ้ามี)
- ยังไม่มี (ยังไม่ผ่าน QA)

---

## Phase 3 (Flutter: profile, geo services, create trip, nearby, matches)

### Task ที่ implement แล้ว
- [x] T2.4 AppMap — `lib/core/map/app_map.dart` (flutter_map + OSM tiles, UA package, attribution "© OpenStreetMap contributors" แตะเปิดลิงก์, การ์ด fallback เมื่อ tile error >= 4 + ลองใหม่, ปุ่มซูม/ตำแหน่งฉัน, วงบริเวณแทนหมุดของผู้อื่น)
- [x] T3.9 Nominatim — `features/geo/data/nominatim_geocoding.dart` (throttle 1.1s, LRU 200 + TTL 24h, cache "ไม่พบ" 10 นาที, UA, timeout 6s, retry 1 ครั้ง, 429/403 cooldown ตาม Retry-After, circuit breaker, reverse cache พิกัด 4 ตำแหน่ง)
- [x] T3.10 OSRM — `osrm_routing.dart` (foot host แยก, driving สำหรับ car/taxi/transit, LRU 50/30 นาที, simplify <= 500 จุด, NoRoute = ROUTE_NOT_FOUND ไม่ retry, fail-closed)
- [x] Config สลับ endpoint ได้ — `core/config/service_config.dart` (`--dart-define` NOMINATIM_BASE_URL, OSRM_BASE_URL_FOOT/CAR, TILE_URL, GEO_USER_AGENT)
- [x] T3.7 (บางส่วน) Profile — `ProfileRepository` + `currentProfileProvider`/`profileGateProvider`; guard อ่านจาก `profiles.display_name` (ลบ local flag แล้ว); หน้า setup จริง + `/me/edit`
- [x] T4.1-T4.3 สร้างทริป 3 ขั้น (`features/trip/presentation/create_trip_step{1,2,3}_screen.dart`): ค้นหา (>=3 ตัว, debounce 800ms, กดค้นหาบนคีย์บอร์ด), ปักหมุด, ตำแหน่งปัจจุบัน (rationale + `record_consent('location')` ก่อนขอสิทธิ์; ปฏิเสธแล้วยังใช้ได้), เวลา (ตอนนี้/กำหนด ไม่ย้อนอดีต ป้ายพรุ่งนี้), โหมดเดียว, preview OSRM, insert พร้อม geometry EWKT + UUID ฝั่ง client (สร้างใหม่ทุกครั้งที่แก้ฟอร์ม), retry แล้ว verify-then-success
- [x] T3.14/T4.4/T4.6 Home (แผนที่ + คนใกล้เคียง 3 คน), Nearby (แผนที่วงบริเวณ + รายการเรียงคะแนน + pull-to-refresh, throttle 10 วิ), รายละเอียดผู้สมัคร, ส่งคำขอ (bottom sheet, in-flight guard, retry + resolve `GWM_ALREADY_*` ด้วยการอ่าน match ซ้ำ), กล่องคำขอ (เข้า/ที่ส่ง), รายการ+รายละเอียดการจับคู่, จุดนัดพบเสนอ/ยืนยัน (T4.29), ยกเลิกการจับคู่, Realtime `matches` -> refetch inbox + จุดแดงบนแท็บ
- [x] Migration 0002: `trips_guard` ล็อก `mode` ขณะมี match pending/accepted (คำตัดสิน PM) + เพิ่มเทสต์ใน `supabase/tests/rls_checklist.sql`
- [x] Tests: 121 ผ่าน (`flutter analyze` ไม่มี issue) — mapping ผล find_matches, throttle/LRU/retry/breaker, Nominatim/OSRM ด้วย MockClient, error mapping, trip form validation, request idempotent flow, place search debounce, widget: create-trip flow, nearby/request, requests accept/decline, meeting point, cancel
- [x] `flutter build apk --debug` สำเร็จ (`build/app/outputs/flutter-apk/app-debug.apk`)

### การตัดสินใจทางเทคนิค
- Repository interface + fake ครบ (test/support/fake_repos.dart, `Fakes` bundle ผ่าน `buildTestApp`); Supabase ถูกอ้างเฉพาะใน `*Provider` ของ data layer
- `badges` จริงจาก `user_badges()` เป็น list ของ `{kind,is_mock,org_name}` (ต่างจากตัวอย่างใน design-api §6.4 ที่เป็น map) — parser รองรับตามโค้ด SQL
- geography ที่อ่านกลับ: parser รองรับทั้ง GeoJSON และ hex EWKB (ยังไม่ยืนยันกับ PostgREST จริงว่าคืนแบบไหน)
- Guard โปรไฟล์ fail-open เมื่ออ่าน profile ไม่ได้ (server บังคับสิทธิ์จริง) และรอโปรไฟล์โหลดที่ splash
- ปักหมุดใช้ `Navigator.push` (MaterialPageRoute) แทน route `/trip/new/pick` ของ spec
- Home ใช้แผนที่บน/แผงล่างแบบสัดส่วนคงที่ แทน draggable sheet เพื่อไม่ให้บัง attribution
- แท็บ "แชท" แสดงรายการคู่ที่จับคู่แล้ว (เปลี่ยนชื่อหัวเรื่องเป็น "จับคู่แล้ว") จนกว่าจะทำแชท
- รัศมีวงบริเวณ 700 ม. ครอบ cell blur 1 กม. (`blurAreaRadiusM`)

### จุดที่ทำไม่ได้ตาม spec 100% / ค้างไว้
- ไม่มีที่ต้องให้ PM ตัดสิน. ค้าง: T3.7 รูปโปรไฟล์ + ผู้ติดต่อฉุกเฉิน (ไม่อยู่ในรายการรอบนี้); T3.6 หน้า consent เต็ม (มีเฉพาะ consent ตำแหน่ง); แชท/SOS/วงจรทริป (รอบหน้า); หน้า "ทริปของฉัน" ยังเป็น placeholder
- ยังไม่ทดสอบกับ Supabase/PostgREST จริง (migration 0002 ยังไม่เคยรันบน Postgres — T3.23) และยังไม่ได้รันแอปบนเครื่อง/emulator
- Realtime `matches` ยังไม่ทดสอบจริง; tile server สาธารณะของ OSM ต้องเปลี่ยนเป็นของตนก่อน production

---

## Demo mode (รันโดยไม่มี Supabase)

- เปิดด้วย `--dart-define=DEMO_MODE=true` เท่านั้น (`lib/demo/demo_mode.dart`, ค่าเริ่มต้น false ทุก build รวม release; ต้องระบุชัดเจนตอน build)
- แยกไว้ที่ `lib/demo/`: `demo_data.dart` (ข้อมูลตัวอย่างกรุงเทพฯ: ผู้ใช้ "มิ้นท์" ล็อกอินแล้ว, ทริปสยาม -> หมอชิต, 5 คนใกล้เคียงพร้อมพื้นที่เบลอ 1 กม. และคะแนน, คำขอ pending 1 (พลอย) + accepted 1 (ต้นไม้ พร้อมจุดนัดที่เสนอ)), `demo_fakes.dart` (fake ของ auth/profile/trip/match/geocoding/routing/location/consent แบบ in-memory มี latency 250ms), `demo_overrides.dart` (override providers + ป้าย DEMO), `demo_hub_screen.dart` (`/demo` ลิงก์ไปทุกหน้า Phase 3 + ปุ่มล้างทริป/รีเซ็ต)
- fake ใน `lib/demo` เขียนแยกจาก `test/support/*` (lib ห้าม import test) จึงไม่ได้ขยายของเทสต์ เพื่อไม่ผูก production กับโค้ดเทสต์
- Routing ในเดโมเป็นเส้นตรงมีจุดโค้ง (`demoRoute`) ไม่ใช่เส้นทางถนนจริง; Nominatim ใช้รายการสถานที่ในกรุงเทพฯ ค้นหาแบบ substring; แผนที่ยังโหลด tile จาก OSM (ออฟไลน์จะเห็นการ์ด fallback)
- จุดแตะ production มี 2 จุดเท่านั้น: `lib/main.dart` (แยก `if (demoModeEnabled)` ก่อน init Supabase) และ `extraRoutesProvider` ใน `app_router.dart` (ว่างเป็นค่าเริ่มต้น). ลบฟีเจอร์: ลบ `lib/demo/`, `test/demo/` และสองจุดนี้
- ป้าย "DEMO" อยู่กลางบนของจอ แตะเพื่อเปิด `/demo`. ต้องกด "ล้างทริปปัจจุบัน" ก่อนจึงจะเข้าหน้าสร้างทริปได้ (ผู้ใช้เดโมมีทริปที่ใช้งานอยู่แล้ว ตามกฎหนึ่งทริปต่อคน)
- เพิ่มแพลตฟอร์ม web ด้วย `flutter create . --platforms web` (โฟลเดอร์ `web/`) เพื่อ build เว็บ
- ตรวจแล้ว: `flutter analyze` ไม่มี issue, `flutter test` 125 ผ่าน (มี `test/demo/demo_test.dart`), `flutter build web --dart-define=DEMO_MODE=true` สำเร็จ, `flutter run -d web-server --web-port 8080 --dart-define=DEMO_MODE=true` ขึ้นและตอบ HTTP ได้
- ไม่ได้ถ่าย screenshot (390x844) เพราะไม่มีเครื่องมือ browser ในสภาพแวดล้อมนี้ ยังไม่ได้ดูหน้าจอจริงของเดโม ควรเปิดดูด้วยตา


---

## Phase 4 (แชท, วงจรทริป + ตำแหน่งสด, SOS/ความปลอดภัย, แชร์ทริป, PDPA)

### Task ที่ implement แล้ว
- [x] T4.7/T4.8 แชท (ฝั่ง client) - `features/chat/{domain,data,presentation}`: `ChatRepository` + `SupabaseChatRepository` (Realtime, `chat_state` RPC, history แบบ keyset, ส่งซ้ำด้วย `client_msg_id`, 23505 = สำเร็จ), `ChatState` mapping (open/blocked/trip_ended/match_closed/not_found; ค่าที่ไม่รู้จัก = อ่านอย่างเดียว), `SendThrottle` (8 ข้อความ/10 วิ, ต่ำกว่า trigger ของ DB ที่ 10/10 วิ), `ChatRoomController` (optimistic + reconcile, ส่งไม่สำเร็จแตะส่งซ้ำ, RLS deny -> อ่าน chat_state ใหม่ -> แถบอ่านอย่างเดียว, backfill ทุก 30 วิ), จุดแดงข้อความใหม่บนแท็บแชท/รายการ (lastSeen เก็บในเครื่อง)
- [x] T4.20 รายงาน/บล็อกจากแชท - เมนูในห้องแชท, `/report/:userId`, `/me/blocked` (เลิกบล็อกได้). บล็อก = แชทอ่านอย่างเดียวทันที + หยุดส่งตำแหน่งสดให้คนนั้น (P-10); การจับคู่ยังอยู่จนกดยกเลิกเอง
- [x] T4.9/T4.10/T4.12/T4.22 วงจรทริป - `TripStateMachine` (สะท้อน `trips_guard`), `TripRepository.myTrips/tripById/transition/deleteTrip` (PATCH มี guard `status in (...)`, ซ้ำแล้วเจอสถานะเป้าหมาย = สำเร็จ), แท็บ "ทริปของฉัน" (ปัจจุบัน/ประวัติ, สร้างใหม่จากทริปหมดอายุ), รายละเอียดทริป, เริ่ม/ยกเลิก (dialog บอกจำนวนคู่ที่จะได้รับแจ้ง)/ลบ, หน้าทริปกำลังเดินทาง, ArrivalPrompt (ใกล้ <= 300 ม. และเลยเวลา 30 นาที พร้อม SOS), หน้าถึงแล้ว, แบนเนอร์ทริปกำลังเดินทางบนทุกแท็บพร้อม SOS
- [x] T4.11 ตำแหน่งสด - `TripTrackingController` (ทำงานจาก `HomeShell` ทุกแท็บ), `LiveLocationSharer` (ห่างกัน >= 5 วิ, ทิ้งจุดเก่ากว่า 2 นาที, ไม่มีคิว, 403 = หยุดถาวร, GWM_RATE_LIMITED = ทิ้งเงียบ), `get_partner_live_location` poll 20 วิ แสดงบนแผนที่. ส่งเฉพาะเมื่อมีคู่ที่ accepted และ `chat_state == open`; หยุดเมื่อทริปจบ/ยกเลิก/บล็อก/ถอนความยินยอม/แอปไม่อยู่หน้าจอ (while-in-use ไม่มี foreground service)
- [x] T4.13/T4.14/T4.23 SOS - `/sos` กดค้าง 2 วิ (วงแหวนความคืบหน้า) หรือแตะยืนยัน, ปุ่ม 191/1669 ขึ้นทันทีก่อนอย่างอื่น, `SosOutbox` (คิวถาวรใน SharedPreferences, id = UUID ฝั่งแอป, upsert `on_conflict=id` ignore-duplicates, backoff 2s..60s ไม่จำกัดครั้งใน 24 ชม., flush ตอนเปิดแอป/กลับมา foreground), debounce 10 วิ ต่อทริป, ส่งข้อความ+ลิงก์ OSM ผ่าน share sheet อัตโนมัติเมื่อรู้ตำแหน่ง (หรือรู้ว่าหาไม่ได้) และปุ่ม SMS/โทรต่อรายชื่อ, ไม่มีผู้ติดต่อ = การ์ดชวนตั้งค่า (ไม่ขวาง), ไม่มีตำแหน่ง = ส่งข้อความไม่มีลิงก์พร้อมบอกเหตุผล
- [x] T4.19 (ส่วน CRUD) ผู้ติดต่อฉุกเฉิน - สูงสุด 3, ตรวจเบอร์ตาม constraint DB (`^\+?[0-9]{8,15}$` หลังตัดเว้นวรรค/ขีด), เบอร์ซ้ำ, ลบรายสุดท้ายมีคำเตือนว่า SOS จะไม่ส่งข้อความหาใคร (P-6), เก็บสำเนาในเครื่องให้ SOS อ่านตอนออฟไลน์, การ์ดเตือนบนหน้าหลังและ dialog เตือนครั้งแรกก่อนเริ่มเดินทาง ข้ามได้ (P-3), หน้า `/safety`
- [x] T4.15/T4.16 (ฝั่ง client) แชร์ทริป - snapshot ข้อความ (ชื่อ, สถานะ, ปลายทางโดยประมาณ, ETA, ลิงก์ตำแหน่งล่าสุด; ไม่มีอีเมล/เบอร์/แชท) พร้อมคำเตือนว่าเรียกคืนไม่ได้; ลิงก์ backend (`create_trip_share`/`revoke_trip_share`, รูปแบบ `https://<host>/t#<token>`) และปุ่ม "หยุดแชร์" ปรากฏเฉพาะเมื่อกำหนด `SHARE_WEB_BASE_URL` (P-5)
- [x] T4.17/T4.25(stub) PDPA/บัญชี - `/me/settings`, `/me/settings/privacy` (สวิตช์ยินยอมตำแหน่งอ่านจาก `consents` ล่าสุด, ปิดแล้วหยุดติดตามทันที, ส่งออกข้อมูล = `export_my_data` แชร์เป็น JSON), `/me/settings/delete-account` (พิมพ์ "ลบบัญชี" + dialog ยืนยัน -> `request_account_deletion` -> ล้าง SharedPreferences -> signOut ทันที ตาม P-8), `/policy` `/terms` ลิงก์จากหน้า Me/ตั้งค่า
- [x] Demo mode ครบทุกฟีเจอร์ข้างบน (ดูหัวข้อ Demo ใน README) + เทสต์ smoke ของ wiring จริง `test/demo/demo_app_smoke_test.dart`
- [x] แก้ layout: ดูหัวข้อ "layout 390 px"

### การตัดสินใจทางเทคนิค
- Realtime แชทใช้ channel เดียวทั้งแอป (`ChatRepository.incoming()`, ไม่ใส่ filter ให้ RLS กรอง) แล้วให้ห้อง/รายการกรองเอง เพื่ออยู่ในกรอบ <= 2 channel ต่อผู้ใช้ (matches + chat). ยังไม่ทดสอบกับ Realtime จริงว่า RLS กรอง `postgres_changes` ที่ไม่มี filter ตามที่คาด (ถ้าไม่ผ่านให้สลับเป็น filter ต่อ match)
- ช่วงห่าง push ตำแหน่ง = 5 วิ (`LiveLocationSharer.livePushInterval`, จุดเดียว) ตามที่ orchestrator สั่งและเท่ากับ trigger ของ DB; design-api ข้อ 8/US-12 เดิมเขียน 15-30 วิ เพื่อประหยัด free tier. **ต้องการให้ PM ยืนยัน** (ปรับค่าเดียวได้)
- ส่งตำแหน่งเฉพาะเมื่อมีคู่ accepted+เปิดอยู่ (data minimisation) ไม่ส่งเมื่อไม่มีใครเห็น; รายการคู่ที่ส่งให้ตรวจซ้ำทุก 60 วิ (ครอบคลุมกรณีอีกฝ่ายบล็อก) และทันทีเมื่อเราบล็อก
- SOS: บันทึกลงคิวในเครื่องก่อนเสมอ แล้วรอ GPS ได้สูงสุด 1.5 วิ ก่อนส่งครั้งแรก (ไม่บล็อก UI) เพื่อให้แถวแรกมีตำแหน่ง; ถ้า GPS มาช้ากว่านั้นและแถวแรกยังไม่ถูกส่ง จะอัปเดตแถวเดิม, ถ้าส่งไปแล้วจะส่งเหตุการณ์ตามหลังอีก 1 แถว (id ใหม่ + note) ให้เจ้าหน้าที่เห็นตำแหน่ง. STALE_REFERENCE (ทริปถูกลบ) = ตัด trip_id ทิ้งแล้วส่งต่อ, 403/VALIDATION = ทิ้ง, เก่ากว่า 24 ชม. = ทิ้ง
- `ExternalActions` (โทร/SMS/share/เปิดลิงก์) เป็น interface เดียว ใช้ `url_launcher` + `share_plus` (เพิ่ม dependency `share_plus`); เดโมแทนด้วยแถบข้อความ. Android manifest เพิ่ม `<queries>` สำหรับ tel/sms
- Notifier ที่ใช้ flag `_disposed` ต้องรีเซ็ตใน `build()` เพราะ Riverpod ใช้ instance เดิมเมื่อ `invalidate` (บั๊กที่เจอตอนเทสต์)
- ปุ่มเริ่มเดินทางใช้สถานะ disabled แทน spinner ระหว่าง flow (flow รอ dialog อยู่ spinner จะหมุนค้าง)
- `MatchSummary.partnerId` (ใหม่, optional) เพื่อบล็อก/รายงาน; รายการแชทเปิดห้องแชทโดยตรง, แตะหัวห้องแชทเพื่อไปหน้ารายละเอียดการจับคู่ (มีปุ่ม "เปิดแชท" ในหน้ารายละเอียดด้วย)
- ข้อความไทยของ Phase 4 อยู่ใน `core/l10n/strings_p4.dart` (`P`)

### layout 390 px (Home)
- เปิดเดโมใน Chrome headless ที่ viewport CSS กว้าง 390 จริง (ใส่ใน iframe) หน้า Home แสดงครบ 5 แท็บ ไม่ถูกตัดขอบขวา. การใช้ `--window-size=390` ตรง ๆ ทำให้ Chrome headless จัด layout กว้าง ~500 px แล้วตัดขอบขวา (แท็บ "ฉัน" หาย) จึงน่าจะเป็นต้นเหตุอาการที่เห็นถ้าใช้วิธีนั้น; **จึงไม่พบการตัดขอบบนหน้า Home จริง**
- แต่พบและแก้ overflow ขอบขวาจริงที่ `CandidateCard` (แถว วิธีเดินทาง · เวลา ไม่มี Expanded ทำให้ข้อความยาว เช่น "แท็กซี่/แอปเรียกรถ · พรุ่งนี้ 00:30" ล้น 38 px ที่ 390 px) แก้ด้วย `Expanded`; เพิ่มเทสต์ `test/features/p4/layout_390_test.dart` ตรวจทุกแท็บและหน้าใหม่ของ Phase 4 ที่ 390 px ทั้ง text scale 1.0 และ 1.4 (ไม่มี overflow/ข้อความล้นขอบ)
- ปุ่ม SOS แบบกดค้างเคย overflow ที่ฟอนต์ใหญ่ แก้ด้วย `FittedBox(scaleDown)`

### จุดที่ทำไม่ได้ตาม spec 100% / ข้อจำกัด
- ไม่มีที่ต้องส่งกลับ PM ให้ตัดสินเรื่อง scope. สิ่งที่ขอให้ยืนยัน: ช่วง push ตำแหน่ง 5 วิ (ดูด้านบน)
- share sheet ของระบบเลือกผู้รับอัตโนมัติไม่ได้ (ข้อจำกัดของ OS): SOS จึงเปิด share sheet ให้ผู้ใช้เลือก และมีปุ่ม SMS/โทรต่อรายชื่อเป็นทางลัด (ไม่ใช่ส่งอัตโนมัติ; sos-dispatch อยู่นอก MVP)
- สถานะ "บันทึกเหตุการณ์แล้ว" ของหน้า SOS อิงว่าคิวในเครื่องว่าง; เหตุการณ์ที่เซิร์ฟเวอร์ปฏิเสธถาวร (403) ถูกทิ้งและจะแสดงว่า "บันทึกแล้ว" (กรณีบั๊ก/สิทธิ์ ไม่ใช่กรณีปกติ)
- ผู้ติดต่อฉุกเฉินและคิว SOS (มีพิกัด) เก็บใน SharedPreferences แบบไม่เข้ารหัส (ต้องอ่านได้ตอนออฟไลน์); ล้างเมื่อลบบัญชี. ถ้าต้องการเข้ารหัสให้ย้ายไป `flutter_secure_storage`
- ชื่อผู้ใช้ที่ถูกบล็อกอาจอ่านไม่ได้ (RLS ของ profiles) จะแสดง "ผู้ใช้ที่ถูกบล็อก"
- ไม่ทำ: T4.21 แก้ไขทริป, T4.24 หน้าเว็บผู้รับลิงก์, T4.26 ฟีดแบ็ก, T4.27 push, รูปโปรไฟล์/หน้า verification (T3.7/S-29), forgot password. หน้า consent แยกเฉพาะไม่ได้ทำ: ใช้ dialog ขอความยินยอมตำแหน่งเดิม (`obtainCurrentLocation`/`ensureTrackingReady`) + สวิตช์ในหน้าความเป็นส่วนตัว + นโยบาย/ข้อกำหนด
- ยังไม่ได้ทดสอบกับ Supabase/Realtime จริง (migration 0001/0002 ยังไม่เคยรันบน Postgres จริง T3.23): `chat_state`, RLS ของ `trip_locations` (ต้องมี consent), `get_partner_live_location`, `sos_events` upsert `on_conflict=id`, `create_trip_share`. ยังไม่ได้ทดสอบ SMS/โทร/share sheet และตำแหน่งสด (geolocator stream) บนเครื่องจริง
- Screenshot: ถ่ายได้เฉพาะหน้า Home ผ่าน Chrome headless (หน้าอื่นต้องนำทางด้วยการแตะ ซึ่งทำอัตโนมัติไม่ได้ในสภาพแวดล้อมนี้); หน้าอื่นตรวจด้วยเทสต์ layout และเทสต์ smoke ของเดโม

### ผลตรวจ
- `flutter analyze`: No issues found
- `flutter test`: 285 ผ่าน (Phase 4 เพิ่มประมาณ 160: `test/features/p4/{domain,sos,chat,lifecycle,safety_account,layout_390}_test.dart`, `test/demo/{demo_p4,demo_app_smoke}_test.dart`)
- `flutter build web --dart-define=DEMO_MODE=true`: สำเร็จ
- `flutter build apk --debug`: สำเร็จ (`build/app/outputs/flutter-apk/app-debug.apk`; ตอนนี้เครื่องนี้มี Android SDK แล้ว)

## QA round 1 fixes (รอบ 1, T5.11-T5.18)

### Task ที่ทำแล้ว
- [x] T5.11 BUG-3 — `supabase/migrations/0003_qa_round1.sql`: `handle_new_user` RAISE `GWM_ADULT_REQUIRED`/`GWM_CONSENT_REQUIRED`; เวลา/consent มาจาก `now()` ของ server ไม่อ่านจาก metadata; config `policy.current_version`; revoke `UPDATE(adult_confirmed_at)` และ `INSERT` consents จาก authenticated. Dart: `mapError` แปลง "Database error saving new user" เป็น `GWM_SIGNUP_REQUIREMENTS` -> ข้อความไทย; signup ส่ง `adult_confirmed`/`policy_version` ผ่าน metadata อยู่แล้ว (`supabase_auth_repository.dart`). `trips_guard` คงไว้
- [x] T5.12 BUG-1 — `request_account_deletion` ตั้ง `auth.users.banned_until` +100 ปี และลบ `auth.sessions` ใน RPC เดียว (ล้มเหลว = rollback ทั้งการลบ, fail-closed). ชั้น client: หลัง `signIn` อ่าน `profiles` ถ้าอ่านสำเร็จแต่ว่าง (profile ที่ลบถูกซ่อนโดย RLS) -> signOut + `GWM_ACCOUNT_DELETED`; error `user_banned` map เป็นข้อความเดียวกัน
- [x] T5.13 BUG-6 — Me tab อ่านจาก `verifications` (`ProfileRepository.myBadges`, `myBadgesProvider`, `parseOwnBadges`); ไม่มีข้อมูล = "ยังไม่ยืนยันตัวตน"
- [x] T5.14 BUG-10 — `match_candidates` กรอง `depart_at > now() - trip.expire_after_min` ทั้งผู้สมัครและทริปผู้ขอ
- [x] T5.15 BUG-8 — `supabase/tests/qa_round1.sql` (signup/grant, deletion, formula, expiry edge, blur, org domain); ปรับ `rls_checklist.sql` (`mkuser` สร้างผู้ใช้ valid แล้วลบ 18+/consent ด้วย superuser เพราะ trigger ปฏิเสธ signup ไม่ครบแล้ว); `.github/workflows/ci.yml` (job flutter: analyze+test; job sql-tests: `supabase start` + psql ทั้งสองไฟล์). Dart: `test/features/qa_round1_test.dart`. ไม่มีตรรกะโดเมนองค์กรฝั่ง Dart (อยู่ใน SQL `sync_user_verifications`) จึงเทสต์ฝั่ง Dart เฉพาะ parse/label/การแสดงป้าย
- [x] T5.16 BUG-7 (ลด scope) — `lib/core/widgets/initials_avatar.dart` (`AvatarInitial`, re-export จาก `matching_widgets.dart`) ใช้ใน Me tab, setup profile, รายการ/หน้าจับคู่, แชท; ไม่มีปุ่มอัปโหลดรูปใน UI. อักษรแรก = grapheme cluster แรก ("มิ้นท์" -> "มิ้")
- [x] T5.17 BUG-4/5 — `AppConstants.livePushInterval([secs])` (clamp 15-30 วิ, จุดเดียว), `LiveLocationSharer.livePushInterval` = 15 วิ, fix แรกส่งทันที, DB guard 5 วิไม่แตะ, push ล้มเหลวไม่หยุด sharer. แก้เทสต์ที่ล็อกค่า 5 วิเดิม (`domain_test.dart`, `contract_and_safety_test.dart`, `lifecycle_test.dart`)
- [x] T5.18 BUG-9 — `qa_round1_test.dart` กลุ่ม sign-out/back stack: back ซ้ำหลังออกจากระบบไม่เห็น home; route ที่ต้อง login ถูก redirect ไป sign-in
- ไม่ทำตามคำสั่ง: P1 (T3.27 อัปโหลดรูป, T5.19 export), OfflineBanner (T5.20)

### การตัดสินใจทางเทคนิค
- ทำ ban/revoke ใน SQL (ไม่ใช้ Edge Function) เพราะ `purge_expired_data` เขียน `auth.users` จาก SQL อยู่แล้วและเป็น transaction เดียว = fail-closed; ไม่ลบ `auth.refresh_tokens` ตรง ๆ (ชนิด `user_id` ต่างตามเวอร์ชัน GoTrue, cast ผิดจะทำให้การลบล้มทั้งก้อน) แต่ลบ `auth.sessions` ซึ่ง cascade. ทางสำรอง Edge Function อยู่ใน `supabase/README.md`
- access token ที่ออกไปแล้วใช้ได้จนหมดอายุ (ปกติ 1 ชม.) แต่ข้อมูลถูกยกเลิก/ซ่อนแล้วและ client signOut ทันที; อีเมลเดิมสมัครใหม่ไม่ได้จนกว่า purge (30 วัน)
- trigger ใหม่ปฏิเสธทุก insert `auth.users` ที่ไม่มี metadata (รวม OAuth/anonymous/admin); MVP ใช้ email+password เท่านั้น; `seed.sql` ปรับ `policy_version` เป็น `0.1-draft`
- `policy.current_version` ต้องตรงกับ `AppConstants.policyVersion` ('0.1-draft')

### ข้อจำกัด / ยังไม่ได้ยืนยัน
- SQL ทั้งหมด (0003, `qa_round1.sql`, `rls_checklist.sql` ที่แก้) ยังไม่เคยรันบน Postgres จริง (เครื่องนี้ไม่มี psql/supabase CLI) — CI job `sql-tests` คือการรันจริงครั้งแรก คาดว่าต้องแก้เล็กน้อย
- ต้องยืนยันบน Supabase จริง: ban ทำให้ sign-in ล้มเหลวและ refresh ใช้ไม่ได้ (T5.12), ข้อความ error ของ GoTrue เมื่อ trigger ล้ม
- requirements ยังต้องให้ BA อัปตามรายการใน tasks.md (ไม่ได้แก้เอง)

## Fix NEW-1 / NEW-2 (round 3)
- NEW-1: SupabaseAuthRepository.signIn now selects `id, deleted_at`; empty row OR non-null deleted_at -> signOut + accountDeleted (helper `isDeletedProfileRows`). profiles_select policy does not filter deleted_at, so the old RLS-hides assumption test in test/qa/round2_contract_test.dart was replaced with a check on the client query plus a unit test of the helper. SQL unchanged.
- NEW-2: fixed stale `live.push_interval_sec` comments (app_constants.dart, live_location.dart); it is a Dart constant.

---

## Driver/Rider roles (Dart) — รอบ 3, T6.9-T6.17, T6.24, T6.18b

### Task ที่ implement แล้ว
- [x] T6.9 Domain — `TripRole` + `carSeats = 1` + `tripsCompatible` (กระจก rule ฝั่ง server) ใน `trip/domain/trip.dart`; `Trip.role`/`TripDraft.role`; `TripFormValidator.validateOptions(role, hasVehicle)` (`roleMissing`/`vehicleMissing`); `features/vehicle/domain/vehicle.dart` (`Vehicle`, `VehicleInput`, `VehicleValidator` 15/60/30, `VehicleView` = get_match_vehicle, `VehicleRepository`, `safeReturnTo`); `MatchCandidate.role`; `MatchSummary` + `myRole/partnerRole/boardedAt/autoClosed/partnerTripStatus` + `copyWith`; `ShareCompanion` (`sharing/domain/share_companion.dart`)
- [x] T6.10 Data — `SupabaseVehicleRepository` (`vehicles` select, `upsert_my_vehicle`, `set_vehicle_share_consent`, `delete_my_vehicle`, `get_match_vehicle`); `SupabaseMatchRepository`: `_cols` + `boarded_at,auto_closed,driver_trip_id,rider_trip_id`, role จาก `driver_trip_id/rider_trip_id` เทียบ trip ของเรา, `partnerTripStatus` จาก `get_trip_card.status`, `proposeMeetingPoint` -> `Result<bool>`, `markBoarded` (retry <= 1), `reportRiderNoShow` (resolve-by-refetch); `createTrip` ส่ง `role`; `ServiceConfig.pickupMaxDeviationM` (=500, `--dart-define=PICKUP_MAX_DEVIATION_M`); error map 11 GWM_* ใหม่ + `GWM_MATCH_LIMIT` = "คุณมีคู่ร่วมทางแล้ว" + `GWM_PENDING_LIMIT` = `match.pending_cap` (ไม่ใส่ตัวเลข เพราะค่า max อยู่ที่ server)
- [x] T6.11 สร้างทริป — `RolePicker` (C-31) ในขั้น 2 (ไม่มีค่าเริ่มต้น, เปลี่ยนไปโหมดอื่นล้าง role, Driver ไม่มีรถ -> การ์ด + ปุ่ม "กรอกข้อมูลรถ" -> `/me/vehicle?returnTo=/trip/new/options`, ร่างทริปอยู่ใน `tripFormProvider` จึงไม่หาย), ขั้น 3 แถว "บทบาท" + snackbar ตาม role + ปุ่ม "กลับไปแก้" เมื่อ server ปฏิเสธ role/vehicle. ตารางโหมดเปลี่ยนเป็นแถวละ 2 การ์ดแบบ `IntrinsicHeight` (การ์ดรถมี sublabel "ขับเอง หรือขอติดรถ"; ความสูงไม่ตายตัว)
- [x] T6.12 `/me/vehicle` (`vehicle_screen.dart`): ฟอร์ม + ชิปสี + PrivacyNotice (เหนือปุ่มบันทึก) + `ShareConsentSwitch` (ปิดเป็นค่าเริ่มต้น, ไม่ผูกกับบันทึก, สลับ = เรียก server แล้วค่อยเปลี่ยน, ล้มเหลว = ค่าเดิม + ข้อความ, ปิด = ข้อความถอนความยินยอม, เลือกก่อนมีรถ = เก็บไว้แล้ว apply หลังบันทึก, apply ไม่สำเร็จ = "บันทึกข้อมูลรถแล้ว แต่ตั้งค่า... ไม่สำเร็จ"), dialog ทิ้งข้อมูล, ยืนยันก่อนแก้เมื่อมีคู่, ปุ่มลบ disabled + เหตุผลเมื่อมีทริปคนขับ active/มีคู่ (Q-6); แถว "ข้อมูลรถของฉัน" ใน `/me`
- [x] T6.13 ค้นหา/คำขอ — `CandidateCard`: `RoleRow` (ป้าย + "รับได้ 1 คน"), ข้อความซ้อนตามทิศทาง, CTA "ขอติดรถ"/"ชวนขึ้นรถ", "ข้อมูลรถจะแสดงหลังคนขับตอบรับ" (การ์ดคนขับ), sheet ส่งคำขอตาม role; Nearby: หัวรายการตาม role, empty state ตาม role, การ์ด "คุณมีคู่ร่วมทางแล้ว" (ทริป car ที่มี accepted), legacy car ไม่มี role = StateView อธิบาย (ไม่เรียก find_matches), กรองซ้ำด้วย `filterCandidates`; Requests: ป้ายบทบาทผู้ส่ง, dialog ตอบรับตาม role, สถานะ "คำขอนี้ปิดแล้ว" เป็นกลาง; peer ยังไม่มี dialog เพิ่ม
- [x] T6.14 หน้า match (car): ป้ายบทบาทคู่, `VehicleInfoCard` (Rider; ไฮไลต์ "เพิ่งจับคู่" < 60 นาที) + `ShareConsentStatus`, Driver เห็น preview + ลิงก์แก้ไข, `PickupPointCard` (none / รอ / เสนอโดยอีกฝ่าย / ตกลงแล้ว / อ่านอย่างเดียว), `TripProgressRow`, แจ้ง "คนขับยังไม่เริ่มและเลยเวลา", `MatchEndNotice` เป็นกลาง, ยกเลิกการจับคู่ (dialog ตาม role ระบุว่าทริปกลับเข้าค้นหา Q-4; หายหลัง boarded), ข้อมูลรถยังแสดงหลัง match สิ้นสุดถ้า boarded (Q-2) ไม่เช่นนั้น "ข้อมูลรถไม่แสดงแล้ว"; `/matches/:id/pickup` (`PickupScreen` ห่อ `PickPointScreen` ที่เพิ่ม `route/confirmLabel/note/onPicked`); ห้องแชท: `RoleRow` + แถว "ดูข้อมูลรถ" พับได้ (Rider) + แถวจุดรับ + ข้อความระบบเป็นกลางใหม่ (`system.match_cancelled[_in_trip]`, `system.boarded`, `system.vehicle_updated`)
- [x] T6.15 แชร์/SOS — `buildTripShareText(companion)` / `buildSosMessage(extraLines)`; Rider: ชื่อคนขับเสมอ + ทะเบียนเมื่อ `share_allowed`; Driver: ทะเบียนตนเอง + ชื่อคนนั่ง (ไม่มีรุ่น/สี); บรรทัดตัวอย่างในหน้าแชร์ (`share-preview-line`) และใต้ปุ่มยืนยัน SOS (`sos-preview-line`); ก่อนส่งแชร์อ่านสถานะสดอีกครั้ง ถ้าข้อความจะต่างจากตัวอย่าง = ไม่ส่ง + snackbar ให้ดูตัวอย่างใหม่ (Q-10); โหลดสถานะไม่ได้ = ส่งชื่อคนขับอย่างเดียว ไม่ขวาง SOS; ไม่ส่ง `vehicle_snapshot` จาก client (server เติม)
- [x] T6.16 ทริปกำลังเดินทาง — `RiderBoardingSection`/`BoardingButton` (ปิด + เหตุผลเป็นข้อความ, confirm, สถานะ "ขึ้นรถแล้วเมื่อ hh:mm", ข้อความหยุดแชร์ตำแหน่ง), `DriverRiderStatusSection` (สถานะ + "คนนั่งไม่มาตามนัด" แบบ Text danger ห่างปุ่ม "ถึงแล้ว" 16 dp + confirm; หลัง no-show ขึ้น "การจับคู่สิ้นสุดแล้ว คุณเดินทางต่อได้ตามปกติ"), การ์ดรถกะทัดรัด/จุดรับที่ตกลง (Rider), "คนขับถึงที่หมายแล้ว" เมื่อ match จบหลัง boarded (derive), หมุดคนนั่งหายและ "ผู้โดยสารอยู่ในรถแล้ว" ฝั่ง Driver; **ตำแหน่งสด**: `livePushPartnersProvider` ตัด match ที่ Rider boarded (ยังเห็นตำแหน่งคนขับ; ถ้ามีลิงก์แชร์ backend ที่ active ยังส่งต่อสำหรับลิงก์ตาม design-roles §2); ConsentSheet "คู่ที่จับคู่แล้วเห็นตำแหน่งสดของคุณ" ก่อนเริ่มทริป car ที่มีคู่ (ครั้งเดียวต่ออุปกรณ์, `car_live_consent_seen`); Driver ที่ยังไม่ตกลงจุดรับเห็นคำเตือนไม่ขวาง (เปิดแชท/เริ่มเลย); ทริป: แถวบทบาทพร้อมไอคอนกุญแจ "เปลี่ยนไม่ได้", `TripCard` มีป้ายบทบาท + "จับคู่แล้ว 1/1" (Driver; peer ยัง x/3), Driver ยกเลิกทริปไม่ได้หลัง boarded (ข้อความเหตุผล; dialog หนักกว่าระหว่างเดินทางก่อน boarded; ทริปอีกฝ่ายไม่ถูกยกเลิก), ปุ่ม "ยกเลิกทริปแล้วสร้างใหม่" สำหรับ legacy car
- [x] T6.17 Demo — `DemoScenario {peer, driver, rider}` (`demo_data.dart`), `DemoMatchRepository` บังคับกติกาเดียวกับ backend (accept ปิดคำขออื่น = auto_closed, 1 accepted ต่อทริป, cancel หลัง boarded, boarding ต้องทั้งสองเริ่ม, Rider เปิด proposal ไม่ได้, no-show เฉพาะ Driver, boolean เบี่ยงเส้นทาง), `DemoVehicleRepository`, `DemoTripRepository` (role + Driver ยกเลิกหลัง boarded ไม่ได้), hub `/demo` หัวข้อ "บทบาท": สลับ peer/คนขับ/คนนั่ง, สวิตช์ทะเบียนฝั่งคนขับ, จำลองอีกฝ่ายเริ่มเดินทาง/เสนอจุดรับ/ขึ้นรถ/ยกเลิก, ล้างข้อมูลรถ
- [x] T6.24 — `MatchAlertController` (`matching_providers.dart`) ฟัง `inboxProvider` (Realtime `matches` เดิม) ระดับแอปผ่าน `MatchAlertHost` ใน `MaterialApp.router(builder)` -> แบนเนอร์ (SOS / แชร์ทริป / ถึงแล้ว / ยกเลิกทริปของฉัน / รับทราบ, ไม่หายเอง) เมื่อ accepted match ของ Rider จบขณะทริป in_progress และ **ยังไม่ boarded**; ไม่เตือนเมื่อเรายกเลิกเอง (`suppress`) หรือเราจบ/ยกเลิกทริป (`quiet`) หรือฝั่ง Driver; กลับเข้าแอป (`appForegroundProvider` false -> true) = invalidate inbox ทันที; `LocalNotifier` (`core/notify/local_notifier.dart`, `DebugLocalNotifier` เป็น default, payload = kind อย่างเดียว ข้อความคงที่ไม่มีทะเบียน/ชื่อ/ตำแหน่ง)
- [x] T6.18b Tests (443 ผ่านทั้งชุด, เพิ่มประมาณ 130): `test/features/roles/{roles_domain,roles_widgets,roles_match_flow,roles_layout}_test.dart`, `test/demo/demo_roles_test.dart`; ปรับเทสต์เดิม 3 จุดให้ตรงกติกาใหม่ (`trip_form_test`, `trip_flow_test` ต้องเลือก role เมื่อเลือก car, `contract_and_safety_test` อ่านทุก migration 0001-0006 ไม่ใช่แค่ 0001-0002 เพื่อตรวจ RPC / GWM_ ของ 0006)
- ไม่ได้แตะ `supabase/` และไม่ได้ apply อะไรกับ remote

### การตัดสินใจทางเทคนิค
- ข้อความแชร์/SOS แบบ plain-text ประกอบฝั่ง client จาก `get_match_vehicle.share_allowed` + ทะเบียนที่ server ส่งมา (ไม่มี RPC ที่คืนข้อความสำเร็จรูป; share sheet ของ OS ส่งได้แค่ข้อความที่แอปประกอบ). ลิงก์ backend และ `sos_events.vehicle_snapshot` server เป็นผู้ตัดสินเอง. T6.15 บรรทัด "ไม่ประกอบทะเบียนที่ client" จึงทำได้เฉพาะส่วนที่ server สร้าง payload
- `shareCompanionProvider` อ่าน repository ตรง (ไม่ผ่าน `matchVehicleProvider` ที่ cache) เพื่อให้การตรวจซ้ำตอนกดส่งเป็นการอ่านสดจริง
- ข้อความแชร์/SOS ของ Driver = ทะเบียนอย่างเดียว ตามคำตัดสิน PM ข้อ 1 (spec R.4 `share.preview_driver` เขียน "ทะเบียน รุ่น สี" ขัดกัน จึงใช้ "ทะเบียนรถของคุณ และชื่อคนนั่ง")
- จุดรับ: UI ให้แก้ได้จนกว่า **ทริปใดทริปหนึ่งเริ่ม** ตาม F-R5.6 (server อนุญาตจนถึง boarded); Rider ตอบรับพร้อมจุดไม่มีช่องในแอป (คำตัดสินข้อ 5)
- คำเตือนจุดรับไกลเส้นทาง: Rider ได้ boolean หลังบันทึก (dialog "เลือกจุดอื่น" / "เสนอจุดนี้ต่อไป" ไม่บล็อก ไม่แสดงระยะ); Driver เห็นระยะเมตรก่อนส่งจากเส้นทางของตัวเอง (`distanceToRouteM`) และส่งต่อได้เสมอ
- Alert ทำเป็น overlay ระดับแอป (ไม่ใช่ modal sheet) เพื่อไม่ต้องพึ่ง Navigator context; ทางลัดใช้ `GoRouter.push`
- ตำแหน่งสด: แยก "คู่ที่เปิดอยู่" (`sharingPartnersProvider` ใช้ดูตำแหน่งคู่) จาก "คู่ที่เราส่งตำแหน่งให้" (`livePushPartnersProvider`) เพราะ Rider หลัง boarded ต้องหยุดส่งแต่ยังเห็นคนขับ
- ป้ายบทบาททุกจุดเป็นไอคอน + ข้อความ; ทะเบียนเป็น `Text` จริง อ่านทีละตัวอักษร (Semantics) และไม่ปรากฏในรายการแชท/การแจ้งเตือน
- เทสต์ layout เจอว่าต้องใช้ `Flexible` กับ `Row` ที่ข้อความอาจกว้างเมื่อฟอนต์ทดสอบ (Ahem) และตัวเลือกโหมดต้องไม่ fix ความสูง (แก้แล้ว)

### จุดที่ทำไม่ได้ตาม spec 100% / ข้อจำกัด
- ไม่มีที่ต้องให้ PM ตัดสินเรื่อง scope
- ยังไม่ทดสอบกับ Supabase/Realtime จริง (0006 ยังไม่ apply, T6.18a/T6.19 ยังไม่ทำ): RLS ของ `vehicles`, Realtime `matches` ที่มีคอลัมน์ใหม่, `get_trip_card.status/role` ยืนยันไม่ได้จนกว่าจะรันบน DB local
- ตรวจชื่อกับ 0006 ตอนท้ายงาน (873 บรรทัด, ยังไม่เห็นการแก้ Q-1/Q-2 ในไฟล์ตอนตรวจ): `mark_boarded`, `report_rider_no_show`, `upsert_my_vehicle`, `set_vehicle_share_consent`, `delete_my_vehicle`, `get_match_vehicle`, `propose_meeting_point -> boolean`, `matches.boarded_at/auto_closed/driver_trip_id/rider_trip_id`, `get_trip_card.status/role`, `find_matches.role` ตรงกันหมด และเทสต์ contract จับชื่อ RPC / พารามิเตอร์ / GWM_ ที่คลาดเคลื่อนให้อัตโนมัติ. **ต้องตรวจซ้ำเมื่อ 0006 แก้เสร็จ** โดยเฉพาะรหัส error ของ "Driver ยกเลิกทริปหลัง boarded" (แอปรับ `GWM_ALREADY_BOARDED` จาก transition ของทริปแล้ว; ถ้า backend ใช้รหัสอื่นต้องเพิ่มใน `failure_messages.dart`)
- `LocalNotifier` เป็น no-op / debug log (ยังไม่เสียบ flutter_local_notifications); ไม่มี remote push ผู้ใช้ที่ปิดแอปอาจไม่เห็นการแจ้งเตือนจนเปิดแอป (Q-7, บันทึกใน README)
- ไม่ทำ (ไม่อยู่ในรายการ): หน้าแก้ไขทริป (T4.21) จึงไม่มีจุดให้แก้ role; หลายคัน / verification (P1)
- ยังไม่ได้ทดสอบ TalkBack/VoiceOver จริง (ใส่ Semantics ตาม R.6 แล้ว) และไม่ได้ดูหน้าจอด้วยตาในเบราว์เซอร์

### ผลตรวจ
- `flutter analyze`: No issues found
- `flutter test`: 443 ผ่านทั้งหมด
- `flutter build web --dart-define=DEMO_MODE=true`: สำเร็จ
- `flutter build apk --debug`: สำเร็จ (`build/app/outputs/flutter-apk/app-debug.apk`)


---

## Dual role (Dart) — รอบ 4 (T8.6–T8.12, T8.14)

### Task ที่ implement แล้ว
- [x] T8.6 Domain — `lib/features/roles/domain/role_state.dart`: `ActiveRole`, `DriverRegistration` (parse `get_my_role_state` แบบป้องกัน: driver โดยไม่ลงทะเบียน = rider), `DriverRegistrationValidator` (ใช้ `VehicleValidator` เดิม + ต้องติ๊กรับรอง), `resolveTripRole` (role เริ่มต้น + `roleTouched`), `RoleSwitchState` (idle/switching/failed), `reconcileRole`, `UnregisterBlock`, `driverDeclarationVersion = 'd1-draft'` (ตรงกับ `driver.declaration_version` ใน 0008)
- [x] T8.7 Data — `data/supabase_role_repository.dart` (RPC ล้วน: `register_driver(p_plate,p_model,p_colour,p_declaration_version)`, `unregister_driver`, `set_active_role`, `get_my_role_state`; ไม่ retry กับ `set_active_role` เพื่อแจ้งออฟไลน์ทันที), `presentation/role_providers.dart` (`RoleController`: แคช active role ต่อบัญชีใน SharedPreferences `gwm.activeRole.<uid>`, reconcile ตอนเปิดแอป/resume, คิวซิงก์การสลับเป็น Rider ตอนออฟไลน์ `gwm.roleSync.<uid>`, one-shot notice); ข้อความไทยของ GWM ใหม่ 7 ตัว (+ `GWM_DRIVER_UNREG_BLOCKED` ตาม tasks.md) ใน `failure_messages.dart`; copy ทั้งหมดอยู่ `core/l10n/strings_dual.dart` (class `D`)
- [x] T8.8 หน้าลงทะเบียน `/me/driver/register` (`driver_register_screen.dart`): notice 3 บรรทัด, เติมรถเดิม + banner, checkbox ไม่ติ๊กไว้, ปุ่มส่งปิดพร้อมเหตุผลเป็นข้อความ, ปุ่มปิดปิดระหว่างรอ, ยืนยันก่อนออกเมื่อมีข้อมูล, สำเร็จ = เสนอสลับ (ไม่สลับเอง), returnTo allow-list (`/me`, `/trip/new/options`, `/home`), ลงทะเบียนแล้วเข้าหน้านี้ = redirect ไป `/me/vehicle`; `role_cards.dart`: `DriverRegisterCard`, `MyRolesCard`, `UnregisterDialog`, `BlockedReasonSheet`; `/me/vehicle` ปรับ (ไม่ลงทะเบียน + ไม่มีรถ -> ไปหน้าลงทะเบียน; ยกเลิกแล้วแต่ยังมีรถ = มุมมอง retained + "ลงทะเบียนอีกครั้ง" + ลบได้; ลงทะเบียนอยู่ = ลบไม่ได้ แสดงเหตุผลพร้อมทางไปยกเลิกลงทะเบียน)
- [x] T8.9 `RoleStrip` (`role_strip.dart`) ใต้แอปบาร์ของ 5 แท็บ (helper `withRoleStrip`), `RoleModeBadge` ไอคอน + ข้อความ, ปุ่มสลับ 1 แตะ (`performRoleSwitch` ใช้ร่วมกับ Me tab/หน้าสำเร็จ), snackbar ตามกรณี (รวมข้อความ "ทริปที่มีอยู่ยังเป็นทริป...เหมือนเดิม"), Semantics, จัดเรียงแนวตั้งเมื่อ text scale >= 1.3; Me tab แสดงบทบาท + การ์ดตามสถานะ
- [x] T8.10 สองธีม — `core/theme/tone.dart` (`ToneColors` เป็น `ThemeExtension` + `context.tone` + `contrastRatio`), `app_theme.dart` (`themeForTone`; `buildAppTheme` = rider เดิม), `app.dart` เลือกธีมตาม `appToneProvider` (`theme`/`darkTheme`/`themeMode`, cross-fade 200 ms, reduce-motion = ทันที), `core/theme/tone_scope.dart` (`ToneScope`) + `features/trip/presentation/trip_tone.dart` (`TripRoleTone.trip/match/active`) ห่อใน router ทุกหน้า trip-bound (รายละเอียด/กำลังเดินทาง/ถึงแล้ว/แชร์/จับคู่/จุดรับ/แชท/ผู้สมัคร/คำขอ/SOS); ย้าย `AppColors` ที่ hardcode (~150 จุดใน widget) เป็น `context.tone.*`, `AppButton`/`AppCard`/`StateView`/`ConfirmDialog` ตามโทน, `RoleBadge` สีคงที่ (amber/mint + navy + ขอบ), SOS แดงเดิม + วงขอบขาวในโทนคนขับ, เส้นทางแผนที่ตาม role ของทริป (`AppMap.routeTone`; คนขับ amber + casing navy), TripCard/ActiveTripBanner/TripContextBar (`/nearby`) เป็นเกาะโทนของทริป
- [x] T8.11 ฟอร์มสร้างทริป: `TripFormState.roleTouched`, `setRole` (ผู้ใช้เลือก) / `setDefaultRole` (ค่าเริ่มต้น), ขั้น 2 ตั้ง role จาก active role + ฟอร์มใช้โทน/ป้าย "ทริปนี้: ..." ตาม role ที่เลือก, `RolePicker` ล็อก "ฉันขับรถ" เมื่อไม่ลงทะเบียน + `DriverGateCard` ในหน้า + ไปลงทะเบียนแล้วกลับ (draft อยู่ใน provider), ขั้น 3 มีแถว "บทบาทของทริปนี้: ..." ใหญ่ + จัดการ `GWM_NOT_A_DRIVER` (refresh สถานะ + ปุ่มลงทะเบียน); ทริปของฉันแสดง role ต่อทริปอยู่แล้ว (รอบ 3) และตอนนี้เป็นเกาะโทนของทริป
- [x] T8.12 Demo — `lib/demo/demo_fakes_roles.dart` (`DemoRoleRepository` บังคับกติกาเดียวกับ server: สลับคนขับต้องลงทะเบียน, ยกเลิกถูกปฏิเสธเมื่อมีทริปคนขับ/จับคู่คนขับที่ตอบรับ, ลงทะเบียนสร้างรถ, รถคงอยู่หลังยกเลิก), `DemoVehicleRepository.deleteMine` -> `GWM_DRIVER_REGISTERED`, hub มีหัวข้อใหม่ (คนนั่งล้วน/สองบทบาท/ยกเลิกจากอุปกรณ์อื่น/ออฟไลน์/server ปฏิเสธ), `DemoScenario` ตั้งสถานะลงทะเบียนให้ตรง (rider = ยังไม่ลงทะเบียน, driver = ลงทะเบียน + โหมดคนขับ); `demo_overrides.dart` ต่อ `roleRepositoryProvider`
- [x] T8.14 Tests: `test/features/dual/{role_domain,role_controller,tone_contrast,dual_widgets,profiles_columns}_test.dart`, `test/demo/demo_dual_test.dart`, `test/support/fake_repos_roles.dart` (ต่อเข้า `Fakes`/`buildTestApp`). ทั้งชุด **576 ผ่าน** (เดิม 443, เพิ่ม 133). Test เดิมที่ปรับเพราะพฤติกรรมเปลี่ยนโดยตั้งใจ (3 ข้อใน `roles_widgets_test.dart`): role เริ่มต้นตามโหมด (เดิม "ไม่มีค่าเริ่มต้น"), เปลี่ยนวิธีเดินทางกลับมา car = ค่าเริ่มต้นใหม่, ลบรถได้เมื่อยังไม่ลงทะเบียนเท่านั้น

### การตัดสินใจทางเทคนิค
- **`profiles` ไม่เคยถูก `select('*')`**: ทุก query ใน lib ระบุคอลัมน์อยู่แล้ว (`supabase_profile_repository` `id,display_name,avatar_path`; `supabase_auth_repository` `id, deleted_at`; `supabase_safety_repositories` `id,display_name`); สถานะบทบาทอ่านผ่าน `get_my_role_state` เท่านั้น; มีเทสต์สแกนซอร์สกันถอยหลังตามรายการคอลัมน์ใน grant ของ 0008 (`profiles_columns_test.dart`)
- **Q-D1 = A (พื้นเข้มทั้งหน้า)** เป็นข้อยกเว้นของ "Light เท่านั้น" เฉพาะโทนคนขับ ทำผ่าน `MaterialApp.theme` (rider) + `darkTheme` (driver) + `themeMode` ผูกกับ active role (ไม่ตาม brightness ของระบบ) เพื่อได้ `AnimatedTheme` cross-fade ฟรี; หน้า trip-bound ห่อ `Theme` ซ้อน (ไม่ animate)
- **Q-D3 = ซ่อนปุ่ม "เปิดโหมดคนขับ"** ถาวร: บัญชีไม่ลงทะเบียนเห็นแค่ป้าย; ทางลงทะเบียนคือแท็บ "ฉัน" และตัวเลือก role ในฟอร์มสร้างทริป (`showDriverGateSheet` ยังอยู่ในโค้ดแต่ไม่มีทางเข้าจาก UI ตามคำตัดสินนี้ เก็บไว้เผื่อทางเข้าในอนาคต)
- **Q-D5 server-last-write**: สลับเป็น Rider = เปลี่ยนทันทีในเครื่อง + ส่ง server; ถ้าล้มเหลวเก็บ flag ซิงก์ไว้ (คงอยู่ข้ามการปิดแอป) แล้ว `refresh()` (เปิดแอป/resume) ส่งก่อนอ่านสถานะ ค่าที่ server ตอบกลับเป็นค่าสุดท้าย
- **ไม่มี RPC ตรวจล่วงหน้าของการยกเลิกลงทะเบียน**: spec D-5 ให้แถวหมุนระหว่าง "ให้ server ตรวจเงื่อนไข" แต่ `unregister_driver` ตรวจและทำในคำสั่งเดียว จึงตรวจล่วงหน้าจากข้อมูลในเครื่อง (`activeTripProvider` + `inboxProvider` รีเฟรชก่อน) แล้วแสดงเหตุผลทันที; ถ้าไม่ตรงกับ server ก็ตัดสินตอน submit (dialog เปลี่ยนเป็นเหตุผลตาม D-10 blocked-at-submit)
- ไอคอน "พวงมาลัย" ไม่มีใน Material Icons: ใช้ `Icons.drive_eta` (คนขับ) คู่ `Icons.event_seat` (คนนั่ง) ที่ `TripRole` ใช้อยู่แล้ว
- Badge ตัวเลขสีแดงบน bottom nav โทนคนขับ ไม่ได้ใส่วงขอบขาว 1.5 dp (Material `Badge` ไม่มี border ในตัว; แดง #C53030 บน navy 3.15:1 ผ่านเฉียด); T8.12b: อ่านค่า reduce-motion (`disableAnimations`) ตอน build ของ `GoWithMeApp` ยังไม่ตามการเปลี่ยนค่าระหว่างใช้งาน
- ฉบับร่างฟอร์มลงทะเบียนไม่เก็บลงดิสก์และไม่ข้ามหน้า (หน้าเดียว มี dialog ยืนยันก่อนออก); draft ของฟอร์มสร้างทริปคงอยู่เพราะอยู่ใน `tripFormProvider` ที่ไม่ dispose
- ถ้า `driverDeclarationVersion` ในแอปต่างจาก server (ฝ่ายกฎหมายเปลี่ยน) `register_driver` ตอบ `GWM_DECLARATION_VERSION_STALE` -> ข้อความ "อัปเดตแอป"; ต้อง bump ค่านี้พร้อมข้อความ `D.decl`
- ข้อควรระวังเวลาเขียนเทสต์ demo: `Future.delayed` ของ demo fake ต้อง pump (ห้าม await ตรง ๆ ใน `testWidgets`) และ snackbar ที่ค้าง (4 วินาที) บังปุ่มล่างสุดของ bottom sheet/ปุ่ม "ถัดไป"
- ระหว่างส่งลงทะเบียน controller รายงาน registered=true ก่อนหน้าจอได้ผลลัพธ์ จึงต้องกัน redirect "ลงทะเบียนแล้ว -> /me/vehicle" ด้วย `_submitting` (บั๊กที่เจอจากเทสต์ demo)

### จุดที่ทำไม่ได้ตาม spec 100% / ข้อจำกัด
- ไม่มีที่ต้องให้ PM ตัดสินเรื่อง scope
- ยังไม่ทดสอบกับ Supabase จริง: `0008` ยังไม่ apply (อีก agent กำลังสรุป) ชื่อ RPC/พารามิเตอร์ตรวจกับไฟล์ 0008 ปัจจุบันด้วย `test/qa/contract_and_safety_test.dart` (ผ่าน); ถ้า 0008 เปลี่ยนต้องตรวจซ้ำ
- (แก้แล้วใน 0008 §13) ทะเบียนรถขยายเป็น 25 ตัวอักษรทั้ง client (`VehicleLimits.plateMax`) และ server (CHECK + upsert_my_vehicle + register_driver)
- RoleStrip อยู่ใต้ AppBar ในเนื้อหาของแท็บ (ไม่ใช่ส่วนหนึ่งของ AppBar) ปักติดบนสุดของเนื้อหา และสูงขยายตาม text scale ได้ไม่ overflow
- ยังไม่ได้ทดสอบ TalkBack/VoiceOver จริง และไม่ได้ดูหน้าจอด้วยตา/golden ในเบราว์เซอร์ (มี contrast test อัตโนมัติทั้งสองชุด token และ widget test ที่ text scale 2.0)
- สถานะบทบาทรีเฟรชตอนเปิดแอป/resume/ทำสลับ เท่านั้น ไม่ subscribe Realtime ของ `profiles` (ตามข้อห้ามใน T8.15)

### ผลตรวจ
- `flutter analyze`: No issues found
- `flutter test`: 576 ผ่านทั้งหมด
- `flutter build web --dart-define=DEMO_MODE=true`: สำเร็จ
- `flutter build apk --debug`: สำเร็จ (`build/app/outputs/flutter-apk/app-debug.apk`)

---

## Round 5 (Dart) — corridor UI, avatars, live map, navigation, reviews, logo (R5.9-R5.17, R5.21-R5.24, R5.27)

Coded against `docs/design-roles.md` §12 and re-checked against `supabase/migrations/0009_corridor_matching_avatars_ratings.sql` (final re-check: contract tests read the file itself, all green). Nothing was applied to any remote project; `supabase/` untouched.

### Task ที่ implement แล้ว
- [x] R5.9 Avatar picker/resizer — `lib/features/avatar/domain/avatar_processing.dart` (decode, EXIF orientation baked, centre square, <= 512 px, JPEG q80 -> 70/60/50/40 until <= 300 KB, hard cap 512 KB, alpha flattened on white, new image = no metadata; refuses < 256 px, non-image, HEIC (unsupported message), > 25 MB input; runs in `compute`). Picker = `image_picker` (`avatar_providers.dart`), web uses the browser file dialog.
- [x] R5.10 Avatar repo + `UserAvatar` — `avatar/data/supabase_avatar_repository.dart`, `avatar_service.dart` (cache 90 s < signed URL 120 s, "none" cached 30 s, evict on state change), `user_avatar.dart` (skeleton, 3 s give-up, initials fallback, semantics). Photo only for accepted matches (or ended-after-boarding) via `partnerAvatarProvider`; search/pending never call it.
- [x] R5.11 Photo page S-35 `/me/photo` (+ privacy sheet once per device via prefs `avatar_notice_seen`, source sheet, progress + cancel, remove with confirm), E-3 viewer sheet with "report this photo", S-41 `/report/photo/:userId`. Entry points: Me tab avatar + row, /me/edit avatar.
- [x] R5.12/R5.13/R5.15/R5.24 Live map S-37 `/matches/:id/live` — `trip/presentation/live_map_screen.dart`, `live_map_widgets.dart`, logic in `trip/domain/live_map_logic.dart` (HeadingTracker >= 15 m, PositionInterpolator 1 s ease-in-out, no extrapolation, > 2 km / reduce-motion jump, stale > 45 s, `EtaService` 1 routing call / 45 s per target with straight-line fallback and route geometry drawn as the route to the next target, `buildLiveMarkers` = the only place markers are decided). Follow / recenter pill / fit-both / zoom in-out, text-alternative sheet, peer card with avatar + chat + one nav button + boarding + "ถึงแล้ว". Route guard: not accepted or my trip not in progress -> back to the match page with a neutral snackbar.
- [x] R5.14 Navigation — `trip/domain/navigation_links.dart` (`navButtonState`, `mapLink`, `availableMapApps`), `trip/presentation/navigate_button.dart` (first-use notice, chooser, safety line, failure snackbar with web fallback). Shown on active trip, match page and live map. URLs carry only the target coordinate.
- [x] R5.16 Corridor copy — `R5.matchRuleExplain`, "ทางเดียวกัน ~N%" (`R.overlap*View` reworded), detour line per viewer (`detourText`), `MatchCandidate.approxDetourM`.
- [x] R5.17 Logo — `tool/make_logo.py`, `assets/branding/` (+ README), iOS/Android/web icon sets, `AppLogo` on splash/onboarding/sign-in/sign-up.
- [x] R5.21/R5.25 Reviews (P1) — `lib/features/reviews/` : StarRatingInput, tags by reviewed role, comment <= 200, blind explanation, S-39/S-40, prompt sheet once after arriving + `ReviewPromptCard` on the arrived page and match page, `/me/reviews` (received + report), `RatingSummary` (only >= 3 revealed reviews; otherwise nothing is drawn).
- [x] R5.22 No-match hint — `get_match_hint` via `MatchFinderRepository.matchHint`, `NoMatchHint` under the empty search state (one sentence, retry with 10 s cooldown, "check destination"), silent on error / has_results.
- [x] Z-2 quick replies — chat chip "ตกลงจุดลงผ่านแชท" (car matches only) fills the text box with a ready sentence; nothing is auto-sent.
- [x] Demo fakes for all of it (`lib/demo/demo_fakes_r5.dart`, `DemoLiveLocationRepository` 15 s steps + "signal lost" switch, hub section "รอบ 5", demo picker feeds the real resize pipeline).
- [x] R5.27 tests — see "ผลตรวจ".

### การตัดสินใจทางเทคนิค
- Stale label wording: `< 60 s` = "อัปเดตเมื่อ N วินาทีที่แล้ว", up to 10 min = "... N นาทีที่แล้ว", later "ตำแหน่งล่าสุดเมื่อ HH:mm" (design-spec + the brief combined).
- Partner position polled every 15 s (was 20) to match the sender cadence; interpolation happens on the display side only.
- Crop UI (S-36) replaced by an automatic centre-square crop (see limits); result is shown at once on S-35 and can be redone.
- `get_partner_avatar_path` returns a path; the client signs it (`createSignedUrl(path, 120)`), so the Storage SELECT policy is what really authorises the file.
- `submit_review`'s server errors get their own Thai texts (`reviewSubmitErrorText`); neutral screen (no explanation about the other side) when not eligible.
- Navigation uses https URLs for all three targets (Google Maps URL opens the app when installed; Apple Maps URL on Apple platforms; OSM directions as the web fallback) so no `LSApplicationQueriesSchemes`/`<queries>` changes were needed. Availability is not probed ("only apps detected" from the design was simplified to platform rules).
- Contract test now also pins: exact param names of the 10 new RPCs, `approx_detour_m` column, hint values == Dart enum (and `time_window` absent), review tag seed == `reviewTagsFor`, `report_reason` values used, avatar path/bucket/mime/size, signed URL <= 300 s, no direct `.from('reviews')`.
- New deps: `image_picker`, `image` (pure Dart resize/JPEG). iOS `Info.plist` got camera/photo usage strings (Thai). Android needs nothing (system picker/intents).
- Existing tests touched: `app_flow_test` (sign-up fields moved below the new logo: `ensureVisible`), everything else unchanged.

### จุดที่ทำไม่ได้ตาม spec 100% / ข้อจำกัด (ไม่ต้องให้ PM ตัดสิน scope)
- **S-36 circular cropper (drag / pinch / rotate / zoom buttons) not built**: automatic centre crop instead. Photos where the face is off-centre get cropped badly. Follow-up task if PM wants the full editor.
- **Rating on search cards not possible**: `find_matches` returns no user id (privacy) and `get_user_rating` takes a user id, so `RatingSummary` appears on the match page and request cards (partner id known) but not on `/nearby` cards. Needs a backend column if PM wants it there.
- Review prompt card on `/trips` list not added (arrived page, match page and the once-only sheet are done).
- Turn list S-38 / E-14 (P1 R5.23) not done. US-25 (vehicle photo) deferred by PM (D8). P2 route layer toggle (R5.26) not done.
- Heading-up mode, "reduce motion" uses `MediaQuery.disableAnimations` only.
- Android monochrome (themed) icon layer missing (needs designer silhouette). Native launch screens still Flutter default.
- Logo: crop looks good (no off-white, corners clean) but the master is the 770 px crop upscaled to 1024, slightly soft; the adaptive/maskable background is a synthetic extension of the artwork, faint tone difference around the skyline band. A full-bleed 1024 from the designer would be better. Checked by eye on the master, mark, adaptive under circle/squircle/rounded masks and small sizes.
- Not run against a real backend (0009 not applied). Web tile/OSRM/real GPS behaviours untested; live map verified with fakes + demo. No TalkBack/VoiceOver run.
- `flutter build web` output is the DEMO build (build/web) as requested.

### ผลตรวจ
- `flutter analyze`: No issues found
- `flutter test`: 677 ผ่านทั้งหมด (รอบ 5 ใหม่ ~100: `test/features/round5/*`, `test/qa/round5_contract_test.dart`, `test/demo/demo_r5_test.dart`)
- `flutter build web --dart-define=DEMO_MODE=true`: สำเร็จ
- `flutter build apk --debug`: สำเร็จ (`build/app/outputs/flutter-apk/app-debug.apk`)

## Round 5b (Dart: driver drop-off limit)
ตาม US-21 ฉบับสุดท้าย + `design-roles.md` §12 + `0009` (ไม่แตะ `supabase/`, ไม่ apply ที่ใด)

### Task ที่ implement แล้ว
- [x] ฟอร์มสร้างทริป (role=driver): `DropoffLimitControl` (`create_trip_widgets.dart`) แถบเลื่อน 500–5000 step 100, แสดงค่า (`formatMetres`: < 1000 = ม., ไม่งั้น กม. 1 ทศนิยม), ชิป 1000/2000/3000/5000, ค่าเริ่มต้น 2000, ข้อความอธิบาย. ส่ง `max_dropoff_m` เฉพาะ `role==driver` (`SupabaseTripRepository.createTrip`); rider/peer ไม่ส่งเลย
- [x] ล็อก: ตัวแก้ในหน้ารายละเอียดทริป (`_DropoffEditor`, ทริปคนขับที่ scheduled) read-only พร้อมเหตุผลเมื่อมีคำขอ pending/accepted (คำนวณจาก inbox); ปุ่มบันทึกเรียก `TripRepository.updateMaxDropoff` (ใหม่) — ถ้า server ตอบ GWM_TRIP_HAS_MATCHES/GWM_TRIP_STARTED จะแสดงข้อความไทย
- [x] `find_matches`: `MatchCandidate` ตรงคอลัมน์ 0009; ลบ `approxDetourM`, เพิ่ม `maxDropoffM`, `approxDest` เป็น nullable (แถวไม่ถูกทิ้งเมื่อ dest = NULL); แผนที่รายละเอียดผู้สมัครไม่วาดพื้นที่ปลายทางเมื่อ null; การ์ดแสดง "คนขับรับส่งได้ไม่เกิน X จากปลายทางของเขา"
- [x] `get_match_hint`: enum เหลือ has_results/none_found/far_destination/far_origin + ข้อความไทย (ไม่มีตัวเลข); ลบ off_route/direction/detour
- [x] GWM: เพิ่ม GWM_DROPOFF_INVALID, GWM_DROPOFF_NOT_ALLOWED (อื่น ๆ มีอยู่แล้ว: TRIP_HAS_MATCHES, TRIP_STARTED, AVATAR_INVALID, REPORT_INVALID, REVIEW_*)
- [x] รีวิว: ตรวจ RPC contract แล้ว — `submit_review(p_match_id,p_stars,p_tags text[],p_comment)`, `get_my_review_state`, `get_reviews_received` ยังคืน `my_tags`/`tags` เป็น text[] (server รวมจาก `review_selected_tags`) จึงไม่ต้องแก้ Dart data layer
- [x] Demo: `demoCarCandidates` กรองตามลิมิตคนขับ (ช่องว่างปลายทาง 800/1500/1900/2461 ม.; ผู้สมัครคนสุดท้าย 2461 ม. ปรากฏเมื่อลิมิต >= 2500 เช่น 3000), แถวคนนั่งไม่มี dest, แถวคนขับมี limit; `DemoTripRepository.updateMaxDropoff` จำลอง error ของ server
- [x] เทสต์: `test/features/trip/dropoff_limit_test.dart` (ใหม่), `round5_logic_test.dart`, `demo_r5_test.dart`, `test/qa/round5_contract_test.dart` (อ่าน 0009: ชื่อ/คอลัมน์ find_matches ครบตามลำดับ, ไม่มี approx_detour_m, ช่วง/step/default ตรงกัน, hint categories, GWM codes)

### การตัดสินใจทางเทคนิค
- ค่าคงที่และ `formatMetres`/`clampDropoff` อยู่ `lib/features/trip/domain/dropoff.dart` (re-export จาก match_models)
- การล็อกฝั่ง client เป็น UX เท่านั้น server บังคับจริง (GWM_TRIP_HAS_MATCHES)
- ข้อความอธิบายกฎในแท็บค้นหา (`matchRuleExplain`) เปลี่ยนเป็นภาษา neighbourhood

### จุดที่ทำไม่ได้ตาม spec 100%
- ไม่มี

### ผลตรวจ
- `flutter analyze`: No issues found; `flutter test`: 696 ผ่านทั้งหมด; `flutter build web --dart-define=DEMO_MODE=true` และ `flutter build apk --debug`: ดูสรุปจาก orchestrator

## Round 6 stage A+B (R6.1-R6.7, US-29..US-33, US-40, US-41)
No backend / RPC / RLS / `supabase/` change. Stage C/D (card deck, presets, one-tap card) not started.

### Task ที่ implement แล้ว
- [x] R6.1 `SwipeToConfirmSlider` — `lib/core/widgets/swipe_to_confirm_slider.dart`: 64 dp track (grows with text), 56 dp thumb, confirm at 95 % of travel, spring-back, plain tap = written hint only, busy lock, error text (alert) + back to idle, `sliderCancelled` for quiet reset, press-and-hold 1.5 s, semantics (label/hint/value, custom action "ยืนยัน: ...", screen-reader activate confirms with no dialog), Enter/Space, haptics, reduce motion, near (geofence) skin.
- [x] R6.2 slider replaces the confirm dialogs of start / boarded / arrived (in `UnifiedRideScreen`). Dialogs kept for cancel / no-show / report / SOS / delete and for start prerequisites (no-contacts nudge, car live-position notice, pickup reminder).
- [x] R6.3 micro-copy: new `lib/core/l10n/strings_r6.dart`; minimal edits `T.requestSent`, `T.acceptedTogether` (snackbar after accepting), `R.driverArrivedPickup`, `R.boardSuccess`; arrival sentence 2 variants with emoji-free screen-reader text. `P.arrivedTitle` left in place (unused by new UI).
- [x] R6.4/R6.5 `unified_ride_screen.dart` (+ `ride_widgets.dart`, `domain/ride_logic.dart`): full-screen map (logic carried over from LiveMapScreen) + `DraggableScrollableSheet` 3 levels (handle tap cycles, custom actions, system back Full->Half->Collapsed, level kept on rotation, chat text controller owned by the screen). Role x state matrix in `ridePrimaryFor`. Half: vehicle (accepted Rider only), pickup card, quick chips (fill box, never send), nav button (US-24 unchanged), text status, arrive slider. Full: details, share, SOS tile, chat, cancel/report/match links.
- [x] R6.6 SOS = `RideTopOverlay`, fixed top-right above the sheet at every level, from scheduled until my trip is over (hidden in Arrived).
- [x] R6.7 routes: `/trips/active` (`Routes.tripActiveNow`; `Routes.tripActive(id)` now returns it), `/trips/:id/active` redirects to it, `/matches/:id/live` = UnifiedRideScreen with the old guard, `/trips/:id/arrived` = Arrived state. Old `ActiveTripScreen` / `LiveMapScreen` / `ArrivedScreen` files kept, no longer routed (`OpenLiveMapButton`, `etaServiceProvider`, `etaLine` still used from live_map_screen.dart).
- [x] R6.11 geofence (`NearGate`): enter < 150 m (150 exactly = no), exit >= 180 m and >= 3 s, poor fix ignored, no fix = no highlight. On device, own pickup/destination, never gates anything, no extra GPS.
- [x] R6.12 Driver "ถึงจุดรับแล้ว": car + accepted + inProgress + before boarding; sends fixed sentence via `ChatRepository.send`, 1/min (`CooldownGate`, clock = `refreshClockProvider`), disabled with reason without agreed pickup; Rider sees it as status line + one `LocalNotifier` notice (`driverArrivedAtPickup`, fixed text).
- Arrival wording: `HomeDestinationMatcher` interface (`homeDestinationMatcherProvider`), default returns `unknown` -> "ถึงที่หมายปลอดภัย"; stage D replaces it.
- Demo: hub section "รอบ 6 (ขั้น A+B)" (link + "driver arrived" simulation); demo GPS walk already turns the slider green near the destination.

### การตัดสินใจทางเทคนิค
- Header of the sheet is a `PinnedHeaderSliver` (measured height drives the Collapsed fraction, <= 42 % at normal text, up to 70 % at scale > 1.3). `initialChildSize` is constant (changing it broke the sheet); Stack uses `StackFit.expand` (a non-positioned child made it 0x0).
- While a slider is confirming, the screen renders a frozen snapshot (`_freeze`) so the state change (inbox refresh / trip completed) does not remove the slider before its success state is shown (600 ms).
- Half/Full content is built only at that level (nothing hidden in the focus order at Collapsed). Content below the fold at Half needs a drag (DraggableScrollableSheet behaviour).
- `_Pin` map marker labels cap text scale at 1.3 (fixed-size marker boxes overflowed at 2.0).
- The automatic first fit-both no longer shows the "no partner" snackbar (it covered the slider).
- Remaining-distance text ("เหลือประมาณ") and the near/overdue prompt card were dropped (spec: no distances; near = slider highlight). Overdue keeps `P.arrivalOverdue` as one line under the slider.

### จุดที่ทำไม่ได้ตาม spec 100%
- Screen-reader announcement on entering near mode is via liveRegion/value only (no once-per-60 s throttled announce). No TalkBack/VoiceOver run.
- Perf of sheet/map drag with live updates not measured (R6.21). Sheet drag on the handle/header uses the DraggableScrollableSheet scroll path (header is inside the scroll view).
- Keyboard rule (hide slider when keyboard open and height < 600) implemented; not verified on a device.

### Tests changed on purpose (list for R6.18)
- `test/features/p4/lifecycle_test.dart`: arrive/start tests drive the slider; arrival prompt test -> slider near highlight; offline arrive message = `R6.sliderOfflineError` (new test for non-network failure keeps `P.arriveFailed`); tracking texts need Half; partner tile texts -> peer status.
- `test/features/roles/roles_match_flow_test.dart`: board tests drive slider (early release, tap, hold, semantics); driver/rider status texts need Half; `R.boardOptionalNote` no longer shown.
- `test/features/round5/round5_widgets_test.dart`: nav button tests open Half first.
- `test/demo/demo_app_smoke_test.dart`, `test/demo/demo_roles_test.dart`: unified screen keys instead of `P.activeTitle`/confirm dialog.
- New: `test/features/round6/{swipe_slider,ride_logic,unified_ride}_test.dart`, `test/support/ride_helpers.dart`; `Fakes.overrides` hook. Contract tests unchanged.

### ผลตรวจ
- `flutter analyze`: No issues found; `flutter test`: 772 passed.

## Round 6 stage C+D (R6.8-R6.10, R6.13, R6.14; US-34, US-35, US-37, US-38, US-39)
No backend / RPC / RLS / `supabase/` change.

### Task ที่ implement แล้ว
- [x] R6.8 CommuteCardDeck — `matching/presentation/commute_card_deck.dart`, `deck_controller.dart`; `NearbyTab` = ViewToggle (deck default, list = the old list kept; choice in prefs `gwm.nearbyView`, `/nearby?view=list`). Card: initials + nickname (no photo, no `Image`), badges, "ทางเดียวกัน ~N%", departure, role; Driver short "รับได้ 1 คน · ไม่เกิน X จากปลายทางของเขา" (long form stays on the detail page), privacy caption, detail link; `CardRatingSlot` = hidden hook for stage E (draws nothing without data). States: loading/error (existing StateView), empty (existing texts + `NoMatchHint`), end-of-deck summary ("ชวนไป N คน", skips never counted), cap bar. No self / duplicate / already-requested cards.
- [x] R6.9 swipe + undo — `DeckSwipeCard` (35 % / 700 dp/s, stamps icon+text, reduce motion = no rotation/animation), X / heart real buttons with semantics labels. Heart / swipe right = existing `NearbyController.request` (idempotent) at once, banner "กำลังชวน…" (undo disabled) -> "ชวนเพื่อนแล้ว! [เลิกชวน]" 5 s (8 s when `accessibleNavigation`; timer waits while the undo button has focus; reduce motion = static "เหลือ N วินาที"). Undo: re-reads the inbox; only a still-`pending` match is cancelled through the existing `inbox.cancel`; accepted/closed = polite text, nothing cancelled. Undone request is no longer pending (cap), server send throttle still counts (Thai text `R6C.throttled`). Cap error -> `R.pendingCap`, heart off + bar until my outgoing pending count drops. Rule errors (`NOT_ELIGIBLE` etc.) remove the card for good.
- [x] R6.10 Match Moment — `match_moment.dart` (`MatchMomentController`, `MatchMomentHost` above the navigator, `MatchMomentDialog`). Requester side only, once per match (prefs ids per user), needs: request seen pending/just sent on this device, now accepted, my active trip, not boarded. Both photos via existing `UserAvatar` (signed-URL rules), confetti only without reduce motion, "ทักทายนัดจุดรับ" = chat with the sentence in the box (`ChatRoomScreen.initialText`, never sent), "ดูแผนที่การเดินทาง" = `/trips/active` or match page + snackbar.
- [x] R6.13 presets — `features/presets/*`: `PresetStorage` (secure storage `gwm.presets.<uid>`; memory in tests/demo), `PresetController` (wipes all on sign-out transition; explicit `clearAll` in the Me sign-out and account deletion), screens `/me/places`, `/me/places/:kind` (privacy sheet before first save, name <= 20, start != home >= 200 m, edit/remove with confirm dialog), Me tab row. `PresetHomeDestinationMatcher` is now the default `homeDestinationMatcherProvider` (150 m, car only; no preset = unknown; Peer = generic per Q5).
- [x] R6.14 one-tap card — `QuickHomeCard` on Home (no active trip), `QuickHomeController`: fixed chips (`quickTimeOptions`, Q8) + "เวลาอื่น...", role switch = app-wide active role, Driver row (default 2000 m, adjustable, remembered), registration/vehicle gate with register CTA, active-trip check, same validators + OSRM + `createTrip` as the wizard, `max_dropoff_m` only for Driver, stable draft id for retries, then `/nearby`. Failure: Thai text + retry + "ไปตั้งทีละขั้น" (wizard prefilled). Missing/partial presets: setup card.
- Demo: hub section "รอบ 6 (ขั้น C+D)" (deck link, "partner accepts" -> Match Moment, throttle toggle, seed presets, presets page); presets in memory.

### การตัดสินใจทางเทคนิค
- Undo guard is client-side (re-read status, then cancel). `cancel_match` on the server still cancels an ACCEPTED (not boarded) match, so a tiny race remains between the re-read and the RPC.
- Banner is drawn on the deck (not a SnackBar) so the timer can pause on focus; it lives in `deckProvider` (survives a detail-page visit) but is only drawn on the deck page.
- Match Moment is requester-only (task: "after the other side accepts"); accepter keeps "ไปด้วยกันเลย!".
- Coach-mark hint is hidden at text scale > 1.3 (space for card + buttons); reduce-motion variant is the same text.
- Peer-mode arrival wording is generic even when the destination is near Home (Q5 wording).

### จุดที่ทำไม่ได้ตาม spec 100% (ส่งต่อให้ PM/db-architect)
- Server-side guard against cancelling an accepted match by undo (BA US-35 says "backend enforces"): needs a change in `cancel_match` (out of scope, no `supabase/` edits). Decision needed: add "only if pending" parameter/RPC in a later DB round.
- Undo banner is not app-level (design F-10 asked for an app snackbar host); no persistence of the window across leaving `/nearby`.
- Rating on the card (US-36) waits for stage E; only the hidden slot exists.
- Offline banner state of the deck (F.5.5) not separate: request errors show the normal Thai network message.
- Not run on a real TalkBack/VoiceOver device.

### Tests changed on purpose
- `test/support/fakes.dart`: harness opens `/nearby` in LIST view by default (`gwm.nearbyView: list`) so the older list-based widget tests keep their meaning; deck tests pass `'deck'`. Adds `Fakes.presets` (memory storage).
- `test/support/fake_repos.dart`: `FakeMatchRepository.request` now leaves a row in the inbox (undo re-reads it); `sampleCandidate(maxDropoffM:)`.
- `test/demo/demo_roles_test.dart`: rider nearby test checks the deck first, then toggles to the list.
- `nearby_tab.dart` list map 200 -> 150 px (room for the toggle at 390 px, text x1.4: existing layout test).
- New: `test/features/round6/{deck,presets,match_moment}_test.dart` (deck swipe/buttons/a11y/undo timing 5 s and 8 s/throttle/cap/after-accept refusal/list toggle/hint/390 px x1.0-2.0; presets per-user + wiped on sign-out/clearAll, time chips, matcher variants, one-tap payloads incl. Driver-only limit, registration gate, active-trip, fallback, layout; Match Moment once/close/greet/map/cancelled/requester-only) + demo hub test.

### ผลตรวจ
- `flutter analyze`: No issues found; `flutter test`: 849 passed; `flutter build web --dart-define=DEMO_MODE=true` OK; `flutter build apk --debug` OK.

## Round 6 stage E (Dart)

Migration 0010 (`supabase/migrations/0010_deck_rating_undo_guard.sql`) is the source of truth; it was being applied to the live DB by another agent while this stage landed. `supabase/` was not touched here.

- [x] R6.16 rating aggregate (US-36) — `MatchCandidate` (`domain/match_models.dart`) gained `ratingAvg`/`ratingCount` (`double?`/`int?`) parsed from the two columns `find_matches` now appends (18 total). Parsing is defensive: absent keys (older server, pre-0010), explicit `null`, out-of-range (`avg` outside 0..5) or a lone half-pair (only one of the two present, which the server should never send) all collapse to `(null, null)` via the private `_rating()` helper — never a crash, never a half-drawn line. `hasRating` convenience getter added. `withoutRequest`/`withRequestStatus` copy the two fields through.
- [x] `CardRatingSlot` (`presentation/commute_card_deck.dart`) rewritten from the stage-D hidden hook to the real widget: takes `avg`/`count`, draws nothing (`SizedBox.shrink`, no gap, no "ยังไม่มีรีวิว" text) unless both are non-null, otherwise `'★ 4.6 (5 รีวิว)'` (`R6C.ratingLine`) wrapped in `Semantics` with a full sentence label (`R6C.ratingSemantics`, `excludeSemantics: true` so the raw text node is not read twice). Wired on the deck card and, with `align: MainAxisAlignment.start`, on `CandidateDetailScreen`. Not added to the old list rows (task said optional; the list is the pre-round-6 fallback view and keeping it visually unchanged avoids widening a widget with a stable existing test suite) — flag to PM/BA if the list should get it too.
- [x] R6.9 backend guard — `MatchRepository.cancelPending(String matchId) -> Result<bool>` added to the interface (`domain/match_repository.dart`), the Supabase impl (`data/supabase_match_repositories.dart`, calls `cancel_pending_match` and maps the text result to `true` = cancelled now / `false` = `already_cancelled`), `demo/demo_fakes.dart` (mirrors the same status-machine as the SQL: not found / already cancelled / not pending / cancel) and `test/support/fake_repos.dart` (`cancelPendingCalls` list so tests can assert the deck stopped calling `cancel`, plus `frozenInbox` to simulate a stale local pre-read racing a server-side accept). `matching_providers.dart` inbox controller got a matching `cancelPending()` (suppresses the "match ended" alert for my own cancel, same as `cancel()`).
- [x] `deck_controller.dart` `undo()`: the local re-read of the inbox is kept but is now UX-only (fast "already accepted?" hint before making a network call); the actual cancel goes through `cancelPending`, never `cancel`. `GWM_MATCH_NOT_PENDING` from the RPC (the real guard: the other side answered between the pre-read and the call) is treated exactly like the local pre-read catching an accept — same `_blocked()` path, same polite copy. `already_cancelled` (`Ok(false)`) is treated as a normal successful undo (idempotent).
- [x] Thai copy — `strings_r6_cd.dart`: `undoAccepted` replaced with the BA-specified sentence "อีกฝ่ายตอบรับไปแล้ว เลิกชวนไม่ได้ แต่ยกเลิกการจับคู่ได้ที่หน้าจับคู่"; added `ratingLine`/`ratingSemantics`. `GWM_MATCH_NOT_FOUND` already had a generic Thai message in `failure_messages.dart` (unchanged) and `GWM_MATCH_NOT_PENDING` is caught before it reaches the generic mapper.
- [x] Demo fakes — `demo/demo_data.dart` `_demoRatings` gives 3 of the 5 demo candidates a rating (>=3-review threshold mirrored), the other 2 stay unrated to exercise the hidden case in the demo build.
- [x] OBS-1 cleanup — deleted `lib/features/trip/presentation/active_trip_screen.dart` (grep confirmed zero references anywhere in `lib`/`test` outside itself; it was not routed). `live_map_screen.dart` was **not** deleted: `OpenLiveMapButton` from it is still imported and used by `match_detail_screen.dart`, so it is live code, not orphaned.
- [x] "ระยะเบี่ยง" docs sweep — read every occurrence in `docs/design-spec.md`, `docs/design-roles.md`, `docs/tasks.md`. All of them already describe the boolean-only / warn-only behaviour that matches the current Dart (`proposeMeetingPoint` returns `bool`, no metre value ever reaches the client, `lib/features/matching/presentation/matching_providers.dart:175`); none claims the client shows or computes a literal distance from server data. No edits made — flagging in case this was meant to point at a different string.

### Tests changed/added in stage E
- `test/features/matching/match_models_test.dart`: new group for `rating_avg`/`rating_count` — both present, both columns absent (older server), explicit null, one-sided (dropped), numeric-string tolerance.
- `test/qa/round5_contract_test.dart`: now reads `supabase/migrations/0010_*.sql` too (`_m0010`); `find_matches` RPC/column tests moved to 0010 and updated to the 18-column list; new `cancel_pending_match` contract test (param `p_match_id`, `returns text`, granted to `authenticated`, `GWM_UNAUTHENTICATED`/`GWM_MATCH_NOT_FOUND`/`GWM_MATCH_NOT_PENDING` present in the SQL and in `failure_messages.dart`, Dart repo calls `cancel_pending_match` and the deck controller no longer calls the plain `cancel(matchId)`).
- `test/support/fake_repos.dart`: `sampleCandidate(ratingAvg:, ratingCount:)`; `FakeMatchRepository.cancelPending` + `cancelPendingCalls`/`cancelPendingFailure`/`frozenInbox`.
- `test/features/round6/deck_test.dart`: rating slot shown/hidden group; undo now asserted to call `cancel_pending_match` (`cancelPendingCalls`); idempotent `already_cancelled` still shows "เลิกชวนแล้ว"; a dedicated accepted-race test where the local pre-read still says pending but the RPC answers `GWM_MATCH_NOT_PENDING` (polite message, match stays accepted). The pre-existing "undo after the other side accepted" test (pre-read catches it) is unchanged.

### ผลตรวจ (stage E)
- `flutter analyze`: No issues found.
- `flutter test`: all 860 tests passed.
- `flutter build web --dart-define=DEMO_MODE=true`: OK.
- `flutter build apk --debug`: OK.

### จุดที่ต้องให้ PM/BA ทราบ (ไม่ใช่บั๊ก แต่เป็นทางเลือกที่ตัดสินใจเอง)
- Rating line not added to the old list-view rows (kept deck + candidate detail only, per "list view rows optional" in the task).
- "ระยะเบี่ยง" docs review found nothing to fix under the given description; left all three files untouched (see note above) in case this referred to different wording that should be pointed out explicitly.

## Round 7 stage A (Dart, DB-independent parts)

Scope: US-42 (push, the client-only half) + US-43 (road-snap). Explicitly did **not** touch `supabase/` and did not apply anything to any remote project — migrations `0011a`/`0011`/`0012` are still drafts (unverified, `/db-architect` owns them next). Everything below is coded against the RPC/enum contract in `docs/design-roles.md` §14 as documented in the SQL drafts already in the tree, not against a live database.

### Task ที่ implement แล้ว

**US-43 road-snap**
- [x] R7.11 — `lib/features/geo/data/osrm_road_snap.dart` (`OsrmRoadSnap implements RoadSnapService`): OSRM `nearest`, mirrors `OsrmRouting`'s style exactly (config-swappable `OSRM_BASE_URL_CAR`/`_FOOT`, `ServiceConfig.snapTimeout` short timeout, one retry via `retryTransient`, per-profile `CircuitBreaker`, small `LruCache`). `parseOsrmNearestResponse` is a pure function (exposed for tests) that recomputes the deviation locally via `haversineM` rather than trusting OSRM's own `distance` field. New config: `ServiceConfig.snapTimeout` (2 s default) and `ServiceConfig.snapMaxDeviationM` (`ROAD_SNAP_MAX_DEVIATION_M`, default 40 m) — independent of the existing `pickupMaxDeviationM` (500 m, off-route warning; a different mechanism that keeps working unchanged).
- [x] R7.11/12 — `lib/features/geo/presentation/pick_point_screen.dart`: added `snapMode` (nullable `TravelMode`) to `PickPointScreen`. Per **Q4** (PM decision in `tasks-round7.md`, which supersedes the design-spec-round7.md G.2.1 draft flow of snapping on every marker release), the OSRM call happens exactly **once**, inside `_confirm()` (the "เสนอจุดนี้"/"ส่งข้อเสนอจุดรับ" tap), never on drag. New `SnapMarkerState` enum (`none/snapping/snapped/rawRejected/rawFallbackError`) drives: a small floating caption ("กำลังปรับหมุดให้ตรงถนน…" while awaiting, "ปรับหมุดให้ตรงถนนแล้ว"/"ใช้ตำแหน่งที่คุณปักไว้ (ปรับให้ตรงถนนไม่ได้ตอนนี้)" for 3 s afterwards, auto-clearing `Timer`), and the marker (`_PickupMarker`): a thin ring + tiny road icon when snapped (shape-based, not colour-only, per a11y guidance), plain pin otherwise, `Semantics(liveRegion: true)` announcing the state change. A short 150-200 ms manual pan (`_animateMoveTo`, 8 steps) recentres the map on the snapped point, skipped entirely under `MediaQuery.disableAnimationsOf` (reduce motion = instant jump). Every branch (accept/reject-deviation/service-failure) is fail-open: `widget.onPicked` is always eventually called and the confirm button is never disabled by snap state. A fresh manual drag after a snap resets `SnapMarkerState` back to `none` (G.2.1 step 6). `PickupScreen` (`features/matching/presentation/pickup_screen.dart`) passes `snapMode: trip?.mode`; no own trip loaded = no snapping, never blocks proposing.
- [x] Copy — `strings_roles.dart` (`R.`): `pickupSnapping`/`pickupSnappedToast`/`pickupSnapFallbackToast`/`pickupMarkerA11ySnapped`/`pickupMarkerA11yRaw` (G.2.4), next to the existing `pickup*` strings (same file the pickup flow already uses).

**US-42 push (client-only half — sending/`push_outbox`/Edge Function drain are DB/ops, out of scope here)**
- [x] R7.3 — new `lib/features/push/` (`domain`/`data`/`presentation`, mirrors every other feature folder):
  - `domain/push_models.dart`: `PushKind` (5 opaque kinds), `DevicePlatform`, `PushMessage.fromData` (parses `RemoteMessage.data`, returns `null` on unknown/missing `kind` — drop silently, never crash). **Wire values matter**: `PushKind`'s wire strings match the DB `push_kind` enum exactly as defined in `supabase/migrations/0011_push_pindrop.sql` — `match_requested`/`match_accepted`/`chat_message`/`driver_arrived`/`match_cancelled` — **not** the informal `new_request`/`new_message` labels used in `docs/design-spec-round7.md`'s G.1.4 table (UX documentation, not the DB contract). Re-checked against §14/the SQL draft at the end of this stage per the task instruction; `register_device_token(p_token text, p_platform device_platform)` / `unregister_device_token(p_token text)` and the `device_platform` enum (`android`/`ios`/`web`) matched design-roles.md §14.6 exactly, no drift there.
  - `domain/push_repository.dart` + `data/supabase_push_repository.dart`: `PushRepository.registerToken`/`unregisterToken` call the two RPCs above through `retryTransient`/`mapError` (same pattern as `SupabaseConsentRepository`). `UnavailablePushRepository` fallback mirrors `UnavailableAuthRepository`.
  - `presentation/push_service.dart`: `PushService` abstraction (`requestPermission`/`currentPermission`/`getToken`/`onTokenRefresh`/`onForegroundMessage`/`onMessageTap`). `FirebasePushService` wraps `firebase_messaging`; `_ensureInit()` calls `Firebase.initializeApp()` guarded in try/catch (no `firebase_options.dart`/native config exists yet — every call fails soft to a neutral value: `PushPermissionStatus.unsupported`/`null`/empty streams, logged once via `Log.d`, never thrown). `NoopPushService` is the DEMO_MODE/no-plugin-at-all fallback. `currentDevicePlatform()`: Android/Web only this round (Q3: iOS/APNs deferred to P1) — returns `null` on iOS/other, and every caller already treats `platform == null` as "can't register, don't error".
  - `presentation/push_providers.dart`: `pushServiceProvider` (production default `FirebasePushService()` — **never** imports `lib/demo/` itself, per the existing architecture rule enforced by `test/qa/contract_and_safety_test.dart`'s "demo code is only referenced from main.dart and the router hook" gate; the demo swap happens entirely in `lib/demo/demo_overrides.dart`), `pushRepositoryProvider`, `pendingDeepLinkProvider` (see R7.6), and `PushController` — one plain class (not a `StateNotifier`, same style as other controllers here) doing all the register/unregister bookkeeping via 3 `SharedPreferences` keys (`push.permission_asked`, `push.master_enabled`, `push.device_token`).
  - `presentation/push_permission_sheet.dart` (**G-1**): `maybeShowPushPermissionSheet` reuses `showConfirmDialog` (C-23/C-24 pattern, same as the existing live-location consent in `trip_flows.dart`) — no new sheet component. Shown once; both "อนุญาตการแจ้งเตือน" and "ไว้ทีหลัง" mark it decided (`PushController.markAsked`).
  - `presentation/notification_settings_screen.dart` (**G-2**, `/me/settings/notifications`): OS permission status row + single master `SwitchListTile` (Q-G1: no per-kind toggle — schema has no per-kind column) + read-only list of the 5 event kinds. Turning the master off unregisters this device's token immediately; turning it on re-opens G-1 if the OS was never asked. "ไปที่ตั้งค่าเครื่อง" is a snackbar placeholder, not a real deep link into OS settings — no `permission_handler`/`app_settings` package is in the project and none is cached offline; flagging as a known P2 gap rather than adding a new native dependency speculatively.
  - `presentation/notification_tap_handler.dart` (**G-3**): `routeForPushMessage` is a pure function, kind -> one of the *existing* routes (`Routes.nearbyRequests`/`Routes.match`/`Routes.live`/`Routes.chat`) — no new guard added, reusing each destination's own existing "gone/expired" handling (`PickupScreen`'s `pickupMatchGone`, `MatchDetailScreen`'s not-found state, etc.) exactly as the design spec asked. Returns `null` (drop silently) when the payload is missing the id its kind needs. `handlePushTap`: signed-in -> `router.go(path)` (replaces the stack, same as the round-6 deep link); signed out -> stashes the path in `pendingDeepLinkProvider` and goes to `/auth/sign-in`.
  - `presentation/push_copy.dart`: `pushKindText(PushKind)` — the single Thai-copy source of truth (`R.push*` strings), used by both the real tap flow and the demo foreground-banner simulation.
  - `presentation/push_tap_host.dart`: `PushTapHost`, sits in `app.dart`'s `builder` alongside `MatchAlertHost`/`MatchMomentHost`. Subscribes to `onMessageTap`/`onForegroundMessage` once; shows a small dismissible in-app banner (G.1.5, "แตะ push ขณะแอปเปิดอยู่หน้าอื่น") that navigates the same way when tapped. On `authUserProvider` transitioning from signed-out to signed-in: silently calls `ensureRegisteredIfEnabled()` and offers G-1 once. **Important fix made partway through this stage**: the G-1 dialog must be shown via `widget.router.routerDelegate.navigatorKey.currentContext` (same trick `match_moment.dart` already uses), not `PushTapHost`'s own `BuildContext` — that context sits *above* the router's `Navigator` (this host wraps the whole `MaterialApp.router`), so `showDialog` from it throws "no Navigator" at runtime.
- [x] R7.4 (Q1) — sign-out (`me_tab.dart`) and delete-account (`privacy/presentation/account_screens.dart`) both call `pushControllerProvider.unregisterThisDevice()` right before the existing sign-out/prefs-clear step — only this device's token, per PM decision Q1 (other signed-in devices keep receiving push).
- [x] R7.5 — Thai copy for all 5 kinds lives only in `strings_roles.dart` (`R.push*`), rendered client-side via `pushKindText`; the payload itself never carries text (opaque `kind` + one id, matching `PushMessage`'s shape and design-roles.md §14.4/14.7).
- [x] R7.6 — deep-link routing + "stale session" resume: `pendingDeepLinkProvider` (a `StateProvider<String?>`) is consumed exactly once inside `routerProvider`'s `redirect` callback in `app_router.dart` — right when the normal guard chain (`computeRedirect`) would otherwise send a freshly-signed-in user to `/home`, it's redirected to the stashed path instead and the provider is cleared. Reuses the existing `returnTo` idea from D.9 without a second guard mechanism; doesn't touch `computeRedirect` itself (kept pure/testable), the interception is a thin wrapper around its result.
- [x] R7.10 (stub mode) — the demo fakes below double as the "no real FCM" CI-testable path; `PushMessage.fromData`/`routeForPushMessage`/`pushKindText` are pure and unit-tested without any plugin/network.
- Routing: new `Routes.settingsNotifications` (`/me/settings/notifications`), registered in `app_router.dart`, row added to `SettingsScreen` (`privacy/presentation/account_screens.dart`) next to "ความเป็นส่วนตัว".
- G-1 trigger wiring: `PushTapHost` (login) and `create_trip_step3_screen.dart`'s `_afterCreate` (first successful trip creation) both call `maybeShowPushPermissionSheet` — whichever fires first wins (`everAsked` guard), matching G.1.1 step 1's "เข้าสู่ระบบครั้งแรก หรือกด 'สร้างทริป' เป็นครั้งแรก แล้วแต่ว่าอะไรถึงก่อน".
- Demo fakes — `lib/demo/demo_fakes_r7.dart` (new): `DemoPushService` (stream-backed, `simulateForeground`/`simulateTap`), `DemoPushRepository` (in-memory), `DemoRoadSnap` (`DemoSnapMode.accept/rejectDeviation/fail`, never touches the real OSRM host, same discipline as `DemoRouting`). Wired in `demo_overrides.dart`. Demo hub (`demo_hub_screen.dart`) new section "รอบ 7 (ขั้น A)": one button per `PushKind` to simulate a tap (routes to the real destination using the first demo match's id), one to simulate a foreground/in-app-banner message, and 3 buttons to switch the next road-snap outcome (accept/reject-deviation/fail) before trying the pickup screen.

### การตัดสินใจทางเทคนิค
- **Q4 (PM) overrides the design-spec-round7.md G.2.1 draft**: the draft's flow assumed a draggable marker snapping on every release; Q4 (in `tasks-round7.md`) explicitly changed this to "once, on the confirm tap" to respect OSRM's public rate limit and avoid flicker while the user is still adjusting. `PickPointScreen`'s existing architecture (a fixed centre pin, the map moves underneath — not a draggable `Marker`) actually fits the once-per-confirm model better than the draft's per-drag model, so no architecture change was needed, just the new code path inside `_confirm()`.
- `snapMaxDeviationM` (40 m default) is a **new**, separate config from `pickupMaxDeviationM` (500 m, the pre-existing off-route warning) — they answer different questions (did the snap move the pin too far from where the user actually pointed? vs. is this pickup point far from the Driver's own route?) and can both fire independently on the same point.
- `PushController` is a plain class, not a `StateNotifier`/`AsyncNotifier`: every call site already re-reads state explicitly after an action (same style as `consentRepositoryProvider`'s callers elsewhere in the app), so no reactive rebuild wiring was needed.
- `NotificationSettingsScreen`'s "ไปที่ตั้งค่าเครื่อง" button is a snackbar placeholder rather than a real OS-settings deep link: no `permission_handler`/`app_settings` dependency exists in `pubspec.yaml`/the offline pub cache, and adding one speculatively risked an offline `pub get` failure. Flagged below for PM/BA, not silently dropped.
- Added Thai messages for `GWM_DEVICE_TOKEN_INVALID` (used this stage) plus `GWM_VIBE_TAG_INVALID`/`GWM_MOOD_INVALID`/`GWM_ORG_VERIFICATION_REQUIRED`/`GWM_GENDER_REQUIRED` (Stage B/US-44/45, not used by any code yet) to `lib/core/error/failure_messages.dart`, purely to keep `test/qa/contract_and_safety_test.dart`'s "every GWM_ code raised by SQL has a Thai message" gate green — that gate scans all of `supabase/migrations/*.sql` regardless of stage, and those 4 codes already exist in the draft 0011/0012 migrations from a parallel `/db-architect` pass. The 4 Stage-B strings are placeholders (not reviewed BA copy) — flagged below.

### บั๊กพบระหว่างพัฒนา (แก้แล้วในรอบนี้เอง ไม่ใช่จุดที่ต้องส่ง PM)
- First full-suite `flutter test` run after adding `PushTapHost` to `app.dart`'s builder showed ~104 failures across a dozen unrelated pre-existing test files (`app_flow_test.dart`, `deck_test.dart`, `presets_test.dart`, `unified_ride_test.dart`, etc.) — root cause: `PushTapHost` now offers the G-1 permission sheet automatically on every "became signed in" transition, and the shared `test/support/fakes.dart` `buildTestApp()` harness signs in a fake user in most of those tests, so an unexpected `AlertDialog` popped up and blocked subsequent taps. Fixed at the harness level (`buildTestApp` now seeds `'push.permission_asked': true` by default, mirroring how `'gwm.nearbyView': 'list'` is already seeded for backward compatibility, plus overrides `pushServiceProvider`/`pushRepositoryProvider` with no-op fakes) rather than in any of the ~12 affected test files. Confirmed clean before/after: isolated re-runs of the previously-failing files all pass now, and 3 separate full-suite runs after the fix are all green (904/904).
- Same investigation also caught a real architecture violation: `push_providers.dart` originally imported `lib/demo/demo_mode.dart` to branch on `demoModeEnabled` directly (copying a comment from an early draft), which `test/qa/contract_and_safety_test.dart`'s "demo code is only referenced from main.dart and the router hook" gate exists specifically to prevent. Fixed by making `pushServiceProvider`'s production definition demo-agnostic (always `FirebasePushService()`) and letting `demo_overrides.dart` do the swap entirely, exactly like every other provider in the app.

### จุดที่ทำไม่ได้ตาม spec 100% (ส่งต่อให้ PM/BA)
- **`docs/design-spec-round7.md` G.1.4's `new_request`/`new_message` `kind` labels do not match `supabase/migrations/0011_push_pindrop.sql`'s actual `push_kind` enum** (`match_requested`/`chat_message`). Coded against the SQL (the DB contract, per the task's own instruction to treat §14/the draft SQL as authoritative and flag drift), not the UX doc's informal labels. **Needs a decision**: should the UX doc's table be corrected to match the enum (cosmetic, no behaviour change), or does BA want the *enum* renamed to match the friendlier doc labels before 0011 is ever applied (schema drift, /db-architect's call, not mine to make)? Either way both must agree before Stage A's push payload/routing is considered final — right now Dart is internally consistent with the *SQL*, not the *UX doc's kind names* (the UX doc's routing destinations per kind, deep-link behaviour, and copy intent are all still followed exactly, only the wire string differs from the doc's table header).
- G-2's OS-settings deep link is a snackbar placeholder (see decisions above) — real deep link needs a new native permission plugin, a PM/BA call on scope (and, if approved, a fresh offline-cache check before adding the dependency).
- `routeForPushMessage`'s `new_message`/`match_accepted` destinations always go to the plain `/chats/:matchId`/`/matches/:matchId` routes; the design spec's nuance ("ถ้าทริปกำลังเดินทาง -> UnifiedRideScreen ที่ระดับ Full โฟกัสช่องพิมพ์") is not wired, because no existing generic "redirect to `/trips/active` whenever my trip is ongoing" guard exists anywhere in the app to reuse (checked `redirect.dart` and the live-trip screens) — building one would be new guard logic, which the design spec explicitly said not to add for this feature. Flagging as a gap rather than inventing a new guard silently.
- The Stage-B GWM_* Thai messages added to `failure_messages.dart` (see above) are placeholders to keep a QA gate green, not reviewed copy — BA should treat them as provisional when Stage B (US-44/45) actually wires up vibe tags/mood/gender.

### Tests added
- `test/features/geo/osrm_road_snap_test.dart` — `parseOsrmNearestResponse` (pure), `OsrmRoadSnap`: cache hit, foot vs. car host/profile, one retry on a transient 503, timeout -> `networkTimeout`, 429 rate-limit (no breaker trip).
- `test/features/geo/pick_point_screen_snap_test.dart` — widget tests: transient "snapping" state (Completer-controlled fake, since a zero-delay fake resolves before a pump can observe it), accepted snap (toast + marker a11y label + moved point + toast self-clears), deviation-over-threshold (silent, raw point kept), service failure (fail-open caption, raw point kept), `snapMode: null` (never calls the snap service at all).
- `test/features/push/push_service_test.dart` — `FirebasePushService` fails soft (unsupported/null/empty streams) with no Firebase config in the test environment; `NoopPushService`; `currentDevicePlatform()`.
- `test/features/push/notification_tap_handler_test.dart` — `routeForPushMessage` per kind + missing-id (`null`, no crash); `PushMessage.fromData` (well-formed/unknown-kind/missing-kind); `pushKindText` covers all 5 kinds with distinct copy.
- `test/features/push/push_controller_test.dart` — `requestPermission`/`markAsked`/`setMasterEnabled` (on/off, with/without OS permission)/`unregisterThisDevice`/`ensureRegisteredIfEnabled`, including the "no platform" edge case.
- `test/features/push/notification_settings_screen_test.dart` — OS granted/denied states, master toggle on/off (with the actual unregister call asserted), the 5 read-only event rows.
- `test/features/push/sign_out_unregisters_token_test.dart` — full `buildTestApp` widget test: signs in, signs out from `/me`, asserts exactly the pre-seeded device token was unregistered (R7.4/Q1).
- `test/support/fakes.dart` — `buildTestApp()` now seeds `push.permission_asked: true` by default and overrides `pushServiceProvider`/`pushRepositoryProvider` with no-op fakes (see "บั๊กพบระหว่างพัฒนา" above); this is a harness change, not a behaviour change, for every pre-existing test that uses it.

### ผลตรวจ
- `flutter analyze`: No issues found.
- `flutter test`: all 904 tests passed (3 clean full-suite runs after the harness fix, plus multiple isolated re-runs of every file touched by the fix).
- `flutter build web --dart-define=DEMO_MODE=true`: OK.
- `flutter build apk --debug`: OK.
- Did not run on a real device/emulator; `FirebasePushService`'s guarded behaviour is verified only by the unit tests above (no real Firebase project exists yet for this round, per the task).

## Round 7 stage B (Dart)

Scope: US-46 (dark mode), US-44 (vibe tags/mood), US-45 (Women-Only — the institution/same-org
filter was **dropped entirely** by the user; `trips.same_org_only` stays a dead/unused column, no
Dart reads or writes it), US-48 (B: TTS quick-voice chips, fully built; A: recorded audio clips,
UI-only + gated). Coded against `docs/design-roles.md` §14 (RPC/schema contract) and
`docs/design-spec-round7.md` G-5..G-10 (institution filter parts of G-8 skipped per the task
instruction). The task's instruction stated migrations 0011a/0011/0012/0013 are **applied live**;
`supabase/` itself was not touched (per the standing rule) — the Dart/repository code below calls
the real columns/RPCs as documented, on trust of that instruction, not because this agent verified
the live DB directly.

### US-44 — Vibe tags & daily mood
- `lib/features/trip/domain/vibe_mood.dart`: `VibeTagCatalog` (driver/rider allow-lists, exact
  strings from the requirements doc), `VibeMoodValidator.validateMood` (Q6 guard: reject text over
  35 chars, an 8+ digit run, or a small blocklist word — client-side mirror only, the server is
  authoritative per design-roles). `vibeMoodExpired` is a best-effort 24h UX hint only.
- `Trip`/`TripDraft` (`lib/features/trip/domain/trip.dart`) gained `vibeTags`, `moodText`,
  `moodSetAt` (Trip only), `womenOnly`. `Trip.fromJson` parses the new `trips` columns tolerantly
  (defaults to empty/null/false so an older server row never crashes parsing).
- `TripRepository` gained `updateVibeMood`/`updateWomenOnly`; implemented in
  `SupabaseTripRepository` as direct `trips` table updates (design-roles §14.7: the 4 new columns
  are `grant insert/update`-able directly, guarded by a server-side trigger, not by an RPC) and in
  both fakes (`DemoTripRepository`, `test/support/fake_repos.dart`'s `FakeTripRepository`).
- UI: `VibeTagChipPicker`/`MoodTextField`/`TripVibeSummaryRow` (G-5/G-6/G-7) in
  `lib/features/trip/presentation/vibe_mood_widgets.dart`; wired into
  `create_trip_step2_screen.dart` (the "สไตล์การเดินทางของคุณวันนี้" block, unconditional — the
  requirements doc does not restrict it to car trips) and displayed (compact, read-only) on
  `CommuteCard` (`commute_card_deck.dart`, after the role block, before the rating slot — matches
  the spec's "does not obscure the safety block" placement) and on `candidate_detail_screen.dart`.
  **Not done for time**: the Match detail screen (S-16, post-accept) was not located/touched this
  stage — only the candidate (pre-accept) detail screen got the summary row. `MatchCandidate`
  gained tolerant `vibeTags`/`moodText` fields (`match_models.dart`) reading `vibe_tags`/`mood_text`
  off `find_matches`/`match_candidates` rows if present; per design-roles §14.6 these columns are
  **not** confirmed to be on that RPC yet (only `get_trip_card` was decided in the open questions) —
  this is written defensively (empty/null when absent) so it does nothing until/unless a DB agent
  adds those columns to the candidate-listing RPC.

### US-45 — Women-Only (institution filter dropped)
- `lib/features/profile/domain/gender.dart`: `Gender` enum (`female`/`male`/`unspecified`),
  `unlocksWomenOnly` (only `female`, per AC).
- `ProfileRepository` gained `getMyGender`/`setMyGender`/`clearMyGender`; `SupabaseProfileRepository`
  calls `get_my_gender()` RPC for reads (self-view only, design-roles §14.6) and writes
  `profiles.gender` directly (`grant update (gender)` per §14.7). Clearing relies entirely on the
  server's `profiles_gender_guard` trigger for the Q7 auto-cancel — **this client never
  reimplements that guard**, per the task instruction; it only refreshes `myGenderProvider` after.
- `GenderSettingsScreen` (G-9, `/me/settings/gender`) — self-declare/clear with the exact privacy
  copy from the spec, placed as its own settings row next to Privacy (not next to Verification,
  Q-G3).
- `SafetyFilterSwitchGroup` (G-8) is **Women-Only only** — the "same institution" row was removed
  per the task's explicit instruction (the user dropped it; `trips.same_org_only` is confirmed dead
  in the requirements doc). Disabled with an inline reason + a link to Gender settings when
  `gender != female`, per spec. Wired into `create_trip_step2_screen.dart` under the vibe/mood
  block.
- No client-side reimplementation of the AND/live-check matching logic (Q8) — that is entirely
  server-side per design-roles; the client only ever writes the boolean it wants and displays
  eligibility from `myGenderProvider`.
- **Not done for time**: no dedicated widget test for `GenderSettingsScreen`/`SafetyFilterSwitchGroup`
  beyond the pure `Gender` domain test — flagged as a gap, not silently dropped.

### US-46 — Dark mode
- `docs/design-roles.md` §G.5.4 models brightness as a second axis of `ToneScope`, independent of
  rider/driver tone. Implemented as: `ToneColors` gained a `brightness` field plus two new static
  token sets, `riderDark`/`driverDark` (exact hex values from design-spec-round7 G.5.1.1/G.5.1.2,
  including the dimmer amber driver-dark per Q-G5), and `ToneColors.resolve(tone, brightness)`.
  `buildToneTheme`/`themeForTone` (`app_theme.dart`) take an optional `brightness` param;
  `ToneScope` (`tone_scope.dart`) forwards the ambient brightness so a trip-tone override never
  silently drops back to light.
- **Important existing-code interaction**: `app.dart`'s `MaterialApp.router` already (pre-round-7)
  repurposes Flutter's `theme`/`darkTheme`/`themeMode` trio to encode **rider vs driver tone**, not
  OS brightness — that is a pre-existing hack, not something this stage introduced. Round 7 layers
  brightness *underneath* that hack instead of replacing it: `theme`/`darkTheme` are now built with
  `themeForTone(tone, brightness: effectiveBrightness)`, where `effectiveBrightness` comes from the
  new resolver below. `themeMode` itself is untouched (still purely rider/driver).
- `lib/core/theme/theme_settings.dart`: `ThemeModeSetting` (system/light/dark/autoByTime),
  `isNightByClock`/`resolveEffectiveBrightness` (pure, unit-tested — Q17: device clock only, no
  GPS/sunrise math, window is 18:00 inclusive .. 06:00 exclusive), `ThemeSettingsController`
  (Riverpod `Notifier`, persisted via `sharedPrefsProvider`, same pattern as other settings
  notifiers in this codebase).
- `ThemeSettingsScreen` (G-10, `/me/settings/theme`) — 4-way radio list, announces "กำลังใช้: ..."
  via a live region.
- `ServiceConfig` gained `tileUrlTemplateDark` (`TILE_URL_DARK` env override, default CartoDB Dark
  Matter as specified). `AppMap` picks the dark URL when `context.tone.isDark`, and draws a subtle
  white glow (`BoxShadow`) behind every `MapPin` icon in dark mode (G.5.2 marker glow/WCAG AA note).
  Route casing width (`borderStrokeWidth: rt.isDriver ? 2 : 1.5`) was **already** in the 1.5-2dp
  range pre-round-7 and needed no change; only the casing/route *colours* differ per the new dark
  tokens.
- **Not done for time**: no explicit geofence-circle-on-dark-tile contrast test beyond the golden
  token-contrast tests in `test/core/theme/theme_settings_test.dart`; the existing geofence circle
  code (`app_map.dart` `CircleLayer`) was not touched (still uses the light `AppColors.green`/`teal`
  constants, not tone-aware) — flagged as a follow-up, not a silent regression (it was already
  tone-unaware before this stage).

### US-48(B) — Quick-voice preset chips (fully built, no DB dependency)
- **Interpretation** (per the task's explicit instruction, documented here as required): a preset
  phrase is sent as a **completely normal chat message** (reuses `ChatRoomController.send`, no new
  `kind`, no new column). The receiving device recognises the exact text against the same fixed
  allow-list (`QuickVoicePresets.phrases`, `lib/features/chat/domain/quick_voice.dart`) and reads it
  aloud via on-device TTS (`flutter_tts`, added to `pubspec.yaml`) — this is why (B) needs zero
  backend work, per the requirements doc's own framing.
- `QuickVoiceThrottle` (Q16: 1 send per 10s per match) gates the **sending** UI action (a new
  "วลีเสียงด่วน" chip next to the existing quick-reply chip in `chat_room_screen.dart`); unlike the
  existing quick-reply chip (which only fills the text box), a quick-voice pick sends immediately —
  that is what the AC describes ("เมื่อกดวลี ข้อความถูกส่ง...").
  `lib/features/chat/presentation/quick_voice_providers.dart`: `QuickVoiceTtsSetting` (persisted
  on/off toggle, default **on** — the AC frames "off" as the opt-out), `maybeSpeakQuickVoice` (hook
  point), wired into `ChatRoomController._onIncoming` (chat_providers.dart) so it fires exactly once
  per genuinely-new incoming message, never for the sender's own message, never for a system row.
  `FlutterTtsSpeaker` wraps the real plugin; `demo_overrides.dart` overrides `ttsSpeakerProvider`
  with a no-op fake (no platform TTS engine exists in demo/web/CI).
- A new toggle "อ่านข้อความด่วนออกเสียง" was added to `NotificationSettingsScreen` (reusing that
  screen rather than creating a new settings page, since it's conceptually adjacent to notification
  behaviour).
- Tests: `test/features/chat/quick_voice_test.dart` (allow-list + throttle, pure), and
  `test/features/chat/quick_voice_providers_test.dart` (the speak-or-not decision matrix: preset vs
  not, self vs other, setting on/off, system message).

### US-48(A) — Recorded audio clips (UI-only, explicitly gated off)
- **DB work still needed before this can ever go live** (flagging per the task instruction, this is
  not this agent's job to build): a private storage bucket (signed URL, same shape as the avatar
  bucket) scoped to the match/trip pair, plus an extension of the existing `storage_purge_queue`
  Edge Function to drain that bucket (or accept a bucket parameter) for the 24h auto-delete. Neither
  exists yet. `docs/tasks-round7.md` R7.38/R7.39 (owner: `/db-architect`) describe exactly this.
- `lib/features/chat/domain/audio_note.dart`: `audioNoteUploadEnabled = false` is the single feature
  flag; `AudioNoteController` is a pure state machine (idle → recording → recorded/uploadDisabled)
  with a 10s hard cap, fully unit-tested (`test/features/chat/audio_note_test.dart`) without any
  real microphone access.
- `AudioNoteButton` (`lib/features/chat/presentation/audio_note_button.dart`): a real ≥56dp
  hold-to-record circular button with a Thai mic-permission explainer dialog (shown once) and a
  live mm:ss counter while "recording". **No real microphone/audio plugin was added** (no `record`/
  `permission_handler` dependency) — since the upload target does not exist yet, this stage
  simulates the timer/state-machine only; the moment `stopRecording()` fires it always lands in
  `AudioNoteState.uploadDisabled`, rendered as a clear "บันทึกเสียงยังไม่เปิดใช้งานในตอนนี้ (เร็ว ๆ นี้)"
  banner rather than attempting a network call that would fail. Wired into `chat_room_screen.dart`
  as a "บันทึกเสียงสั้น" chip opening a bottom sheet with the button.
- **Explicitly not built** (would need the packages above once the bucket exists): actual mic
  capture, waveform rendering from real audio data, upload, signed-URL playback bubble in the chat
  timeline, and the "เสียงหมดอายุแล้ว" expiry message (R7.41/R7.42) — all deferred to whichever stage
  does the DB work, per the task's own gating instruction.

### Known gaps / follow-ups (flagged, not silently dropped)
1. Match-detail (post-accept, S-16) vibe/mood display was not wired — only the pre-accept candidate
   detail screen and the deck card were.
2. `MatchCandidate.vibeTags/moodText` parsing is defensive/speculative against a `find_matches`
   column that design-roles §14.6 does not confirm exists yet — needs a DB-agent check before
   relying on it in QA.
3. Geofence-circle dark-tile contrast (`AppMap`'s `CircleLayer`) was not made tone-aware.
4. `GenderSettingsScreen`/`SafetyFilterSwitchGroup` only have the pure `Gender` domain test, no
   widget test.
5. US-48(A) needs the DB work above before it can be un-gated; nothing on the Dart side should need
   to change beyond flipping `audioNoteUploadEnabled` and wiring a real repository once that lands.

Verification this stage:
- `flutter analyze`: 0 issues (4 pre-existing-style `deprecated_member_use` infos on
  `RadioListTile`, same pattern already used elsewhere in the codebase, e.g. `avatar_screens.dart`).
- `flutter test`: all 958 tests passed (full suite, after the one fix below). One pre-existing
  assertion in `roles_widgets_test.dart` coincidentally asserted "no `TextField` anywhere on step 2"
  to mean "no seat-count input"; updated it to check for the seat-count field specifically instead
  of blanket-asserting no `TextField`, since the new (legitimate) `MoodTextField` is also a
  `TextField`. No other regressions.
- `flutter build web --dart-define=DEMO_MODE=true`: OK (`build/web`).
- `flutter build apk --debug`: OK (`build/app/outputs/flutter-apk/app-debug.apk`).
- Did not run on a real device/emulator; `flutter_tts` and the hold-to-record UI were only verified
  via `flutter analyze`/`flutter test`/the two builds above, not real speech/microphone hardware.

## Round 7 stage C (Dart)

Scope: US-49 (lateness detection & no-fault cancel), US-50 (route detour tolerance), US-47 (shared
impact & haptics). Migrations 0011a-0015 were already applied live before this stage started; all
RPCs/columns referenced below are real (`supabase/migrations/0014_lateness_detour.sql`), not draft.

### US-49 — Lateness detection & no-fault cancel
- `lib/features/trip/domain/lateness.dart`: pure, unit-tested domain logic mirroring the server's
  config defaults (`lateness.overdue_min=10`, `eta_stall_window_min=5`, `eta_stall_m=100`, Q11) —
  `isOverdueByTime` (now vs. `greatest(driver.depart_at, rider.depart_at) + 10min`), `isEtaStalled`
  (last-3-samples-in-5min straight-line distance to the meeting point not shrinking by >= 100 m),
  `checkLateness` (a OR b), and `LatenessSnooze` (client-only "wait 10 more minutes" timer — no
  RPC/schema for it, per design-roles.md §15.3's explicit "intentionally not built" note). This is a
  **hint only**: the server (`cancel_match_no_fault`, migration 0014) re-verifies both conditions
  itself from `trips.depart_at`/`trip_locations` and never trusts the client.
- `MatchRepository.cancelNoFault(matchId)` (`match_repository.dart` + `supabase_match_repositories.dart`)
  calls the `cancel_match_no_fault` RPC; idempotent (`'cancelled'`/`'already_cancelled'`, Q12
  first-write-wins, never throws on a repeat). `GWM_NOT_OVERDUE` mapped to a Thai message in
  `failure_messages.dart` ("ยังไม่เข้าเงื่อนไขล่าช้าตามที่ระบบตรวจสอบ...") — this is the "server
  double-checks, client shows the rejection gracefully" path from the task, exercised by
  `test/demo/demo_r7c_test.dart` and `test/features/matching/lateness_card_test.dart`.
- `lib/features/matching/presentation/lateness_card.dart`: the two-choice `LatenessCard`
  ("รอต่ออีก 10 นาที" / "ยกเลิกการเดินทาง (ไม่เสียประวัติ)"), a normal `AppCard` + two full-width
  `AppButton`s (screen-reader friendly by construction, no colour-only meaning).
- Wired into `UnifiedRideScreen` (`unified_ride_screen.dart`): a rolling buffer of the caller's OWN
  live-tracking fixes (`_lateSamples`, reusing the existing `tripTrackingProvider`/`_clockTimer` 5s
  tick — **no new polling was added**) feeds `checkLateness` each tick while the match is an
  accepted, not-yet-boarded car match on an in-progress trip; the card is rendered in `_body()`
  gated on `!nearArrive` so it always yields the screen to the arrive slider near the destination
  (per the AC's "การ์ดต้องหลบให้ UI สไลด์ถึงที่หมายเสมอ"). "รอต่อ" calls `LatenessSnooze.snooze()`;
  "ยกเลิก" calls `cancelNoFault` and shows either a neutral success snackbar or the graceful
  `GWM_NOT_OVERDUE` message (card stays up, no crash). The other side's notification reuses the
  EXISTING `push_outbox`/`system.match_cancelled` channel (0011/0014 trigger) — no new Dart wiring
  was needed for that half, per design-roles.md §15.3.
- Explicitly NOT touched: SOS/emergency flow (`lib/features/safety/**`) — the lateness card is a
  fully separate mechanism, verified by inspection (no shared state/widgets) rather than a new test,
  since SOS already has its own full test suite untouched by this change.

### US-50 — Route detour tolerance
- `lib/features/trip/domain/detour.dart`: client-side mirror of the `trips.detour_tolerance_m`
  bounds (200..2000 step 100, default 500 — migration 0014's `trips_detour_tolerance_guard`),
  exactly parallel to the existing `dropoff.dart` for `max_dropoff_m`.
- `Trip`/`TripDraft` (`trip.dart`), `TripFormState`/`TripFormController` (`trip_providers.dart`),
  `TripRepository.updateDetourTolerance` + `SupabaseTripRepository` (added `detour_tolerance_m` to
  the trips column list and insert/update paths, driver-only, same pattern as `max_dropoff_m`).
- UI: `DetourToleranceControl` (`create_trip_widgets.dart`) — same slider-plus-chips shape as
  `DropoffLimitControl` but a DIFFERENT label ("ระยะเบี่ยงที่ยอมรับได้เพิ่มเติม") and help text
  explaining the two-mechanism distinction per the requirements; shown ALONGSIDE (not instead of)
  `DropoffLimitControl` on `create_trip_step2_screen.dart` for a car Driver only. `trip_detail_screen.dart`
  gained a parallel `_DetourEditor`, locked while pending/accepted exactly like `_DropoffEditor`.
- **No read-side model change**: confirmed against `docs/design-roles.md` §15.5 ("`find_matches`'s
  FINAL column list... **not adding new columns**") that `match_candidates`/`find_matches`'s
  client-visible output is unchanged — the OR-with-`max_dropoff_m` predicate is evaluated entirely
  server-side (`_car_rule_eval`) and the client never sees the other side's `detour_tolerance_m` or
  the computed delta. `MatchCandidate` parsing was NOT touched.
- Demo: `demo_data.dart` gained `demoCarDetourApproxM`/`demoCarDriverDetourM` (fixed per-candidate
  numbers standing in for the real PostGIS/OSRM approximation) and `demoCarCandidates(...,
  driverDetourM: ...)` OR-filters exactly like the real `_car_rule_eval` (dest-gap-within-dropoff OR
  detour-approx-within-tolerance); `DemoMatchRepository`/`DemoTripRepository` wire the active
  driver trip's own `detourToleranceM` through automatically. Demo hub buttons ("คนขับตั้งระยะเบี่ยง
  แคบ/กว้าง") let a reviewer see the candidate list change without touching Supabase.

### US-47 — Shared impact & haptics
- `lib/features/trip/domain/shared_impact.dart`: `co2KgFor(distanceM)` = `distanceM/1000 * 0.120`,
  null when `distanceM <= 0` (hides the number rather than showing "0 kg"); `formatCo2Kg` renders
  `"~X.X kg"`.
- `lib/features/chat/domain/thank_you_sticker.dart`: a fixed 4-message allow-list, exactly mirroring
  the `QuickVoicePresets` shape added in Stage B for US-48(B) — sent through the SAME
  `ChatRepository.send(...)` path as every other quick-reply (`kind='user'`, no new message kind).
- `SharedImpactCard` + `ThankYouStickerRow` (`ride_widgets.dart`), wired into `ArrivedSummary` (the
  post-arrival-slide screen, `_SharedImpactSection`) gated on `acceptedPartnersOf(inbox,
  trip.id).firstOrNull` — nothing shown for a solo/Peer-no-partner trip or one whose match never
  reached `accepted` (cancelled-before-arrival/blocked all fall out of that same accepted-only
  check, matching the AC without needing separate blocked/cancelled-specific logic). The label
  includes the required "(โดยประมาณ)" tag plus the PM-approved one-line disclaimer footnote (Q9).
- Haptics (`swipe_to_confirm_slider.dart`, `commute_card_deck.dart`): **found that reduce-motion was
  NOT previously gating any of the existing `HapticFeedback.*` calls** in `SwipeToConfirmSlider`
  (only the spring-back/scale ANIMATIONS checked `_reduce`) — every haptic call in both files now
  checks the same `MediaQuery.disableAnimationsOf(context)` (`_reduce`) getter that already existed
  for animation gating, per the task's "reuse/extend it, do not duplicate detection logic"
  instruction. Per the AC wording, the drag-start haptic on `CommuteCardDeck`'s `DeckSwipeCard`
  stayed `selectionClick` (light), and the slider's 95%-confirm-threshold/hold/success haptics were
  changed from `mediumImpact` to `heavyImpact` (the AC explicitly asks for "heavy impact" at that
  point). `test/features/matching/haptics_reduce_motion_test.dart` intercepts the real
  `SystemChannels.platform` "HapticFeedback.vibrate" calls (not just "the setting is read") to prove
  the gating actually suppresses the platform call under reduce-motion while the confirm action
  itself keeps working.

### Tests added this stage
- `test/features/trip/lateness_test.dart` — `isOverdueByTime`/`isEtaStalled`/`checkLateness`/
  `LatenessSnooze` (overdue threshold, eta-stall trend incl. window/sample-count edge cases, snooze
  extends the window and a fresh snooze after expiry re-arms it).
- `test/features/matching/lateness_card_test.dart` — the two-choice card's callbacks, busy-disables-
  both-buttons, and the `GWM_NOT_OVERDUE` error text staying visible (graceful, not a dead end).
- `test/demo/demo_r7c_test.dart` — `DemoMatchRepository.cancelNoFault` contract (default
  `GWM_NOT_OVERDUE`, confirmed-overdue → `cancelled` → idempotent `already_cancelled`, unknown id →
  `GWM_MATCH_NOT_FOUND`, non-car match → `GWM_NOT_ELIGIBLE` even when "overdue" is forced) and US-50
  detour-tolerance bounds/step/driver-only/lock + the OR-matching logic (narrow vs wide tolerance
  changing which demo candidates appear).
- `test/features/trip/detour_tolerance_test.dart` — slider bounds/step/chips, both controls shown
  together and independent, driver-only gating, create-trip wiring, trip-detail editor + lock.
- `test/features/trip/shared_impact_test.dart` — CO2 formula/formatting/hide-at-zero,
  `SharedImpactCard` rendering (name/value/approx-label/disclaimer), `ThankYouStickerRow` sending a
  preset through the real `ChatRepository.send` (proving no new send path/message kind was created).
- `test/features/matching/haptics_reduce_motion_test.dart` — see above.
- Updated `test/support/fake_repos.dart` (`FakeTripRepository.updateDetourTolerance`,
  `FakeMatchRepository.cancelNoFault`, `sampleTrip(detourToleranceM: ...)`) so existing fixtures work
  with the two new abstract repository methods.

### Not built in this stage (out of scope per the task)
- No `supabase/` files were edited (migration 0014 was already applied live before this stage).
- No demo-mode change was needed for `find_matches`'s column list (confirmed unchanged, see above).

Verification this stage:
- `flutter analyze`: 0 new issues (same 4 pre-existing `deprecated_member_use` infos on
  `RadioListTile` as before, unrelated to this stage).
- `flutter test`: all 1003 tests passed (958 pre-existing + 45 new across the 6 files above); one
  pre-existing demo test (`demo_r5_test.dart`'s "driver limit filters rider candidates") needed a
  1-line fix to `demo_data.dart` — the new OR-with-detour filter defaulted the fallback detour value
  to `0` (not `detourDefaultM`) when a caller passes `driverLimitM` without `driverDetourM`, so a
  bare `max_dropoff_m`-only call (as that pre-existing test does) keeps its original semantics; the
  real `DemoMatchRepository.findMatches` path always passes both, so the new OR behaviour is intact
  for the actual demo flow.
- `flutter build web --dart-define=DEMO_MODE=true`: OK (`build/web`).
- `flutter build apk --debug`: OK (`build/app/outputs/flutter-apk/app-debug.apk`).

## Round 7 — precise detour + vibe/mood fix (Dart)

Scope: implement the Dart side of migration `0016_precise_detour.sql` (US-50 BUG-R7-03,
US-44 BUG-R7-01 per `docs/test-report.md`, contract in `docs/design-roles.md` §16, flow in
`docs/flow-us50-detour.md`). This ADDS the precise per-request OSRM calculation on top of the
existing `detour.dart`/`DetourToleranceControl` UI from round 7 Stage C — nothing from that stage
was replaced. `supabase/` was not edited (migration 0016 is treated as already applied per the task).

### 1. Precise (OSRM) detour calculation at request time
- `lib/features/trip/domain/precise_detour.dart` (new, pure/testable):
  - `needsDetourPath({driverDest, riderDest, effectiveDropoffLimitM})` mirrors the server's
    `_car_detour_path_used` (0016) using data the client already has: the candidate's OWN blurred
    destination (`MatchCandidate.approxDest`), my own exact destination (`Trip.dest`), and the
    server-computed effective dropoff limit (`MatchCandidate.maxDropoffM`, which already IS
    `_car_dropoff_limit(...)` — no need to duplicate that formula/config value client-side). This is
    a client-side PRE-CHECK only (decides whether to spend 3 OSRM calls); the server is the only
    authority on which path actually applied.
  - `computePreciseDetourM({routing, mode, driverOrigin, driverDest, riderDest})` calls the EXISTING
    `RoutingService` (`OsrmRouting`, the trip-creation route-preview client — NOT the US-43
    `nearest`/road-snap client) exactly 3 times: `route(A,Z)` direct, `route(A,M)`, `route(M,Z)`, and
    returns `route(A,M) + route(M,Z) - route(A,Z)` (clamped to >= 0). This exact leg structure and its
    relationship to `_car_detour_floor_m`'s `floor_m = |AM| + |MZ| - route(A,Z)` (triangle inequality
    applied twice, `route(A,Z)` being the one leg 0016 knows exactly) is documented in the file's doc
    comments AND re-asserted by `test/features/trip/precise_detour_test.dart` and
    `test/qa/round7_stage_d_contract_test.dart` so a future SQL formula change is caught on both
    sides. Returns `null` (fail-closed) if ANY of the 3 OSRM calls fails/times out.
  - **Which candidates can compute this at all**: only a car Rider requesting a car Driver candidate
    — the OSRM legs need the Driver's origin/destination, and the Rider only ever sees those as the
    SAME blurred points the candidate card already shows (server never reveals exact coordinates
    pre-match). The reverse direction (a Driver requesting a Rider candidate) can NEVER compute this
    client-side: `find_matches` never returns a Rider candidate's destination at all (privacy rule,
    unchanged by 0016), so there is no `riderDest` to route through. That direction always omits
    `p_client_detour_m`; if the detour path was the only one that would have qualified, the server
    answers `GWM_NOT_ELIGIBLE`. This is `docs/design-roles.md` §16.7's own open question — not
    resolved by this task, documented as a known limitation, not silently patched over.
  - Wired into `NearbyController.request` (`matching_providers.dart`): computes `clientDetourM`
    before calling the repository when applicable, and returns
    `Err(AppFailure(FailureCode.detourCalcFailed, retryable: true))` WITHOUT calling `request_match`
    at all when the OSRM calc fails — per the task's explicit ask, a failed calculation shows
    "ลองใหม่อีกครั้ง" rather than silently omitting the value and letting the server answer the more
    confusing `GWM_NOT_ELIGIBLE` (which reads as a permanent rule failure, not a network hiccup). The
    existing `DeckController._onInviteFailed` needed NO changes: this new `AppFailure` code is simply
    not in `_dropCodes`, so the card stays and the invite button re-enables, exactly like the
    existing `GWM_RATE_LIMITED` handling.
- `MatchRepository.request` gained an optional `double? clientDetourM` param (both
  `SupabaseMatchRepository` and `DemoMatchRepository` updated; `SupabaseMatchRepository` sends it as
  `p_client_detour_m` only when non-null, using Dart's null-aware map-entry syntax
  `'p_client_detour_m': ?clientDetourM` — required by the `use_null_aware_elements` lint over an
  explicit `if`). `test/support/fake_repos.dart`'s `FakeMatchRepository` gained `requestDetourM`
  (records every call's value) for test assertions.
- `FailureCode.detourCalcFailed` (`DETOUR_CALC_FAILED`, new, client-side only — never sent by any
  server) + a Thai message in `failure_messages.dart`.

### 2. GWM_DETOUR_IMPLAUSIBLE
- Mapped in `failure_messages.dart`: "ระยะเบี่ยงที่คำนวณได้ไม่สมเหตุสมผล ลองใหม่อีกครั้ง". Note this
  code is reachable by an HONEST client too (not only a malicious one): the client's precise
  calculation uses BLURRED driver coordinates (the only ones a Rider ever sees pre-match), while the
  server's floor uses the driver's EXACT geometry, so blur error can rarely push a genuine value just
  under the sound floor. Accepted as a known, documented edge case (small relative to typical detour
  margins), not something this Dart-only task can fix (would require either exposing exact
  coordinates, which BUG-R7-03's design explicitly rejects, or a looser server floor, which is a
  /db-architect + PM decision, not implied by this task's scope).

### 3. vibe/mood on cards (BUG-R7-01)
- No code change was needed in `MatchCandidate.fromJson`, `CommuteCardDeck`, or
  `CandidateDetailScreen`: all three already read/render `vibe_tags`/`mood_text` by NAME (JSON map
  keys), not by column position/count, so nothing broke or needed adjusting for the new 20-column
  shape — the Stage B parsing code (round 7, `match_models.dart:161-162`) simply starts receiving
  real data now that `find_matches` (0016) actually returns the two columns. Verified end-to-end with
  a 20-column fixture in `test/features/matching/match_models_test.dart` (new group) and the demo
  candidate added below.

### 4. Contract tests updated
- New `test/qa/round7_stage_d_contract_test.dart` (the 0010-based `round5_contract_test.dart` was
  intentionally left untouched — it asserts what the HISTORICAL 0010 migration did, not the current
  live shape): asserts `find_matches` (0016) returns exactly the 20-column list ending
  `vibe_tags`/`mood_text`, the same 24h `mood_set_at` staleness guard as `get_trip_card`, Dart reads
  both new keys, `request_match`'s new optional `p_client_detour_m double precision default null`
  param and that Dart sends it conditionally, `GWM_DETOUR_IMPLAUSIBLE`/`GWM_NOT_ELIGIBLE` are raised
  and mapped, the old 2-arg `request_match` signature is dropped (not left callable), the new
  `matches.detour_precise_m` column, and cross-references the exact `_car_detour_floor_m` SQL text
  the Dart file's doc comments claim to mirror.

### 5. Demo fakes
- `demo_data.dart`: `demoDetourOnlyCandidate` (id `demo-cand-detour-only`) — a 5th car Driver
  candidate whose destination is genuinely far (a different demo place, ~13 km) from the demo Rider
  trip's own destination, so the radial `max_dropoff_m` path alone fails and the detour-tolerance
  path is the only way it qualifies — the one demo scenario that actually exercises
  `needsDetourPath` -> `computePreciseDetourM` instead of being short-circuited by the radial path
  like every pre-existing demo candidate. Also carries `vibeTags`/`moodText` so the same scenario
  doubles as the BUG-R7-01 demo proof. Opt-in via `demoCarCandidates(includeDetourOnly: true)` /
  `DemoMatchRepository.showDetourOnlyCandidate` (default `false`) — every pre-existing demo
  scenario/test is unaffected.
- `DemoRouting.failNextRoute` (new field): the next `route()` call throws
  `AppFailure(FailureCode.networkTimeout)` then resets — simulates the OSRM-failure-at-request-time
  retry state for demo purposes (real `GWM_DETOUR_IMPLAUSIBLE` needs a malicious client, so this
  simulates the OTHER failure path the task asked for: the client-side calc itself failing).
  `routingServiceProvider`'s demo override moved from an inline `DemoRouting()` to a new
  `demoRoutingProvider` so the hub can reach and flip this field.
- `demo_hub_screen.dart`: new "รอบ 7 (ขั้น D)" section — a switch to add/remove แนน (the detour-only
  candidate), a tool to arm the next OSRM failure, and a direct link to her detail page (vibe/mood
  chips).

### Tests (all new, all green)
- `test/features/trip/precise_detour_test.dart` — leg structure/formula (documents the exact 0016
  cross-reference in comments), negative-clamp, all-3-legs-fail-closed, `needsDetourPath` cases.
- `test/features/matching/precise_detour_request_test.dart` — full deck-invite flow: detour-only
  candidate succeeds (3 OSRM calls, `p_client_detour_m` sent and non-null), radial-qualifying
  candidate is untouched (0 OSRM calls, param omitted), OSRM failure never calls `request_match` and
  shows the "ลองใหม่อีกครั้ง" notice with the card still invitable.
- `test/core/error_mapper_test.dart` — `GWM_DETOUR_IMPLAUSIBLE` and `DETOUR_CALC_FAILED` Thai
  messages, non-generic, distinct from each other.
- `test/features/matching/match_models_test.dart` — new `vibe_tags/mood_text (0016 Stage D...)` group:
  full 20-column fixture end-to-end, older-server (columns absent) defaults, blank/whitespace/
  non-string tolerance, survives `withRequestStatus`/`withoutRequest`.
- `test/qa/round7_stage_d_contract_test.dart` — see item 4 above.
- `test/demo/demo_r7c_test.dart` (appended group) — `demoDetourOnlyCandidate` opt-in behaviour, the
  hub toggle wiring into `findMatches`/`request`, and `DemoRouting.failNextRoute`'s one-shot-then-reset
  contract.

### Verification
- `flutter analyze`: 0 new issues (same 4 pre-existing `deprecated_member_use` infos, unrelated files
  not touched by this task).
- `flutter test`: all 1034 tests passed (1003 pre-existing + ~31 new across the files above; some
  existing files gained new test groups rather than new files, e.g. `match_models_test.dart`,
  `error_mapper_test.dart`, `demo_r7c_test.dart`).
- `flutter build web --dart-define=DEMO_MODE=true`: OK (`build/web`).
- `flutter build apk --debug`: OK (`build/app/outputs/flutter-apk/app-debug.apk`).

### Nothing to send back to PM
No scope had to be cut or reinterpreted. The one genuine open item (Driver-initiates-request cannot
compute the precise detour, §16.7) is an already-acknowledged design gap, not a new one introduced
here, and does not block US-50's primary (Rider-initiates) flow from working correctly end-to-end.

---

## Round 8: Bug fixes (docs/tasks-round8.md / docs/requirements-round8.md) — T1/T2/T3

ทั้ง 3 task เป็น P0 เท่ากัน ไม่มี scope change และไม่มีจุดที่ต้องส่งกลับ PM

### T1 — BUG-1 dedup ผลค้นหาสถานที่ (duplicate-key crash)
- ไฟล์ที่แก้:
  - `lib/features/geo/presentation/place_search_controller.dart` — เพิ่ม `_dedup()` (static, `LinkedHashSet`-style ด้วย `Set<String>` ของ key `label|lat|lng` + `List.add` เมื่อ key ใหม่) เรียกใน `_run()` ก่อน set `results`/สถานะ `empty` เพื่อให้ empty-state ยังตรง (เดิมเช็ค `r.isEmpty` เปลี่ยนเป็นเช็ค `results.isEmpty` หลัง dedup)
  - `lib/features/geo/presentation/place_search_field.dart` — เปลี่ยน `ListTile` key จาก `place-${s.label}` เป็น `place-$index-${s.label}-${s.point.latitude}-${s.point.longitude}` (ใช้ `.indexed` ของ Dart 3.11) เป็น safety net ชั้นสอง ตามที่ tasks-round8 ระบุ ไม่ใช่การแก้แทน dedup
- เทสต์ที่เพิ่ม:
  - `test/features/geo/place_search_controller_test.dart` — เพิ่ม 3 case: dedup label+point ซ้ำ (เก็บตัวแรก, เหลือ 2 จาก 4), label ซ้ำแต่ point ต่างกันไม่ถือเป็นซ้ำ, regression 5 รายการไม่ซ้ำต้องเหลือครบตามลำดับเดิม
  - `test/features/geo/place_search_field_test.dart` (ไฟล์ใหม่) — widget test 2 เคส: geocoder คืนผลซ้ำ -> render ไม่ throw (`tester.takeException()` เป็น null) และเหลือ 2 tile ที่ dedup แล้ว; regression 3 รายการไม่ซ้ำ render ครบ 3

### T2 — BUG-2 timeout ครบทุกขั้นของ location request (ANR)
- ไฟล์ที่แก้:
  - `lib/features/geo/data/geolocator_location_service.dart` — เพิ่ม `.timeout()` ให้ `permission()` (ครอบทั้ง `isLocationServiceEnabled` และ `checkPermission`) และ `request()` (ครอบ `isLocationServiceEnabled` และ `requestPermission`) โดย catch `TimeoutException` แล้ว map เป็น `LocationPermissionState.serviceOff` (เลือก state นี้แทน `denied` เพราะ `current_location.dart obtainCurrentLocation` เจอ `denied` แล้วจะเปิด dialog consent ซ้ำ ซึ่งไม่ตรงความหมาย "timeout"; `serviceOff` ไหลตรงไปที่ error branch `_snack(context, T.locOpenSettings)` ทันทีตาม AC ข้อ 3 ของ requirements-round8) — ไม่ต้องแก้ enum/`location_service.dart` ตามที่ tasks-round8 แนะนำให้เลี่ยงถ้าเป็นไปได้
  - `currentPosition()` เพิ่ม `.timeout()` ชั้นนอกครอบ `Geolocator.getCurrentPosition(...)` ทั้งที่มี `timeLimit: 10s` อยู่แล้วข้างใน (defense-in-depth ตามที่ระบุใน task) และแยก catch `TimeoutException` ให้คืน `AppFailure(FailureCode.networkTimeout)` (มีอยู่แล้วในระบบ ไม่ต้องเพิ่ม failure code ใหม่) แทนที่จะรวมกับ error อื่นเป็น `locationUnavailable` เหมือนเดิม
  - เปลี่ยน constructor `GeolocatorLocationService` จาก `const GeolocatorLocationService()` (ไม่มีพารามิเตอร์) เป็นรับ `permissionTimeout`/`positionTimeout` (default 12 วินาทีทั้งคู่ — อยู่ในช่วง 10-15 วิที่ requirements-round8 ระบุ, มากกว่า `timeLimit` ภายใน 10 วิเล็กน้อยตามคำแนะนำใน task) เพื่อให้เทสต์ inject ค่าสั้นแทนที่จะรอจริง 12 วิ; ที่เรียกใช้จริงจุดเดียว (`geo_providers.dart:35 const GeolocatorLocationService()`) ยังคอมไพล์ผ่านเพราะทุกพารามิเตอร์มี default
  - ไม่ต้องแก้ `lib/features/geo/domain/location_service.dart` และ `lib/features/geo/presentation/current_location.dart` — ตรวจแล้วว่า error/timeout ทุก branch ไหลเข้า `_snack(context, failureMessage(f))`/`_snack(context, T.locOpenSettings)` ที่มีอยู่แล้วได้จริงโดยไม่ต้องแก้ (ยืนยันด้วย widget/unit test ด้านล่าง)
  - grep `Geolocator.` ทั้งโปรเจกต์แล้ว: จุดเรียกอื่นทั้งหมด (`pick_point_screen.dart`, `preset_screens.dart`, `create_trip_step1_screen.dart`) เรียกผ่าน `LocationService` interface (`obtainCurrentLocation`/`loc.permission()`) จุดเดียวกัน ไม่มีการเรียก native plugin ตรงๆ นอกไฟล์นี้ — fix ที่จุดเดียวครอบคลุมทุก flow ตามที่ tasks-round8 คาดไว้
- เทสต์ที่เพิ่ม (ไฟล์ใหม่ `test/features/geo/geolocator_location_service_test.dart`):
  - ใช้ `GeolocatorPlatform.instance = _FakeGeolocatorPlatform()` (จาก `geolocator_platform_interface`, เพิ่มเป็น `dev_dependencies` ใน `pubspec.yaml` เพราะแต่ก่อนมีแค่ transitive) แทนการ mock ผ่าน method channel — ทดสอบพฤติกรรม timeout ของ `GeolocatorLocationService` ตัวจริงได้ตรง ๆ โดยตั้ง `permissionTimeout`/`positionTimeout` เป็น 50ms ในเทสต์เพื่อไม่ต้องรอจริง
  - Case ค้าง (ใช้ `Completer` ที่ไม่ complete): `permission()`/`request()` ค้างที่ `isLocationServiceEnabled`/`checkPermission`/`requestPermission` -> คืน `serviceOff` ภายใน timeout ที่ตั้งไว้ (assert ด้วย `.timeout(Duration(seconds: 2))` รอบนอกกันเทสต์ค้างจริงถ้าโค้ดมีบั๊ก); `currentPosition()` ค้าง -> คืน `Err(networkTimeout)` ภายในเวลา
  - Regression: ตอบเร็วปกติ -> `permission()`/`request()` คืน `granted` ตามจริง, `currentPosition()` คืนพิกัดถูกต้อง
  - Regression: `serviceEnabled=false` / `checkResult=denied` ตอบเร็ว -> ได้ `serviceOff`/`denied` ทันที ไม่ปนกับ timeout

### T3 — BUG-3 validation ไม่อัปเดตหลังปักหมุดจุดเริ่มต้น
- ไฟล์ที่แก้: `lib/features/trip/presentation/create_trip_step1_screen.dart`
  - แทนที่จะ cache ผล validate ไว้ในฟิลด์ `TripFormIssue? _issue` (ที่ set เฉพาะใน `_next()`) เปลี่ยนเป็น derive ค่าใหม่ทุกครั้งที่ `build()` รัน: `final issue = _touched ? TripFormValidator.validatePlaces(form.origin, form.dest) : null;` — เพราะ `build()` เรียก `ref.watch(tripFormProvider)` อยู่แล้ว จึง rebuild อัตโนมัติทุกครั้งที่ origin/dest เปลี่ยนไม่ว่าจะมาจาก flow ไหน (พิมพ์ค้นหา/GPS/ปักหมุด ล้วนเรียก `ctrl.setOrigin`/`ctrl.setDest` ที่แก้ provider เดียวกัน) แก้ปัญหาที่ root cause เดียวโดยไม่ต้องเขียน `ref.listen` แยก 3 จุด
  - เพิ่ม `bool _touched` (แทน `TripFormIssue? _issue`) ตั้งเป็น `true` ใน `_next()` เท่านั้น เพื่อไม่ให้ error message โผล่ก่อนผู้ใช้เคยกด "ถัดไป" (กัน false-positive ตอนเพิ่งเปิดหน้า ตาม AC ข้อ 3 ของ BUG-3) — `_next()` ยัง validate + navigate เหมือนเดิมทุกประการ (คงไว้ตามที่ tasks-round8 ระบุ)
- เทสต์ที่เพิ่ม (ไฟล์ใหม่ `test/features/trip/create_trip_step1_screen_test.dart`):
  - ใช้ harness แบบเบา (`ProviderScope` + `MaterialApp.router` กับ `GoRouter` ที่มีแค่ 3 route ที่เกี่ยวข้อง) แทน `openApp()`/`buildTestApp()` ของ `test/support/` **โดยตั้งใจ** — พบว่า `openApp()` ตอนนี้ throw `UnimplementedError: init() has not been implemented` จาก `video_player` ตั้งแต่ `SplashScreen` ในสภาพแวดล้อมนี้ (คอนเฟิร์มว่าเป็นปัญหาเดิมของ test infra ไม่เกี่ยวกับ T3 โดยรันของเดิม `test/features/trip/dropoff_limit_test.dart`/`detour_tolerance_test.dart` ที่ไม่ได้แตะเลยก็ fail แบบเดียวกัน 15 เคส) ไม่อยู่ใน scope ของ round 8 (bug fix เฉพาะ 3 บั๊กที่ระบุ) จึงไม่ได้แก้ harness กลาง แต่หลบด้วย router เบาแทนสำหรับเทสต์ใหม่นี้
  - Case หลัก (BUG-3): กด "ถัดไป" ทั้งที่ฟอร์มว่าง -> เห็น `T.errOriginMissing` -> จำลองปักหมุดจุดเริ่มต้น (เปิด `PickPointScreen` จริงผ่านปุ่ม "ปักหมุดบนแผนที่" ตัวที่ 2 แล้วกด key `pick-confirm`) -> error หายทันที (เปลี่ยนเป็น `errDestMissing` เพราะยังไม่มีปลายทาง) โดยไม่ต้องกด "ถัดไป" ซ้ำ
  - Regression flow พิมพ์ค้นหา: พิมพ์ในช่อง `ValueKey('origin-field')` + กด submit + แตะผลลัพธ์ -> error หายทันที
  - Regression flow GPS: ตั้ง `FakeLocationService.state = granted` (ข้าม consent dialog) แล้วกด "ใช้ตำแหน่งปัจจุบัน" -> error หายทันที
  - Regression: หน้าเปิดใหม่ยังไม่กด "ถัดไป" -> ไม่มี error ทั้งสองข้อความค้างอยู่เลย
  - Regression: origin (จากปักหมุด) + dest (set ตรงผ่าน `tripFormProvider.notifier.setDest` ด้วยจุดที่ไกลพอ เพื่อแยกการทดสอบนี้ออกจากพฤติกรรม default-centre ของแผนที่ ซึ่งถูกครอบคลุมแยกในเคสหลักด้านบนแล้ว) -> กด "ถัดไป" นำทางไปหน้าถัดไปสำเร็จ (เช็คจาก route placeholder `step2-placeholder` แทนการ render `CreateTripStep2Screen` จริงเพื่อไม่ผูกเทสต์นี้กับ dependency อื่นของหน้า step2)

### ผลตรวจ (round 8)
- `flutter analyze` เฉพาะไฟล์ที่แก้/เพิ่ม (4 ไฟล์ lib + 4 ไฟล์ test): No issues found
- `flutter test` เฉพาะไฟล์ที่แก้/เพิ่ม: ผ่านทั้งหมด (controller 8, field 2, geolocator service 9, step1 screen 5)
- `flutter test test/features/geo/ test/features/trip/` (regression กว้างขึ้น): 119 ผ่าน, 15 fail — ยืนยันแล้วว่าทั้ง 15 เคสที่ fail เป็นปัญหาเดิมของ `openApp()`/`video_player` ใน `dropoff_limit_test.dart`/`detour_tolerance_test.dart` (ไม่เกี่ยวกับไฟล์ที่แก้รอบนี้เลย ทดสอบซ้ำแล้วว่า fail เหมือนกันแม้ไม่มีการแก้ของ round 8) ไม่ใช่ regression จาก T1/T2/T3

### ทางเทคนิคที่ตัดสินใจเอง (ไม่ใช่ scope change ของ requirement)
- เพิ่ม `permissionTimeout`/`positionTimeout` เป็นพารามิเตอร์ constructor ของ `GeolocatorLocationService` (ไม่ใช่ const ตายตัวในโค้ด) เพื่อให้ inject ค่าสั้นในเทสต์ได้โดยไม่ต้องรอจริง 12 วิ/เทสต์ — ไม่กระทบผู้ใช้จริง (`geo_providers.dart` ยังสร้างแบบไม่ใส่ argument ได้ค่า default 12 วิเหมือนเดิม)
- เพิ่ม `geolocator_platform_interface` เป็น dev_dependency ตรง ๆ ใน `pubspec.yaml` (เดิมเป็นแค่ transitive ผ่าน `geolocator`) เพื่อให้เทสต์ import ได้โดยไม่ขึ้น lint `depend_on_referenced_packages`
- ไม่แก้ `test/support/fakes.dart`/`p4_helpers.dart` (harness กลาง) แม้พบว่า `openApp()` fail จาก video_player เพราะนอก scope บั๊ก 3 ตัวที่ได้รับมอบหมายรอบนี้ — ควรแจ้งทีมทราบว่ามี test-infra issue ค้างอยู่ (ไม่ใช่ของใหม่ที่ทำรอบนี้) แนะนำเปิด task แยกไปตรวจ/mock `video_player` ให้ test อื่นที่ใช้ `openApp()` กลับมาผ่านได้ครบ

---

## Round 9: UI/UX Overhaul (docs/requirements-round9.md / docs/tasks-round9.md / docs/design-spec-round9.md)

ขอบเขต: T1-T7 (P0). T8-T10 (P1/P2) ไม่ได้ทำ — ไม่มีเวลาเหลือหลัง P0 (ตามที่ tasks-round9.md อนุญาตให้ข้ามถ้าไม่ใช่ trivial).

### Task ที่ implement แล้ว

- [x] T1 (US-7 Design System Tokens) — `lib/core/theme/tokens.dart` (`AppColors.bg`), `lib/core/theme/tone.dart` (`ToneColors.rider.bg`): `#F7FAFC` -> `#F8F9FC` ตามคำตัดสิน PM ข้อ 8 ของ design-spec-round9.md (`driver.bg`/`riderDark`/`driverDark` ไม่แตะ — จงใจเป็นธีมมืดอยู่แล้ว ไม่ใช่ "พื้นหลังสว่างทั่วไป" ที่ AC พูดถึง). ถอด `AppColors.border` ที่เป็นเส้นขอบตกแต่ง: `CandidateCard` (`matching_widgets.dart`) unselected state เปลี่ยนจาก `BorderSide(color: context.tone.border, width:1)` เป็น `BorderSide.none` (คงไว้เฉพาะ selected = เส้นเขียว semantic ตามที่ design-spec ระบุชัดว่าต้องคงไว้); `trip_widgets.dart` `TripStatusChip` เปลี่ยนจาก `AppColors.*` เป็น `context.tone.*` ทั้งชุด (แก้ปัญหา `AppColors.border` เดิมที่ cancelled/expired ใช้ปนกับ completed ไปพร้อมกัน — ดู T6). `AppCard`/`CardThemeData` ไม่มี `BorderSide` อยู่แล้วจากรอบก่อน ไม่ต้องแก้เพิ่ม. **ไม่ได้แตะ** `role_badge.dart`/`SeatChip` และ `onboarding_screen.dart` ที่ยังอ้าง `AppColors.border` เพราะไม่อยู่ใน 5 ไฟล์เป้าหมายของรอบนี้ (ไม่ใช่ AppCard/generic container ในความหมายที่ US-7 AC ชี้ถึงโดยตรง) — ถ้าต้องการถอดให้ครบ 100% ทั้งแอปต้องเป็นงานแยก

- [x] T2 (US-6 Global Verified Badge) — `lib/core/widgets/global_verified_badge.dart` (ใหม่): `GlobalVerifiedBadge(badges, {onGlass, loading})`. กรอง `kind == 'organization'` ทิ้งเสมอ; มี email/phone อย่างน้อย 1 -> ป้ายเดียว "ยืนยันตัวตนแล้ว" (โทนฟ้าอ่อน `tone.primaryTint`/`primaryInk`, บนภาพใช้ frosted `onGlass:true`); ไม่มีทั้งคู่ -> ป้าย "ยังไม่ยืนยันตัวตน" โทนกลาง (ไม่ใช่สีแดง) ตามคำตัดสิน PM ข้อ 5 (**ไม่ใช่เงียบแบบที่ UIUX ร่าง RC-4 ไว้ตอนแรก** — ต้องอัปเดตตามคำตัดสิน PM ก่อนเริ่มเขียนโค้ด ตามที่ design-spec-round9.md ท้ายเอกสารสั่งไว้). `BadgeWrap` (`matching_widgets.dart`) เปลี่ยนเป็น wrapper บาง ๆ เรียก `GlobalVerifiedBadge` ตัวเดียว — ทำให้ทุกจุดที่เคย import `BadgeWrap` อยู่แล้ว (`commute_card_deck.dart`, `requests_screen.dart`, `candidate_detail_screen.dart`, `match_detail_screen.dart` x2) ได้พฤติกรรมใหม่ทันทีโดยไม่ต้องแก้ทีละไฟล์. `me_tab.dart` (`myBadgesProvider` ที่ L35 เดิม) เปลี่ยนจาก `VerifiedBadge`/`Wrap` มือเขียนเป็น `GlobalVerifiedBadge(badges)` ตัวเดียวใน `_ProfileHeroCard`. **ไม่แตะ** `verifications`/`org_domains`/`parseBadges()`/`VerificationBadge.label` ตามที่ระบุไว้ชัดว่าเป็น presentation-layer ล้วน
- อัปเดตเทสต์ตามพฤติกรรมใหม่: `test/features/qa_round1_test.dart` กลุ่ม "T5.13 Me tab badges" — 2 เคสแรกเปลี่ยนจาก assert ข้อความ badge แยกทีละตัว (`'ยืนยันอีเมลแล้ว'`, `'องค์กร: ...'`) เป็น assert ป้ายรวม `'ยืนยันตัวตนแล้ว'` + ยืนยันว่าไม่มีข้อความ `'องค์กร'` หลุดออกมาเลยแม้ badge องค์กรจะยังอยู่ใน fixture; เคสที่ 3 ("no verification rows") ไม่ต้องแก้ (ยัง assert `'ยังไม่ยืนยันตัวตน'` เหมือนเดิม เพราะ behaviour คงเดิมตามคำตัดสิน PM ข้อ 5). `test/features/matching/match_models_test.dart` ไม่ต้องแก้ (เทสต์ parse-level ล้วน ไม่เกี่ยวกับการแสดงผล ตามที่ US-6 AC ระบุว่า backend/parse logic ไม่ถูกแตะ)

- [x] T3 (US-1 Tinder-Style Commute Card Deck) — `lib/features/matching/presentation/commute_card_deck.dart`: `CommuteCard` เปลี่ยนจาก `StatelessWidget` (ข้อความล้วนบนพื้นขาว) เป็น `StatefulWidget` เต็มจอ 3 สไลด์ (`_CardSlide.avatar/vehicle/route`) ควบคุมด้วย story bar (RC-1) — จำนวนขีด data-driven จริง (`role==driver` -> เพิ่มสไลด์รถ, `approxDest != null` -> เพิ่มสไลด์ route ตามคำตัดสิน PM ข้อ 3 คือ nullability-driven ไม่ใช่ role-driven). สไลด์ 1 (`_AvatarVectorSlide`) = gradient พาสเทล derive จากชื่อ + ตัวอักษรแรกเต็มจอ (ไม่ใช่ `Image` widget เพื่อไม่ชน regression test เดิมที่ assert `find.byType(Image), findsNothing`). สไลด์ 2 (`_VehicleVectorSlide`) = gradient กรมท่า + ไอคอนรถมินิมอล. สไลด์ 3 (`_RouteSnapshotSlide`) = ฝัง `AppMap` เดิม (`interactive:false`, `showZoomButtons:false`, `AbsorbPointer`) center ที่จุดกึ่งกลาง origin/dest, zoom heuristic ตามระยะทาง (ไม่มี fit-bounds API ใน `AppMap` เดิม จึงประมาณ zoom เอาเองจากระยะ ไม่ใช่การเพิ่ม service ใหม่). Gradient ดำ + ข้อมูล 4 บล็อก (`_CommuteInfoOverlay`, RC-2) — คงทุก `Key`/ข้อความ/logic เดิมไว้ทั้งหมด (`card-name`, `card-overlap`, `card-depart`, `card-role-text`, `card-rating` ผ่าน `CardRatingSlot` เดิมที่เพิ่ม param `color` ใหม่, `R6C.cardSemantics` บน `Semantics` ตัวนอกสุดเดิม) เพื่อไม่ให้ regression กับ `test/features/round6/deck_test.dart`/`precise_detour_request_test.dart` ที่มีอยู่แล้วจำนวนมาก — อายุ (`age`) **ไม่มี branch เลย** ตามคำตัดสิน PM ข้อ 1 ของ design-spec-round9.md (ไม่มีฟิลด์นี้ในโมเดล และจะไม่มีวันมี ไม่ใช่ optional จริง). ปุ่ม 3 วง (`_ActionBar`/RC-3): skip 64dp (คงเดิม, แค่เพิ่ม `backgroundColor`), invite 80dp (เดิม 72dp, ขยายให้เด่นกว่าเห็นชัด), ℹ️ เปลี่ยนจาก `TextButton` ข้อความเป็นปุ่มวงกลม `IconButton` 56dp — **onDetail callback เดิมทุกประการ** (`context.push(Routes.candidate(...))`) ตามคำตัดสิน PM ข้อ 2 (ไม่ใช่ bottom sheet)
- `CardRatingSlot` (เดิมอยู่ท้ายไฟล์เดียวกัน) เพิ่ม optional `color` param (ใช้สีขาวบนภาพ) — ไม่กระทบจุดเรียกเดิมที่ไม่ส่ง `color`
- แก้ regression ที่พบจาก `flutter test test/features/round6/deck_test.dart` รอบแรก: บล็อก 2/3 ของ `_CommuteInfoOverlay` (role text / overlap / depart) เดิมเขียนเป็น `Row(mainAxisSize:min, children:[Icon,...,Text(...)])` แบบไม่มี `Flexible` ทำให้ overflow ที่ text scale 2.0 กับชื่อ/ข้อความยาว (เทสต์ `layout at 390 px, text x2.0` เดิมจับได้ทันที) — แก้เป็น `Wrap` (ไอคอน+ข้อความ) แทน `Row` ตรงจุดเดิม เพื่อให้ reflow ขึ้นบรรทัดใหม่แทนการ overflow เมื่อพื้นที่ไม่พอ
- `matching_widgets.dart`: `BadgeWrap`/`CandidateCard` แก้ตาม T1/T2 ข้างบน

- [x] T4 (US-2 Home Screen & Map Zoom) — `lib/features/home/presentation/home_tab.dart` เขียนใหม่ทั้งไฟล์ (โครงสร้าง `Stack` แทน `Column(Expanded flex4/5)`): แผนที่เต็มจอเป็นพื้นหลัง (`Positioned.fill`, ไม่มีกรอบ/การ์ดครอบ), header ลอยแบบโปร่งใส (ชื่อ "สวัสดี, [ชื่อ]" + text-shadow, ปุ่มโล่ safety ลอยวงกลมแทน `AppBar action` เดิม — **คง tooltip `P.safetyShield` เดิมไว้** เพราะมีเทสต์ `find.byTooltip(P.safetyShield)` อยู่แล้ว), ปุ่ม 🧭 recenter ลอยมุมขวา (`_FloatingIconButton`, เรียก `AppMap.onMyLocation` เดิม), จุดตำแหน่งฉันกระพริบ (`_PulseDot`), และ `_FloatingSearchPanel` (การ์ดขาวมุมบนโค้งลอยด้านล่าง แทน `Expanded(flex:5, ListView(...))` เดิม — เนื้อหาข้างใน (`_noTrip`/`_withTrip`, `QuickHomeCard`, `HintCard`, nearby list) **ไม่เปลี่ยน logic เลย** ย้ายเข้ามาอยู่ใน panel ใหม่เท่านั้น)
- Zoom: GPS granted -> animate ไป zoom **15.2** (อยู่ในช่วง 15.0-15.5 ตาม AC) ด้วย tween มือเขียน 650ms (ไม่มี `flutter_map_animations` เป็น dependency อยู่แล้ว จึงไม่เพิ่ม package ใหม่ — ใช้ `AnimationController` ธรรมดา `move()` ทุกเฟรม); ไม่มีตำแหน่ง/ถูกปฏิเสธ -> fallback zoom **12** (ระดับเมือง) ตามที่ design-spec-round9.md เสนอไว้
- **จุดตัดสินใจสำคัญที่ต่างจาก spec ร่างเริ่มต้น (ป้องกัน regression กับ BUG-2)**: แยก location flow เป็น 2 เส้นทาง — (1) `_locateSilently()` เรียกตอนเปิดหน้า (ใน `initState`/`postFrameCallback`) เช็คแค่ `loc.permission()` เฉย ๆ, **ไม่เรียก `obtainCurrentLocation` (ที่โชว์ consent dialog) อัตโนมัติ** ถ้ายังไม่เคยอนุญาต — ถ้า granted อยู่แล้วก็ animate เงียบ ๆ, ถ้าไม่ granted ก็ไม่ทำอะไรเลย (ไม่โชว์ dialog/snackbar โดยไม่มีผู้ใช้กดอะไร); (2) `_locate()` (ปุ่ม 🧭 recenter, แตะเอง) เรียก `obtainCurrentLocation(context, ref)` เดิมเต็มรูปแบบ (BUG-2-safe flow, round 8) ไม่ถูกแก้แม้แต่บรรทัดเดียว — **เหตุผล**: ถ้าเรียก `obtainCurrentLocation` อัตโนมัติตอนเปิดหน้า Home ทุกครั้ง จะ pop consent dialog ให้ผู้ใช้ทุกคนที่ยังไม่เคยอนุญาตตำแหน่งโดยที่เขาไม่ได้กดอะไรเลย (ไม่ตรงกับพฤติกรรมเดิมของทุกหน้าจอในแอปที่ location prompt เป็น explicit action เสมอ) และจะทำให้ widget test เดิมจำนวนมากที่เปิดหน้า Home โดยไม่ mock dialog ค้าง/พัง โดยเฉพาะเพราะ `FakeLocationService.state` default = `denied` (ตรวจสอบแล้วว่า `_locateSilently` เจอ `denied` แล้ว return เงียบ ๆ พอดี — ปลอดภัยกับ default ของเทสต์เดิมทั้งหมดโดยไม่ต้องแก้ fixture ใด ๆ)
- **จุดตัดสินใจสำคัญที่ 2**: จุดกระพริบ (`_PulseDot`) ใช้ `AnimationController.repeat(reverse:true, count:6)` (**จำกัดรอบ ไม่ใช่ infinite `.repeat()`**) — ทดสอบแล้วว่าไม่มีจุดไหนในโค้ดเดิมทั้งโปรเจกต์ใช้ infinite repeat เลยแม้จุดเดียว (`grep '\.repeat()'` เจอแค่จุดนี้จุดเดียว) เพราะ `tester.pumpAndSettle()` (ใช้อยู่ทั่วทั้ง test suite รวม `lifecycle_test.dart` ที่ตั้ง `location.state = granted` จริง) จะ timeout ทันทีถ้ามี animation ที่ไม่มีวันจบค้างอยู่บนจอ ไม่ว่าจะเคารพ reduce-motion หรือไม่ (reduce-motion แค่ทำให้มองไม่เห็นการเคลื่อนไหว ไม่ได้หยุด ticker) — เลือกจำกัด 6 รอบ (~5.4 วิ) แทนเพื่อให้ยังได้ AC "เต้น/กระพริบ" จริงแต่ animation จบเป็นปกติ
- `HomeTab` ไม่ได้เปลี่ยน role switch mechanism เดิมเลย — **ไม่ได้เพิ่มสวิตช์แคปซูล [🚗|🎒] ใหม่ตามที่ RC-6 UIUX ร่างไว้** เพราะระบบเดิมมี `withRoleStrip(...)` (ครอบทุกแท็บอยู่แล้ว, `RoleModeBadge`/`RoleStrip` มีอยู่แล้ว) ทำหน้าที่เดียวกัน (แสดง + สลับ role) อยู่แล้วทั้งแอป — การเพิ่มสวิตช์ซ้ำอีกจุดเฉพาะหน้า Home มีความเสี่ยง regression สูง (ต้อง sync state 2 จุด) โดยที่ AC หลักคือ "ยังคงสลับ role state เดิมของระบบ" ซึ่งทำได้อยู่แล้วผ่านกลไกเดิม — **จุดนี้ต้องแจ้ง PM/UIUX**: ยังไม่ได้ implement RC-6 "สวิตช์แคปซูลมุมขวาบน" แยกตามสเปกอักษรตรงตัว 100% (ใช้กลไกเดิมที่เทียบเท่าแทน)
- **ยังไม่ได้ทำตามคำตัดสิน PM ข้อ 4** (ย้าย time chip/role segmented/dropoff selector ของ `QuickHomeCard._ready()` ไปไว้หลังการแตะช่องค้นหา/ปุ่มหลัก) — หมดเวลาในรอบนี้ ไม่ได้แตะ `lib/features/presets/presentation/quick_home_card.dart` เลย (0 regression risk แต่ 0 progress ต่อข้อนี้) ยังคงแสดง time chip/role/dropoff ทั้งหมดอยู่บนการ์ดเหมือนเดิมเมื่อ preset ครบ (`_ready()` state) เพียงแต่ตอนนี้การ์ดนั้นลอยอยู่ใน `_FloatingSearchPanel` ใหม่แทนที่จะอยู่ใน `Expanded` เดิม — **ต้องแจ้ง PM**: AC "ไม่มีกล่องซ้อนกล่อง"/สถาปัตยกรรม option-B ยังไม่ครบ 100% สำหรับ state `_ready()` โดยเฉพาะ (state `missing`/`partial`/`with-active-trip` ตรง AC อยู่แล้วเพราะเนื้อหาสั้นอยู่แล้ว)

- [x] T5 (US-3 Chat Tab) — `lib/features/chat/presentation/chats_tab.dart` เขียนใหม่ทั้งไฟล์: `ListView.separated` + `Divider` บาง (`context.tone.border`) แทน `ListView.builder` + `Card` ต่อแถว (RC-8 `_ChatRow`). อวาตาร์ 56dp (เดิม 40dp) ผ่าน `UserAvatar.partner(size:56)` เดิม + ไอคอนรถเล็กมุมขวาล่างเมื่อ `match.partnerRole == TripRole.driver` (ฟิลด์มีอยู่แล้วในโมเดล ไม่ต้องเพิ่ม). เพิ่มเวลาแบบสั้น (`_shortTime`: "HH:mm" วันนี้ / "เมื่อวาน" / "DD/MM") — ฟีเจอร์ใหม่ที่ AC ขอ ("เวลาข้อความล่าสุด") ซึ่งของเดิมไม่เคยแสดงเวลาเลย. Unread ยังเป็น**จุดแดง**ไม่ใช่ตัวเลข ตามที่ design-spec-round9.md ยืนยันว่า `unreadMatchIdsProvider` เป็น `Set<String>` ไม่มี count จริง (คง `Key('unread-<id>')` เดิมไว้ให้ `test/features/p4/chat_test.dart` ผ่าน). แตะแถว -> `context.push(Routes.chat(m.id))` เดิมทุกประการ; ไม่มี swipe action ในโค้ดเดิม (ตรวจแล้วตามที่ design-spec-round9.md ระบุ) จึงไม่มีอะไรต้อง regress

- [x] T6 (US-4 Ride Pass Card) — `lib/features/trip/presentation/trip_widgets.dart`: `TripStatusChip` (RC-10) เปลี่ยนสีจาก `AppColors.*` คงที่เป็น `context.tone.*` ทั้ง 5 สถานะ (ทุกสถานะเดิมยังมี pill เป็นของตัวเอง ไม่มีตกหล่น, คง class name เดิมไว้เพราะ `trip_detail_screen.dart` ยัง import อยู่) — แก้ปัญหาเดิมที่ cancelled/expired ใช้สีเดียวกัน (`AppColors.border`) แยกไม่ออก ตอนนี้ cancelled = `dangerTint`, expired = `warningTint`. เพิ่ม `_RouteLine` (RC-9): 🟢 originLabel / เส้นประ / 🔴 destLabel พร้อม fallback ข้อความ "ตำแหน่งที่ปักหมุด" เมื่อ label ว่าง (`trip.originLabel`/`destLabel` เป็น server-resolved text อยู่แล้วเสมอ ไม่เคยเป็นพิกัดดิบตั้งแต่แรก — ตรวจสอบ `trip.dart`/`supabase` mapping แล้วไม่มีจุดไหนแปลง lat/lng เป็น string ให้ UI เห็นเลย จึงไม่มี "ตัวเลขพิกัด GPS ดิบ" ให้ต้องแก้จริง ๆ ตามที่ AC กลัว — งานที่ต้องทำจริงคือเพิ่ม origin label ที่เดิมไม่เคยแสดงเลย (เดิมโชว์แค่ dest) และเพิ่ม fallback ที่เป็นมิตรกว่าเดิม). ปุ่ม action (รวม "เดินทางซ้ำ") ย้ายเข้า `Align(alignment: centerRight, ...)` (มุมขวาล่างของการ์ด ตาม AC) — ไม่ได้แยก action "เดินทางซ้ำ" ออกจาก `Wrap` เดิมเป็นปุ่มวงกลมเดี่ยว ๆ เพราะ `actions` ยังเป็น `List<Widget>` ที่ `trips_tab.dart` ประกอบเอง (มีได้หลายปุ่มพร้อมกัน เช่น legacy-cancel) — คงสถาปัตยกรรมเดิมไว้เพื่อไม่ต้องแก้ API ของ `TripCard`. `Card`/`CardTheme` เดิม (squircle จาก `app_theme.dart` อยู่แล้ว, ไม่มี solid navy `#0B2545` ในโค้ดปัจจุบันให้ต้องถอดจริง ๆ — อาจถูกแก้ไปแล้วในรอบก่อนหน้า หรือ AC อ้างอิง mockup เก่าที่ไม่ตรงกับโค้ดปัจจุบัน 100%)

- [x] T7 (US-5 Profile / Me Tab) — `lib/features/profile/presentation/me_tab.dart` เขียนใหม่บางส่วน: `_ProfileHeroCard` (RC-11, avatar 84dp ลดจาก 96dp ผ่าน `UserAvatar.mine(size:84)` เดิม คง `Key('me-avatar')`, ชื่อตัวหนา, `GlobalVerifiedBadge` แทน `VerifiedBadge`/`Wrap` มือเขียนเดิม, `_StatsRow` 3 คอลัมน์) + `_SettingsGroupCard` x3 (RC-12: การเดินทาง/ความปลอดภัย/ระบบ) แทน `_Row` เรียงยาว 9 แถวเดิม — **ทุกแถวเดิมยังอยู่ครบ ทุก `Key`/label/route เดิมคงเดิม 100%** (`me-vehicle-row`, `R5.photoTitle`, `R6C.placesTitle`, `R5.reviewMineRow`, `P.meSafety`, `P.meContacts`, `P.meSettings`, `P.meBlocked`, `S.policy`, `S.terms`) เพียงจัดกลุ่มใหม่ผ่าน `_RowData`/`_SettingsRow` (ไอคอนในวงกลมพาสเทลตามหมวด, ใช้ `context.tone.*` เสมอ)
- **`_StatsRow` (สถิติ 3 คอลัมน์) เป็น placeholder ล้วนทั้ง 3 คอลัมน์** ("ยังไม่มีคะแนน"/"เร็ว ๆ นี้"/"เร็ว ๆ นี้") — grep ทั้ง `lib/features/` แล้วไม่พบ provider ใด ๆ ที่ให้ "คะแนนรีวิวสะสมของฉัน"/"จำนวนทริปสะสม"/"CO₂ สะสม" ของผู้ใช้เอง (มีแค่ per-trip `co2KgFor()` และ rating เฉพาะของคู่ match ไม่ใช่ของตัวเอง) ตรงตามที่ design-spec-round9.md ทำนายไว้ในประเด็น 7 — ทำตามคำตัดสิน PM ข้อ 7 คือ fallback ต่อคอลัมน์โดยไม่บล็อก T7 ที่เหลือ **ไม่ได้ลองเพิ่ม aggregation query ใหม่** (หมดเวลาในรอบนี้) — ถ้าต้องการค่าจริงต้องเป็นงานแยกที่ยังไม่ได้ทำ ไม่ใช่แค่ empty state เฉย ๆ

### การตัดสินใจทางเทคนิคอื่น ๆ
- `AppMap` (`lib/core/map/app_map.dart`) **ไม่ได้แก้เลย** (ไฟล์อยู่ในรายการเป้าหมายของ requirements-round9.md แต่ `interactive`/`showZoomButtons`/`controller`/`onMyLocation` ที่ต้องใช้ทั้งหมดมีอยู่แล้วครบจากรอบก่อน ตามที่ tasks-round9.md ยืนยันไว้แล้วว่าไม่ต้องเพิ่ม API ใหม่) — ทั้ง T3 (route snapshot) และ T4 (full-bleed home map + recenter) ใช้ widget เดิมตรง ๆ ผ่าน `controller`/`markers` ที่มีอยู่แล้ว
- ไม่ได้รัน `flutter build apk`/`flutter build web` รอบนี้ (ไม่ได้ระบุใน AC ของรอบนี้ และเวลาจำกัด) — ตรวจแค่ `flutter analyze`/`flutter test` ตามที่ระบุไว้ใน AC ของ US-1/US-7

### จุดที่ทำไม่ได้ตาม spec 100% — ต้องส่งกลับให้ PM ตัดสิน/รับทราบ
1. **T4/US-2**: ไม่ได้ implement RC-6 "สวิตช์แคปซูล [🚗|🎒] ลอยมุมขวาบนของ Home โดยเฉพาะ" ตามตัวอักษร — ใช้กลไก `withRoleStrip`/`RoleModeBadge` เดิมที่ทำงานเทียบเท่า (แสดง+สลับ role) อยู่แล้วทั่วแอปแทน เพื่อลดความเสี่ยง regression จากการซิงก์ state 2 จุด ถ้าต้องการหน้าตาแคปซูลใหม่ตรงตามภาพจริง ๆ ต้องเป็นงานแยกที่ refactor `RoleStrip` หรือทำ capsule ใหม่ที่ผูกกับ provider เดียวกัน
2. **T4/US-2 (คำตัดสิน PM ข้อ 4)**: ยังไม่ได้ย้าย time-chip/role-segmented/dropoff selector ของ `QuickHomeCard._ready()` ไปไว้หลังการแตะช่องค้นหา (architecture option B ที่ PM สั่งไว้ชัดเจนแล้ว) — ไม่ได้แตะ `quick_home_card.dart` เลยในรอบนี้ (หมดเวลา) ผู้ใช้ที่มี preset ครบจะยังเห็น selector เต็มบนการ์ดเหมือนเดิม ไม่ตรง AC "ไม่มีกล่องซ้อนกล่อง" 100% สำหรับ state นี้โดยเฉพาะ — เป็นงานที่ต้องทำต่อรอบหน้า (มีความเสี่ยง regression สูงสุดของ T4 ตามที่ tasks-round9.md เตือนไว้แล้วล่วงหน้า)
3. **T7/US-5**: สถิติ 3 คอลัมน์ (คะแนนรีวิว/จำนวนทริป/CO₂) เป็น placeholder ล้วน ไม่มีของจริงแม้แต่คอลัมน์เดียว เพราะไม่พบ provider ที่อ่าน "ค่าสะสมของฉัน" ในระบบปัจจุบัน — ตามคำตัดสิน PM ข้อ 7 ไม่ใช่ blocker แต่ถ้าต้องการค่าจริงต้องมี aggregation query ใหม่ (ยังอยู่ใน UI/data-layer ได้ ไม่ต้องมี schema ใหม่) ที่ยังไม่ได้ลองทำในรอบนี้
4. **T1/US-7**: ถอด `AppColors.border` แบบตกแต่งได้ครบเฉพาะในไฟล์ของ 5 หน้า + `trip_widgets.dart`/`matching_widgets.dart` — ยังเหลือ `lib/core/widgets/role_badge.dart` (`SeatChip`) และ `lib/features/onboarding/presentation/onboarding_screen.dart` ที่ยังอ้าง `AppColors.border` อยู่ (นอกขอบเขตไฟล์เป้าหมายของรอบนี้) ถ้าต้องการถอดให้ครบ 100% ทั้งแอปต้องระบุเป็น scope เพิ่ม

### ผลตรวจ
- `flutter analyze` เต็มโปรเจกต์ (ไม่ใช่แค่ไฟล์ที่แก้): **"16 issues found" ทั้งหมดเป็น `info`** — 3 `prefer_const_constructors` ที่มีอยู่แล้วก่อนรอบนี้ (`tokens.dart:67-69`), 4 `deprecated_member_use` ที่มีอยู่แล้วก่อนรอบนี้ (`theme_settings_screen.dart`, `gender_settings_screen.dart` — ไม่ได้แตะไฟล์พวกนี้เลย), และ 9 `prefer_const_constructors` ใหม่ใน `me_tab.dart` (บรรทัดที่สร้าง `_RowData(...)` แบบไม่ใส่ `const`) — **ไม่มี error หรือ warning ใหม่เลยแม้แต่ตัวเดียว** (`prefer_const_constructors`/`deprecated_member_use` เป็น info-level severity ทั้งคู่) ตรงตาม AC ของ US-7/US-1 ("ไม่มี error/warning ใหม่")
- `flutter test` — **ยืนยันด้วยการทดลองแยกแล้วว่า test harness ของโปรเจกต์นี้เสียอยู่ก่อนรอบนี้แล้ว** ไม่ใช่สิ่งที่ round 9 ทำให้พัง: รัน `test/features/round6/presets_test.dart` (ไฟล์ที่**ไม่ได้แตะเลยในรอบนี้**) แยกเดี่ยว ๆ ก็ยัง fail จำนวนมาก (11 ผ่าน/26 fail) ด้วย exception เดียวกันทุกเคส (`UnimplementedError: init() has not been implemented` จาก `video_player_platform_interface` ที่ `SplashScreen.initState` — เหมือนกับที่ round 8 dev-notes เคยบันทึกไว้แล้วว่าเป็น pre-existing test-infra issue ไม่เกี่ยวกับโค้ดที่แก้ ดูหัวข้อ "T3 — BUG-3" ด้านบน) ยืนยันว่าปัญหานี้กว้างกว่าที่ round 8 เคยเจอ (ตอนนั้นเจอแค่ 15/134 ไฟล์ที่ใช้ `openApp()`; ตอนนี้ในสภาพแวดล้อมรันจริงดูเหมือนจะกระทบแทบทุกเทสต์ที่ผ่าน `buildTestApp()`/`openApp()` ซึ่งทุกไฟล์ผ่าน `SplashScreen` เสมอ) — **เป็นปัญหาของ sandbox/plugin registration ในสภาพแวดล้อมนี้ ไม่ใช่บั๊กที่ round 9 introduce** แต่ทำให้ไม่สามารถยืนยัน "flutter test ผ่านหมด" ได้จริงในรอบนี้
- สิ่งที่ยืนยันได้จริงก่อน test harness จะพัง: พบและแก้ 1 regression จริงระหว่างการตรวจ — `_CommuteInfoOverlay` (T3) มี `Row(mainAxisSize:min, children:[Icon,...,Text])` ไม่มี `Flexible`/`Wrap` ทำให้ overflow ที่ text scale 2.0 (`deck_test.dart` "layout at 390 px, text x2.0/x1.4" จับได้ก่อน harness จะพังไปเจอปัญหา video_player) — แก้แล้วเป็น `Wrap` (ดูหัวข้อ T3 ด้านบน)
- **แนะนำ QA/orchestrator**: ต้องแก้/mock `video_player` ของ test harness กลาง (`test/support/`) ก่อน ถึงจะรัน `flutter test` เต็มชุดแล้วเชื่อผลได้จริงอีกครั้ง — นี่คือ pre-existing infra debt ที่สะสมมาตั้งแต่ round 8 อย่างน้อย ไม่ใช่สิ่งที่ programmer คนเดียวควรแก้เองกลางรอบ UI-only เพราะอยู่นอก scope ที่ได้รับมอบหมาย แนะนำเปิด task แยก

### ไฟล์ที่แตะในรอบนี้
- `lib/core/theme/tokens.dart`, `lib/core/theme/tone.dart` (T1)
- `lib/core/widgets/global_verified_badge.dart` (ใหม่, T2)
- `lib/features/matching/presentation/matching_widgets.dart` (T1+T2)
- `lib/features/matching/presentation/commute_card_deck.dart` (T3)
- `lib/features/home/presentation/home_tab.dart` (T4, เขียนใหม่ทั้งไฟล์)
- `lib/features/chat/presentation/chats_tab.dart` (T5, เขียนใหม่ทั้งไฟล์)
- `lib/features/trip/presentation/trip_widgets.dart` (T6)
- `lib/features/profile/presentation/me_tab.dart` (T7)

## Round 9 — QA round 1 fixes

ตอบ 4 บั๊ก P0 ที่ QA ตีกลับใน `docs/qa-result.md` (รอบนี้คือรอบที่ 1) ทีละข้อ:

### 1. `QuickHomeCard._ready()` — ย้าย selector ที่ซับซ้อนไปหลังการแตะ (PM ruling ข้อ 4)
- ไฟล์: `lib/features/presets/presentation/quick_home_card.dart` (ที่ตั้งจริงคือ `lib/features/presets/...` ไม่ใช่ `lib/features/home/...` ตามที่ task อ้างถึง — เป็นไฟล์เดียวที่ตรงกับเนื้อหาที่ QA ชี้)
- `_ready()` เดิมทั้งหมด (time chip / role segmented / dropoff adjuster / register hint / switch-failed / error / active-trip banner / final create button) ถูกย้ายไปอยู่ในเมธอดใหม่ `_selectorsBody()` ที่เรียกผ่าน `_openSelectors()` (แสดงเป็น `showModalBottomSheet`) แทนที่จะ render อยู่บนการ์ดตลอดเวลา
- `_ready()` ตอนนี้แสดงพื้นผิวขั้นต่ำตาม AC 3 ส่วนเท่านั้น: (1) แถบ "ช่องค้นหา" ลักษณะ pill พร้อม placeholder `R6C.quickSearchPlaceholder` ("วันนี้กลับไหนดี?") — key `quick-search-field`, แตะแล้วเปิด sheet selector, (2) ชิปทางลัด 2 อัน key `quick-shortcut-home`/`quick-shortcut-work` (label `R6C.quickShortcutHome`/`quickShortcutWork` = "🏠 บ้าน"/"🏢 ที่ทำงาน") ที่เรียก action ที่มีอยู่แล้วในไฟล์เดิม (`context.push(Routes.mePlace(PresetKind.home.db))` / `.start.db)`) — ตัดสินใจ reuse action ที่มีอยู่แล้วแทนการเพิ่ม "ไปยังที่ทำงาน" เป็น trip type ใหม่ (ไม่มีอยู่ในโมเดล `PresetData`/`PlacePreset` เลย การเพิ่มจะเป็นการขยาย scope เกินบั๊กฟิกซ์รอบนี้), (3) ปุ่มหลักแคปซูลเดียว key `quick-primary-cta` (label `R6C.quickPrimaryCta` = "หาเพื่อนร่วมทาง") ที่เปิด sheet เดียวกัน
- ภายใน sheet (`_selectorsBody`): คง **ทุก Key/ข้อความ/logic เดิม 100%** ของ selector เดิม (`time-chip-*`, `quick-role`, `quick-dropoff`, `quick-dropoff-adjust`, `quick-register-hint`, `quick-register`, `quick-switch-error`, `quick-cta`, `quick-error`, `quick-go-active`, `quick-step-by-step`) — แค่ย้ายตำแหน่ง render เท่านั้น ปุ่มสร้างทริปจริงยัง key `quick-cta` เหมือนเดิม
- กลไก sync state ระหว่าง sheet กับ State เดิม: sheet ใช้ `StatefulBuilder` + helper `update(VoidCallback fn) { setState(fn); setSheet(() {}); }` (เขียน field ที่ State ของการ์ด แล้วสั่ง sheet rebuild ทันที) ตามแพทเทิร์นเดียวกับที่ `_adjustDropoff` เดิมใช้อยู่แล้ว (dual-update) — เพื่อให้ตัวเลือกที่ผู้ใช้เลือกค้างอยู่ได้แม้ปิด/เปิด sheet ใหม่ และให้ dropoff sheet ที่ซ้อนอยู่ข้างในซิงก์กลับมาถูกต้องหลังปิด (`await _adjustDropoff(dropoff); setSheet(() {});`)
- สตริงใหม่เพิ่มใน `lib/core/l10n/strings_r6_cd.dart` (คลาส `R6C`): `quickSearchPlaceholder`, `quickShortcutHome`, `quickShortcutWork`, `quickPrimaryCta`, `quickSelectorsTitle`, `quickSearchSemantics(route)` — ไม่แตะสตริงเดิมที่มีอยู่แล้วเลย
- **ผลกระทบต่อเทสต์เดิมที่ต้องแจ้ง Tester**: เทสต์ใดที่เคย pump แล้วหา `quick-cta`/`quick-role`/time-chip ฯลฯ ทันทีบนหน้า (ไม่ผ่านการแตะ `quick-search-field`/`quick-primary-cta` ก่อน) จะหา widget เหล่านั้นไม่เจอแล้ว เพราะต้องแตะเปิด sheet ก่อนเสมอ — เป็นผลลัพธ์ที่ตั้งใจตาม PM ruling ข้อ 4 ไม่ใช่ regression

### 2. Home header — RoleSwitchCapsule ลอยจริงแทน `withRoleStrip`
- ไฟล์: `lib/features/home/presentation/home_tab.dart`
- เอา `withRoleStrip(...)` ออกจาก `HomeTab.build()` (เหลือ `Stack` ตรง ๆ) — RoleStrip แบบแถบใต้ AppBar เดิมไม่ใช้กับ Home อีกต่อไปตามที่ RC-6 ระบุตำแหน่งใหม่ชัดเจน (การถอดออกกระทบแค่ Home tab เพราะ `withRoleStrip`/`RoleStrip` ยังอยู่ให้แท็บอื่นใช้ต่อได้ตามเดิม ไม่ได้ลบไฟล์ `role_strip.dart`)
- เพิ่ม widget ใหม่ `_RoleSwitchCapsule` (ConsumerWidget) ต่อท้ายไฟล์เดิม วางในแถว header ลอยฝั่งขวา (ก่อนปุ่มโล่ safety เดิม) — แคปซูลทึบโปร่งแสงดำ (`Colors.black.withValues(alpha:0.35)`, `StadiumBorder`) มี 2 segment `[🚗 คนขับ | 🎒 คนนั่ง]` (icon `drive_eta`/`event_seat` + label `D.roleWordDriver`/`D.roleWordRider`) — segment ที่ active มีพื้นขาวทึบตัดกับพื้นแคปซูลโปร่งแสงเพื่อ contrast >=4.5:1 บนแผนที่ทุกสี ตาม RC-6 A11y note
- Tap ฝั่งที่ยังไม่ active เรียก `performRoleSwitch(context, ref, role)` ตัวเดิมจาก `role_strip.dart` ตรง ๆ (import แบบ `show performRoleSwitch` เท่านั้น ไม่ import `withRoleStrip`/`RoleModeBadge` อีก) — ไม่แตะ provider/switching logic เดิมเลยสักบรรทัด ตามที่ task กำหนด
- States: `switching` โชว์ spinner เล็กแทนไอคอนเฉพาะ segment เป้าหมาย (`s.switching.target`), unregistered driver (`s.registered != true`) → segment คนขับกด tap ไม่ได้ (ไม่ error, sheet/snackbar เดิมของ `performRoleSwitch` จัดการ error case อยู่แล้วเหมือนเดิม)
- Key ใหม่: `home-role-capsule-driver`, `home-role-capsule-rider`
- เพิ่ม import `strings_dual.dart` (ใช้ `D.roleWordDriver/roleWordRider/a11yModeCurrent`), `role_state.dart`, `role_providers.dart`

### 3. BUG-QA9-1 — `tone_contrast_test.dart:90` ค่าสีเก่าค้าง
- ไฟล์: `test/features/dual/tone_contrast_test.dart` บรรทัด 90 — เปลี่ยน `expect(r.scaffoldBackgroundColor, const Color(0xFFF7FAFC))` เป็น `const Color(0xFFF8F9FC)` ให้ตรงกับ token ที่เปลี่ยนไปแล้วใน T1 ของรอบก่อนหน้า
- ยืนยันด้วยการรันไฟล์นี้แยกเดี่ยว: **50/50 ผ่านทั้งหมด** (ไม่ผ่าน `SplashScreen`/`video_player` เลยตามที่ QA ยืนยันไว้ว่ารันคนเดียวได้สะอาด)

### 4. BUG-QA9-2 — `HomeTab._animateTo` ไม่เช็ค reduced-motion
- ไฟล์: `lib/features/home/presentation/home_tab.dart` — `_animateTo()` เพิ่มเช็ค `MediaQuery.disableAnimationsOf(context)` เป็นบรรทัดแรก: ถ้าเปิด reduced-motion จะ dispose animation controller เก่า (ถ้ามี), เรียก `_mapController.move(target, _kGpsZoom)` ทันทีแบบไม่มี tween แล้ว `setState(() => _me = target)` แล้ว return ทันที — ไม่สร้าง `AnimationController`/`CurvedAnimation` เลยเมื่ออยู่ในโหมดนี้ ตรงกับแพทเทิร์นเดียวกับ `_PulseDot` ในไฟล์เดียวกัน (เช็คก่อน `_c.repeat(...)`) และ `DeckSwipeCardState`/`AnimatedSwitcher` ใน `commute_card_deck.dart`
- ระวัง bug แฝงที่แก้พร้อมกัน: เส้นทาง animate ปกติต้องอ่าน `fromCenter`/`fromZoom` **ก่อน** `setState(_me = target)` เสมอ (ย้าย `setState` ไปไว้หลัง `_anim = c;` เหมือนเดิม) มิเช่นนั้น `_me` จะกลายเป็น `target` ไปแล้วตั้งแต่ก่อนคำนวณจุดเริ่ม ทำให้ animation เริ่ม-จบที่จุดเดียวกัน (ไม่ขยับ) — คนละบั๊กกับที่ QA รายงาน แต่เป็นจุดเสี่ยงที่เกิดขึ้นได้ง่ายระหว่างแก้ reduce-motion จึงเขียนลำดับให้ถูกไว้ตั้งแต่แรก

### ผลตรวจรอบนี้
- `flutter analyze` ทั้งโปรเจกต์: ยังคง 16 issues เดิมทั้งหมด (info-level, pre-existing) — **ไม่มี error/warning ใหม่จาก 4 จุดที่แก้**
- `flutter analyze` เจาะจงไฟล์ที่แก้ (`quick_home_card.dart`, `home_tab.dart`, `strings_r6_cd.dart`): No issues found
- `flutter test test/features/dual/tone_contrast_test.dart`: 50/50 passed
- ยืนยัน tone token ที่ใช้ใน `quick_home_card.dart`/`home_tab.dart` ใหม่ (`tone.bg`, `tone.border`, `tone.textSecondary`) มีนิยามอยู่ครบทั้ง 4 variant (rider/driver/riderDark/driverDark) ใน `lib/core/theme/tone.dart` แล้วก่อนหน้านี้ — ไม่ต้องเพิ่ม token ใหม่
- ไม่ได้รัน widget test แบบ end-to-end ของ `HomeTab`/`QuickHomeCard` เพราะไม่มีเทสต์เดิมที่อ้างถึง widget เหล่านี้โดยตรง (grep แล้วไม่พบ) และการเปิด harness ผ่าน `openApp()`/`SplashScreen` ยังติดปัญหา `video_player` เดิมตามที่บันทึกไว้ใน dev-notes รอบก่อน (pre-existing, นอกขอบเขตรอบนี้) — ยืนยันความถูกต้องด้วย `flutter analyze` (compile-level) + การอ่านโค้ดตรวจ logic ซ้ำแทน

### ไฟล์ที่แตะเพิ่มในรอบนี้ (QA round 1 fix)
- `lib/features/presets/presentation/quick_home_card.dart` (บั๊ก #1)
- `lib/features/home/presentation/home_tab.dart` (บั๊ก #2, #4)
- `lib/core/l10n/strings_r6_cd.dart` (สตริงใหม่สำหรับบั๊ก #1)
- `test/features/dual/tone_contrast_test.dart` (บั๊ก #3)
- `test/features/qa_round1_test.dart` (อัปเดตเทสต์ตาม T2)

## Round 9 — P1 follow-up fixes

แก้ 2 ข้อค้นพบ P1 ที่ QA รอบ 2 (`docs/qa-result.md`) ปล่อยผ่านแบบ PASS with notes พร้อมสั่งส่งกลับ programmer:

### 1. Test debt — `dual_widgets_test.dart` ยัง assert `role-strip` บน Home tab
- ไฟล์: `test/features/dual/dual_widgets_test.dart`
- root cause (ตาม QA): Home tab เปลี่ยนจาก `withRoleStrip` เป็น `_RoleSwitchCapsule` (RC-6, key `home-role-capsule-driver`/`-rider`) ไปแล้วตั้งแต่บั๊ก #2 ของรอบก่อน แต่เทสต์เก่ายังอ้าง key `role-strip`/`role-switch` และสตริง `D.modeRider`/`D.modeDriver`/`D.switchToDriver`/`D.switchToRider` (ที่มีแค่บน `RoleStrip`, ไม่ใช่บน capsule ซึ่งใช้ `D.roleWordRider`/`D.roleWordDriver` แทน) บน Home tab ซึ่งเป็น default tab ของ `_open()`/`openApp()`
- แก้เฉพาะจุดที่อ้างถึง Home tab (ยืนยันด้วยการไล่โค้ด default-tab ของแต่ละเทสต์ทีละเคส ไม่ใช่ blanket-replace):
  - กลุ่ม `'role strip + 1-tap switch (US-20)'`: 2 เทสต์แรก (เดิมบรรทัด 62-87) เปลี่ยนไปเช็ค `home-role-capsule-driver`/`-rider` + แตะ capsule โดยตรงแทน `role-switch` (ตัด assertion ข้อความ `D.modeRider`/`D.modeDriver`/`D.switchToDriver`/`D.switchToRider` ที่ไม่มีอยู่บน capsule ออก เหลือแค่ snackbar `D.switchedDriver`/`D.switchedRider` ที่ยังมีจริงหลังสลับ role)
  - เทสต์ "the strip is on all 5 shell tabs..." เปลี่ยนเป็นเช็ค capsule keys สำหรับ Home ก่อน แล้ว loop เฉพาะ 4 แท็บที่เหลือ (Nearby/Chats/Trips/Me) สำหรับ `role-strip` — ส่วนที่เหลือของเทสต์ (fail switch, `role-switch`, `mode-badge-rider`) ไม่ต้องแก้เพราะจบ loop อยู่ที่ Me tab (มี `role-strip`/`role-switch` จริง)
  - เทสต์ "unregistered account" เปลี่ยน `find.text(D.modeRider)` เป็น `find.byKey(home-role-capsule-rider)`
  - เทสต์ "a mode the server no longer allows is reconciled..." เปลี่ยน `role-strip`/`D.modeRider` เป็น `home-role-capsule-rider`
  - กลุ่ม `'trip screens keep the tone of the TRIP role'`: เทสต์แรก (เดิมบรรทัด 202) เปลี่ยน `role-strip` เป็น `home-role-capsule-driver` (app-level Home tone check ก่อนเข้า trip detail)
  - **ไม่แตะ** `role-strip` ใน 3 จุดที่เหลือของไฟล์ (registration full-screen `findsNothing`, unregister-confirm test) เพราะทั้งหมดอยู่บนแท็บอื่น (Me tab หรือหน้า registration) ที่ยังใช้ `withRoleStrip` จริงตามที่ QA ยืนยันว่าถูกต้องอยู่แล้ว
- **ยังบล็อกด้วยปัญหาเดิม**: รันไฟล์นี้แยกยังคง 0/38 ผ่าน เพราะ `SplashScreen`'s `video_player` `UnimplementedError` บังอยู่ก่อนถึงจุด assert เสมอ (pre-existing test-infra gap ตามที่ QA ยืนยันไว้แล้วในหลายรอบ ไม่ใช่สิ่งที่ต้องแก้ในงานนี้) — แก้ไขนี้เป็นการเตรียมเทสต์ให้ถูกต้องล่วงหน้า ป้องกัน false failure จำนวนมากเมื่อ video_player mock ถูกทำสำเร็จในอนาคต ตามที่ QA ร้องขอ

### 2. `_PulseDotState.initState()` เรียก `MediaQuery.disableAnimationsOf` ผิดจังหวะ lifecycle
- ไฟล์: `lib/features/home/presentation/home_tab.dart` (`_PulseDotState`)
- เดิม: `initState()` เรียก `MediaQuery.disableAnimationsOf(context)` (InheritedWidget lookup) ก่อน `initState()` return — ผิดหลัก Flutter lifecycle, throw `FlutterError` assertion (`dependOnInheritedWidgetOfExactType()`/`dependOnInheritedElement()` called before initState() completed) ทุกครั้งที่ `_PulseDot` ถูก build (เช่นตอนมี GPS marker บนแผนที่ Home)
- แก้: ย้าย `AnimationController` creation ไว้ใน `initState()` เหมือนเดิม แต่ย้ายเฉพาะ `MediaQuery.disableAnimationsOf(context)` + `_c.repeat(...)` ไปไว้ใน `didChangeDependencies()` แทน (จุดที่ถูกต้องสำหรับการอ่าน InheritedWidget ครั้งแรกตามเอกสาร Flutter) — เพิ่ม flag `_animationStarted` กันไม่ให้ `_c.repeat(...)` ถูกเรียกซ้ำทุกครั้งที่ `didChangeDependencies()` ถูกเรียกใหม่ (เช่น text-scale/orientation เปลี่ยน) เพราะจะรีสตาร์ท pulse animation โดยไม่ตั้งใจ
- ไม่มี precedent เดิมในโค้ดเบสที่ใช้ `didChangeDependencies()` มาก่อน (grep แล้วไม่พบ) จึงใช้ pattern มาตรฐานของ Flutter เอง (guard flag) แทนการ "คิดค้น pattern ใหม่" ที่ซับซ้อนกว่าที่จำเป็น
- **ยืนยันผลแก้**: รัน `flutter test test/features/p4/lifecycle_test.dart` และ `test/demo/demo_roles_test.dart` แยกเดี่ยว — `grep -c "dependOnInheritedWidgetOfExactType"` = 0 ทั้งสองไฟล์ (เดิมมี assertion error นี้ซ้ำหลายครั้งตามที่ Tester รายงานไว้ใน `docs/test-report.md`) ยืนยันว่าบั๊กถูกแก้จริง — ทั้งสองไฟล์ยังคง fail ด้วย `UnimplementedError`/`video_player` เดิมอยู่ (out of scope ตามที่ระบุไว้ในงานนี้ ไม่ใช่สิ่งที่ต้องแก้)

### ผลตรวจหลังแก้ทั้ง 2 จุด
- `flutter analyze` ทั้งโปรเจกต์: ยังคง 16 unique info-level issues เดิม (pre-existing) — ไม่มี error/warning ใหม่
- `flutter test test/features/dual/tone_contrast_test.dart`: 50/50 passed (ไม่มี regression)
- `flutter test test/features/dual/dual_widgets_test.dart`: ยังคง 0/38 (บล็อกโดย video_player harness เดิม ตามที่คาด — ไม่ใช่ regression ใหม่จากการแก้ครั้งนี้)
- `flutter test test/features/p4/lifecycle_test.dart` และ `test/demo/demo_roles_test.dart`: ทุกความล้มเหลวที่เหลือเป็น `UnimplementedError` (video_player) ล้วน ไม่มี `dependOnInheritedWidgetOfExactType` assertion หลงเหลือแล้ว — ยืนยันบั๊ก #2 ถูกแก้จริง

### ไฟล์ที่แตะในรอบ follow-up นี้
- `test/features/dual/dual_widgets_test.dart` (P1 follow-up #1)
- `lib/features/home/presentation/home_tab.dart` (P1 follow-up #2)

---

## Bug fix: OSRM/Nominatim `User-Agent` header breaks routing on web build

- ปัญหาที่ยืนยันแล้ว: หน้าสร้างทริปขึ้น "คำนวณเส้นทางไม่ได้ในตอนนี้ ลองใหม่อีกครั้ง" ทุกครั้งบน Flutter **web build** เท่านั้น (native ปกติ) ทั้งที่เน็ตใช้งานได้และยิง OSRM endpoint ตรง ๆ ด้วย GET เปล่าได้ 200 — root cause คือทั้ง 3 ไฟล์ตั้ง header `User-Agent` เองในทุก `http.Client.get()` ซึ่งบนเบราว์เซอร์ตั้งค่าไม่ได้ (forbidden header ตาม Fetch spec) หรือทำให้บางเอนจิน mobile browser trigger CORS preflight (OPTIONS) ที่เซิร์ฟเวอร์ปฏิเสธเพราะ `Access-Control-Allow-Headers` ไม่มี `User-Agent`
- แก้: ห่อ header `'User-Agent': _cfg.userAgent` ด้วย `if (!kIsWeb)` (จาก `package:flutter/foundation.dart`) ใน 3 ไฟล์ — `lib/features/geo/data/osrm_routing.dart`, `lib/features/geo/data/osrm_road_snap.dart`, `lib/features/geo/data/nominatim_geocoding.dart` (ไฟล์นี้ยังส่ง `'Accept-Language': 'th'` เหมือนเดิมไม่มีเงื่อนไข เพราะ CORS-safelisted อยู่แล้ว ไม่เกี่ยวกับบั๊กนี้)
- เฉพาะ web build เท่านั้นที่เปลี่ยนพฤติกรรม: native (Android/iOS/desktop) ยังส่ง `User-Agent` ตามเดิมทุกครั้ง (ตามนโยบายการใช้งาน OSM ที่ต้องมี UA ระบุตัวตนได้)
- ตรวจแล้ว: `flutter analyze` บน 3 ไฟล์ที่แก้ — ไม่มี issue; `flutter test test/features/geo/osrm_road_snap_test.dart test/features/geo/services_test.dart` 22 ผ่านทั้งหมด (รวมเทสต์ที่เช็คว่ายังส่ง UA บน non-web test VM); รัน widget tests ที่กว้างกว่า (`trip_flow_test.dart`, `detour_tolerance_test.dart`, `dropoff_limit_test.dart`) พบ failures 21 รายการ — ยืนยันแล้วว่าเป็น pre-existing (รันซ้ำด้วยโค้ดเดิมก่อนแก้ก็ fail เหมือนกันทุกตัว ไม่ใช่ regression จากการแก้นี้)

---

## Bug fix: "หาตำแหน่งปัจจุบันไม่ได้" บน web build เข้าผ่าน HTTP + LAN IP (ไม่ใช่ localhost/HTTPS)

### การสืบสวน root cause
- อาการ: บน Safari มือถือ เข้าแอปผ่าน `http://172.20.10.7:8765` (LAN IP ธรรมดา ไม่ใช่ localhost, ไม่ใช่ HTTPS) แม้กด "อนุญาต" ตอนขอสิทธิ์ตำแหน่งแล้ว กดปุ่ม "ใช้ตำแหน่งปัจจุบัน" ก็ยังเจอ error เดิมทุกครั้ง: `FailureCode.locationUnavailable` ("หาตำแหน่งปัจจุบันไม่ได้ ลองใหม่หรือปักหมุดแทน")
- ไล่โค้ดจริงยืนยันแล้ว (ไม่ใช่แค่สมมติฐาน "GPS ช้า"):
  1. `lib/features/geo/presentation/current_location.dart` `obtainCurrentLocation()`: เรียก `loc.permission()` ก่อน ถ้า `granted` อยู่แล้ว (กรณีผู้ใช้กด "อนุญาต" ไปแล้วในรอบก่อนหน้า) จะข้าม consent dialog ไปเรียก `loc.currentPosition()` ตรง ๆ
  2. `package:geolocator_web` (`html_permissions_manager.dart`) ใช้ `navigator.permissions.query({name:'geolocation'})` สำหรับ `checkPermission()` — API นี้ไม่ได้ถูกบล็อกโดย secure-context เหมือนกับ `navigator.geolocation` ตัวจริง จึงสามารถรายงาน `granted` ได้แม้ origin เป็น `http://` ธรรมดา (ไม่ใช่ localhost) — นี่คือจุดที่ error message เดิมสับสนให้ดูเหมือน "มีสิทธิ์แล้วแต่หาตำแหน่งไม่ได้"
  3. แต่พอเรียก `_geolocation.getCurrentPosition()` จริง (`html_geolocation_manager.dart`) เบราว์เซอร์จะปฏิเสธทันทีด้วย `GeolocationPositionError.code == 1` (PERMISSION_DENIED) เพราะ **`navigator.geolocation` เป็น API ที่ถูกจำกัดด้วย secure context จริง ๆ** (ต้องเป็น `https://` หรือ `localhost`/`127.0.0.1` เท่านั้น — เป็นข้อจำกัดด้านความปลอดภัยของเบราว์เซอร์เอง ไม่ใช่สิ่งที่โค้ดแอปแก้ไขให้ทำงานได้) — ยืนยันจาก `geolocator_web-4.1.4/lib/src/utils.dart` `convertPositionError()` ที่แปลง code 1 เป็น `PermissionDeniedException`
  4. เดิม `lib/features/geo/data/geolocator_location_service.dart` `currentPosition()` มีแค่ `on TimeoutException` กับ `catch (_)` รวบทุก exception (รวมถึง `PermissionDeniedException` จากข้อ 3) เป็น `FailureCode.locationUnavailable` ข้อความเดียวกันหมด — ไม่แยกสาเหตุ "insecure origin" ออกจาก timeout/GPS จริง ตรงกับที่ task สมมติฐานไว้
- สรุป root cause ที่ยืนยันแล้ว: **เบราว์เซอร์บล็อก `navigator.geolocation` เพราะ origin เป็น HTTP ธรรมดาที่ไม่ใช่ localhost** — ไม่ใช่ GPS ช้าหรือ permission จริง ๆ ถูกปฏิเสธ

### การแก้ไข
ตามที่ task ระบุ: เขียน workaround ให้ HTTP ธรรมดาใช้ geolocation ได้ไม่ได้จริง (เป็น browser security boundary) จึงแก้ด้วยการ **ตรวจจับ insecure origin ล่วงหน้าแล้วแสดงข้อความที่ตรงกับสาเหตุจริง**:
- `lib/core/error/app_failure.dart`: เพิ่ม `FailureCode.locationInsecureOrigin = 'LOCATION_INSECURE_ORIGIN'`
- `lib/core/error/failure_messages.dart`: เพิ่มข้อความ `'ต้องเปิดผ่าน HTTPS หรือ localhost เพื่อใช้ตำแหน่งปัจจุบันบนเว็บ ลองปักหมุดเองแทน'`
- `lib/features/geo/data/geolocator_location_service.dart`:
  - เพิ่ม `static bool get _isInsecureWebOrigin` เช็ค `kIsWeb && Uri.base.scheme != 'https' && Uri.base.host` ไม่ใช่ `localhost`/`127.0.0.1`/`::1`/`[::1]`
  - `currentPosition()`: เช็คเงื่อนไขนี้เป็นอันดับแรก ก่อน try เรียก `Geolocator.getCurrentPosition()` เลย — ถ้าตรง คืน `Err(AppFailure(FailureCode.locationInsecureOrigin))` ทันทีโดยไม่ต้องรอ native call ล้มเหลว
  - เพิ่ม `on PermissionDeniedException` แยกจาก `catch (_)` เดิม คืน `FailureCode.locationDenied` แทน `locationUnavailable` เป็น fallback เผื่อกรณีเช็ค origin พลาด (เช่น environment ที่ `Uri.base` ไม่ตรงกับพฤติกรรมเบราว์เซอร์จริง) — อย่างน้อยก็ไม่เข้าใจผิดว่าเป็น "หาตำแหน่งไม่ได้" ทั่วไป
- **ไม่แตะ** `permission()`/`request()` หรือ `LocationPermissionState` enum: เส้นทางที่ยืนยันแล้วจากอาการจริงของ user (กด "อนุญาต" ไปแล้ว → ข้าม consent dialog → เรียก `currentPosition()` ตรง) ถูกแก้ครบแล้วด้วยจุดเดียวนี้ การแก้ enum/permission() เพิ่มจะมีความเสี่ยง ripple effect กว้าง (หลาย call site, หลาย test) โดยไม่จำเป็นกับอาการที่รายงาน

### จุดที่ยังไม่ perfect (ไม่กระทบอาการที่รายงาน แจ้งไว้เผื่อ PM ต้องการ follow-up)
- ถ้าเป็นการกดปุ่มครั้งแรกสุด (ยังไม่เคยอนุญาตมาก่อน, `permission()` คืน `denied`) บน insecure origin: flow จะไปโชว์ consent dialog ก่อน แล้ว `request()` จะเรียก `Geolocator.requestPermission()` ซึ่งบน web (`geolocator_web.dart` `requestPermission()`) catch ทุก exception แล้วคืน `LocationPermission.deniedForever` เสมอ — UI จะไปโชว์ข้อความ `T.locOpenSettings` ("เปิดตำแหน่งในการตั้งค่าของเครื่อง...") แทนที่จะเป็นข้อความ HTTPS ที่เจาะจงกว่า ข้อความนี้ไม่ผิด (เพราะ deniedForever ก็จริงในแง่ที่เบราว์เซอร์ปฏิเสธถาวรสำหรับ origin นี้) แต่ไม่ได้อธิบายสาเหตุ HTTPS ให้ชัดเท่ากรณีที่แก้ไปแล้ว — ไม่ใช่สิ่งที่ user รายงานในบั๊กนี้ (user ยืนยันว่า "กด 'อนุญาต' แล้ว" ก่อนเจอ error) จึงไม่แก้เพิ่มในรอบนี้ตามขอบเขตที่ได้รับ

### ผลตรวจหลังแก้
- `flutter analyze lib/features/geo lib/core/error`: No issues found
- `flutter test test/features/geo/geolocator_location_service_test.dart`: 10/10 passed (รันบน non-web test VM, `kIsWeb == false` เสมอ จึง `_isInsecureWebOrigin` เป็น `false` ตลอด — path เดิมไม่เปลี่ยนพฤติกรรม ไม่มี regression)
- `flutter test test/qa/contract_and_safety_test.dart`: 14/14 passed (เช็ค "ทุก GWM_ code มีข้อความไทย" ไม่กระทบ เพราะโค้ดใหม่ไม่ใช่ `GWM_*` prefix)

### ไฟล์ที่แตะ
- `lib/core/error/app_failure.dart`
- `lib/core/error/failure_messages.dart`
- `lib/features/geo/data/geolocator_location_service.dart`
