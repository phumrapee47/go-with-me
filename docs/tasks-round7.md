# Task List รอบ 7: Push, Road-Snapped Pickup, Vibe & Niche Filters, Dark Mode, Shared Impact (US-42..US-47)

อ้างอิง: `docs/requirements-round7-ba.md` (ไม่แก้ `tasks.md`/`tasks-round6.md` เดิม) ขนาด: S = ครึ่งรอบ, M = 1 รอบ, L = 1.5-2 รอบ

## คำตัดสิน PM (Q1-Q10)
- Q1: sign-out ลบ token **เฉพาะอุปกรณ์นั้น** ไม่ลบทุกอุปกรณ์ — ยังปลอดภัยเพราะ token ผูกกับอุปกรณ์ (device-bound) อยู่แล้ว sign-out จากเครื่องอื่นไม่ต้องพึ่งการลบ token เพื่อความปลอดภัย เหตุผล: ตรงกับพฤติกรรมผู้ใช้ทั่วไป (อยากรับ push ต่อบนเครื่องอื่นที่ยัง sign-in อยู่) และไม่มีความเสี่ยงเพิ่มจริง
- Q2: debounce/รวม push แชทภายในหน้าต่าง **60 วินาทีต่อ match** เป็นการแจ้งเตือนเดียว ข้อความ "มีข้อความใหม่..." (ลด push ถล่มเวลาพิมพ์รัว ๆ); เหตุการณ์ชนิดอื่น (คำขอจับคู่/ตอบรับ/ถึงจุดรับ/ยกเลิก) **ไม่ coalesce** — เป็นเหตุการณ์สำคัญ/ความถี่ต่ำ ต้องส่งทันที
- Q3: ยืนยันเลื่อน iOS/APNs เป็น P1 — ต้องมี Apple Developer Program enrollment ของผู้ใช้ก่อน ไม่ block รอบนี้ (Android+Web ผ่าน FCM ก่อน)
- Q4: snap เพียง**ครั้งเดียว** ตอนผู้ใช้กด "เสนอจุดนี้" เท่านั้น (ไม่ snap ทุกครั้งที่ปล่อยหมุดระหว่างลาก) — ลดจำนวนเรียก OSRM ลงมาก เคารพ public OSRM rate limit และลด flicker ของหมุดระหว่างผู้ใช้ยังปรับตำแหน่งอยู่
- Q5: ยืนยันตามสมมติฐาน BA — vibe tags/mood ผูกกับ **ทริป** ไม่ใช่โปรไฟล์ (เคลียร์อัตโนมัติเมื่อจบทริป/24 ชม.)
- Q6: **เปลี่ยนสมมติฐานเดิม** — ยังคง mood เป็น free text ≤35 ตัวอักษรตามร่าง แต่เพิ่ม guard ราคาถูกทั้ง client และ server: ปฏิเสธข้อความที่มีเลขติดกัน ≥8 หลัก (รูปแบบคล้ายเบอร์โทร) หรือชนกับ blocklist คำหยาบชุดเล็ก; ความเสี่ยงที่เหลือ (เนื้อหาไม่เหมาะสมรูปแบบอื่นที่ไม่ใช่เบอร์โทร/คำหยาบในลิสต์) ยอมรับและบันทึกเป็นความเสี่ยงต่อ ไม่ใช่ full moderation — เหตุผล: บล็อกความเสี่ยงที่พบบ่อยและถูกที่สุดโดยไม่ต้องเลื่อน/ตัด free text ทั้งหมดซึ่งกระทบ UX ของ story มากเกินไป
- Q7: การลบฟิลด์เพศขณะมีคำขอ/จับคู่ women-only ที่ pending อยู่ ให้ **auto-cancel คำขอ/จับคู่ที่ pending นั้นทันที** พร้อมข้อความสุภาพแจ้งทั้งสองฝ่าย (ไม่เปิดเผยเหตุผลจริงเจาะจงเรื่องเพศของอีกฝ่าย) — เหตุผล: การเปิดสวิตช์ women-only คือสัญญาความปลอดภัยเฉพาะเจาะจง เมื่อเงื่อนไขไม่เป็นจริงแล้วต้องไม่ปล่อยให้ค้าง match ที่ผิดเงื่อนไขต่อ
- Q8: **ไม่ต้องมีการจัดการพิเศษเพิ่มเติม** — ทั้งสวิตช์สถาบันเดียวกันและ women-only ต้องบังคับที่ `find_matches` (server-side) ให้เช็คสถานะ verification/เพศแบบ **สด (live)** ทุกครั้งที่ค้นหา ไม่ใช่ cache ค่าที่ตั้งไว้ตอนเปิดสวิตช์ ดังนั้น verification หมดอายุ/เปลี่ยนอีเมลจะทำให้ผู้ใช้หลุดจากสระการค้นหานั้นในครั้งค้นหาถัดไปโดยอัตโนมัติ ไม่ต้องมี job แยกไปปิดสวิตช์ที่บันทึกไว้ (สวิตช์ที่ผู้ใช้ตั้งไว้ยังคง "เปิด" อยู่ในหน้าตั้งค่าได้ แต่ไม่มีผลจนกว่าเงื่อนไขจริงกลับมาตรง)
- Q9: ป้าย "(โดยประมาณ)" บนการ์ด CO₂ บวก **footnote/disclaimer หนึ่งบรรทัด** (เช่น "ตัวเลขนี้เป็นค่าประมาณเพื่อสร้างแรงบันดาลใจ ไม่ใช่ค่าที่รับรองทางวิทยาศาสตร์") เพียงพอแล้ว ไม่ใช่การกล่าวอ้างเชิงการตลาด — ไม่ต้องขอฝ่ายกฎหมายทบทวนเพิ่มในรอบนี้
- Q10: คง Stage เดิมตามร่าง A (US-42+43) → B (US-44+45) → C (US-46+47); ทุก schema ใหม่/เปลี่ยน (`device_tokens`, `push_outbox`, `profiles.gender`, คอลัมน์ vibe/mood ต่อทริป) **ต้องผ่าน /db-architect** (audit + verify แบบ rolled-back บน live DB ก่อน apply จริงเสมอ ตามวินัยรอบ 3-6) — งานนี้มีแนวโน้มเป็น **คอขวดจริงของแต่ละ Stage** ไม่ใช่งาน Dart/UI ดังนั้นให้เริ่มงาน /db-architect ของแต่ละ Stage ให้เร็วที่สุดและขนานกับงาน UI ที่ไม่พึ่ง schema
- ต้องอัป requirements: **ใช่ (Q6, Q7 เปลี่ยน AC จริง)** รายการให้ BA แก้ `requirements-round7-ba.md`:
  1. US-44 AC บรรทัด "ข้อความ mood ยาวไม่เกิน 35 ตัวอักษร; ไม่มีการกรองคำหยาบ/PII อัตโนมัติในรอบนี้" (บรรทัด ~100) → แก้เป็น: มี guard ราคาถูกทั้ง client/server ปฏิเสธเลขติดกัน ≥8 หลัก และคำในบล็อกลิสต์ขนาดเล็ก; ความเสี่ยงที่เหลือเกินกว่านี้ยังคงบันทึกเป็นความเสี่ยง ไม่ใช่ full moderation
  2. สมมติฐานข้อ 9 (บรรทัด ~33) และ Edge case US-44 (บรรทัด ~197) ปรับข้อความให้ตรงกับ Q6 (ไม่ใช่ "ไม่มีการกรองอัตโนมัติ" เฉย ๆ อีกต่อไป)
  3. Out of Scope (บรรทัด ~219) แก้ข้อ "การกรองคำหยาบ/PII อัตโนมัติในข้อความ mood" ให้ระบุว่าทำแบบ guard พื้นฐานแล้วตาม Q6 ไม่ใช่ยกเว้นทั้งหมด
  4. US-45 AC บรรทัด "การลบทำให้สวิตช์ women-only ปิดอัตโนมัติ" (บรรทัด ~123) → เพิ่มว่า ถ้ามีคำขอ/จับคู่ women-only ที่ pending อยู่ ณ ตอนลบ ต้อง **auto-cancel** คำขอ/จับคู่นั้นทันทีพร้อมข้อความสุภาพแจ้งทั้งสองฝ่าย (ไม่ระบุเหตุผลเจาะจงเรื่องเพศ)
  5. Edge case US-45 (บรรทัด ~198) ปิดคำถามเปิด Q7/Q8 เป็น "PM ตัดสินแล้ว" ตามข้อ Q7/Q8 ข้างต้น
  6. Q1-Q10 ทั้งหมด: เปลี่ยนสถานะเป็น "PM ยืนยันแล้ว" ปิดหัวข้อ "คำถามเปิดสำหรับ PM" ของรอบ 7

