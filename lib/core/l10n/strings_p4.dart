/// Thai copy for Phase 4 (chat, trip lifecycle, safety, privacy).
/// Same stop-gap as `S`/`T`: one place, migrate to ARB later.
abstract final class P {
  // Chat
  static const chatHint = 'พิมพ์ข้อความ';
  static const chatSend = 'ส่ง';
  static const chatEmpty = 'ทักทายกันเลย และนัดจุดพบ';
  static const chatNotice = 'แชทนี้ใช้เพื่อนัดหมายการเดินทางเท่านั้น';
  static const chatSendFailed = 'ส่งไม่สำเร็จ แตะเพื่อส่งซ้ำ';
  static const chatSending = 'กำลังส่ง';
  static const chatLimit = 'ข้อความยาวได้ไม่เกิน 1,000 ตัวอักษร';
  static const chatThrottled = 'ส่งเร็วเกินไป รอสักครู่แล้วส่งใหม่';
  static const chatLoadOlder = 'ดูข้อความก่อนหน้า';
  static const chatReadOnlyTripEnded = 'ห้องแชทนี้อ่านอย่างเดียว เพราะทริปจบแล้ว';
  static const chatReadOnlyBlocked = 'ห้องแชทนี้อ่านอย่างเดียว เพราะมีการบล็อกในคู่นี้';
  static const chatReadOnlyClosed = 'ห้องแชทนี้อ่านอย่างเดียว เพราะการจับคู่ปิดแล้ว';
  static const chatMenuReport = 'รายงานผู้ใช้';
  static const chatMenuBlock = 'บล็อกผู้ใช้';
  static const chatBlockTitle = 'บล็อกผู้ใช้นี้?';
  static const chatBlockBody =
      'แชทจะเป็นอ่านอย่างเดียวทันทีทั้งสองฝ่าย และเราจะหยุดแชร์ตำแหน่งสดกับคนนี้ '
      'การจับคู่ยังอยู่จนกว่าคุณจะกดยกเลิกการจับคู่เอง';
  static const chatBlockConfirm = 'บล็อก';
  static const chatBlockKeep = 'ไม่บล็อก';
  static const chatBlocked = 'บล็อกแล้ว';
  static const chatSos = 'ปุ่มขอความช่วยเหลือ SOS';
  static const unreadDot = 'มีข้อความใหม่';
  static const sysTripCompleted = 'ทริปเสร็จสิ้นแล้ว';
  static const sysTripCancelled = 'ทริปถูกยกเลิก';
  static const sysTripExpired = 'ทริปหมดอายุ';
  static const sysGeneric = 'ข้อความจากระบบ';
  static const chatsEmpty = 'ยังไม่มีแชท';
  static const chatsEmptyBody = 'เมื่อมีคนตอบรับ คุณจะคุยกันได้ที่นี่';
  static const chatsTitle = 'แชท';
  static const noMessagesYet = 'ยังไม่มีข้อความ';

  // Report / block
  static const reportTitle = 'รายงานผู้ใช้';
  static const reportReason = 'เหตุผล';
  static const reportDetails = 'รายละเอียด (ไม่บังคับ)';
  static const reportAlsoBlock = 'บล็อกผู้ใช้นี้ด้วย';
  static const reportSubmit = 'ส่งรายงาน';
  static const reportThanks = 'ขอบคุณที่แจ้ง เราจะตรวจสอบต่อไป';
  static const reasonHarassment = 'รบกวนหรือคุกคาม';
  static const reasonFake = 'ข้อมูลไม่จริง';
  static const reasonUnsafe = 'พฤติกรรมไม่ปลอดภัย';
  static const reasonSpam = 'สแปม';
  static const reasonOther = 'อื่น ๆ';
  static const blockedTitle = 'ผู้ใช้ที่ถูกบล็อก';
  static const blockedEmpty = 'ยังไม่ได้บล็อกใคร';
  static const blockedUnknownName = 'ผู้ใช้ที่ถูกบล็อก';
  static const unblock = 'เลิกบล็อก';
  static const unblockTitle = 'เลิกบล็อกผู้ใช้นี้?';
  static const unblockBody = 'เขาจะกลับมาปรากฏในผลจับคู่ได้อีก';
  static const unblockDone = 'เลิกบล็อกแล้ว';

