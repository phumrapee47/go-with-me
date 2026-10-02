/// Thai copy for Driver/Rider roles (design-spec R.4). One place, same
/// stop-gap as `S`/`T`/`P`. No commercial wording (no fares, fees, "hire").
abstract final class R {
  // Role picker
  static const roleGroupLabel = 'บทบาทของทริป';
  static const rolePickerTitle = 'วันนี้คุณจะ...';
  static const roleDriver = 'ฉันขับรถ';
  static const roleRider = 'ฉันขอติดรถ';
  static const roleDriverDesc = 'คุณกำลังขับรถกลับบ้าน และรับเพื่อนร่วมทางได้ 1 คน';
  static const roleRiderDesc = 'คุณอยากติดรถของคนที่กำลังไปทางเดียวกัน';
  static const roleOneOnly = 'รับเพื่อนร่วมทางได้ 1 คนเท่านั้น';
  static const roleNoMoney = 'แอปนี้ช่วยหาเพื่อนร่วมทางเท่านั้น ไม่มีการจ่ายหรือรับเงินในแอป';
  static const roleLockedNote = 'เลือกแล้วเปลี่ยนไม่ได้หลังสร้างทริป ถ้าเลือกผิด ให้ยกเลิกทริปแล้วสร้างใหม่';
  static const roleRequired = 'เลือกก่อนว่าคุณขับรถหรือขอติดรถ';
  static const roleBadgeDriver = 'คนขับ';
  static const roleBadgeRider = 'คนนั่ง';
  static const seatOne = 'รับได้ 1 คน';
  static const rowSummaryDriver = 'บทบาท: คนขับ (รับได้ 1 คน)';
  static const rowSummaryRider = 'บทบาท: คนนั่ง';
  static const legacyNoRole = 'ทริปนี้ไม่มีบทบาท จึงไม่แสดงในการค้นหา ยกเลิกแล้วสร้างใหม่ได้';
  static const createdDriver = 'สร้างทริปแล้ว กำลังหาคนนั่งที่ไปทางเดียวกัน';
  static const createdRider = 'สร้างทริปแล้ว กำลังหาคนขับที่ไปทางเดียวกัน';
  static const needsVehicle = 'ต้องมีข้อมูลรถก่อนสร้างทริปคนขับ';
  static const fillVehicle = 'กรอกข้อมูลรถ';
  static const serverRejected = 'สร้างทริปไม่สำเร็จ ตรวจสอบบทบาทและข้อมูลรถอีกครั้ง';
  static const carSublabel = 'ขับเอง หรือขอติดรถ';
  static const roleFixedRow = 'เปลี่ยนไม่ได้';
  static const nextDisabledRole = 'เลือกก่อนว่าคุณขับรถหรือขอติดรถ';
  static const backToFix = 'กลับไปแก้';
  static const legacyCancelRecreate = 'ยกเลิกทริปแล้วสร้างใหม่';
  static const matchedPairDriver = 'จับคู่แล้ว 1/1';
  static const matchedPairDriverHint = 'รับเพื่อนร่วมทางได้ 1 คน';
  static const matchedPairRider = 'จับคู่แล้ว';
  static const notMatchedRider = 'ยังไม่ได้จับคู่';
  static const roleLabel = 'บทบาท';

  // Nearby
  static const listForDriver = 'คนนั่งที่ไปทางเดียวกับคุณ';
  static const listForRider = 'คนขับที่ไปทางเดียวกับคุณ';
  static String overlapDriverView(int n) => 'ทางเดียวกัน ~$n%';
  static String overlapRiderView(int n) => 'ทางเดียวกัน ~$n%';
  static const vehicleAfterAccept = 'ข้อมูลรถจะแสดงหลังคนขับตอบรับ';
  static const emptyDriverTitle = 'ยังไม่มีคนนั่งที่ไปทางเดียวกันตอนนี้';
  static const emptyDriverBody = 'คนที่ขอติดรถจะเห็นทริปของคุณเมื่อเส้นทางตรงกัน กลับมาดูใหม่ได้นะ';
  static const emptyRiderTitle = 'ยังไม่มีคนขับที่ไปทางเดียวกันตอนนี้';
  static const emptyRiderBody = 'ลองปรับเวลาออกเดินทางให้ยืดหยุ่นขึ้น หรือกลับมาดูใหม่อีกครั้ง';
  static const matchedTitle = 'คุณมีคู่ร่วมทางแล้ว';
  static const matchedBody = 'ทริปของคุณจับคู่แล้ว จึงไม่แสดงในการค้นหา';
  static const viewMatch = 'ดูการจับคู่';
  static const viewMyTrips = 'ดูทริปของฉัน';
  static const notAvailable = 'ทริปนี้ไม่พร้อมแล้ว';

