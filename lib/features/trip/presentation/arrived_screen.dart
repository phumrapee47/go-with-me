import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings_p4.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../../matching/domain/match_models.dart';
import '../../matching/presentation/matching_providers.dart';
import '../../reviews/presentation/review_providers.dart';
import '../../reviews/presentation/review_widgets.dart';
import '../domain/trip_form.dart';
import 'trip_lifecycle_providers.dart';

/// S-22: warm confirmation after "arrived". Live sharing has already stopped
/// (the trip is completed, so tracking and pushes are off).
class ArrivedScreen extends ConsumerStatefulWidget {
  const ArrivedScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<ArrivedScreen> createState() => _ArrivedState();
}

class _ArrivedState extends ConsumerState<ArrivedScreen> {
  bool _hideCard = false; // "later": hides the card here, it stays elsewhere until the window closes

  String get tripId => widget.tripId;

  @override
  void initState() {
    super.initState();
    // US-26: offer the review once, as a sheet, right after arriving (never blocks leaving).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final inbox = await ref.read(inboxProvider.future).catchError((_) => const <MatchSummary>[]);
      if (!mounted) return;
      final m = reviewableMatchFor(inbox, tripId);
      if (m != null) await maybeShowReviewSheet(context, ref, m);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inbox = ref.watch(inboxProvider).valueOrNull ?? const <MatchSummary>[];
    final reviewMatch = reviewableMatchFor(inbox, tripId);
    final trip = ref.watch(tripByIdProvider(tripId)).valueOrNull;
    final took = (trip?.startedAt != null && trip?.endedAt != null)
        ? trip!.endedAt!.difference(trip.startedAt!)
        : null;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: const BoxDecoration(color: AppColors.mint, shape: BoxShape.circle),
                child: const Icon(Icons.check_circle, size: 72, color: AppColors.green),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(P.arrivedTitle, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              Text(P.arrivedBody, style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
              if (trip != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  [
                    if (took != null) 'ใช้เวลา ${took.inMinutes} นาที',
                    if (trip.distanceM > 0) formatRouteSummary(trip.distanceM, trip.durationS),
                  ].join(' · '),
                  textAlign: TextAlign.center,
                ),
              ],
              if (reviewMatch != null && !_hideCard) ...[
                const SizedBox(height: AppSpacing.lg),
                ReviewPromptCard(match: reviewMatch, onLater: () => setState(() => _hideCard = true)),
              ],
              const SizedBox(height: AppSpacing.xxl),
              AppButton(label: P.backHome, onPressed: () => context.go(Routes.home)),
            ]),
          ),
        ),
      ),
    );
  }
}
