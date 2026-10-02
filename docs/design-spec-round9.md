# Design Spec รอบ 9: Modern Lifestyle & Human-First UI/UX Overhaul (ส่วนต่อของ docs/design-spec.md .. round8)

ขอบเขต: US-1..US-7 ตาม `docs/requirements-round9.md` + `docs/tasks-round9.md` (T1-T10) — UI/UX-only, ไม่แตะ backend/schema ยกเว้นจุดที่ระบุไว้แล้ว (การซ่อน organization badge ที่ชั้น UI)
**ไฟล์นี้เป็นเอกสารเพิ่มเติมใหม่ทั้งหมด (round9) — ไม่แก้ไข docs/design-spec.md หรือ docs/design-spec-round7.md ใดๆ ออร์เคสเตรเตอร์จะนำไปรวมแยกต่างหาก**
ระเบียบวิธี: ใช้ semantic tone-token เดิมเสมอ (`context.tone.*` จาก `lib/core/theme/tone.dart`) ไม่อ้าง hex ตรง ๆ ยกเว้นจุดที่ตั้งใจให้ hardcode ดำ/ขาวบนรูปภาพ (gradient บนการ์ด US-1) ซึ่ง requirement อนุญาตไว้ชัดเจนแล้ว (บรรทัด 32 ของ requirements-round9.md)
ไม่มีโค้ด ไม่เลือก package ใหม่ ไม่ตัดสิน business logic ที่ requirement ไม่ได้ระบุ — จุดที่ขัดแย้ง/เดาไม่ได้ถูกยกไปหัวข้อท้ายเอกสารให้ PM ตัดสิน

## 0. หลักการเพิ่มเติมรอบ 9
- ทุก component ใหม่ที่ "ต่อยอด" flow เดิม (CommuteCardDeck, TripCard, ChatsTab list, MeTab) ต้องเรียก action/provider เดิมทั้งหมด ห้ามเปลี่ยน business logic, ห้ามเปลี่ยน routing target เดิม ยกเว้นจุดที่ระบุไว้ชัดเจนว่าเป็นการเปลี่ยนกลไก navigation (ดูหัวข้อ "ข้อเสนอแนะ" ท้ายเอกสาร)
- Token เก่า `AppColors.border` (hex ตายตัว `#FFD8E2EC`, ไม่รู้จัก dark mode) กับ `context.tone.border` (theme-aware, ต่อยอดจาก round 7) เป็นคนละตัวกัน — งานรอบนี้ (US-7) คือถอด `AppColors.border` ออกจากทุกจุดที่ใช้เป็นเส้นขอบตกแต่ง ส่วน `context.tone.border`/`context.tone.borderStrong` ยังใช้ได้ตามปกติสำหรับ hairline divider/semantic border เพราะรองรับ 4 ธีมอยู่แล้ว
- ทุกหน้าที่ overhaul ต้องผ่าน 48dp min tap target (`AppSpacing.minTap`), contrast >= 4.5:1 (ข้อความ) / >= 3:1 (ไอคอน/ขอบ UI ขนาดใหญ่), และ dynamic type (ข้อความห้ามตัด/ห้าม overflow ที่ text scale 2.0 — ใช้ `Flexible`/`Wrap` เหมือนโค้ดเดิมที่ทำอยู่แล้วในหลายจุด)
- Squircle (`AppShape.card()`/`.control()`/`.sheet()`, `AppRadius`) และ `ToneColors.cardShadow`/`cardShadowPressed` เป็น infra ที่มีอยู่แล้ว — component ใหม่ในเอกสารนี้อ้างอิงชื่อเหล่านี้ตรง ๆ ไม่ประดิษฐ์ shadow/radius ใหม่

---

## G9.1 US-1: Tinder-Style Commute Card Deck

### G9.1.1 User Flow: ปัดการ์ดคนร่วมทาง (ต่อยอด F-7 เดิม, ไม่เปลี่ยน state machine ของ `deckProvider`/`DeckSwipeCard`)
1. ผู้ใช้เปิดหน้า deck (`CommuteCardDeck`) เห็นการ์ดใบแรกเต็มพื้นที่ 80-85% ของความสูงที่มี มุมโค้ง squircle 24dp
2. ด้านบนการ์ดเห็น story indicator bar (1-3 ขีด ตามจำนวนภาพที่การ์ดนั้นมีจริง) ขีดแรกไฮไลต์เต็มความกว้าง
3. ผู้ใช้แตะครึ่งขวาของการ์ด (ไม่ใช่ลาก) → ขีดที่ 2 ไฮไลต์ ภาพเปลี่ยนเป็นภาพที่ 2 (รถ/vector รถ, เฉพาะ candidate ที่เป็น driver) ด้วย cross-fade สั้น ไม่มี delay; แตะครึ่งซ้าย → ย้อนกลับขีดก่อนหน้า; แตะซ้ายสุดตอนอยู่ขีดแรก = no-op (ไม่ข้ามไปการ์ดก่อนหน้า, ไม่ชนกับ skip gesture)
4. ผู้ใช้ลาก (pan) ซ้าย/ขวาบนการ์ด (จุดไหนของการ์ดก็ได้ รวมพื้นที่ story-tap) → ยังคงเป็น gesture skip/invite เดิมของ `DeckSwipeCard` เสมอ (drag ชนะ tap เมื่อระยะขยับเกิน touch-slop มาตรฐานของ `GestureDetector`/`PanGesture` เดิม — ไม่ต้องเขียน gesture arena ใหม่ เพราะ `GestureDetector` ของ Flutter แยก tap/pan ให้อยู่แล้วตาม pan threshold มาตรฐาน)
5. ผู้ใช้เห็นข้อมูล 4 บล็อกซ้อนบน gradient ดำโปร่งแสงด้านล่างภาพ: (1) ชื่อ+อายุ(ถ้ามี — ดูข้อเสนอแนะท้ายเอกสารเรื่องไม่มีฟิลด์อายุ)+ป้าย "✓ ยืนยันตัวตนแล้ว"+คะแนนรีวิว (เงื่อนไข `hasRating`) (2) ข้อมูลรถ (เฉพาะ `role == driver`) (3) ต้นทาง➜ปลายทาง+เวลา+overlapPct (4) vibe chip แถว (ซ่อนถ้า `vibeTags` ว่าง)
6. ผู้ใช้แตะปุ่มวงกลม ✕ (ซ้าย) → เรียก `onSkip` เดิม (= `_skip`) หรือปัดซ้าย → `fling(right:false)`; แตะปุ่มวงกลม 💚 (ขวา, ใหญ่กว่าปุ่มอื่นชัดเจน) → เรียก `onInvite`/`_invite` เดิม หรือปัดขวา → `fling(right:true)`; แตะปุ่ม ℹ️ (กลาง, เล็กกว่า 2 ปุ่มข้าง) → เปิดรายละเอียด (ดูข้อเสนอแนะท้ายเอกสารเรื่อง bottom sheet vs full page)
7. Flow เดิมทั้งหมดที่ตามมา (undo banner, cap-active banner, coach hint, empty/end-of-deck state) ไม่เปลี่ยนแปลง — ครอบด้วย visual ใหม่เท่านั้น

### G9.1.2 Components

#### RC-1 CommutePhotoDeck (ภาพ/vector 3 ช่องพร้อม story bar — แทนที่ส่วนบนของ `CommuteCard` เดิม)
- Purpose: แสดงภาพเต็มพื้นที่การ์ด 80-85% พร้อม story indicator แบบ Instagram และ tap-to-advance
- Content: `PageView`/`IndexedStack`-เทียบเท่าของ "สไลด์" 1-3 ช่อง ตามจำนวนภาพจริงของ candidate นั้น; แต่ละช่องคือ 1 ใน 3 ชนิด: AvatarPhotoSlide (vector avatar ตัวอักษรชื่อ, เต็มพื้นที่, พื้นหลังไล่สีพาสเทลตามตัวอักษรแรกของชื่อ) / VehiclePhotoSlide (vector รถ 3D มินิมอล, เฉพาะ `role == driver`) / RouteSnapshotSlide (embedded `AppMap` แบบ `interactive: false`, `showZoomButtons: false`, `onTap: null`, fit-bounds ครอบ `approxOrigin`→`approxDest` พร้อม 2 `MapPin`)
- จำนวนขีดบน story bar = จำนวนสไลด์จริง: peer/rider candidate (ไม่มีรูปรถ) = 2 ขีด (avatar + route); driver candidate ที่มี `approxDest` = 3 ขีด; driver candidate ที่ `approxDest == null` (rider ค้นหา ไม่รู้ปลายทางตัวเอง) = 2 ขีด (avatar + vehicle เท่านั้น ไม่มี route snapshot เพราะไม่มี dest ให้ fit bounds — ดูข้อเสนอแนะท้ายเอกสาร)
- States: default (ขีดแรกแสดง) / advancing (cross-fade < 200ms ระหว่างสไลด์, reduce-motion: slide ทันทีไม่มี fade) / single-slide (มีแค่ 1 ภาพจริง — ไม่แสดง story bar เลย ตาม AC "จำนวนขีด = จำนวนภาพจริง" ถ้าเหลือ 1 ภาพไม่มีอะไรให้ "ขีด" บอก)
- A11y: ปุ่ม tap-zone ซ้าย/ขวาต้อง >= 48dp กว้าง (ครึ่งการ์ดเกิน 48dp อยู่แล้วในทางปฏิบัติ); ประกาศ semantics "ภาพที่ N จาก M: [โปรไฟล์/รถ/เส้นทาง]" เมื่อเปลี่ยนสไลด์ (polite); RouteSnapshotSlide มี `ExcludeSemantics` ด้านในของตัวแผนที่เอง (ไม่ประกาศ tile/marker labels ของ OSM ซ้ำ) แต่มี semantics label รวมระดับสไลด์ว่า "แผนที่ย่อแสดงเส้นทางจาก [ต้นทาง] ไป [ปลายทาง]" อ่านจาก approxOrigin/approxDest ที่เบลอไว้อยู่แล้ว (ไม่ใช่พิกัดดิบ)