  // Requests
  static const ctaRider = 'ขอติดรถ';
  static const ctaDriver = 'ชวนขึ้นรถ';
  static const sendSheetRider =
      'คนขับจะเห็นชื่อ รูป และป้ายยืนยันของคุณ ข้อมูลรถจะเห็นหลังคนขับตอบรับ และตำแหน่งของคุณยังแสดงเป็นบริเวณกว้าง '
      'คุณส่งคำขอถึงคนขับหลายคนได้ แต่ตอบรับสำเร็จได้ 1 คน';
  static const sendSheetDriver =
      'คนนั่งจะเห็นชื่อ รูป และป้ายยืนยันของคุณ ถ้าเขาตอบรับ คุณจะรับเพื่อนร่วมทางได้ 1 คน '
      'และทริปของคุณจะหยุดปรากฏในการค้นหา';
  static const pendingCap = 'คุณมีคำขอที่รอตอบครบจำนวนสูงสุดแล้ว รอผลก่อนส่งเพิ่มนะ';
  static const acceptTitleDriver = 'ตอบรับคนนั่งคนนี้ใช่ไหม';
  static const acceptBodyDriver =
      'คุณรับเพื่อนร่วมทางได้ 1 คน หลังตอบรับ ทริปของคุณจะไม่แสดงในการค้นหา และคำขออื่นที่ค้างอยู่ทั้งหมดจะถูกปิด';
  static const acceptTitleRider = 'ขอติดรถคนขับคนนี้ใช่ไหม';
  static const acceptBodyRider = 'หลังตอบรับ คำขออื่นที่ค้างอยู่ของคุณจะถูกปิด และคุณจะเห็นข้อมูลรถของคนขับ';
  static const acceptConfirm = 'ตอบรับ';
  static const acceptBack = 'ยังไม่ตอบรับ';
  static const alreadyPaired = 'คุณมีคู่ร่วมทางแล้ว';
  static const justMatched = 'เพิ่งจับคู่';
  static const requestClosed = 'คำขอนี้ปิดแล้ว';

