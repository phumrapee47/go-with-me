/// Thai UI copy in one place (T1.8 stop-gap; migrate to ARB with gen-l10n
/// when a second locale is needed).
abstract final class S {
  // Common
  static const retry = 'ลองอีกครั้ง';
  static const cancel = 'ยกเลิก';
  static const loading = 'กำลังดำเนินการ...';
  static const next = 'ถัดไป';
  static const skip = 'ข้าม';
  static const back = 'ย้อนกลับ';
  static const comingSoon = 'ฟีเจอร์นี้กำลังจะมาเร็ว ๆ นี้';

  // Config error (S-02)
  static const configErrorTitle = 'ยังไม่ได้ตั้งค่าการเชื่อมต่อเซิร์ฟเวอร์';
  static const configErrorBody =
      'ตั้งค่า SUPABASE_URL และ SUPABASE_ANON_KEY ตามคู่มือใน README แล้วเปิดแอปใหม่';
  static const configInvalidUrl = 'SUPABASE_URL ไม่ถูกต้อง ตรวจสอบรูปแบบแล้วเปิดแอปใหม่';
  static const configInsecureUrl = 'SUPABASE_URL ต้องขึ้นต้นด้วย https:// เท่านั้น';
  static const configNotAnon =
      'คีย์ที่ตั้งไว้ไม่ใช่ anon/publishable key แอปจึงปฏิเสธการเริ่มทำงานเพื่อความปลอดภัย';
  static const configInvalidKey = 'SUPABASE_ANON_KEY มีรูปแบบไม่ถูกต้อง';
  static const configInitFailed = 'เริ่มการเชื่อมต่อเซิร์ฟเวอร์ไม่สำเร็จ ตรวจสอบค่าที่ตั้งไว้แล้วเปิดแอปใหม่';

  // Onboarding (S-03)
  static const onboardStart = 'เริ่มต้นใช้งาน';
  static const onboard1Title = 'เจอคนทางเดียวกัน';
  static const onboard1Body =
      'บอกว่าจะกลับไหน เมื่อไหร่ เราช่วยหาคนที่ไปทางเดียวกัน ไม่ต้องกลับคนเดียว';
  static const onboard2Title = 'กลับบ้านอย่างอุ่นใจ';
  static const onboard2Body =
      'ยืนยันตัวตนหลายระดับ ปุ่ม SOS แชร์ทริปให้คนที่ไว้ใจ และยืนยันเมื่อถึงบ้าน';
  static const onboard3Title = 'ตำแหน่งของคุณ คุณควบคุมเอง';
  static const onboard3Body =
      'คนอื่นเห็นแค่บริเวณกว้างจนกว่าคุณจะยอมรับการจับคู่ และเราไม่ติดตามคุณนอกเวลาเดินทาง';

  // Auth
  static const signIn = 'เข้าสู่ระบบ';
  static const signUp = 'สมัครสมาชิก';
  static const signOut = 'ออกจากระบบ';
  static const email = 'อีเมล';
  static const password = 'รหัสผ่าน';
  static const displayName = 'ชื่อที่แสดง';
  static const noAccount = 'ยังไม่มีบัญชี? สมัครสมาชิก';
  static const haveAccount = 'มีบัญชีแล้ว? เข้าสู่ระบบ';
  static const passwordHint = 'อย่างน้อย 8 ตัวอักษร';
  static const errEmail = 'รูปแบบอีเมลไม่ถูกต้อง';
  static const errPasswordShort = 'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร';
  static const errPasswordEmpty = 'กรุณากรอกรหัสผ่าน';
  static const errName = 'กรุณากรอกชื่อที่แสดง';
  static const errConsent = 'กรุณายอมรับนโยบายความเป็นส่วนตัวและข้อกำหนดการใช้งาน';
  static const errAdult = 'ต้องยืนยันว่าอายุ 18 ปีขึ้นไปจึงจะใช้งานได้';
  static const adultLabel = 'ฉันอายุ 18 ปีขึ้นไป';
  static const consentPrefix = 'ฉันยอมรับ';
  static const policy = 'นโยบายความเป็นส่วนตัว';
  static const terms = 'ข้อกำหนดการใช้งาน';
  static const and = 'และ';
  static const signUpNetworkError = 'สมัครไม่สำเร็จ ตรวจสอบอินเทอร์เน็ตแล้วลองใหม่';
  static const signInNetworkError = 'เข้าสู่ระบบไม่สำเร็จ ตรวจสอบอินเทอร์เน็ตแล้วลองใหม่';

  // Verify email (T4.28)
  static const verifyTitle = 'ตรวจอีเมลเพื่อยืนยันบัญชี';
  static const verifyBody =
      'เราส่งลิงก์ยืนยันไปที่อีเมลของคุณแล้ว กดลิงก์ในอีเมลเพื่อยืนยัน จากนั้นกลับมาเข้าสู่ระบบ';
  static const verifyResend = 'ส่งอีเมลยืนยันอีกครั้ง';
  static const verifyResent = 'ส่งอีเมลยืนยันแล้ว';
  static const verifyGoSignIn = 'ยืนยันแล้ว เข้าสู่ระบบ';
  static const verifyHintSpam = 'ไม่เจออีเมล? ลองดูในโฟลเดอร์สแปม';

  // Profile setup (S-08)
  static const setupTitle = 'ตั้งค่าโปรไฟล์';
  static const setupDone = 'เสร็จสิ้น';
  static const setupLater = 'ไว้ทีหลัง';
  static const setupContacts = 'ผู้ติดต่อฉุกเฉิน';
  static const setupContactsBody =
      'ใช้เมื่อคุณกด SOS เท่านั้น เพิ่มได้ภายหลังในหน้า "ฉัน" (กำลังจะมาเร็ว ๆ นี้)';

  // Shell
  static const tabHome = 'หน้าหลัก';
  static const tabNearby = 'ใกล้ฉัน';
  static const tabChats = 'แชท';
  static const tabTrips = 'ทริปของฉัน';
  static const tabMe = 'ฉัน';
  static const homeGreeting = 'กลับบ้านวันนี้ไปกับใครดี?';
  static const homeEmptyTitle = 'ยังไม่มีทริป';
  static const homeEmptyBody = 'สร้างทริปเมื่อพร้อมกลับบ้าน แล้วเราจะช่วยหาคนทางเดียวกัน';
  static const nearbyTitle = 'คนที่กำลังกลับใกล้ฉัน';
  static const nearbyEmptyBody = 'สร้างทริปก่อน แล้วเราจะแสดงคนที่ไปทางเดียวกัน';
  static const chatsEmptyTitle = 'ยังไม่มีแชท';
  static const chatsEmptyBody = 'แชทจะเปิดหลังจากคุณจับคู่กับใครสักคน';
  static const tripsEmptyTitle = 'ยังไม่มีทริป';
  static const tripsEmptyBody = 'ทริปของคุณจะแสดงที่นี่';
  static const signOutTitle = 'ออกจากระบบ?';
  static const signOutBody = 'คุณต้องเข้าสู่ระบบใหม่เพื่อใช้งานต่อ';
  static const signOutStay = 'ยังไม่ออก';

  // Policy
  static const draftNotice = 'ข้อความตัวอย่าง อยู่ระหว่างทบทวนโดยฝ่ายกฎหมาย';
}
