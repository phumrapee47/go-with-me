import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/l10n/strings_dual.dart';
import '../../../core/l10n/strings_p4.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/role_badge.dart';
import '../../chat/presentation/chat_providers.dart';
import '../../matching/presentation/matching_providers.dart';
import '../../roles/presentation/role_providers.dart';
import '../../safety/presentation/safety_providers.dart';
import '../../safety/presentation/sos_widgets.dart';
import '../../trip/domain/trip.dart';
import '../../trip/presentation/trip_lifecycle_providers.dart';
import '../../trip/presentation/trip_providers.dart';

/// Bottom-nav shell (C-25): 5 tabs, labels always visible. Also hosts the
/// app-lifetime session work (C-26 active-trip banner, live tracking,
/// SOS retry) so it runs on every tab.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Anything left in the SOS outbox from an earlier run goes out now.
    Future.microtask(() => unawaited(ref.read(sosServiceProvider).kick()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    ref.read(appForegroundProvider.notifier).state = fg;
    if (fg) {
      unawaited(ref.read(sosServiceProvider).kick());
      // The server is the source of truth for the role: reconcile on resume (F-D8).
      unawaited(ref.read(roleControllerProvider.notifier).refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Red dot on "ใกล้ฉัน" while a request waits for my answer.
    final pending = ref.watch(incomingPendingCountProvider);
    final unreadChats = ref.watch(unreadMatchIdsProvider).isNotEmpty;
    final trip = ref.watch(activeTripProvider).valueOrNull;
    // Keeps GPS + live sharing alive on every tab while a trip is in progress.
    ref.watch(tripTrackingProvider);
    final shell = widget.navigationShell;
    // Registration lost on another device: the tone already fell back to Rider; tell the user once (polite).
    ref.listen<RoleNotice?>(roleControllerProvider.select((s) => s.notice), (_, n) {
      if (n == null) return;
      ref.read(roleControllerProvider.notifier).consumeNotice();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(D.reconciled)));
    });

    return Scaffold(
      body: Column(children: [
        Expanded(child: shell),
        if (trip != null && trip.status == TripStatus.inProgress) _ActiveTripBanner(trip: trip),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: S.tabHome,
          ),
          NavigationDestination(
            icon: Badge(isLabelVisible: pending > 0, child: const Icon(Icons.people_outline)),
            selectedIcon: Badge(isLabelVisible: pending > 0, child: const Icon(Icons.people)),
            label: S.tabNearby,
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unreadChats,
              child: const Icon(Icons.chat_bubble_outline),
            ),
            selectedIcon: Badge(isLabelVisible: unreadChats, child: const Icon(Icons.chat_bubble)),
            label: S.tabChats,
          ),
          const NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: S.tabTrips,
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: S.tabMe,
          ),
        ],
      ),
    );
  }
}

/// C-26: persistent banner while a trip is in progress, with a compact SOS so
/// help is two taps away from any tab.
class _ActiveTripBanner extends StatelessWidget {
  const _ActiveTripBanner({required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.green,
      child: InkWell(
        onTap: () => context.push(Routes.tripActive(trip.id)),
        child: Padding(
          padding: const EdgeInsets.only(left: AppSpacing.pageH, top: AppSpacing.xs, bottom: AppSpacing.xs),
          child: Row(children: [
            const Icon(Icons.directions_walk, color: AppColors.navy),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    P.bannerActiveTrip,
                    style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w600),
                  ),
                  // D-14: the banner names the role of the TRIP, whatever mode the app is in.
                  if (trip.role != null) RoleBadge(trip.role!),
                ],
              ),
            ),
            SosMiniButton(tripId: trip.id),
          ]),
        ),
      ),
    );
  }
}
