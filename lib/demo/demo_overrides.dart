import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app.dart';
import '../core/config/app_config.dart';
import '../core/platform/external_actions.dart';
import '../core/providers.dart';
import '../core/router/app_router.dart';
import '../features/auth/presentation/auth_providers.dart';
import '../features/avatar/presentation/avatar_providers.dart';
import '../features/chat/presentation/chat_providers.dart';
import '../features/chat/presentation/quick_voice_providers.dart';
import '../features/geo/presentation/geo_providers.dart';
import '../features/matching/domain/match_models.dart';
import '../features/matching/presentation/matching_providers.dart';
import '../features/onboarding/presentation/onboarding_providers.dart';
import '../features/presets/data/preset_storage.dart';
import '../features/presets/presentation/preset_providers.dart';
import '../features/privacy/presentation/consent_providers.dart';
import '../features/profile/presentation/profile_providers.dart';
import '../features/push/presentation/push_providers.dart';
import '../features/reviews/presentation/review_providers.dart';
import '../features/roles/presentation/role_providers.dart';
import '../features/safety/presentation/safety_providers.dart';
import '../features/sharing/presentation/sharing_providers.dart';
import '../features/trip/presentation/trip_lifecycle_providers.dart';
import '../features/trip/presentation/trip_providers.dart';
import '../features/vehicle/presentation/vehicle_providers.dart';
import 'demo_fakes.dart';
import 'demo_fakes_p4.dart';
import 'demo_fakes_r5.dart';
import 'demo_fakes_r7.dart';
import 'demo_fakes_roles.dart';
import 'demo_hub_screen.dart';

final demoTripRepositoryProvider = Provider<DemoTripRepository>((_) => DemoTripRepository());
final demoMatchRepositoryProvider = Provider<DemoMatchRepository>((ref) {
  final trips = ref.watch(demoTripRepositoryProvider);
  final matches = DemoMatchRepository(trips);
  // Q-1: the Driver's trip cannot be cancelled once the Rider boarded.
  trips.hasBoardedRider = (tripId) =>
      matches.matches.any((m) => m.myTripId == tripId && m.iAmDriver && m.boarded && m.status == MatchStatus.accepted);
  trips.hasOpenMatch = (tripId) =>
      matches.matches.any((m) => m.myTripId == tripId && (m.status == MatchStatus.pending || m.status == MatchStatus.accepted));
  return matches;
});
final demoVehicleRepositoryProvider = Provider<DemoVehicleRepository>(
  (ref) => DemoVehicleRepository(ref.watch(demoMatchRepositoryProvider), ref.watch(demoTripRepositoryProvider)),
);
final demoRoleRepositoryProvider = Provider<DemoRoleRepository>(
  (ref) => DemoRoleRepository(
    ref.watch(demoVehicleRepositoryProvider),
    ref.watch(demoTripRepositoryProvider),
    ref.watch(demoMatchRepositoryProvider),
  ),
);
final demoChatRepositoryProvider = Provider<DemoChatRepository>(
  (ref) => DemoChatRepository(ref.watch(demoTripRepositoryProvider), ref.watch(demoMatchRepositoryProvider)),
);
final demoSafetyRepositoryProvider =
    Provider<DemoSafetyRepository>((ref) => DemoSafetyRepository(ref.watch(demoChatRepositoryProvider)));
final demoContactRepositoryProvider = Provider<DemoContactRepository>((_) => DemoContactRepository());
final demoSosRepositoryProvider = Provider<DemoSosRepository>((_) => DemoSosRepository());
final demoShareRepositoryProvider = Provider<DemoTripShareRepository>((_) => DemoTripShareRepository());
final demoLiveLocationRepositoryProvider =
    Provider<DemoLiveLocationRepository>((ref) => DemoLiveLocationRepository(ref.watch(demoMatchRepositoryProvider)));
final demoAvatarRepositoryProvider = Provider<DemoAvatarRepository>((_) => DemoAvatarRepository());
final demoReviewRepositoryProvider =
    Provider<DemoReviewRepository>((ref) => DemoReviewRepository(ref.watch(demoMatchRepositoryProvider)));
final demoPushServiceProvider = Provider<DemoPushService>((_) => DemoPushService());
final demoPushRepositoryProvider = Provider<DemoPushRepository>((_) => DemoPushRepository());
final demoRoadSnapProvider = Provider<DemoRoadSnap>((_) => DemoRoadSnap());

/// US-50 (round 7 Stage D): a named provider (not `.overrideWithValue` inline)
/// so the demo hub can flip `failNextRoute` to show the OSRM-failure-at-
/// request-time retry state (see `DemoRouting`'s doc comment).
final demoRoutingProvider = Provider<DemoRouting>((_) => DemoRouting());

/// US-48(B): a no-op TTS speaker for demo/CI (no platform engine to call, and
/// tests must never depend on real speech synthesis).
class _DemoTtsSpeaker implements TtsSpeaker {
  @override
  Future<void> speak(String text) async {}
}

/// Onboarding is treated as already completed in demo mode.
class _DemoOnboarding extends OnboardingDoneNotifier {
  @override
  bool build() => true;
}