  // Match lifecycle
  static const cancel = 'ยกเลิกการจับคู่';
  static const cancelTitle = 'ยกเลิกการจับคู่นี้ใช่ไหม';
  static const cancelBodyDriver =
      'คนนั่งจะได้รับแจ้ง แชทจะอ่านอย่างเดียว ข้อมูลรถของคุณจะถูกซ่อนจากเขาทันที '
      'และคุณสองคนจะส่งคำขอหากันอีกไม่ได้ ทริปของคุณจะกลับไปอยู่ในการค้นหา (ถ้ายังไม่เริ่มเดินทาง)';
  static const cancelBodyRider =
      'คนขับจะได้รับแจ้ง แชทจะอ่านอย่างเดียว คุณจะไม่เห็นข้อมูลรถของคนขับอีก '
      'และคุณสองคนจะส่งคำขอหากันอีกไม่ได้ ทริปของคุณจะกลับไปอยู่ในการค้นหา (ถ้ายังไม่เริ่มเดินทาง)';
  static const cancelKeep = 'ไม่ยกเลิก';
  static const cancelDuringTripTitle = 'ยกเลิกทริประหว่างเดินทางใช่ไหม';
  static const cancelDuringTripBody = 'คนนั่งอาจยังอยู่ระหว่างเดินทางหรืออยู่ในรถของคุณ เขาจะได้รับแจ้งทันที';
  static const cancelDuringTripConfirm = 'ยืนยันยกเลิก';
  static const cancelTripWithMatchBody =
      'การจับคู่จะสิ้นสุดและอีกฝ่ายจะได้รับแจ้ง ทริปของอีกฝ่ายไม่ถูกยกเลิก';
  static const ended = 'การจับคู่นี้สิ้นสุดแล้ว';
  static const endedByMe = 'คุณยกเลิกการจับคู่แล้ว';
  static const endedBackToSearch = 'ทริปของคุณกลับมาหาเพื่อนร่วมทางแล้ว';
  static const endedDriverSide = 'การจับคู่สิ้นสุดแล้ว คุณเดินทางต่อได้ตามปกติ';
  static const endedNoShare = 'การจับคู่สิ้นสุดแล้ว ไม่มีข้อมูลคนขับให้ส่ง';
  static const driverLate = 'คนขับยังไม่เริ่มเดินทางและเลยเวลานัดแล้ว';
  static const driverStartedPrompt = 'คนขับออกเดินทางแล้ว';
  static const startMyTrip = 'เริ่มทริปของฉัน';
  static const alertTitle = 'การจับคู่นี้สิ้นสุดแล้ว ทริปของคุณยังอยู่ตามเดิม';
  static const alertSafety = 'ถ้าคุณอยู่ในรถหรือรู้สึกไม่ปลอดภัย กด SOS ได้ทันที';
  static const alertAck = 'รับทราบ';
  static const alertCancelTrip = 'ยกเลิกทริปของฉัน';
  static const alertShare = 'แชร์ทริป';
  static const alertArrived = 'ถึงแล้ว';
  static const partnerArrived = 'คนขับถึงที่หมายของเขาแล้ว ทริปของคุณยังเดินทางต่อ กด "ถึงแล้ว" เมื่อคุณถึง';
  static const tripStatusBoth = 'ทริปของคุณสองคน';
  static const partnerWaiting = 'รอออกเดินทาง';
  static const partnerMoving = 'กำลังเดินทาง';
  static const cannotCancelAfterBoarded =
      'ยกเลิกทริปไม่ได้หลังคนนั่งขึ้นรถแล้ว เมื่อถึงที่หมายให้กด "ถึงแล้ว"';
  static const cannotCancelMatchAfterBoarded = 'ยกเลิกการจับคู่ไม่ได้หลังขึ้นรถแล้ว';

  // No-show
  static const noShowButton = 'คนนั่งไม่มาตามนัด';
  static const noShowTitle = 'คนนั่งไม่มาตามนัดใช่ไหม';
  static const noShowBody =
      'การจับคู่จะสิ้นสุด แชทจะอ่านอย่างเดียว และข้อมูลรถของคุณจะถูกซ่อนจากคนนั่ง คุณเดินทางต่อและจบทริปได้ตามปกติ';
  static const noShowKeep = 'ยังก่อน';
  static const noShowConfirm = 'ยืนยัน คนนั่งไม่มา';

  // Boarding
  static const boardButton = 'ขึ้นรถแล้ว';
  static const boardDisabledDriver = 'รอคนขับเริ่มเดินทางก่อน';
  static const boardDisabledMine = 'เริ่มทริปของคุณก่อนจึงจะกด "ขึ้นรถแล้ว" ได้';
  static const boardConfirmTitle = 'ขึ้นรถแล้วใช่ไหม';
  static const boardConfirmBody =
      'เราจะหยุดแชร์ตำแหน่งของคุณให้คนขับ เพราะคุณอยู่ในรถเดียวกันแล้ว ตำแหน่งของคนขับยังแสดงให้คุณจนจบทริป';
  static const boardConfirmYes = 'ใช่ ฉันขึ้นรถแล้ว';
  static const boardConfirmNo = 'ยังไม่ขึ้น';
  // US-40 (round 6): the 2 friendly phrases owned by this file (screen-reader text without emoji: R6).
  static const driverArrivedPickup = 'คนขับมารอที่จุดรับแล้วนะ';
  static const boardSuccess = 'ขึ้นรถเรียบร้อยแล้ว 🚗';
  static String boardDone(String time) => 'ขึ้นรถแล้วเมื่อ $time';
  static const boardLocationStopped = 'หยุดแชร์ตำแหน่งของคุณให้คนขับแล้ว';
  static const boardOptionalNote = 'ไม่กดก็ไม่เป็นไร การกดช่วยให้คนขับรู้ว่าคุณขึ้นรถแล้ว';
  static const driverStatusWaiting = 'คนนั่ง: ยังไม่ขึ้นรถ';
  static const driverStatusDone = 'คนนั่ง: ขึ้นรถแล้ว';
  static const riderInCar = 'ผู้โดยสารอยู่ในรถแล้ว';
  static const boardShareNote = 'ตำแหน่งของคุณแชร์ให้คนขับจนกว่าคุณจะกด "ขึ้นรถแล้ว"';
  static const boardError = 'ยืนยันไม่สำเร็จ ลองอีกครั้ง';

