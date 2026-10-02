import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/error/failure_messages.dart';
import '../../../core/geo/geo.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/router/redirect.dart';
import '../../../core/widgets/state_view.dart';
import '../../geo/presentation/geo_providers.dart';
import '../../geo/presentation/pick_point_screen.dart';
import '../../trip/domain/trip.dart';
import '../../trip/presentation/trip_providers.dart';
import '../domain/match_models.dart';
import 'car_match_widgets.dart';
import 'matching_providers.dart';

/// S-34 (`/matches/:matchId/pickup`): propose a pickup point.
///
/// The warning about a point far from the Driver's route is soft (R3-2): the
/// point is always saved and can always be kept. The server only returns a
/// boolean for a Rider (never the distance, design-roles 5.3); the Driver knows
/// their own route, so their app can also show the distance before sending.
class PickupScreen extends ConsumerWidget {
  const PickupScreen({super.key, required this.matchId});
  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(inboxProvider);
    final trip = ref.watch(activeTripProvider).valueOrNull;
    return inbox.when(
      loading: () => Scaffold(appBar: AppBar(title: const Text(R.pickupScreenTitle)), body: const StateView.loading()),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text(R.pickupScreenTitle)),
        body: StateView.failure(
          e is AppFailure ? e : const AppFailure(FailureCode.unknown),
          onRetry: () => ref.invalidate(inboxProvider),
        ),
      ),
      data: (all) {
        MatchSummary? m;
        for (final x in all) {
          if (x.id == matchId) m = x;
        }
        if (m == null || !pickupEditable(m, myTripStatus: trip?.status)) {
          return Scaffold(
            appBar: AppBar(title: const Text(R.pickupScreenTitle)),
            body: StateView.empty(
              icon: Icons.link_off,
              title: m == null || m.status != MatchStatus.accepted ? R.pickupMatchGone : R.pickupReadOnly,
              actionLabel: m == null ? null : R.viewMatch,
              // push (not go): keep the back stack so the user isn't stranded
              // on match detail with no way back into the app.
              onAction: m == null ? null : () => context.push(Routes.match(m!.id)),
            ),
          );
        }
        return _Editor(match: m, trip: trip);
      },
    );
  }
}

class _Editor extends ConsumerWidget {
  const _Editor({required this.match, required this.trip});
  final MatchSummary match;
  final Trip? trip;

  Future<bool> _submit(BuildContext context, WidgetRef ref, Place place) async {
    final m = match;
    final limit = ref.read(serviceConfigProvider).pickupMaxDeviationM;
    // Driver: the distance can be computed locally (own route) and shown first.
    if (m.iAmDriver && trip != null && trip!.route.length >= 2) {
      final d = distanceToRouteM(place.point, trip!.route).round();
      if (d > limit) {
        final keep = await _offRouteDialog(context, R.pickupOffRouteM(d));
        if (!keep || !context.mounted) return false;
      }
    }
    final res = await ref.read(inboxProvider.notifier).proposeMeeting(m.id, place.point, place.label);
    if (!context.mounted) return false;
    return await res.when(
      ok: (beyond) async {
        // Rider: the server said "beyond the limit" (no distance). Warn, never block.
        if (beyond && !m.iAmDriver) {
          final keep = await _offRouteDialog(context, R.pickupOffRoute);
          if (!keep || !context.mounted) return false;
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(R.pickupSaved)));
        }
        return true;
      },
      err: (f) async {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failureMessage(f))));
        return false;
      },
    );
  }

  /// true = keep this point, false = choose another.
  Future<bool> _offRouteDialog(BuildContext context, String text) async {
    final keep = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('off-route-dialog'),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text(R.pickupOffRouteChange)),
          FilledButton(
            key: const Key('off-route-continue'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(R.pickupOffRouteContinue),
          ),
        ],
      ),
    );
    return keep ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = match;
    final LatLng? start = m.proposedPoint ?? m.meetingPoint ?? trip?.origin;
    return PickPointScreen(
      title: R.pickupScreenTitle,
      initial: start,
      // Only the Driver's own route is ever drawn (a Rider never receives it).
      route: m.iAmDriver ? (trip?.route ?? const []) : const [],
      note: R.pickupPublicNote,
      confirmLabel: m.iAmDriver ? R.pickupSend : R.pickupSendNew,
      onPicked: (place) => _submit(context, ref, place),
      // US-43 (R7.11): snap once per "เสนอจุดนี้"/"ส่งข้อเสนอจุดรับ" tap using
      // this trip's own travel mode. No own trip loaded (edge case) = no
      // snapping, never blocks proposing (fail-open).
      snapMode: trip?.mode,
    );
  }
}
