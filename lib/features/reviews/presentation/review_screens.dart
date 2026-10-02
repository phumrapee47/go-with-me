import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/error/failure_messages.dart';
import '../../../core/l10n/strings_r5.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/state_view.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../avatar/presentation/user_avatar.dart';
import '../../matching/domain/match_models.dart';
import '../../matching/presentation/matching_providers.dart';
import '../../trip/domain/trip.dart' show TripRole;
import '../domain/review_models.dart';
import 'review_providers.dart';
import 'review_widgets.dart';

String reviewSubmitErrorText(AppFailure f) => switch (f.code) {
      'GWM_RATE_LIMITED' => R5.reviewErrRate,
      'GWM_REVIEW_WINDOW_CLOSED' => R5.reviewErrClosed,
      'GWM_REVIEW_DUPLICATE' => R5.reviewErrAlready,
      'GWM_REVIEW_NOT_ELIGIBLE' => R5.reviewErrUnavailable,
      FailureCode.networkOffline || FailureCode.networkTimeout || FailureCode.serverUnavailable => R5.reviewErrNetwork,
      _ => failureMessage(f),
    };

/// E-15 star input: five 48 dp stars, nothing pre-selected, filled + outlined shapes (not colour only).
class StarRatingInput extends StatelessWidget {
  const StarRatingInput({super.key, required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: value == 0 ? R5.reviewStarsRequired : R5.reviewStarsA11y(value),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Semantics(
              button: true,
              selected: i == value,
              label: R5.reviewStarsA11y(i),
              excludeSemantics: true,
              child: InkResponse(
                key: Key('star-$i'),
                onTap: () => onChanged(i),
                radius: 28,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(
                    i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 44,
                    color: i <= value ? const Color(0xFFB77900) : context.tone.textSecondary,
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// S-39 /matches/:matchId/review
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, required this.matchId});
  final String matchId;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewState();
}

class _ReviewState extends ConsumerState<ReviewScreen> {
  int _stars = 0;
  final _tags = <String>{};
  final _comment = TextEditingController();
  bool _busy = false;
  bool _showStarError = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  MatchSummary? _match() {
    for (final m in ref.read(inboxProvider).valueOrNull ?? const <MatchSummary>[]) {
      if (m.id == widget.matchId) return m;
    }
    return null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_stars == 0) {
      setState(() => _showStarError = true);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await ref.read(reviewRepositoryProvider).submit(
          matchId: widget.matchId,
          stars: _stars,
          tags: _tags.toList(),
          comment: _comment.text,
        );
    if (!mounted) return;
    res.when(
      ok: (_) {
        ref.invalidate(reviewStateProvider(widget.matchId));
        context.pushReplacement(Routes.reviewDone(widget.matchId));
      },
      err: (f) => setState(() {
        _busy = false;
        _error = reviewSubmitErrorText(f);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = _match();
    final st = ref.watch(reviewStateProvider(widget.matchId));
    final theme = Theme.of(context);
    final name = m?.displayName ?? 'ผู้ใช้';
    // Guard: not allowed -> neutral message (never explains why the other side is or is not eligible).
    final state = st.valueOrNull;
    if (st.isLoading) return Scaffold(appBar: AppBar(title: const Text(R5.reviewGive)), body: const StateView.loading());
    if (state == null || !state.promptable) {
      final closed = state?.windowClosed ?? false;
      return Scaffold(
        appBar: AppBar(title: Text(R5.reviewTitle(name))),
        body: StateView.empty(
          key: const Key('review-unavailable'),
          icon: Icons.star_outline_rounded,
          title: closed ? R5.reviewErrClosed : (state?.alreadySubmitted ?? false) ? R5.reviewErrAlready : R5.reviewErrUnavailable,
          actionLabel: 'กลับ',
          onAction: () => context.canPop() ? context.pop() : context.go(Routes.home),
        ),
      );
    }
    final reviewee = m?.partnerRole ?? TripRole.driver;
    final tags = reviewTagsFor(reviewee);
    final good = [for (final t in tags) if (R5.reviewPositiveTags.contains(t)) t];
    final improve = [for (final t in tags) if (!R5.reviewPositiveTags.contains(t)) t];
    final len = _comment.text.characters.length;
    return Scaffold(
      appBar: AppBar(title: Text(R5.reviewTitle(name))),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.pageH),
        children: [
          Row(children: [
            m == null ? const SizedBox(width: 56) : UserAvatar.partner(name: name, matchId: m.id, size: 56),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text('${R5.reviewTitle(name)} ${ratingRoleLabel(reviewee)}', style: theme.textTheme.titleMedium)),
          ]),
          const SizedBox(height: AppSpacing.lg),
          StarRatingInput(value: _stars, onChanged: (v) => setState(() {
                _stars = v;
                _showStarError = false;
              })),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _stars == 0 ? (_showStarError ? R5.reviewStarsRequired : '') : R5.reviewStarLabels[_stars - 1],
            key: const Key('star-caption'),
            style: theme.textTheme.bodyMedium?.copyWith(color: _showStarError && _stars == 0 ? context.tone.dangerInk : null),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(R5.reviewTagsTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          _tagGroup(R5.reviewTagsGood, good),
          _tagGroup(R5.reviewTagsImprove, improve),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('review-comment'),
            controller: _comment,
            maxLines: 4,
            minLines: 2,
            maxLength: maxReviewComment,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: R5.reviewCommentHint,
              helperText: R5.reviewCommentHelp,
              helperMaxLines: 2,
              counterText: '$len/$maxReviewComment',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _note(Icons.visibility_outlined, R5.reviewNoteVisibility(name)),
          _note(Icons.hourglass_top, R5.reviewNoteReveal),
          _note(Icons.lock_outline, R5.reviewNoteFinal),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Text(_error!, key: const Key('review-error'), style: TextStyle(color: context.tone.dangerInk)),
            ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(key: const Key('review-submit'), label: R5.reviewSubmit, loading: _busy, onPressed: _stars == 0 ? null : _submit),
          AppButton(
            label: R5.reviewSkip,
            variant: AppButtonVariant.text,
            onPressed: _busy ? null : () => context.canPop() ? context.pop() : context.go(Routes.home),
          ),
        ],
      ),
    );
  }

  Widget _note(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text)),
        ]),
      );

