import 'package:flutter/material.dart';

import '../../../core/l10n/strings_p4.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/theme/tone_scope.dart';
import '../../../core/widgets/role_badge.dart';
import '../domain/trip.dart';
import '../domain/trip_form.dart';
import 'trip_tone.dart';

String tripStatusLabel(TripStatus s) => switch (s) {
      TripStatus.scheduled => P.statusScheduled,
      TripStatus.inProgress => P.statusInProgress,
      TripStatus.completed => P.statusCompleted,
      TripStatus.cancelled => P.statusCancelled,
      TripStatus.expired => P.statusExpired,
    };

/// C-13 / RC-10 TripStatusPill (round 9 US-4): always icon + text (never colour alone).
/// Colours now come from theme-aware `context.tone.*` tokens (so all 4 tone x brightness
/// variants stay readable/distinguishable) instead of the old fixed `AppColors.*` — that
/// also drops the last `AppColors.border` decorative use in this file (US-7).
class TripStatusChip extends StatelessWidget {
  const TripStatusChip(this.status, {super.key});
  final TripStatus status;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final (IconData icon, Color bg, Color fg) = switch (status) {
      TripStatus.scheduled => (Icons.schedule, tone.infoBg, tone.accentInk),
      // AC: "กำลังเดินทาง" = mint-soft tone, clearly distinct from "เสร็จสิ้น" gray.
      TripStatus.inProgress => (Icons.directions_walk, tone.successFill, tone.onSuccessFill),
      TripStatus.completed => (Icons.check_circle_outline, tone.surfaceRaised, tone.textSecondary),
      TripStatus.cancelled => (Icons.block, tone.dangerTint, tone.dangerInk),
      TripStatus.expired => (Icons.timer_off_outlined, tone.warningTint, tone.warningInk),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              tripStatusLabel(status),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// C-12: a trip in the "my trips" list.
class TripCard extends StatelessWidget {
  const TripCard({
    super.key,
    required this.trip,
    required this.matchedCount,
    required this.onTap,
    this.actions = const [],
  });

  final Trip trip;
  final int matchedCount;
  final VoidCallback onTap;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    // D-14 TripToneIsland: a car trip keeps the tone of ITS role even on an app-level page of the other tone.
    if (trip.role == null) return _TripCardBody(this);
    return ToneScope(tone: toneOfTripRole(trip.role), child: _TripCardBody(this));
  }
}

class _TripCardBody extends StatelessWidget {
  const _TripCardBody(this.c);
  final TripCard c;

  Trip get trip => c.trip;
  int get matchedCount => c.matchedCount;
  VoidCallback get onTap => c.onTap;
  List<Widget> get actions => c.actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = context.tone;
    final now = DateTime.now();
    final island = trip.role != null;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: island && !tone.isDriver ? tone.infoBg : null,
      child: InkWell(
        onTap: onTap,
        child: Container(
          // Driver island: 4 dp amber band on the left (decorative; the badge carries the meaning).
          decoration: island && tone.isDriver
              ? const BoxDecoration(border: Border(left: BorderSide(color: Color(0xFFF5A623), width: 4)))
              : null,
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // RC-9 RidePassCard (round 9 US-4): status pill up top, then the route as
              // 🟢 origin ── 🔴 dest with real place names — never raw lat/lng (the label
              // fields are always server-resolved text already; a friendly fallback stands
              // in for an empty label instead of a blank or a coordinate pair).
              Align(alignment: Alignment.centerLeft, child: TripStatusChip(trip.status)),
              const SizedBox(height: AppSpacing.sm),
              _RouteLine(originLabel: trip.originLabel, destLabel: trip.destLabel),
              const SizedBox(height: AppSpacing.xs),
              Text('${trip.mode.label} · ${formatDeparture(trip.departAt, now)}'),
              if (trip.role != null) ...[
                const SizedBox(height: AppSpacing.xs),
                RoleRow(trip.role!),
              ],
              if (trip.isLegacyCarWithoutRole)
                Text(
                  R.legacyNoRole,
                  key: const Key('trip-legacy-no-role'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: context.tone.textSecondary),
                )
              else if (trip.status.isActive)
                Text(
                  // Car trips take exactly one companion: "1/1" for a Driver, plain for a Rider.
                  switch (trip.role) {
                    TripRole.driver => matchedCount > 0 ? R.matchedPairDriver : 'จับคู่แล้ว 0/1',
                    TripRole.rider => matchedCount > 0 ? R.matchedPairRider : R.notMatchedRider,
                    null => P.matchedCount.replaceFirst('%s', '$matchedCount'),
                  },
                  style: theme.textTheme.bodyMedium?.copyWith(color: context.tone.textSecondary),
                ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                // AC: "เดินทางซ้ำ"/other trip actions sit at the bottom-right of the card.
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: actions),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// RC-9: 🟢 origin ── 🔴 dest with real place-name labels. Never raw coordinates — both
/// labels are already server-resolved text (`trips.origin_label`/`dest_label`); an empty
/// label (label resolution failed upstream) falls back to a friendly phrase, never a blank
/// or a lat/lng pair (US-4 AC).
class _RouteLine extends StatelessWidget {
  const _RouteLine({required this.originLabel, required this.destLabel});
  final String originLabel;
  final String destLabel;

  static const _fallback = 'ตำแหน่งที่ปักหมุด';

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final theme = Theme.of(context);
    Widget row(Color dotColor, String label, {Key? key}) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Icon(Icons.circle, size: 10, color: dotColor),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(label, key: key, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
            ),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row(AppColors.green, originLabel.isEmpty ? _fallback : originLabel, key: const Key('trip-origin-label')),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Container(width: 1, height: 12, color: tone.border),
        ),
        row(AppColors.danger, destLabel.isEmpty ? _fallback : destLabel, key: const Key('trip-dest-label')),
      ],
    );
  }
}
