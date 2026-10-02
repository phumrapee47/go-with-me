import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/tone.dart';

/// Bordered surface card; `tone` picks the info/warning/error banner colours.
enum AppCardTone { plain, info, warning, error }

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.tone = AppCardTone.plain,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final Widget child;
  final AppCardTone tone;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      AppCardTone.plain => context.tone.surface,
      AppCardTone.info => context.tone.infoBg,
      AppCardTone.warning => context.tone.warningTint,
      AppCardTone.error => context.tone.dangerTint,
    };
    return Card(
      color: color,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
