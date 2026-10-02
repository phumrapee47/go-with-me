/// Round 5 copy (design-spec round 5 section 9): avatars, live map, navigation, reviews, no-match hint.
/// Thai only, like the rest of the app. Parameterised strings are functions.
abstract final class R5 {
  // ---- photo.* ----
  static const photoTitle = 'รูปโปรไฟล์';
  static const photoAddCta = 'เพิ่มรูปโปรไฟล์';
  static const photoPick = 'เลือกรูป';
  static const photoChange = 'เปลี่ยนรูป';
  static const photoRemove = 'ลบรูป';
  static const photoEmptyHint = 'ตอนนี้ยังไม่มีรูป ใช้ตัวอักษรย่อของคุณอยู่';
  static const photoSourceCamera = 'ถ่ายรูป';
  static const photoSourceGallery = 'เลือกจากคลังภาพ';
  static const photoSourceFile = 'เลือกไฟล์รูป';
  static const photoKeepInitials = 'ใช้ตัวอักษรย่อต่อไป';
  static const photoPermDenied = 'ยังไม่ได้อนุญาต ลองเลือกวิธีอื่น หรือใช้ตัวอักษรย่อต่อไปได้';
  static const photoPrivacyTitle = 'ใครเห็นรูปของคุณ';
  static const photoPrivacyWho = 'เฉพาะคนที่ตอบรับจับคู่กับคุณแล้ว';
  static const photoPrivacyWhen = 'ระหว่างทริป และอีก 24 ชั่วโมงหลังทริปจบ';
  static const photoPrivacyNotWho = 'ไม่แสดงในผลค้นหา คำขอที่ยังไม่ตอบรับ หรือกับคนที่ไม่ได้จับคู่';
  static const photoPrivacyControl = 'ลบรูปได้ทุกเมื่อ และเราไม่ใช้รูปเพื่อจดจำใบหน้า';
  static const photoPrivacyAck = 'เข้าใจแล้ว ไปต่อ';
  static const photoPrivacyShort = 'รูปนี้เห็นได้เฉพาะคู่ที่จับคู่กับคุณ';
  static const photoPrivacyMore = 'ดูรายละเอียด';
  static const photoUploading = 'กำลังอัปโหลดรูป...';
  static const photoPreparing = 'กำลังเตรียมรูป...';
  static const photoSaved = 'บันทึกรูปแล้ว';
  static const photoRemoved = 'ลบรูปแล้ว';
  static const photoRemoveTitle = 'ลบรูปโปรไฟล์?';
  static const photoRemoveBody = 'รูปจะถูกลบออกจากระบบ และคนที่จับคู่กับคุณจะเห็นเป็นตัวอักษรย่อ';
  static const photoErrNotImage = 'ไฟล์นี้ไม่ใช่รูปภาพหรือเปิดไม่ได้ ลองเลือกรูปอื่น';
  static const photoErrTooLarge = 'รูปนี้ใหญ่เกินไป ลองเลือกรูปอื่น';
  static const photoErrTooSmall = 'รูปเล็กเกินไป เลือกรูปที่ชัดกว่านี้';
  static const photoErrUnsupported = 'ยังไม่รองรับรูปแบบนี้ ลองใช้รูป JPEG หรือ PNG';
  static const photoErrUpload = 'อัปโหลดไม่สำเร็จ รูปเดิมของคุณยังอยู่ ลองใหม่อีกครั้ง';
  static const photoErrServer = 'ระบบรับรูปนี้ไม่ได้ ลองเลือกรูปอื่น';
  static const photoErrOffline = 'ต้องต่ออินเทอร์เน็ตก่อนจึงจะเปลี่ยนรูปได้';
  static const photoErrDelete = 'ลบรูปไม่สำเร็จ ลองใหม่อีกครั้ง';
  static const photoCancel = 'ยกเลิก';
  static String photoAvatarLabel(String name) => 'รูปโปรไฟล์ของ $name';
  static String photoInitialLabel(String name) => 'ตัวอักษรย่อของ $name';
  static const photoReportCta = 'รายงานรูปนี้';
  static const photoReportTitle = 'รายงานรูปโปรไฟล์';
  static const photoReportR1 = 'ไม่ใช่รูปของบุคคลนี้';
  static const photoReportR2 = 'มีเนื้อหาไม่เหมาะสม';
  static const photoReportR3 = 'มีบุคคลอื่นในรูป';
  static const photoReportR4 = 'อื่น ๆ';
  static const photoReportSubmit = 'ส่งรายงาน';
  static const photoReportDone = 'ส่งรายงานแล้ว เราซ่อนรูปนี้จากคุณแล้ว';
  static const photoReportAnon = 'ผู้ถูกรายงานจะไม่เห็นว่าใครรายงาน';
  static const photoReportAlready = 'คุณรายงานรูปนี้ไปแล้ว';
  static const photoViewerGone = 'ดูรูปนี้ไม่ได้แล้ว';

