import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gowithme/app.dart';
import 'package:gowithme/core/config/app_config.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/error/result.dart';
import 'package:gowithme/core/notify/local_notifier.dart';
import 'package:gowithme/core/platform/external_actions.dart';
import 'package:gowithme/core/providers.dart';
import 'package:gowithme/features/auth/domain/auth_repository.dart';
import 'package:gowithme/features/auth/presentation/auth_providers.dart';
import 'package:gowithme/features/avatar/domain/avatar_processing.dart';
import 'package:gowithme/features/avatar/presentation/avatar_providers.dart';
import 'package:gowithme/features/chat/presentation/chat_providers.dart';
import 'package:gowithme/features/geo/presentation/geo_providers.dart';
import 'package:gowithme/features/matching/presentation/matching_providers.dart';
import 'package:gowithme/features/presets/data/preset_storage.dart';
import 'package:gowithme/features/presets/presentation/preset_providers.dart';
import 'package:gowithme/features/privacy/presentation/consent_providers.dart';
import 'package:gowithme/features/profile/presentation/profile_providers.dart';
import 'package:gowithme/features/push/domain/push_repository.dart';
import 'package:gowithme/features/push/presentation/push_providers.dart';
import 'package:gowithme/features/push/presentation/push_service.dart';
import 'package:gowithme/features/reviews/presentation/review_providers.dart';
import 'package:gowithme/features/roles/presentation/role_providers.dart';
import 'package:gowithme/features/safety/presentation/safety_providers.dart';
import 'package:gowithme/features/sharing/presentation/sharing_providers.dart';
import 'package:gowithme/features/trip/presentation/trip_lifecycle_providers.dart';
import 'package:gowithme/features/trip/presentation/trip_providers.dart';
import 'package:gowithme/features/vehicle/presentation/vehicle_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_repos.dart';
import 'fake_repos_p4.dart';
import 'fake_repos_r5.dart';
import 'fake_repos_roles.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AuthUser? initial}) : _user = initial;

  AuthUser? _user;
  final _controller = StreamController<AuthUser?>.broadcast();
  AppFailure? signInFailure;
  AppFailure? signUpFailure;
  bool needsVerification = true;
  int resendCalls = 0;
  String? lastSignUpName;

  void _emit(AuthUser? u) {
    _user = u;
    _controller.add(u);
  }

  @override
  Stream<AuthUser?> authChanges() async* {
    yield _user;
    yield* _controller.stream;
  }

  @override
  Future<Result<SignUpOutcome>> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    lastSignUpName = displayName;
    if (signUpFailure != null) return Err(signUpFailure!);
    return Ok(SignUpOutcome(needsEmailVerification: needsVerification));
  }

  @override
  Future<Result<void>> signIn({required String email, required String password}) async {
    if (signInFailure != null) return Err(signInFailure!);
    _emit(AuthUser(id: 'u1', email: email, displayName: 'มิ้นท์', emailConfirmed: true));
    return const Ok(null);
  }

  @override
  Future<Result<void>> signOut() async {
    _emit(null);
    return const Ok(null);
  }

  @override
  Future<Result<void>> resendVerification(String email) async {
    resendCalls++;
    return const Ok(null);
  }
}

