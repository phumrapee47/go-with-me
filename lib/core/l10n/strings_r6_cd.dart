/// Thai copy for round 6 stage C+D (deck, swipe/undo, Match Moment, presets, one-tap card).
/// Safety / error / consent copy is NOT reworded here (US-40).
abstract final class R6C {
  // ---- view toggle (F-12) ----
  static const viewGroup = 'มุมมอง';
  static const viewCard = 'การ์ด';
  static const viewList = 'รายการ';

  // ---- deck ----
  static String counter(int i, int n) => '$i จาก $n';
  static const nextCardHeading = 'การ์ดถัดไป';
  static String overlapLine(int pct) => 'ทางเดียวกัน ~$pct%';
  static String overlapSemantics(int pct) => 'ทางเดียวกันประมาณ $pct เปอร์เซ็นต์';
  static String departLine(String when) => 'ออกเดินทาง $when';
  static const seatOne = 'รับได้ 1 คน';
  static String driverShortLimit(String x) => 'รับได้ 1 คน · ไม่เกิน $x จากปลายทางของเขา';
  static const riderLine = 'คนนั่ง';
  static const privacyCaption = 'จะเห็นรูปและปลายทางจริงเมื่อจับคู่กันแล้ว';
  static const detailLink = 'ดูรายละเอียด';
  static const skip = 'ข้าม';
  static const invite = 'ชวนกลับด้วยกัน';
  static const stampInvite = 'ชวน';
  static const stampSkip = 'ข้าม';
  static const coach = 'ปัดขวาเพื่อชวน ปัดซ้ายเพื่อข้าม หรือกดปุ่มด้านล่าง';
  static const deckLoading = 'กำลังหาเพื่อนกลับบ้านให้คุณ...';
  static const deckError = 'โหลดการ์ดไม่สำเร็จ ลองอีกครั้งนะ';
  static const endTitle = 'ดูครบทุกคนแล้ว';
  static String endSummary(int n) => 'ชวนไป $n คน';
  static const endToList = 'ดูเป็นรายการ';
  static const endToRequests = 'ดูคำขอที่ชวนไว้';
  static const endRefresh = 'รีเฟรช';
  static const emptyEditTrip = 'แก้เวลา/ทริป';
  static const unavailable = 'คนนี้ไม่ว่างแล้ว';
  static String announceSkipped(String name) => 'ข้าม $name แล้ว';
  static String announceNext(String name) => 'การ์ดถัดไป $name';
  static String cardSemantics({
    required String name,
    required String role,
    required String badges,
    required int pct,
    required String when,
    required String roleText,
  }) =>
      '$name, $role, $badges, ${overlapSemantics(pct)}, ออกเดินทาง $when, $roleText';

  // ---- invite / undo (US-35, Q6) ----
  static String inviting(String name) => 'กำลังชวน $name…';
  static const undo = 'เลิกชวน';
  /// Card rating line (US-36), only drawn when the server sent both values.
  static String ratingLine(double avg, int count) => '★ ${avg.toStringAsFixed(1)} ($count รีวิว)';
  static String ratingSemantics(double avg, int count) => 'คะแนนรีวิวเฉลี่ย ${avg.toStringAsFixed(1)} จาก 5 จาก $count รีวิว';
  static const undone = 'เลิกชวนแล้ว';
  static String undoLeft(int s) => 'เหลือ $s วินาที';
  static String announceInviting(String name, int s) => 'กำลังชวน $name กดเลิกชวนได้ภายใน $s วินาที';
  static String announceUndone(String name) => 'เลิกชวน $name แล้ว';
  static const undoAccepted = 'อีกฝ่ายตอบรับไปแล้ว เลิกชวนไม่ได้ แต่ยกเลิกการจับคู่ได้ที่หน้าจับคู่';
  static const undoClosed = 'คำขอนี้ปิดไปแล้ว เลิกชวนไม่ได้แล้วนะ';
  static const undoUnknown = 'ตอนนี้ยังยกเลิกคำขอนี้ไม่ได้ ดูสถานะได้ที่หน้าคำขอ';
  static const throttled = 'ชวนถี่เกินไป รอสักครู่แล้วลองใหม่นะ (การเลิกชวนก็นับเป็นการชวนหนึ่งครั้งเหมือนกัน)';
  static String inviteFailed(String reason) => 'ชวนไม่สำเร็จ $reason';
  static const capBar = 'ตอนนี้ชวนได้พร้อมกันครบจำนวนสูงสุดแล้ว รอเพื่อนตอบก่อนนะ';
  static const dismiss = 'ปิดข้อความ';