  // ---- live.* ----
  static String liveTitle(String name) => 'แผนที่ของคุณกับ $name';
  static const liveRoleDriver = 'คนขับ';
  static const liveRoleRider = 'คนนั่ง';
  static const liveStatusComingToYou = 'กำลังมาหาคุณ';
  static const liveStatusGoingToPickup = 'กำลังไปรับ';
  static const liveStatusTogether = 'อยู่บนรถเดียวกัน';
  static const liveStatusNearby = 'ใกล้ถึงจุดรับแล้ว';
  static const liveStatusNearbyFresh = 'ได้รับตำแหน่งล่าสุดแล้ว';
  static const liveStaleHint = 'ยังไม่ได้รับตำแหน่งใหม่ อาจเป็นเพราะสัญญาณ';
  static String liveNoPeer(String name) => 'ยังไม่ได้รับตำแหน่งของ $name';
  static const liveReconnecting = 'กำลังเชื่อมต่อใหม่...';
  static const liveRiderBoarded = 'คนนั่งขึ้นรถแล้ว ระบบหยุดแสดงตำแหน่งของเขาแล้ว';
  static const liveEnded = 'การจับคู่นี้สิ้นสุดแล้ว ไม่แสดงตำแหน่งอีก';
  static const liveUnavailable = 'ตอนนี้ยังดูแผนที่ร่วมกันไม่ได้';
  static const liveOpen = 'ดูแผนที่ร่วมกัน';
  static const liveLoading = 'กำลังโหลดแผนที่...';
  static const liveLocationOff = 'เปิดตำแหน่งเพื่อให้เห็นตัวคุณบนแผนที่';
  static const liveCtlFollow = 'ตามตำแหน่งของฉัน';
  static const liveCtlFollowing = 'กำลังตามตำแหน่งของคุณ';
  static const liveCtlRecenter = 'กลับมาที่ตำแหน่ง';
  static const liveCtlFitBoth = 'ดูทั้งสองฝ่าย';
  static const liveCtlStopped = 'หยุดตามตำแหน่งแล้ว';
  static String liveCtlFitNoPeer(String name) => 'ยังไม่มีตำแหน่งของ $name จึงแสดงเฉพาะตำแหน่งของคุณ';
  static const liveCtlZoomIn = 'ซูมเข้า';
  static const liveCtlZoomOut = 'ซูมออก';
  static const liveYou = 'คุณ';
  static const livePickupLabel = 'จุดรับ';
  static const liveDestLabel = 'ปลายทางของคุณ';
  static const liveChat = 'แชท';
  static const liveRouteUnavailable = 'ยังแสดงเส้นทางไม่ได้ในตอนนี้';
  static const liveArrived = 'ถึงแล้ว';

  /// "อัปเดตเมื่อ N วินาทีที่แล้ว" (stale after 45 s); minutes up to 10, then a clock time.
  static String liveUpdatedSeconds(int s) => 'อัปเดตเมื่อ $s วินาทีที่แล้ว';
  static String liveUpdatedMinutes(int m) => 'อัปเดตเมื่อ $m นาทีที่แล้ว';
  static String liveLastSeenAt(String hhmm) => 'ตำแหน่งล่าสุดเมื่อ $hhmm';

  // ETA
  static String etaPickupRider(int n) => 'คนขับจะถึงจุดรับประมาณ $n นาที';
  static String etaPickupDriver(int n) => 'คุณจะถึงจุดรับประมาณ $n นาที';
  static String etaDest(int n) => 'ถึงปลายทางประมาณ $n นาที';
  static const etaApproxTag = '(ไม่แม่น)';
  static const etaSoon = 'ใกล้ถึงแล้ว';
  static const etaCalculating = 'กำลังคำนวณเวลา...';
  static String etaMinutes(int n) {
    if (n >= 60) {
      final h = n ~/ 60;
      final m = n % 60;
      return m == 0 ? '$h ชม.' : '$h ชม. $m นาที';
    }
    return '$n นาที';
  }

  // text alternative (E-13)
  static const textAltOpen = 'ดูข้อมูลแบบข้อความ';
  static String textAltDistance(String name, String dist, String dir) => '$name อยู่ห่างจากคุณประมาณ $dist ไปทาง$dir';
  static const dirs = ['เหนือ', 'ตะวันออกเฉียงเหนือ', 'ตะวันออก', 'ตะวันออกเฉียงใต้', 'ใต้', 'ตะวันตกเฉียงใต้', 'ตะวันตก', 'ตะวันตกเฉียงเหนือ'];