  Widget _tagGroup(String title, List<String> tags) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
        child: Text(title, style: Theme.of(context).textTheme.labelLarge),
      ),
      Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
        for (final t in tags)
          FilterChip(
            key: Key('tag-$t'),
            label: Text(R5.reviewTagLabels[t] ?? t),
            selected: _tags.contains(t),
            showCheckmark: true,
            onSelected: (v) => setState(() {
              if (v && _tags.length < maxReviewTags) {
                _tags.add(t);
              } else {
                _tags.remove(t);
              }
            }),
          ),
      ]),
    ]);
  }
}

/// S-40 sent + blind explanation.
class ReviewDoneScreen extends ConsumerWidget {
  const ReviewDoneScreen({super.key, required this.matchId});
  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    MatchSummary? m;
    for (final x in ref.watch(inboxProvider).valueOrNull ?? const <MatchSummary>[]) {
      if (x.id == matchId) m = x;
    }
    final closes = ref.watch(reviewStateProvider(matchId)).valueOrNull?.closesAt;
    final date = closes == null ? '' : '${closes.day}/${closes.month}';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_circle, size: 72, color: AppColors.green),
              const SizedBox(height: AppSpacing.lg),
              Text(R5.reviewDoneTitle, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              Text(R5.reviewDoneBody(m?.displayName ?? 'อีกฝ่าย', date), key: const Key('review-done-body'), textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xl),
              AppButton(label: R5.reviewDoneClose, onPressed: () => context.go(Routes.home)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// S-42 /me/reviews: my aggregate (only when >= 3 revealed) and the revealed reviews I received.
class MyReviewsScreen extends ConsumerWidget {
  const MyReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authUserProvider).valueOrNull?.id;
    final received = ref.watch(receivedReviewsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(R5.reviewMineTitle)),
      body: received.when(
        loading: () => const StateView.loading(),
        error: (e, _) => StateView.failure(
          e is AppFailure ? e : const AppFailure(FailureCode.unknown),
          onRetry: () => ref.invalidate(receivedReviewsProvider),
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.all(AppSpacing.pageH),
          children: [
            if (uid != null) ...[
              RatingSummary(userId: uid, role: TripRole.driver, full: true),
              const SizedBox(height: AppSpacing.xs),
              RatingSummary(userId: uid, role: TripRole.rider, full: true),
              const SizedBox(height: AppSpacing.md),
            ],
            if (list.isEmpty)
              const StateView.empty(icon: Icons.star_outline_rounded, title: R5.reviewMineEmpty)
            else
              for (final r in list) _ReviewRow(review: r),
          ],
        ),
      ),
    );
  }
}

class _ReviewRow extends ConsumerWidget {
  const _ReviewRow({required this.review});
  final ReceivedReview review;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: AppSpacing.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 1; i <= 5; i++) Icon(i <= review.stars ? Icons.star_rounded : Icons.star_outline_rounded, size: 20),
            ]),
            Text(ratingRoleLabel(review.role)),
          ]),
          if (review.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Wrap(spacing: AppSpacing.xs, children: [
                for (final t in review.tags) Chip(label: Text(R5.reviewTagLabels[t] ?? t)),
              ]),
            ),
          if ((review.comment ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: AppSpacing.xs), child: Text(review.comment!)),
          TextButton(
            onPressed: () => _report(context, ref),
            child: const Text(R5.reviewReportCta),
          ),
        ]),
      ),
    );
  }

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final reason = await showModalBottomSheet<ReviewReportReason>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(minTileHeight: 56, title: const Text(R5.reviewReportInappropriate), onTap: () => Navigator.pop(ctx, ReviewReportReason.inappropriate)),
          ListTile(minTileHeight: 56, title: const Text(R5.reviewReportPrivate), onTap: () => Navigator.pop(ctx, ReviewReportReason.privateInfo)),
          ListTile(minTileHeight: 56, title: const Text(R5.reviewReportOther), onTap: () => Navigator.pop(ctx, ReviewReportReason.other)),
        ]),
      ),
    );
    if (reason == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final res = await ref.read(reviewRepositoryProvider).report(review.id, reason);
    res.when(
      ok: (_) {
        ref.invalidate(receivedReviewsProvider); // the reported review is hidden from me at once
        messenger.showSnackBar(const SnackBar(content: Text(R5.reviewReportDone)));
      },
      err: (f) => messenger.showSnackBar(SnackBar(content: Text(failureMessage(f)))),
    );
  }
}
