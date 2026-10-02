import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/error/failure_messages.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/app_text_field.dart';
import 'auth_providers.dart';
import 'auth_validators.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final res = await ref
        .read(authRepositoryProvider)
        .signIn(email: _email.text, password: _password.text);
    if (!mounted) return;
    res.when(
      ok: (_) => setState(() => _submitting = false), // router redirects on auth change
      err: (f) {
        if (f.code == FailureCode.authEmailUnconfirmed) {
          context.go('${Routes.verifyEmail}?email=${Uri.encodeQueryComponent(_email.text.trim())}');
          return;
        }
        setState(() {
          _submitting = false;
          _error = f.code == FailureCode.networkOffline || f.code == FailureCode.networkTimeout
              ? S.signInNetworkError
              : failureMessage(f);
          // Keep the email, clear only the password (US-3).
          if (f.code == FailureCode.authInvalidCredentials) _password.clear();
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppLogo(size: MediaQuery.viewInsetsOf(context).bottom > 0 ? 56 : 72),
                    const SizedBox(height: AppSpacing.lg),
                    Text(S.signIn, style: theme.textTheme.titleLarge),
                    const SizedBox(height: AppSpacing.xl),
                    if (_error != null) ...[
                      AppCard(
                        tone: AppCardTone.error,
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: AppColors.danger),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(child: Text(_error!)),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    AppTextField(
                      label: S.email,
                      controller: _email,
                      enabled: !_submitting,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      validator: validateEmail,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppTextField(
                      label: S.password,
                      controller: _password,
                      enabled: !_submitting,
                      obscure: true,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      validator: (v) => (v == null || v.isEmpty) ? S.errPasswordEmpty : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AppButton(label: S.signIn, loading: _submitting, onPressed: _submit),
                    const SizedBox(height: AppSpacing.sm),
                    AppButton(
                      label: S.noAccount,
                      variant: AppButtonVariant.text,
                      onPressed: _submitting ? null : () => context.push(Routes.signUp),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
