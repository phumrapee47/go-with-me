import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/tone.dart';

/// C-23. Safe option first; labels must describe the action, not "OK/Cancel".
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String safeLabel,
  required String confirmLabel,
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(safeLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: destructive ? AppColors.danger : ctx.tone.primary,
            foregroundColor: destructive ? Colors.white : ctx.tone.onPrimary,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
