# Task List — RECONSTRUCTION DRAFT (docs/tasks-RECOVERED.md)

> **หมายเหตุสถานะไฟล์นี้**
> ไฟล์นี้คือ **การกู้คืนโดยการอนุมาน (reconstruction)** ของส่วนที่หายไปจาก `docs/tasks.md` (เหตุการณ์ Write ทับไฟล์ระหว่าง Round 9) ไม่ใช่การกู้คืนของจริง — ไม่มี git/OneDrive version history/editor local-history ให้ใช้กู้คืน 100% ได้
>
> วิธีสร้างเอกสารนี้: (1) คัดลอกส่วนที่ **ยังอยู่ครบใน `docs/tasks.md` ปัจจุบัน** มาเก็บไว้เหมือนเดิมทุกตัวอักษร (ไม่มีป้ายกำกับ derivation เพิ่ม) (2) เติมส่วนที่หายไปด้วยการอนุมานจาก `docs/dev-notes.md` (มี task ID อ้างอิงเกือบทุกจุดที่ทำเสร็จจริง), `docs/requirements-round5.md`, `docs/tasks-round6.md` (หัวข้อสรุปต้นไฟล์), และโครงสร้างโค้ดจริงใน `lib/features/*` (3) **รอบตรวจทานที่สอง**: cross-check เนื้อหาที่อนุมานของรอบ 3 (Driver/Rider) และรอบ 4 (Dual-role) กับโค้ดจริง (`lib/features/roles/`, `lib/features/vehicle/`, `lib/features/matching/presentation/pickup_screen.dart`) เพราะเป็น core feature ที่ใช้งานจริงในแอปวันนี้ — ดูหัวข้อ "ผลตรวจสอบกับโค้ดจริง (รอบ 2 ของการกู้คืน)" ในแต่ละส่วนที่เกี่ยวข้องด้านล่าง
> ทุกส่วนที่เติมจะมีป้าย `[RECONSTRUCTED FROM: ...]` กำกับไว้เสมอ — ห้ามถือว่าข้อความ/ID/ขนาด task ที่เติมนี้ถูกต้อง 100% โดยเฉพาะตัวเลข ID ที่ dev-notes ไม่ได้พูดถึงตรง ๆ (ทำเครื่องหมาย "ไม่ทราบ ID แน่ชัด" ไว้ชัดเจน)
> ใช้เอกสารนี้เป็น **ข้อมูลอ้างอิงชั่วคราว** เท่านั้น ห้ามใช้แทน `docs/tasks.md` จริงจนกว่าทีมจะตรวจทานและย้ายเนื้อหาที่ยืนยันแล้วกลับเข้า `docs/tasks.md` อย่างเป็นทางการ

---

# Task List: กลับด้วยกันมั้ย (GOWITHME) MVP 0.1

## กติกาอ่านเอกสารนี้
- ลำดับตาม Roadmap 5 เฟส: 1 Setup -> 2 UI พื้นฐาน -> 3 ข้อมูล+จับคู่ -> 4 ฟีเจอร์หลัก -> 5 ทดสอบ/ปรับปรุง
- ขนาด: S = ไม่เกินครึ่งวัน, M = 1-2 วัน, L = 3 วันขึ้นไป (Programmer แตกย่อยเองได้ แต่ห้ามข้ามเกณฑ์ยอมรับ)
- Stack: Flutter + Riverpod + go_router + flutter_map + supabase_flutter, feature-first (data/domain/presentation)
- **เอกสารออกแบบที่จะตามมา (Programmer ต้องทำตามอย่างเคร่งครัด):**
  - docs/design-db.md (schema, index, migration) -> กำหนด T3.x ด้านข้อมูล
  - docs/design-api.md (RPC/endpoint, realtime, สัญญา request/response) -> กำหนด data layer และสูตรจับคู่ฝั่งเซิร์ฟเวอร์
  - docs/design-security.md (RLS, การทำให้ตำแหน่งคลาดเคลื่อน, token แชร์, retention) -> กำหนด T3.x/T4.x ด้านสิทธิ์
  - docs/design-spec.md (UIUX: theme, ส่วนประกอบ, หน้าจอ) -> กำหนดทุก task ที่เป็น presentation
  - Task ที่มีสัญลักษณ์ [รอ DB] [รอ API] [รอ SEC] [รอ UX] ห้ามเริ่มเขียนโค้ดจริงจนกว่าเอกสารนั้นจะออก (เตรียมโครง/interface ได้)
  - หากเอกสารออกแบบขัดกับ requirements.md ให้แจ้ง orchestrator เพื่อเรียก PM ตัดสิน ห้ามตีความเอง

---

## เฟส 1: Setup โปรเจกต์
(verbatim จาก docs/tasks.md ปัจจุบัน — ส่วนนี้ไม่ได้สูญหาย ครบทั้ง P0/P1 อยู่แล้ว ไม่ต้องกู้คืนเพิ่ม)

### P0
- T1.1: สร้างโปรเจกต์ Flutter (iOS+Android), เพิ่ม dependency ..., เปิด lint เข้ม — size S — dependency: ไม่มี
- T1.2: วางโครงโฟลเดอร์ feature-first ... — size S — dependency: T1.1
- T1.3: ระบบ config อ่าน SUPABASE_URL/SUPABASE_ANON_KEY ... — size S — dependency: T1.1
- T1.4: Riverpod bootstrap ... — size S — dependency: T1.2, T1.3
- T1.5: นโยบาย logging ... — size S — dependency: T1.4
- T1.6: ตั้งค่า permission แพลตฟอร์ม ... — size S — dependency: T1.1
- T1.7: config จุดเดียวสำหรับ endpoint/threshold ... — size S — dependency: T1.4

### P1
- T1.8: โครงสร้าง l10n (ARB) ... — size S — dependency: T1.4

(รายละเอียดเต็มดู docs/tasks.md บรรทัด 28-40 — คงอยู่ครบ ไม่ต้องอนุมานใหม่)

---

## เฟส 2: UI พื้นฐาน

### P0 (T2.1-T2.5 verbatim จาก docs/tasks.md ปัจจุบัน)
- T2.1: [รอ UX] Theme + design tokens — size M — dependency: T1.4, design-spec.md
- T2.2: [รอ UX] shared widgets — size M — dependency: T2.1
- T2.3: [รอ UX] Splash + Onboarding 3 หน้า — size M — dependency: T2.1, T1.4
- T2.4: [รอ UX] Widget แผนที่กลาง (flutter_map) — size M — dependency: T2.1, T1.7
- T2.5: [รอ UX] Home shell + navigation — size M — dependency: T2.2, T2.4

### P0 (ส่วนที่เติม) `[RECONSTRUCTED FROM: docs/dev-notes.md L17 "T2.6" section "Phase 1-2"]`
- [ ] T2.6: Router guard/redirect pipeline (`core/router/redirect.dart`, ฟังก์ชัน pure `computeRedirect` มีเทสต์แยก) ลำดับ: config error -> booting/splash -> onboarding -> sign-in -> verify-email -> setup/profile -> home; ผูกกับ auth state จริง (ไม่ใช่ stub) — size S — dependency: T2.3, T2.5, T1.4 (ยืนยันจาก dev-notes: "T2.6 — core/router/redirect.dart ... ผูกกับ auth จริงเลย")

**หมายเหตุความไม่แน่นอน:** dev-notes ระบุ T2.6 ชัดเจนเป็นงานที่ทำเสร็จในช่วง Phase 1-2 แต่ไม่ยืนยันว่าอยู่ P0 หรือ P1 ของเฟส 2 เดิม — จัดเป็น P0 เพราะเป็น blocking path ของทุกหน้าจอ (สมเหตุสมผลสูง)