## ลำดับทำ (staging, มิเรอร์ A/B/C จากร่าง)
1. **Stage A (P0)**: US-42 (Push) + US-43 (Road-snap) — เริ่ม /db-architect ของ `device_tokens`/`push_outbox` ทันทีเป็นงานแรกของรอบ (คอขวด); งาน Dart client/UI ของทั้งสอง US ทำขนานได้โดยไม่ต้องรอ schema เสร็จสมบูรณ์ (mock ตารางระหว่างพัฒนา)
2. **Stage B (P1)**: US-44 (Vibe/mood) + US-45 (สวิตช์สถาบัน + women-only) — เริ่ม /db-architect ของ `profiles.gender` และคอลัมน์ vibe/mood ต่อทริปได้ทันทีที่ Stage A ส่งต่องาน (ขนานกับ Stage A ตอนท้ายได้ถ้ากำลังคนพอ เพราะไม่มี dependency ทางเทคนิคข้าม Stage)
3. **Stage C (P1/P2)**: US-46 (Dark mode) + US-47 (Shared impact/haptics) — ไม่พึ่ง /db-architect เลย ทำขนานกับ B ได้เต็มที่ถ้ากำลังคนเพียงพอ เพื่อไม่ให้รอ Stage B ที่ติดคอขวด DB
4. **Stage D (ทดสอบ/QA/release)**: หลัง A/B/C แต่ละงานผ่านทดสอบของตัวเองแล้ว

> **หมายเหตุอัปเดต (ดูหัวข้อ "รวมแผนงาน Stage A/B/C ฉบับเต็ม" ท้ายไฟล์):** การจัด Stage ข้างบนนี้เป็นฉบับตั้งต้น (เฉพาะ US-42..US-47) ร่างผู้ใช้รอบขยายภายหลังเพิ่ม US-48/49/50 และจัดกลุ่ม Stage ใหม่เป็น **A=42+43, B=46+48+44+45, C=49+50+47** (ย้าย US-46 จาก C เดิมไปอยู่ B ใหม่ และ US-47 จาก C เดิมไปอยู่ C ใหม่ร่วมกับ US-49/50) — ใช้การจัดกลุ่มใหม่นี้เป็นหลักตั้งแต่นี้ไป งานย่อย R7.1-R7.27 ด้านล่างยังใช้ได้ทั้งหมด เพียงแต่ "Stage C" ในหัวข้อเดิมด้านล่าง (US-46+US-47) ถูกแทนที่ด้วยการจัดกลุ่มใหม่ตามนี้

## P0 (ต้องมี) — Stage A

### Push Notifications (US-42)
- [ ] R7.1: schema `device_tokens (user_id, token, platform, updated_at)` + RLS (เจ้าของแถวเท่านั้นเห็น/เขียนของตน) — **owner: /db-architect** — size M — dependency: ไม่มี (เริ่มก่อนสุดของรอบ)
- [ ] R7.2: schema `push_outbox` (ตาราง outbox) + DB trigger insert แถวเมื่อ: สร้างคำขอจับคู่, จับคู่ตอบรับ, ข้อความแชทใหม่, คนขับถึงจุดรับ (US-33 เดิม), ยกเลิกจับคู่/ทริป — **owner: /db-architect** — size M — dependency: R7.1
- [ ] R7.3: Dart client: ขอสิทธิ์แจ้งเตือนพร้อมคำอธิบายไทย (ไม่ block ถ้าปฏิเสธ), ลงทะเบียน/อัปเดต token ที่ `device_tokens` (token ซ้ำ = update ไม่ insert ซ้ำ) — size M — dependency: R7.1 (mock ได้ระหว่างรอ schema จริง)
- [ ] R7.4: ขยาย flow sign-out และลบบัญชี (US-15 เดิม) ให้ลบ `device_tokens` ของอุปกรณ์นั้นทันที (Q1: เฉพาะอุปกรณ์นี้ ไม่ลบทุกเครื่อง) — size S — dependency: R7.1, R7.3
- [ ] R7.5: payload data-only/opaque เท่านั้น (`kind` + `trip_id`/`match_id`) render ข้อความไทยฝั่ง client จาก `strings_trip.dart`/`strings_roles.dart` เพียงแหล่งเดียว — size S — dependency: R7.3
- [ ] R7.6: deep-link routing เมื่อแตะ push ไปหน้าที่เกี่ยวข้อง (ใช้เส้นทางเดิม `/matches/:id/live` รอบ 6); session หลุด → ไปหน้าเข้าสู่ระบบแล้วนำทางต่อได้หลัง login โดยไม่เสียปลายทาง; แตะขณะแอปเปิดหน้าอื่นอยู่ไม่ทำ state ปัจจุบันหาย — size M — dependency: R7.3, R7.5
- [ ] R7.7: wiring เหตุการณ์ trigger → `push_outbox` รวม **coalescing แชทภายใน 60 วิ/match เป็น 1 แจ้งเตือน "มีข้อความใหม่..."** (Q2) ส่วนเหตุการณ์อื่น (คำขอ/ตอบรับ/ถึงจุดรับ/ยกเลิก) ส่งทันทีไม่ coalesce — size M — dependency: R7.2 — **owner: /db-architect** (ตรรกะ coalesce ทำใน trigger/SQL หรือชั้น edge function ก็ได้ แต่ schema ส่วนนับเวลาต้องผ่าน /db-architect)
- [ ] R7.8: scheduled Edge Function drain `push_outbox` (รูปแบบเดียวกับ `purge-storage-queue`: service_role key + cron secret) เรียก FCM HTTP v1; Android+Web เท่านั้นรอบนี้ (Q3: iOS/APNs เลื่อน P1 รอ Apple Developer Program ของผู้ใช้); **ต้องขออนุมัติ deploy จากผู้ใช้ก่อนเสมอ** — size M — dependency: R7.2, R7.7
- [ ] R7.9: ล้าง token ออกจาก `device_tokens` เมื่อ FCM ตอบ error เฉพาะว่า token invalid/expired (กันยิงซ้ำไปเรื่อย ๆ) — size S — dependency: R7.8
- [ ] R7.10: mode/stub สำหรับ CI ทดสอบ payload opaque + flow deep-link โดยไม่ยิงถึง FCM จริง (ไม่ต้องรอ Firebase project ของผู้ใช้ ซึ่งเป็น dependency เฉพาะการทดสอบ end-to-end จริงเท่านั้น) — size M — dependency: R7.3, R7.5

### Road-Snapped Pickup Pin (US-43)
- [ ] R7.11: เรียก OSRM `nearest` **เฉพาะครั้งเดียวตอนกดปุ่ม "เสนอจุดนี้"** (Q4 — ไม่ snap ทุกครั้งที่ปล่อยหมุดระหว่างลาก), endpoint สลับได้ผ่าน config แบบเดียวกับ `OSRM_BASE_URL_CAR`/`_FOOT`; ตรวจระยะเบี่ยงของผลลัพธ์ก่อนยอมรับ (เกินเกณฑ์ = ไม่ snap ใช้จุดดิบ); timeout สั้น + fallback จุดดิบทันทีเมื่อ fail/timeout/rate-limit (fail-open ต่อผู้ใช้) — แก้ `lib/features/matching/presentation/pickup_screen.dart` และ `geo/pick_point_screen.dart` — size M — dependency: ไม่มี, ไม่พึ่ง /db-architect (ไม่มีคอลัมน์ใหม่)
- [ ] R7.12: ข้อความสั้น "ปรับหมุดให้ตรงถนนแล้ว" หลัง snap, ยังลากแก้ตำแหน่งเองได้ต่อก่อนกดยืนยันเสนอจริง; ต่อเข้ากับ flow `propose_meeting_point`/`confirm_meeting_point` เดิมทั้งหมดโดยไม่แก้ RPC/RLS; คำเตือน off-route เดิมยังทำงานคู่กันไม่ถูกแทนที่ — size S — dependency: R7.11

## P1 (ควรมี) — Stage B (ฉบับตั้งต้น: US-44/45 เท่านั้น — ดูหมายเหตุด้านบน สำหรับ Stage B จริงที่รวม US-46/48 ด้วย)

### Vibe Tags & Daily Mood (US-44)
- [ ] R7.13: schema คอลัมน์ vibe tag/mood ผูกกับทริป (ไม่ใช่ `profiles` — Q5 ยืนยัน) + กลไกเคลียร์อัตโนมัติเมื่อจบทริปหรือผ่าน 24 ชม. — **owner: /db-architect** — size M — dependency: ไม่มี (เริ่มขนานกับ Stage A ได้)
- [ ] R7.14: UI เลือกแท็กสูงสุด 3 จาก allow-list ตายตัว (server-validate ปฏิเสธนอกลิสต์) แสดงเป็นชิปบน CommuteCardDeck โดยไม่บดบังข้อมูลความปลอดภัย (ป้าย/บทบาท/ระยะรับส่ง) — size M — dependency: R7.13
- [ ] R7.15: mood free text ≤35 ตัวอักษร + **guard PII/คำหยาบราคาถูกทั้ง client และ server** ตาม Q6 (ปฏิเสธเลขติดกัน ≥8 หลัก, บล็อกลิสต์คำหยาบขนาดเล็ก); ข้อความไทยอธิบายเหตุผลปฏิเสธแบบไม่เปิดเผยรายละเอียดกฎกรอง — size M — dependency: R7.13
- [ ] R7.16: ทริปไม่มีแท็ก/mood แสดงการ์ดปกติไม่มีช่องว่างที่ดูเป็นบั๊ก (สอดคล้อง layout US-34/36 เดิม); ผู้ใช้ล้างเองก่อนหมดเวลาได้ — size S — dependency: R7.14, R7.15

