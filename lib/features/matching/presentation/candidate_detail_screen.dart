import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/strings_roles.dart';
import '../../../core/l10n/strings_trip.dart';
import '../../../core/map/app_map.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/role_badge.dart';
import '../../../core/widgets/state_view.dart';
import '../../trip/domain/trip.dart' show TripRole;
import '../../trip/domain/trip_form.dart';
import '../../trip/presentation/vibe_mood_widgets.dart';
import '../domain/match_models.dart';
import 'commute_card_deck.dart' show CardRatingSlot;
import 'matching_providers.dart';
import 'matching_widgets.dart';

/// S-14: candidate before matching. Only blurred areas are ever shown.
class CandidateDetailScreen extends ConsumerWidget {
  const CandidateDetailScreen({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(nearbyProvider).valueOrNull ?? const <MatchCandidate>[];
    MatchCandidate? c;
    for (final x in list) {
      if (x.tripId == tripId) c = x;
    }
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(c?.displayName ?? T.homeNearbyHeader)),
      body: c == null
          ? const StateView.empty(icon: Icons.person_off_outlined, title: T.notAvailable)
          : _body(context, ref, c, theme),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, MatchCandidate c, ThemeData theme) {
    final now = DateTime.now();
    final status = c.requestStatus;
    final label = switch (status) {
      MatchStatus.pending => T.requested,
      MatchStatus.accepted => T.matched,
      _ => requestLabel(c),
    };
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.pageH),
      children: [
        if (c.role != null) ...[
          RoleRow(c.role!),
          const SizedBox(height: AppSpacing.md),
        ],
        Row(children: [
          AvatarInitial(name: c.displayName, radius: 32),
          const SizedBox(width: AppSpacing.lg),
          Expanded(child: Text(c.displayName, style: theme.textTheme.titleLarge)),
        ]),
        const SizedBox(height: AppSpacing.md),
        BadgeWrap(c.badges),
        CardRatingSlot(avg: c.ratingAvg, count: c.ratingCount, align: MainAxisAlignment.start),
        if (c.vibeTags.isNotEmpty || (c.moodText?.isNotEmpty ?? false)) ...[
          const SizedBox(height: AppSpacing.md),
          TripVibeSummaryRow(vibeTags: c.vibeTags, moodText: c.moodText, compact: false),
        ],
        const SizedBox(height: AppSpacing.lg),
        _metric(context, Icons.route, overlapText(c)),
        if (dropoffText(c) case final dt?) _metric(context, Icons.social_distance_outlined, dt),
        if (c.role == TripRole.driver) _metric(context, Icons.directions_car_outlined, R.vehicleAfterAccept),
        _metric(context, c.mode.icon, c.mode.label),
        _metric(context, Icons.schedule, formatDeparture(c.departAt, now)),
        _metric(context, Icons.straighten, '${T.distanceAbout}${distanceText(c.approxDistanceM)}'),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 220,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: AppMap(
              center: c.approxOrigin,
              zoom: 12,
              areas: [
                MapArea(center: c.approxOrigin, radiusM: blurAreaRadiusM, highlighted: true),
                if (c.approxDest case final d?) MapArea(center: d, radiusM: blurAreaRadiusM),
              ],
              showZoomButtons: false,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(T.mapPrivacy, style: TextStyle(color: context.tone.textSecondary)),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: label,
          onPressed: status == null ? () => confirmAndSendRequest(context, ref, c) : null,
        ),
      ],
    );
  }

  Widget _metric(BuildContext context, IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(children: [
          Icon(icon, size: 20, color: context.tone.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(text)),
        ]),
      );
}