ไม่พบหลักฐานของ P1/P2 เพิ่มเติมในเฟส 2 นอกเหนือจาก T2.6 — เป็นไปได้ว่าเฟส 2 เดิมจบที่ T2.5/T2.6 และงานหน้าจอ auth (sign-up/sign-in/verify-email) ถูกเลขเป็น T3.4/T3.5/T4.28 (เห็นได้จาก dev-notes บรรทัด 18 "T3.4/T3.5 (ส่วน client เท่านั้น) + T4.28 — sign-up, sign-in, verify-email, profile setup stub, /policy /terms placeholder") ซึ่งบ่งชี้ว่า flow บัญชีผู้ใช้ถูกจัดไว้ในเฟส 3/4 ไม่ใช่เฟส 2

---

## เฟส 3: ข้อมูล + จับคู่

`[RECONSTRUCTED FROM: docs/dev-notes.md "Phase 3" section L54-82, และ QA-round1 section L146-168 ที่อ้างถึง T3.x]`

**คำเตือนสำคัญ:** เลข ID ของเฟสนี้ไม่ต่อเนื่องสมบูรณ์ในหลักฐานที่มี (เช่น เห็น T3.4, T3.5, T3.6, T3.7, T3.9, T3.10, T3.14, T3.19, T3.23, T3.27 แต่ไม่เห็น T3.1-T3.3, T3.8, T3.11-T3.13, T3.15-T3.18, T3.20-T3.22, T3.24-T3.26 เลยในเอกสารที่ค้นหาได้) — ช่องว่างเหล่านี้อาจเป็นงานที่ยังไม่ถูกหยิบมาพูดถึงใน dev-notes (เช่น งาน backend/design ล้วนที่ programmer ไม่ log) ไม่ใช่ว่าไม่เคยมี ให้ถือว่า **ไม่ทราบเนื้อหาของ ID ที่ขาดหายไปเหล่านี้จริง ๆ**

### P0 (เท่าที่ยืนยันได้จาก dev-notes)
- [ ] T3.4: [รอ API][รอ SEC] หน้า sign-up (ชื่อ, อีเมล, รหัสผ่าน >= 8, checkbox ยืนยันอายุ 18+ และยอมรับนโยบาย, ปุ่มปิดจนกว่าครบ, error ใต้ช่อง, banner เครือข่าย) — size M — dependency: T2.2, T1.4 (อ้างอิง US-2)
- [ ] T3.5: [รอ API] หน้า sign-in (ข้อความ error ทั่วไปเดียว ไม่บอกว่าอีเมล/รหัสผ่านผิดจุดไหน), หน้า verify-email (ส่งซ้ำ + cooldown 60 วิ) — size S — dependency: T3.4 (US-2)
- [ ] T3.6: หน้า consent/ความยินยอมเต็มรูปแบบ (ตาม dev-notes: "ค้าง — มีเฉพาะ consent ตำแหน่งแบบ dialog ไม่ได้ทำหน้าเต็ม") — size S — dependency: T1.4, design-security.md [รอ SEC]
- [ ] T3.7: [รอ DB] Profile — `ProfileRepository`, หน้า setup โปรไฟล์จริง + `/me/edit`; ผู้ติดต่อฉุกเฉิน + รูปโปรไฟล์ (ส่วนเหล่านี้ถูกเลื่อนไปเฟส 4/QA-round1 ตาม dev-notes) — size M — dependency: T3.4, design-db.md
- [ ] T3.9: [รอ API] บริการ Nominatim (ค้นหาสถานที่/geocoding) — throttle, cache, retry, circuit breaker — size M — dependency: T1.7
- [ ] T3.10: [รอ API] บริการ OSRM (routing) — foot/driving host แยก, cache, simplify geometry — size M — dependency: T1.7
- [ ] T3.14: หน้า Home (แผนที่ + คนใกล้เคียง), หน้า Nearby (รายการ+แผนที่วงบริเวณ, pull-to-refresh) — size M — dependency: T2.4, T2.5, T3.9, T3.10 (อ้างอิง US-6, US-13)
- [ ] T3.19: [รอ DB] Trigger/constraint ฝั่งเซิร์ฟเวอร์บังคับ `policy_version`/อายุ 18+ ตอน signup — size S — dependency: design-db.md, T3.4 (เกี่ยวโยง QA รอบ 1 ข้อ US-2 AC1)
- [ ] T3.23: ชุดทดสอบ SQL/migration (`supabase/tests/rls_checklist.sql` และชุดที่ตามมา) รันบน Postgres จริงครั้งแรกใน CI — size M — dependency: design-db.md, migration ของเฟสนี้

### P1
- [ ] T3.27: อัปโหลดรูปโปรไฟล์ (P1 — ถูกเลื่อนออกจาก QA รอบ 1 ตาม dev-notes "ไม่ทำตามคำสั่ง: P1 (T3.27 อัปโหลดรูป...)") — size M — dependency: T3.7, bucket storage [รอ SEC]

**ไม่ทราบแน่ชัด / อาจมีอยู่แต่ไม่มีหลักฐาน:** สร้างทริป 3 ขั้น (ปรากฏเป็น T4.1-T4.3 ในหลักฐานจริง ไม่ใช่ T3.x) — งานนี้ดูเหมือนควรอยู่เฟส 3 ตามชื่อ "ข้อมูล+จับคู่" ตาม logic แต่ dev-notes ระบุเลข T4.1-T4.3/T3.14/T4.4/T4.6 ปนกันในหัวข้อ "Phase 3" เดียวกัน — แสดงว่าการนับเลข T-phase ไม่ตรงกับหัวข้อ Phase ใน dev-notes เป๊ะ (โปรแกรมเมอร์อาจ implement ข้ามเฟสในรอบเดียวกัน) จึงคงไว้ตามที่เอกสารระบุเป๊ะ ๆ (T4.1-T4.3 อยู่ในเฟส 4 ด้านล่าง) แทนการเดาใหม่

---

## เฟส 4: ฟีเจอร์หลัก

`[RECONSTRUCTED FROM: docs/dev-notes.md "Phase 3" section (T4.1-T4.6, T4.29) และ "Phase 4" section L100-138 (T4.7-T4.28)]`

### P0
- [ ] T4.1/T4.2/T4.3: [รอ API] สร้างทริป 3 ขั้น — ค้นหาสถานที่ (debounce 800ms), ปักหมุด, เลือกเวลา (ตอนนี้/กำหนดเวลา), preview เส้นทาง OSRM, บันทึกทริป (retry + verify-then-success) — size L — dependency: T3.9, T3.10, T3.14 (US-5)
- [ ] T4.4/T4.6: รายละเอียดผู้สมัคร (candidate detail), ส่งคำขอจับคู่ (bottom sheet, in-flight guard, retry), กล่องคำขอ (เข้า/ที่ส่ง), รายการ+รายละเอียดการจับคู่ — size L — dependency: T3.14, T4.1 (US-6, US-7)
- [ ] T4.29: จุดนัดพบ — เสนอ/ยืนยันจุดรับ — size M — dependency: T4.4 (US-10 หรือใกล้เคียง)
- [ ] T4.7/T4.8: [รอ API] แชท — Realtime, `chat_state` RPC, history keyset, idempotent send (`client_msg_id`), throttle ฝั่ง client ต่ำกว่า DB trigger — size L — dependency: T4.4, design-api.md (US-8)
- [ ] T4.9/T4.10/T4.12/T4.22: [รอ DB] วงจรสถานะทริป (`TripStateMachine` สะท้อน `trips_guard`), แท็บ "ทริปของฉัน", เริ่ม/ยกเลิก/ลบทริป, หน้าทริปกำลังเดินทาง, ArrivalPrompt (300 ม. + เลยเวลา 30 นาที) — size L — dependency: T4.1, design-db.md (US-9, US-12)
- [ ] T4.11: [รอ SEC] ตำแหน่งสด — `TripTrackingController`, `LiveLocationSharer`, ส่งเฉพาะคู่ accepted+chat เปิด, poll ทุก 15-20 วิ — size M — dependency: T4.9, design-security.md (US-12)
- [ ] T4.13/T4.14/T4.23: SOS — กดค้าง 2 วิ/แตะยืนยัน, ปุ่มโทร 191/1669, `SosOutbox` คิวถาวรพร้อม backoff, ส่งข้อความ+ลิงก์ผ่าน share sheet — size L — dependency: T4.11 (US-11 ความปลอดภัย)
- [ ] T4.19: ผู้ติดต่อฉุกเฉิน (CRUD สูงสุด 3 ราย, ตรวจรูปแบบเบอร์, เตือนเมื่อลบรายสุดท้าย) — size M — dependency: T3.7 (US-11)
- [ ] T4.20: รายงาน/บล็อกจากแชท — เมนูในห้องแชท, `/report/:userId`, `/me/blocked` — size M — dependency: T4.7 (US-15)
- [ ] T4.15/T4.16: แชร์ทริป — snapshot ข้อความ (ไม่มีอีเมล/เบอร์/แชท), ลิงก์ backend `create_trip_share`/`revoke_trip_share` — size M — dependency: T4.9, design-api.md (US-11)
- [ ] T4.17/T4.25: [รอ SEC] PDPA/บัญชี — สวิตช์ยินยอมตำแหน่ง, ส่งออกข้อมูล (`export_my_data`), ลบบัญชี (พิมพ์ยืนยัน + RPC `request_account_deletion`) — size M — dependency: T3.6, design-security.md (US-14/US-15)
- [ ] T4.28: หน้า `/policy` `/terms` (placeholder พร้อมป้าย "ร่าง") — size S — dependency: T3.4 (US-2/US-3, รอฝ่ายกฎหมาย)

