import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings_r5.dart';
import '../../../core/providers.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../avatar/presentation/user_avatar.dart';
import '../../matching/domain/match_models.dart';
import '../../trip/domain/trip.dart' show TripRole;
import '../domain/review_models.dart';
import 'review_providers.dart';

/// E-16 RatingSummary. Shows an average only when at least 3 revealed reviews exist; otherwise the widget
/// is completely absent (Z-3: no "not enough reviews" text). [userId] must be someone the server lets me
/// read (a match partner, or myself).
class RatingSummary extends ConsumerWidget {
  const RatingSummary({super.key, required this.userId, required this.role, this.full = false});
  final String userId;
  final TripRole role;
  final bool full;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratings = ref.watch(userRatingProvider(userId)).valueOrNull;
    if (ratings == null) return const SizedBox.shrink();
    final r = visibleRating(ratings, role);
    if (r == null) return const SizedBox.shrink();
    return RatingLine(avg: r.avg!, count: r.count!, role: role, full: full);
  }
}

/// The visible part (also used directly by tests).
class RatingLine extends StatelessWidget {
  const RatingLine({super.key, required this.avg, required this.count, required this.role, this.full = false});
  final double avg;
  final int count;
  final TripRole role;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final t = context.tone;
    final avgText = ratingText(avg);
    final roleText = ratingRoleLabel(role);
    final text = full ? '$roleText: ${R5.reviewSummary(avgText, count)}' : '$avgText ($count) $roleText';
    return Semantics(
      label: R5.reviewSummaryA11y(avgText, count, roleText),
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.star_rounded, size: 20, color: t.isDriver ? const Color(0xFFFFC24D) : const Color(0xFF8A5A00)),
        const SizedBox(width: AppSpacing.xs),
        Flexible(child: Text(text, key: const Key('rating-line'), style: Theme.of(context).textTheme.bodyMedium)),
      ]),
    );
  }
}

/// ReviewPromptCard: shown while the review window is open and nothing has been sent yet.
/// After sending it becomes a quiet "sent, waiting" line (blind status).
class ReviewPromptCard extends ConsumerWidget {
  const ReviewPromptCard({super.key, required this.match, this.onLater});
  final MatchSummary match;
  final VoidCallback? onLater;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(reviewStateProvider(match.id)).valueOrNull;
    if (st == null) return const SizedBox.shrink();
    if (st.alreadySubmitted) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(children: [
          Icon(Icons.hourglass_top, size: 18),
          SizedBox(width: AppSpacing.sm),
          Text(R5.reviewStatusPending, key: Key('review-pending')),
        ]),
      );
    }
    if (!st.promptable) return const SizedBox.shrink();
    final now = DateTime.now();
    final closes = st.closesAt;
    final date = closes == null ? '' : '${closes.day}/${closes.month}';
    return AppCard(
      key: const Key('review-prompt'),
      tone: AppCardTone.info,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          UserAvatar.partner(name: match.displayName, matchId: match.id, size: 40),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(R5.reviewPrompt(match.displayName, date, st.daysLeft(now)))),
        ]),
        const SizedBox(height: AppSpacing.sm),
        Wrap(spacing: AppSpacing.sm, children: [
          AppButton(
            key: const Key('review-give'),
            label: R5.reviewGive,
            expand: false,
            onPressed: () => context.push(Routes.review(match.id)),
          ),
          if (onLater != null)
            AppButton(label: R5.reviewLater, expand: false, variant: AppButtonVariant.text, onPressed: onLater),
        ]),
      ]),
    );
  }
}

/// Shows the prompt as a sheet once per match (after arriving). Safe to call repeatedly.
Future<void> maybeShowReviewSheet(BuildContext context, WidgetRef ref, MatchSummary match) async {
  final prefs = ref.read(sharedPrefsProvider);
  final key = reviewPromptSeenKey(match.id);
  if (prefs.getBool(key) ?? false) return;
  final st = await ref.read(reviewStateProvider(match.id).future);
  if (st == null || !st.promptable || !context.mounted) return;
  await prefs.setBool(key, true);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Consumer(
          builder: (ctx, ref, _) => ReviewPromptCard(match: match, onLater: () => Navigator.of(ctx).pop()),
        ),
      ),
    ),
  );
}
