import 'package:flutter/material.dart';

import '../error/app_failure.dart';
import '../error/failure_messages.dart';
import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tone.dart';
import 'app_button.dart';

/// C-4. One widget for the loading / empty / error states of every screen.
class StateView extends StatelessWidget {
  const StateView.loading({super.key, this.message})
      : icon = null,
        title = null,
        actionLabel = null,
        onAction = null,
        _kind = _Kind.loading;

  const StateView.empty({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  }) : _kind = _Kind.empty;

  const StateView.error({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.error_outline,
    this.actionLabel = S.retry,
    this.onAction,
  }) : _kind = _Kind.error;

  /// Error state built from a failure; never shows internal codes.
  factory StateView.failure(AppFailure failure, {Key? key, VoidCallback? onRetry}) {
    final offline = failure.code == FailureCode.networkOffline;
    return StateView.error(
      key: key,
      title: failureMessage(failure),
      icon: offline ? Icons.wifi_off_outlined : Icons.error_outline,
      onAction: onRetry,
      actionLabel: onRetry == null ? null : S.retry,
    );
  }

  final _Kind _kind;
  final IconData? icon;
  final String? title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_kind == _Kind.loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(message!, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      );
    }
    final isError = _kind == _Kind.error;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: isError ? context.tone.dangerTint : context.tone.infoBg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 40,
                color: isError ? context.tone.dangerInk : context.tone.accentInk,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(title!, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(color: context.tone.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: actionLabel!,
                onPressed: onAction,
                variant: isError ? AppButtonVariant.secondary : AppButtonVariant.primary,
                expand: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _Kind { loading, empty, error }