  // My trips
  static const segCurrent = 'ปัจจุบัน';
  static const segHistory = 'ประวัติ';
  static const tripsEmptyCurrent = 'ยังไม่มีทริป';
  static const tripsEmptyCurrentBody = 'เริ่มต้นสร้างทริปแรกของคุณ';
  static const tripsEmptyHistory = 'ยังไม่มีประวัติทริป';
  static const tripsEmptyHistoryBody = 'ทริปที่จบหรือยกเลิกแล้วจะอยู่ที่นี่';
  static const createTripFab = 'สร้างทริป';
  static const createTripDisabled = 'จบหรือยกเลิกทริปเดิมก่อนจึงจะสร้างทริปใหม่ได้';
  static const statusScheduled = 'รอออกเดินทาง';
  static const statusInProgress = 'กำลังเดินทาง';
  static const statusCompleted = 'เสร็จสิ้น';
  static const statusCancelled = 'ยกเลิก';
  static const statusExpired = 'หมดอายุ';
  static const matchedCount = 'จับคู่แล้ว %s/3';
  static const tripDetail = 'รายละเอียดทริป';
  static const tripFrom = 'จาก';
  static const tripTo = 'ไป';
  static const tripPartners = 'คู่ที่จับคู่แล้ว';
  static const tripNoPartners = 'ยังไม่มีคู่ที่จับคู่แล้ว';
  static const startTrip = 'เริ่มเดินทาง';
  static const cancelTrip = 'ยกเลิกทริป';
  static const goActive = 'ไปหน้าทริป';
  static const deleteTrip = 'ลบทริป';
  static const recreateTrip = 'สร้างทริปใหม่ด้วยข้อมูลเดิม';
  static const cancelTripTitle = 'ยกเลิกทริปนี้?';
  static const cancelTripBodyNoPartner = 'ทริปจะถูกยกเลิกและคำขอที่ค้างอยู่จะถูกปิด';
  static const cancelTripBodyPartner = 'คู่ของคุณ %s คนจะได้รับข้อความแจ้งว่าทริปถูกยกเลิก';
  static const cancelTripKeep = 'ไม่ยกเลิก';
  static const tripCancelled = 'ยกเลิกทริปแล้ว';
  static const tripStarted = 'เริ่มเดินทางแล้ว';
  static const deleteTripTitle = 'ลบทริปนี้?';
  static const deleteTripBody = 'ทริปจะถูกลบออกจากประวัติของคุณ ย้อนกลับไม่ได้';
  static const deleteTripKeep = 'ไม่ลบ';
  static const tripDeleted = 'ลบทริปแล้ว';
  static const tripNotFound = 'ไม่พบทริปนี้';

  // Start trip prompts
  static const noContactsTitle = 'ยังไม่ได้ตั้งผู้ติดต่อฉุกเฉิน';
  static const noContactsBody =
      'ตั้งผู้ติดต่อไว้ล่วงหน้า เพื่อให้ปุ่ม SOS ส่งตำแหน่งหาคนที่คุณไว้ใจได้ทันที ข้ามไปก่อนก็ได้';
  static const noContactsSetup = 'ตั้งค่าตอนนี้';
  static const noContactsSkip = 'ข้ามไปก่อน เริ่มเดินทาง';
  static const noContactsCard = 'ตั้งผู้ติดต่อฉุกเฉินไว้ เผื่อต้องขอความช่วยเหลือ';