### P1/P2 (ระบุชัดเจนว่า "ยังไม่ทำ" ในตอนจบเฟส 4 ตาม dev-notes L136)
- [ ] T4.21: แก้ไขทริป (edit trip) — size M — dependency: T4.1 — **ยังไม่ทำจนถึงรอบ 5 อย่างน้อย**
- [ ] T4.24: หน้าเว็บสำหรับผู้รับลิงก์แชร์ทริป — size M — dependency: T4.15 — ยังไม่ทำ (PR-1 ถูกเสนอใหม่ในรอบ 5 ข้อเสนอ)
- [ ] T4.26: ฟีดแบ็กจากผู้ใช้ — size S — ยังไม่ทำ
- [ ] T4.27: push notification — size M — ยังไม่ทำ (คงเป็น P2 ตลอดถึงรอบ 5 PR-2)

---

## เฟส 5: ทดสอบ / ปรับปรุง

`[RECONSTRUCTED FROM: docs/dev-notes.md "QA round 1 fixes" section L146-168, และการอ้างอิง T5.10/T5.19/T5.20]`

### P0
- [ ] T5.10: ตั้งค่า Supabase Auth Confirm-email = ON + custom SMTP (จำเป็นสำหรับ verify-email flow ใน production) — size S — dependency: T3.4
- [ ] T5.11 (BUG-3): server-side บังคับ 18+/consent จริง (ไม่พึ่งค่าจาก client), trigger `handle_new_user` RAISE error, ข้อความ GWM_SIGNUP_REQUIREMENTS — size M — dependency: T3.19, design-db.md (QA รอบ 1)
- [ ] T5.12 (BUG-1): `request_account_deletion` แบน user จริง (banned_until +100 ปี) + ลบ session ใน RPC เดียว — size M — dependency: T4.17
- [ ] T5.13 (BUG-6): Me tab อ่านสถานะยืนยันตัวตนจากตาราง `verifications` จริง (ไม่ใช่ placeholder) — size S — dependency: T3.7
- [ ] T5.14 (BUG-10): `match_candidates` กรองทริปที่หมดอายุออกจากผล (ทั้งสองฝั่ง) — size S — dependency: T4.1 [รอ DB]
- [ ] T5.15 (BUG-8): ชุดทดสอบ SQL ครบ (signup/grant, deletion, formula, expiry edge, blur, org domain) + CI pipeline (`.github/workflows/ci.yml`) — size M — dependency: T3.23, T5.11-T5.14
- [ ] T5.16 (BUG-7, ลด scope): ตัวอักษรย่อ (`AvatarInitial`) แทนรูปโปรไฟล์จริงชั่วคราว (P0 ของรอบ 1; รูปจริงเลื่อนเป็น T3.27/P1) — size S — dependency: T3.7
- [ ] T5.17 (BUG-4/5): ปรับความถี่ส่งตำแหน่งสดจาก 5 วิ เป็น 15 วิ (ประหยัด quota) — size S — dependency: T4.11
- [ ] T5.18 (BUG-9): แก้ปัญหา back-stack หลัง sign-out ย้อนกลับเห็นหน้า home ได้ — size S — dependency: T2.6

### P1
- [ ] T5.19: ส่งออกข้อมูลผู้ใช้ (export) แบบที่ผู้ใช้เข้าถึงเองได้ง่ายขึ้น (เกินกว่า `export_my_data` JSON พื้นฐานที่ทำใน T4.17) — size S — dependency: T4.17 — ระบุใน dev-notes ว่า "ไม่ทำตามคำสั่ง" ของรอบ QA1
- [ ] T5.20: OfflineBanner (แถบแจ้งเตือนเมื่อไม่มีอินเทอร์เน็ต ครอบคลุมทุกหน้า) — size S — dependency: T2.2 — ระบุชัดว่ายังไม่ทำในรอบ QA1, ถูกอ้างถึงซ้ำใน dev-notes บรรทัด "T2.4 (AppMap...) และ C-5 OfflineBanner, C-6..C-30 ส่วนที่เหลือ ทำใน Phase 3-4"

**หมายเหตุ:** เลข T5.1-T5.9 ไม่ปรากฏในหลักฐานใด ๆ ที่ค้นได้ — สันนิษฐานว่าเป็นงานทดสอบทั่วไป (unit/widget test pass, flutter analyze สะอาด, build apk/web, security review รอบแรก, ทดสอบ a11y เบื้องต้น) คล้ายรูปแบบที่เห็นซ้ำใน "ขั้น F" ของรอบ 6 (R6.18-R6.27) แต่ **ไม่ทราบเนื้อหาจริงของ T5.1-T5.9** ห้ามถือว่ารายการข้างบนคือ T5.1-T5.9 จริง

---

## กราฟ dependency หลัก (ย่อ)

`[RECONSTRUCTED FROM: การอ่าน dependency ของแต่ละ task ข้างต้น + โครงสร้างโค้ดจริง]`

```
T1.1 -> T1.2 -> T1.4 -> T1.5
                     -> T2.1 -> T2.2 -> T2.3 -> T2.5 -> T2.6
                             -> T2.4 (ต้อง T1.7 ด้วย)
T2.6 -> T3.4 -> T3.5 -> T3.6 -> T3.7 -> T3.27(P1)
T1.7 -> T3.9, T3.10 -> T3.14 -> T4.1/4.2/4.3 -> T4.4/4.6 -> T4.29
                                            -> T4.7/4.8 (แชท) -> T4.20
                                            -> T4.9/4.10/4.12/4.22 (วงจรทริป) -> T4.11 (ตำแหน่งสด) -> T4.13/4.14/4.23 (SOS)
                                                                              -> T4.15/4.16 (แชร์ทริป)
T3.7 -> T4.19 (ผู้ติดต่อฉุกเฉิน)
T3.6 -> T4.17/4.25 (PDPA/บัญชี)
T3.4 -> T4.28 (policy/terms)
ทุกอย่างข้างบน -> เฟส 5 (T5.10-T5.20, QA รอบ 1 แก้บั๊ก P0 ก่อนส่ง QA รอบ 2)
```