  // Pickup
  static const pickupTitle = 'จุดรับ';
  static const pickupNone = 'ยังไม่ได้กำหนดจุดรับ';
  static const pickupWaitDriver = 'รอคนขับเสนอจุดรับ';
  static const pickupPropose = 'เสนอจุดรับ';
  static const pickupProposeAgain = 'เสนอจุดอื่น';
  static const pickupSend = 'ส่งข้อเสนอจุดรับ';
  static const pickupSendNew = 'เสนอจุดรับใหม่';
  static String pickupProposedByDriver(String place) => 'คนขับเสนอจุดรับ: $place';
  static String pickupProposedByRider(String place) => 'คนนั่งเสนอจุดรับใหม่: $place';
  static String pickupWaitingOther(String who, String place) => 'รอ$whoยืนยัน: $place';
  static const pickupConfirm = 'ยืนยันจุดรับนี้';
  static String pickupAgreed(String place) => 'ตกลงจุดรับแล้ว: $place';
  static const pickupOffRoute =
      'จุดนี้อยู่ห่างจากเส้นทางคนขับเกินระยะที่แนะนำ ถ้าคุณสองคนตกลงกันได้ ก็ใช้จุดนี้ต่อไปได้ '
      'หรือลองเลือกจุดที่ใกล้เส้นทางกว่านี้';
  static String pickupOffRouteM(int m) =>
      'จุดนี้ห่างจากเส้นทางคนขับประมาณ $m เมตร ถ้าคุณสองคนตกลงกันได้ ก็เสนอต่อได้ หรือลองเลือกจุดที่ใกล้เส้นทางกว่านี้';
  static const pickupOffRouteChange = 'เลือกจุดอื่น';
  static const pickupOffRouteContinue = 'เสนอจุดนี้ต่อไป';
  static const pickupOffRouteOk = 'ตกลง';
  static const pickupStartWarnTitle = 'ยังไม่ได้ตกลงจุดรับ';
  static const pickupStartWarnBody = 'นัดกับคนนั่งผ่านแชทก่อนออกเดินทางนะ';
  static const pickupOpenChat = 'เปิดแชท';
  static const pickupStartAnyway = 'เริ่มเดินทางเลย';
  static const pickupPublicNote = 'นัดพบในที่สาธารณะที่มีคนพลุกพล่านนะ';
  static const pickupSaved = 'ส่งข้อเสนอจุดรับแล้ว';
  static const pickupReadOnly = 'ทริปเริ่มแล้ว ให้นัดกันผ่านแชทแทน';
  static const pickupWhoRider = 'คนนั่ง';
  static const pickupWhoDriver = 'คนขับ';
  static const pickupScreenTitle = 'เสนอจุดรับ';
  static const pickupMatchGone = 'การจับคู่นี้ไม่พร้อมแล้ว';

  // Road-snap (US-43, G.2.4)
  static const pickupSnapping = 'กำลังปรับหมุดให้ตรงถนน…';
  static const pickupSnappedToast = 'ปรับหมุดให้ตรงถนนแล้ว';
  static const pickupSnapFallbackToast = 'ใช้ตำแหน่งที่คุณปักไว้ (ปรับให้ตรงถนนไม่ได้ตอนนี้)';
  static const pickupMarkerA11ySnapped = 'หมุด: ปรับให้ตรงถนนแล้ว';
  static const pickupMarkerA11yRaw = 'หมุด: ตำแหน่งที่ปักไว้';