  // ---- quick replies for agreeing a drop-off (Z-2 option A) ----
  static const quickTitle = 'ตกลงจุดลงผ่านแชท';
  static const quickReplies = <String>[
    'ขอลงก่อนถึงปลายทางได้ไหม',
    'ช่วยบอกจุดที่สะดวกให้ลงหน่อย',
    'ลงตรงนี้ได้เลย ขอบคุณ',
    'ตกลง ลงตามที่คุยกัน',
  ];

  // ---- nav.* ----
  static const navToPickup = 'นำทางไปจุดรับ';
  static const navToDestination = 'นำทางไปปลายทาง';
  static const navNoPickup = 'ยังไม่ได้กำหนดจุดรับ';
  static const navGoSetPickup = 'ไปตกลงจุดรับ';
  static const navSheetTitle = 'เปิดด้วยแอปไหน';
  static const navGoogle = 'Google Maps';
  static const navApple = 'Apple Maps';
  static const navWeb = 'เปิดในเว็บแผนที่';
  static const navSafety = 'ขับรถอย่างปลอดภัยและทำตามกฎจราจร ไม่ใช้มือถือขณะขับ';
  static const navNoticeTitle = 'ก่อนเปิดแอปแผนที่';
  static String navNoticeBody(String what) =>
      'เราจะส่งพิกัดของ$whatให้แอปแผนที่ที่คุณเลือก แอปนั้นมีนโยบายข้อมูลของตัวเอง เราไม่ส่งตำแหน่งของคู่ทริปให้แอปแผนที่';
  static const navNoticeOk = 'เข้าใจแล้ว ไปต่อ';
  static const navOpenFail = 'เปิดแอปแผนที่ไม่สำเร็จ ลองเปิดในเว็บแผนที่แทนได้';
  static const navTargetPickup = 'จุดรับ';
  static const navTargetDest = 'ปลายทางของคุณ';
  static const navUseWeb = 'เปิดในเว็บ';
  static const navCancel = 'ยกเลิก';

  // ---- review.* ----
  static String reviewPrompt(String name, String date, int days) => 'ให้คะแนน $name ได้ถึง $date (เหลือ $days วัน)';
  static const reviewLater = 'ไว้ทีหลัง';
  static const reviewGive = 'ให้คะแนน';
  static String reviewTitle(String name) => 'ให้คะแนน $name';
  static const reviewAsDriver = 'ในฐานะคนขับ';
  static const reviewAsRider = 'ในฐานะคนนั่ง';
  static const reviewStarLabels = ['ไม่ดีเลย', 'ยังไม่ค่อยดี', 'พอใช้', 'ดี', 'ดีมาก'];
  static String reviewStarsA11y(int n) => 'ให้ $n ดาวจาก 5 ดาว';
  static const reviewStarsRequired = 'เลือกจำนวนดาวก่อนส่ง';
  static const reviewTagsTitle = 'เลือกที่ตรงกับการเดินทางครั้งนี้ (ไม่บังคับ)';
  static const reviewTagsGood = 'ข้อดี';
  static const reviewTagsImprove = 'ควรปรับปรุง';
  static const reviewCommentHint = 'เขียนเพิ่มเติมได้ (ไม่บังคับ)';
  static const reviewCommentHelp = 'ห้ามใส่เบอร์โทร ชื่อจริง ทะเบียนรถ หรือข้อมูลส่วนตัวของผู้อื่น';
  static String reviewNoteVisibility(String name) => 'ความเห็นเห็นได้เฉพาะ $name และผู้ดูแลระบบ ไม่แสดงชื่อคุณ';
  static const reviewNoteReveal = 'รีวิวจะเปิดเผยเมื่อทั้งสองฝ่ายส่งครบ หรือครบ 7 วัน อย่างใดอย่างหนึ่งก่อน';
  static const reviewNoteFinal = 'ส่งแล้วแก้ไขไม่ได้';
  static const reviewSubmit = 'ส่งรีวิว';
  static const reviewSkip = 'ข้ามไปก่อน';
  static const reviewDoneTitle = 'ขอบคุณที่ให้คะแนน';
  static String reviewDoneBody(String name, String date) =>
      'รีวิวของคุณจะถูกเปิดเผยเมื่อ $name ส่งรีวิวแล้ว หรือครบ 7 วัน ($date) อย่างใดอย่างหนึ่งก่อน';
  static const reviewDoneClose = 'เสร็จสิ้น';
  static const reviewErrClosed = 'หมดเวลารีวิวสำหรับทริปนี้แล้ว';
  static const reviewErrAlready = 'คุณรีวิวคนนี้ไปแล้ว';
  static const reviewErrRate = 'ส่งบ่อยเกินไป รอสักครู่แล้วลองใหม่';
  static const reviewErrNetwork = 'ส่งไม่สำเร็จ ข้อความที่คุณเขียนยังอยู่ ลองใหม่อีกครั้ง';
  static const reviewErrUnavailable = 'ไม่สามารถส่งรีวิวนี้ได้แล้ว';
  static const reviewSent = 'ส่งรีวิวแล้ว';
  static const reviewStatusPending = 'ส่งแล้ว รอเปิดเผย';
  static String reviewSummary(String avg, int n) => 'ดาว $avg จาก $n รีวิว';
  static String reviewSummaryA11y(String avg, int n, String role) => 'คะแนน $avg จาก 5 ดาว จาก $n รีวิว $role';
  static const reviewMineTitle = 'คะแนนของฉัน';
  static const reviewMineEmpty = 'ยังไม่มีรีวิวที่เปิดเผย รีวิวจะปรากฏเมื่อทั้งสองฝ่ายส่งครบ หรือครบ 7 วัน';
  static const reviewMineRow = 'คะแนนและรีวิวของฉัน';
  static const reviewReportCta = 'รายงานความเห็นนี้';
  static const reviewReportDone = 'ส่งรายงานแล้ว เราซ่อนความเห็นนี้ไว้ก่อน';
  static const reviewReportOther = 'อื่น ๆ';
  static const reviewReportInappropriate = 'ไม่เหมาะสม';
  static const reviewReportPrivate = 'มีข้อมูลส่วนตัว';
  static const reviewTagLabels = <String, String>{
    'on_time': 'ตรงเวลา',
    'polite': 'สุภาพ',
    'safe_driving': 'ขับปลอดภัย',
    'vehicle_matches': 'รถตรงตามที่แจ้ง',
    'late': 'มาช้า',
    'not_as_agreed': 'ไม่ตรงนัด',
  };
  static const reviewPositiveTags = {'on_time', 'polite', 'safe_driving', 'vehicle_matches'};