  // ---- Match Moment (US-37) ----
  static const momentTitle = 'ได้เพื่อนกลับบ้านแล้ว! 🎉';
  static const momentTitleSemantics = 'ได้เพื่อนกลับบ้านแล้ว';
  static String momentSub(String name) => '$name ไปด้วยกันกับคุณ';
  static const momentGreet = 'ทักทายนัดจุดรับ';
  static const momentGreetText = 'สวัสดี! เรานัดจุดรับกันที่ไหนดี';
  static const momentMap = 'ดูแผนที่การเดินทาง';
  static const momentClose = 'ปิด';
  static const momentMapUnavailable = 'ยังไม่ถึงเวลาเดินทาง ดูรายละเอียดการจับคู่ก่อนนะ';

  // ---- presets (US-38) ----
  static const placesTitle = 'สถานที่โปรด';
  static const placesRowSub = 'บ้านและจุดเริ่มประจำ เก็บไว้ในเครื่องนี้เท่านั้น';
  static const localOnlyCaption = 'เก็บไว้ในเครื่องนี้เท่านั้น';
  static const noticeTitle = 'เก็บไว้ในเครื่องนี้เท่านั้น';
  static const noticeBody =
      'บ้านและจุดเริ่มประจำของคุณเก็บไว้ในเครื่องนี้เท่านั้น ไม่ถูกส่งไปที่เซิร์ฟเวอร์ ไม่ตามไปเมื่อเปลี่ยนเครื่อง (ต้องตั้งใหม่) และจะถูกลบเมื่อออกจากระบบหรือลบบัญชี คุณลบเองได้ทุกเมื่อ';
  static const noticeImportant = 'เมื่อสร้างทริป จุดเริ่มและปลายทางของทริปนั้นจะถูกบันทึกตามปกติ';
  static const noticeOk = 'เข้าใจแล้ว ไปต่อ';
  static const noticeCancel = 'ยกเลิก';
  static const homeName = 'บ้าน';
  static const homeRow = 'บ้าน';
  static const startRow = 'จุดเริ่มประจำ';
  static const editHomeTitle = 'ตั้งบ้าน';
  static const editStartTitle = 'ตั้งจุดเริ่มประจำ';
  static const nameLabel = 'ชื่อที่เรียก';
  static const nameHint = 'ไม่เกิน 20 ตัวอักษร';
  static const nameTooLong = 'ชื่อยาวเกินไป (ไม่เกิน 20 ตัวอักษร)';
  static const nameEmpty = 'ใส่ชื่อก่อนนะ';
  static const placeLabelHome = 'ที่อยู่บ้าน';
  static const placeLabelStart = 'สถานที่เริ่มต้น';
  static const typeGroup = 'ประเภทจุดเริ่ม';
  static const typeWork = 'ที่ทำงาน';
  static const typeCampus = 'มหาวิทยาลัย';
  static const typeOther = 'อื่นๆ';
  static const next = 'ต่อไป';
  static const save = 'บันทึก';
  static const saved = 'บันทึกไว้ในเครื่องนี้แล้ว';
  static const saveFailed = 'บันทึกไม่สำเร็จ ลองอีกครั้งนะ';
  static const edit = 'แก้ไข';
  static const remove = 'ลบ';
  static const removed = 'ลบแล้ว';
  static const done = 'เสร็จ';
  static String removeTitle(String name) => 'ลบ $name ออกจากเครื่องนี้?';
  static const removeBody = 'ลบแล้วจะไม่มีข้อมูลนี้เหลืออยู่ในเครื่อง ตั้งใหม่ได้ทุกเมื่อ';
  static const notSet = 'ยังไม่ได้ตั้ง';
  static const setHome = 'ตั้งบ้าน';
  static const setStart = 'ตั้งจุดเริ่มประจำ';
  static const sameAsHome = 'จุดเริ่มกับบ้านอยู่ที่เดียวกัน ลองเลือกจุดเริ่มใหม่';
  static const pickPlaceFirst = 'เลือกสถานที่ก่อนนะ';
  static const useCurrent = 'ใช้ตำแหน่งปัจจุบัน';
  static const pickOnMap = 'ปักหมุดบนแผนที่';

