import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n/strings_dual.dart';
import '../core/l10n/strings_r6.dart';
import '../core/l10n/strings_r6_cd.dart';
import '../core/l10n/strings_roles.dart';
import '../core/router/redirect.dart';
import '../features/chat/domain/chat_models.dart';
import '../features/geo/presentation/geo_providers.dart';
import '../features/matching/domain/match_models.dart' show MatchHint;
import '../features/matching/presentation/matching_providers.dart';
import '../features/presets/domain/preset.dart';
import '../features/presets/presentation/preset_providers.dart';
import '../features/push/domain/push_models.dart';
import '../features/roles/presentation/role_providers.dart';
import '../features/safety/presentation/safety_providers.dart';
import '../features/sharing/presentation/sharing_providers.dart';
import '../features/trip/presentation/trip_lifecycle_providers.dart';
import '../features/trip/presentation/trip_providers.dart';
import '../features/vehicle/presentation/vehicle_providers.dart';
import 'demo_data.dart';
import 'demo_fakes_r7.dart';
import 'demo_overrides.dart';

const demoHubPath = '/demo';

/// Index of every screen so a reviewer can reach all of them without a server.
class DemoHubScreen extends ConsumerWidget {
  const DemoHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget section(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(t, style: Theme.of(context).textTheme.titleMedium),
        );
    Widget item(String title, String path, {bool push = true, String? sub}) => ListTile(
          title: Text(title),
          subtitle: sub == null ? null : Text(sub),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => push ? context.push(path) : context.go(path),
        );
    Widget tool(IconData icon, String title, VoidCallback onTap, {String? sub}) => ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: sub == null ? null : Text(sub),
          onTap: onTap,
        );
    void toast(String t) =>
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

    void refreshAll() {
      ref.invalidate(activeTripProvider);
      ref.invalidate(nearbyProvider);
      ref.invalidate(inboxProvider);
      ref.invalidate(myTripsProvider(false));
      ref.invalidate(myTripsProvider(true));
      ref.invalidate(contactsProvider);
      ref.invalidate(blockedUsersProvider);
      ref.invalidate(myVehicleProvider);
      ref.read(roleControllerProvider.notifier).refresh();
    }

    void setScenario(DemoScenario sc) {
      ref.read(demoTripRepositoryProvider).reset(sc);
      ref.read(demoMatchRepositoryProvider).reset(sc);
      ref.read(demoVehicleRepositoryProvider).reset(sc);
      ref.read(demoRoleRepositoryProvider).reset(sc);
      ref.read(demoChatRepositoryProvider).reset();
      refreshAll();
      toast('สลับเป็น: ${sc.label}');
    }

    final matches = ref.read(demoMatchRepositoryProvider);
    final vehicles = ref.read(demoVehicleRepositoryProvider);

    final roles = ref.read(demoRoleRepositoryProvider);
    final chat = ref.read(demoChatRepositoryProvider);
    final sos = ref.read(demoSosRepositoryProvider);
    final push = ref.read(demoPushServiceProvider);
    final roadSnap = ref.read(demoRoadSnapProvider);
    String demoMatchId() => matches.matches.isEmpty ? 'demo-match-1' : matches.matches.first.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('เดโม (DEMO)'),
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home)),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'โหมดเดโม: ไม่เชื่อมต่อ Supabase ข้อมูลทั้งหมดเป็นข้อมูลสมมติในหน่วยความจำ '
              '(ผู้ใช้: $demoUserName) การค้นหาสถานที่และเส้นทางเป็นตัวจำลองออฟไลน์ '
              'เส้นทางเป็นเส้นตรงพร้อมจุดผ่านจำลอง ไม่ใช่เส้นทางถนนจริง '
              'การโทร/แชร์/SMS จะแสดงเป็นแถบข้อความด้านล่างแทนการเปิดแอปจริง',
            ),
          ),
          section(R.demoRoleTitle),
          ValueListenableBuilder<bool>(
            valueListenable: vehicles.partnerShareAllowed,
            builder: (_, allowed, _) => SwitchListTile(
              secondary: const Icon(Icons.badge_outlined),
              title: const Text('คนขับอนุญาตส่งทะเบียนไปกับแชร์/SOS (ฝั่งคนนั่ง)'),
              subtitle: const Text('สลับแล้วเปิดหน้าแชร์/SOS ดูตัวอย่างข้อความ มี/ไม่มีทะเบียน'),
              value: allowed,
              onChanged: (v) {
                vehicles.partnerShareAllowed.value = v;
                ref.invalidate(shareCompanionProvider);
              },
            ),
          ),
          for (final sc in DemoScenario.values)
            tool(
              matches.scenario == sc ? Icons.radio_button_checked : Icons.radio_button_off,
              'สลับเป็น: ${sc.label}',
              () => setScenario(sc),
              sub: sc == DemoScenario.peer
                  ? 'เดิน/รถสาธารณะ/แท็กซี่ ยังจับคู่แบบ peer'
                  : 'รีเซ็ตทริป คำขอ และข้อมูลรถให้ตรงกับบทบาท',
            ),
          section('โหมดคนขับ/คนนั่ง และการลงทะเบียนคนขับ (รอบ 4)'),
          tool(Icons.person_outline, 'บัญชี: คนนั่งล้วน (ยังไม่ลงทะเบียน)', () {
            roles.asRiderOnly();
            refreshAll();
            ref.read(roleControllerProvider.notifier).refresh();
            toast('บัญชีคนนั่งล้วน: ไม่มีปุ่มสลับ ตัวเลือกคนขับในฟอร์มสร้างทริปถูกล็อก');
          }, sub: 'ลงทะเบียนได้ที่แท็บ "ฉัน" หรือจากฟอร์มสร้างทริป (ฟอร์มไม่หาย)'),
          tool(Icons.people_outline, 'บัญชี: สองบทบาท (ลงทะเบียนแล้ว)', () {
            roles.asTwoRoles();
            refreshAll();
            ref.read(roleControllerProvider.notifier).refresh();
            toast('บัญชีสองบทบาท: สลับโหมดได้ 1 แตะจากแถบบน');
          }),
          tool(Icons.devices_other, 'จำลอง: ยกเลิกลงทะเบียนจากอุปกรณ์อื่น', () {
            roles.unregisterElsewhere();
            ref.read(roleControllerProvider.notifier).refresh();
            toast('กลับหน้าหลักเพื่อดูโทนเปลี่ยนเป็นคนนั่งพร้อมข้อความแจ้ง');
          }, sub: 'ถ้าเครื่องนี้อยู่โหมดคนขับ จะถูกปรับเป็นคนนั่ง (F-D8)'),
          ValueListenableBuilder<bool>(
            valueListenable: roles.offline,
            builder: (_, off, _) => SwitchListTile(
              secondary: const Icon(Icons.wifi_off),
              title: const Text('จำลองออฟไลน์ (สลับ/ลงทะเบียน/ยกเลิกไม่ได้)'),
              subtitle: const Text('สลับเป็นคนนั่งยังได้ (บันทึกทีหลัง) สลับเป็นคนขับต้องออนไลน์'),
              value: off,
              onChanged: (v) {
                roles.offline.value = v;
                if (!v) ref.read(roleControllerProvider.notifier).refresh();
              },
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: roles.rejectRegistration,
            builder: (_, on, _) => SwitchListTile(
              secondary: const Icon(Icons.gpp_bad_outlined),
              title: const Text('จำลอง: เซิร์ฟเวอร์ปฏิเสธการลงทะเบียน'),
              subtitle: const Text('ข้อความรับรองเวอร์ชันเก่า: ข้อมูลที่กรอกยังอยู่'),
              value: on,
              onChanged: (v) => roles.rejectRegistration.value = v,
            ),
          ),
          item(D.regTitle, Routes.driverRegister, sub: 'ถ้าลงทะเบียนแล้ว จะพาไปหน้าข้อมูลรถ'),
          item('ข้อมูลรถของฉัน', Routes.vehicle),
          item('ข้อมูลรถ (กรอกแล้วกลับไปสร้างทริป)', Routes.vehicleFor(returnTo: Routes.tripOptions)),
          item('เสนอจุดรับ (ต้องมีการจับคู่ที่ตอบรับแล้ว)', Routes.pickup('demo-match-pending')),
          tool(Icons.play_circle_outline, 'จำลอง: อีกฝ่ายเริ่มเดินทาง', () {
            matches.partnerStartsTrip();
            toast('ทริปของอีกฝ่ายกำลังเดินทาง (ปุ่ม "ขึ้นรถแล้ว" เปิดได้ถ้าทริปของคุณเริ่มแล้ว)');
          }),
          tool(Icons.place_outlined, 'จำลอง: อีกฝ่ายเสนอจุดรับ', () {
            toast(matches.partnerProposesPickup() ? 'อีกฝ่ายเสนอจุดรับแล้ว' : 'ทำไม่ได้ (ยังไม่มีการจับคู่ หรือขึ้นรถแล้ว)');
          }),
          tool(Icons.airline_seat_recline_normal, 'จำลอง: คนนั่งกดขึ้นรถแล้ว (มุมคนขับ)', () {
            toast(matches.partnerBoards() ? 'คนนั่งขึ้นรถแล้ว' : 'ยังไม่มีการจับคู่');
          }),
          tool(Icons.link_off, 'จำลอง: อีกฝ่ายยกเลิกการจับคู่', () {
            toast(matches.partnerEndsMatch()
                ? 'อีกฝ่ายยกเลิกการจับคู่แล้ว (คนนั่งที่กำลังเดินทางจะเห็นการแจ้งเตือน)'
                : 'ทำไม่ได้ (ไม่มีการจับคู่ หรือคนนั่งขึ้นรถแล้ว)');
          }, sub: 'ถ้าเป็นคนนั่งและทริปกำลังเดินทาง จะเห็นแบนเนอร์แจ้งเตือนทันที'),
          tool(Icons.no_crash_outlined, 'ล้างข้อมูลรถของฉัน', () {
            vehicles.clear();
            ref.invalidate(myVehicleProvider);
            toast('ล้างข้อมูลรถแล้ว (คนขับสร้างทริปใหม่ไม่ได้จนกว่าจะกรอก)');
          }),
          section('เริ่มต้น'),
          item('Splash (ก่อนเข้าแอป)', Routes.splash, push: false),
          item('Onboarding', Routes.onboarding, push: false, sub: 'ต้องออกจากระบบก่อนจึงจะเห็นตามลำดับปกติ'),
          item('ตั้งค่าโปรไฟล์ / แก้ไขโปรไฟล์', Routes.meEdit),
          item('นโยบายความเป็นส่วนตัว', Routes.policy),
          item('ข้อกำหนดการใช้งาน', Routes.terms),
          section('แท็บหลัก'),
          item('หน้าหลัก', Routes.home, push: false),
          item('ใกล้ฉัน (คนใกล้เคียง)', Routes.nearby, push: false),
          item('แชท', Routes.chats, push: false),
          item('ทริปของฉัน', Routes.trips, push: false),
          item('ฉัน', Routes.me, push: false),
          section('สร้างทริป'),
          item('ขั้น 1: เลือกต้นทาง/ปลายทาง', Routes.tripNew,
              sub: 'ต้องไม่มีทริปที่ใช้งานอยู่ (ใช้ปุ่มล้างทริปด้านล่าง)'),
          item('ขั้น 2: เวลาและวิธีเดินทาง', Routes.tripOptions),
          item('ขั้น 3: ยืนยัน', Routes.tripConfirm),
          section('คนใกล้เคียงและการจับคู่'),
          item('กล่องคำขอ', Routes.nearbyRequests),
          item('รายละเอียดผู้สมัคร (นุ่น)', Routes.candidate('demo-cand-1')),
          item('คำขอที่รอตอบ (พลอย)', Routes.match('demo-match-pending')),
          item('จับคู่แล้ว + จุดนัดพบ (ต้นไม้)', Routes.match('demo-match-accepted')),
          section('แชท'),
          item('ห้องแชทกับต้นไม้', Routes.chat('demo-match-accepted'),
              sub: 'พิมพ์ส่งได้ ต้นไม้จะตอบอัตโนมัติใน 2 วินาที'),
          tool(Icons.mark_chat_unread_outlined, 'ให้ต้นไม้ส่งข้อความมา (จุดแดงบนแท็บแชท)', () {
            chat.partnerSays('ถึงสถานีแล้วนะครับ');
            toast('ส่งข้อความจากต้นไม้แล้ว');
          }),
          tool(Icons.lock_open, 'สถานะแชท: เปิด', () {
            chat.forceState(null);
            toast('แชทเปิดปกติ');
          }, sub: 'chat_state = open'),
          tool(Icons.block, 'สถานะแชท: บล็อก (อ่านอย่างเดียว)', () {
            chat.forceState(ChatState.blocked);
            toast('แชทเป็นอ่านอย่างเดียว (blocked)');
          }),
          tool(Icons.flag_outlined, 'สถานะแชท: ทริปจบแล้ว', () {
            chat.forceState(ChatState.tripEnded);
            toast('แชทเป็นอ่านอย่างเดียว (trip_ended)');
          }),
          tool(Icons.link_off, 'สถานะแชท: การจับคู่ปิดแล้ว', () {
            chat.forceState(ChatState.matchClosed);
            toast('แชทเป็นอ่านอย่างเดียว (match_closed)');
          }),
          section('วงจรทริปและตำแหน่งสด'),
          item('รายละเอียดทริปปัจจุบัน', Routes.tripDetail('demo-trip-me'),
              sub: 'กด "เริ่มเดินทาง" แล้วดูแผนที่ ตำแหน่งจำลองเดินไปถึงปลายทางใน ~1 นาที'),
          item('หน้าทริปกำลังเดินทาง', Routes.tripActive('demo-trip-me'), sub: 'ต้องกดเริ่มเดินทางก่อน'),
          item('หน้าถึงแล้ว', Routes.tripArrived('demo-trip-me')),
          item('แชร์ทริป', Routes.tripShare('demo-trip-me')),
          item('ทริปที่เสร็จสิ้น (ประวัติ)', Routes.tripDetail('demo-trip-h1')),
          section('ความปลอดภัย'),
          item('SOS', Routes.sos, sub: 'กดค้าง 2 วินาที หรือแตะยืนยัน'),
          item('ความปลอดภัย (Safety)', Routes.safety),
          item('ผู้ติดต่อฉุกเฉิน', Routes.safetyContacts, sub: 'สูงสุด 3 ราย ลบรายสุดท้ายมีคำเตือน'),
          item('รายงานผู้ใช้', Routes.report('demo-user-demo-cand-2', matchId: 'demo-match-accepted', name: 'ต้นไม้')),
          item('ผู้ใช้ที่ถูกบล็อก', Routes.blocked),
          ValueListenableBuilder<bool>(
            valueListenable: sos.offline,
            builder: (_, off, _) => SwitchListTile(
              secondary: const Icon(Icons.cloud_off_outlined),
              title: const Text('จำลองออฟไลน์ (SOS ส่งขึ้นเซิร์ฟเวอร์ไม่ได้)'),
              subtitle: const Text('เหตุการณ์ SOS จะค้างในคิวในเครื่องแล้วส่งซ้ำอัตโนมัติเมื่อปิดสวิตช์'),
              value: off,
              onChanged: (v) {
                sos.offline.value = v;
                if (!v) ref.read(sosServiceProvider).kick();
              },
            ),
          ),
          tool(Icons.send_outlined, 'ส่งคิว SOS ตอนนี้', () async {
            final r = await ref.read(sosServiceProvider).kick();
            toast('ส่งแล้ว ${r.sent} · ค้างในคิว ${r.remaining}');
          }, sub: 'คิวค้าง: ${ref.read(sosServiceProvider).pendingCount}'),
          section('รอบ 5: รูปโปรไฟล์ แผนที่สด นำทาง รีวิว'),
          item('รูปโปรไฟล์ของฉัน', Routes.mePhoto, sub: 'เลือกรูปสมมติ ย่อ 512 px เป็น JPEG แล้ว "อัปโหลด"'),
          item('แผนที่สด (คู่ที่จับคู่แล้ว)', Routes.live('demo-match-accepted'),
              sub: 'ต้องกด "เริ่มเดินทาง" ในทริปก่อน ไอคอนขยับทุก 15 วินาที'),
          ValueListenableBuilder<bool>(
            valueListenable: ref.read(demoLiveLocationRepositoryProvider).frozen,
            builder: (_, frozen, _) => SwitchListTile(
              secondary: const Icon(Icons.signal_wifi_off_outlined),
              title: const Text('จำลองสัญญาณคู่ขาด (ตำแหน่งหยุดอัปเดต)'),
              subtitle: const Text('เกิน 45 วินาทีจะขึ้น "อัปเดตเมื่อ N วินาทีที่แล้ว" และไอคอนคู่เป็นแบบเก่า'),
              value: frozen,
              onChanged: (v) => ref.read(demoLiveLocationRepositoryProvider).frozen.value = v,
            ),
          ),
          tool(Icons.lightbulb_outline, 'สลับหมวดคำอธิบายเมื่อไม่พบผล', () {
            final order = [MatchHint.noneFound, MatchHint.farDestination, MatchHint.farOrigin, MatchHint.hasResults];
            final next = order[(order.indexOf(matches.hintForDemo) + 1) % order.length];
            matches.hintForDemo = next;
            ref.invalidate(matchHintProvider);
            toast('หมวดคำอธิบาย: ${next.db} (เห็นใต้สถานะว่างที่แท็บ ค้นหา เมื่อไม่มีผล)');
          }, sub: 'ปัจจุบัน: ${matches.hintForDemo.db}'),
          item('ให้คะแนนหลังเดินทาง', Routes.review('demo-match-accepted'), sub: 'ต้องมีคนนั่งขึ้นรถแล้ว (โหมดคนขับ/คนนั่ง)'),
          item('คะแนนของฉัน', Routes.meReviews),
          section('รอบ 6 (ขั้น A+B): หน้าเดินทางรวม สไลด์ยืนยัน'),
          item('หน้าเดินทางรวม (/trips/active)', Routes.tripActiveNow,
              sub: 'แผนที่เต็มจอ + แผ่นลาก 3 ระดับ; SOS มุมขวาบนทุกระดับ; ทริปที่ยังไม่เริ่ม = สไลด์เริ่มเดินทาง'),
          tool(Icons.pin_drop_outlined, 'จำลอง: คนขับกด "ถึงจุดรับแล้ว" (มุมคนนั่ง)', () {
            chat.partnerSays(R6.arrivedAtPickupMessage);
            toast('ส่งข้อความ "${R6.arrivedAtPickupMessage}" จากอีกฝ่ายแล้ว (สถานะบนหน้าเดินทางรวมเปลี่ยน)');
          }, sub: 'ต้องเป็นคนนั่งที่จับคู่ตอบรับแล้ว ทริปกำลังเดินทาง และยังไม่ขึ้นรถ'),
          const ListTile(
            leading: Icon(Icons.swipe),
            title: Text('สไลด์เขียวเมื่อใกล้ปลายทาง (< 150 ม.)'),
            subtitle: Text('ตำแหน่งจำลองเดินถึงปลายทางใน ~1 นาทีหลังเริ่มเดินทาง; ผู้ใช้ screen reader ใช้ดับเบิลแตะ/กดค้าง 1.5 วินาทีแทนการสไลด์'),
          ),
          section('รอบ 6 (ขั้น C+D): การ์ดเพื่อนร่วมทาง สถานที่โปรด ทางลัดกลับบ้าน'),
          item('การ์ดเพื่อนร่วมทาง (/nearby)', Routes.nearby,
              push: false, sub: 'ปัดขวา/💚 ชวนทันที เลิกชวนได้ 5 วินาที ปัดซ้าย/✕ ข้าม; สลับ "รายการ" ได้'),
          tool(Icons.favorite_border, 'จำลอง: เพื่อนตอบรับคำขอที่ชวนไว้ (Match Moment)', () {
            final ok = matches.partnerAcceptsPending();
            toast(ok ? 'เพื่อนตอบรับแล้ว: หน้าจอ "ได้เพื่อนกลับบ้านแล้ว" จะขึ้น' : 'ยังไม่มีคำขอที่ชวนไว้ ไปปัดขวาที่การ์ดก่อน');
          }, sub: 'ต้องชวนใครไว้ก่อนที่แท็บ ค้นหา'),
          tool(Icons.speed, 'จำลอง: ชวนถี่เกินไป (throttle) ครั้งถัดไป', () {
            matches.throttleNextRequest = true;
            toast('การชวนครั้งถัดไปจะขึ้นข้อความ "ชวนถี่เกินไป"');
          }),
          tool(Icons.home_work_outlined, 'ตั้งค่าตัวอย่าง: บ้าน + ที่ทำงาน (เก็บในหน่วยความจำ)', () async {
            final c = ref.read(presetsProvider.notifier);
            await c.save(PresetKind.home,
                PlacePreset(name: 'บ้าน', label: demoPlaces[2].label, point: demoPlaces[2].point));
            await c.save(PresetKind.start,
                PlacePreset(name: 'ที่ทำงาน', label: demoPlaces[0].label, point: demoPlaces[0].point, startType: StartType.work));
            toast('ตั้งบ้านและที่ทำงานแล้ว: ล้างทริปแล้วไปหน้าแรกเพื่อเห็นการ์ด "กำลังจะกลับบ้านใช่ไหม?"');
          }, sub: 'ต้องเป็นโหมดคนขับ/คนนั่ง (รถ) และไม่มีทริปที่ใช้งานอยู่'),
          item('สถานที่โปรด (/me/places)', Routes.mePlaces, sub: 'ตั้ง/แก้/ลบ บ้านและจุดเริ่มประจำ พร้อมแผ่นแจ้งความเป็นส่วนตัว'),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text(R6C.localOnlyCaption),
            subtitle: Text('สถานที่โปรดถูกล้างเมื่อออกจากระบบหรือลบบัญชี'),
          ),
          section('รอบ 7 (ขั้น A): แจ้งเตือนพุช และหมุดปรับติดถนน'),
          item('การตั้งค่าแจ้งเตือน (/me/settings/notifications)', Routes.settingsNotifications,
              sub: 'มาสเตอร์ทอกเกิลเดียว (Q-G1); สถานะสิทธิ์ระดับเครื่อง'),
          for (final kind in PushKind.values) ...[
            tool(Icons.notifications_active_outlined, 'จำลอง: แตะแจ้งเตือน "${kind.wire}"', () {
              push.simulateTap(PushMessage(kind: kind, matchId: demoMatchId(), tripId: demoMatchId()));
              toast('จำลองแตะ push: ${kind.wire} -> นำทางไปหน้าเป้าหมายแล้ว');
            }, sub: kind == PushKind.newRequest ? 'ไปหน้ารายการคำขอ; อื่น ๆ ไปหน้าคู่จับคู่/แชท/live ตามชนิด' : null),
          ],
          tool(Icons.notifications_none, 'จำลอง: แจ้งเตือนเข้าขณะเปิดแอปอยู่หน้าอื่น (in-app banner)', () {
            push.simulateForeground(const PushMessage(kind: PushKind.newMessage, matchId: 'demo-match-1'));
            toast('แบนเนอร์ในแอปควรขึ้นด้านบน แตะเพื่อไปหน้าแชท');
          }),
          tool(Icons.route, 'จำลอง: หมุดปรับติดถนนสำเร็จ (ครั้งถัดไป)', () {
            roadSnap.mode = DemoSnapMode.accept;
            toast('ครั้งถัดไปที่กด "เสนอจุดนี้" ในหน้าจุดรับ หมุดจะขยับติดถนนพร้อมวงแหวน+ไอคอนถนน');
          }, sub: 'ไปที่ /matches/:id/pickup ของคู่จับคู่แล้วลองปักหมุด'),
          tool(Icons.warning_amber_outlined, 'จำลอง: หมุดเบี่ยงเกินเกณฑ์ (ปฏิเสธ snap เงียบ ๆ)', () {
            roadSnap.mode = DemoSnapMode.rejectDeviation;
            toast('ครั้งถัดไปหมุดจะไม่ขยับ (เบี่ยงเกิน ${ref.read(serviceConfigProvider).snapMaxDeviationM} ม.) ใช้จุดดิบต่อ');
          }),
          tool(Icons.wifi_off, 'จำลอง: บริการปรับติดถนนล้มเหลว/timeout', () {
            roadSnap.mode = DemoSnapMode.fail;
            toast('ครั้งถัดไปจะ fallback ใช้จุดดิบทันที พร้อมข้อความเล็กใต้แผนที่');
          }),
          section('รอบ 7 (ขั้น C): ล่าช้า/ยกเลิกไม่เสียประวัติ, ระยะเบี่ยง, ผลกระทบร่วม'),
          tool(Icons.hourglass_bottom, 'จำลอง: เข้าเงื่อนไขล่าช้า (การ์ดสองตัวเลือก)', () {
            ref.read(demoMatchRepositoryProvider).demoServerConfirmsOverdue = true;
            toast('เซิร์ฟเวอร์จำลองจะยืนยันว่าล่าช้าจริงเมื่อกด "ยกเลิกการเดินทาง" ในหน้าเดินทางรวม');
          }, sub: 'ต้องมีคู่จับคู่ตอบรับแล้ว (รถ) และยังไม่ขึ้นรถ ทริปทั้งสองฝั่งกำลังเดินทาง'),
          tool(Icons.block_flipped, 'จำลอง: เซิร์ฟเวอร์ยังไม่ยืนยันว่าล่าช้า (GWM_NOT_OVERDUE)', () {
            ref.read(demoMatchRepositoryProvider).demoServerConfirmsOverdue = false;
            toast('ค่าเริ่มต้น: กด "ยกเลิกการเดินทาง" จะได้ข้อความอธิบายว่ายังไม่เข้าเงื่อนไข');
          }),
          tool(Icons.social_distance, 'จำลอง: คนขับตั้งระยะเบี่ยงแคบ (300 ม.)', () {
            ref.read(demoTripRepositoryProvider).updateDetourTolerance('demo-trip-me', 300);
            refreshAll();
            toast('ตั้งระยะเบี่ยงเป็น 300 ม.: ผู้สมัครที่ปลายทางไกลจะหายไปจากรายการค้นหา (ถ้าไม่เข้าเกณฑ์ระยะรับส่งด้วย)');
          }, sub: 'ต้องเป็นโหมดคนขับ'),
          tool(Icons.social_distance_outlined, 'จำลอง: คนขับตั้งระยะเบี่ยงกว้าง (2,000 ม.)', () {
            ref.read(demoTripRepositoryProvider).updateDetourTolerance('demo-trip-me', 2000);
            refreshAll();
            toast('ตั้งระยะเบี่ยงเป็น 2,000 ม.: ผู้สมัครที่ปลายทางไกลกว่าจะปรากฏเพิ่มในรายการค้นหา');
          }, sub: 'ต้องเป็นโหมดคนขับ'),
          item('หน้าถึงแล้ว (การ์ดผลกระทบร่วม + สติกเกอร์ขอบคุณ)', Routes.tripArrived('demo-trip-me'),
              sub: 'ต้องมีคู่จับคู่ตอบรับแล้วบนทริปนี้จึงจะเห็นการ์ด CO2 และปุ่มสติกเกอร์'),
          section('รอบ 7 (ขั้น D): ระยะเบี่ยงแม่นยำ (OSRM) และชิป vibe/mood บนการ์ด'),
          SwitchListTile(
            secondary: const Icon(Icons.alt_route),
            title: const Text('เพิ่มผู้สมัคร "แนน" ที่เข้าเกณฑ์ผ่านระยะเบี่ยงเท่านั้น'),
            subtitle: const Text('ต้องเป็นบัญชีคนนั่ง (รถ) ปลายทางของแนนไกลเกินระยะรับส่งปกติ '
                'แต่การกด "ขอติดรถ" จะคำนวณระยะเบี่ยงจริงผ่าน OSRM แล้วส่งไปพร้อมคำขอ'),
            value: matches.showDetourOnlyCandidate,
            onChanged: (v) {
              matches.showDetourOnlyCandidate = v;
              refreshAll();
              toast(v
                  ? 'เพิ่มแนนแล้ว: ไปที่แท็บ "ค้นหา" แล้วลองกดชวนแนนดู (ต้องเป็นบัญชีคนนั่ง)'
                  : 'เอาแนนออกจากรายการค้นหาแล้ว');
            },
          ),
          tool(Icons.wifi_off, 'จำลอง: บริการ OSRM ล้มเหลวในการคำนวณครั้งถัดไป', () {
            ref.read(demoRoutingProvider).failNextRoute = true;
            toast('การชวนครั้งถัดไปที่ต้องคำนวณระยะเบี่ยง (เช่น ชวนแนน) จะขึ้น '
                '"คำนวณระยะเบี่ยงไม่สำเร็จ ลองใหม่อีกครั้ง" แทนที่จะส่งคำขอ');
          }, sub: 'เปิดสวิตช์ "เพิ่มผู้สมัครแนน" ด้านบนก่อน แล้วลองกดชวนแนน'),
          item('รายละเอียดแนน (ดูชิป vibe/mood บนหน้ารายละเอียด)', Routes.candidate(demoDetourOnlyCandidateId),
              sub: 'ต้องเปิดสวิตช์ "เพิ่มผู้สมัครแนน" ด้านบนก่อน'),
          section('บัญชีและความเป็นส่วนตัว'),
          item('ตั้งค่า', Routes.settings),
          item('ความเป็นส่วนตัวและตำแหน่ง', Routes.settingsPrivacy),
          item('ลบบัญชี', Routes.settingsDeleteAccount, sub: 'ในเดโมจะออกจากระบบ แล้วเข้าใหม่ด้วยอะไรก็ได้'),
          section('เครื่องมือเดโม'),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('ล้างทริปปัจจุบัน'),
            subtitle: const Text('เพื่อลองสร้างทริปใหม่'),
            onTap: () {
              ref.read(demoTripRepositoryProvider).clear();
              refreshAll();
              toast('ล้างทริปแล้ว');
            },
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('รีเซ็ตข้อมูลเดโมทั้งหมด'),
            onTap: () {
              ref.read(demoTripRepositoryProvider).reset();
              ref.read(demoMatchRepositoryProvider).reset(DemoScenario.peer);
              ref.read(demoVehicleRepositoryProvider).reset(DemoScenario.peer);
              ref.read(demoRoleRepositoryProvider).reset(DemoScenario.peer);
              ref.read(demoChatRepositoryProvider).reset();
              ref.read(demoSafetyRepositoryProvider).reset();
              ref.read(demoContactRepositoryProvider).reset();
              ref.read(demoShareRepositoryProvider).reset();
              ref.read(demoAvatarRepositoryProvider).reset();
              ref.read(demoReviewRepositoryProvider).reset();
              ref.read(demoLiveLocationRepositoryProvider).frozen.value = false;
              sos.offline.value = false;
              ref.read(demoRoadSnapProvider).mode = DemoSnapMode.accept;
              refreshAll();
              toast('รีเซ็ตแล้ว');
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
