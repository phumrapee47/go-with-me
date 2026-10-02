import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure_messages.dart';
import '../../../core/l10n/strings_r5.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/l10n/strings_trip.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/global_verified_badge.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/role_badge.dart';
import '../../trip/domain/trip.dart' show TripRole;
import '../../trip/domain/trip_form.dart';
import '../domain/match_models.dart';
import 'matching_providers.dart';

export '../../../core/widgets/initials_avatar.dart' show AvatarInitial;

/// Round 9 (US-6/T2): every call site that used to render one [VerifiedBadge]
/// per [VerificationBadge] (including the organization one) now shows a single
/// merged [GlobalVerifiedBadge] — organization badges are never rendered anymore.
class BadgeWrap extends StatelessWidget {
  const BadgeWrap(this.badges, {super.key});
  final List<VerificationBadge> badges;

  @override
  Widget build(BuildContext context) => GlobalVerifiedBadge(badges);
}

/// "ขอติดรถ" when the candidate drives (I am the Rider), "ชวนขึ้นรถ" when the
/// candidate is a Rider (I am the Driver); the peer wording for other modes.
String requestLabel(MatchCandidate c) => switch (c.role) {
      TripRole.driver => R.ctaRider,
      TripRole.rider => R.ctaDriver,
      null => T.goTogether,
    };

String overlapText(MatchCandidate c) => switch (c.role) {
      TripRole.driver => R.overlapRiderView(c.overlapPct),
      TripRole.rider => R.overlapDriverView(c.overlapPct),
      null => '${T.overlap} ${c.overlapPct}%',
    };

/// "คนขับรับส่งได้ไม่เกิน X จากปลายทางของเขา": only on a car Driver candidate (rider searching).
String? dropoffText(MatchCandidate c) {
  final d = c.maxDropoffM;
  if (d == null || c.role != TripRole.driver) return null;
  return R5.matchDriverMaxDropoff(formatMetres(d));
}

String distanceText(int m) => formatMetres(m);

/// C-14. Shows only blurred/bucketed facts (never street names or exact points).
class CandidateCard extends StatelessWidget {
  const CandidateCard({
    super.key,
    required this.candidate,
    required this.now,
    this.selected = false,
    this.onTap,
    this.onRequest,
  });

  final MatchCandidate candidate;
  final DateTime now;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onRequest;

  @override
  Widget build(BuildContext context) {
    final c = candidate;
    final theme = Theme.of(context);
    final status = c.requestStatus;
    final String? buttonLabel = switch (status) {
      MatchStatus.pending => T.requested,
      MatchStatus.accepted => T.matched,
      _ => null,
    };
    return Semantics(
      container: true,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          // US-7 (round 9): the unselected state is decorative -> no border anymore (borderless
          // cards). The selected border stays: it's semantic (tells the user which card is picked).
          side: selected ? const BorderSide(color: AppColors.green, width: 2) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Role first (US-16 AC5): icon + text, plus "รับได้ 1 คน" for drivers.
                if (c.role != null) ...[
                  RoleRow(c.role!),
                  const SizedBox(height: AppSpacing.sm),
                ],
                Row(
                  children: [
                    AvatarInitial(name: c.displayName),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: Text(c.displayName, style: theme.textTheme.titleMedium)),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                BadgeWrap(c.badges),
                const SizedBox(height: AppSpacing.sm),
                Row(children: [
                  Icon(c.mode.icon, size: 18, color: context.tone.textSecondary),
                  const SizedBox(width: AppSpacing.xs),
                  // Expanded: a long label wraps instead of running off the right edge.
                  Expanded(child: Text('${c.mode.label} · ${formatDeparture(c.departAt, now)}')),
                ]),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  // Car overlap is measured on the Rider's route, so the wording has a direction.
                  '${overlapText(c)} · ${T.distanceAbout}${distanceText(c.approxDistanceM)}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: context.tone.textSecondary),
                ),
                if (dropoffText(c) case final dt?)
                  Text(
                    dt,
                    key: const Key('dropoff-text'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: context.tone.textSecondary),
                  ),
                if (c.role == TripRole.driver)
                  Text(
                    R.vehicleAfterAccept,
                    key: const Key('vehicle-after-accept'),
                    style: theme.textTheme.bodySmall?.copyWith(color: context.tone.textSecondary),
                  ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: buttonLabel ?? requestLabel(c),
                  variant: buttonLabel == null ? AppButtonVariant.primary : AppButtonVariant.tonal,
                  onPressed: buttonLabel == null ? onRequest : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Confirm sheet (US-7 step 1) then sends the request. Returns true when a
/// request now exists (sent, or auto-matched).
Future<bool> confirmAndSendRequest(BuildContext context, WidgetRef ref, MatchCandidate c) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(T.sendRequestTitle, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            Text(switch (c.role) {
              TripRole.driver => R.sendSheetRider, // I am the Rider asking a Driver
              TripRole.rider => R.sendSheetDriver,
              null => T.sendRequestBody,
            }),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: c.role == null ? T.sendRequest : requestLabel(c),
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
            AppButton(
              label: 'ยกเลิก',
              variant: AppButtonVariant.text,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
          ],
        ),
      ),
    ),
  );
  if (ok != true || !context.mounted) return false;

  final res = await ref.read(nearbyProvider.notifier).request(c);
  if (!context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  return res.when(
    ok: (o) {
      messenger.showSnackBar(SnackBar(
        content: Text(o.status == MatchStatus.accepted ? T.requestMatchedNow : T.requestSent),
      ));
      return true;
    },
    err: (f) {
      messenger.showSnackBar(SnackBar(content: Text(failureMessage(f))));
      return false;
    },
  );
}

/// Small card used on empty/permission hints.
class HintCard extends StatelessWidget {
  const HintCard(this.text, {super.key, this.tone = AppCardTone.info});
  final String text;
  final AppCardTone tone;

  @override
  Widget build(BuildContext context) => AppCard(tone: tone, child: Text(text));
}