#### RC-2 CommuteInfoOverlay (บล็อกข้อมูล 4 ส่วนบน gradient)
- Purpose: อ่านข้อมูลสำคัญได้ในไม่กี่วินาทีบนพื้นรูปภาพทุกโทน
- Content:
  - Gradient: `LinearGradient` ดำ (Colors.black) opacity ไล่ 0% (กลางการ์ด) → ~35% (ขอบล่างสุด) สูงประมาณ 45-55% ของการ์ด (มากพอให้บล็อกข้อความอ่านง่ายเสมอ ไม่ว่าพื้นหลังสไลด์จะสว่างหรือมืด) — เป็นข้อยกเว้น hardcode สีดำ/ขาวที่ requirement อนุญาต (อยู่บนรูปเสมอ ไม่ใช่พื้นหลังหน้าจอ)
  - บล็อก 1: `Row` — ชื่อเล่นตัวหนาสีขาว ขนาด titleLarge + (ถ้ามีอายุ) " • NN" + ป้าย GlobalVerifiedBadge (ดู RC-4) + (ถ้า `hasRating`) "★ x.x (n ทริป)" สีขาว/ขาวนวล — ทั้งแถว wrap ได้ที่ text scale สูง ไม่ fix ความสูงบรรทัดเดียว
  - บล็อก 2: เฉพาะ `role == driver` — ไอคอนรถ + ข้อความสั้นแบบเดิม (`CommuteCard.roleText`) สีขาว
  - บล็อก 3: ไอคอน `alt_route` + overlap/ต้นทาง-ปลายทางแบบเบลอเดิม + ไอคอน `schedule` + เวลาออกเดินทาง (`formatDeparture`) — คงข้อความ/ตรรกะเบลอเดิมทั้งหมด (`overlapText`, `R6C.overlapLine`) เพียงเปลี่ยนสีเป็นขาวและวางซ้อนภาพแทนพื้นการ์ดขาว
  - บล็อก 4: เฉพาะ `vibeTags.isNotEmpty` — แถว chip โปร่งแสง (frosted-glass: พื้นขาว opacity ~15-20% + `BackdropFilter` เบลอเบา ถ้า reduce-transparency ให้ fallback เป็นพื้นขาว opacity ทึบขึ้น ~35% แทนไม่มี blur) ข้อความสีขาว ไม่มีเส้นขอบแข็ง
- States: with-role-block / without-role-block (peer หรือ rider candidate) / with-rating / without-rating / with-vibe / without-vibe (ไม่เว้นช่องว่าง) — รวม 2^3 การผสมที่เป็นไปได้ตาม AC เดิม
- A11y: ทุกข้อความบนภาพต้องผ่าน contrast >= 4.5:1 ต่อ gradient ที่จุดนั้น — gradient ต้องเข้มพอบริเวณที่มีข้อความเสมอ (แนะนำ: ความสูง gradient ขยายอัตโนมัติตามจำนวนบล็อกที่แสดงจริง ไม่ fix ความสูงตายตัว เพื่อไม่ให้บล็อกที่ 4 ตอนมี vibe tags หลุดพ้นเขต gradient เข้มพอ)

#### RC-3 CommuteActionCluster (ปุ่มลอย 3 ปุ่ม — แทนที่ `_ActionBar` เดิม)
- Purpose: ปุ่ม skip / invite / detail แบบวงกลมลอย เรียก action เดิมทั้งหมด (`onSkip`/`onInvite`/detail navigation)
- Content: 3 ปุ่มวงกลมเรียงแถวแนวนอน กึ่งกลาง — ✕ skip (64dp, ขอบ `tone.borderStrong`, ไอคอน `tone.text`), 💚 invite (80dp, เด่นกว่าใบอื่นอย่างชัดเจนตาม AC — ใหญ่กว่า/พื้นทึบสี `tone.successFill` หรือ `tone.primary` ตามที่ theme ปัจจุบันใช้เป็นสี positive-action, ไอคอน/เงาเด่นกว่า), ℹ️ detail (56dp, พื้น `tone.surface` + เงา `cardShadow`, ไอคอน `tone.textSecondary`) — ทั้ง 3 ปุ่ม >= 48dp (ผ่าน min tap target อยู่แล้วตามขนาดที่กำหนด)
- States: default / invite-disabled (`capActive == true` → ปุ่ม 💚 disabled พร้อม opacity ลดลง, ไม่ใช่ซ่อน — คง affordance เดิมตาม `_ActionBar` ปัจจุบันที่ทำ `onInvite: null`) / skip-pressed / invite-pressed (มี scale/ripple feedback สั้น)
- A11y: label เดิม (R6C.skip, R6C.detailLink, ป้าย invite) คงไว้ทั้งหมด — เปลี่ยนแค่รูปลักษณ์จากปุ่มสี่เหลี่ยม/ข้อความ เป็นวงกลม ไม่เปลี่ยน semantics label

#### RC-4 GlobalVerifiedBadge (shared component — ใช้ร่วมกับ T2/US-6, ใช้ซ้ำใน US-1 และ US-5)
- Purpose: แสดงป้ายเดียว "✓ ยืนยันตัวตนแล้ว" สีฟ้าอ่อน กรอง `organization` badge ทิ้งเสมอ (สมมติฐาน B/C)
- Logic (ไม่ใช่ business logic ใหม่ เป็น presentation filter ล้วนตามที่ T2 ระบุ): input = `List<VerificationBadge>` เดิมจาก `parseBadges()`; ถ้ามี `kind == email` และ/หรือ `kind == phone` อย่างน้อย 1 อัน → แสดง badge เดียว; ถ้าไม่มีทั้งคู่ (ไม่ว่าจะมี `organization` หรือไม่) → คืนค่า widget ว่าง (ไม่แสดงอะไรเลย ไม่ใช่ "ยังไม่ยืนยัน" แบบเดิมของ `BadgeWrap`/`MeTab` — ดูข้อเสนอแนะท้ายเอกสารเรื่องพฤติกรรม "ไม่มี badge เลย" ที่เปลี่ยนไปจากเดิม)
- Content: ไอคอนถูก (✓) ขนาดเล็ก + ข้อความ "ยืนยันตัวตนแล้ว" พื้นหลัง `tone.infoBg`/`tone.selectedFill` (ฟ้าอ่อนตามธีม; บนพื้นรูปภาพ US-1 ใช้เวอร์ชัน frosted บนกระจกขาวโปร่งแสงแทนเพื่อไม่ให้ฟ้าเข้มปนกับภาพพื้นหลังหลากสี), ตัวอักษร `tone.onSelectedFill`/สีขาวเมื่ออยู่บนภาพ
- States: shown (มี email/phone) / hidden (ไม่มีทั้งคู่) — ไม่มี "loading"/"error" เพราะ derive จากข้อมูล badge ที่โหลดมาแล้วเสมอ (ไม่เรียก network เพิ่ม)
- A11y: label เต็ม "ยืนยันตัวตนแล้ว ด้วยอีเมลหรือเบอร์โทร" (ไม่ต้องระบุว่าอันไหนเป๊ะ ๆ ก็ได้ตาม AC — ป้ายเดียวรวม)

### G9.1.3 States รวมของการ์ด (US-1)
- loading-photo (ระหว่าง `AppMap` embed กำลัง initial render ของ RouteSnapshotSlide — แสดง skeleton สีเทาพาสเทลของ tone ปัจจุบันแทนแผนที่ว่าง) / ready / peer-mode (ซ่อนบล็อก 2 + สไลด์รถ) / rider-candidate (ซ่อนสไลด์รถ, มีสไลด์ route ถ้ามี approxDest) / driver-candidate-no-dest (ซ่อนสไลด์ route ด้วยตามที่ระบุใน RC-1)

---

## G9.2 US-2: หน้าแรก (Home Screen & Map Zoom)