  // Vehicle
  static const vehicleTitle = 'ข้อมูลรถของฉัน';
  static const vehicleEmptyTitle = 'เพิ่มข้อมูลรถของคุณ';
  static const vehicleEmptyBody =
      'ต้องมีข้อมูลรถก่อนสร้างทริปคนขับ คนนั่งที่คุณตอบรับแล้วจะเห็นข้อมูลนี้เพื่อจำรถคุณได้ถูกคัน';
  static const plate = 'ทะเบียนรถ';
  static const plateHint = 'เช่น 1กก 1234 กรุงเทพมหานคร';
  static const model = 'ยี่ห้อ/รุ่น';
  static const modelHint = 'เช่น Toyota Yaris';
  static const color = 'สี';
  static const errPlateRequired = 'กรุณากรอกทะเบียนรถ';
  static const errModelRequired = 'กรุณากรอกยี่ห้อ/รุ่น';
  static const errColorRequired = 'กรุณากรอกสีรถ';
  static const errTooLong = 'ข้อความยาวเกินไป ลดลงหน่อยนะ';
  static const privacyTitle = 'ใครเห็นข้อมูลรถนี้บ้าง';
  static const privacy1 = 'ในแอป: เฉพาะคนนั่งที่คุณตอบรับแล้วเท่านั้นที่เห็นทะเบียน รุ่น และสี';
  static const privacy2 = 'ไม่แสดงในรายการค้นหาหรือคำขอที่ยังรอตอบ และเขาจะไม่เห็นอีกเมื่อการจับคู่สิ้นสุด';
  static const privacy3 =
      'ชื่อที่แสดงของคุณจะถูกส่งไปกับการแชร์หรือ SOS ของคนนั่งที่จับคู่กับคุณเสมอ เพื่อความปลอดภัยของเขา';
  static const unverified = 'ข้อมูลรถแจ้งโดยคนขับ ยังไม่ผ่านการตรวจสอบ';
  static const shareSwitch = 'อนุญาตให้ส่งทะเบียนรถไปกับการแชร์/SOS ของคนนั่งที่จับคู่กับฉัน';
  static const shareDesc =
      'เมื่อเปิด จะมี "ทะเบียนอย่างเดียว" (ไม่มีรุ่นและสี) ถูกส่งต่อให้ผู้ติดต่อของคนนั่งผ่านข้อความ ลิงก์แชร์ และ SOS '
      'ปิดไว้ก็ได้ ไม่กระทบการสร้างทริปหรือการจับคู่ เปลี่ยนได้ทุกเมื่อ';
  static const shareOffState = 'ปิดอยู่: จะไม่มีทะเบียนของคุณในข้อความแชร์/SOS ของคนนั่ง';
  static const shareOnState = 'เปิดอยู่: ทะเบียนอย่างเดียวจะถูกส่งในข้อความแชร์/SOS ของคนนั่ง';
  static const shareWithdrawNotice =
      'ปิดแล้ว ทะเบียนจะไม่ถูกส่งในการแชร์/SOS ครั้งถัดไป และถูกตัดออกจากลิงก์แชร์ที่ยังใช้งานอยู่ทันที '
      'แต่ข้อความที่ส่งไปแล้วเรียกคืนไม่ได้';
  static const shareSaving = 'กำลังบันทึกการตั้งค่า...';
  static const shareFailed = 'เปลี่ยนการตั้งค่าไม่สำเร็จ ลองอีกครั้ง';
  static const sharePartialFailed = 'บันทึกข้อมูลรถแล้ว แต่ตั้งค่าการส่งทะเบียนไม่สำเร็จ ลองอีกครั้งที่หน้านี้';
  static const shareChangedSnack = 'คนขับเปลี่ยนการอนุญาตแล้ว ตัวอย่างข้อความอัปเดตให้ใหม่';
  static const save = 'บันทึกข้อมูลรถ';
  static const saved = 'บันทึกข้อมูลรถแล้ว';
  static const saveFailed = 'บันทึกไม่สำเร็จ ตรวจสอบข้อมูลแล้วลองอีกครั้ง';
  static const delete = 'ลบข้อมูลรถ';
  static const deleteTitle = 'ลบข้อมูลรถใช่ไหม';
  static const deleteBody = 'คุณต้องกรอกข้อมูลรถใหม่ก่อนสร้างทริปคนขับครั้งต่อไป';
  static const deleteKeep = 'ไม่ลบ';
  static const deleted = 'ลบข้อมูลรถแล้ว';
  static const deleteLocked = 'ลบไม่ได้ขณะมีเพื่อนร่วมทางที่จับคู่แล้ว หรือมีทริปคนขับที่ยังไม่จบ ยกเลิกทริปก่อน';
  static const editNotice = 'คนนั่งที่จับคู่กับคุณจะได้รับแจ้งว่าข้อมูลรถมีการเปลี่ยน';
  static const discardTitle = 'ทิ้งข้อมูลที่กรอกไว้ใช่ไหม';
  static const discardConfirm = 'ทิ้ง';
  static const discardKeep = 'กรอกต่อ';
  static const cardTitle = 'รถของคนขับ';
  static const ownerPreviewTitle = 'ข้อมูลรถของคุณที่คนนั่งจะเห็นหลังตอบรับ';
  static const vehicleEnded = 'ข้อมูลรถไม่แสดงแล้ว เพราะการจับคู่สิ้นสุด';
  static const vehicleLoadFailed = 'โหลดข้อมูลรถไม่ได้ ลองอีกครั้ง';
  static const retry = 'ลองอีกครั้ง';
  static const rowStatusNone = 'ยังไม่ได้เพิ่ม';
  static const rowStatusSet = 'กรอกแล้ว';
  static const editVehicle = 'แก้ไขข้อมูลรถ';
  static const showVehicle = 'ดูข้อมูลรถ';
  static const colorChips = ['ขาว', 'ดำ', 'เทา/เงิน', 'แดง', 'น้ำเงิน', 'อื่น ๆ'];
  static const plateShareAllowed = 'คนขับอนุญาตให้ส่งทะเบียนไปกับการแชร์/SOS ของคุณ';
  static const plateShareDenied =
      'คนขับไม่ได้อนุญาตให้ส่งทะเบียนไปกับการแชร์/SOS ของคุณ (ชื่อคนขับยังถูกส่งไปด้วย)';
  static const plateShareError = 'ยังโหลดสถานะไม่ได้ ข้อความจะมีชื่อคนขับ';
  static const vehicleUpdatedSystem = 'คนขับอัปเดตข้อมูลรถแล้ว';

