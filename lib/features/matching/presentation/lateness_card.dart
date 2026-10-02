import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';

/// US-49 (round 7 Stage C): the two-choice card shown on BOTH sides when lateness is detected
/// (`checkLateness`, client-side hint only — the server re-verifies via `cancel_match_no_fault`).
/// Accessible: a normal AppCard + two full-width tap targets, readable by a screen reader like any
/// other text/button pair (no colour-only meaning, no auto-dismiss timer that could race a user).
class LatenessCard extends StatelessWidget {
  const LatenessCard({
    super.key,
    required this.onWaitMore,
    required this.onCancelNoFault,
    this.busy = false,
    this.errorText,
  });

  final VoidCallback onWaitMore;
  final VoidCallback onCancelNoFault;
  final bool busy;

  /// Shown when the server rejected the cancel with `GWM_NOT_OVERDUE` (client timing was off; the
  /// card stays up so the user can keep waiting or try again once really overdue).
  final String? errorText;

  static const title = 'ดูเหมือนการเดินทางจะล่าช้ากว่าที่คาด';
  static const body = 'ยังไม่เจอเพื่อนร่วมทางตามที่นัดไว้ ต้องการรอต่อ หรือยกเลิกการเดินทางครั้งนี้ไหม?';
  static const waitLabel = 'รอต่ออีก 10 นาที';
  static const cancelLabel = 'ยกเลิกการเดินทาง (ไม่เสียประวัติ)';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: AppCard(
        key: const Key('lateness-card'),
        tone: AppCardTone.warning,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.hourglass_bottom, semanticLabel: ''),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(title, key: const Key('lateness-title'), style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(body, key: Key('lateness-body')),
            if (errorText != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                errorText!,
                key: const Key('lateness-error'),
                style: theme.textTheme.bodyMedium?.copyWith(color: context.tone.dangerInk),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: const Key('lateness-wait'),
              label: waitLabel,
              variant: AppButtonVariant.secondary,
              onPressed: busy ? null : onWaitMore,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              key: const Key('lateness-cancel'),
              label: cancelLabel,
              variant: AppButtonVariant.danger,
              loading: busy,
              onPressed: busy ? null : onCancelNoFault,
            ),
          ],
        ),
      ),
    );
  }
}