### G9.2.1 User Flow: เปิดหน้าแรก
1. ผู้ใช้เปิดแอป/สลับมาแท็บ Home → เห็นแผนที่เต็มจอเป็นพื้นหลังทันที (แทนที่โครง `Column` แบ่ง flex 4/5 เดิมที่มีแผนที่เป็นกล่องด้านบน) พร้อม header ลอย + การ์ดค้นหาลอยด้านล่าง วางซ้อนด้วย `Stack` เดียวกับที่ `RainNotification`/`HomeTab` ปัจจุบันใช้อยู่แล้ว (ขยายรูปแบบเดิม ไม่ใช่ pattern ใหม่)
2. ถ้า location permission ได้รับอนุญาตแล้วและอ่านตำแหน่งสำเร็จ: กล้องแผนที่ animate (ไม่กระโดด) ไปยังตำแหน่ง GPS จริงที่ zoom 15.0-15.5 ภายในเวลาสั้น ๆ หลังเปิดหน้า
3. จุดสีฟ้าที่ตำแหน่งผู้ใช้มี pulse animation ต่อเนื่อง (เพิ่มจาก marker เดิมที่มีอยู่แล้วสำหรับตำแหน่งทริป/candidate — เป็น marker ใหม่เฉพาะ "ตำแหน่งของฉัน" ไม่ใช่ pin ทริป)
4. ถ้า permission ถูกปฏิเสธ/อ่านตำแหน่งไม่ได้/timeout (BUG-2 เดิม): แผนที่ใช้ fallback center เดิม (`defaultMapCenter`, กรุงเทพฯ) ที่ zoom fallback ที่กำหนดไว้ชัดเจน (เสนอ **zoom 12** — ระดับเมือง อ่านสถานที่สำคัญได้ แต่ไม่ใช่ zoom เข้าใกล้ระดับ 15 ซึ่งจะผิดความจริงถ้า center เป็นจุดกลางกรุงเทพฯ ไม่ใช่ตำแหน่งจริงของผู้ใช้ — ดูข้อเสนอแนะท้ายเอกสารสำหรับตัวเลขนี้) error handling เดิมของ BUG-2 (เช่น timeout message/retry) ต้องยังทำงานเหมือนเดิมทุกจุด ไม่ถูกแทนที่
5. ผู้ใช้กดปุ่มลอยวงกลม 🧭 (มุมขวาล่างเหนือการ์ดค้นหา) → กล้อง animate กลับไปตำแหน่งผู้ใช้ปัจจุบันที่ zoom 15.0-15.5 (เรียก `onMyLocation` callback แบบเดียวกับที่ `AppMap` มีอยู่แล้ว `_MapButton(icon: Icons.my_location...)` — ต่อยอด ไม่ใช่สร้างกลไกใหม่)
6. ผู้ใช้เห็น header ลอยมุมซ้ายบน "สวัสดี, [ชื่อเล่น]" (ข้อความเปล่าไม่มีกล่อง มีแค่ text-shadow/gradient บางเพื่ออ่านง่ายบนแผนที่ทุกสี — เทียบเท่า RC-2 gradient แต่บางกว่าเพราะพื้นหลังเป็นแผนที่ไม่ใช่ภาพเต็ม) และมุมขวาบนสวิตช์แคปซูล [🚗 คนขับ | 🎒 คนนั่ง] ที่ยังคงเป็น UI แสดง/สลับ role เดิม (เทียบเท่า `RoleModeBadge`+switch ของ `RoleStrip` เดิม แต่ในรูปแบบแคปซูลลอยแทนแถบใต้ AppBar)
7. ผู้ใช้เลื่อนสายตาลงมาที่การ์ดค้นหาด้านล่าง (ขาวนวลลอย เงาจาง ไม่มีกล่องซ้อนกล่อง): ช่องค้นหา placeholder "วันนี้กลับไหนดี?" + ชิป [🏠 บ้าน][🏢 ที่ทำงาน] + ปุ่มแคปซูล "หาเพื่อนร่วมทาง" — ทั้งหมดเรียก action เดิมของ `QuickHomeCard`/wizard flow (ดูข้อเสนอแนะท้ายเอกสารเรื่องการ compress ฟีเจอร์ `QuickHomeCard` เดิม)

### G9.2.2 Components

#### RC-5 FullBleedHomeMap
- Purpose: แผนที่เต็มจอเป็นพื้นหลังของทั้งหน้า Home (แทน `Expanded(flex:4, child: AppMap(...))`)
- Content: `AppMap` เดิม (`center`, `zoom`, `route`, `areas`, `pins`) ขยายให้เต็มความสูงจอ (`Positioned.fill` ใต้ header/การ์ดที่ลอยทับ) + `markers` ใหม่ 1 ตัว: `UserPulseMarker` (จุดฟ้า + วงแหวน pulse) ที่ตำแหน่ง GPS ปัจจุบันเมื่อมี
- States: locating (กำลังขอ/รอตำแหน่ง — แผนที่ยังอยู่ที่ fallback center/zoom จนกว่าจะได้ตำแหน่งจริง, ไม่ค้างจอขาว) / located (camera animate ไปตำแหน่งจริง zoom 15-15.5) / permission-denied / timeout-error (BUG-2 flow เดิม — มี retry ตามที่มีอยู่แล้ว) / recentering (ระหว่าง animate หลังกดปุ่ม 🧭)
- A11y: ปุ่ม 🧭 recenter >= 48dp มี tooltip/semantics label "ไปที่ตำแหน่งของฉัน" (ใช้ข้อความเดิมของ `_MapButton` ที่มีอยู่แล้วใน `app_map.dart:234`)

#### RC-6 FloatingHomeHeader
- Purpose: แทน `AppBar` เดิมของ Home ด้วย header ลอยโปร่งใส
- Content: ซ้าย = "สวัสดี, [ชื่อเล่น]" (ตัดคำเดิม "สวัสดี คุณ$name" ให้สั้นลงตาม AC ใหม่ หรือคงคำเดิมถ้า PM ต้องการ — ข้อความเป็น product copy ไม่ใช่ UX แล้วแต่ทีม copy) ขวา = RoleSwitchCapsule (ป้าย role ปัจจุบัน + แตะเพื่อสลับ, ใช้ provider/action เดียวกับ `performRoleSwitch`/`RoleStrip` เดิม) — ทั้งสองฝั่งมี soft text-shadow หรือ scrim gradient บางที่ด้านหลัง (ไม่ใช่กล่องพื้นทึบ) เพื่ออ่านง่ายบน tile ทุกสี (light/dark)
- Safety icon เดิม (`Icons.shield_outlined` ไปหน้า Safety) ต้องยังเข้าถึงได้ — เสนอวางเป็นปุ่มวงกลมลอยเล็กถัดจากสวิตช์ role หรือรวมเป็นเมนู overflow เล็ก (ดูข้อเสนอแนะท้ายเอกสาร เพราะ AC ของ US-2 ไม่ได้พูดถึงปุ่มนี้เลย แต่มันมีอยู่แล้วและต้อง regression-safe)
- States: default / role-switching (spinner เล็กแทนไอคอน สอดคล้องกับ `_SwitchButton` เดิม) / switch-failed (snackbar เดิม, ไม่ต้องมี state visual พิเศษเพิ่มบน header เอง)
- A11y: ทั้งสองฝั่งต้องผ่าน contrast >= 4.5:1 กับพื้นแผนที่ทุกสี — แนะนำ scrim gradient ดำโปร่งแสงบางที่ด้านบนสุดของจอ (คล้าย RC-2 แต่เบากว่ามาก) เป็นเทคนิคเดียวที่รับประกัน contrast ได้ในทุกกรณี (สี tile ของแผนที่เปลี่ยนได้ตามตำแหน่ง/ธีม data-driven ไม่ fix)

#### RC-7 FloatingSearchCard (แทน `QuickHomeCard` เมื่อยังไม่มี trip)
- Purpose: การ์ดขาวนวลลอยด้านล่าง ไม่มีกล่องซ้อนกล่อง
- Content: ช่องค้นหา placeholder "วันนี้กลับไหนดี?" (แตะแล้วพาไป flow ค้นหา/สร้างทริปเดิม — ตรงกับปุ่ม "หาเพื่อนร่วมทาง" หรือ wizard), ชิปทางลัด [🏠 บ้าน][🏢 ที่ทำงาน] (เดิมอยู่ใน `QuickHomeCard`/presets — คงการเรียก preset เดิม), ปุ่มแคปซูลหลัก "หาเพื่อนร่วมทาง" (full-width, `AppRadius.pill`)
- **หมายเหตุสำคัญ**: `QuickHomeCard` เดิมมี state ซับซ้อนมาก (time chip, role segmented, dropoff adjuster, register hint, error/failure text, active-trip link) ที่ AC ของ US-2 ไม่ได้พูดถึงเลย (AC พูดถึงแค่ช่องค้นหา+2 ชิป+ปุ่ม). งานนี้จึงมีทางเลือกสถาปัตยกรรม 2 แบบที่ implementation ต้องเลือก — ยกเป็นประเด็นให้ PM ดูท้ายเอกสาร (ไม่ตัดสินเองในนี้)
- States: missing (ไม่มี preset บ้าน/ที่ทำงาน — ใช้ copy/flow เดิมของ `_missing`) / partial / ready (มี preset ครบ) / creating / error — สืบทอด state เดิมของ `quickHomeProvider` ทั้งหมด เปลี่ยนแค่เปลือก visual

### G9.2.3 States เพิ่ม (US-2 รวม)
- with-active-trip: เมื่อมี trip active อยู่แล้ว การ์ดด้านล่างควรแสดงสรุปทริปปัจจุบัน (เนื้อหาเดิมของ `_withTrip`) แต่ยังอยู่ในเปลือกการ์ดลอยแบบใหม่ (ไม่ใช่ `AppCard` กล่องเทอะทะเดิม) — AC ของ US-2 ไม่ได้พูดถึง state นี้ตรง ๆ แต่ regression rule บังคับให้ยังทำงานได้ครบ จึงต้องออกแบบเปลือกเดียวกันให้ครอบคลุม state นี้ด้วย

---

## G9.3 US-3: หน้ารายการแชท (Chat Tab)

