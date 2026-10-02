/// Thai copy for Phase 3 (trip creation, nearby, matches, profile).
/// Same stop-gap as `S`: one place, migrate to ARB later.
abstract final class T {
  // Home
  static const homeCreateTrip = 'สร้างทริป';
  static const homeCreatePrompt = 'ไปกันเลย - สร้างทริป';
  static const homeMyTrip = 'ทริปปัจจุบัน';
  static const homeNearbyHeader = 'คนที่กำลังกลับใกล้ฉัน';
  static const homeSeeAll = 'ดูทั้งหมด';
  static const homeNoTripBody = 'สร้างทริปก่อนเพื่อหาคนทางเดียวกัน';
  static const homeNobodyNear = 'ยังไม่มีใครทางเดียวกันตอนนี้';
  static const homeNobodyNearBody = 'ลองกลับมาดูใหม่อีกครั้ง หรือปรับเวลาออกเดินทาง';
  static const mapPrivacy = 'ตำแหน่งแสดงเป็นบริเวณกว้าง จนกว่าคุณสองคนจะจับคู่กัน';

  // Create trip
  static const newTripTitle = 'สร้างทริป';
  static const stepOf = 'ขั้นที่ %s จาก 3';
  static const fromLabel = 'เริ่มจากตรงไหน';
  static const toLabel = 'จะไปไหน';
  static const useCurrent = 'ใช้ตำแหน่งปัจจุบัน';
  static const pickOnMap = 'ปักหมุดบนแผนที่';
  static const searchHint = 'พิมพ์อย่างน้อย 3 ตัวอักษร';
  static const searching = 'กำลังค้นหา...';
  static const noPlaceFound =
      'ไม่พบสถานที่นี้ ลองพิมพ์ชื่อถนนหรือย่านใกล้เคียง หรือปักหมุดบนแผนที่';
  static const searchRateLimited = 'ค้นหาถี่เกินไป รอสักครู่แล้วลองใหม่';
  static const searchUnavailable = 'ค้นหาที่อยู่ไม่ได้ในตอนนี้ ปักหมุดบนแผนที่แทนได้';
  static const permissionDeniedHint = 'ยังใช้ตำแหน่งปัจจุบันไม่ได้ แต่ยังสร้างทริปได้ด้วยการค้นหาหรือปักหมุด';
  static const hasActiveTrip = 'คุณมีทริปที่ยังไม่จบ 1 ทริป';
  static const hasActiveTripBody = 'จบหรือยกเลิกทริปเดิมก่อนจึงจะสร้างทริปใหม่ได้';
  static const goMyTrips = 'ไปที่ทริปของฉัน';
  static const errOriginMissing = 'เลือกจุดเริ่มต้น';
  static const errDestMissing = 'เลือกปลายทาง';
  static const errTooClose = 'จุดเริ่มต้นกับปลายทางใกล้กันมาก ลองเลือกปลายทางที่ไกลกว่านี้';
  static const errDepartPast = 'เลือกเวลาที่ยังมาไม่ถึง';
  static const errModeMissing = 'เลือกวิธีเดินทาง';

  // Consent for location
  static const locConsentTitle = 'ขอใช้ตำแหน่งของคุณ';
  static const locConsentBody =
      'เราใช้ตำแหน่งของคุณเฉพาะตอนที่คุณกดปุ่มนี้ เพื่อตั้งจุดเริ่มต้นของทริป '
      'คนอื่นจะไม่เห็นตำแหน่งที่แน่นอนของคุณ ระบบจะบันทึกว่าคุณยินยอมให้ใช้ตำแหน่ง';
  static const locConsentAllow = 'ยินยอมและใช้ตำแหน่ง';
  static const locConsentNot = 'ไม่ตอนนี้';
  static const locOpenSettings = 'เปิดตำแหน่งในการตั้งค่าของเครื่อง หรือเลือกจุดด้วยการค้นหา/ปักหมุด';

  // Pick
  static const pickTitleOrigin = 'ปักหมุดจุดเริ่มต้น';
  static const pickTitleDest = 'ปักหมุดปลายทาง';
  static const pickTitleMeeting = 'ปักหมุดจุดนัดพบ';
  static const usePoint = 'ใช้จุดนี้';
  static const resolvingAddress = 'กำลังหาชื่อสถานที่...';

  // Options
  static const departQuestion = 'ออกเดินทางเมื่อไหร่';
  static const departNow = 'ตอนนี้';
  static const departSchedule = 'กำหนดเวลา';
  static const today = 'วันนี้';
  static const tomorrow = 'พรุ่งนี้';
  static const pickTime = 'เลือกเวลา';
  static const modeQuestion = 'เดินทางด้วยอะไร';
  static const modeHelper = 'เราจะจับคู่กับคนที่เดินทางแบบเดียวกัน';

