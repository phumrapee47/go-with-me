import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_constants.dart';
import '../../../core/error/failure_messages.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';
import 'auth_providers.dart';

/// T4.28: shown after sign-up (Confirm email = ON) and when sign-in reports
/// an unconfirmed email. Works signed-out (email from query) or signed-in.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, this.email});

  final String? email;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  Timer? _timer;
  int _cooldown = 0;
  bool _sending = false;
  String? _message;
  bool _isError = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _email => widget.email ?? ref.read(authUserProvider).valueOrNull?.email ?? '';

  void _startCooldown() {
    _cooldown = AppConstants.resendCooldown.inSeconds;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _resend() async {
    if (_sending || _cooldown > 0 || _email.isEmpty) return;
    setState(() {
      _sending = true;
      _message = null;
    });
    final res = await ref.read(authRepositoryProvider).resendVerification(_email);
    if (!mounted) return;
    res.when(
      ok: (_) {
        _message = S.verifyResent;
        _isError = false;
        _startCooldown();
      },
      err: (f) {
        _message = failureMessage(f);
        _isError = true;
        if (f.retryAfter != null) _startCooldown();
      },
    );
    setState(() => _sending = false);
  }

  Future<void> _goSignIn() async {
    // A signed-in but unconfirmed session must be dropped first, or the
    // guard would send us straight back here.
    if (ref.read(authUserProvider).valueOrNull != null) {
      await ref.read(authRepositoryProvider).signOut();
    }
    if (mounted) context.go(Routes.signIn);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = _email;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.mark_email_unread_outlined, size: 56, color: AppColors.blue),
                  const SizedBox(height: AppSpacing.lg),
                  Text(S.verifyTitle, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
                  const SizedBox(height: AppSpacing.md),
                  if (email.isNotEmpty)
                    Text(
                      email,
                      style: theme.textTheme.labelLarge,
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: AppSpacing.md),
                  const Text(S.verifyBody, textAlign: TextAlign.center),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    S.verifyHintSpam,
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (_message != null) ...[
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _isError ? AppColors.danger : AppColors.greenDark,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  AppButton(label: S.verifyGoSignIn, onPressed: _goSignIn),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: _cooldown > 0 ? '${S.verifyResend} ($_cooldown)' : S.verifyResend,
                    variant: AppButtonVariant.secondary,
                    loading: _sending,
                    onPressed: (_cooldown > 0 || email.isEmpty) ? null : _resend,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