### G9.3.1 User Flow
1. ผู้ใช้เปิดแท็บแชท เห็นรายการ borderless (ไม่มีกล่องขาวตีกรอบเทาต่อแถวเหมือน `Card` เดิม) คั่นด้วย hairline divider บาง (`tone.border`, 1px, เฉพาะระหว่างแถว ไม่ใช่รอบแถว) หรือ spacing ล้วนถ้าทีมเลือกไม่มีเส้นเลย (ดูข้อเสนอแนะ)
2. แต่ละแถว: อวาตาร์วงกลม 56dp ซ้ายสุด (เพิ่มจาก 40dp เดิม) — ถ้าคู่สนทนาฝั่งนั้นเป็น driver (`m.mode`/role ที่มีอยู่ในข้อมูล match) มีไอคอนรถเล็กซ้อนมุมขวาล่างอวาตาร์ (เหมือน "online dot" badge pattern)
3. ชื่อคู่สนทนาตัวหนาคมชัด, เวลาข้อความล่าสุด (จาก `ChatMessage.createdAt` — field มีอยู่แล้ว) สีเทาอ่อนชิดขวาสุดของแถว (แถวบนสุดของฝั่งขวา คนละบรรทัดกับ unread badge), ข้อความล่าสุด 1 บรรทัด ellipsis สีเทานุ่มกว่าชื่อ (ใช้ logic `last?.displayText` เดิม)
4. แชทที่ `unread.contains(m.id)` แสดง badge แดงมินิมอล (คงตำแหน่ง/สไตล์จุดแดงเดิม หรือใส่ตัวเลขถ้ามี unread-count จริงในระบบ — ปัจจุบัน `unreadMatchIdsProvider` เป็น `Set<String>` ไม่มี "จำนวนข้อความ" เก็บไว้ จึงแสดงได้แค่ "จุดแดง" ไม่ใช่ตัวเลข ตาม data ที่มีจริง ไม่ใช่ badge ตัวเลขปลอม)
5. ผู้ใช้แตะแถว → เข้าหน้าสนทนาเหมือนเดิม (`context.push(Routes.chat(m.id))`) — ไม่มี swipe action ใดอยู่ในโค้ดปัจจุบัน (ตรวจสอบแล้วไม่พบ `Dismissible`/swipe ใน `chats_tab.dart`) จึงไม่มีอะไรต้อง regression-test ในหัวข้อนี้ (ดูข้อเสนอแนะ — AC ระบุ "ถ้ามี" ซึ่งไม่มีจริง)

### G9.3.2 Components

#### RC-8 BorderlessChatRow
- Purpose: แถวแชทแบบ iOS Messages/LINE ไม่มีกล่องแยก
- Content: `ListTile`-เทียบเท่าแบบกำหนดเอง ไม่ห่อด้วย `Card`: leading = `ChatAvatarWithRoleBadge` (อวาตาร์ 56dp + ไอคอนรถมุมขวาล่างถ้า driver), title = ชื่อ (fontWeight.w700), trailing top = เวลา (เทาอ่อน, ใช้ helper format เวลาแบบสั้น เช่น "14:32"/"เมื่อวาน" — ต้องมี helper ใหม่หรือ reuse ของเดิมถ้ามี, ดูข้อเสนอแนะ), subtitle = ข้อความล่าสุด 1 บรรทัด ellipsis
- แถวทั้งหมดคั่นด้วย `Divider`/`SizedBox` ความสูง AppSpacing.md ระหว่างแถว + optional hairline เส้นบาง `tone.border` เฉพาะกรณีทีมต้องการเส้นคั่นชัด (ไม่ใช่กรอบรอบแถว)
- States: unread (ชื่อ+ข้อความหนาขึ้นเล็กน้อยตามที่มีอยู่แล้ว + badge แดง) / read / partner-is-driver (ไอคอนรถ) / partner-is-rider-or-peer (ไม่มีไอคอนรถ) / no-messages-yet (subtitle = ข้อความ placeholder เดิม `P.noMessagesYet`)
- ทั้งแถว (รวม avatar+title+subtitle+trailing) ต้องมี tap target รวม >= 48dp สูง (56dp avatar เกินอยู่แล้ว)
- A11y: semantics รวมต่อแถว "แชทกับ [ชื่อ], [มีข้อความใหม่ ถ้ามี], ข้อความล่าสุด [ข้อความ], [เวลา]"

---

## G9.4 US-4: หน้าทริปของฉัน (Ride Pass Card)

### G9.4.1 User Flow
1. ผู้ใช้เปิดแท็บทริปของฉัน เห็นการ์ดทริปแบบ Ride Pass ขาวนวล squircle ลอยบนพื้นเทาอ่อน (แทนการ์ดกรมท่าทึบเดิม)
2. แต่ละการ์ดแสดงเส้นทาง 🟢 ───── 🔴 พร้อมชื่อสถานที่กำกับแต่ละจุด (ไม่ใช่ตัวเลขพิกัด — ใช้ `originLabel`/`destLabel`/reverse-geocode helper ที่มีอยู่แล้ว)
3. ป้ายสถานะเป็น pill สี: "กำลังเดินทาง" (`TripStatus.inProgress`) = มินต์นวล, "เสร็จสิ้น" (`completed`) = เทา, สถานะอื่นที่มีอยู่เดิม (`scheduled`, `cancelled`, `expired`) ต้องมี pill สีของตัวเองด้วย (ดูตาราง mapping ด้านล่าง) — ไม่มีสถานะไหนตกหล่น
4. ปุ่ม "เดินทางซ้ำ" มุมขวาล่างของการ์ด (แทนตำแหน่งปุ่ม action แถวเดิมใน `TripCard`) เรียก `_recreate(t)` เดิม
5. กดที่การ์ด (ไม่ใช่ปุ่ม) → เข้ารายละเอียดทริปเดิม; ปุ่ม action อื่นที่มีอยู่เดิมของ `TripCard` (เช่น `startTrip` สำหรับ `scheduled`) ต้องยังอยู่ครบ เพียงจัดใหม่ให้เข้ากับ layout การ์ดใหม่

### G9.4.2 Components

#### RC-9 RidePassCard (แทน `TripCard` เดิม)
- Purpose: การ์ดทริปสไตล์บัตรโดยสาร อ่านง่าย ไม่มีพิกัดดิบ
- Content: แถวบน = `TripStatusPill` (ดู RC-10) + ไอคอนโหมดเดินทาง; กลางการ์ด = เส้นทาง 2 แถว (🟢 + originLabel ชื่อสถานที่จริง / เส้นประแนวตั้งเชื่อม / 🔴 + destLabel) — ทุกจุดที่เคยมีพิกัดดิบต้องผ่าน location-label resolver เดิม (`labelFor()`/`GeocodingService.reverse()`, `lib/features/geo/presentation/current_location.dart:59`) พร้อม fallback ข้อความมิตร "ตำแหน่งที่ปักหมุด" แทนพิกัดเมื่อ reverse-geocode ล้มเหลว (ไม่ใช่ปล่อยว่าง); ล่าง = เวลาออกเดินทาง + จำนวนคู่จับคู่แล้ว (`matchedCount` เดิม) + ปุ่ม "เดินทางซ้ำ" มุมขวาล่าง
- พื้นการ์ด `tone.surface` (ขาวใน light / `tone.surfaceRaised` ใน dark), squircle `AppShape.card()`, เงา `tone.cardShadow`, ไม่มี `BorderSide` ตกแต่ง
- States: scheduled / inProgress / completed / cancelled / expired (ทุกสถานะเดิมต้องมี pill ของตัวเอง) / geocode-fallback (แสดงข้อความมิตรแทนพิกัดที่ resolve ไม่ได้) / has-matches (แสดง badge จำนวนคู่) / no-matches

#### RC-10 TripStatusPill (แทน `TripStatusChip` เดิม)
- Purpose: pill สถานะทริป minimal สอดคล้อง 4 ธีม
- Mapping สี (semantic ไม่ใช่ hex ตรง — อ้างอิง token ที่มีอยู่แล้วต่อ tone):
  | สถานะ | พื้น | ตัวอักษร/ไอคอน | เหตุผล |
  |---|---|---|---|
  | scheduled | `tone.infoBg` | `tone.accentInk`/`tone.primaryInk` | ยังไม่เริ่ม เป็นกลาง ใช้โทน info เดิม |
  | inProgress | `tone.successFill`/`tone.infoBg` (มินต์นวลตาม AC) | `tone.onSuccessFill`/`tone.successInk` | ตรง AC "มินต์นวล" |
  | completed | `tone.border`/`tone.surfaceRaised` (เทา) | `tone.textSecondary` | ตรง AC "เทา" |
  | cancelled | `tone.dangerTint` | `tone.dangerInk` | เดิมใช้ `AppColors.border` เทาเฉย ๆ ซึ่งแยกไม่ออกจาก completed — เสนอเปลี่ยนเป็นโทนแดงอ่อนเพื่อแยกแยะชัดเจนขึ้น (ดูข้อเสนอแนะ เพราะ AC ไม่ได้พูดถึงสถานะนี้ตรง ๆ) |
  | expired | `tone.warningTint` | `tone.warningInk` | เดิมใช้เทาเหมือน cancelled — เสนอแยกเป็นโทนเหลือง/warning เพื่อไม่ให้ทับซ้อนความหมายกับ completed/cancelled |
- States: ต่อสถานะข้างต้นทั้งหมด (5 สถานะ) — ไม่มี "loading"/"error" (มาจาก enum ที่มีอยู่แล้วเสมอ)
- A11y: สีคู่กับ contrast ตัวอักษรต้องผ่าน >= 4.5:1 ในทั้ง 4 ธีม (ต้องตรวจเพิ่มสำหรับ cancelled/expired ถ้าเปลี่ยนโทนตามที่เสนอ) — ไอคอนประกอบทุก pill เสมอ (ไม่ใช้สีอย่างเดียวแยกสถานะ ตาม a11y NFR เดิมของโปรเจกต์)

---

## G9.5 US-5: หน้าโปรไฟล์ (Profile / Me Tab)