  // Confirm
  static const confirmTitle = 'ตรวจสอบก่อนสร้างทริป';
  static const calculatingRoute = 'กำลังคำนวณเส้นทาง...';
  static const routeEstimate = 'เวลาเป็นค่าประมาณ';
  static const routeFailed = 'คำนวณเส้นทางไม่ได้ในตอนนี้ ลองใหม่อีกครั้ง';
  static const privacyNote = 'คนอื่นจะเห็นเพียงบริเวณโดยประมาณ จนกว่าคุณจะยอมรับการจับคู่';
  static const createTrip = 'สร้างทริป';
  static const tripCreated = 'สร้างทริปแล้ว กำลังหาคนทางเดียวกัน';
  static const rowFrom = 'จาก';
  static const rowTo = 'ไป';
  static const rowTime = 'เวลา';
  static const rowMode = 'วิธี';

  // Nearby
  static const nearbyPrivacy = 'ตำแหน่งแสดงเป็นบริเวณกว้าง จนกว่าคุณสองคนจะจับคู่กัน';
  static const nearbyNoTrip = 'สร้างทริปก่อนเพื่อหาคนทางเดียวกัน';
  static const nearbyEmpty = 'ยังไม่มีใครทางเดียวกันตอนนี้';
  static const nearbyEmptyHint = 'ลองปรับเวลาออกเดินทางให้ยืดหยุ่นขึ้น หรือกลับมาดูใหม่อีกครั้ง';
  static const requestsTitle = 'คำขอจับคู่';
  static const goTogether = 'กลับด้วยกัน';
  static const requested = 'ส่งคำขอแล้ว';
  static const matched = 'จับคู่แล้ว';
  static const overlap = 'เส้นทางซ้อนกัน';
  static const distanceAbout = 'ห่าง ~';
  static const notAvailable = 'ทริปนี้ไม่พร้อมแล้ว';
  static const sendRequestTitle = 'ส่งคำขอกลับด้วยกัน?';
  static const sendRequestBody =
      'อีกฝ่ายจะเห็นชื่อ และป้ายยืนยันของคุณ หากเขาตอบรับ คุณทั้งสองจะเห็นข้อมูลกันมากขึ้นและตกลงจุดนัดพบกันได้';
  static const sendRequest = 'ส่งคำขอ';
  // US-40 (round 6): friendlier, shown only after a successful send.
  static const requestSent = 'ชวนเพื่อนแล้ว! รอเพื่อนตอบแป๊บนะ';
  static const acceptedTogether = 'ไปด้วยกันเลย!';
  static const requestMatchedNow = 'จับคู่แล้ว! อีกฝ่ายขอคุณไว้ก่อนแล้ว';
  static const requestDeclined = 'คำขอไม่ได้รับการตอบรับ';
  static const newRefresh = 'ดึงลงเพื่อรีเฟรช';

  // Requests / matches
  static const tabIncoming = 'คำขอเข้า';
  static const tabSent = 'ที่ฉันส่ง';
  static const noIncoming = 'ยังไม่มีคำขอใหม่';
  static const noSent = 'ยังไม่ได้ส่งคำขอ';
  static const accept = 'ตอบรับ';
  static const decline = 'ปฏิเสธ';
  static const waitingReply = 'รอการตอบรับ';
  static const closedRequest = 'คำขอนี้ปิดแล้ว';
  static const matchesTitle = 'จับคู่แล้ว';
  static const matchesEmpty = 'ยังไม่มีคู่ที่จับคู่แล้ว';
  static const matchesEmptyBody = 'เมื่ออีกฝ่ายตอบรับ คู่ของคุณจะแสดงที่นี่ (แชทกำลังจะมาเร็ว ๆ นี้)';
  static const matchDetail = 'รายละเอียดการจับคู่';
  static const meetingPoint = 'จุดนัดพบ';
  static const meetingNone = 'ยังไม่ได้กำหนดจุดนัดพบ';
  static const meetingPropose = 'เสนอจุดนัดพบ';
  static const meetingChange = 'เสนอจุดใหม่';
  static const meetingConfirm = 'ยืนยันจุดนี้';
  static const meetingWaiting = 'รออีกฝ่ายยืนยันจุดที่คุณเสนอ';
  static const meetingProposedByPartner = 'อีกฝ่ายเสนอจุดนัดพบ';
  static const meetingSaved = 'ส่งข้อเสนอจุดนัดพบแล้ว';
  static const meetingConfirmed = 'ยืนยันจุดนัดพบแล้ว';
  static const publicPlaceWarning = 'นัดพบในที่สาธารณะที่มีผู้คน และแจ้งคนที่ไว้ใจก่อนเดินทาง';
  static const cancelMatch = 'ยกเลิกการจับคู่';
  static const cancelMatchTitle = 'ยกเลิกการจับคู่?';
  static const cancelMatchBody = 'อีกฝ่ายจะรับรู้ว่าการจับคู่ถูกยกเลิก';
  static const cancelMatchKeep = 'ยังไม่ยกเลิก';
  static const matchCancelled = 'ยกเลิกการจับคู่แล้ว';

  // Profile
  static const editProfile = 'แก้ไขโปรไฟล์';
  static const profileSaved = 'บันทึกโปรไฟล์แล้ว';
  static const save = 'บันทึก';
}
