import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/strings_roles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../domain/vehicle.dart';

Color? _colorFor(String name) {
  final n = name.trim();
  if (n.contains('ขาว')) return Colors.white;
  if (n.contains('ดำ')) return Colors.black;
  if (n.contains('เทา') || n.contains('เงิน')) return Colors.grey;
  if (n.contains('แดง')) return const Color(0xFFC53030);
  if (n.contains('น้ำเงิน') || n.contains('ฟ้า')) return AppColors.blue;
  return null;
}

/// C-34. Shown to the owner (preview) and to a Rider whose request the Driver
/// accepted. The colour dot is decoration only: the colour name is always text.
/// The plate is real text (scales, wraps) and read letter by letter by screen readers.
class VehicleInfoCard extends StatelessWidget {
  const VehicleInfoCard({
    super.key,
    required this.title,
    required this.plate,
    required this.model,
    required this.color,
    this.compact = false,
    this.highlight,
  });

  factory VehicleInfoCard.forRider(VehicleView v, {Key? key, bool compact = false, String? highlight}) =>
      VehicleInfoCard(
        key: key,
        title: R.cardTitle,
        plate: v.plate,
        model: v.model,
        color: v.color,
        compact: compact,
        highlight: highlight,
      );

  factory VehicleInfoCard.ownerPreview(Vehicle v, {Key? key}) =>
      VehicleInfoCard(key: key, title: R.ownerPreviewTitle, plate: v.plate, model: v.model, color: v.color);

  final String title;
  final String plate;
  final String model;
  final String color;
  final bool compact;

  /// Optional pill, e.g. "เพิ่งจับคู่".
  final String? highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dot = _colorFor(color);
    if (compact) {
      return AppCard(
        tone: AppCardTone.info,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(children: [
          Icon(Icons.directions_car_outlined, color: context.tone.text),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Semantics(
              label: '${R.plate} ${plate.split('').join(' ')} $model สี $color',
              excludeSemantics: true,
              child: Text('$plate · $model · $color', key: const Key('vehicle-compact-line')),
            ),
          ),
        ]),
      );
    }
    return AppCard(
      tone: AppCardTone.info,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.directions_car_outlined, color: context.tone.text),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
          if (highlight != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
              decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(AppRadius.pill)),
              child: Text(highlight!, style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w600)),
            ),
        ]),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          label: '${R.plate} ${plate.split('').join(' ')}',
          excludeSemantics: true,
          child: Text(
            plate,
            key: const Key('vehicle-plate'),
            style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 1.5, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(model, key: const Key('vehicle-model')),
        const SizedBox(height: AppSpacing.xs),
        Row(children: [
          if (dot != null) ...[
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle, border: Border.all(color: context.tone.border)),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(child: Text('${R.color}: $color', key: const Key('vehicle-color'))),
        ]),
        const SizedBox(height: AppSpacing.sm),
        Text(R.unverified, style: theme.textTheme.bodyMedium?.copyWith(color: context.tone.textSecondary)),
      ]),
    );
  }
}

/// C-38 (Driver): the plate-forwarding consent switch. OFF by default. Not tied
/// to saving the vehicle. The switch only moves after the server confirmed
/// ([busy] disables it meanwhile); a failure leaves it where it was.
class ShareConsentSwitch extends StatelessWidget {
  const ShareConsentSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.busy = false,
    this.showWithdrawNotice = false,
    this.errorText,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool busy;
  final bool showWithdrawNotice;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stateText = busy ? R.shareSaving : (value ? R.shareOnState : R.shareOffState);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
          container: true,
          liveRegion: true,
          child: SwitchListTile(
            key: const Key('share-consent-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text(R.shareSwitch),
            subtitle: Text(stateText, key: const Key('share-consent-state')),
            value: value,
            onChanged: busy ? null : onChanged,
          ),
        ),
        Text(R.shareDesc, style: theme.textTheme.bodyMedium?.copyWith(color: context.tone.textSecondary)),
        if (showWithdrawNotice && !value) ...[
          const SizedBox(height: AppSpacing.sm),
          const Text(R.shareWithdrawNotice, key: Key('share-withdraw-notice')),
        ],
        if (errorText != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(errorText!, style: TextStyle(color: context.tone.dangerInk)),
        ],
      ]),
    );
  }
}

/// C-38 (Rider): read-only status of the Driver's consent. Never reveals the
/// vehicle itself; never blocks share/SOS when it cannot be loaded.
class ShareConsentStatus extends StatelessWidget {
  const ShareConsentStatus({super.key, required this.view});
  final AsyncValue<VehicleView?> view;

  @override
  Widget build(BuildContext context) {
    return view.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const _StatusRow(Icons.info_outline, R.plateShareError),
      data: (v) {
        if (v == null) return const SizedBox.shrink();
        return v.shareAllowed
            ? const _StatusRow(Icons.check_circle_outline, R.plateShareAllowed, key: Key('consent-allowed'))
            : const _StatusRow(Icons.do_not_disturb_on_outlined, R.plateShareDenied, key: Key('consent-denied'));
      },
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow(this.icon, this.text, {super.key});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Semantics(
          liveRegion: true,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 20, color: context.tone.text),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(text)),
          ]),
        ),
      );
}

/// Error card with a retry button (vehicle failed to load).
class VehicleLoadError extends StatelessWidget {
  const VehicleLoadError({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => AppCard(
        tone: AppCardTone.error,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(R.vehicleLoadFailed),
          AppButton(label: R.retry, variant: AppButtonVariant.text, expand: false, onPressed: onRetry),
        ]),
      );
}
