import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tone.dart';

enum AppButtonVariant { primary, secondary, tonal, success, danger, text }

/// C-1. Height is min 48 and grows with text scale (never fixed).
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.loading = false,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool loading;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final enabled = onPressed != null && !loading;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.control),
    );
    const minSize = Size(AppSpacing.minTap, AppSpacing.minTap);
    final onTap = enabled ? onPressed : null;

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading) ...[
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.sm),
        ] else if (icon != null) ...[
          Icon(icon, size: 20),
          const SizedBox(width: AppSpacing.sm),
        ],
        Flexible(
          child: Text(
            loading ? S.loading : label,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );

    final Widget button = switch (variant) {
      AppButtonVariant.secondary => OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            minimumSize: minSize,
            shape: shape,
            foregroundColor: tone.primaryInk,
            side: BorderSide(color: enabled ? tone.primaryInk : tone.border, width: 1.5),
          ),
          child: child,
        ),
      AppButtonVariant.text => TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            minimumSize: minSize,
            shape: shape,
            foregroundColor: tone.primaryInk,
          ),
          child: child,
        ),
      _ => FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            minimumSize: minSize,
            shape: shape,
            backgroundColor: switch (variant) {
              AppButtonVariant.tonal => tone.infoBg,
              AppButtonVariant.success => tone.successFill,
              AppButtonVariant.danger => tone.danger,
              _ => tone.primary,
            },
            // Green/mint backgrounds use navy text for contrast (design-spec 1.1); amber uses navy too.
            foregroundColor: switch (variant) {
              AppButtonVariant.tonal => tone.text,
              AppButtonVariant.success => tone.onSuccessFill,
              AppButtonVariant.danger => Colors.white,
              _ => tone.onPrimary,
            },
            disabledBackgroundColor: tone.isDriver ? tone.surfaceRaised : tone.border,
            disabledForegroundColor: tone.isDriver ? tone.textDisabled : tone.textSecondary,
          ),
          child: child,
        ),
    };

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