  // System messages (server sends i18n keys)
  static const sysMatchCancelled = 'การจับคู่นี้สิ้นสุดแล้ว';
  static const sysBoarded = 'คนนั่งขึ้นรถแล้ว';
  static const sysPickupProposed = 'มีการเสนอจุดรับ';
  static const sysPickupConfirmed = 'ตกลงจุดรับแล้ว';

  // Share / SOS preview. PM decision: the Driver's own text carries the plate
  // only (no model/color), so the preview says so (spec copy said the full set).
  static const sharePreviewRiderWithPlate = 'ข้อความนี้จะมี: ชื่อคนขับ และทะเบียนรถ';
  static const sharePreviewRiderNoPlate = 'ข้อความนี้จะมี: ชื่อคนขับ (ไม่มีทะเบียนรถ เพราะคนขับไม่ได้อนุญาต)';
  static const sharePreviewDriver = 'ข้อความนี้จะมี: ทะเบียนรถของคุณ และชื่อคนนั่ง';
  static const sosPreviewRiderWithPlate = 'ข้อความ SOS จะมีชื่อและทะเบียนรถของคนขับ';
  static const sosPreviewRiderNoPlate = 'ข้อความ SOS จะมีชื่อคนขับ (ไม่มีทะเบียน)';
  static const sosPreviewRiderFallback = 'ข้อความ SOS จะมีชื่อคนขับ';
  static const sosPreviewDriver = 'ข้อความ SOS จะมีทะเบียนรถของคุณและชื่อคนนั่ง';
  static const textDriverLine = 'คนขับ';
  static const textPlateLine = 'ทะเบียนรถ';
  static const textRiderLine = 'คนนั่ง';