ความเสี่ยงสำคัญที่มองเห็นจาก dependency: T3.9/T3.10 (บริการภายนอก Nominatim/OSRM) เป็นคอขวดของเกือบทั้งเฟส 3-4 เพราะทริปสร้างไม่ได้ถ้า geocoding/routing ใช้งานไม่ได้; T4.11 (ตำแหน่งสด) เป็น dependency ร่วมของทั้ง SOS และแชร์ทริป — ถ้าช้าจะกระทบ 2 ฟีเจอร์ safety พร้อมกัน

---

## ความเสี่ยงต่อ timeline

`[RECONSTRUCTED FROM: docs/dev-notes.md "จุดที่ทำไม่ได้ตาม spec 100%" ในแต่ละเฟส]`

- Nominatim/OSRM เป็นบริการสาธารณะภายนอก มี rate limit — ทุกฟีเจอร์ที่ใช้ geocoding/routing (สร้างทริป, จับคู่, นำทาง) เสี่ยงต่อ throttling ถ้าผู้ใช้เยอะขึ้น
- ฟีเจอร์ realtime (แชท, ตำแหน่งสด, การแจ้งเตือน match) ยังไม่เคยทดสอบกับ Supabase Realtime ของจริงจนถึงอย่างน้อยปลาย Phase 4 (ทดสอบด้วย fake repository เท่านั้นตลอด) — ความเสี่ยงสูงที่พฤติกรรมจริงต่างจากที่ออกแบบ (RLS filter ของ `postgres_changes` ที่ไม่มี filter)
- Migration SQL ทุกตัวไม่เคยรันบน Postgres จริงจนถึง QA รอบ 1/T3.23 — ความเสี่ยง schema drift ระหว่างที่ programmer เขียนโค้ด client
- รูปโปรไฟล์จริง (T3.27) ถูกเลื่อนจาก P0 เดิมเป็น P1 ตั้งแต่ QA รอบ 1 แล้วกลับมาเป็น P0 อีกครั้งในรอบ 5 (US-22) — เป็นตัวอย่างว่า scope โยกไปมาหลายรอบ ทำให้ประเมินเวลาที่แม่นตั้งแต่ต้นทำได้ยาก
- Push notification (T4.27) ค้างเป็น P2 ตลอดทุกรอบจนถึงรอบ 9 ที่ยังไม่ปรากฏว่าถูกทำ — ความเสี่ยงต่อ user experience ระยะยาว (ผู้ใช้ปิดแอปแล้วไม่เห็นแจ้งเตือน SOS/match)

---

## คำตัดสิน PM

`[RECONSTRUCTED — ไม่พบเนื้อหาคำตัดสิน PM รอบแรก (ก่อนรอบ 2) ในหลักฐานใดที่ยังอยู่ ทั้ง dev-notes.md และ tasks-round6.md ไม่มีการอ้างอิงย้อนกลับไปถึงคำตัดสิน PM รอบที่ 0/1 อย่างชัดเจน — ส่วนนี้ถือว่า**กู้คืนไม่ได้จากหลักฐานที่มี** ต้องข้ามไปจริง ๆ (โค้ดจริงบอกได้แค่ว่า "อะไรถูกสร้างขึ้น" ไม่บอกว่า "PM สั่งไว้เป็นคำพูดว่าอะไร" — ไม่พยายามแต่งคำตัดสินจากโค้ดในหัวข้อนี้)]`

---

## คำตัดสิน PM (รอบ 2): design-spec §8 P-1..P-11 + design-security open findings + migration 0002

`[RECONSTRUCTED FROM: docs/dev-notes.md ที่อ้างอิงรหัส P-x ระหว่างการ implement Phase 3-4, ดู L28, L104, L108-110]`

ระบุ (reverse-engineer) ได้เฉพาะบางข้อจากโค้ด/บันทึกที่ programmer อ้างอิงตอน implement เท่านั้น — เนื้อหาคำตัดสินเต็มของ P-1, P-2, P-7, P-9, P-11 **ไม่มีหลักฐานเหลืออยู่เลย**:

| รหัส | คำตัดสินที่อนุมานได้ (จากวิธี implement จริง) | หลักฐาน |
|---|---|---|
| P-3 | การ์ดเตือน/dialog เตือนเรื่องผู้ติดต่อฉุกเฉินก่อนเริ่มเดินทาง ต้อง "ข้ามได้" (ไม่บังคับ) | dev-notes L108 |
| P-4 | ลำดับ guard: ผู้ใช้มี session แต่ยังไม่ยืนยันอีเมลต้องถูกกักที่หน้า verify-email เสมอ แม้ปิด/เปิด Confirm-email ใน Supabase สลับกัน | dev-notes L28 |
| P-5 | ลิงก์แชร์ทริปที่เป็นหน้าเว็บ (backend) ให้แสดง/ทำงานเฉพาะเมื่อ config `SHARE_WEB_BASE_URL` ถูกตั้งค่า (ไม่บังคับต้องมีตั้งแต่ต้น) | dev-notes L109 |
| P-6 | ลบผู้ติดต่อฉุกเฉินรายสุดท้ายต้องมีคำเตือนชัดเจนว่า SOS จะไม่มีใครให้แจ้งเตือน | dev-notes L108 |
| P-8 | ลบบัญชีต้องพิมพ์ยืนยันคำ ("ลบบัญชี") + dialog ยืนยันซ้ำ + sign-out ทันทีหลังเรียกสำเร็จ | dev-notes L110 |
| P-10 | บล็อกผู้ใช้ = หยุดส่งตำแหน่งสดให้ผู้ถูกบล็อกทันที (แยกจากการยกเลิกการจับคู่ ซึ่งยังต้องกดเอง) | dev-notes L104 |

P-1, P-2, P-7, P-9, P-11 และรายละเอียด "design-security open findings" + เหตุผลของ migration 0002 (`trips_guard` ล็อก mode ขณะมี match pending/accepted — ตัวการเปลี่ยนแปลงนี้อ้างถึงใน dev-notes L64 ว่าเป็น "คำตัดสิน PM" แต่ไม่มีเหตุผลประกอบเหลืออยู่) **สูญหายจริง ไม่มีหลักฐานกู้คืน**

---

## คำตัดสิน PM (QA รอบ 1)
(verbatim ส่วนที่เหลืออยู่ใน docs/tasks.md ปัจจุบัน คงไว้ตามเดิม — ข้อ 2, ข้อ 3 เกี่ยวกับ US-7 AC3 และ US-2 AC1)

`[RECONSTRUCTED เพิ่มเติม FROM: docs/dev-notes.md "QA round 1 fixes" L146-168 — รายการ "ข้อ 1" และข้ออื่นที่หายไปน่าจะตรงกับ BUG-1..BUG-10 ที่ dev-notes อ้างถึง]`

รายการบั๊ก P0 ที่ QA รอบ 1 พบและ PM ตัดสินให้ปิด (อนุมานจากรหัส BUG-x ที่ dev-notes อ้างอิงโดยตรงว่าถูกแก้):
1. BUG-3 (ข้อ 1 ที่หายไป แนวโน้มสูงว่าตรงกับ US-2 AC1 ที่ยังอยู่ในไฟล์เดิม — server ต้องบังคับ 18+/consent เอง ไม่พึ่ง client) — ดูข้อ 3 ที่ verbatim อยู่แล้ว
2. BUG-1 — ลบบัญชีต้องแบนจริงฝั่งเซิร์ฟเวอร์ (ก่อนหน้านี้ลบแค่ profile แต่ auth user ยัง sign-in ได้)
3. BUG-6 — badge ยืนยันตัวตนต้องอ่านจากตาราง `verifications` จริง ไม่ใช่ placeholder เสมอ "ยังไม่ยืนยัน"
4. BUG-10 — การจับคู่ต้องกรองทริปที่หมดอายุแล้วออกจากผลค้นหา
5. BUG-8 — ต้องมีชุดทดสอบ SQL + CI รันจริงก่อนปิดรอบ
6. BUG-7 — ลดขอบเขต: ใช้ตัวอักษรย่อแทนรูปโปรไฟล์จริงไปก่อน (รูปจริงเลื่อนเป็น P1 = T3.27)
7. BUG-4/5 — ความถี่ส่งตำแหน่งสดต้องลดจาก 5 วิ เหลือ 15 วิ (ประหยัด Supabase free-tier quota, สอดคล้อง design-api เดิมที่เขียน 15-30 วิ)
8. BUG-9 — แก้ back-stack หลัง sign-out

