import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/config/app_config.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/l10n/strings.dart';
import 'package:gowithme/features/auth/domain/auth_repository.dart';

import '../support/fakes.dart';

const _confirmed = AuthUser(id: 'u1', email: 'a@b.co', displayName: 'มิ้นท์', emailConfirmed: true);

void main() {
  testWidgets('missing config shows setup screen instead of crashing', (tester) async {
    await tester.pumpWidget(
      await buildTestApp(config: const ConfigProblem(ConfigIssue.missing)),
    );
    await tester.pumpAndSettle();
    expect(find.text(S.configErrorTitle), findsOneWidget);
  });

  testWidgets('first run shows onboarding, finishing goes to sign-in', (tester) async {
    await tester.pumpWidget(await buildTestApp(repo: FakeAuthRepository()));
    await tester.pumpAndSettle();
    expect(find.text(S.onboard1Title), findsOneWidget);

    await tester.tap(find.text(S.next));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.next));
    await tester.pumpAndSettle();
    expect(find.text(S.onboard3Title), findsOneWidget);
    await tester.tap(find.text(S.onboardStart));
    await tester.pumpAndSettle();
    expect(find.text(S.signIn), findsWidgets);
    expect(find.text(S.noAccount), findsOneWidget);
  });

  testWidgets('skip on onboarding goes to sign-in', (tester) async {
    await tester.pumpWidget(await buildTestApp(repo: FakeAuthRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.skip));
    await tester.pumpAndSettle();
    expect(find.text(S.noAccount), findsOneWidget);
  });

  testWidgets('restored session lands on home with 5 tabs', (tester) async {
    await tester.pumpWidget(await buildTestApp(
      repo: FakeAuthRepository(initial: _confirmed),
      prefs: {'onboarding_done': true},
    ));
    await tester.pumpAndSettle();
    expect(find.text(S.homeGreeting), findsOneWidget);
    for (final l in [S.tabHome, S.tabNearby, S.tabChats, S.tabTrips, S.tabMe]) {
      expect(find.text(l), findsOneWidget);
    }
    await tester.tap(find.text(S.tabMe));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(S.signOut), 200);
    expect(find.text(S.signOut), findsOneWidget);
  });

  testWidgets('wrong credentials show a generic error and keep the email', (tester) async {
    final repo = FakeAuthRepository()
      ..signInFailure = const AppFailure(FailureCode.authInvalidCredentials);
    await tester.pumpWidget(await buildTestApp(repo: repo, prefs: {'onboarding_done': true}));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.co');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrongpass');
    await tester.tap(find.widgetWithText(FilledButton, S.signIn));
    await tester.pumpAndSettle();

    expect(find.text('อีเมลหรือรหัสผ่านไม่ถูกต้อง'), findsOneWidget);
    expect(find.text('a@b.co'), findsOneWidget);
    expect(find.text('wrongpass'), findsNothing);
  });

  testWidgets('sign-up needs 18+ and consent, then shows verify-email', (tester) async {
    final repo = FakeAuthRepository();
    await tester.pumpWidget(await buildTestApp(repo: repo, prefs: {'onboarding_done': true}));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.noAccount));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'มิ้นท์');
    await tester.enterText(find.byType(TextFormField).at(1), 'a@b.co');
    await tester.enterText(find.byType(TextFormField).at(2), 'password123');
    await tester.pump();

    final submit = find.widgetWithText(FilledButton, S.signUp);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.ensureVisible(find.text(S.adultLabel));
    await tester.tap(find.text(S.adultLabel));
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.ensureVisible(find.textContaining(S.consentPrefix));
    await tester.tap(find.textContaining(S.consentPrefix));
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);

    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(repo.lastSignUpName, 'มิ้นท์');
    expect(find.text(S.verifyTitle), findsOneWidget);
    expect(find.text('a@b.co'), findsOneWidget);

    await tester.tap(find.textContaining(S.verifyResend));
    await tester.pump();
    expect(repo.resendCalls, 1);
    // Cooldown disables a second resend.
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox()); // dispose the cooldown timer
  });

  testWidgets('duplicate email error is shown under the email field', (tester) async {
    final repo = FakeAuthRepository()
      ..signUpFailure = const AppFailure(FailureCode.authEmailTaken, field: 'email');
    await tester.pumpWidget(await buildTestApp(repo: repo, prefs: {'onboarding_done': true}));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.noAccount));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'x');
    await tester.enterText(find.byType(TextFormField).at(1), 'a@b.co');
    await tester.enterText(find.byType(TextFormField).at(2), 'password123');
    await tester.ensureVisible(find.text(S.adultLabel));
    await tester.tap(find.text(S.adultLabel));
    await tester.ensureVisible(find.textContaining(S.consentPrefix));
    await tester.tap(find.textContaining(S.consentPrefix));
    await tester.pump();
    final submit = find.widgetWithText(FilledButton, S.signUp);
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.textContaining('อีเมลนี้มีบัญชีอยู่แล้ว'), findsOneWidget);
  });

  testWidgets('profile without a display name is sent to setup, saving goes home', (tester) async {
    final fakes = Fakes(profileName: '');
    await tester.pumpWidget(await buildTestApp(
      repo: FakeAuthRepository(initial: _confirmed),
      prefs: {'onboarding_done': true},
      fakes: fakes,
    ));
    await tester.pumpAndSettle();
    expect(find.text(S.setupTitle), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'มิ้นท์');
    await tester.tap(find.text(S.setupDone));
    await tester.pumpAndSettle();
    expect(fakes.profile.updates, 1);
    expect(find.text(S.homeGreeting), findsOneWidget);
  });

  testWidgets('profile with a name skips setup (no local flag involved)', (tester) async {
    await tester.pumpWidget(await buildTestApp(
      repo: FakeAuthRepository(initial: _confirmed),
      prefs: {'onboarding_done': true},
    ));
    await tester.pumpAndSettle();
    expect(find.text(S.setupTitle), findsNothing);
    expect(find.text(S.homeGreeting), findsOneWidget);
  });
}