### G9.5.1 User Flow
1. ผู้ใช้เปิดแท็บฉัน เห็น Profile Hero Card บนสุด: อวาตาร์วงกลม 84dp กึ่งกลาง (เพิ่มจาก 96dp เดิม → ปรับเป็น 84dp ตาม AC ใหม่), ชื่อเล่นตัวหนา, `GlobalVerifiedBadge` (RC-4 เดียวกับ US-1), แถบสถิติ 3 คอลัมน์ (★ คะแนนรีวิว / จำนวนทริป / CO₂ ที่ลดได้)
2. ถ้าค่าใดไม่มีข้อมูล (เช่นยังไม่มีรีวิว) แสดง placeholder ที่สื่อความหมาย ("ยังไม่มีคะแนน"/"ยังไม่มีทริป"/"เริ่มนับเมื่อเดินทางครั้งแรก") — ห้ามแสดง 0/ว่างที่ทำให้เข้าใจผิด (ดูข้อเสนอแนะเรื่องไม่มี field จำนวนทริป/CO₂ ใน provider ปัจจุบัน)
3. เลื่อนลงเห็นปุ่ม "แก้ไขโปรไฟล์" (คงเดิม) แล้วเมนูตั้งค่าจัดเป็น 3 การ์ดมนขาว: "การเดินทาง" (รถ, สถานที่โปรด, รีวิวของฉัน), "ความปลอดภัย" (ผู้ติดต่อฉุกเฉิน, safety shield, women-only ถ้ามีจาก round7), "ระบบ" (แจ้งเตือน, ธีม, นโยบาย/ข้อกำหนด, ผู้ใช้ที่บล็อก, ออกจากระบบ) — ทุกแถวเดิมต้องอยู่ในกลุ่มใดกลุ่มหนึ่ง ไม่มีรายการหาย
4. แต่ละแถวเมนูมีไอคอนในวงกลมพื้นพาสเทลอ่อน (สีตามหมวด: การเดินทาง = โทน primary-tint, ความปลอดภัย = โทน danger-tint/warning-tint อ่อน, ระบบ = โทนกลาง/เทา) — สีต้องมาจาก tone token เสมอ
5. แตะแถวใด ๆ ยังคงพาไป route เดิมทุกจุด (`Routes.vehicle`, `Routes.mePhoto`, `Routes.mePlaces`, `Routes.meReviews`, `Routes.safety`, `Routes.safetyContacts`, `Routes.settings`, `Routes.blocked`, `Routes.policy`, `Routes.terms`, ปุ่มออกจากระบบเดิม)

### G9.5.2 Components

#### RC-11 ProfileHeroCard
- Purpose: สรุปตัวตนด้านบนสุดแบบสวยงาม
- Content: `UserAvatar.mine` 84dp (คง `onTap` ไปหน้ารูปเดิม), ชื่อ (titleLarge, w700), `GlobalVerifiedBadge` (RC-4 — แทนที่ `VerifiedBadge(label: 'ยังไม่ยืนยันตัวตน', verified: false)` เดิมตอน badges ว่าง: เวอร์ชันใหม่ไม่แสดง badge อะไรเลยถ้าไม่มี email/phone แทนที่จะโชว์ "ยังไม่ยืนยันตัวตน" — ดูข้อเสนอแนะ เพราะเป็นการเปลี่ยน UX ของสถานะ "ยังไม่ยืนยัน" จาก "แสดงป้ายลบ" เป็น "ไม่แสดงอะไรเลย"), `StatsRow` 3 คอลัมน์
- `StatsRow`: คอลัมน์ 1 = "★ x.x" หรือ "ยังไม่มีคะแนน", คอลัมน์ 2 = "N ทริป" หรือ placeholder, คอลัมน์ 3 = "X กก. CO₂" หรือ placeholder — **ทั้ง 3 ค่าต้องดึงจาก state ที่มีอยู่แล้วในระบบตาม AC; ตรวจสอบโค้ดแล้วยังไม่พบ provider ที่ให้ "จำนวนทริปรวม" หรือ "CO₂ สะสม" ของผู้ใช้ในหน้า Me ปัจจุบัน (มีแค่ per-trip data และ rating ต่อ role ผ่าน role/vehicle providers ที่ไม่ตรงกับ 'สถิติสะสมของฉัน') — ยกเป็นประเด็นให้ PM ตัดสินท้ายเอกสาร**
- States: loaded / rating-empty / trips-empty / co2-empty (placeholder ต่อคอลัมน์อิสระต่อกัน ไม่ต้องรอครบ)

#### RC-12 SettingsGroupCard (×3: การเดินทาง / ความปลอดภัย / ระบบ)
- Purpose: จัดกลุ่มเมนูตั้งค่าเดิมเป็น 3 การ์ดมนขาว
- Content: หัวข้อกลุ่ม (labelLarge, `tone.textSecondary`) + รายการ `SettingsMenuRow` ภายในการ์ดเดียว (ใช้ divider บางระหว่างแถวในการ์ดเดียวกัน ไม่ใช่การ์ดซ้อนการ์ด)
- Mapping รายการเดิม → กลุ่มใหม่ (ครบทุกแถวจาก `me_tab.dart` ปัจจุบัน):
  - **การเดินทาง**: ข้อมูลรถ (`me-vehicle-row`), รูปโปรไฟล์ (`R5.photoTitle`), สถานที่โปรด (`R6C.placesTitle`), รีวิวของฉัน (`R5.reviewMineRow`)
  - **ความปลอดภัย**: ความปลอดภัย/Safety shield (`P.meSafety`), ผู้ติดต่อฉุกเฉิน (`P.meContacts`) — (women-only/gender setting ถ้ามีจาก round7 G-9 เข้ากลุ่มนี้ด้วยถ้าถูก implement แล้ว)
  - **ระบบ**: การตั้งค่าทั่วไป (`P.meSettings` — ซึ่งอาจมีธีม/แจ้งเตือนซ้อนอยู่แล้วข้างใน), ผู้ใช้ที่บล็อก (`P.meBlocked`), นโยบาย (`S.policy`), ข้อกำหนด (`S.terms`) — ปุ่ม "ออกจากระบบ" อยู่นอก 3 การ์ด ท้ายสุดของหน้าเหมือนเดิม (destructive action ไม่ควรถูกจัดรวมเป็น "แถวเมนู" ปกติ)
- `SettingsMenuRow`: ไอคอนในวงกลม 32-36dp พื้นพาสเทล (สีตามกลุ่ม, ทุกสีจาก tone token) + label + chevron ขวา, สูง >= 48dp
- States: default / navigating (ripple feedback) — ไม่มี state พิเศษอื่นเพราะเป็นแค่ navigation list

---

## G9.6 US-6: Global Verified Badge ทั่วแอป (shared — ครอบคลุมโดย RC-4 ด้านบนแล้ว)
- ไม่มี component ใหม่เพิ่มเติมนอกจาก RC-4 — งานหลักของ US-6 คือ "grep แล้วแทนที่" ทุกจุดที่ยัง render `VerifiedBadge`/`BadgeWrap` แบบเดิม (พบแล้วอย่างน้อย: `matching_widgets.dart:BadgeWrap`, `me_tab.dart` badge row, และทุกจุดที่ `CandidateCard`/bottom sheet รายละเอียดผู้สมัครใช้ `BadgeWrap`) ให้เปลี่ยนไปใช้ RC-4 `GlobalVerifiedBadge` แทน
- ต้องยืนยันด้วย grep `kind == 'organization'`/`orgName`/`VerificationBadge.label` ว่าไม่มีจุดไหนหลุดไปโชว์ `b.label` ของ badge องค์กรอีก (ปัจจุบัน `VerificationBadge.label` ยังคง return ข้อความ "องค์กร: ..." ถ้า `kind == organization` — ฟังก์ชันนี้ไม่ควรถูกเรียกกับ badge organization อีกต่อไปหลัง filter ที่ RC-4 แล้ว แต่ตัว `.label` เองไม่ได้ถูกลบ/แก้ ตามหลัก UI-only)

---

## G9.7 US-7: Design System Tokens & Polish (พื้นฐานร่วม)

### G9.7.1 จุดที่ถอด border (decorative) vs จุดที่คงไว้ (semantic)
| จุด | ปัจจุบัน | การเปลี่ยนแปลง |
|---|---|---|
| `AppCard` | ไม่มี `BorderSide` อยู่แล้ว (rely on `CardTheme`) | ตรวจสอบ `CardTheme`/`app_theme.dart` ว่าไม่มี `side: BorderSide(color: AppColors.border)` แอบอยู่ — ถ้ามี ถอดออก |
| `CandidateCard` (`matching_widgets.dart:90-93`) | `BorderSide(color: selected ? AppColors.green : context.tone.border, width: selected?2:1)` | **คงไว้** — นี่คือ semantic border (บอกว่าการ์ดถูกเลือกอยู่หรือไม่ ไม่ใช่ตกแต่งเฉย ๆ); เปลี่ยนแค่ฝั่ง unselected จาก `context.tone.border` (1px) → พิจารณาเอาออกเป็น "ไม่มีเส้น" (0 width/none) ถ้าต้องการ borderless ทั้งระบบ แต่เส้นตอน `selected` ต้องคงไว้เสมอเพราะสื่อความหมาย state |
| Text field error state | ยังไม่ตรวจละเอียด (นอก scope ไฟล์เป้าหมาย 5 หน้า) | **คงไว้** ตามหลักการทั่วไป — error border เป็น semantic เสมอ ไม่ใช่ของตกแต่ง |
| `RoleStrip` bottom border (`Border(bottom: BorderSide(color: tone.border))`) | ใช้ `tone.border` (theme-aware) ไม่ใช่ `AppColors.border` | **ไม่ต้องแก้** — นี่คือ `tone.border` ของ round 7 ไม่ใช่ token เดิมที่ US-7 ต้องการถอด; ทำหน้าที่แบ่งโซน UI (structural divider) ไม่ใช่ box-outline แบบเดิม จึงอยู่นอกขอบเขตของ AC นี้ |
| `AppColors.border` ที่เหลือ (ค้นหาทุกจุดที่ import `tokens.dart` แล้วอ้าง `AppColors.border` ตรง ๆ) | ต้อง grep เพิ่มตอน implement (นอกเหนือจาก 2 จุดข้างต้นที่ BA ระบุไว้แล้วใน requirements บรรทัด 13) | ถอดทุกจุดที่เป็นเส้นขอบตกแต่งกล่อง/การ์ด/container ทั่วไป |