/// Entry point used by main() when DEMO_MODE=true. Never touches Supabase.
/// [extraOverrides] exists for tests (e.g. switching map tiles off).
Future<void> runDemoApp(void Function(Widget) run, {List<Override> extraOverrides = const []}) async {
  final prefs = await SharedPreferences.getInstance();
  run(
    ProviderScope(
      overrides: [
        // A syntactically valid placeholder; nothing connects to it.
        configProvider.overrideWithValue(
          const ConfigReady(url: 'https://demo.invalid', anonKey: 'demo'),
        ),
        sharedPrefsProvider.overrideWithValue(prefs),
        // Saved places stay in memory in the demo (nothing is written to the device).
        presetStorageProvider.overrideWithValue(MemoryPresetStorage()),
        splashDurationProvider.overrideWithValue(const Duration(milliseconds: 2500)),
        onboardingDoneProvider.overrideWith(_DemoOnboarding.new),
        authRepositoryProvider.overrideWithValue(DemoAuthRepository()),
        profileRepositoryProvider.overrideWithValue(DemoProfileRepository()),
        tripRepositoryProvider.overrideWith((ref) => ref.watch(demoTripRepositoryProvider)),
        matchRepositoryProvider.overrideWith((ref) => ref.watch(demoMatchRepositoryProvider)),
        matchFinderRepositoryProvider.overrideWith((ref) => ref.watch(demoMatchRepositoryProvider)),
        vehicleRepositoryProvider.overrideWith((ref) => ref.watch(demoVehicleRepositoryProvider)),
        roleRepositoryProvider.overrideWith((ref) => ref.watch(demoRoleRepositoryProvider)),
        geocodingServiceProvider.overrideWithValue(DemoGeocoding()),
        routingServiceProvider.overrideWith((ref) => ref.watch(demoRoutingProvider)),
        roadSnapServiceProvider.overrideWith((ref) => ref.watch(demoRoadSnapProvider)),
        locationServiceProvider.overrideWith((ref) => DemoLocationService(ref.watch(demoTripRepositoryProvider))),
        chatRepositoryProvider.overrideWith((ref) => ref.watch(demoChatRepositoryProvider)),
        safetyRepositoryProvider.overrideWith((ref) => ref.watch(demoSafetyRepositoryProvider)),
        emergencyContactRepositoryProvider.overrideWith((ref) => ref.watch(demoContactRepositoryProvider)),
        sosRepositoryProvider.overrideWith((ref) => ref.watch(demoSosRepositoryProvider)),
        liveLocationRepositoryProvider.overrideWith((ref) => ref.watch(demoLiveLocationRepositoryProvider)),
        avatarRepositoryProvider.overrideWith((ref) => ref.watch(demoAvatarRepositoryProvider)),
        avatarPickerProvider.overrideWithValue(const DemoAvatarPicker()),
        reviewRepositoryProvider.overrideWith((ref) => ref.watch(demoReviewRepositoryProvider)),
        tripShareRepositoryProvider.overrideWith((ref) => ref.watch(demoShareRepositoryProvider)),
        // The demo pretends a share page exists so "stop sharing" can be seen.
        shareWebBaseUrlProvider.overrideWithValue('https://share.gowithme.example'),
        accountRepositoryProvider.overrideWithValue(DemoAccountRepository()),
        pushServiceProvider.overrideWith((ref) => ref.watch(demoPushServiceProvider)),
        pushRepositoryProvider.overrideWith((ref) => ref.watch(demoPushRepositoryProvider)),
        externalActionsProvider.overrideWithValue(DemoExternalActions()),
        partnerPollIntervalProvider.overrideWithValue(const Duration(seconds: 5)),
        // US-48(B): never touch a real platform TTS engine in the demo (web build has none anyway).
        ttsSpeakerProvider.overrideWithValue(_DemoTtsSpeaker()),
        ...extraOverrides,
        consentRepositoryProvider.overrideWithValue(DemoConsentRepository()),
        extraRoutesProvider.overrideWithValue([
          GoRoute(path: demoHubPath, builder: (_, _) => const DemoHubScreen()),
        ]),
      ],
      child: const _DemoShell(),
    ),
  );
}

/// Wraps the real app with a small tappable "DEMO" pill that opens the hub.
class _DemoShell extends ConsumerWidget {
  const _DemoShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          const GoWithMeApp(),
          const _DemoToast(),
          Align(
            alignment: Alignment.topCenter,
            child: GestureDetector(
              onTap: () => ref.read(routerProvider).push(demoHubPath),
              child: Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFB45309),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'DEMO',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows what the platform would have done (dial, SMS, share sheet).
class _DemoToast extends StatelessWidget {
  const _DemoToast();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: demoToast,
      builder: (context, text, _) {
        if (text == null) return const SizedBox.shrink();
        return Positioned(
          left: 12,
          right: 12,
          bottom: 96,
          child: Material(
            color: const Color(0xFF0B2545),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => demoToast.value = null,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '$text\n(แตะเพื่อปิด)',
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