  // Live-location consent before starting a car trip (Q-8)
  static const consentSheetTitle = 'ก่อนออกเดินทาง';
  static const consentSheetBody = 'คู่ที่จับคู่แล้วเห็นตำแหน่งสดของคุณระหว่างเดินทาง';
  static const consentSheetOk = 'เข้าใจแล้ว เริ่มเดินทาง';
  static const consentSheetBack = 'ยังก่อน';

  // Local notification: neutral, no plate, name or place.
  static const notifyTitle = 'GoWithMe';
  static const notifyBody = 'การจับคู่สิ้นสุดแล้ว เปิดแอปเพื่อดูรายละเอียด';

  // Push notifications (US-42, G-1/G-2). Rendered client-side from `kind`
  // only — the server payload never carries text (design-roles 14.4/14.7).
  static const pushRationaleTitle = 'เปิดการแจ้งเตือน';
  static const pushRationaleBody =
      'ไม่พลาดคำชวน คำตอบรับ ข้อความ และตอนคนขับถึงจุดรับ แม้ปิดแอปอยู่';
  static const pushAllow = 'อนุญาตการแจ้งเตือน';
  static const pushLater = 'ไว้ทีหลัง';
  static const pushGranted = 'เปิดการแจ้งเตือนแล้ว';

  // The 5 opaque `kind`s (US-42 payload contract) -> Thai text, single source
  // of truth for both a real push tap and the in-app banner (G.1.5).
  static const pushNewRequest = 'มีคนอยากไปทางเดียวกับคุณ แตะเพื่อดูคำขอ';
  static const pushMatchAccepted = 'จับคู่กันแล้ว แตะเพื่อดูรายละเอียด';
  static const pushDriverArrived = 'คนขับถึงจุดรับแล้ว';
  static const pushMatchCancelled = 'การจับคู่นี้ถูกยกเลิกแล้ว';
  // Q2: coalesced (<=1 push/60 วิ/match) — copy is intentionally generic,
  // never quotes the message itself.
  static const pushNewMessage = 'มีข้อความใหม่จากคู่เดินทางของคุณ';
  static const pushDeepLinkGone = 'รายการนี้ไม่พร้อมแล้ว (อาจถูกถอน/หมดอายุ/ยกเลิกไปแล้ว)';

  // /me/settings/notifications (G-2 NotificationSettingsScreen)
  static const notifSettingsTitle = 'การแจ้งเตือน';
  static const notifOsOn = 'สิทธิ์ระดับเครื่อง: เปิดอยู่';
  static const notifOsOff = 'สิทธิ์ระดับเครื่อง: ปิดอยู่ — ไปเปิดในตั้งค่าเครื่อง';
  static const notifOsOpenSettings = 'ไปที่ตั้งค่าเครื่อง';
  static const notifMaster = 'รับการแจ้งเตือน';
  static const notifMasterOn = 'เปิดอยู่';
  static const notifMasterOff = 'ปิดอยู่';
  static const notifEventsListTitle = 'คุณจะได้รับแจ้งเตือนเมื่อ:';
  static const notifEventNewRequest = 'มีคำขอจับคู่ใหม่';
  static const notifEventMatchAccepted = 'มีคนตอบรับคำขอของคุณ';
  static const notifEventNewMessage = 'มีข้อความแชทใหม่';
  static const notifEventDriverArrived = 'คนขับถึงจุดรับ';
  static const notifEventCancelled = 'การจับคู่/ทริปถูกยกเลิก';
  static const notifSettingsRow = 'การแจ้งเตือน';

  // Demo hub
  static const demoRoleTitle = 'บทบาท (คนขับ/คนนั่ง)';
}