### G9.7.2 Token polish
- พื้นหลังหลักแอป: `#F8F9FC` (light) — ปัจจุบัน `ToneColors.rider.bg = #F7FAFC`/`driver.bg` เป็น navy ทึบ ต้องตรวจว่า "พื้นหลังหลัก #F8F9FC" ที่ AC ขอเป็นการปรับค่า `rider.bg` เล็กน้อย (จาก F7FAFC → F8F9FC ใกล้เคียงกันมาก) หรือเป็น token ใหม่แยกต่างหาก — ต่างกันเพียง ~1 ค่า RGB แทบไม่ต่างกันทางสายตา จึงเสนอ **ปรับ `ToneColors.rider.bg`/`driver.bg`(เมื่ออยู่ในบริบทพื้นหลังทั่วไป) ให้เป็น `#F8F9FC` ตรง ๆ** แทนสร้าง token คู่ขนาน (ลดความซับซ้อน) — ยกเป็นข้อเสนอแนะให้ยืนยัน เพราะเป็นการแก้ไข token ที่ประกาศไว้แล้วตั้งแต่ round ก่อน
- การ์ดขาว `#FFFFFF` + ambient shadow blur 16-24px opacity 4-6%: เทียบกับ `ToneColors.cardShadow` ปัจจุบัน (rider light: blur 28px @ 12% + blur 6px @ 7%) ค่อนข้างเข้มกว่าที่ AC ขอ (16-24px @ 4-6%) — เสนอให้ใช้ `cardShadow` เดิมต่อไป (ห้ามแก้ ตามที่บอกไว้ใน task context ว่า "already tuned") และตีความตัวเลข blur/opacity ของ AC เป็นแนวทางออกแบบเบื้องต้นที่ `cardShadow` เดิมได้ทำไว้ดีอยู่แล้วในทางปฏิบัติ ไม่ใช่ spec บังคับตัวเลขเป๊ะ ๆ ที่ต้องรื้อของเดิม (ดูข้อเสนอแนะท้ายเอกสาร)
- Dark-mode equivalent: มีอยู่แล้วสมบูรณ์ (`riderDark.bg`/`driverDark.bg`) — ไม่ต้องนิยามใหม่ เพียงตรวจว่าทุก container ที่ใช้ `#F8F9FC`/`#FFFFFF` ใหม่ผูกกับ `context.tone.bg`/`context.tone.surface` เสมอ ไม่ hardcode hex ตรง ๆ ในหน้า

---

## ข้อเสนอแนะที่อาจขัดกับ requirement / ต้องให้ PM ตัดสิน

### ประเด็น 1 (ใหม่ — ไม่เคยถูกยกในสมมติฐาน A/B/C/D ของ BA): MatchCandidate ไม่มีฟิลด์ "อายุ" เลย ไม่ใช่แค่ optional
- US-1 AC บรรทัด 51 ขอ "ชื่อเล่น + อายุ (ถ้ามีข้อมูลอายุในระบบ; ถ้าไม่มีให้ซ่อน)" — ตรวจสอบ `lib/features/matching/domain/match_models.dart` (`MatchCandidate` ทั้ง class) แล้ว **ไม่มีฟิลด์อายุเลยแม้แต่ฟิลด์เดียว** (คล้ายกรณีสมมติฐาน A เรื่องรูปภาพ แต่ยังไม่เคยถูก BA/PM ตัดสินใจไว้ในรอบนี้)
- ทางเลือก A: ซ่อนส่วนอายุถาวร 100% ของเวลา (ไม่ใช่ "ถ้ามี/ถ้าไม่มี" แบบ conditional จริง เพราะไม่มีวันมี) — เขียนโค้ดแบบไม่มี branch เงื่อนไขอายุเลยก็ได้ในทางปฏิบัติ
- ทางเลือก B: PM ต้องการเพิ่ม field อายุจริงในรอบถัดไป (ต้องผ่าน schema change ซึ่งนอก scope UI-only รอบนี้)
- เสนอ: ทำตามทางเลือก A ไปก่อนเพื่อไม่บล็อกงาน (สอดคล้องแนวทางเดียวกับสมมติฐาน A ของ BA ที่ PM ratify ไปแล้ว) แต่ **ต้องแจ้ง PM รับทราบอย่างชัดเจนแยกจากสมมติฐาน A** เพราะเป็นฟิลด์ข้อมูลที่ขาดหายอีกจุดที่ยังไม่เคยถูกพูดถึง

### ประเด็น 2: ปุ่ม ℹ️ ของ US-1 — เปิด "bottom sheet รายละเอียด" (AC) vs push ไปหน้าเต็ม (โค้ดปัจจุบัน)
- โค้ดปัจจุบัน `onDetail`/`R6C.detailLink` เรียก `context.push(Routes.candidate(c.tripId))` คือ full-page navigation ไม่ใช่ bottom sheet ส่วน AC ของ US-1 (บรรทัด 52) เขียนตรง ๆ ว่า "ℹ️ เปิด bottom sheet รายละเอียด"
- ทางเลือก A: คงพฤติกรรม navigation เดิม (push หน้าเต็ม) เพียงเปลี่ยนปุ่มจาก text-link เป็นวงกลม ℹ️ ลอย — ความเสี่ยง regression ต่ำที่สุด, ตรงกับ "เรียก action เดิม" ตาม tasks-round9.md T3 มากกว่า
- ทางเลือก B: ทำจริงตาม AC คือเปลี่ยนเป็น `showModalBottomSheet` แสดงรายละเอียดแบบย่อบนหน้าเดิม (ไม่ navigate ออกจาก deck) — ตรงตามถ้อยคำ AC มากกว่า แต่เป็นการเปลี่ยน navigation pattern ที่ requirement ไม่เคยยืนยันชัดว่าต้องการเปลี่ยนจริง (อาจแค่คำที่ BA ใช้หลวม ๆ)
- เอกสารนี้เขียน user flow ตามทางเลือก A ไว้ชั่วคราว (ความเสี่ยงต่ำสุด) — ให้ PM ยืนยัน/เลือกก่อน programmer เริ่ม

### ประเด็น 3: RouteSnapshotSlide (ภาพที่ 3) เมื่อ `approxDest == null`
- Driver candidate ที่กำลังค้นหา (rider ค้นหาคนขับ) จะมี `approxDest: null` เสมอตาม docstring ของ `MatchCandidate` ("Null when the candidate is a car Rider... server never reveals a Rider's destination" — แต่จริง ๆ แล้วต้องเช็คระแวดระวังว่ากรณีไหนที่ candidate เป็น driver แต่ `approxDest` เป็น null ด้วยหรือไม่ เนื่องจาก field เป็น nullable ทั่วไปในโมเดล)
- เอกสารนี้เสนอ fallback = ไม่แสดงสไลด์ที่ 3 เลยเมื่อไม่มี `approxDest` (เหลือ 2 สไลด์) สอดคล้องกับหลัก "จำนวนขีด = จำนวนภาพจริง" — ขอให้ PM/โปรแกรมเมอร์ยืนยันว่าตรงกับพฤติกรรมจริงของ field นี้ในทุก role หรือไม่ (ไม่ใช่แค่ rider-search-driver case)

### ประเด็น 4: US-2 — ขอบเขตของ `QuickHomeCard` เดิมที่ซับซ้อนกว่า AC ของ US-2 มาก
- `QuickHomeCard` ปัจจุบันมี state ~8 แบบ (missing/partial/ready/creating/register-hint/switch-failed/active-trip/error) พร้อม time-chip selector และ role segmented button และ dropoff adjuster ที่ AC ของ US-2 (การ์ดค้นหา = ช่องค้นหา + 2 ชิป + ปุ่มเดียว) ไม่ได้กล่าวถึงเลย
- ทางเลือก A: `FloatingSearchCard` (RC-7) เป็นแค่ "เปลือก" ใหม่ที่ยังคง render logic ทั้งหมดของ `QuickHomeCard` เดิมข้างในเมื่อมี state ซับซ้อน (time chip ฯลฯ) — แปลว่าการ์ดจะ "ขยาย" ออกจากรูปแบบเรียบง่ายตาม AC เมื่อ user เข้าสู่ state พวกนั้น ซึ่งขัดกับ "ไม่มีกล่องซ้อนกล่อง" บางส่วน
- ทางเลือก B: ตีความ AC ว่าต้องการเปลี่ยนเฉพาะจุดเข้าเมื่อ "ยังไม่มีทริป" (`_noTrip`) ให้เป็นการ์ดค้นหาเรียบง่ายตามนี้จริง ๆ แล้วย้าย logic ซับซ้อนของ `QuickHomeCard` เดิมไปอยู่หลังการแตะช่องค้นหา/ปุ่ม "หาเพื่อนร่วมทาง" (เปิด sheet/หน้าใหม่ที่มี time/role/dropoff ตามเดิม) — ตรงกับ "หน้าแรกเรียบง่าย" ตาม vision ของ US-2 มากกว่า แต่เป็นการเปลี่ยน flow ที่ลึกกว่าที่ AC ระบุตรง ๆ (AC บอกแค่ "ต้องเรียก action เดิม" ไม่ได้บอกว่าต้องย้าย step)
- เอกสารนี้ไม่ตัดสินเอง — ส่งให้ PM เลือก A หรือ B ก่อนเริ่ม T4