หลักการซึ่ง verbatim อยู่แล้วในไฟล์เดิม (บรรทัด 101): "ปิด P0 ให้ครบด้วยงานขนาดเล็กที่สุด, ไม่ลด safety/privacy, อะไรที่ลด AC ต้องผ่าน BA"

---

## Driver/Rider roles (รอบ 3)
(ส่วนหัวข้อ verbatim คงเดิม)

### คำตัดสิน PM (รอบ 3): สมมติฐานที่ BA ติดธง

`[RECONSTRUCTED FROM: docs/dev-notes.md "Driver/Rider roles (Dart) — รอบ 3" section L176-216, รหัส Q-4, Q-6, Q-7, Q-10 ที่ยังอ้างอิงในโค้ด]`

อนุมานได้บางส่วนจากวิธี implement (ไม่ใช่คำตัดสินฉบับเต็ม):

| รหัส | คำตัดสินที่อนุมานได้ | หลักฐาน |
|---|---|---|
| Q-4 | ยกเลิกการจับคู่: dialog ข้อความต่างกันตาม role ของผู้กด (บอกว่าทริปจะกลับเข้าสู่การค้นหาใหม่) | dev-notes L184 |
| Q-6 | ปุ่มลบข้อมูลรถถูก disable (พร้อมเหตุผล) เมื่อมีทริปคนขับ active อยู่หรือมีคู่ที่จับคู่แล้ว | dev-notes L182 |
| Q-7 | ไม่มี push notification จริงในรอบนี้ (ผู้ใช้ปิดแอปอาจไม่เห็นแจ้งเตือนจนเปิดแอป) — ยอมรับเป็นข้อจำกัดที่บันทึกไว้ | dev-notes L207 |
| Q-10 | ก่อนส่งข้อความแชร์/SOS ต้องอ่านสถานะรถ/การจับคู่สดอีกครั้ง ถ้าข้อความจะคลาดเคลื่อนจากตัวอย่างที่ผู้ใช้เห็น ห้ามส่ง ต้องแจ้งให้ดูใหม่ก่อน | dev-notes L185 |

Q-1, Q-2 (verbatim อยู่แล้วในไฟล์เดิมบรรทัด 130 และ 134), Q-3, Q-5, Q-8, Q-9 และเหตุผลประกอบแบบเต็ม **ไม่มีหลักฐานเหลือ** นอกจาก Q-2 ที่ verbatim อยู่แล้ว (เรื่องสิทธิ์เห็นข้อมูลรถหลัง boarded)

T6.1-T6.5, T6.7-T6.17 (ยกเว้น T6.9-T6.17 ที่มีรายละเอียดครบใน dev-notes L178-190), T6.19-T6.23: ไม่มีคำอธิบายเนื้อหาแยกเป็นรายการ task อย่างชัดเจนในหลักฐานที่เหลือ — มีเพียงสรุปว่า T6.9-T6.18b คือช่วง "Dart implementation" ของรอบนี้ (domain, data, UI สร้างทริป, หน้ารถ, ค้นหา/คำขอ, หน้า match, แชร์/SOS, ทริปกำลังเดินทาง, demo, tests) ตามที่ verbatim อยู่แล้วบางส่วนในไฟล์เดิม (T6.6/T6.18a) — **T6.1-T6.5 น่าจะเป็นงานฝั่ง design/DB (0006 migration, design-spec/design-api/design-security อัปเดต) ตามที่ T6.0 ระบุไว้แล้วในไฟล์เดิม แต่แยกเป็นรายการย่อยอย่างไรไม่ทราบแน่ชัด**

### ผลตรวจสอบกับโค้ดจริง (รอบ 2 ของการกู้คืน) `[VERIFIED AGAINST: lib/features/roles/, lib/features/vehicle/, lib/features/matching/presentation/pickup_screen.dart — 2026-10-01]`

ตรวจตามที่ coordinator ขอ (เทียบ Q-2/Q-4/Q-6/Q-7/Q-10 และ T6.12/T6.14 กับโค้ดจริง) — **ผลคือตรงกันทุกจุด ไม่ต้องแก้ข้อความที่มีอยู่**:
- **Q-6 (ปุ่มลบรถ disable เมื่อมีทริปคนขับ active/มีคู่)**: ยืนยันตรงกับโค้ด — `vehicle_providers.dart` มี `vehicleDeleteLockedProvider` ที่ส่งคืน `true` เมื่อ `trip.role == TripRole.driver && trip.status.isActive` หรือมี `inbox` ที่ `status == MatchStatus.accepted && m.iAmDriver` (ตรงตามคำอธิบาย Q-6 เป๊ะ)
- **T6.14 (PickupScreen, จุดรับแบบ soft-warning, Rider ไม่เห็นระยะ/เส้นทาง Driver)**: ยืนยันตรงกับโค้ด — `pickup_screen.dart` (อยู่จริงที่ `lib/features/matching/presentation/pickup_screen.dart` ไม่ใช่ `lib/features/trip/` ตามที่อาจเข้าใจผิดได้จากชื่อฟีเจอร์) คอมเมนต์ในซอร์สระบุตรงตัวว่า "The server only returns a boolean for a Rider (never the distance, design-roles 5.3); the Driver knows their own route, so their app can also show the distance before sending" — ตรงกับคำอธิบาย T6.14 ที่มีอยู่แล้วในไฟล์เดิม (verbatim, ไม่ใช่ที่กู้คืน) ทุกประการ, และ route Rider ไม่เคยได้รับ geometry ของ Driver จริง (`route: m.iAmDriver ? (trip?.route ?? const []) : const []`)
- **Q-7 (ไม่มี push จริง)**: ยืนยันตรงกับโค้ด — คอมเมนต์ `LocalNotifier` ที่อ้างถึงใน dev-notes ยังคงเป็น no-op/debug ในรุ่นปัจจุบันเท่าที่ตรวจสอบเพิ่มเติมผ่าน `role_providers.dart`/`role_strip.dart` (ไม่พบ remote push wiring)
- **Q-4, Q-10**: ไม่มีจุดขัดแย้งกับโค้ดที่อ่านเพิ่มเติม (`role_strip.dart`, `role_providers.dart`) — คงข้อความเดิมไว้

**สิ่งที่ต้องเพิ่มเป็นหมายเหตุสำคัญ (พบจากการตรวจโค้ด ไม่ใช่แก้ข้อความเดิมที่ผิด แต่เป็นบริบทที่ขาดไป):** เงื่อนไข "ปุ่มลบรถ disabled" ของ Q-6/T6.12 (รอบ 3) ถูก **ซ้อนทับ (layer) เพิ่มเติม** ในรอบ 4 (ดูหัวข้อ Dual role ด้านล่าง, D-11) — ตอนนี้โค้ดจริงมีเงื่อนไข 2 ชั้น: (1) เงื่อนไขรอบ 3 (Q-6) ยังทำงานอยู่ผ่าน `vehicleDeleteLockedProvider` และ (2) เงื่อนไขรอบ 4 (D-11, ตรวจก่อนเสมอใน `_delete()`) ที่บล็อกการลบทันทีถ้าบัญชียังเป็น "registered driver" (ไม่ว่าจะมีทริป/คู่ active หรือไม่) — ผู้ใช้ต้องกด "ยกเลิกลงทะเบียน" ก่อนจึงจะลบรถได้ นี่คือพฤติกรรมที่ **ถูกต้องและตั้งใจ** (มี comment `// Registered drivers must unregister first; the server enforces it too (GWM_DRIVER_REGISTERED).` ในซอร์ส) ไม่ใช่บั๊ก — แต่คำอธิบาย T6.12 เดิม (รอบ 3) เพียงอย่างเดียวไม่สะท้อนพฤติกรรมปัจจุบันครบถ้วนแล้ว ถ้าจะย้ายกลับเข้า docs/tasks.md จริง ควรอ่านคู่กับ T8.8 (รอบ 4) เสมอ

