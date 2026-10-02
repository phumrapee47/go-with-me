import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// C-3 (minimal). Always icon + text, never colour alone.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, required this.label, this.verified = true});

  final String label;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final fg = verified ? AppColors.greenDark : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: verified ? AppColors.mint : AppColors.border.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(verified ? Icons.verified_outlined : Icons.help_outline, size: 16, color: fg),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