### สวิตช์สถาบันเดียวกัน + Women-Only (US-45)
- [ ] R7.17: schema `profiles.gender` (nullable, optional, self-view only, ลบเองได้) — **owner: /db-architect** — size S — dependency: ไม่มี
- [ ] R7.18: ขยาย `find_matches`: เงื่อนไข "สถาบันเดียวกัน" (ทั้งสองฝ่ายเปิดสวิตช์ + `org_suffix` ยืนยันแล้วตรงกัน, เช็คสดจาก `verifications`/`org_domains` เดิม ไม่ cache — Q8); เงื่อนไข women-only (ทั้งสองฝ่ายเปิดสวิตช์ + gender=หญิงทั้งคู่ เช็คสดเช่นกัน); ทั้งสองสวิตช์เปิดพร้อมกัน = AND ทุกเงื่อนไข; ห้ามคืนค่าฟิลด์เพศจริงของอีกฝ่ายผ่าน API — **owner: /db-architect** — size L — dependency: R7.17, `org_domains`/`verifications` เดิม (ไม่แตะ)
  - **อัปเดต (Q-G4, UIUX round 7):** สวิตช์ทั้งสอง (institution-only, women-only) ผูกกับ **"ทริป"** (เหมือน `max_dropoff_m`/vibe/mood) ไม่ใช่ผูกกับโปรไฟล์หรือค้นหาแต่ละครั้ง → คอลัมน์จริงคือ `trips.same_org_only` และ `trips.women_only` (ตั้งชื่อสุดท้ายให้ /db-architect ยืนยันตอน implement 0012) เช็คสดจาก `profiles.gender`/`verifications` ของคู่กรณี ณ ขณะ `find_matches` รันเสมอ
- [ ] R7.19: **auto-cancel** คำขอ/จับคู่ women-only ที่ pending อยู่ทันทีที่ผู้ใช้ลบ/ล้างฟิลด์เพศ พร้อมข้อความสุภาพแจ้งทั้งสองฝ่าย (ไม่เปิดเผยเหตุผลเจาะจงเรื่องเพศ — Q7) ต่อผ่าน `push_outbox`/แชทเดิมสำหรับแจ้งเตือน — size M — dependency: R7.17, R7.18, R7.2/R7.7 (ใช้ช่องแจ้งเตือน) — **DB decision (14.8-7):** ใช้ loop-based auto-cancel ยอมรับได้ (จำนวนแถว pending ต่อผู้ใช้น้อย ไม่ต้อง set-based optimization)
- [ ] R7.20: UI สวิตช์ "หาเฉพาะเพื่อนในสถาบันเดียวกัน": เปิดได้เมื่อมี org verification เดิม; ถ้าไม่มีให้ข้อความชี้ทางไปหน้ายืนยันอีเมลเดิม ไม่สร้างขั้นตอนใหม่ — size S — dependency: R7.18
- [ ] R7.21: UI สวิตช์ women-only: เปิดได้เฉพาะเมื่อระบุเพศเป็นหญิง+ยินยอมใช้เพื่อจับคู่; แสดงเฉพาะสถานะเปิด/ปิดของตนเอง ไม่แสดงค่าจริงบนการ์ด/Match Moment/UnifiedRideScreen; ปุ่มลบฟิลด์เพศ (ผูกกับ R7.19) — size M — dependency: R7.17, R7.19
  - **อัปเดต (Q-G3, UIUX):** วาง `GenderSettingsScreen` เคียงหน้า privacy settings (ไม่เคียงหน้า verification เพื่อไม่ให้เข้าใจผิดว่าต้อง "ยืนยัน" เพศ)

## P1 (ควรมี) — Stage C (ฉบับตั้งต้น: US-46/47 เท่านั้น — ดูหมายเหตุด้านบน)

### Dark Mode (US-46)
- [ ] R7.22: tone token ชุดใหม่ `rider-dark`/`driver-dark` ต่อยอด token เดิม (ไม่กระทบ token สว่างเดิม); tile แผนที่โหมดมืดสลับผ่าน config เดียวกับ `TILE_URL` เดิม (เช่น CartoDB Dark Matter) — size M — dependency: ไม่มี (ไม่พึ่ง /db-architect, ทำขนานกับ Stage B ได้เต็มที่)
  - **อัปเดต (Q-G5, UIUX):** `driver-dark` ใช้ amber จางกว่า `driver-light` (ลดแสงจ้าตอนขับกลางคืน) ตามที่ UIUX ออกแบบไว้
- [ ] R7.23: สลับ system/manual override ในหน้าตั้งค่า (**อัปเดต: ต้องเป็น 4 โหมดจริงตาม AC ล่าสุดของ US-46 — System/Light/Dark/Auto-by-time 18:00–06:00, ดู R7.22a ด้านล่าง**); สลับขณะทริปกำลังดำเนิน (UnifiedRideScreen) ไม่รีเซ็ตสถานะทริป/แชท/ตำแหน่ง sheet (US-29 รอบ 6); ไม่รีโหลด/กระตุกทั้งหน้าจอ; อุปกรณ์ไม่รองรับ system API เก่า = fallback manual toggle เท่านั้น — size M — dependency: R7.22
- [ ] R7.24: หมุดรถ/คนเดิน/จุดนัดรับผ่าน WCAG AA contrast บน tile มืด; retest contrast geofence เขียว (US-32 รอบ 6) และ badge/ปุ่มสำคัญในโหมดมืด — size S — dependency: R7.22

### Shared Impact & Haptics (US-47)
- [ ] R7.25: การ์ดสรุป CO₂ หลังสไลด์ถึงที่หมาย (ต่อ label US-31/US-40 รอบ 6): สูตร ระยะร่วมกัน × ~120 g/km, ป้าย "(โดยประมาณ)" **+ footnote/disclaimer หนึ่งบรรทัด** (Q9); ซ่อนตัวเลขเมื่อระยะ=0/คำนวณไม่ได้; ไม่แสดงส่วนเพื่อนเมื่อทริปไม่มีคู่ตอบรับ/ยกเลิกก่อนถึง/บล็อกกันแล้ว — size M — dependency: US-31/40 เดิม (ไม่แตะ)
- [ ] R7.26: ปุ่ม "สติกเกอร์ขอบคุณ" preset เท่านั้น ใช้รูปแบบ quick-reply แชทเดิม (US-8/US-24) ไม่มีช่องพิมพ์อิสระ — size S — dependency: quick-reply เดิม (ไม่แตะ)
- [ ] R7.27: haptics ต่อยอด `lib/core/widgets/swipe_to_confirm_slider.dart` hook `disableAnimations` เดิม: selection tap เบาเมื่อลากการ์ด deck, heavy impact เมื่อ slider สำเร็จที่ 95%; เคารพ reduce-motion/haptics ของ OS เสมอ (ปิดเมื่อผู้ใช้ตั้งลดการเคลื่อนไหว) — size M — dependency: ไม่มี (ทำขนานกับ R7.25/26 ได้)

## Stage D: ทดสอบ / a11y / security / release
- [ ] R7.28 (P0): unit/widget test — push stub mode (opaque payload, deep-link+session-lost, coalescing 59/60/61 วิ per-match), device_tokens ลบเฉพาะอุปกรณ์นี้ (Q1), road-snap deviation threshold + fallback timeout — size L — dependency: R7.10, R7.6, R7.7, R7.11
- [ ] R7.29 (P0): SQL test แบบ rolled-back สำหรับ schema ใหม่ทั้งหมด (`device_tokens`, `push_outbox`, `profiles.gender`, vibe/mood ต่อทริป) + regression `find_matches` เดิม (ไม่กระทบ Peer/car/rating รอบ 6) — **owner: /db-architect** — size L — dependency: R7.1, R7.2, R7.13, R7.17, R7.18
- [ ] R7.30 (P0): security test ตรง API — women-only ไม่คืนค่าเพศจริงของอีกฝ่าย; org/women-only เช็คสด ไม่ cache (ปิด verification แล้วหลุดจากสระค้นหาถัดไปจริง); mood guard ปฏิเสธเลขติดกัน/คำในบล็อกลิสต์ทั้ง client/server — size M — dependency: R7.18, R7.15
- [ ] R7.31 (P0): a11y pass — push แจ้งเตือนอ่านได้ด้วย screen reader, contrast dark mode (WCAG AA), haptics เป็นส่วนเสริมเท่านั้น (มี label คู่กันเสมอ) เคารพ reduce-motion — size M — dependency: R7.23, R7.24, R7.27
- [ ] R7.32 (P0): perf check — drain `push_outbox` เป็น background แยกจาก request path (ไม่เพิ่ม latency `request_match`/ส่งแชท), OSRM `nearest` เรียกครั้งเดียวไม่ทำ flow เสนอจุดช้าลงมีนัยสำคัญ, query แท็ก/mood ไม่ทำ `find_matches`/deck ช้าเกินกรอบเดิม — size M — dependency: R7.8, R7.11, R7.14
- [ ] R7.33 (P0): `flutter analyze` สะอาด + ชุดเดิมทั้งหมดผ่าน ยกเว้นที่แก้ตั้งใจ — size S — dependency: R7.28
- [ ] R7.34 (P0): BA แก้ `requirements-round7-ba.md` ตามรายการ "ต้องอัป requirements" ข้างบน (Q6/Q7 AC + ปิด Q1-Q10) — size S — dependency: ไม่มี (ทำก่อน QA) — **สถานะ: ทำเสร็จแล้ว** (ดู `requirements-round7-ba.md` ปัจจุบันซึ่งปิด Q1-Q10 หมดแล้วและมี US-42..US-50 ครบ)
- [ ] R7.35 (P1): Live-DB rollout เรียงตาม Stage: A (`device_tokens`/`push_outbox`) → B (`profiles.gender`, vibe/mood ต่อทริป, `find_matches` ขยาย) — แต่ละตัว dry-run rolled-back + regression เดิมทั้งชุดก่อน → รายงานผู้ใช้ → **apply เฉพาะเมื่อผู้ใช้อนุมัติชัดเจน** → smoke test + advisor; แผนถอยกลับระบุต่อ schema — size L — dependency: R7.29 — **อัปเดต: ต้องต่อคิวรวมกับ Stage B/C ใหม่ (0012/0013/0014/0015 ด้านล่าง) เป็นลำดับเดียวกัน ไม่แยกสอง track**
- [ ] R7.36 (P0 gate ไม่บล็อกพัฒนา): อนุมัติ deploy Edge Function drain `push_outbox` จากผู้ใช้ก่อนเสมอ (เช่นเดียวกับ `purge-storage-queue` ที่ค้างรอบ 5 — แยกเรื่องกัน ไม่ deploy พร้อมกัน) — size S — dependency: R7.8
- [ ] R7.37 (P0): QA เว็บ 2 โปรไฟล์ Chrome ครอบคลุม: push (stub mode, coalescing, deep-link), road-snap (fallback เมื่อ mock service ล้มเหลว), vibe/mood เคลียร์อัตโนมัติ, สวิตช์สถาบัน+women-only (AND logic, auto-cancel เมื่อผู้ใช้ลบเพศ), dark mode toggle กลางทริป, การ์ด CO₂ + สติกเกอร์ขอบคุณ, haptics respect reduce-motion + a11y screen reader อย่างน้อย 1 แพลตฟอร์ม — size M — dependency: R7.33, R7.34 — **อัปเดต: QA รอบเดียวนี้ยังไม่ครอบคลุม US-48/49/50 — ดู R7.63 ใหม่ท้ายไฟล์สำหรับรอบ QA เพิ่มของ Stage B/C ใหม่**

