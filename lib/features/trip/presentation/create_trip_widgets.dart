import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings_r5.dart';
import '../../../core/l10n/strings_trip.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/state_view.dart';
import '../domain/detour.dart';
import '../domain/dropoff.dart';

/// C-7: "ขั้นที่ 2 จาก 3" as text (also read by screen readers) + progress bar.
class StepIndicator extends StatelessWidget {
  const StepIndicator({super.key, required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, 0, AppSpacing.pageH, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            T.stepOf.replaceFirst('%s', '$step'),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: context.tone.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          LinearProgressIndicator(
            value: step / 3,
            minHeight: 6,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            color: context.tone.primaryInk,
            backgroundColor: context.tone.primaryTint,
          ),
        ],
      ),
    );
  }
}

/// Shown instead of the flow when the user already has an active trip.
class ActiveTripBlocked extends StatelessWidget {
  const ActiveTripBlocked({super.key});

  @override
  Widget build(BuildContext context) {
    return StateView.empty(
      icon: Icons.route_outlined,
      title: T.hasActiveTrip,
      message: T.hasActiveTripBody,
      actionLabel: T.goMyTrips,
      onAction: () => context.go(Routes.trips),
    );
  }
}

/// Bottom-anchored primary action for the flow screens.
class FlowBottomBar extends StatelessWidget {
  const FlowBottomBar({super.key, required this.label, required this.onPressed, this.loading = false});
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: AppButton(label: label, onPressed: onPressed, loading: loading),
      ),
    );
  }
}

/// Driver drop-off limit (`trips.max_dropoff_m`): slider 500..5000 step 100 + quick chips.
/// [lockedReason] non-null = read-only (trip has a pending request / accepted match).
class DropoffLimitControl extends StatelessWidget {
  const DropoffLimitControl({super.key, required this.value, required this.onChanged, this.lockedReason});
  final int value;
  final ValueChanged<int> onChanged;
  final String? lockedReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locked = lockedReason != null;
    return Column(
      key: const Key('dropoff-control'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(R5.dropoffLabel, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          formatMetres(value),
          key: const Key('dropoff-value'),
          style: theme.textTheme.headlineSmall?.copyWith(color: context.tone.primaryInk),
        ),
        Slider(
          key: const Key('dropoff-slider'),
          value: value.toDouble().clamp(dropoffMinM.toDouble(), dropoffMaxM.toDouble()),
          min: dropoffMinM.toDouble(),
          max: dropoffMaxM.toDouble(),
          divisions: (dropoffMaxM - dropoffMinM) ~/ dropoffStepM,
          label: formatMetres(value),
          semanticFormatterCallback: (v) => formatMetres(v.round()),
          onChanged: locked ? null : (v) => onChanged(clampDropoff(v.round())),
        ),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final m in dropoffChipsM)
              ChoiceChip(
                key: Key('dropoff-chip-$m'),
                label: Text(formatMetres(m)),
                selected: value == m,
                onSelected: locked ? null : (_) => onChanged(m),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (locked)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.lock_outline, size: 16),
            const SizedBox(width: 4),
            Expanded(child: Text(lockedReason!, key: const Key('dropoff-locked'))),
          ])
        else
          Text(R5.dropoffHelper,
              key: const Key('dropoff-helper'),
              style: theme.textTheme.bodySmall?.copyWith(color: context.tone.textSecondary)),
      ],
    );
  }
}

/// US-50 (round 7): driver route detour tolerance (`trips.detour_tolerance_m`): slider 200..2000 m
/// step 100. A SECOND, INDEPENDENT matching path from [DropoffLimitControl] above — both are shown
/// together on the create-trip form so the distinction is clear: [DropoffLimitControl] is a radius
/// from the driver's destination, this is the extra ROUND-TRIP road distance accepted to detour to
/// a rider's destination anywhere (OR'd together server-side, `docs/design-roles.md` #15.5).
/// [lockedReason] non-null = read-only (trip has a pending request / accepted match).
class DetourToleranceControl extends StatelessWidget {
  const DetourToleranceControl({super.key, required this.value, required this.onChanged, this.lockedReason});
  final int value;
  final ValueChanged<int> onChanged;
  final String? lockedReason;

  static const _label = 'ระยะเบี่ยงที่ยอมรับได้เพิ่มเติม';
  static const _helper =
      'ต่างจากระยะรับส่งด้านบน: นี่คือระยะทางถนนที่ยอมให้รถวิ่งเพิ่มขึ้นจริง (ไป-กลับ) เพื่อแวะส่งคนนั่งที่ปลายทางอยู่นอกเส้นทางของคุณเล็กน้อย ช่วยให้จับคู่กับคนนั่งที่ปลายทางไม่ตรงเป๊ะได้มากขึ้น';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locked = lockedReason != null;
    return Column(
      key: const Key('detour-control'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_label, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          formatMetres(value),
          key: const Key('detour-value'),
          style: theme.textTheme.headlineSmall?.copyWith(color: context.tone.primaryInk),
        ),
        Slider(
          key: const Key('detour-slider'),
          value: value.toDouble().clamp(detourMinM.toDouble(), detourMaxM.toDouble()),
          min: detourMinM.toDouble(),
          max: detourMaxM.toDouble(),
          divisions: (detourMaxM - detourMinM) ~/ detourStepM,
          label: formatMetres(value),
          semanticFormatterCallback: (v) => formatMetres(v.round()),
          onChanged: locked ? null : (v) => onChanged(clampDetour(v.round())),
        ),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final m in detourChipsM)
              ChoiceChip(
                key: Key('detour-chip-$m'),
                label: Text(formatMetres(m)),
                selected: value == m,
                onSelected: locked ? null : (_) => onChanged(m),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (locked)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.lock_outline, size: 16),
            const SizedBox(width: 4),
            Expanded(child: Text(lockedReason!, key: const Key('detour-locked'))),
          ])
        else
          Text(_helper,
              key: const Key('detour-helper'),
              style: theme.textTheme.bodySmall?.copyWith(color: context.tone.textSecondary)),
      ],
    );
  }
}