Future<Widget> buildTestApp({
  ConfigState config = const ConfigReady(url: 'https://x.supabase.co', anonKey: 'k'),
  FakeAuthRepository? repo,
  Map<String, Object> prefs = const {},
  Fakes? fakes,
}) async {
  final f = fakes ?? Fakes();
  // Round 6: the deck is the default view; the older widget tests were written for the list view, so the harness
  // opens the list unless a test asks for the deck (`'gwm.nearbyView': 'deck'`).
  // Round 7 (US-42): `PushTapHost` offers the G-1 permission sheet automatically on
  // the first sign-in of a session; pre-existing tests never expect that dialog to
  // pop up and steal subsequent taps, so the harness marks it "already asked" by
  // default (push tests override this back to unseen explicitly).
  SharedPreferences.setMockInitialValues({
    'gwm.nearbyView': 'list',
    'push.permission_asked': true,
    ...prefs,
  });
  final sp = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      configProvider.overrideWithValue(config),
      sharedPrefsProvider.overrideWithValue(sp),
      splashDurationProvider.overrideWithValue(Duration.zero),
      if (repo != null) authRepositoryProvider.overrideWithValue(repo),
      profileRepositoryProvider.overrideWithValue(f.profile),
      tripRepositoryProvider.overrideWithValue(f.trips),
      matchFinderRepositoryProvider.overrideWithValue(f.finder),
      matchRepositoryProvider.overrideWithValue(f.matches),
      geocodingServiceProvider.overrideWithValue(f.geocoding),
      routingServiceProvider.overrideWithValue(f.routing),
      locationServiceProvider.overrideWithValue(f.location),
      consentRepositoryProvider.overrideWithValue(f.consent),
      mapTilesEnabledProvider.overrideWithValue(false),
      chatRepositoryProvider.overrideWithValue(f.chat),
      safetyRepositoryProvider.overrideWithValue(f.safety),
      emergencyContactRepositoryProvider.overrideWithValue(f.contacts),
      sosRepositoryProvider.overrideWithValue(f.sos),
      sosAutoRetryProvider.overrideWithValue(false),
      liveLocationRepositoryProvider.overrideWithValue(f.live),
      avatarRepositoryProvider.overrideWithValue(f.avatars),
      avatarPickerProvider.overrideWithValue(f.picker),
      avatarProcessorProvider.overrideWithValue((b) async => processAvatarSync(b)),
      reviewRepositoryProvider.overrideWithValue(f.reviews),
      tripShareRepositoryProvider.overrideWithValue(f.shares),
      accountRepositoryProvider.overrideWithValue(f.account),
      externalActionsProvider.overrideWithValue(f.actions),
      vehicleRepositoryProvider.overrideWithValue(f.vehicles),
      roleRepositoryProvider.overrideWithValue(f.roles),
      localNotifierProvider.overrideWithValue(f.notifier),
      presetStorageProvider.overrideWithValue(f.presets),
      pushServiceProvider.overrideWithValue(const NoopPushService()),
      pushRepositoryProvider.overrideWithValue(const UnavailablePushRepository()),
      if (f.shareBaseUrl != null) shareWebBaseUrlProvider.overrideWithValue(f.shareBaseUrl!),
      ...f.overrides,
    ],
    child: const GoWithMeApp(useGoogleFonts: false),
  );
}

/// Bundle of fake backends so tests can tweak them before/after pumping.
class Fakes {
  Fakes({String profileName = 'มิ้นท์'}) : profile = FakeProfileRepository(name: profileName);

  final FakeProfileRepository profile;
  final trips = FakeTripRepository();
  final finder = FakeMatchFinderRepository();
  final matches = FakeMatchRepository();
  final geocoding = FakeGeocoding();
  final routing = FakeRouting();
  final location = FakeLocationService();
  final consent = FakeConsentRepository();
  final chat = FakeChatRepository();
  final safety = FakeSafetyRepository();
  final contacts = FakeContactRepository();
  final sos = FakeSosRepository();
  final live = FakeLiveLocationRepository();
  final shares = FakeTripShareRepository();
  final account = FakeAccountRepository();
  final actions = FakeExternalActions();
  final vehicles = FakeVehicleRepository();
  final roles = FakeRoleRepository();
  final notifier = FakeLocalNotifier();
  final avatars = FakeAvatarRepository();
  final picker = FakePicker(const PickOutcome.cancelled());
  final reviews = FakeReviewRepository();
  final presets = MemoryPresetStorage();

  /// Non-null = a share web page exists, so backend links are created.
  String? shareBaseUrl;

  /// Extra provider overrides for one test (e.g. the Home-destination matcher, round 6).
  final overrides = <Override>[];
}

/// Records notices; lets tests assert the payload carries no personal data.
class FakeLocalNotifier implements LocalNotifier {
  final shown = <LocalNotice>[];

  @override
  Future<void> show(LocalNotice notice) async => shown.add(notice);
}
