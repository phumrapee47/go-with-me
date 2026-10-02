# QA Result

## ผลตัดสิน: PASS with notes

## เหตุผล
- รอบนี้เป็น bug-fix round ขนาดเล็ก (BA/PM/UIUX/Architect ถูกข้ามโดย orchestrator อย่างถูกต้อง — ไม่มี architecture-spec.md, ไม่มี security checklist ที่ต้องปิดเพิ่ม)
- Bug 1 (CORS/User-Agent บน OSRM/Nominatim): PASS ครบ 5/5 ข้อ — แก้ถูกครบ 3 ไฟล์, native behavior ไม่เปลี่ยน, ไม่มี header อื่นที่เสี่ยง CORS หลงเหลือ, test 22/22 ผ่าน, ไม่มี regression
- Bug 2 (geolocation บน insecure origin): ตรรกะ `_isInsecureWebOrigin` ถูกต้อง 100% (ตรวจสอบ edge case ของ host normalization, port, `[::1]` แล้วไม่พบบั๊กจริง) — นี่คือ **ส่วนที่แก้ตรงกับ bug ที่ผู้ใช้รายงานจริง** (ผู้ใช้ทดสอบโดยกด Allow ไปแล้วก่อนหน้า คือเคสที่ permission granted/denied อยู่แล้ว ไม่ใช่ pristine first-request) — flow นี้ผ่าน `currentPosition()` ที่มี check ใหม่อยู่ครบ จึงแสดงข้อความ Thai เฉพาะเจาะจงตามที่ตั้งใจ
- ช่องว่างที่ tester พบ (first-tap-ever ก่อนเคยขอ permission เลย จะไปชน `deniedForever` ใน `request()` ก่อนถึง check ใหม่ จึงยังเห็นข้อความทั่วไปเดิม) เป็น **Medium, ไม่ block** — เหตุผล: (1) ไม่กระทบ scenario ที่ผู้ใช้รายงานจริง เพราะผู้ใช้ทดสอบจากเคสกด Allow ไปแล้ว ไม่ใช่เคส first-tap-ever (2) เป็น edge case เพิ่มเติมที่ tester ยกระดับความสำคัญขึ้นมาเอง ไม่ใช่ AC เดิมของบั๊กที่ขอให้แก้ (3) ไม่มี regression, ไม่กระทบ flow อื่น — ผู้ใช้ไม่ต้องรอรอบแก้นี้ก่อนไปทดสอบต่อ
- เอกสาร mismatch (14/14 vs 13/13 ของ `contract_and_safety_test.dart`) และ dead code `'[::1]'` เป็นเรื่อง non-functional ล้วน ไม่กระทบผู้ใช้ปลายทาง
- flutter analyze สะอาด (16 issues ทั้งหมดเป็น pre-existing info-level ไม่เกี่ยวกับไฟล์ที่แก้)
- ไม่มีข้อ P0 ใดที่ FAIL และไม่มี Security Checklist ที่ค้างปิด → เกณฑ์ FAIL ไม่ถูกเข้าเงื่อนไข

## สถานะสำหรับผู้ใช้
**ไปทดสอบซ้ำบนมือถือผ่าน Safari ผ่าน LAN hotspot ได้เลยตอนนี้** ทั้ง routing (OSRM/Nominatim) และ geolocation ควรทำงานได้ตามที่คาดหวังสำหรับ scenario ที่รายงานไว้เดิม (กด Allow ไปแล้ว → เห็นข้อความ error ที่อธิบายปัญหา HTTPS/localhost ชัดเจนแทนข้อความทั่วไป)

ข้อควรรู้: ถ้าทดสอบบนเบราว์เซอร์/โปรไฟล์ใหม่ที่ไม่เคยขอ location permission มาก่อนเลย (first-tap-ever) อาจยังเห็นข้อความ error แบบเดิม (ทั่วไป) แทนข้อความเฉพาะเจาะจง — แก้ไขไม่ยาก แต่ยังไม่ปิดในรอบนี้ จะติดตามเป็นรายการตามมา

## หมายเหตุสำหรับผู้ใช้ (กรณี PASS with notes)
1. [P1 - follow-up ไม่ block] First-tap-ever บน insecure web origin ยังเห็นข้อความ generic (`T.locOpenSettings`) แทนข้อความเฉพาะเจาะจง HTTPS — อ้างอิง: test-report.md บรรทัด 32-34 — Root cause: **โค้ด** (gap ที่ programmer เองก็ confirm ว่าเป็น incomplete path จริง ไม่ใช่ AC คลุมเครือ — มี fix ที่ชัดเจนเสนอไว้แล้วคือ short-circuit ใน `request()`/`current_location.dart` เหมือนที่ `currentPosition()` ทำ) — แนะนำส่งกลับ programmer ในรอบถัดไป (ไม่เร่งด่วน เพราะไม่กระทบ scenario ที่รายงานจริง)
2. [P2 - เอกสารเท่านั้น] dev-notes.md ระบุ "14/14" สำหรับ `contract_and_safety_test.dart` แต่จริง 13/13 — ไม่ใช่บั๊ก functional, แก้แค่ตัวเลขในเอกสาร — ไม่ต้องส่งกลับ programmer เร่งด่วน
3. [P2 - เอกสาร/cleanup] `'[::1]'` ใน `localHosts` set (`geolocator_location_service.dart:49`) เป็น dead code เพราะ Dart normalize เป็น `::1` อยู่แล้ว — ไม่กระทบ behavior ปล่อยไว้ cleanup ทีหลังได้

## รอบนี้คือรอบที่: 1