  // Active trip
  static const activeTitle = 'กำลังเดินทาง';
  static const arrived = 'ถึงแล้ว';
  static const arrivedConfirmTitle = 'ถึงแล้วใช่ไหม?';
  static const arrivedConfirmBody = 'เราจะจบทริปและหยุดแชร์ตำแหน่งของคุณ';
  static const arrivedConfirmYes = 'ใช่ ฉันถึงแล้ว';
  static const arrivedConfirmNo = 'ยังไม่ถึง';
  static const arrivalNear = 'ใกล้ถึงแล้ว ถึงบ้านแล้วหรือยัง?';
  static const arrivalOverdue = 'เลยเวลาที่คาดไว้แล้ว ถึงแล้วหรือยัง?';
  static const arrivalDismiss = 'ยังไม่ถึง';
  static const trackingNote = 'แชร์ตำแหน่งขณะเดินทางเท่านั้น จะหยุดเมื่อคุณถึงแล้ว';
  static const trackingSharing = 'กำลังแชร์ตำแหน่งกับคู่ร่วมทาง';
  static const trackingNoPartner = 'ยังไม่มีคู่ร่วมทาง จึงไม่มีการส่งตำแหน่งสดให้ใคร';
  static const gpsSearching = 'กำลังหาตำแหน่งของคุณ...';
  static const gpsDenied = 'ยังไม่ได้อนุญาตตำแหน่ง แต่คุณยังกด "ถึงแล้ว" และ SOS ได้';
  static const shareTripButton = 'แชร์ทริป';
  static const partnerHere = 'ตำแหน่งของคู่ร่วมทาง';
  static const partnerNoLocation = 'ยังไม่เห็นตำแหน่งของคู่ (ต้องเดินทางพร้อมกันและยังไม่ใกล้ปลายทาง)';
  static const partnerUpdated = 'อัปเดตล่าสุด %s';
  static const openChat = 'แชท';
  static const etaRemaining = 'เหลือประมาณ %s';
  static const arrivedTitle = 'ถึงแล้ว! ขอให้พักผ่อนนะ';
  static const arrivedBody = 'การแชร์ตำแหน่งหยุดแล้ว เราแจ้งคู่ร่วมทางให้แล้ว';
  static const backHome = 'กลับหน้าหลัก';
  static const arriveFailed = 'ยืนยันไม่สำเร็จ ทริปยังเป็นกำลังเดินทาง ลองใหม่อีกครั้ง';

  // SOS
  static const sos = 'SOS';
  static const sosTitle = 'ต้องการความช่วยเหลือใช่ไหม';
  static const sosDanger = 'ถ้าอยู่ในอันตราย โทร 191 ทันที';
  static const sosHold = 'กดค้างเพื่อขอความช่วยเหลือ';
  static const sosRelease = 'ปล่อยเพื่อยกเลิก';
  static const sosTapConfirm = 'ยืนยันขอความช่วยเหลือ';
  static const sosCancel = 'ยกเลิก';
  static const sosCall191 = 'โทร 191 ตำรวจ';
  static const sosCall1669 = 'โทร 1669 การแพทย์ฉุกเฉิน';
  static const sosShareContacts = 'ส่งตำแหน่งให้ผู้ติดต่อฉุกเฉิน';
  static const sosSetupContacts = 'ยังไม่ได้ตั้งผู้ติดต่อฉุกเฉิน ตั้งค่าตอนนี้';
  static const sosSaving = 'กำลังบันทึกเหตุการณ์...';
  static const sosSaved = 'บันทึกเหตุการณ์แล้ว';
  static const sosQueued = 'บันทึกเหตุการณ์ไว้ในเครื่องแล้ว จะส่งให้เมื่อกลับมาออนไลน์';
  static const sosLocating = 'กำลังหาตำแหน่ง...';
  static const sosNoLocation =
      'หาตำแหน่งไม่ได้ ข้อความจะส่งโดยไม่มีลิงก์ตำแหน่ง แต่คุณยังโทรขอความช่วยเหลือได้';
  static const sosSmsContact = 'ส่ง SMS ถึง %s';
  static const sosContactsHeader = 'ผู้ติดต่อฉุกเฉินของคุณ';
  static const sosCallFailed = 'เปิดหน้าโทรไม่ได้ในเครื่องนี้ โปรดโทร 191 หรือ 1669 ด้วยตัวเอง';
  static const sosDone = 'ส่งสัญญาณขอความช่วยเหลือแล้ว';
  static const sosHoldProgress = 'กำลังกดค้าง...';

