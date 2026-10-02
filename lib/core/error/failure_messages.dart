import '../l10n/strings_dual.dart';
import '../l10n/strings_r5.dart';
import '../l10n/strings_roles.dart';
import 'app_failure.dart';

/// Thai user-facing text per failure code. Server `message` is never shown.
String failureMessage(AppFailure f) {
  final m = _messages[f.code];
  if (m != null) return m;
  // Unknown GWM_* codes fall back to the generic message (design-api 6.2).
  return _messages[FailureCode.unknown]!;
}

const _messages = <String, String>{
  FailureCode.unknown: 'มีบางอย่างผิดพลาด ลองใหม่อีกครั้ง',
  FailureCode.validation: 'ข้อมูลไม่ถูกต้อง ตรวจสอบแล้วลองใหม่',
  FailureCode.notFound: 'ไม่พบข้อมูลที่ต้องการ',
  FailureCode.duplicate: 'ข้อมูลนี้มีอยู่แล้ว',
  FailureCode.staleReference: 'ข้อมูลนี้ถูกเปลี่ยนแปลงหรือถูกลบแล้ว ลองโหลดใหม่',
  FailureCode.forbiddenRls: 'ตอนนี้ยังทำรายการนี้ไม่ได้',
  FailureCode.forbiddenColumn: 'มีบางอย่างผิดพลาด ลองใหม่อีกครั้ง',
  FailureCode.sessionExpired: 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่',
  FailureCode.serverUnavailable: 'เซิร์ฟเวอร์ไม่พร้อมใช้งานชั่วคราว ลองใหม่อีกครั้ง',
  FailureCode.rateLimited: 'ลองใหม่อีกครั้งในอีกสักครู่',
  FailureCode.networkOffline: 'ไม่มีการเชื่อมต่ออินเทอร์เน็ต ตรวจสอบแล้วลองใหม่',
  FailureCode.networkTimeout: 'การเชื่อมต่อช้าเกินไป ลองใหม่อีกครั้ง',
  FailureCode.realtimeDisconnected: 'กำลังเชื่อมต่อใหม่',
  FailureCode.configMissing: 'ยังไม่ได้ตั้งค่าการเชื่อมต่อเซิร์ฟเวอร์',
  FailureCode.shareLinkInvalid: 'ลิงก์นี้ใช้ไม่ได้แล้ว',
  FailureCode.uploadTooLarge: 'ไฟล์ใหญ่เกินไป',
  FailureCode.uploadType: 'ชนิดไฟล์ไม่รองรับ',
  FailureCode.authInvalidCredentials: 'อีเมลหรือรหัสผ่านไม่ถูกต้อง',
  FailureCode.authEmailTaken:
      'อีเมลนี้มีบัญชีอยู่แล้ว ลองเข้าสู่ระบบหรือกู้รหัสผ่าน',
  FailureCode.authWeakPassword: 'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร',
  FailureCode.authEmailUnconfirmed: 'ยังไม่ได้ยืนยันอีเมล กรุณาตรวจอีเมลของคุณ',
  FailureCode.signupRequirements: 'กรุณายืนยันอายุ 18 ปีขึ้นไปและยอมรับนโยบาย',
  FailureCode.accountDeleted: 'บัญชีนี้ถูกลบแล้ว ไม่สามารถเข้าสู่ระบบได้',
  FailureCode.routeNotFound: 'ไม่พบเส้นทางระหว่างจุดทั้งสอง ลองเปลี่ยนวิธีเดินทางหรือปักหมุดใหม่',
  FailureCode.locationDenied: 'ยังไม่ได้อนุญาตตำแหน่ง เลือกจุดจากการค้นหาหรือปักหมุดแทนได้',
  FailureCode.locationUnavailable: 'หาตำแหน่งปัจจุบันไม่ได้ ลองใหม่หรือปักหมุดแทน',
  FailureCode.locationInsecureOrigin:
      'ต้องเปิดผ่าน HTTPS หรือ localhost เพื่อใช้ตำแหน่งปัจจุบันบนเว็บ ลองปักหมุดเองแทน',
  // US-50 (round 7 Stage D): OSRM calc for the precise detour failed before request_match was called.
  FailureCode.detourCalcFailed: 'คำนวณระยะเบี่ยงไม่สำเร็จ ลองใหม่อีกครั้ง',
  'GWM_ADULT_REQUIRED': 'ต้องยืนยันว่าอายุ 18 ปีขึ้นไปก่อนใช้งานส่วนนี้',
  'GWM_CONSENT_REQUIRED': 'ต้องยอมรับนโยบายความเป็นส่วนตัวก่อนใช้งานส่วนนี้',
  'GWM_EMAIL_NOT_VERIFIED': 'ต้องยืนยันอีเมลก่อนส่งคำขอ',
  'GWM_INVALID_POINT': 'ตำแหน่งที่เลือกไม่ถูกต้อง',
  'GWM_MATCH_CLOSED': 'การจับคู่นี้ปิดแล้ว ทำรายการไม่ได้',
  'GWM_NO_PROPOSAL': 'ยังไม่มีจุดนัดพบที่เสนอ',
  'GWM_OWN_PROPOSAL': 'อีกฝ่ายต้องเป็นผู้ยืนยันจุดนัดพบที่คุณเสนอ',
  'GWM_PENDING_LIMIT': R.pendingCap,
  'GWM_TRIP_HAS_MATCHES': 'มีคำขอจับคู่ค้างอยู่ ต้องยกเลิกคำขอก่อนแก้ไขทริป',
  'GWM_RATE_LIMITED': 'ทำรายการถี่เกินไป รอสักครู่แล้วลองใหม่',
  'GWM_TRIP_RATE_LIMIT': 'สร้างทริปครบจำนวนต่อวันแล้ว ลองใหม่พรุ่งนี้',
  'GWM_TRIP_EDIT_LIMIT': 'แก้ไขเส้นทางครบจำนวนครั้งแล้ว',
  'GWM_ACTIVE_TRIP_LIMIT': 'คุณมีทริปที่ยังใช้งานอยู่แล้ว จบหรือยกเลิกทริปเดิมก่อน',
  'GWM_ALREADY_EXISTS': 'ข้อมูลนี้มีอยู่แล้ว',
  'GWM_ALREADY_REQUESTED': 'คุณส่งคำขอไปแล้ว',
  'GWM_CANCEL_BEFORE_DELETE': 'กรุณายกเลิกทริปที่ยังใช้งานอยู่ก่อนลบบัญชี',
  'GWM_DEPART_IN_PAST': 'เลือกเวลาที่ยังมาไม่ถึง',
  'GWM_EMERGENCY_CONTACT_LIMIT': 'เพิ่มผู้ติดต่อฉุกเฉินได้ไม่เกิน 3 ราย',
  'GWM_FORBIDDEN': 'คุณไม่มีสิทธิ์ทำรายการนี้',
  'GWM_IMMUTABLE': 'ข้อมูลนี้แก้ไขไม่ได้',
  'GWM_INVALID_CODE': 'รหัสไม่ถูกต้อง',
  'GWM_INVALID_TRIP_TRANSITION': 'ตอนนี้เปลี่ยนสถานะทริปนี้ไม่ได้',
  // Car trips take exactly 1 companion, so the limit reads as "you already have a partner".
  'GWM_MATCH_LIMIT': R.alreadyPaired,
  'GWM_MATCH_NOT_FOUND': 'ไม่พบการจับคู่นี้',
  'GWM_MATCH_NOT_PENDING': 'คำขอนี้ปิดแล้ว',
  'GWM_NOT_ELIGIBLE': 'ยังจับคู่กับทริปนี้ไม่ได้',
  // Driver/Rider roles (0006). Server messages are never shown; no commercial wording.
  'GWM_ROLE_REQUIRED': R.roleRequired,
  'GWM_ROLE_NOT_ALLOWED': 'บทบาทคนขับ/คนนั่งใช้ได้กับรถส่วนตัวเท่านั้น',
  'GWM_ROLE_IMMUTABLE': 'เปลี่ยนบทบาทหรือวิธีเดินทางของทริปนี้ไม่ได้ ยกเลิกทริปแล้วสร้างใหม่ได้',
  'GWM_VEHICLE_REQUIRED': R.needsVehicle,
  'GWM_VEHICLE_INVALID': R.saveFailed,
  'GWM_VEHICLE_IN_USE': R.deleteLocked,
  // Dual role (0008): register / unregister / switch. Server text is never shown.
  'GWM_NOT_A_DRIVER': D.errTripDriverNotRegistered,
  'GWM_DRIVER_ACTIVE_TRIP': D.blockedTrip,
  'GWM_DRIVER_ACTIVE_MATCH': D.blockedMatch,
  'GWM_DRIVER_UNREG_BLOCKED': D.blockedTrip,
  'GWM_DRIVER_REGISTERED': D.vehicleDeleteBlockedRegistered,
  'GWM_DECLARATION_REQUIRED': D.errDeclRequired,
  'GWM_DECLARATION_VERSION_STALE': D.errDeclStale,
  'GWM_INVALID_ROLE': D.errSwitch,
  'GWM_NOT_RIDER': 'ปุ่มนี้ใช้ได้เฉพาะคนนั่งของการจับคู่นี้',
  'GWM_TRIP_NOT_STARTED': 'ต้องให้ทั้งสองทริปเริ่มเดินทางก่อน',
  'GWM_ALREADY_BOARDED': 'ทำรายการนี้ไม่ได้หลังคนนั่งขึ้นรถแล้ว เมื่อถึงที่หมายให้กด "ถึงแล้ว"',
  'GWM_NO_SHOW_NOT_ALLOWED': 'ตอนนี้ยังใช้ปุ่มคนนั่งไม่มาตามนัดไม่ได้',
  'GWM_PICKUP_DRIVER_FIRST': 'ให้คนขับเสนอจุดรับก่อน แล้วคุณค่อยยืนยันหรือเสนอจุดอื่นได้',
  'GWM_PHONE_MOCK_DISABLED': 'ฟีเจอร์นี้ยังไม่เปิดใช้งาน',
  'GWM_PROFILE_UNAVAILABLE': 'ดูโปรไฟล์นี้ไม่ได้',
  'GWM_SHARE_LIMIT': 'แชร์ทริปได้ครบจำนวนสูงสุดแล้ว',
  'GWM_TRIP_FINISHED': 'ทริปนี้จบแล้ว',
  'GWM_TRIP_NOT_FOUND': 'ไม่พบทริปนี้',
  'GWM_TRIP_STARTED': 'ทริปเริ่มเดินทางแล้ว แก้ไขไม่ได้',
  'GWM_TRIP_TOO_SHORT': 'ระยะทางใกล้เกินไปที่จะสร้างทริป',
  'GWM_TRIP_UNAVAILABLE': 'ทริปนี้ไม่พร้อมให้จับคู่แล้ว',
  'GWM_UNAUTHENTICATED': 'กรุณาเข้าสู่ระบบใหม่',
  // Round 5 (0009): avatars, reports, reviews.
  'GWM_AVATAR_INVALID': R5.photoErrServer,
  'GWM_DROPOFF_INVALID': 'ระยะรับส่งต้องอยู่ระหว่าง 500 ม. ถึง 5 กม. และเพิ่มทีละ 100 ม.',
  'GWM_DROPOFF_NOT_ALLOWED': 'ตั้งระยะรับส่งได้เฉพาะทริปที่คุณเป็นคนขับ',
  'GWM_REPORT_INVALID': 'รายงานนี้ไม่ได้แล้ว',
  'GWM_REVIEW_NOT_ELIGIBLE': R5.reviewErrUnavailable,
  'GWM_REVIEW_WINDOW_CLOSED': R5.reviewErrClosed,
  'GWM_REVIEW_DUPLICATE': R5.reviewErrAlready,
  'GWM_REVIEW_INVALID': 'ข้อมูลรีวิวไม่ถูกต้อง ตรวจสอบแล้วลองใหม่',
  // Round 7 draft migrations (0011a/0011/0012, not yet applied/approved on any
  // live DB — design-roles.md §14.6/14.8-5). Mapped here only to keep
  // `test/qa/contract_and_safety_test.dart`'s "every GWM_ code has a Thai
  // message" gate green; only `GWM_DEVICE_TOKEN_INVALID` (US-42, this stage)
  // is ever reachable by code in this round. The other 4 (US-44/45, Stage B)
  // are not wired to any RPC call yet — final copy is BA/PM's call when Stage
  // B lands, this is a safe placeholder, not the reviewed final string.
  'GWM_DEVICE_TOKEN_INVALID': 'ลงทะเบียนอุปกรณ์นี้เพื่อรับแจ้งเตือนไม่สำเร็จ ลองใหม่ภายหลัง',
  'GWM_VIBE_TAG_INVALID': 'แท็กนี้ไม่อยู่ในรายการที่เลือกได้',
  'GWM_MOOD_INVALID': 'ข้อความนี้ใช้ไม่ได้ ลองแก้แล้วส่งใหม่',
  'GWM_ORG_VERIFICATION_REQUIRED': 'ต้องยืนยันอีเมลสถาบันก่อนจึงจะเปิดสวิตช์นี้ได้',
  'GWM_GENDER_REQUIRED': 'ต้องระบุเพศก่อนจึงจะเปิดสวิตช์นี้ได้',
  // Round 7 Stage C (0014): US-49 lateness/no-fault cancel, US-50 detour tolerance.
  'GWM_NOT_OVERDUE': 'ยังไม่เข้าเงื่อนไขล่าช้าตามที่ระบบตรวจสอบ ลองรออีกสักครู่แล้วลองใหม่',
  'GWM_DETOUR_INVALID': 'ระยะเบี่ยงต้องอยู่ระหว่าง 200 ม. ถึง 2 กม. และเพิ่มทีละ 100 ม.',
  'GWM_DETOUR_NOT_ALLOWED': 'ตั้งระยะเบี่ยงได้เฉพาะทริปที่คุณเป็นคนขับ',
  // Round 7 Stage D (0016): US-50 precise (OSRM) detour validation, US-44 vibe/mood on find_matches.
  'GWM_DETOUR_IMPLAUSIBLE': 'ระยะเบี่ยงที่คำนวณได้ไม่สมเหตุสมผล ลองใหม่อีกครั้ง',
};
