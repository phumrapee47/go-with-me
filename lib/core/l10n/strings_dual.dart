/// Thai copy for dual role (register as driver / switch mode / tones), design-spec D.8.
/// No commercial wording and nothing that says the app checks a licence or a vehicle:
/// every string here goes through legal review before release (T8.20).
abstract final class D {
  // Mode badge + switch (role2.*)
  static const modeRider = 'โหมดคนนั่ง';
  static const modeDriver = 'โหมดคนขับ';
  static String a11yModeCurrent(String role) => 'โหมดปัจจุบัน $role';
  static const roleWordRider = 'คนนั่ง';
  static const roleWordDriver = 'คนขับ';
  static const switchToDriver = 'สลับเป็นโหมดคนขับ';
  static const switchToRider = 'สลับเป็นโหมดคนนั่ง';
  static const switchToDriverHint = 'ใช้กับทริปใหม่เท่านั้น ทริปที่มีอยู่ไม่เปลี่ยน';
  static const switching = 'กำลังสลับ...';
  static const switchedDriver = 'เปลี่ยนเป็นโหมดคนขับแล้ว ใช้กับทริปใหม่เท่านั้น ทริปที่มีอยู่ไม่เปลี่ยน';
  static const switchedRider = 'เปลี่ยนเป็นโหมดคนนั่งแล้ว ใช้กับทริปใหม่เท่านั้น ทริปที่มีอยู่ไม่เปลี่ยน';
  static String switchedActiveTrip(String mode, String tripRole) =>
      'เปลี่ยนเป็น$modeแล้ว ทริปที่มีอยู่ยังเป็นทริป$tripRoleเหมือนเดิม';
  static const switchedRiderOffline = 'เปลี่ยนเป็นโหมดคนนั่งแล้ว จะบันทึกเมื่อกลับมาออนไลน์';
  static const errSwitch = 'สลับโหมดไม่สำเร็จ ลองอีกครั้งนะ';
  static const errOfflineDriver = 'ต้องต่ออินเทอร์เน็ตก่อนถึงจะสลับเป็นโหมดคนขับได้';
  static const errNotRegistered = 'ยังสลับเป็นโหมดคนขับไม่ได้ ต้องลงทะเบียนเป็นคนขับก่อน';
  static const reconciled = 'เปลี่ยนเป็นโหมดคนนั่งให้แล้ว เพราะบัญชีนี้ไม่ได้ลงทะเบียนเป็นคนขับแล้ว';
  static const gateTitle = 'โหมดคนขับต้องลงทะเบียนก่อน';
  static const gateBody = 'ลงทะเบียนเป็นคนขับด้วยข้อมูลรถของคุณ แล้วสลับใช้โหมดคนขับได้เลย';
  static const gateCta = 'ลงทะเบียนเป็นคนขับ';
  static const gateLater = 'ไว้ก่อน';
  static const pickerLocked = 'ต้องลงทะเบียนก่อน';
  static const pickerGate = 'ต้องลงทะเบียนเป็นคนขับก่อน ถึงจะสร้างทริปแบบคนขับได้';
  static const pickerUseRider = 'ใช้แบบคนนั่งไปก่อน';
  static const pickerPrefillNote = 'ตั้งไว้ให้ตามโหมดที่คุณใช้อยู่ เปลี่ยนได้';
  static const pickerPrefillAfterSwitch = 'ตั้งตามโหมดคนขับที่คุณเพิ่งสลับ เปลี่ยนได้';
  static String pickerActiveChanged(String role) => 'โหมดที่ใช้อยู่เปลี่ยนแล้ว ทริปนี้ยังเป็น$roleตามที่เลือก';
  static String tripCreatingAs(String role) => 'ทริปนี้: $role';
  static String confirmRow(String role) => 'บทบาทของทริปนี้: $role';
  static const confirmRowNote = 'เลือกแล้วเปลี่ยนไม่ได้หลังสร้างทริป';
  static String tripctxSearchingDriver(String time) => 'กำลังหาคนขับ สำหรับทริป $time';
  static String tripctxSearchingRider(String time) => 'กำลังหาคนนั่ง สำหรับทริป $time';
  static const roleStripUnknown = 'กำลังตรวจสอบโหมด...';

  // Me tab
  static const rolesTitle = 'บทบาทของฉัน';
  static const roleChipRider = 'คนนั่ง';
  static const roleChipDriver = 'คนขับ';
  static const driverCardTitle = 'มีรถ? ลงทะเบียนเป็นเจ้าของทริป';
  static const driverCardBody = 'เปิดทริปแบบคนขับ รับเพื่อนร่วมทางได้ 1 คน';
  static const driverCardCta = 'ลงทะเบียนเป็นคนขับ';
  static const driverCardNote = 'แจ้งด้วยตัวเอง ยังไม่ผ่านการตรวจสอบ';
  static const driverCardPrefill = 'เติมข้อมูลรถเดิมให้แล้ว ตรวจและรับรองใหม่ได้เลย';
  static const driverCardError = 'ตรวจสถานะไม่ได้ ลองอีกครั้ง';
  static const unregisterRow = 'ยกเลิกการลงทะเบียนคนขับ';
  static const profileRoleRiderOnly = 'บทบาท: คนนั่ง';
  static const profileRoleBoth = 'บทบาท: คนนั่ง และ คนขับ';