## ไฟล์/เทสต์ที่ได้รับผลกระทบ (ใช้ของเดิม ไม่สร้างซ้ำ)
- `lib/features/matching/presentation/pickup_screen.dart`, `geo/pick_point_screen.dart` — เพิ่ม call OSRM nearest ครั้งเดียวก่อนเสนอจุด (R7.11/12) ไม่แก้ flow propose/confirm เดิม
- ตาราง `org_domains`, `verifications` เดิม — **ใช้ join/เช็คสดเท่านั้น ห้ามสร้างซ้ำ** สำหรับสวิตช์สถาบันเดียวกัน (R7.18/20)
- `lib/core/widgets/swipe_to_confirm_slider.dart` — ต่อยอด hook `disableAnimations` เดิมสำหรับ haptics (R7.27) ไม่สร้าง widget ใหม่
- tone token files/`TILE_URL` config เดิม — เพิ่มชุด dark เท่านั้น (R7.22)
- แชท quick-reply pattern เดิม (US-8/US-24) — ใช้ซ้ำสำหรับสติกเกอร์ขอบคุณ (R7.26) และวลีสำเร็จรูปพูดด้วยเสียง US-48(B) (R7.43) ไม่สร้างระบบข้อความสำเร็จรูปที่สอง
- `strings_trip.dart`/`strings_roles.dart` — เพิ่มข้อความ render จาก push payload (R7.5), guard error ของ mood (R7.15)
- `storage_purge_queue`/Edge Function เดิม (ค้างรอบ 5/6) — ขยาย drain หลาย bucket/รับ bucket param สำหรับ audio bucket ของ US-48(A) (R7.39) ไม่สร้างกลไก cleanup ใหม่
- `PresetController`/preset Home-Office เดิม (US-38 รอบ 6) — เพิ่มหมวดใหม่ "จุดต่อรถขนส่งสาธารณะ" (R7.58) แต่แหล่งข้อมูล/storage แยกจาก device-local secure storage เดิมโดยสิ้นเชิง
- ไฟล์ใหม่: `device_tokens`/`push_outbox` migration + client repo, Edge Function drain, `profiles.gender` migration, vibe/mood ต่อทริป migration, `find_matches` migration ขยาย (org/women-only), private audio bucket migration, `transit_hubs` reference table migration, `trips.transit_hub_detour_m` migration
- test ที่ต้องเพิ่ม: push stub mode, coalescing window, road-snap deviation/fallback, mood guard client+server, find_matches security (ไม่คืนเพศจริง, เช็คสด), dark mode contrast/state-preserve, haptics reduce-motion, US-48 isolation test (A vs B), US-49 no-fault cancel schema regression, US-50 OSRM fail-closed + radius boundary

## Dependency หลัก (ย่อ)
- R7.1 → R7.2 → (R7.7, R7.8) → R7.9, R7.36; R7.1/R7.3 → R7.4, R7.5 → R7.6
- R7.11 → R7.12 (ไม่พึ่ง /db-architect เลย ทำขนานเต็มที่กับ push งานอื่น)
- R7.13 → (R7.14, R7.15) → R7.16
- R7.17 → R7.18 → (R7.19, R7.20, R7.21); R7.19 พึ่ง R7.7 ด้วย (ใช้ช่องแจ้งเตือน)
- R7.22 → R7.23, R7.24 (ไม่พึ่ง /db-architect เลย ทำขนานกับ Stage B ได้เต็มที่)
- R7.25/26/27 ไม่พึ่งกันเอง ทำขนานได้
- R7.28/29/30/31/32 → R7.33 → R7.37; R7.34 ก่อน R7.37; R7.35 พึ่ง R7.29 (เฉพาะ schema ใหม่)

## Release notes (ร่างสำหรับผู้ใช้)
- ได้รับแจ้งเตือนบนมือถือแม้ปิดแอปเมื่อมีคนชวน/ตอบรับ/ถึงจุดรับ/ยกเลิก (Android/เว็บก่อน iOS ตามมาทีหลัง)
- ข้อความแชทที่พิมพ์ติด ๆ กันภายใน 1 นาทีรวมเป็นแจ้งเตือนเดียว ไม่ถล่มมือถือ
- ลากหมุดจุดนัดรับแล้วกด "เสนอจุดนี้" ระบบช่วยขยับให้ตรงถนนให้อัตโนมัติ ยังลากแก้ได้ก่อนยืนยัน
- เพิ่มแท็ก vibe และข้อความสั้นประจำวันบนการ์ดเดินทาง (หายเองเมื่อจบทริปหรือ 24 ชม.)
- เปิดหาเฉพาะเพื่อนสถาบันเดียวกัน หรือเฉพาะผู้หญิงด้วยกันได้ (ข้อมูลเพศเห็นแค่ตัวเอง ลบได้เอง)
- โหมดมืดสำหรับขับตอนกลางคืน สลับได้ทั้งอัตโนมัติตามระบบและเลือกเอง
- การ์ดสรุปลดคาร์บอนหลังจบทริป พร้อมส่งสติกเกอร์ขอบคุณและสัมผัสสั่นตอนยืนยันสำเร็จ

## ความเสี่ยง
1. (สูง) /db-architect เป็นคอขวดจริงของทั้ง 3 Stage (schema ใหม่ 4-5 ตาราง/คอลัมน์ในรอบเดียว) — บรรเทาโดยเริ่มคิว /db-architect ของแต่ละ Stage ให้เร็วที่สุดและให้งาน UI ที่ไม่พึ่ง schema (dark mode, road-snap, haptics, sticker) ทำขนานเต็มที่
2. (สูง) การ deploy Edge Function drain `push_outbox` ต้องรออนุมัติผู้ใช้ (เหมือน `purge-storage-queue` ที่ค้างมาตั้งแต่รอบ 5) — ถ้าผู้ใช้ยังไม่อนุมัติ ฟีเจอร์ push จะพร้อมโค้ดแต่ยังส่งจริงไม่ได้ ต้องแจ้งชัดเจนว่าเป็นสถานะ "รอ" ไม่ใช่ "เสร็จ"
3. (กลาง) mood free-text guard (Q6) เป็นการลดความเสี่ยงบางส่วนเท่านั้น เนื้อหาไม่เหมาะสมรูปแบบอื่นยังหลุดได้ — ต้องมีทางรายงานเนื้อหาแบบเดิมที่มีอยู่ (ไม่ใช่ของใหม่) รองรับ escalate ได้
4. (กลาง) women-only auto-cancel (Q7) ต้องระวังไม่ให้ข้อความแจ้งเผลอเปิดเผยเหตุผลเจาะจงเรื่องเพศของอีกฝ่าย — ต้องเขียน copy ให้เป็นกลางจริง (เช่น "เงื่อนไขการจับคู่พิเศษไม่ครบแล้ว" ไม่ใช่ "อีกฝ่ายไม่ใช่ผู้หญิงแล้ว")
5. (กลาง) find_matches เช็คสด (Q8) ต้องไม่ทำให้ query ช้าลงเกินกรอบเดิม (ต้อง join กับ verifications/gender ทุกครั้ง) — ต้องวัด perf จริงใน R7.32/R7.29
6. (ต่ำ) OSRM public rate limit — snap ครั้งเดียวต่อการเสนอจุด (Q4) ช่วยลดแล้ว แต่ยังต้อง monitor ถ้าผู้ใช้เยอะพร้อมกัน
7. (ต่ำ) iOS/APNs เลื่อนออก (Q3) กระทบ parity ระหว่างแพลตฟอร์ม — ต้องสื่อสารชัดในหน้า release note ว่า iOS ยังไม่ได้ push จริง