### ประเด็น 5: RC-11 — placeholder "ยังไม่ยืนยันตัวตน" หายไปเมื่อไม่มี badge เลย
- พฤติกรรมเดิมของ `me_tab.dart`: ไม่มี badge เลย → แสดง `VerifiedBadge(label: 'ยังไม่ยืนยันตัวตน', verified: false)` (แจ้งสถานะลบอย่างชัดเจน) พฤติกรรมใหม่ตาม US-6 AC (บรรทัด 141): "ต้องไม่แสดงป้าย ✓ ยืนยันตัวตนแล้ว" แต่ **ไม่ได้บอกว่าต้องแสดง/ไม่แสดงป้าย "ยังไม่ยืนยัน" แทน**
- ทางเลือก A: ไม่แสดงอะไรเลย (เงียบ) ตามที่ RC-4 ออกแบบไว้ในเอกสารนี้
- ทางเลือก B: คงป้าย "ยังไม่ยืนยันตัวตน" แบบเดิมไว้เป็น negative state ที่ยังมีประโยชน์ (บอกผู้ใช้ว่าควรไปยืนยันอีเมล/เบอร์)
- เอกสารนี้เอียงไปทาง B มากกว่าจริง ๆ (มีประโยชน์กับผู้ใช้มากกว่า เงียบเฉยๆ) แต่เขียน RC-4 ไว้แบบ A ตาม literal reading ของ AC — ให้ PM ยืนยันก่อน เพราะเป็นจุดที่กระทบทั้ง US-1 การ์ดจับคู่ (ควรมีป้ายลบไหม?) และ US-5 โปรไฟล์

### ประเด็น 6 (a11y/touch-target): ปุ่ม ✕ 64dp vs ปุ่ม 💚 ที่ต้อง "ใหญ่เด่นกว่าอย่างชัดเจน" ใน RC-3
- AC ต้องการให้ปุ่ม invite ใหญ่เด่นกว่าปุ่มอื่นชัดเจน — เอกสารเสนอ 80dp (invite) vs 64dp (skip) vs 56dp (detail) ซึ่งทั้งหมดผ่าน 48dp min tap target อยู่แล้ว ไม่มีปัญหา a11y แต่ถ้า dynamic type ผู้ใช้ตั้งค่าตัวอักษรใหญ่มาก ไอคอนวงกลมไม่ scale ตาม text scale (เป็น fixed-size icon button) — ต้องยืนยันกับ programmer ว่าจะไม่ทำให้ปุ่มเล็กกว่าข้อความ label ข้างใต้จนวางซ้อนกัน (ปัจจุบัน skip button มี label ข้อความอยู่ใต้ปุ่มอยู่แล้วตาม `_ActionBar` เดิม ซึ่งต้อง wrap ได้ที่ text scale สูงเหมือนเดิม) — เป็นรายละเอียด implementation ไม่ใช่ประเด็น scope ที่ต้องส่ง PM

### ประเด็น 7: RC-11 StatsRow — ไม่มี provider "จำนวนทริปสะสม"/"CO₂ สะสม" ของผู้ใช้ในปัจจุบัน
- ตรวจสอบ `me_tab.dart`/`profile_providers.dart` (เท่าที่อ่านได้ในรอบนี้) ไม่พบ provider ที่ให้ค่าสะสมทั้งสองนี้ตรง ๆ ในบริบทหน้า Me — อาจมีอยู่ที่อื่นในโปรเจกต์ (เช่น `trip_lifecycle_providers.dart`/impact tracking จาก round7 "Shared Impact") ที่ยังไม่ได้ตรวจในรอบนี้
- ให้ programmer ตรวจสอบเพิ่มก่อน implement ว่ามี provider ที่ใช้ได้จริงหรือไม่; ถ้าไม่มี ต้องแจ้งกลับเป็นประเด็น scope (ต้องเพิ่ม provider ใหม่ที่อ่านข้อมูลเดิม ไม่ใช่ schema ใหม่ — ยังอยู่ใน UI-only ได้ถ้าข้อมูลดิบมีอยู่แล้วใน DB เพียงไม่มี aggregation query) — ไม่ใช่ประเด็นที่ UX ตัดสินเองได้ จึงระบุไว้เป็นความเสี่ยง scope สำหรับ T7 ไม่ใช่ทางเลือก A/B ให้ PM เลือก (เป็นคำถามข้อเท็จจริงทางเทคนิคที่ programmer ต้องตรวจสอบก่อน)