  // Emergency contacts
  static const contactsTitle = 'ผู้ติดต่อฉุกเฉิน';
  static const contactsEmpty = 'ยังไม่มีผู้ติดต่อฉุกเฉิน';
  static const contactsEmptyBody =
      'แนะนำให้เพิ่มอย่างน้อย 1 ราย (ไม่บังคับ) เพื่อให้ SOS ส่งตำแหน่งถึงคนที่คุณไว้ใจ';
  static const contactsAdd = 'เพิ่มผู้ติดต่อ';
  static const contactsMax = 'เพิ่มได้สูงสุด 3 ราย ลบรายเดิมก่อนจึงจะเพิ่มได้';
  static const contactsCount = '%s/3 ราย';
  static const contactName = 'ชื่อ';
  static const contactPhone = 'เบอร์โทร';
  static const contactSave = 'บันทึก';
  static const contactEdit = 'แก้ไขผู้ติดต่อ';
  static const contactNew = 'เพิ่มผู้ติดต่อฉุกเฉิน';
  static const errContactName = 'กรอกชื่อ (ไม่เกิน 60 ตัวอักษร)';
  static const errContactPhone = 'เบอร์โทรไม่ถูกต้อง (ตัวเลข 8-15 หลัก ขึ้นต้นด้วย + ได้)';
  static const errContactDuplicate = 'เบอร์นี้มีในรายชื่อแล้ว';
  static const contactDeleteTitle = 'ลบผู้ติดต่อนี้?';
  static const contactDeleteBody = 'จะลบ %s ออกจากผู้ติดต่อฉุกเฉิน';
  static const contactDeleteLastBody =
      'นี่คือผู้ติดต่อรายสุดท้ายของคุณ หลังลบ SOS จะไม่ส่งข้อความหาใคร (ยังโทร 191 และ 1669 ได้เหมือนเดิม)';
  static const contactDeleteKeep = 'เก็บไว้';
  static const contactDelete = 'ลบ';
  static const contactSaved = 'บันทึกแล้ว';
  static const contactDeleted = 'ลบแล้ว';

  // Safety hub
  static const safetyTitle = 'ความปลอดภัย';
  static const emergencyNumbers = 'เบอร์ฉุกเฉิน';
  static const activeShares = 'ลิงก์แชร์ที่ใช้งานอยู่';
  static const noShares = 'ยังไม่มีการแชร์ทริปแบบลิงก์';
  static const safetyTips = 'คำแนะนำความปลอดภัย';
  static const tip1 = 'นัดพบในที่สาธารณะที่มีคนพลุกพล่าน';
  static const tip2 = 'แชร์ทริปให้คนที่ไว้ใจก่อนออกเดินทาง';
  static const tip3 = 'ไม่ให้ข้อมูลส่วนตัวเกินจำเป็น เช่น ที่อยู่บ้านหรือที่ทำงาน';
  static const tip4 = 'กด SOS ได้ทุกเมื่อ ถ้าอยู่ในอันตรายให้โทร 191 ทันที';
  static const safetyShield = 'ความปลอดภัย';

  // Share trip
  static const shareTitle = 'แชร์ทริปให้คนที่ไว้ใจ';
  static const shareIntro = 'เพื่อให้คนที่ห่วงคุณรู้ว่าคุณอยู่ที่ไหน';
  static const shareWillShare = 'สิ่งที่จะแชร์';
  static const shareWillShareBody =
      'ชื่อของคุณ, สถานะทริป, ปลายทางโดยประมาณ, เวลาที่คาดว่าจะถึง, ตำแหน่งล่าสุด (ถ้ามี)';
  static const shareWontShare = 'ไม่แชร์: อีเมล เบอร์โทร และข้อความแชทของคุณ';
  static const shareSend = 'ส่งให้คนที่ไว้ใจ';
  static const shareSnapshotWarning =
      'ข้อความที่ส่งไปแล้วเรียกคืนไม่ได้ เพราะเป็นข้อความที่คนรับได้รับไปเลย (ไม่ใช่ลิงก์สด)';
  static const shareLinkWarning = 'ใครก็ตามที่ได้รับลิงก์นี้จะเห็นข้อมูลที่แชร์ จนกว่าคุณจะหยุดแชร์';
  static const shareActive = 'กำลังแชร์ทริปกับคนที่คุณไว้ใจ';
  static const shareStop = 'หยุดแชร์';
  static const shareStopped = 'หยุดแชร์แล้ว';
  static const shareStopTitle = 'หยุดแชร์ลิงก์นี้?';
  static const shareStopBody = 'คนที่มีลิงก์จะเปิดดูไม่ได้อีก ข้อความที่ส่งไปแล้วยังอยู่กับผู้รับ';
  static const shareStopKeep = 'แชร์ต่อ';
  static const shareSentSnapshot = 'ส่งข้อความสรุปทริปแล้ว (เรียกคืนไม่ได้)';
  static const shareFailed = 'สร้างลิงก์ไม่สำเร็จ ลองใหม่';
  static const shareUnavailable = 'เปิดหน้าแชร์ของเครื่องนี้ไม่ได้';
  static const shareExpires = 'หมดอายุ %s';