## แผนตรวจสอบ (Verification)
- Tester: unit/widget test ตาม R7.28, `flutter analyze` สะอาด, ชุดเดิมผ่านทั้งหมด; SQL test แบบ rolled-back ตาม R7.29 สำหรับทุก schema ใหม่ + regression find_matches เดิม
- Security: R7.30 (API ไม่คืนเพศจริง, live-check ไม่ cache, mood guard client+server, payload push เป็น opaque จริงไม่มี PII)
- a11y: R7.31 (screen reader อ่าน push ได้, contrast dark mode WCAG AA, haptics เป็นส่วนเสริมมี label คู่เสมอ, เคารพ reduce-motion)
- Perf: R7.32 (push drain ไม่เพิ่ม latency RPC เดิม, OSRM nearest ไม่ทำ flow ช้าอย่างมีนัยสำคัญ, query vibe/mood ไม่ทำ deck ช้าเกินกรอบเดิม)
- QA: R7.37 ตรวจเว็บ 2 โปรไฟล์ตามรายการ อ่านผลจาก `docs/qa-result.md`
- Live DB: ใช้เฉพาะ R7.1, R7.2, R7.13, R7.17, R7.18 (และ trigger ที่เกี่ยวข้อง) เท่านั้น เรียงลำดับ dry-run rolled-back ก่อนเสมอ → รายงานผู้ใช้ → apply เฉพาะเมื่อผู้ใช้อนุมัติชัดเจน (ห้าม apply เอง); Edge Function deploy (R7.36) เป็นการอนุมัติแยกอีกชั้นหนึ่ง คนละขั้นกับการ apply schema

## สรุปจำนวน
- P0: 22 งาน (R7.1-R7.12 = 12 งานพัฒนา Stage A; R7.28-R7.34, R7.36-R7.37 = 10 งานทดสอบ/QA/BA/gate)
- P1: R7.13-R7.24, R7.35 (13 งาน); P2: R7.25-R7.27 (3 งาน)
- หมายเหตุ: US-47 เป็น P2 ตาม BA แต่จัดใน Stage C เดียวกับ US-46 (P1) เพราะไม่พึ่ง /db-architect เหมือนกัน ทำขนานได้โดยไม่กระทบลำดับ P0/P1
- **อัปเดต (ดูหัวข้อรวมท้ายไฟล์):** ตัวเลขข้างบนนี้เป็นสรุปเฉพาะ US-42..US-47 (ฉบับตั้งต้น) รวมงานใหม่ของ US-48/49/50 แล้วดูสรุปจำนวนรวมในหัวข้อ "สรุปจำนวนรวม (ฉบับเต็ม A/B/C)" ท้ายไฟล์

## คำตัดสิน (Orchestrator) — รอบ 7 (ถ้ามีคำถามเพิ่มเติมนอกเหนือ Q1-Q10 ให้เติมที่นี่)
- (ว่าง — รอ orchestrator/ผู้ใช้ ถ้ามีประเด็นเพิ่มระหว่างพัฒนา Stage A/B/C)

## คำตัดสิน (Orchestrator) — UIUX round 7 questions Q-G1..Q-G5
- Q-G1: ใช้มาสเตอร์ทอกเกิลเดียวสำหรับการแจ้งเตือน (ไม่ทำ per-kind toggle รอบนี้ ลด schema/db-architect scope)
- Q-G2: mood เกิน 35 ตัวอักษร บล็อกแบบ inline จนกว่าจะแก้ (ไม่ตัดข้อความอัตโนมัติ เพื่อไม่ให้ความหมายขาดหาย)
- Q-G3: วาง GenderSettingsScreen เคียงหน้า privacy settings (ไม่เคียงหน้า verification เพื่อไม่ให้เข้าใจผิดว่าต้อง "ยืนยัน" เพศ)
- Q-G4: สวิตช์ institution-only และ women-only ผูกกับ "ทริป" (ต่อทริป เหมือน max_dropoff_m/vibe/mood) ไม่ใช่ผูกกับโปรไฟล์หรือค้นหาแต่ละครั้ง — DB agent ใช้แนวนี้สำหรับ trips.women_only_only และพารามิเตอร์ same-org ต่อทริป
- Q-G5: driver-dark ใช้ amber จางกว่า driver-light (ลดแสงจ้าตอนขับกลางคืน) ตามที่ UIUX ออกแบบไว้

## คำตัดสิน (Orchestrator) — DB round 7 open questions 14.8-1..8
- 14.8-1: แยก ALTER TYPE ADD VALUE ('driver_arrived') เป็นไฟล์ก่อนหน้า 0011a_message_kind.sql เสมอ (ไม่ต้องรอทดสอบว่าพังก่อน กันความเสี่ยงล่วงหน้า)
- 14.8-2: ต้องตรวจ chat_messages CHECK จริงด้วย \d ก่อน apply (ทำตอนขั้นตรวจ rollback)
- 14.8-4: ยอมรับพฤติกรรมไม่ประเมินย้อนหลัง pending เดิม เหมือนบรรทัดฐานรอบ 5 (car_rule_checked)
- 14.8-5, 14.8-6: ต้องปิดก่อนส่งต่อ programmer — ให้ DB agent อ่าน get_trip_card และ export_my_data เต็มฟังก์ชัน แล้ว (ก) เพิ่ม vibe_tags/mood_text ใน get_trip_card (หรือ RPC ที่ Dart ใช้แสดงบนการ์ด) (ข) เพิ่ม gender/vibe_tags/mood_text ใน export_my_data ทั้งสองอย่างเป็นส่วนหนึ่งของ 0012 (ไม่ต้องแยก 0013)
- 14.8-7: loop-based auto-cancel ยอมรับได้ (จำนวนแถวน้อย)

## คำตัดสิน (Orchestrator) — US-50 จุดต่อรถขนส่งสาธารณะ (หลังคุยกับผู้ใช้)
US-50 ใช้กลไก "ระยะทางเบี่ยงเพิ่มที่ยอมรับได้" (ไม่ใช่ corridor ทั่วไป, ไม่ใช่ "ต้องอยู่บนเส้นทางหลักเป๊ะ"):
- เพิ่มคอลัมน์ใหม่ (แยกจาก `trips.max_dropoff_m` ของรอบ 5 เพราะวัดคนละแบบ): ระยะทางที่คนขับยอมให้เพิ่มขึ้นจริงบนถนน (ไป-กลับ) เพื่อแวะจุดต่อรถขนส่งสาธารณะ
- คนขับปรับเองต่อทริป: ช่วง 200–2,000 เมตร ขยับทีละ 100 ม. ค่าเริ่มต้น 500 ม. เพดานระบบ (config) 2,000 ม.
- ใช้เฉพาะเมื่อปลายทางของคนนั่งตรงกับสถานีในรายการอ้างอิง (BTS/MRT/ท่ารถตู้) ที่กำหนดไว้ล่วงหน้าเท่านั้น ไม่ใช่กฎทั่วไปของทุกทริป
- คำนวณระยะเบี่ยงจากระยะทางถนนจริง (ผ่าน OSRM: route(origin→station→destination) − route(origin→destination)) ไม่ใช่เส้นตรง
- ไม่ต้องมีสวิตช์ยินยอมเพิ่มเติม เพราะตัวเลขที่คนขับตั้งเองคือการยินยอมอยู่แล้ว (เหมือน max_dropoff_m)

## คำตัดสิน (Orchestrator) — round 7 open questions Q11..Q17
- Q11 (นิยาม "ETA ไม่ดีขึ้น"): เข้าเงื่อนไข lateness เมื่อ (ก) เลยเวลานัดหมายเกิน 10 นาที หรือ (ข) ตำแหน่งสดล่าสุด 3 ครั้งติดกัน (~5 นาที) ระยะทางตรงถึงจุดนัดพบไม่ลดลงอย่างน้อย 100 ม. เข้าเงื่อนไขข้อใดข้อหนึ่งพอ
- Q12 (กดพร้อมกัน): first-write-wins แบบ atomic ที่ DB (เหมือน cancel_pending_match เดิม) ฝ่ายที่กดหลังเห็นสถานะที่ตัดสินไปแล้วพร้อมข้อความอธิบาย ไม่ error
- Q13 (no-fault cancel กับระบบรีวิว): ต้องไม่สร้างสถานะที่ทำให้ถูกรีวิวย้อนหลังหรือกระทบสถิติในอนาคต ใช้ ended_reason แยกชนิดชัดเจน (เช่น no_fault_lateness) — /db-architect ต้องตรวจกับ schema match_outcomes/reviews จริงว่าปัจจุบัน eligibility ต้อง "ขึ้นรถแล้ว" อยู่แล้วหรือไม่ (ถ้าใช่ เคสนี้อาจไม่กระทบอะไรเพิ่มอยู่แล้ว แค่ยืนยันด้วยเทสต์)
- Q14 (ชุดข้อมูลสถานี): ให้ orchestrator ดึงพิกัดสถานีรถไฟฟ้าหลัก ๆ (BTS/MRT/ARL จุดเปลี่ยนสาย) จาก OpenStreetMap/Nominatim เป็น seed list เสนอให้ผู้ใช้ตรวจสอบ/อนุมัติก่อนใส่ migration (ไม่ใช้ admin table ในรอบนี้ ทำเป็น reference table ธรรมดาที่แก้ผ่าน migration ไปก่อน)
- Q15 (รัศมีนับว่า "ตรงสถานี"): ปลายทางที่ผู้ใช้ปักห่างจากพิกัดสถานีในรายการไม่เกิน 100 ม. ถือว่าเลือกสถานีนั้น
- Q16 (TTS ถี่เกิน): จำกัด 1 ครั้งต่อ 10 วินาทีต่อคู่ (เหมือน throttle แชทเดิม) กดซ้ำในช่วงนั้นปุ่มถูกปิดชั่วคราว
- Q17 (auto-by-time): ใช้เวลานาฬิกาเครื่องตรง ๆ ไม่ต้องคำนวณพระอาทิตย์ขึ้น-ตก