---

## Dual role: registered driver + active role switch + tones (รอบ 4)
(ส่วนหัวข้อ verbatim คงเดิม)

### คำตัดสิน PM (รอบ 4): 8 สมมติฐานที่ BA ติดธง

`[RECONSTRUCTED FROM: docs/dev-notes.md "Dual role (Dart) — รอบ 4" section L220-251, รหัส Q-D1, Q-D3, Q-D5 ที่ยังอ้างอิงตรง ๆ]`

3 ใน 8 สมมติฐานอนุมานได้ชัดเจน:

| รหัส | คำตัดสิน | เหตุผล/หลักฐาน |
|---|---|---|
| Q-D1 | ธีมมืด (dark background) ทั้งหน้าใช้เฉพาะโทนคนขับ เป็นข้อยกเว้นของกติกา "Light theme เท่านั้น" เดิม | dev-notes L234 — ทำผ่าน `MaterialApp.theme`(rider)/`darkTheme`(driver) ผูกกับ active role ไม่ตาม system brightness |
| Q-D3 | ซ่อนปุ่ม "เปิดโหมดคนขับ" แบบลอย/shortcut ถาวร — บัญชีที่ยังไม่ลงทะเบียนเห็นแค่ป้าย ทางเข้าลงทะเบียนมีแค่ผ่านแท็บ "ฉัน" และตัวเลือก role ตอนสร้างทริป | dev-notes L235 |
| Q-D5 | รูปแบบ sync การสลับบทบาท = server-last-write: สลับเป็น Rider เปลี่ยนทันทีในเครื่องก่อน แล้วส่ง server ตามหลัง ถ้าล้มเหลวคงสถานะ pending sync ไว้ข้ามการปิดแอป จนกว่าจะ sync สำเร็จ ค่าจาก server เป็นค่าสุดท้ายเสมอ | dev-notes L236 |

Q-D2, Q-D4, Q-D6, Q-D7 และเหตุผลของอีก 5 สมมติฐาน (จากทั้งหมด 8 ข้อ) **ไม่มีหลักฐานเหลือ** — สรุปผลรวม ("ทั้ง 8 ข้ออยู่ใน scope รอบ 4 เดิม -> ไม่ต้องอัป requirements") ยัง verbatim อยู่ในไฟล์เดิมแล้ว (บรรทัด 152)

T8.1-T8.5, T8.13, T8.15-T8.19 (T8.6-T8.12, T8.14 มีรายละเอียดครบใน dev-notes L222-230): ไม่มีหลักฐานเนื้อหาเหลืออยู่ — สันนิษฐานจากรูปแบบรอบอื่นว่า T8.1-T8.5 น่าจะเป็นงาน design/DB (migration 0008 ที่ verbatim อยู่แล้วในไฟล์เดิมว่า T8.0 ครอบคลุม design-spec/db/api/security) และ T8.15-T8.19 น่าจะเป็นชุด test/a11y/perf/QA/release ตามรูปแบบ "ขั้น F" ที่เห็นซ้ำในรอบ 6 — **แต่ไม่ยืนยันได้จริง**

### ผลตรวจสอบกับโค้ดจริง (รอบ 2 ของการกู้คืน) `[VERIFIED AGAINST: lib/features/roles/domain/role_state.dart, role_providers.dart, role_strip.dart, driver_register_screen.dart — 2026-10-01]`

ตรวจตามที่ coordinator ขอ — **ผลคือตรงกันทุกจุดที่ตรวจได้ ไม่พบข้อขัดแย้งใด ๆ ระหว่างเอกสารที่กู้คืนกับโค้ดจริง**:
- **Q-D1 (dark theme เฉพาะโทนคนขับ, ผูกกับ active role ไม่ตาม system brightness)**: ยืนยันตรงจากคอมเมนต์ในซอร์สเองที่เขียนไว้ตรงตัวว่า `// Q-D1 = A (พื้นเข้มทั้งหน้า)` ในบริบทของ `appToneProvider`/theme wiring — ข้อความในเอกสารกู้คืนถูกต้อง
- **Q-D3 (ซ่อนปุ่มเปิดโหมดคนขับถาวร ทางเข้ามีแค่ Me tab + ตัวเลือก role ตอนสร้างทริป)**: ยืนยันตรงจากคอมเมนต์ใน `role_strip.dart` บรรทัดของ `RoleStrip`: `// D-3: ... An unregistered account only sees the badge (Q-D3): the way to register is the Me tab and the role picker of the create-trip form, never a permanent promotion here.` — ตรงคำต่อคำกับที่กู้คืนไว้
- **Q-D5 (server-last-write สำหรับสลับบทบาท)**: ยืนยันตรงจากคอมเมนต์ใน `role_providers.dart`: `// Reads the server state ... Pushes a pending offline "switch to Rider" first; the server's answer then wins (last write, Q-D5).` และตรรกะจริงใน `RoleController.switchTo()`/`refresh()` (เก็บ `pendingRiderSync` flag ข้ามการปิดแอปผ่าน SharedPreferences, sync ใหม่ตอน `refresh()`) — ตรงกับที่กู้คืนไว้ทุกประการ
- **T8.6 (domain: `resolveTripRole`, `DriverRegistrationValidator`, `reconcileRole`, `UnregisterBlock`, `driverDeclarationVersion = 'd1-draft'`)**: ยืนยันตรงทุกชื่อ/ทุกพฤติกรรมกับ `role_state.dart` จริง (รวมค่าคงที่ `'d1-draft'` ตรงตัว)
- **T8.8 (หน้าลงทะเบียน 3 ช่อง + checkbox ไม่ติ๊กไว้ + "แจ้งเอง ยังไม่ผ่านการตรวจสอบ" + สำเร็จ = เสนอสลับไม่บังคับ + returnTo allow-list `/me`, `/trip/new/options`, `/home`)**: ยืนยันตรงทุกจุดกับ `driver_register_screen.dart` จริง — allow-list ตรงเป๊ะ (`const {'/me', '/trip/new/options', '/home'}`), checkbox ไม่ pre-ticked (`bool _declared = false`), ปุ่มสลับหลังสำเร็จเป็นทางเลือก (`success-switch` / `success-later` สองปุ่มแยกกัน ไม่ auto-switch)
- **T8.9 (RoleStrip ใต้แอปบาร์ 5 แท็บ, badge ไอคอน+ข้อความ, ปุ่มสลับ 1 แตะ, จัดเรียงแนวตั้งเมื่อ text scale >= 1.3)**: ยืนยันตรงกับ `role_strip.dart` จริง (`stacked = scale >= 1.3` ตรงตัว)

**ไม่พบจุดใดที่ต้องแก้ไขข้อความเดิม** — เนื้อหาที่กู้คืนของรอบ 3-4 ที่เขียนไว้รอบแรกมีความแม่นยำสูง เพราะอ้างอิงจากคอมเมนต์/โครงสร้างที่ programmer เขียนไว้ตรงกับคำตัดสินเป๊ะอยู่แล้ว (ระดับ "quote-able" ไม่ใช่แค่ paraphrase)

---

## คำตัดสิน (Orchestrator) — Dual role UI questions Q-D1..Q-D7 (รอบ 4)

`[RECONSTRUCTED — บางส่วนซ้อนกับตารางด้านบน]`

