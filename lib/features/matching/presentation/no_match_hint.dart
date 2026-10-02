import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings_r5.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../trip/domain/trip.dart';
import '../domain/match_models.dart';
import 'matching_providers.dart';

/// US-21 P1: one sentence under the empty search state, taken from `get_match_hint`. Shows nothing while
/// loading, when results exist, or when the call fails (the result list is never affected).
class NoMatchHint extends ConsumerStatefulWidget {
  const NoMatchHint({super.key, required this.trip});
  final Trip trip;

  @override
  ConsumerState<NoMatchHint> createState() => _NoMatchHintState();
}

class _NoMatchHintState extends ConsumerState<NoMatchHint> {
  bool _cooling = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _retry() {
    ref.read(nearbyProvider.notifier).refresh(force: true);
    ref.invalidate(matchHintProvider(widget.trip.id));
    setState(() => _cooling = true);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _cooling = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hint = ref.watch(matchHintProvider(widget.trip.id));
    return hint.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (h) {
        final text = matchHintMessage(h, role: widget.trip.role);
        if (text == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, AppSpacing.sm, AppSpacing.pageH, 0),
          child: AppCard(
            key: const Key('no-match-hint'),
            tone: AppCardTone.info,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.lightbulb_outline, size: 22),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text(text, key: const Key('no-match-hint-text'))),
              ]),
              const SizedBox(height: AppSpacing.sm),
              Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
                AppButton(
                  key: const Key('hint-check-trip'),
                  label: R5.noneCheckDest,
                  expand: false,
                  variant: AppButtonVariant.tonal,
                  onPressed: () => context.push(Routes.tripDetail(widget.trip.id)),
                ),
                AppButton(
                  key: const Key('hint-retry'),
                  label: _cooling ? R5.noneWait : R5.noneRetry,
                  expand: false,
                  variant: AppButtonVariant.text,
                  onPressed: _cooling ? null : _retry,
                ),
              ]),
            ]),
          ),
        );
      },
    );
  }
}