---

# รวมแผนงาน Stage A/B/C ฉบับเต็ม (รอบ 7 ขยาย — US-42..US-50)

หัวข้อนี้เป็นการรวม/ขยายแผนงานทั้งหมดให้ครบ US-42..US-50 ตาม `requirements-round7-ba.md` ฉบับล่าสุด (ครอบคลุมเต็ม, ปิด Q1-Q10 แล้ว มี Q11-Q17 เป็นคำตัดสิน orchestrator ที่บันทึกไว้ข้างบนแล้ว) — **ไม่ลบของเดิม** (R7.1-R7.37 ด้านบนยังใช้ได้ทั้งหมด) หัวข้อนี้เพิ่มเฉพาะ (ก) การจัดกลุ่ม Stage ใหม่ตามร่างผู้ใช้ล่าสุด (ข) งานของ US-48/49/50 ที่ยังไม่เคยมีเลขงาน (ค) DB migration queue แบบเรียงลำดับจริงที่ /db-architect ต้องทำ (ง) แผนทดสอบ/release notes ที่ครอบคลุมทั้ง 9 story

## สถานะ ณ วันที่เขียน (2026-09-27)
- ตรวจ `docs/dev-notes.md` แล้ว **ไม่พบหัวข้อ "Round 7"** ใด ๆ — หมายความว่า **ยังไม่มีหลักฐานว่า Stage A (US-42+43) ถูก implement แม้บางส่วน** แม้คำสั่งต้นทางจะระบุว่า "already partly done" ก็ตาม — **สิ่งที่ต้องทำ:** โปรแกรมเมอร์/orchestrator ต้องยืนยันสถานะจริงของ R7.1-R7.12 ก่อนเริ่มงานต่อ (อาจกำลังทำอยู่แต่ยังไม่บันทึก dev-notes, หรือยังไม่เริ่มจริง) ห้ามสันนิษฐานว่าเสร็จแล้วโดยไม่ตรวจโค้ด/DB จริง
- ไม่พบไฟล์ migration `0011a`/`0011`/`0012` ในโค้ด local (ค้นหา `**/*.sql` ในโปรเจกต์ไม่พบไฟล์ migration ใด ๆ เลย) — สอดคล้องกับรูปแบบโปรเจกต์นี้ที่ /db-architect ทำงานตรงกับ **live Supabase** (ดู MEMORY: "GOWITHME live Supabase") ไม่ได้เก็บไฟล์ migration ใน repo เสมอไป — ดังนั้นเลขไฟล์ 0011a/0011/0012/0013/0014/0015 ด้านล่างเป็น **ลำดับเชิงตรรกะที่ /db-architect ต้องยึดตาม** ไม่ใช่การยืนยันว่ามีไฟล์จริงในเครื่องนี้แล้ว

## การจัดกลุ่ม Stage ที่ใช้จริง (แทนที่ฉบับตั้งต้นด้านบน)
| Stage | User Stories | เหตุผลจัดกลุ่ม |
|---|---|---|
| **A** (P0) | US-42 (Push) + US-43 (Road-snap) | คอขวด DB แรกสุดของรอบ, ไม่มี dependency ไปยัง story อื่น |
| **B** (P1) | US-46 (Dark mode) + US-48 (Audio notes/voice preset) + US-44 (Vibe/mood) + US-45 (สวิตช์สถาบัน+women-only) | รวม "Identity, Delight & Communication" ตามร่างผู้ใช้ล่าสุด — US-46/48 ไม่พึ่ง schema เดิมมาก จึงทำขนานกับ US-44/45 ที่พึ่ง /db-architect หนักได้ |
| **C** (P1/P2) | US-49 (Lateness/no-fault cancel) + US-50 (Transit-hub detour) + US-47 (Shared impact/haptics) | รวม "Journey Safety & Transit" — US-47 ไม่พึ่ง DB จึงแทรกทำขนานได้แม้ priority ต่ำกว่า |

## Stage A — สถานะงานเดิม (ไม่มีงานใหม่เพิ่ม)
งานทั้งหมดคือ R7.1-R7.12 (พัฒนา) + R7.28/29/30/31/32/33/36 (ทดสอบที่เกี่ยวข้อง) ตามที่มีอยู่แล้วด้านบน **ยังไม่ต้องแก้ไข** — สิ่งเดียวที่เพิ่มคือข้อเตือนสถานะด้านบน (ต้องตรวจของจริงก่อนถือว่าเสร็จบางส่วน)

## Stage B — งานใหม่ที่เพิ่ม (US-48) + อัปเดตอ้างอิง (US-44/45/46 เดิม)
งาน US-44/45/46 คือ R7.13-R7.24 เดิมทั้งหมด (ไม่แก้ เพิ่มแค่หมายเหตุ Q-G3/Q-G4/Q-G5 ที่ระบุไว้ในจุดที่เกี่ยวข้องด้านบนแล้ว) เพิ่มเฉพาะงานของ US-48 ใหม่ดังนี้:

### DB (owner: /db-architect เสมอ)
- [ ] **R7.38**: migration private audio bucket ใหม่ (bucket policy: เจ้าของคู่จับคู่/ทริปนั้นเท่านั้นอ่าน/เขียนได้, signed URL อายุสั้นแบบเดียวกับ avatar bucket รอบ 5) — size M — dependency: ไม่มี — เข้าคิว DB Stage B ต่อจาก 0012 (ดูลำดับ migration queue ด้านล่าง เป็น 0013)
- [ ] **R7.39**: ขยาย `storage_purge_queue`/Edge Function เดิมให้ drain ได้หลาย bucket หรือรับ bucket param (รองรับ audio bucket ลบอัตโนมัติใน 24 ชม.) — **ตัดสินใจรูปแบบขยาย (multi-bucket table vs bucket-param column) เป็นหน้าที่ /db-architect เอง** ตามที่ requirements ระบุไว้ชัดเจน — size M — dependency: R7.38 — ต้องขออนุมัติ deploy จากผู้ใช้ก่อนเสมอ (แยกอนุมัติจาก R7.8/R7.36 ของ push, แม้ใช้ pattern เดียวกัน)

### Dart (sub-feature A: บันทึกเสียงสั้น)
- [ ] **R7.40**: ปุ่มกดค้างบันทึกเสียง (hold-to-record) ≥56dp, ปล่อยนิ้ว/ครบ 10 วิ = หยุดอัตโนมัติ, คำอธิบายขอสิทธิ์ไมค์ภาษาไทยไม่ block ถ้าปฏิเสธ — size M — dependency: R7.38 (mock ระหว่างรอ schema จริง)
- [ ] **R7.41**: อัปโหลดไฟล์เสียงเข้า private bucket ผูกคู่จับคู่/ทริป, เล่นฟัง (playback only) ผ่าน signed URL แบบไฟล์แนบแชทเดิม, privacy note ก่อนใช้งานครั้งแรกว่าไม่มีการแปลงเป็นข้อความ/วิเคราะห์เนื้อหา — size M — dependency: R7.38, R7.40
- [ ] **R7.42**: กรณีไฟล์ถูกลบไปแล้ว (ครบ 24 ชม.) ก่อนอีกฝ่ายเปิดฟัง → แสดงข้อความ "เสียงหมดอายุแล้ว" ไม่ error ดิบ — size S — dependency: R7.39, R7.41

### Dart (sub-feature B: วลีสำเร็จรูปพูดด้วยเสียง — แยกจาก A โดยสิ้นเชิง)
- [ ] **R7.43**: รายการวลี allow-list ตายตัว ส่งผ่านช่องแชท/push เดิม (ใช้รูปแบบ quick-reply เดิม US-8/24/47) ไม่มีข้อความอิสระ — size S — dependency: quick-reply เดิม, push R7.5-7 (ไม่แตะ)
- [ ] **R7.44**: เมื่อฝ่ายรับได้ข้อความวลี ให้ on-device TTS อ่านออกเสียงอัตโนมัติ (อุปกรณ์ฝ่ายรับเท่านั้น ไม่มี server TTS/ไฟล์เสียง); ปิดได้ในหน้าตั้งค่า (fallback ข้อความ/แจ้งเตือนปกติ); **throttle 1 ครั้ง/10 วิ/คู่ (Q16)** ปุ่มถูกปิดชั่วคราวระหว่าง cooldown — size M — dependency: R7.43
- [ ] **R7.45**: เทสต์แยก (A) vs (B) อย่างชัดเจน — ยืนยันว่า flow (B) ไม่มีการอัปโหลด/สร้างไฟล์เสียงใด ๆ เกี่ยวข้องเลย (กันการปนกันทั้งโค้ดและการสื่อสาร QA) — size S — dependency: R7.41, R7.44