  // Settings / privacy / account
  static const settingsTitle = 'ตั้งค่า';
  static const settingsPrivacy = 'ความเป็นส่วนตัวและตำแหน่ง';
  static const settingsCredit = 'แผนที่: © OpenStreetMap contributors';
  static const settingsLanguage = 'ภาษา: ไทย (ภาษาอื่นเร็ว ๆ นี้)';
  static const privacyTitle = 'ความเป็นส่วนตัว';
  static const locationSwitch = 'อนุญาตให้ใช้ตำแหน่ง';
  static const locationSwitchOffTitle = 'ปิดการใช้ตำแหน่ง?';
  static const locationSwitchOffBody =
      'เราจะหยุดแชร์ตำแหน่งสดและไม่ใช้ตำแหน่งปัจจุบัน ส่วนที่ไม่ใช้ตำแหน่งยังใช้ได้ '
      'การสร้างทริปต้องค้นหาหรือปักหมุดเอง เปิดใหม่ได้ทุกเมื่อ';
  static const locationSwitchOffConfirm = 'ปิดการใช้ตำแหน่ง';
  static const locationSwitchOffKeep = 'ไม่ปิด';
  static const locationNote =
      'ใช้เพื่อหาเส้นทางและจับคู่คนทางเดียวกัน แชร์ตำแหน่งสดเฉพาะขณะที่ทริปกำลังเดินทาง และเมื่อคุณกด SOS เท่านั้น';
  static const consentUpdated = 'บันทึกความยินยอมแล้ว';
  static const exportData = 'ส่งออกข้อมูลของฉัน';
  static const exportPreparing = 'กำลังเตรียมข้อมูล...';
  static const exportReady = 'ข้อมูลของคุณพร้อมแล้ว';
  static const exportNote =
      'ตอนนี้ส่งออกเป็นข้อความ JSON ผ่านหน้าแชร์ของเครื่อง (ฟีเจอร์ครบชุดจะมาในภายหลัง)';
  static const exportShare = 'แชร์/บันทึกข้อมูล';
  static const viewPolicy = 'อ่านนโยบายความเป็นส่วนตัว';
  static const viewTerms = 'อ่านข้อกำหนดการใช้งาน';
  static const deleteAccountRow = 'ลบบัญชีของฉัน';
  static const deleteTitle = 'ลบบัญชีของฉัน';
  static const deleteWhat =
      'สิ่งที่จะเกิดขึ้น: ทริปที่ใช้งานอยู่จะถูกยกเลิก, การจับคู่ที่ค้างอยู่จะถูกปิด, '
      'ผู้ติดต่อฉุกเฉินและตำแหน่งสดจะถูกลบ, ชื่อและรูปของคุณจะถูกทำให้ไม่ระบุตัวตน';
  static const deleteNote = 'ข้อมูลส่วนบุคคลและตำแหน่งของคุณจะถูกลบหรือทำให้ไม่ระบุตัวตนภายใน 30 วัน';
  static const deleteIrreversible = 'ย้อนกลับไม่ได้ และคุณจะถูกออกจากระบบทันที';
  static const deletePhrase = 'ลบบัญชี';
  static const deleteTypeHint = 'พิมพ์ "ลบบัญชี" เพื่อยืนยัน';
  static const deleteButton = 'ลบบัญชีของฉัน';
  static const deleteConfirmTitle = 'ลบบัญชีถาวรใช่ไหม?';
  static const deleteConfirmBody = 'ย้อนกลับไม่ได้ คุณจะถูกออกจากระบบทันที';
  static const deleteConfirmKeep = 'ไม่ลบ';
  static const deleteConfirmYes = 'ลบถาวร';
  static const meSafety = 'ความปลอดภัย';
  static const meContacts = 'ผู้ติดต่อฉุกเฉิน';
  static const meSettings = 'ตั้งค่า';
  static const meBlocked = 'ผู้ใช้ที่ถูกบล็อก';
  static const bannerActiveTrip = 'ทริปกำลังเดินทาง - แตะเพื่อกลับไปหน้าทริป';
  static const consentGranted = 'ให้ความยินยอมแล้ว';
  static const consentNotGranted = 'ยังไม่ได้ให้ความยินยอม';
  static const policyVersionLabel = 'เวอร์ชันนโยบาย';
}
