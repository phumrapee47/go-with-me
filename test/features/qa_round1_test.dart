import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gowithme/core/config/app_constants.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/error/failure_messages.dart';
import 'package:gowithme/core/l10n/strings.dart';
import 'package:gowithme/core/router/redirect.dart';
import 'package:gowithme/core/widgets/initials_avatar.dart';
import 'package:gowithme/features/matching/domain/match_models.dart';
import 'package:gowithme/features/profile/data/supabase_profile_repository.dart';

import '../support/fakes.dart';
import '../support/p4_helpers.dart';

String _location(WidgetTester tester) {
  final ctx = tester.element(find.byType(Scaffold).first);
  return GoRouter.of(ctx).routerDelegate.currentConfiguration.uri.toString();
}

void main() {
  group('T5.13 Me tab badges come from verifications', () {
    // Round 9 (US-6/T2): organization badges are never shown anywhere anymore, and the
    // remaining email/phone badges are merged into a single "ยืนยันตัวตนแล้ว" pill
    // (GlobalVerifiedBadge) instead of one pill per badge kind.
    testWidgets('email only: shows the merged verified badge, no organisation badge', (tester) async {
      final f = await openApp(tester, Fakes()..profile.badges = const [VerificationBadge(kind: 'email')]);
      await tester.tap(find.text(S.tabMe));
      await tester.pumpAndSettle();
      expect(find.text('ยืนยันตัวตนแล้ว'), findsOneWidget);
      expect(find.textContaining('องค์กร'), findsNothing);
      expect(f.profile.badges, hasLength(1));
    });

    testWidgets('with an organisation badge: only the merged verified badge is shown, never the org one', (tester) async {
      await openApp(
        tester,
        Fakes()
          ..profile.badges = const [
            VerificationBadge(kind: 'email'),
            VerificationBadge(kind: 'organization', orgName: 'สถาบันการศึกษา (.ac.th)'),
          ],
      );
      await tester.tap(find.text(S.tabMe));
      await tester.pumpAndSettle();
      expect(find.text('ยืนยันตัวตนแล้ว'), findsOneWidget);
      expect(find.textContaining('องค์กร'), findsNothing);
    });

    testWidgets('no verification rows: never claims a badge', (tester) async {
      await openApp(tester, Fakes()..profile.badges = const []);
      await tester.tap(find.text(S.tabMe));
      await tester.pumpAndSettle();
      expect(find.text('ยืนยันอีเมลแล้ว'), findsNothing);
      expect(find.text('ยังไม่ยืนยันตัวตน'), findsOneWidget);
    });

    test('parseOwnBadges maps rows, embeds org_name and orders email, organization, phone', () {
      final badges = parseOwnBadges([
        {'kind': 'phone', 'is_mock': true, 'org_suffix': null, 'org_domains': null},
        {'kind': 'organization', 'is_mock': false, 'org_suffix': 'ac.th', 'org_domains': {'org_name': 'มหาวิทยาลัย'}},
        {'kind': 'email', 'is_mock': false, 'org_suffix': null, 'org_domains': null},
        {'no_kind': true},
      ]);
      expect(badges.map((b) => b.kind), ['email', 'organization', 'phone']);
      expect(badges[1].orgName, 'มหาวิทยาลัย');
      expect(badges[1].label, 'องค์กร: มหาวิทยาลัย');
      expect(badges[2].isMock, isTrue);
      expect(parseOwnBadges(const []), isEmpty);
    });

    test('organisation badge label falls back when the org name is unknown', () {
      expect(const VerificationBadge(kind: 'organization').label, 'ยืนยันองค์กรแล้ว');
      expect(parseBadges([
        {'kind': 'organization', 'org_name': 'X'}
      ]).single.label, 'องค์กร: X');
    });
  });

  group('T5.16 initials avatar', () {
    test('avatarInitial', () {
      expect(avatarInitial('มิ้นท์'), 'มิ้'); // first grapheme cluster (base + vowel + tone mark)
      expect(avatarInitial('  alice'), 'A');
      expect(avatarInitial(''), '?');
      expect(avatarInitial('   '), '?');
    });

    testWidgets('widget shows the initial', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AvatarInitial(name: 'bob'))));
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('Me tab uses the initials avatar and has no dead "upload photo" control', (tester) async {
      await openApp(tester, Fakes(profileName: 'มิ้นท์'));
      await tester.tap(find.text(S.tabMe));
      await tester.pumpAndSettle();
      expect(find.byType(AvatarInitial), findsOneWidget);
      expect(find.text('มิ้'), findsOneWidget);
      expect(find.textContaining('อัปโหลดรูป'), findsNothing);
      expect(find.textContaining('เปลี่ยนรูป'), findsNothing);
    });
  });

  group('T5.17 live push interval config', () {
    test('default 15 s, clamped to 15-30 s', () {
      expect(AppConstants.livePushInterval(), const Duration(seconds: 15));
      expect(AppConstants.livePushInterval(1), const Duration(seconds: 15));
      expect(AppConstants.livePushInterval(20), const Duration(seconds: 20));
      expect(AppConstants.livePushInterval(999), const Duration(seconds: 30));
    });
  });

  group('T5.11 / T5.12 error messages', () {
    test('signup rejected by the server trigger maps to a Thai message, not the raw text', () {
      final msg = failureMessage(const AppFailure(FailureCode.signupRequirements));
      expect(msg, 'กรุณายืนยันอายุ 18 ปีขึ้นไปและยอมรับนโยบาย');
      expect(msg.toLowerCase(), isNot(contains('database')));
    });

    test('deleted account sign-in message', () {
      expect(failureMessage(const AppFailure(FailureCode.accountDeleted)), contains('ถูกลบแล้ว'));
    });
  });

  group('T5.18 sign-out and the back stack (US-3 AC3)', () {
    testWidgets('after sign-out, back does not return to a screen that needs login', (tester) async {
      await openApp(tester, Fakes());
      await tester.tap(find.text(S.tabMe));
      await tester.pumpAndSettle();
      // Build some history first: Me -> settings.
      await goTo(tester, Routes.settings);
      await goBack(tester);
      expect(_location(tester), isNot(Routes.signIn));

      await tester.scrollUntilVisible(find.text(S.signOut), 200);
      await tester.tap(find.text(S.signOut));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.signOut).last); // confirm in the dialog
      await tester.pumpAndSettle();

      expect(_location(tester), Routes.signIn);
      expect(find.text(S.noAccount), findsOneWidget);
      expect(find.text(S.homeGreeting), findsNothing);

      // System back (Android) repeatedly: never reveals the home shell or any authenticated page.
      for (var i = 0; i < 3; i++) {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text(S.homeGreeting), findsNothing);
        expect(find.text(S.tabMe), findsNothing);
      }
    });

    testWidgets('after sign-out, opening a protected route is redirected to sign-in', (tester) async {
      await openApp(tester, Fakes());
      await tester.tap(find.text(S.tabMe));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(S.signOut), 200);
      await tester.tap(find.text(S.signOut));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.signOut).last);
      await tester.pumpAndSettle();
      expect(_location(tester), Routes.signIn);

      await goTo(tester, Routes.settings);
      expect(_location(tester), Routes.signIn);
      await goTo(tester, Routes.tripActive('trip-1'));
      expect(_location(tester), Routes.signIn);
      expect(find.text(S.homeGreeting), findsNothing);
    });
  });
}