### ประเด็น 8: การเปลี่ยนค่า `ToneColors.rider.bg`/`driver.bg` (G9.7.2)
- เป็นการแก้ไข token ที่ round ก่อน ๆ เคย "ตัดสินใจ" ไว้แล้ว (round 1/7) แม้ค่าจะใกล้เคียงกันมาก (#F7FAFC → #F8F9FC) — ทางเทคนิคเป็นการเปลี่ยน design token ของระบบเดิม ไม่ใช่แค่จุดเดียว ขอให้ PM รับทราบว่าเป็น breaking-ish change เชิง token แม้ผลลัพธ์ทางสายตาแทบไม่ต่าง

---

## คำตัดสิน PM (รอบ 9 — design-spec-round9.md)

อ้างอิงตอบ 8 ประเด็นข้างต้นทีละข้อ ทุกข้อ**ไม่เปลี่ยน scope ของ requirements-round9.md** (ไม่ต้องอัป requirements) — เป็นการอุดช่องว่างการตีความ/ยืนยัน implementation detail ที่ UIUX ยกมาให้ตัดสินอย่างถูกต้องแล้ว (ไม่ควรเดาเอง)

### ประเด็น 1: MatchCandidate ไม่มีฟิลด์ "อายุ" เลย
**คำตัดสิน: ทางเลือก A — ซ่อนส่วนอายุถาวร 100%** เขียนโค้ดแบบไม่มี branch เงื่อนไขแสดงอายุเลยก็ได้ (ไม่ใช่ conditional จริงเพราะไม่มีวันมีข้อมูล)
**เหตุผล:** เหตุผลเดียวกับสมมติฐาน A ที่ ratify ไปแล้วเรื่องรูปภาพ — รอบนี้เป็น UI-only ไม่เพิ่ม schema/field ใหม่ การเพิ่ม field อายุจริงต้องผ่าน BA/Architect ออกแบบแยกรอบ (privacy implication ด้วย เพราะอายุเป็นข้อมูลอ่อนไหวกว่ารูป) ไม่ใช่สิ่งที่ตัดสินใจเพิ่มกลางรอบ visual overhaul นี้ได้

### ประเด็น 2: ปุ่ม ℹ️ — bottom sheet (AC) vs push เต็มหน้า (โค้ดปัจจุบัน)
**คำตัดสิน: ทางเลือก A — คงพฤติกรรม push ไปหน้าเต็มแบบเดิม** เปลี่ยนแค่รูปลักษณ์ปุ่มเป็นวงกลมลอย ℹ️ ไม่เปลี่ยน navigation target
**เหตุผล:** tasks-round9.md T3 ระบุชัดว่า "ทั้ง 3 ปุ่มยังคงเรียก action เดิม ... โดยไม่เปลี่ยน business logic การจับคู่" — ถ้อยคำ "bottom sheet" ใน AC requirements-round9.md ตีความว่าเป็นคำอธิบายรูปแบบ interaction อย่างหลวม ๆ ของ BA ไม่ใช่ requirement เปลี่ยน navigation pattern ที่ยืนยันแน่ชัด ความเสี่ยง regression ของการเปลี่ยนเป็น bottom sheet จริง (ต้องย้าย candidate-detail content ทั้งหน้ามาอยู่ใน sheet, จัดการ state ระหว่างเปิด sheet กับ deck ด้านหลัง) ไม่คุ้มกับรอบที่เน้น "ห้ามเปลี่ยน business logic" เป็นหลัก

### ประเด็น 3: RouteSnapshotSlide เมื่อ `approxDest == null`
**คำตัดสิน: ยืนยันว่า "ซ่อนสไลด์ที่ 3 เมื่อไม่มี approxDest" ครอบคลุมทุก role ที่เป็นไปได้ ไม่จำกัดเฉพาะ rider-search-driver case** — กฎคือ: มี `approxDest` → แสดงสไลด์ route; ไม่มี (ไม่ว่าเพราะเหตุผลอะไร/role ไหนก็ตาม) → ไม่แสดงสไลด์นั้น จำนวนขีดปรับตามจริงเสมอ
**เหตุผล:** ตรงตามหลัก AC "จำนวนขีด = จำนวนภาพจริง" อยู่แล้วโดยไม่ต้องแยกเงื่อนไขตาม role เพิ่ม — เป็นกฎ data-driven เดียวที่ simple และไม่พลาดเคส edge case ที่ UIUX กังวล (driver ที่ approxDest เป็น null ด้วยเหตุผลอื่น) เพราะเงื่อนไขคือ nullability ของ field ไม่ใช่ role

### ประเด็น 4: ขอบเขต `QuickHomeCard` ซับซ้อนกว่า AC US-2
**คำตัดสิน: ทางเลือก B — ย้าย selector ที่ซับซ้อน (time chip/role segmented/dropoff adjuster) ไปอยู่หลังการแตะช่องค้นหา/ปุ่มหลัก; ค่าเริ่มต้นของการ์ดแสดงเฉพาะพื้นผิวขั้นต่ำตาม AC (ช่องค้นหา + 2 ชิป + ปุ่มเดียว)**
**เหตุผล:** ตรวจโค้ด `quick_home_card.dart` แล้วพบว่า state `_ready()` (บรรทัด 208-370, เกิดเมื่อผู้ใช้มี preset บ้าน/ที่ทำงานครบแล้ว — ซึ่งเป็น**สถานะปกติของผู้ใช้กลับมาใช้ซ้ำ ไม่ใช่ edge case**) แสดง time chip + role segmented + dropoff adjuster **ทั้งหมดพร้อมกันโดยไม่ต้องแตะอะไรก่อน** ถ้าใช้ทางเลือก A (ห่อเปลือกใหม่ครอบ logic เดิมทั้งหมด) การ์ดจะไม่เรียบง่ายตาม AC เลยสำหรับผู้ใช้ส่วนใหญ่ที่ผ่าน onboarding ไปแล้ว ขัดกับเจตนารมณ์หลักของ US-2 ("ไม่ต้อง pinch-zoom เอง...UI ค้นหาที่ลอยเรียบไม่เทอะทะ") และ AC ข้อ "ต้องไม่มีกล่องซ้อนกล่อง" โดยตรง — ทางเลือก B เสี่ยง regression มากกว่าเล็กน้อย (ต้องย้าย step) แต่ยังคงเรียก provider/action เดิมทั้งหมดของ `quickHomeProvider` ไม่เปลี่ยนแค่ห่อ UI entry ใหม่ จึงไม่ขัดกับกติกา "ห้ามเปลี่ยน business logic"
**ขอบเขตการทำ:** เปิด selector เดิม (time/role/dropoff) ผ่าน sheet/หน้าเมื่อผู้ใช้แตะช่องค้นหาหรือปุ่ม "หาเพื่อนร่วมทาง" — content ข้างในยังเป็น logic/widget เดิมของ `_ready()` ทั้งหมด (ไม่ต้องเขียนใหม่) เพียงเปลี่ยนจุดเรียกจาก "แสดงอยู่บนการ์ดเสมอ" เป็น "แสดงหลังแตะ" เท่านั้น สถานะ `missing`/`partial` (register hint) ที่เนื้อหาเบากว่าอยู่แล้วให้คงแสดงตรงบนการ์ดได้ตามเดิมไม่ต้องซ่อน (เนื้อหาเดิมของ 2 state นี้สั้นพออยู่แล้ว ไม่ขัด AC); `with-active-trip` (G9.2.3) คงแสดงสรุปทริปตรงบนการ์ดเหมือนเดิมเช่นกันไม่ต้องซ่อน (เป็นข้อมูลสำคัญที่ควรเห็นทันที ไม่ใช่ตัวเลือกก่อนค้นหา)

### ประเด็น 5: placeholder "ยังไม่ยืนยันตัวตน" เมื่อไม่มี badge เลย
**คำตัดสิน: ทางเลือก B — คงป้าย "ยังไม่ยืนยันตัวตน" (negative state) ไว้ ทั้งใน US-1 การ์ดจับคู่ และ US-5 โปรไฟล์** ไม่ใช่ทางเลือก A (เงียบ/ไม่แสดงอะไรเลย) ที่ RC-4 ร่างไว้
**เหตุผล:** US-6 AC (บรรทัด 141 ของ requirements-round9.md) ห้ามเฉพาะการ "ปลอมสถานะยืนยันให้คนที่ยังไม่ได้ยืนยันจริง" — ไม่ได้ห้ามแสดงสถานะลบที่บอกความจริงตามที่เป็นอยู่ การคงป้าย negative ไว้มีประโยชน์กับผู้ใช้จริง (กระตุ้นให้ไปยืนยันอีเมล/เบอร์, ช่วยให้ผู้ใช้อื่นบนการ์ดจับคู่ประเมินความน่าเชื่อถือได้ตามจริง) และไม่ขัดกับ "Global Verified badge เดียว" (badge บวกยังคงรวมเป็นป้ายเดียวตามเดิม) — ปรับ RC-4: เพิ่ม state `not-verified` (แสดงป้าย "ยังไม่ยืนยันตัวตน" โทนเทา/เป็นกลาง ไม่ใช่สีแดง/อันตราย) คู่กับ state `shown`/`hidden` เดิม — `hidden` (ไม่มี field ข้อมูลใด ๆ เลยจริง ๆ เพราะยัง loading) ยังคงมีไว้สำหรับ edge case โหลดข้อมูลไม่สำเร็จเท่านั้น ไม่ใช่ default ของ "ไม่มี badge"

### ประเด็น 6: ขนาดปุ่ม 3 ปุ่ม RC-3 (a11y)
**รับทราบ — ไม่มีประเด็น scope ต้องตัดสิน** เป็นรายละเอียด implementation ที่ Programmer ดำเนินการเองได้ตามที่ UIUX ระบุไว้แล้ว (80dp/64dp/56dp ผ่าน 48dp min tap target ครบ, ต้องแค่ระวัง label ข้อความใต้ปุ่ม wrap ได้ที่ text scale สูง)

### ประเด็น 7: StatsRow ไม่มี provider จำนวนทริปสะสม/CO₂ สะสม
**คำตัดสิน:** ให้ Programmer ตรวจสอบก่อน implement ตามที่ UIUX เสนอ (ค้นหา `trip_lifecycle_providers.dart`/round7 "Shared Impact" และจุดอื่นที่เกี่ยวข้องก่อน) — **กรณีพบ provider ที่ใช้ได้จริง**: ใช้ตามนั้น **กรณีไม่พบเลย**: ให้ถือเป็น**fallback ที่ระดับ column ไม่ใช่ blocker ของทั้ง T7** — คอลัมน์ที่ไม่มีข้อมูลจริงให้แสดง placeholder สื่อความหมาย (เช่น "ยังไม่เปิดให้ดูข้อมูลนี้"/"เร็ว ๆ นี้") เหมือน state `trips-empty`/`co2-empty` ที่ RC-11 ออกแบบไว้แล้วอยู่แล้ว โดยไม่บล็อกการส่ง T7/US-5 ส่วนที่เหลือทั้งหมด — การเพิ่ม aggregation query ใหม่ที่อ่านข้อมูลดิบที่มีอยู่แล้ว (ถ้าเป็นไปได้ในเวลา) ยังถือว่าอยู่ใน UI/data-layer ของรอบนี้ได้ (ไม่ใช่ schema ใหม่) แต่ถ้าซับซ้อนเกินไป/ต้องมี schema ใหม่จริง ให้ Programmer แจ้งกลับเป็นประเด็น scope แยก ไม่ใช่เดาทำเอง
**เหตุผล:** รอบนี้เป็น UI-only ที่เน้นห้าม block ส่งงาน — ไม่ควรให้ 1 คอลัมน์สถิติที่ขาด provider ทำให้ทั้งหน้าโปรไฟล์ overhaul ล่าช้า ในเมื่อ RC-11 ออกแบบ empty-state ไว้รองรับอยู่แล้ว

### ประเด็น 8: เปลี่ยนค่า `ToneColors.rider.bg`/`driver.bg` จาก `#F7FAFC` → `#F8F9FC`
**คำตัดสิน: อนุมัติ** ให้ปรับค่า token เดิมตรง ๆ ตามที่ UIUX เสนอ (ไม่สร้าง token คู่ขนานใหม่)
**เหตุผล:** ผลต่างสายตาแทบไม่มี (1-2 ค่า RGB) ไม่กระทบ contrast/WCAG ที่เคยผ่านมาแล้วในทางปฏิบัติ การสร้าง token คู่ขนานจะเพิ่มความซับซ้อนของระบบ design token โดยไม่จำเป็น — เป็น "small but real" change ตามที่ orchestrator อธิบายไว้ถูกต้อง แต่ไม่ถึงขั้นต้องผ่านกระบวนการตัดสินใจแยกใหญ่โต เพราะ effect เข้ากันได้กับ AC ที่เขียนไว้ตรง ๆ อยู่แล้ว

---

**สรุปสำหรับ Programmer:** เอกสารนี้ (design-spec-round9.md) พร้อมให้เริ่มงานได้แล้วทั้งหมด รวมคำตัดสิน PM 8 ข้อข้างบน — จุดที่ต้องปรับจาก draft เดิมของ UIUX ก่อนเริ่มเขียนโค้ดจริง: **RC-4 ต้องเพิ่ม state `not-verified`** (ประเด็น 5), **RC-7/US-2 ต้องย้าย selector ซับซ้อนไปหลังการแตะช่องค้นหา** (ประเด็น 4), ส่วนที่เหลือใช้ตามที่ UIUX ร่างไว้ในเอกสารได้ทันที (ปุ่ม ℹ️ คงพฤติกรรม push เดิม, ไม่มีอายุถาวร, route snapshot ซ่อนแบบ data-driven ตาม nullability, StatsRow มี fallback ไม่บล็อก, token bg เปลี่ยนตามที่เสนอ)
