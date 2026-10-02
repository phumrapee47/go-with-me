import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/l10n/strings_roles.dart';
import '../../../core/map/app_map.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../trip/domain/trip.dart';
import '../domain/match_models.dart';

/// Pure decision: may the pickup point still be changed in the UI? (F-R5.6)
/// Read-only once either trip started, after boarding, or when the match ended.
bool pickupEditable(MatchSummary m, {TripStatus? myTripStatus}) {
  if (m.status != MatchStatus.accepted || m.boarded) return false;
  if (myTripStatus == TripStatus.inProgress) return false;
  if (m.partnerTripStatus == TripStatus.inProgress) return false;
  return true;
}

/// C-35. One card for the whole pickup handshake of a car match:
/// none / waiting for the other / proposed by the other / agreed / read-only.
class PickupPointCard extends StatelessWidget {
  const PickupPointCard({
    super.key,
    required this.match,
    required this.editable,
    required this.busy,
    required this.onPropose,
    required this.onConfirm,
  });

  final MatchSummary match;
  final bool editable;
  final bool busy;
  final VoidCallback onPropose;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final m = match;
    final theme = Theme.of(context);
    final proposed = m.proposedPoint;
    final agreed = m.meetingPoint;
    final otherWho = m.iAmDriver ? R.pickupWhoRider : R.pickupWhoDriver;

    final children = <Widget>[
      Row(children: [
        Icon(Icons.place_outlined, color: context.tone.text),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(R.pickupTitle, style: theme.textTheme.titleMedium)),
      ]),
      const SizedBox(height: AppSpacing.sm),
    ];

    if (proposed != null) {
      final place = m.proposedLabel ?? '';
      children.addAll([
        Text(
          m.proposedByMe
              ? R.pickupWaitingOther(otherWho, place)
              : (m.iAmDriver ? R.pickupProposedByRider(place) : R.pickupProposedByDriver(place)),
          key: const Key('pickup-status'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.sm),
        _MiniMap(point: proposed),
        if (editable) ...[
          const SizedBox(height: AppSpacing.md),
          if (!m.proposedByMe)
            AppButton(
              key: const Key('pickup-confirm'),
              label: R.pickupConfirm,
              variant: AppButtonVariant.success,
              loading: busy,
              onPressed: onConfirm,
            ),
          AppButton(
            key: const Key('pickup-propose-again'),
            label: m.proposedByMe ? R.pickupPropose : R.pickupProposeAgain,
            variant: AppButtonVariant.secondary,
            onPressed: busy ? null : onPropose,
          ),
        ],
      ]);
    } else if (agreed != null) {
      children.addAll([
        Text(
          R.pickupAgreed(m.meetingLabel ?? ''),
          key: const Key('pickup-status'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.sm),
        _MiniMap(point: agreed),
        if (editable) ...[
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const Key('pickup-propose-again'),
            label: R.pickupProposeAgain,
            variant: AppButtonVariant.secondary,
            onPressed: busy ? null : onPropose,
          ),
        ],
      ]);
    } else {
      children.add(const Text(R.pickupNone, key: Key('pickup-status')));
      if (editable) {
        children.add(const SizedBox(height: AppSpacing.md));
        if (m.iAmDriver) {
          children.add(AppButton(
            key: const Key('pickup-propose'),
            label: R.pickupPropose,
            loading: busy,
            onPressed: onPropose,
          ));
        } else {
          // US-18: the Driver opens the proposal; the Rider confirms or counters.
          children.add(const Text(R.pickupWaitDriver, key: Key('pickup-wait-driver')));
        }
      }
    }
    if (!editable && m.status == MatchStatus.accepted) {
      children.addAll([
        const SizedBox(height: AppSpacing.sm),
        Text(R.pickupReadOnly, style: TextStyle(color: context.tone.textSecondary)),
      ]);
    }
    children.addAll([
      const SizedBox(height: AppSpacing.sm),
      Text(R.pickupPublicNote, style: TextStyle(color: context.tone.textSecondary)),
    ]);
    return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children));
  }
}

class _MiniMap extends StatelessWidget {
  const _MiniMap({required this.point});
  final LatLng point;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 160,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: AppMap(
            center: point,
            zoom: 16,
            pins: [MapPin(point: point, icon: Icons.place, color: AppColors.danger)],
            showZoomButtons: false,
          ),
        ),
      );
}

/// C-37 (neutral variants): the same wording for both sides, never a reason
/// and never who pressed what (US-18 AC9).
class MatchEndNotice extends StatelessWidget {
  const MatchEndNotice({
    super.key,
    required this.byMe,
    required this.backToSearch,
    required this.driverContinues,
  });

  /// I pressed cancel just now on this screen.
  final bool byMe;

  /// My trip is still waiting to start, so it is searchable again.
  final bool backToSearch;

  /// Driver side while the trip is running: they simply continue.
  final bool driverContinues;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      tone: AppCardTone.warning,
      child: Semantics(
        liveRegion: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.link_off, color: context.tone.warningInk),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                byMe ? R.endedByMe : R.ended,
                key: const Key('match-ended'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ]),
          if (backToSearch) ...[
            const SizedBox(height: AppSpacing.xs),
            const Text(R.endedBackToSearch, key: Key('match-ended-back')),
          ],
          if (driverContinues) ...[
            const SizedBox(height: AppSpacing.xs),
            const Text(R.endedDriverSide),
          ],
        ]),
      ),
    );
  }
}

/// "ทริปของคุณสองคน: รอออกเดินทาง / กำลังเดินทาง" (+ Driver: Rider boarded or not).
class TripProgressRow extends StatelessWidget {
  const TripProgressRow({super.key, required this.match, this.myTripStatus});
  final MatchSummary match;
  final TripStatus? myTripStatus;

  @override
  Widget build(BuildContext context) {
    final started = myTripStatus == TripStatus.inProgress || match.partnerTripStatus == TripStatus.inProgress;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.route_outlined, size: 20, color: context.tone.text),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            '${R.tripStatusBoth}: ${started ? R.partnerMoving : R.partnerWaiting}',
            key: const Key('trip-progress'),
          ),
        ),
      ]),
      if (match.iAmDriver && match.status == MatchStatus.accepted)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Row(children: [
            Icon(match.boarded ? Icons.check_circle_outline : Icons.hourglass_empty, size: 20, color: context.tone.text),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                match.boarded ? R.driverStatusDone : R.driverStatusWaiting,
                key: const Key('rider-boarded-status'),
              ),
            ),
          ]),
        ),
    ]);
  }
}