  // ---- one-tap card (US-39) ----
  static const quickTitle = 'กำลังจะกลับบ้านใช่ไหม?';
  static String quickRoute(String from, String to) => 'จาก $from ไป $to';
  static const quickLandmark = 'ทางลัดกลับบ้าน';
  static const quickCta = 'หาเพื่อนกลับบ้าน';
  static String quickCtaSemantics(String time, String role) => 'หาเพื่อนกลับบ้าน เวลา $time โหมด $role';
  static const quickCreating = 'กำลังสร้างทริป...';
  // ---- minimal ready-state surface (round 9, PM ruling #4: selectors move behind a tap) ----
  static const quickSearchPlaceholder = 'วันนี้กลับไหนดี?';
  static const quickShortcutHome = '🏠 บ้าน';
  static const quickShortcutWork = '🏢 ที่ทำงาน';
  static const quickPrimaryCta = 'หาเพื่อนร่วมทาง';
  static const quickSelectorsTitle = 'ตั้งเวลาและบทบาท';
  static String quickSearchSemantics(String route) => 'ค้นหาเพื่อนร่วมทางกลับบ้าน $route แตะเพื่อตั้งเวลาและบทบาท';
  static const timeGroup = 'เวลาออกเดินทาง';
  static const timeNow = 'ตอนนี้เลย';
  static const timeOther = 'เวลาอื่น...';
  static String timeSemantics(String label, bool selected) => selected ? '$label, เลือกแล้ว' : '$label น.';
  static const roleGroup = 'บทบาทวันนี้';
  static const roleRider = 'คนนั่ง';
  static const roleDriver = 'ขับรถเอง';
  static String dropoffRow(String x) => 'รับส่งห่างจากปลายทางคุณได้ไม่เกิน $x';
  static const dropoffAdjust = 'ปรับ';
  static const dropoffDone = 'ตกลง';
  static const driverNeedsRegister = 'ต้องลงทะเบียนคนขับก่อน';
  static const driverRegisterLink = 'ลงทะเบียนคนขับ';
  static const driverNoVehicle = 'ยังไม่มีข้อมูลรถ ลงทะเบียนคนขับก่อนนะ';
  static const stepByStep = 'ไปตั้งทีละขั้น';
  static const createOwn = 'สร้างทริปเอง';
  static const createOwnLink = 'สร้างทริปเองทีละขั้น';
  static const goActiveTrip = 'ไปที่ทริปเดิม';
  static const missingTitle = 'ตั้งบ้านไว้ แล้วกลับบ้านได้ในแตะเดียว';
  static const missingCta = 'ตั้งค่าสถานที่โปรด';
  static String partialMissing(String what) => 'ยังขาด$what';
  static const partialCta = 'ตั้งค่าต่อ';
  static const quickNetworkError = 'สร้างทริปไม่สำเร็จ ลองอีกครั้งนะ';
  static const quickRetry = 'ลองอีกครั้ง';
  static const quickCreated = 'สร้างทริปกลับบ้านแล้ว';
}
