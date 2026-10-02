import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/l10n/strings_r5.dart';
import '../../../core/platform/external_actions.dart';
import '../../../core/providers.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../matching/domain/match_models.dart';
import '../domain/navigation_links.dart';
import '../domain/trip.dart';

const _noticeKey = 'ext_map_notice_seen';

/// Which platforms show Apple Maps (overridable in tests).
final navIsAppleProvider = Provider<bool>(
  (_) => defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS,
);

/// E-9 / US-24: ONE button chosen by state. Target = the agreed pickup or my own destination, nothing else.
/// Hidden within 50 m of the pickup; disabled with a reason while no pickup is agreed.
class NavigateButton extends ConsumerWidget {
  const NavigateButton({super.key, required this.trip, required this.match, required this.myPosition});
  final Trip trip;
  final MatchSummary? match;
  final LatLng? myPosition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = match;
    final st = navButtonState(
      matchAccepted: m != null && m.status == MatchStatus.accepted,
      riderBoarded: m?.boarded ?? false,
      myTripInProgress: trip.status == TripStatus.inProgress,
      pickup: m?.meetingPoint,
      myPosition: myPosition,
    );
    switch (st) {
      case NavButtonState.hidden:
        return const SizedBox.shrink();
      case NavButtonState.toPickupDisabledNoPoint:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const AppButton(key: Key('nav-pickup-disabled'), label: R5.navToPickup, icon: Icons.navigation_outlined, onPressed: null),
          const SizedBox(height: AppSpacing.xs),
          Text(R5.navNoPickup, key: const Key('nav-no-pickup'), textAlign: TextAlign.center, style: TextStyle(color: context.tone.textSecondary)),
          TextButton(
            onPressed: m == null ? null : () => context.push(Routes.pickup(m.id)),
            child: const Text(R5.navGoSetPickup),
          ),
        ]);
      case NavButtonState.toPickup:
        return AppButton(
          key: const Key('nav-pickup'),
          label: R5.navToPickup,
          icon: Icons.navigation_outlined,
          variant: AppButtonVariant.secondary,
          onPressed: () => openNavigation(context, ref, target: m!.meetingPoint!, forPickup: true),
        );
      case NavButtonState.toDestination:
        return AppButton(
          key: const Key('nav-destination'),
          label: R5.navToDestination,
          icon: Icons.navigation_outlined,
          variant: AppButtonVariant.secondary,
          onPressed: () => openNavigation(context, ref, target: trip.dest, forPickup: false),
        );
    }
  }
}

/// First-time notice (E-10), then the app chooser (E-9), then the launch. Only [target] leaves the app.
Future<void> openNavigation(BuildContext context, WidgetRef ref, {required LatLng target, required bool forPickup}) async {
  final prefs = ref.read(sharedPrefsProvider);
  if (!(prefs.getBool(_noticeKey) ?? false)) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(R5.navNoticeTitle),
        content: Text(R5.navNoticeBody(forPickup ? R5.navTargetPickup : R5.navTargetDest)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(R5.navCancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(R5.navNoticeOk)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await prefs.setBool(_noticeKey, true);
  }
  if (!context.mounted) return;
  final apps = availableMapApps(isApple: ref.read(navIsAppleProvider));
  final app = await showModalBottomSheet<MapApp>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.sm),
          child: Text(R5.navSheetTitle, style: Theme.of(ctx).textTheme.titleLarge),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Text(forPickup ? R5.navTargetPickup : R5.navTargetDest),
        ),
        const Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Row(children: [
            Icon(Icons.warning_amber_rounded, size: 20),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(R5.navSafety)),
          ]),
        ),
        for (final a in apps)
          ListTile(
            key: Key('nav-app-${a.name}'),
            minTileHeight: 56,
            leading: Icon(a == MapApp.web ? Icons.public : Icons.map_outlined),
            title: Text(switch (a) {
              MapApp.google => R5.navGoogle,
              MapApp.apple => R5.navApple,
              MapApp.web => R5.navWeb,
            }),
            onTap: () => Navigator.pop(ctx, a),
          ),
        ListTile(minTileHeight: 56, title: const Text(R5.navCancel), onTap: () => Navigator.pop(ctx)),
      ]),
    ),
  );
  if (app == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final ok = await ref.read(externalActionsProvider).openUrl(mapLink(app, target));
  if (!ok) {
    messenger.showSnackBar(SnackBar(
      content: const Text(R5.navOpenFail),
      action: SnackBarAction(
        label: R5.navUseWeb,
        onPressed: () => ref.read(externalActionsProvider).openUrl(mapLink(MapApp.web, target)),
      ),
    ));
  }
}
