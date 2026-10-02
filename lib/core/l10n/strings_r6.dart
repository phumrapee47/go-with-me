import 'strings_roles.dart';

/// Thai copy for round 6 (stage A+B: slider, unified ride screen, friendly micro-copy).
/// New file on purpose: the older string files are only touched for the 5 US-40 phrases.
///
/// Safety / error / SOS / cancel / delete / consent copy is NOT reworded here (US-40).
abstract final class R6 {
  // ---- SwipeToConfirmSlider labels (design-spec F.4.1, US-31) ----
  static const sliderStart = 'สไลด์เพื่อเริ่มออกเดินทาง';
  static const sliderBoard = 'สไลด์เพื่อขึ้นรถแล้ว';
  static const sliderArriveHome = 'สไลด์เมื่อถึงบ้านปลอดภัย';
  static const sliderArriveDest = 'สไลด์เมื่อถึงที่หมายปลอดภัย';

  // ---- slider states ----
  static const sliderNearDest = 'ใกล้ถึงแล้ว';
  static const sliderNearPickup = 'ใกล้จุดรับแล้ว';
  static const sliderHoldingLabel = 'กดค้างไว้...';
  static const sliderHoldAnnounce = 'กดค้างเพื่อยืนยัน';
  static const sliderSubmitting = 'กำลังบันทึก...';
  static const sliderSubmittingAnnounce = 'กำลังบันทึก';
  static const sliderTapHint = 'สไลด์ไปทางขวา หรือกดค้างที่แถบ 1.5 วินาที';
  static const sliderHelp = 'ลากไม่ได้? กดค้างที่แถบ 1.5 วินาที';
  static const sliderSemanticsHint = 'ดับเบิลแตะเพื่อยืนยัน หรือกดค้างแล้วปล่อยเมื่อครบ';
  static const sliderValueReady = 'พร้อมยืนยัน';
  static String sliderValueDisabled(String reason) => 'ปิดใช้งาน $reason';
  static String sliderActionName(String label) => 'ยืนยัน: $label';
  static const sliderRetryHint = 'สไลด์ใหม่ได้เลย';
  static const sliderOfflineError = 'ยังบันทึกไม่ได้ เพราะไม่มีอินเทอร์เน็ต ยังไม่ถือว่าจบทริป';

  // ---- success texts (with emoji + screen-reader text without the emoji name, US-40) ----
  static const boardedSuccess = R.boardSuccess;
  static const boardedSuccessSemantics = 'ขึ้นรถเรียบร้อยแล้ว';
  static const startedSuccess = 'เริ่มออกเดินทางแล้ว';
  static const arrivedHome = 'ถึงบ้านปลอดภัยแล้ว 🎉 ขอบคุณเพื่อนร่วมทาง';
  static const arrivedHomeSemantics = 'ถึงบ้านปลอดภัยแล้ว ขอบคุณเพื่อนร่วมทาง';
  static const arrivedDest = 'ถึงที่หมายปลอดภัยแล้ว 🎉 ขอบคุณเพื่อนร่วมทาง';
  static const arrivedDestSemantics = 'ถึงที่หมายปลอดภัยแล้ว ขอบคุณเพื่อนร่วมทาง';

  // ---- Driver: arrived at pickup (US-33) ----
  static const arrivedAtPickupButton = 'ถึงจุดรับแล้ว';
  static const arrivedAtPickupSemantics = 'แจ้งคนนั่งว่าถึงจุดรับแล้ว';
  static const arrivedAtPickupMessage = R.driverArrivedPickup;
  static const arrivedAtPickupSent = 'ส่งแล้ว';
  static const arrivedAtPickupSentAnnounce = 'ส่งข้อความแล้ว';
  static String arrivedAtPickupCooldown(int s) => 'ส่งซ้ำได้ใน $s วินาที';
  static const arrivedAtPickupFailed = 'ส่งไม่สำเร็จ ลองอีกครั้ง';
  static const arrivedAtPickupNoPoint = 'ยังไม่ได้กำหนดจุดรับ';
  static const arrivedAtPickupThrottled = 'เพิ่งส่งไป รอสักครู่แล้วลองใหม่';

  // ---- UnifiedRideScreen ----
  static const sheetLabel = 'แผ่นข้อมูลการเดินทาง';
  static const sheetLevelCollapsed = 'ระดับย่อ';
  static const sheetLevelHalf = 'ระดับครึ่ง';
  static const sheetLevelFull = 'ระดับเต็ม';
  static const sheetExpand = 'ขยาย';
  static const sheetCollapse = 'ย่อ';
  static const sheetAnnounceFull = 'แผ่นข้อมูลขยายเป็นเต็มจอ';
  static const sheetAnnounceHalf = 'แผ่นข้อมูลขยายเป็นครึ่งจอ';
  static const sheetAnnounceCollapsed = 'แผ่นข้อมูลย่อลงแล้ว';
  static const back = 'กลับ';
  static const waitingDepart = 'รอออกเดินทาง';
  static const waitingDepartHelp = 'เมื่อพร้อมแล้ว สไลด์เพื่อเริ่มออกเดินทาง';
  static const driverArrivedStatus = 'คนขับมารอที่จุดรับแล้วนะ';
  static const soloTitle = 'ทริปของคุณ';
  static const soloStatusInProgress = 'กำลังเดินทาง';
  static const soloStatusScheduled = 'รอออกเดินทาง';
  static const noPeerHint = 'ยังไม่มีคู่ร่วมทางในทริปนี้';
  static const pickupAgreedTag = 'ตกลงแล้ว';
  static const pickupNotSet = 'ยังไม่ได้กำหนดจุดรับ';
  static const pickupCardTitle = 'จุดรับ';
  static const safetySection = 'ความปลอดภัย';
  static const sosTile = 'ขอความช่วยเหลือ SOS';
  static const detailsSection = 'รายละเอียดทริป';
  static const chatSection = 'แชท';
  static const chatEmpty = 'ยังไม่มีข้อความ';
  static const chatEnded = 'แชทนี้ปิดแล้ว';
  static const moreActions = 'การกระทำอื่น';
  static const cancelTripAction = 'ยกเลิกทริป';
  static const reportPartnerAction = 'รายงานผู้ใช้';
  static const cancelMatchAction = 'ยกเลิกการจับคู่';
  static const routeFrom = 'จาก';
  static const routeTo = 'ไป';
  static const quickRepliesTitle = 'ข้อความด่วน';
  static const arrivedSummaryHome = 'กลับหน้าหลัก';
  static const arrivedRateAction = 'ให้คะแนนเพื่อนร่วมทาง';
  static const arrivedSharingStopped = 'การแชร์ตำแหน่งหยุดแล้ว เราแจ้งคู่ร่วมทางให้แล้ว';
  static const guardBackToMatch = 'ตอนนี้ยังดูแผนที่ร่วมกันไม่ได้';
  static const tripNotFound = 'ไม่พบทริปที่กำลังดำเนินอยู่';
  static const peerEndedRider = 'การจับคู่นี้สิ้นสุดแล้ว ทริปของคุณยังเดินทางต่อได้';
  static const overdueTitle = 'เลยเวลาที่คาดไว้แล้ว ถ้าถึงแล้วให้สไลด์เพื่อจบทริป';
  static const textStatusTitle = 'สถานะตามข้อความ';
}