## Stage C — งานใหม่ที่เพิ่ม (US-49 + US-50) + อัปเดตอ้างอิง (US-47 เดิม)
งาน US-47 คือ R7.25-27 เดิม (ไม่แก้) เพิ่มงานใหม่ของ US-49/US-50 ดังนี้:

### US-49: Lateness Detection & No-Fault Cancellation

**DB (owner: /db-architect) — เริ่มจากข้อนี้ก่อนเสมอในคิว Stage C:**
- [ ] **R7.46 (P0-blocking)**: อ่าน schema/RPC จริงของ `match_outcomes` และระบบรีวิวทั้งหมด เพื่อปิด **Q13** ให้เสร็จก่อนส่งต่อ programmer — ตรวจว่า eligibility การรีวิวปัจจุบันต้อง "ขึ้นรถแล้ว" (boarded) อยู่แล้วหรือไม่ (ถ้าใช่ การยกเลิกก่อนขึ้นรถแบบ no-fault น่าจะไม่กระทบสถิติอยู่แล้ว แค่ต้องยืนยันด้วยเทสต์จริง ไม่ใช่เดา); ถ้าจำเป็นให้เพิ่มฟิลด์แยกชนิดชัดเจน เช่น `ended_reason = 'no_fault_lateness'`/`is_no_fault boolean` กันไม่ให้ปนกับการยกเลิกทั่วไป — size M — dependency: ไม่มี — **นี่คือ open item ที่ต้องให้คนจริง (ตัว /db-architect agent ที่ทำ Stage C) อ่านโค้ด/schema มายืนยัน ไม่ใช่ PM ตัดสินเอง เพราะต้องเห็นโครงสร้างจริงของ `match_outcomes`/`reviews` ก่อน**
- [ ] **R7.47**: schema/trigger รองรับ first-write-wins แบบ atomic สำหรับกรณีกดยกเลิก/รอต่อพร้อมกัน (Q12) — reuse pattern เดียวกับ `cancel_pending_match` เดิม — size S — dependency: R7.46

**Dart:**
- [ ] **R7.48**: wiring ตรวจจับ lateness ตามนิยาม Q11 (เกิน 10 นาที **หรือ** 3 ครั้งติดกัน ~5 นาทีที่ระยะตรงไม่ลดลง ≥100 ม.) ใช้ ETA/live-tracking poll cadence เดิม ไม่สร้าง poll ใหม่ — size M — dependency: R7.46
- [ ] **R7.49**: การ์ดสองตัวเลือกแสดงพร้อมกันทั้งสองฝั่ง ("รอต่ออีก 10 นาที" / "ยกเลิก (ไม่เสียประวัติ)"); กด "รอต่อ" แล้วเข้าเงื่อนไขซ้ำแสดงการ์ดใหม่ได้ไม่จำกัดรอบ แต่ไม่รบกวนถี่เกินระหว่างนับเวลา; การ์ดต้องหลบให้ UI สไลด์ถึงที่หมายเสมอเมื่อทริปใกล้จบแล้ว (กันแย่งพื้นที่จอ) — size M — dependency: R7.48
- [ ] **R7.50**: บังคับที่ backend เสมอ (ไม่ใช่แค่ UI) ว่า "ยกเลิก" ชนะ "รอต่อ" เมื่อกดพร้อมกัน (Q12 first-write-wins); ฝ่ายที่ไม่ได้กดยกเลิกได้รับแจ้งเตือนสุภาพผ่าน push channel เดิม (US-42) ไม่กล่าวโทษฝ่ายใด — size M — dependency: R7.47, R7.49, R7.6-8
- [ ] **R7.51**: regression — ยืนยันไม่กระทบ SOS/emergency flow เดิม (US-9 ฯลฯ), การ์ด lateness เป็นกลไกแยกไม่ลดระดับ SOS — size S — dependency: R7.49

### US-50: Transit-Hub Detour Slider

**DB (owner: /db-architect):**
- [ ] **R7.52**: คอลัมน์ใหม่ `trips.transit_hub_detour_m` (int, ช่วง 200-2000, default 500) **แยกจาก** `trips.max_dropoff_m` เดิม (คนละความหมาย ไม่แก้ของเดิม); เพดานสูงสุด 2000 เป็นค่า config ระบบ (ปรับได้ฝั่งระบบ ไม่ hardcode ในแอป) — size S — dependency: ไม่มี — เริ่มคิว DB Stage C ทันทีหลัง R7.46/47
- [ ] **R7.53**: ตาราง public reference ใหม่ `transit_hubs (id, name, lat, lng, type)` (BTS/MRT/ARL) — **seed data กำลังอยู่ระหว่างคุยตรงกับผู้ใช้แล้ว (ไม่ต้องถามซ้ำ)** — เมื่อได้ลิสต์พิกัดที่ผู้ใช้อนุมัติแล้ว ให้ /db-architect ใส่เป็น seed ใน migration นี้; โครงสร้างตารางออกแบบล่วงหน้าได้เลยโดยไม่ต้องรอ seed data จริง (พัฒนา schema ขนานไปก่อน ใส่ seed ทีหลังได้) — size S (schema) — dependency: ไม่มี
- [ ] **R7.54**: ขยาย `find_matches`/RPC ที่เกี่ยวข้อง เพิ่ม predicate: ใช้เฉพาะเมื่อปลายทางคนนั่งอยู่ในรัศมี **≤100 ม. (Q15)** จากแถวใน `transit_hubs`; คำนวณ delta = `route(origin→station→destination) − route(origin→destination)` ผ่าน OSRM จริง (ไม่ใช่ haversine); ถ้า delta > `trips.transit_hub_detour_m` ของคนขับ = ไม่จับคู่แนวนี้; **OSRM ล้มเหลว/timeout = fail-closed (ไม่จับคู่แนวนี้)** ต่างจาก US-43 ที่ fail-open เพราะที่นี่เป็นตัวเลขตัดสินใจจับคู่จริง ไม่ใช่แค่ช่วยขยับหมุด — size L — dependency: R7.52, R7.53
- [ ] **R7.55**: perf test เรียก OSRM 2 เส้นทางต่อการเช็คหนึ่งครั้ง (origin→station→destination, origin→destination) ต้องไม่ทำให้ `find_matches`/preview ช้าเกินกรอบเดิมอย่างมีนัยสำคัญ — size M — dependency: R7.54

**Dart:**
- [ ] **R7.56**: UI สไลเดอร์คนขับ 200-2,000 ม. ขยับทีละ 100 ม. ค่าเริ่มต้น 500 ม. ต่อทริป; ไม่มีสวิตช์ยินยอมเพิ่มเติม (ค่าที่ตั้งเองคือการยินยอมอยู่แล้ว เหมือน `max_dropoff_m`) — size M — dependency: R7.52
- [ ] **R7.57**: `PresetController` เพิ่มหมวดใหม่ "จุดต่อรถขนส่งสาธารณะ" ดึงจากตาราง public reference/bundled asset (**ห้ามใช้ device-local secure storage เดิมของ Home/Office** — แยกสถาปัตยกรรมจริง) — size M — dependency: R7.53
- [ ] **R7.58**: หน้าเลือกปลายทางของคนนั่งแสดงตัวเลือกสถานีจากรายการอ้างอิง (ภายในรัศมีที่เกี่ยวข้อง); เลือกแล้ว flag ปลายทางเป็น hub-match ให้ `find_matches` ใช้เงื่อนไข R7.54 — size M — dependency: R7.53, R7.57

## Migration queue ที่ /db-architect ต้องยึดลำดับ (ทั้งรอบ 7)
1. `0011a` — ALTER TYPE ADD VALUE ('driver_arrived') แยกไฟล์ก่อน 0011 เสมอ (14.8-1)
2. `0011` — `device_tokens` + `push_outbox` (R7.1, R7.2) — ตรวจ `chat_messages` CHECK จริงด้วย `\d` ก่อน apply (14.8-2)
3. `0012` — `profiles.gender` + `trips.same_org_only`/`trips.women_only` (ชื่อสุดท้ายยืนยันตอน implement, ผูกกับทริปตาม Q-G4) + `trips.vibe_tags`/`trips.mood_text` (R7.13, R7.17, R7.18) + อัปเดต `get_trip_card`/`export_my_data` ให้ครบ (14.8-5, 14.8-6, **ทำในไฟล์เดียวกันนี้ ไม่แยก 0013**) + women-only auto-cancel loop logic (14.8-7, R7.19)
4. `0013` — private audio bucket (R7.38) + ขยาย `storage_purge_queue` รองรับ multi-bucket (R7.39)
5. `0014` — US-49: ตรวจ/แก้ `match_outcomes`/reviews ตาม Q13 (R7.46) + atomic cancel-wins (R7.47)
6. `0015` — US-50: `trips.transit_hub_detour_m` (R7.52) + ตาราง `transit_hubs` schema (R7.53, seed รอผู้ใช้อนุมัติแยกจาก schema) + ขยาย `find_matches` OSRM delta predicate (R7.54)