  // ---- match.* ----
  static const matchRuleExplain = 'จุดเริ่มต้องอยู่ใกล้กัน และปลายทางของคนนั่งต้องอยู่ในระยะที่คนขับรับส่งได้';
  static String matchSameWay(int n) => 'ทางเดียวกัน ~$n%';
  static String matchDriverMaxDropoff(String x) => 'คนขับรับส่งได้ไม่เกิน $x จากปลายทางของเขา';
  static const noneNoDriver = 'ยังไม่มีคนขับที่รอในช่วงนี้ ทริปของคุณยังอยู่ในระบบ ลองกลับมาดูอีกครั้ง';
  static const noneNoRider = 'ยังไม่มีคนนั่งที่รอในช่วงนี้ ทริปของคุณยังอยู่ในระบบ ลองกลับมาดูอีกครั้ง';
  static const noneFarDest = 'มีทริปที่ออกจากจุดใกล้คุณ แต่ปลายทางอยู่ไกลเกินระยะที่คนขับรับส่งได้ ลองตรวจปลายทางหรือระยะรับส่ง';
  static const noneFarOrigin = 'มีทริปที่ปลายทางใกล้เคียง แต่จุดเริ่มอยู่ไกลจากคุณ ลองตรวจจุดเริ่ม';
  static const noneRoute = 'ตอนนี้ยังไม่มีทริปที่อยู่ตามเส้นทางของคุณ ลองตรวจปลายทางและจุดเริ่ม';
  static const nonePeerRoute = 'ยังไม่มีทริปที่ออกไปทางเดียวกับคุณ ลองตรวจปลายทางหรือเวลา';
  // ---- driver drop-off limit (trips.max_dropoff_m) ----
  static const dropoffLabel = 'รับส่งได้ไกลจากปลายทางของฉันไม่เกิน';
  static const dropoffHelper =
      'คนนั่งที่ปลายทางอยู่ห่างจากปลายทางของคุณเกินระยะนี้จะไม่ถูกจับคู่ให้คุณ ยิ่งตั้งไกลยิ่งมีคนนั่งให้เลือกมากขึ้น (ค่าเริ่มต้น 2 กม.)';
  static const dropoffLockedReason = 'แก้ไม่ได้ขณะมีคำขอจับคู่ที่รออยู่หรือมีคู่ที่ตอบรับแล้ว ยกเลิกคำขอ/การจับคู่ก่อนจึงจะแก้ได้';
  static const dropoffSave = 'บันทึกระยะรับส่ง';
  static const dropoffSaved = 'บันทึกระยะรับส่งแล้ว';
  static const noneGeneric = 'ยังไม่พบคู่ที่ตรงกัน ลองใหม่อีกครั้งภายหลัง';
  static const noneCheckDest = 'ตรวจปลายทาง';
  static const noneRetry = 'ลองค้นหาใหม่';
  static const noneWait = 'รอสักครู่ก่อนลองใหม่';
}
