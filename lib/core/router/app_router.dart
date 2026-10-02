import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_providers.dart';
import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/auth/presentation/sign_up_screen.dart';
import '../../features/auth/presentation/verify_email_screen.dart';
import '../../features/avatar/presentation/avatar_screens.dart';
import '../../features/chat/presentation/chat_room_screen.dart';
import '../../features/chat/presentation/chats_tab.dart';
import '../../features/home/presentation/home_tab.dart';
import '../../features/matching/presentation/candidate_detail_screen.dart';
import '../../features/matching/presentation/match_detail_screen.dart';
import '../../features/matching/presentation/nearby_tab.dart';
import '../../features/matching/presentation/pickup_screen.dart';
import '../../features/matching/presentation/requests_screen.dart';
import '../../features/onboarding/presentation/config_error_screen.dart';
import '../../features/onboarding/presentation/onboarding_providers.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/onboarding/presentation/splash_screen.dart';
import '../../features/presets/domain/preset.dart';
import '../../features/presets/presentation/preset_screens.dart';
import '../../features/privacy/presentation/account_screens.dart';
import '../../features/privacy/presentation/policy_screen.dart';
import '../../features/profile/presentation/gender_settings_screen.dart';
import '../../features/profile/presentation/me_tab.dart';
import '../../features/profile/presentation/profile_providers.dart';
import '../../features/profile/presentation/profile_setup_screen.dart';
import '../../features/push/presentation/notification_settings_screen.dart';
import '../../features/push/presentation/push_providers.dart';
import '../../features/reviews/presentation/review_screens.dart';
import '../../features/roles/presentation/driver_register_screen.dart';
import '../../features/safety/presentation/contacts_screens.dart';
import '../../features/safety/presentation/safety_screens.dart';
import '../../features/safety/presentation/sos_screen.dart';
import '../../features/sharing/presentation/share_trip_screen.dart';
import '../../features/shell/presentation/home_shell.dart';
import '../../features/trip/presentation/create_trip_step1_screen.dart';
import '../../features/trip/presentation/create_trip_step2_screen.dart';
import '../../features/trip/presentation/create_trip_step3_screen.dart';
import '../../features/trip/presentation/trip_detail_screen.dart';
import '../../features/trip/presentation/trip_tone.dart';
import '../../features/trip/presentation/trips_tab.dart';
import '../../features/trip/presentation/unified_ride_screen.dart';
import '../../features/vehicle/presentation/vehicle_screen.dart';
import '../config/app_config.dart';
import '../l10n/strings.dart';
import '../providers.dart';
import '../theme/presentation/theme_settings_screen.dart';
import 'redirect.dart';

/// Bridges Riverpod state changes to GoRouter's refreshListenable.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    for (final p in <ProviderListenable<Object?>>[
      authUserProvider,
      onboardingDoneProvider,
      profileGateProvider,
      splashElapsedProvider,
    ]) {
      ref.listen(p, (_, _) => notifyListeners());
    }
  }
}