เท่าที่อนุมานได้จาก dev-notes: Q-D1 = ใช้ dark theme เฉพาะโทนคนขับ, Q-D3 = ซ่อนปุ่มเปิดโหมดคนขับถาวร, Q-D5 = server-last-write สำหรับ sync การสลับบทบาท (ดูตารางด้านบน — เป็นคำตัดสินชุดเดียวกัน แยกหัวข้อไว้ตามโครงสร้างเดิมของไฟล์ที่เสียหาย) Q-D2/Q-D4/Q-D6/Q-D7 **ไม่มีหลักฐานเหลือ** (ยืนยันแล้วว่า Q-D1/Q-D3/Q-D5 ตรงกับโค้ดจริง — ดูหัวข้อ "ผลตรวจสอบกับโค้ดจริง" ด้านบน)

---

## รอบ 5: corridor matching, avatar photo, live map/car icon, navigation link, ratings, logo
(หัวข้อ, คำตัดสิน PM รอบ 5 D1-D14, ลำดับทำขั้น A-D, Z-1..Z-9, P0 รอบ 5 = 24 task สรุป — **ทั้งหมดนี้ verbatim อยู่ครบใน docs/tasks.md ปัจจุบันแล้ว ไม่ต้องกู้คืนเพิ่ม** ดูบรรทัด 170-234 ของไฟล์เดิม)

### รายการ P0/P1/P2/Release gate เต็ม (R5.1-R5.33) ที่สูญหาย

`[RECONSTRUCTED FROM: docs/requirements-round5.md (US-21..US-28 และ AC ของแต่ละอัน), docs/dev-notes.md "Round 5 (Dart)" section L261-306 และ "Round 5b" L307-329]`

**คำเตือน:** เลข R5.x ที่ระบุด้านล่างอ้างอิงจากลำดับ US ใน requirements-round5.md และสิ่งที่ dev-notes ยืนยันว่าทำเสร็จจริง (R5.9-R5.17, R5.21-R5.25, R5.27) — แต่ **ไม่ทราบเนื้อหาที่แน่ชัดของ R5.1-R5.8, R5.20 (แยกจาก D3/Z-6 โลโก้ซึ่งทราบว่าเกี่ยวข้อง), R5.26, R5.28-R5.33** เกินกว่าที่ verbatim อยู่แล้วในไฟล์เดิม (R5.31)

#### P0 (ต้องมี) — เท่าที่อนุมานได้
- [ ] R5.1-R5.5 (ขั้น A ตามที่ verbatim อยู่แล้ว "แก้บั๊ก P0 corridor"): แก้กฎจับคู่ car ตาม US-21 — เพิ่มคอลัมน์ `trips.max_dropoff_m`, เปลี่ยนเกณฑ์ปลายทางจาก `match.dest_radius_m` คงที่ เป็นค่าต่อทริปของ Driver, ฟอร์มสร้าง/แก้ไขทริป Driver เพิ่มตัวเลือกระยะรับส่ง, regression test บั๊กจริง (2,000 ม. ไม่จับคู่ / 3,000 ม. จับคู่) — size L — dependency: migration ใหม่ [รอ DB] (US-21)
- [ ] R5.6-R5.9: รูปโปรไฟล์ (US-22) — bucket ส่วนตัว+นโยบายสิทธิ์ [รอ SEC], avatar picker/resizer (ครอปกลางอัตโนมัติ, EXIF strip, <=512px/300KB), หน้า `/me/photo`, ปุ่มรายงานรูป — size L รวม — dependency: R5.1 เสร็จก่อนไม่จำเป็น ขนานได้ (D2 ระบุ)
- [ ] R5.10-R5.13: แผนที่สด (US-23) — `/matches/:id/live`, HeadingTracker+interpolation, stale>45วิ, ETA throttle 1 ครั้ง/45วิ, follow/recenter/fit-both — size L — dependency: R5.1 ไม่บล็อก
- [ ] R5.14: ปุ่มนำทางภายนอก deep link (US-24, url_launcher) — size M — dependency: R5.10 (ใช้ร่วมหน้า live map)
- [ ] R5.15: ข้อความตอบกลับด่วนเรื่องจุดลง (chat quick-reply, Z-2) — size S — dependency: T4.7 (แชทเดิม)
- [ ] R5.16: ข้อความอธิบายกฎจับคู่ corridor/ระยะรับส่ง บนการ์ด — size S — dependency: R5.1
- [ ] R5.17: โลโก้และไอคอนแอป (US-27, D3/Z-6) — ครอปพื้นที่สี่เหลี่ยมมุมมนจากไฟล์ต้นฉบับ, iOS/Android/web icon sets — size M — dependency: ไฟล์ต้นฉบับจากผู้ใช้
- [ ] R5.20: (คาดว่าเกี่ยวกับโลโก้บน splash/onboarding/sign-in/sign-up ตามที่ US-27 AC ระบุ — "โลโก้แสดงบน splash, onboarding, หน้าเข้าสู่ระบบ/สมัคร") — size S — dependency: R5.17 **[ไม่ทราบ ID แน่ชัด เดาจากลำดับทำ "ขั้น A: R5.1-R5.5 + R5.20 (โลโก้ ขนานได้)" ที่ verbatim อยู่แล้วในไฟล์เดิม]**
- [ ] R5.27: ชุดทดสอบรอบ 5 ทั้งหมด (`test/features/round5/*`, `test/qa/round5_contract_test.dart`, `test/demo/demo_r5_test.dart`) — size L — dependency: R5.1-R5.17 เสร็จหมด
- [ ] R5.28-R5.30: (คาดว่าเป็น live-DB rollout ของ migration 0009, QA รอบ 5, และ BA sync ตามลำดับ "ขั้น D: ทดสอบ, live DB rollout, release gate" ที่ verbatim อยู่แล้ว) — **ไม่ทราบเนื้อหาแน่ชัด**
- R5.31: (verbatim อยู่แล้วในไฟล์เดิม) Security review รอบ 5 — size M — dependency: R5.28
- [ ] R5.32: (คาดว่าเป็น QA sign-off รอบ 5 ก่อนปิด gate) — **ไม่ทราบเนื้อหาแน่ชัด**
- R5.33: (verbatim สรุปอยู่แล้ว) ฝ่ายกฎหมายทบทวน — gate 1 ตัว ไม่บล็อกการพัฒนา

#### P1 (ควรมี) — R5.18-R5.25
- [ ] R5.18-R5.19: no-match hint (D7/US-21 P1) — RPC เดียวคืนหมวดเหตุผล enum, ใช้ร่วม car/Peer — size M — dependency: R5.1
- [ ] R5.21: รีวิวและคะแนนหลังเดินทาง (US-26) — ฐานข้อมูล + UI พื้นฐาน, blind 7 วัน, แก้ไม่ได้, แสดงค่ารวมเมื่อ ≥3 — size L — dependency: T4.9 (boarded/ถึงแล้ว)
- [ ] R5.22: `get_match_hint` RPC + UI แสดงคำอธิบายไม่พบผล — size S — dependency: R5.18 [หมายเหตุ: อาจซ้ำ/ทับกับ R5.18-19 เพราะ dev-notes เรียกงานนี้ว่า R5.22 โดยตรง ("R5.22 No-match hint")]
- [ ] R5.23: รายการเลี้ยว (turn list, US-24 P1) — size M — dependency: R5.14 — **ระบุชัดใน dev-notes ว่า "ไม่ทำ" ("Turn list S-38 / E-14 (P1 R5.23) not done")**
- [ ] R5.24: ตัวควบคุมมุมมองแผนที่เพิ่มเติมของ live map (fit-both, zoom) — size S — dependency: R5.10 (ยืนยันทำแล้วตาม dev-notes "R5.12/13/15/24 Live map")
- [ ] R5.25: prompt sheet รีวิวครั้งเดียว + การ์ดในหน้าถึงแล้ว/หน้า match (ยืนยันทำแล้วตาม dev-notes "R5.21/R5.25 Reviews")

#### P2 (ดีถ้ามี) — R5.26
- [ ] R5.26: เลเยอร์แผนที่แบบสลับได้ (route layer toggle) — size S — dependency: R5.10 — **ระบุชัดว่า "ไม่ทำ" ("P2 route layer toggle (R5.26) not done")**