แต่ละไฟล์ต้อง dry-run rolled-back + regression ชุดเดิมทั้งหมดก่อนเสมอ → รายงานผู้ใช้ → apply เฉพาะเมื่อผู้ใช้อนุมัติชัดเจน (ตามวินัยเดิมของโปรเจกต์ทุกรอบ)

## Stage D (เพิ่ม) — ทดสอบ/QA ของ US-48/49/50
- [ ] **R7.59 (P0)**: unit/widget test US-48 — isolation (A)/(B) (R7.45), audio expiry graceful message (R7.42), TTS throttle 10 วิ/คู่ (R7.44), mic-permission-denied ไม่กระทบ (B) — size L — dependency: R7.41, R7.44, R7.45
- [ ] **R7.60 (P0)**: SQL test แบบ rolled-back สำหรับ `match_outcomes`/reviews หลังปิด Q13 (R7.46) + regression ว่าการยกเลิกทั่วไปเดิมไม่กระทบ + race-condition test คนละฝั่งกดพร้อมกัน (R7.47/50) — **owner: /db-architect** — size L — dependency: R7.46, R7.47
- [ ] **R7.61 (P0)**: test US-50 — OSRM fail-closed จริง (mock ให้ timeout แล้วตรวจว่าไม่จับคู่), boundary รัศมี 100 ม. พอดี/เกิน 1 ม. (Q15), delta > ค่าที่คนขับตั้ง = ไม่จับคู่, perf 2x OSRM call ไม่เกินกรอบ (R7.55) — size L — dependency: R7.54, R7.55
- [ ] **R7.62 (P0)**: a11y/security เพิ่มสำหรับ Stage B/C ใหม่ — ปุ่มบันทึกเสียง ≥56dp เข้าถึงด้วย screen reader, การ์ด lateness สองตัวเลือกอ่านได้ด้วย screen reader + ปุ่มขนาดแตะง่าย, no-fault cancel บังคับที่ backend (กัน client ส่งค่าไม่ตรง), find_matches US-50 คำนวณที่ backend เท่านั้นไม่พึ่ง client — size M — dependency: R7.49, R7.54
- [ ] **R7.63 (P0)**: QA เว็บ 2 โปรไฟล์ Chrome รอบเพิ่ม ครอบคลุม US-48 (บันทึกเสียง+วลี TTS แยกกันชัดเจน), US-49 (การ์ดสองตัวเลือก, no-fault cancel ไม่กระทบรีวิว, race condition), US-50 (สไลเดอร์คนขับ, เลือกสถานีปลายทาง, จับคู่จริงเมื่อ delta อยู่ในเกณฑ์) — size M — dependency: R7.59, R7.60, R7.61, R7.62, R7.33, R7.34

## Open items ที่ยังต้องมีคนปิด (ไม่ใช่ PM)
1. **Q13 (US-49, สำคัญที่สุด)** — ต้องให้ **/db-architect agent ที่รับผิดชอบ Stage C** อ่าน schema/RPC จริงของ `match_outcomes` และ `reviews` ก่อนเริ่ม R7.46 เพื่อยืนยันว่า eligibility ปัจจุบันต้อง "ขึ้นรถแล้ว" หรือไม่ — **นี่ไม่ใช่การตัดสินใจเชิงนโยบายที่ PM ตัดสินได้ ต้องเห็นโครงสร้างจริงก่อน** ธงไว้เป็นงานแรกของคิว DB Stage C (R7.46)
2. **Q14 (US-50, seed data สถานี)** — orchestrator กำลังคุยตรงกับผู้ใช้เพื่อขอพิกัด/อนุมัติ seed list อยู่แล้ว (ไม่ต้องถามซ้ำในเอกสารนี้) — เมื่อได้ลิสต์ที่อนุมัติแล้วให้ /db-architect ใส่ใน migration `0015`; ระหว่างรอ สามารถออกแบบ/สร้าง schema ตาราง `transit_hubs` (R7.53) ล่วงหน้าได้โดยไม่ต้องรอ seed data จริง
3. (จากเดิม) การอนุมัติ deploy Edge Function 3 รายการที่แยกกัน — `purge-storage-queue` เดิม (ค้างรอบ 5), ส่วนขยาย push `push_outbox` drain (R7.8/R7.36), ส่วนขยาย multi-bucket ของ storage purge สำหรับ US-48 (R7.39) — **ทั้งสามต้องขออนุมัติแยกกันจากผู้ใช้ ไม่ผูกรวมเป็นการอนุมัติเดียว** แม้ใช้ pattern โค้ดคล้ายกัน

## สรุปจำนวนรวม (ฉบับเต็ม A/B/C)
- Stage A (P0, ไม่เปลี่ยนจากเดิม): R7.1-R7.12 = 12 งานพัฒนา
- Stage B (P1): R7.13-R7.24 (เดิม, 12 งาน: US-44 4 + US-45 5 + US-46 3) + R7.38-R7.45 (ใหม่, US-48 = 8 งาน) = **20 งาน**
- Stage C (P1/P2): R7.25-R7.27 (เดิม, US-47 = 3 งาน) + R7.46-R7.51 (ใหม่, US-49 = 6 งาน) + R7.52-R7.58 (ใหม่, US-50 = 7 งาน) = **16 งาน**
- Stage D ทดสอบ/QA/release (P0 ส่วนใหญ่): R7.28-R7.37 (เดิม, 10 งาน) + R7.59-R7.63 (ใหม่, 5 งาน) = **15 งาน**
- **รวมทั้งรอบ 7 ขยาย (US-42..US-50): 63 งาน** (P0 core ~34 งาน นับ Stage A + Stage D ส่วน P0 ทั้งหมด, ที่เหลือ P1/P2)
- จุดเสี่ยง timeline ที่สุด: **คิว migration 6 ไฟล์เรียงลำดับ (0011a→0015)** ที่ /db-architect ต้องทำทีละไฟล์แบบ dry-run-then-approve เสมอ — ถ้าผู้ใช้อนุมัติช้าแม้เพียงจุดเดียวในคิว จะดีเลย์ทุก Stage ถัดไปที่พึ่ง DB (โดยเฉพาะ US-45/US-48/US-49/US-50 ที่พึ่ง DB หนักกว่าที่อื่น); งาน Dart ที่ไม่พึ่ง DB เลย (US-43, US-46, US-47 บางส่วน, US-48(B) บางส่วน) ควรเร่งทำขนานให้เต็มที่เพื่อบัฟเฟอร์ความล่าช้าฝั่ง DB

## คำตัดสิน (Orchestrator) — US-50 ปรับทิศทางใหม่ (ยกเลิกรายชื่อสถานี, ทำแบบทั่วไป)
หลังคุยกับผู้ใช้เพิ่มเติม: **ยกเลิกแนวคิด "รายชื่อสถานีอ้างอิง (transit_hubs)" ทั้งหมด** เพราะ:
- ใช้ได้แค่กรุงเทพฯ ไม่ครอบคลุมต่างจังหวัด
- ซ้ำซ้อนกับ UI ค้นหา/ปักหมุดปลายทางที่มีอยู่แล้ว ไม่ต้องสร้างใหม่

**กฎ US-50 ฉบับสุดท้าย (แทนที่ทุกเวอร์ชันก่อนหน้า):**
- คนนั่งเลือกปลายทางตามปกติ (ค้นหาชื่อสถานที่ หรือปักหมุดบนแผนที่ — ใช้ flow เดิมที่มีอยู่แล้วในการสร้างทริป ไม่มี UI ใหม่สำหรับ "เลือกสถานี")
- กฎจับคู่ใหม่นี้เป็น **ทางเลือกที่สอง** นอกเหนือจากกฎ "ปลายทางใกล้กัน" (`max_dropoff_m`, รัศมีจากปลายทางคนขับ) ที่มีอยู่แล้ว — ทั้งสองกฎ "หรือกัน" (match ได้ถ้าผ่านกฎใดกฎหนึ่ง)
- วัดจาก **ระยะทางถนนจริงที่เพิ่มขึ้น** (ไป-กลับ) เทียบกับเส้นทางเดิมของคนขับ ผ่าน OSRM: `route(origin→rider_dest→destination) − route(origin→destination)`
- คนขับตั้งค่าเองต่อทริป: คอลัมน์ใหม่ (ไม่ใช่ `max_dropoff_m`) ช่วง 200–2,000 เมตร ขยับทีละ 100 ม. ค่าเริ่มต้น 500 ม. เพดาน config 2,000 ม.
- **ใช้ได้กับปลายทางของคนนั่งทุกที่ ไม่จำกัดเฉพาะสถานีขนส่ง ไม่จำกัดพื้นที่ทางภูมิศาสตร์** ใช้ได้ทุกที่ที่ OSRM มีถนน (ทั่วประเทศ)
- ไม่ต้องมีตาราง/seed data สถานีใดๆ ทั้งสิ้น — ยกเลิกงานหาพิกัดสถานีที่ทำค้างไว้ก่อนหน้า (ไม่เสียหาย ไม่ได้ใช้)
- ไม่ต้องมีสวิตช์ยินยอมเพิ่มเติม (ตัวเลขที่คนขับตั้งเองคือการยินยอมอยู่แล้ว)
