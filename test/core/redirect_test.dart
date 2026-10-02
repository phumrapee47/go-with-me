import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/router/redirect.dart';
import 'package:gowithme/features/auth/domain/auth_repository.dart';

const _user = AuthUser(id: 'u', email: 'a@b.co', displayName: 'A', emailConfirmed: true);

RedirectState st({
  bool config = true,
  bool booting = false,
  bool onboarded = true,
  AuthUser? user,
  bool setup = true,
}) =>
    RedirectState(
      configReady: config,
      booting: booting,
      onboardingDone: onboarded,
      user: user,
      profileSetupDone: setup,
    );

void main() {
  test('no config -> config-error and nothing else', () {
    expect(computeRedirect('/home', st(config: false, user: _user)), Routes.configError);
    expect(computeRedirect(Routes.configError, st(config: false)), isNull);
  });

  test('booting stays on splash', () {
    expect(computeRedirect('/home', st(booting: true)), Routes.splash);
    expect(computeRedirect(Routes.splash, st(booting: true)), isNull);
  });

  test('signed out: first run -> onboarding, else sign-in', () {
    expect(computeRedirect(Routes.splash, st(onboarded: false)), Routes.onboarding);
    expect(computeRedirect(Routes.splash, st()), Routes.signIn);
    expect(computeRedirect(Routes.onboarding, st()), Routes.signIn);
    expect(computeRedirect(Routes.home, st()), Routes.signIn);
  });

  test('signed out may open auth and legal pages', () {
    expect(computeRedirect(Routes.signUp, st()), isNull);
    expect(computeRedirect(Routes.verifyEmail, st()), isNull);
    expect(computeRedirect(Routes.policy, st()), isNull);
    expect(computeRedirect(Routes.terms, st(onboarded: false)), isNull);
  });

  test('unconfirmed email is held at verify-email', () {
    const u = AuthUser(id: 'u', email: 'a@b.co', displayName: 'A', emailConfirmed: false);
    expect(computeRedirect(Routes.home, st(user: u)), Routes.verifyEmail);
    expect(computeRedirect(Routes.verifyEmail, st(user: u)), isNull);
  });

  test('confirmed but no profile setup -> setup', () {
    expect(computeRedirect(Routes.home, st(user: _user, setup: false)), Routes.setupProfile);
    expect(computeRedirect(Routes.setupProfile, st(user: _user, setup: false)), isNull);
  });

  test('signed in skips entry screens', () {
    for (final p in [Routes.splash, Routes.onboarding, Routes.signIn, Routes.setupProfile]) {
      expect(computeRedirect(p, st(user: _user)), Routes.home);
    }
    expect(computeRedirect(Routes.trips, st(user: _user)), isNull);
  });
}