/// Extra top-level routes injected by optional modules (e.g. lib/demo).
/// Empty in production.
final extraRoutesProvider = Provider<List<RouteBase>>((_) => const []);

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  RedirectState snapshot() {
    final auth = ref.read(authUserProvider);
    final splash = ref.read(splashElapsedProvider);
    final gate = ref.read(profileGateProvider);
    final user = auth.value;
    return RedirectState(
      configReady: ref.read(configProvider) is ConfigReady,
      // Profile is only awaited for a confirmed, signed-in user.
      booting: auth.isLoading ||
          splash.isLoading ||
          (user != null && user.emailConfirmed && gate == ProfileGate.loading),
      onboardingDone: ref.read(onboardingDoneProvider),
      user: user,
      profileSetupDone: gate != ProfileGate.needsSetup,
    );
  }

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final target = computeRedirect(state.uri.path, snapshot());
      // G.1.2 (US-42): a push tapped while signed out stashes its
      // destination here; consume it once, right after the guard chain
      // would otherwise land the user on Home post sign-in.
      if (target == Routes.home) {
        final pending = ref.read(pendingDeepLinkProvider);
        if (pending != null) {
          ref.read(pendingDeepLinkProvider.notifier).state = null;
          return pending;
        }
      }
      return target;
    },
    routes: [
      ...ref.read(extraRoutesProvider),
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.configError, builder: (_, _) => const ConfigErrorScreen()),
      GoRoute(path: Routes.onboarding, builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: Routes.signIn, builder: (_, _) => const SignInScreen()),
      GoRoute(path: Routes.signUp, builder: (_, _) => const SignUpScreen()),
      GoRoute(
        path: Routes.verifyEmail,
        builder: (_, state) => VerifyEmailScreen(email: state.uri.queryParameters['email']),
      ),
      GoRoute(
        path: Routes.policy,
        builder: (_, _) => const PolicyScreen(title: S.policy, body: policyBody),
      ),
      GoRoute(
        path: Routes.terms,
        builder: (_, _) => const PolicyScreen(title: S.terms, body: termsBody),
      ),
      GoRoute(path: Routes.setupProfile, builder: (_, _) => const ProfileSetupScreen()),
      GoRoute(path: Routes.meEdit, builder: (_, _) => const ProfileSetupScreen(editMode: true)),
      GoRoute(path: Routes.tripNew, builder: (_, _) => const CreateTripStep1Screen()),
      GoRoute(path: Routes.tripOptions, builder: (_, _) => const CreateTripStep2Screen()),
      GoRoute(path: Routes.tripConfirm, builder: (_, _) => const CreateTripStep3Screen()),
      // Registered before the :candidateTripId pattern so it is not shadowed.
      GoRoute(path: Routes.nearbyRequests, builder: (_, _) => const TripRoleTone.active(child: RequestsScreen())),
      GoRoute(
        path: Routes.candidatePattern,
        builder: (_, s) => TripRoleTone.active(child: CandidateDetailScreen(tripId: s.pathParameters['candidateTripId']!)),
      ),
      GoRoute(
        path: Routes.driverRegister,
        builder: (_, s) => DriverRegisterScreen(returnTo: s.uri.queryParameters['returnTo']),
      ),
      GoRoute(path: Routes.vehicle, builder: (_, s) => VehicleScreen(returnTo: s.uri.queryParameters['returnTo'])),
      GoRoute(path: Routes.mePhoto, builder: (_, _) => const AvatarScreen()),
      GoRoute(path: Routes.mePlaces, builder: (_, _) => const PresetSummaryScreen()),
      GoRoute(
        path: Routes.mePlacePattern,
        // Unknown kind -> summary (never a blank page).
        redirect: (_, s) => PresetKind.fromDb(s.pathParameters['kind']) == null ? Routes.mePlaces : null,
        builder: (_, s) => PresetEditScreen(kind: PresetKind.fromDb(s.pathParameters['kind']) ?? PresetKind.home),
      ),
      GoRoute(path: Routes.meReviews, builder: (_, _) => const MyReviewsScreen()),
      GoRoute(
        path: Routes.reportPhotoPattern,
        builder: (_, s) => ReportPhotoScreen(
          userId: s.pathParameters['userId']!,
          matchId: s.uri.queryParameters['match'],
          name: s.uri.queryParameters['name'],
        ),
      ),
      GoRoute(
        path: Routes.livePattern,
        // Round 6: the live map is the same UnifiedRideScreen (old guard kept inside).
        builder: (_, s) => TripRoleTone.match(
          s.pathParameters['matchId']!,
          child: UnifiedRideScreen(matchId: s.pathParameters['matchId']!),
        ),
      ),
      GoRoute(
        path: Routes.reviewPattern,
        builder: (_, s) => TripRoleTone.match(s.pathParameters['matchId']!, child: ReviewScreen(matchId: s.pathParameters['matchId']!)),
      ),
      GoRoute(
        path: Routes.reviewDonePattern,
        builder: (_, s) => TripRoleTone.match(s.pathParameters['matchId']!, child: ReviewDoneScreen(matchId: s.pathParameters['matchId']!)),
      ),
      GoRoute(
        path: Routes.pickupPattern,
        builder: (_, s) => TripRoleTone.match(s.pathParameters['matchId']!, child: PickupScreen(matchId: s.pathParameters['matchId']!)),
      ),
      GoRoute(
        path: Routes.matchPattern,
        builder: (_, s) => TripRoleTone.match(s.pathParameters['matchId']!, child: MatchDetailScreen(matchId: s.pathParameters['matchId']!)),
      ),
      GoRoute(
        path: Routes.chatPattern,
        builder: (_, s) => TripRoleTone.match(
          s.pathParameters['matchId']!,
          // Match Moment "ทักทายนัดจุดรับ": a ready-made sentence in the message box (never sent by itself).
          child: ChatRoomScreen(matchId: s.pathParameters['matchId']!, initialText: s.extra is String ? s.extra as String : null),
        ),
      ),
      // Before `/trips/:tripId` so "active" is not read as a trip id.
      GoRoute(
        path: Routes.tripActiveNow,
        builder: (_, _) => const TripRoleTone.active(child: UnifiedRideScreen()),
      ),
      GoRoute(
        path: Routes.tripDetailPattern,
        builder: (_, s) => TripRoleTone.trip(s.pathParameters['tripId']!, child: TripDetailScreen(tripId: s.pathParameters['tripId']!)),
      ),
      GoRoute(
        // Old deep link: alias of /trips/active.
        path: Routes.tripActivePattern,
        redirect: (_, _) => Routes.tripActiveNow,
        builder: (_, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: Routes.tripArrivedPattern,
        // Round 6: S-22 is the Arrived state of the unified ride screen.
        builder: (_, s) => TripRoleTone.trip(
          s.pathParameters['tripId']!,
          child: UnifiedRideScreen(tripId: s.pathParameters['tripId']!, arrived: true),
        ),
      ),
      GoRoute(
        path: Routes.tripSharePattern,
        builder: (_, s) => TripRoleTone.trip(s.pathParameters['tripId']!, child: ShareTripScreen(tripId: s.pathParameters['tripId']!)),
      ),
      GoRoute(
        path: Routes.sos,
        builder: (_, s) {
          final trip = s.uri.queryParameters['trip'];
          final screen = SosScreen(tripId: trip, fromChat: s.uri.queryParameters['source'] == 'chat');
          return trip == null ? TripRoleTone.active(child: screen) : TripRoleTone.trip(trip, child: screen);
        },
      ),
      GoRoute(path: Routes.safety, builder: (_, _) => const SafetyScreen()),
      GoRoute(path: Routes.safetyContacts, builder: (_, _) => const ContactsScreen()),
      GoRoute(
        path: Routes.safetyContactEdit,
        builder: (_, s) => ContactEditScreen(contactId: s.uri.queryParameters['id']),
      ),
      GoRoute(
        path: Routes.reportPattern,
        builder: (_, s) => ReportScreen(
          userId: s.pathParameters['userId']!,
          matchId: s.uri.queryParameters['match'],
          name: s.uri.queryParameters['name'],
        ),
      ),
      GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen()),
      GoRoute(path: Routes.settingsPrivacy, builder: (_, _) => const PrivacySettingsScreen()),
      GoRoute(path: Routes.settingsNotifications, builder: (_, _) => const NotificationSettingsScreen()),
      GoRoute(path: Routes.settingsDeleteAccount, builder: (_, _) => const DeleteAccountScreen()),
      GoRoute(path: Routes.settingsGender, builder: (_, _) => const GenderSettingsScreen()),
      GoRoute(path: Routes.settingsTheme, builder: (_, _) => const ThemeSettingsScreen()),
      GoRoute(path: Routes.blocked, builder: (_, _) => const BlockedUsersScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.home, builder: (_, _) => const HomeTab()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.nearby, builder: (_, s) => NearbyTab(initialView: s.uri.queryParameters['view'])),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.chats, builder: (_, _) => const ChatsTab()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.trips, builder: (_, _) => const TripsTab()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.me, builder: (_, _) => const MeTab()),
          ]),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