  // Registration page
  static const regTitle = 'ลงทะเบียนเป็นคนขับ';
  static const notice1 = 'เป็นการแจ้งด้วยตัวเอง ยังไม่ผ่านการตรวจสอบ';
  static const notice2 = 'เปิดทริปแบบคนขับรับเพื่อนร่วมทางได้ 1 คน';
  static const notice3 = 'ไม่มีการจ่ายหรือรับเงินในแอป';
  static const sectionVehicle = 'ข้อมูลรถของคุณ';
  static const prefillBanner = 'เติมข้อมูลรถเดิมให้แล้ว ตรวจและแก้ไขได้ ต้องรับรองใบขับขี่ใหม่อีกครั้ง';
  static const decl = 'ฉันรับรองว่าฉันมีใบขับขี่ที่ยังไม่หมดอายุและใช้ขับรถได้ตามกฎหมาย';
  static const declNote =
      'เป็นการรับรองด้วยตัวเอง แอปไม่ตรวจสอบใบขับขี่ และไม่เก็บเลขที่หรือรูปใบขับขี่ เก็บเฉพาะว่าคุณรับรองแล้วและเวลาที่รับรอง';
  static const consentHint = 'ตั้งค่าการส่งทะเบียนรถไปกับการแชร์ได้ภายหลังที่ ข้อมูลรถของฉัน (ปิดอยู่ตั้งแต่ต้น)';
  static const regCta = 'ลงทะเบียนเป็นคนขับ';
  static const ctaDisabledReason = 'กรอกข้อมูลรถให้ครบและติ๊กรับรองก่อน';
  static const submitting = 'กำลังลงทะเบียน...';
  static const errDeclRequired = 'ติ๊กรับรองก่อนถึงจะลงทะเบียนได้';
  static const errNetwork = 'ลงทะเบียนไม่สำเร็จ ตรวจอินเทอร์เน็ตแล้วลองอีกครั้ง ข้อมูลที่กรอกยังอยู่';
  static const errServer = 'ลงทะเบียนไม่สำเร็จ ลองอีกครั้งในอีกสักครู่';
  static const errOffline = 'ต้องต่ออินเทอร์เน็ตก่อนถึงจะลงทะเบียนได้';
  static const errDeclStale = 'ข้อความรับรองมีการอัปเดต กรุณาอัปเดตแอปแล้วลองอีกครั้ง';
  static const already = 'คุณลงทะเบียนเป็นคนขับไว้แล้ว';
  static const discardTitle = 'ออกโดยไม่ลงทะเบียน?';
  static const discardBody = 'ข้อมูลที่กรอกไว้จะไม่ถูกบันทึก';
  static const discardStay = 'กรอกต่อ';
  static const discardLeave = 'ออกจากหน้านี้';
  static const successTitle = 'ลงทะเบียนเป็นคนขับแล้ว';
  static const successBody = 'ตอนนี้คุณเป็นทั้งคนนั่งและคนขับ';
  static const successSwitch = 'สลับเป็นโหมดคนขับ';
  static const successLater = 'ไว้ทีหลัง';
  static const successReturnTrip = 'แล้วกลับไปสร้างทริปต่อ';
  static const successSwitchFailed = 'ลงทะเบียนแล้ว สลับใช้โหมดคนขับได้ภายหลังจากแถบบน';

  // Unregister
  static const unregTitle = 'ยกเลิกการลงทะเบียนคนขับ?';
  static const unregItem1 = 'คุณจะกลับเป็นโหมดคนนั่งทันที';
  static const unregItem2 = 'สร้างทริปแบบคนขับไม่ได้ จนกว่าจะลงทะเบียนและรับรองใบขับขี่ใหม่อีกครั้ง';
  static const unregItem3 = 'ประวัติทริปเดิมยังอยู่';
  static const unregItem4 = 'ข้อมูลรถยังเก็บไว้ เห็นได้เฉพาะคุณ ลบได้ที่ ข้อมูลรถของฉัน';
  static const unregStay = 'ไม่ยกเลิก';
  static const unregConfirm = 'ยกเลิกการลงทะเบียน';
  static const unregDone = 'ยกเลิกการลงทะเบียนคนขับแล้ว ตอนนี้คุณอยู่โหมดคนนั่ง';
  static const unregErrNetwork = 'ยกเลิกไม่สำเร็จ ตรวจอินเทอร์เน็ตแล้วลองอีกครั้ง';
  static const unregRetry = 'ลองอีกครั้ง';
  static const blockedTitle = 'ยังยกเลิกการลงทะเบียนไม่ได้';
  static const blockedTrip = 'ยังมีทริปคนขับที่ยังไม่จบ ยกเลิกหรือจบทริปนั้นก่อน แล้วค่อยยกเลิกการลงทะเบียน';
  static const blockedMatch = 'ยังมีการจับคู่ที่ตอบรับแล้ว ยกเลิกการจับคู่นั้นก่อน แล้วค่อยยกเลิกการลงทะเบียน';
  static const blockedCta = 'ไปที่ทริปของฉัน';
  static const blockedClose = 'ปิด';

  // Vehicle after unregistering / delete
  static const vehicleRetainedNote = 'ข้อมูลรถนี้เห็นได้เฉพาะคุณ และยังไม่ถูกใช้ในการแชร์หรือจับคู่';
  static const vehicleReregisterCta = 'ลงทะเบียนเป็นคนขับอีกครั้ง';
  static const vehicleDeleteBlockedRegistered = 'ลบข้อมูลรถไม่ได้ขณะยังลงทะเบียนเป็นคนขับ ยกเลิกการลงทะเบียนก่อน';
  static const vehicleDeleteBlockedCta = 'ยกเลิกการลงทะเบียนคนขับ';
  static const errTripDriverNotRegistered = 'สร้างทริปแบบคนขับไม่ได้ ต้องลงทะเบียนเป็นคนขับก่อน';
}