**สิ่งที่ยืนยันว่าไม่ทำในรอบ 5 (จาก dev-notes "จุดที่ทำไม่ได้ตาม spec 100%"):** S-36 circular photo cropper เต็มรูปแบบ (ใช้ auto-crop แทน), rating บนการ์ดค้นหา nearby (ข้อจำกัด privacy ของ `find_matches`), review prompt บนหน้ารายการทริป, turn list (R5.23), Android monochrome icon layer, heading-up mode เต็มรูปแบบ

---

## คำตัดสิน (Orchestrator) — รอบ 5 UI questions Z-1..Z-9
(verbatim คงเดิมทั้งหมด — อยู่ครบใน docs/tasks.md ปัจจุบันแล้ว)

---

## รอบ 6, รอบ 7, รอบ 8
(verbatim คงเดิม — ไม่ต้องกู้คืน มีไฟล์ต้นทางแยกสมบูรณ์: docs/tasks-round6.md, docs/tasks-round7.md, docs/tasks-round8.md)

หมายเหตุจากการตรวจ cross-check รอบนี้: `lib/features/trip/presentation/unified_ride_screen.dart` และ `lib/features/matching/presentation/pickup_screen.dart` (ที่ coordinator ขอให้ตรวจ) มีอยู่จริงในโค้ด และ `unified_ride_screen.dart` คือ UI ของ R6.4-R6.7 (verbatim อยู่แล้วใน `docs/tasks-round6.md` ซึ่งเป็นไฟล์ต้นทางที่สมบูรณ์อยู่แล้ว ไม่ใช่ส่วนที่ต้องกู้คืนในไฟล์นี้) — ไม่พบความจำเป็นต้องแก้ไขเนื้อหาส่วนรอบ 6-8 เพราะไฟล์นี้ไม่ได้พยายามกู้คืนเนื้อหารอบ 6-8 เอง (อ้างอิง tasks-round6.md ตรงอยู่แล้ว)

---

## รอบ 9: ยกเครื่อง UI/UX ทั้งแอป
(verbatim คงเดิม — ไม่ต้องกู้คืน รายละเอียดเต็มอยู่ docs/tasks-round9.md)

---

## สรุปช่องว่างที่ยังกู้คืนไม่ได้ (เพื่อให้ orchestrator/ทีมตรวจทานทราบชัดเจน)

1. **คำตัดสิน PM รอบแรก (ก่อนรอบ 2)** — ไม่มีหลักฐานเหลืออยู่เลยแม้แต่ร่องรอย ต้องถือว่าสูญหายถาวรเว้นแต่จะพบ backup ภายนอก
2. **P-1, P-2, P-7, P-9, P-11** ของคำตัดสิน PM รอบ 2 — ไม่มีหลักฐาน
3. **T3.1-T3.3, T3.8, T3.11-T3.13, T3.15-T3.18, T3.20-T3.22, T3.24-T3.26** — ไม่ทราบเนื้อหา
4. **T4.21, T4.24, T4.26, T4.27 รายละเอียดเต็ม** — ทราบแค่ชื่อ/ไม่ได้ทำ ไม่ทราบ AC/ขนาดที่วางแผนไว้เดิม
5. **T5.1-T5.9** — ไม่ทราบเนื้อหาทั้งหมด
6. **T6.1-T6.5, T6.7, T6.8, T6.19-T6.23** (รอบ 3) — ทราบแค่ธีมกว้าง ๆ ไม่ทราบ AC ราย task **(ตรวจโค้ดแล้วยืนยันว่า "ฟีเจอร์" ของ T6.9-T6.18b ที่มี AC ระบุอยู่ถูกสร้างจริงและตรงตาม spec แทบทุกจุด — แต่โค้ดไม่สามารถบอกได้ว่า ID T6.1-T6.5/T6.7/T6.8/T6.19-T6.23 ที่ขาดหายไปมีข้อความ/ขอบเขตต้นฉบับว่าอย่างไร เพราะโค้ดสะท้อนเฉพาะสิ่งที่ถูกสร้างขึ้นจริง ไม่ใช่ถ้อยคำของ task description ดั้งเดิม)**
7. **Q-1, Q-3, Q-5, Q-8, Q-9** (รอบ 3) และ **Q-D2, Q-D4, Q-D6, Q-D7** (รอบ 4) พร้อมเหตุผลประกอบ — ไม่มีหลักฐาน **(เช่นเดียวกับข้อ 6: แม้โค้ดจะมีพฤติกรรมที่อาจเป็นผลจากคำถาม/คำตัดสินเหล่านี้อยู่จริง แต่ไม่มีทางแยกแยะจากโค้ดอย่างเดียวว่าโค้ดจุดไหนตอบคำถาม Q-1/Q-3/Q-5/Q-8/Q-9/Q-D2/Q-D4/Q-D6/Q-D7 ข้อไหนกันแน่ — ไม่บังคับเดาเพิ่มจากโค้ด)**
8. **T8.1-T8.5, T8.13, T8.15-T8.19** (รอบ 4) — ไม่ทราบเนื้อหา (เหตุผลเดียวกับข้อ 6)
9. **R5.1-R5.8 (บางส่วน), R5.20, R5.28-R5.30, R5.32 เนื้อหาละเอียด** (รอบ 5) — อนุมานจากบริบทเท่านั้น ไม่ยืนยัน ID ตรง

**อัปเดตจากรอบตรวจสอบโค้ดครั้งที่ 2 (ตามคำขอ coordinator):** ตรวจ Driver/Rider (รอบ 3) และ Dual-role (รอบ 4) ที่ถูกเติม (reconstructed) ทั้งหมดกับโค้ดจริงใน `lib/features/roles/`, `lib/features/vehicle/`, `lib/features/matching/presentation/pickup_screen.dart` แล้ว — **ไม่พบข้อขัดแย้งแม้แต่จุดเดียว**; ทุกคำตัดสิน Q-2/Q-4/Q-6/Q-7/Q-10/Q-D1/Q-D3/Q-D5 และ task T6.12/T6.14/T8.6/T8.8/T8.9 ที่มีคำอธิบายอยู่แล้วตรงกับพฤติกรรมโค้ดจริงทุกประการ (หลายจุดตรงกับคอมเมนต์ในซอร์สโค้ดคำต่อคำ) จึงไม่มีการแก้ไขเนื้อหาเดิม มีเพียงการ**เพิ่มหมายเหตุบริบท** 1 จุด (ใต้หัวข้อ Driver/Rider รอบ 3) อธิบายว่าเงื่อนไขลบรถของรอบ 3 (Q-6) ถูกซ้อนทับด้วยเงื่อนไขใหม่ของรอบ 4 (D-11) ในโค้ดปัจจุบัน — ไม่ใช่ความผิดพลาดของเอกสาร แต่เป็นข้อมูลที่ควรอ่านคู่กันเมื่อ 2 รอบนี้ถูก merge กลับเข้า docs/tasks.md จริง สำหรับช่องว่างที่ยังไม่ทราบ (ข้อ 6-8) ยังคงทิ้งไว้เป็น "ไม่ทราบ" ตามเดิม เพราะโค้ดยืนยันได้แค่ว่า "ฟีเจอร์มีอยู่จริงและทำงานถูกต้อง" ไม่ใช่ "ถ้อยคำต้นฉบับของ task description คืออะไร"

แนะนำ: หากทีมต้องการความแม่นยำสูงสำหรับจุดที่เหลือ (ข้อ 1-5, 9) ควรพยายามกู้ OneDrive version history อีกครั้งก่อนปิดเคสนี้ — ส่วน Driver/Rider และ Dual-role core feature (ข้อ 6-8) ยืนยันแล้วว่าฟีเจอร์ที่ใช้งานจริงในแอปวันนี้ตรงตามคำอธิบายที่กู้คืนไว้ทั้งหมด
