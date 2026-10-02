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

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _adult = false;
  bool _consent = false;
  bool _submitting = false;
  String? _banner;
  String? _emailError;
  String? _passwordError;

  bool get _complete =>
      validateDisplayName(_name.text) == null &&
      validateEmail(_email.text) == null &&
      validatePassword(_password.text) == null &&
      _adult &&
      _consent;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _email, _password]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_complete || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _banner = null;
      _emailError = null;
      _passwordError = null;
    });
    final res = await ref.read(authRepositoryProvider).signUp(
          email: _email.text,
          password: _password.text,
          displayName: _name.text,
        );
    if (!mounted) return;
    res.when(
      ok: (outcome) {
        setState(() => _submitting = false);
        // With a session the router takes over; otherwise ask to verify email.
        if (outcome.needsEmailVerification) {
          context.go('${Routes.verifyEmail}?email=${Uri.encodeQueryComponent(_email.text.trim())}');
        }
      },
      err: (f) => setState(() {
        _submitting = false;
        final offline =
            f.code == FailureCode.networkOffline || f.code == FailureCode.networkTimeout;
        if (f.field == 'email') {
          _emailError = failureMessage(f);
        } else if (f.field == 'password') {
          _passwordError = failureMessage(f);
        } else {
          _banner = offline ? S.signUpNetworkError : failureMessage(f);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locked = _submitting;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: AppLogo(size: MediaQuery.viewInsetsOf(context).bottom > 0 ? 56 : 72)),
                    const SizedBox(height: AppSpacing.md),
                    Text(S.signUp, style: theme.textTheme.titleLarge),
                    const SizedBox(height: AppSpacing.xl),
                    if (_banner != null) ...[
                      AppCard(
                        tone: AppCardTone.error,
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: AppColors.danger),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(child: Text(_banner!)),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    AppTextField(
                      label: S.displayName,
                      controller: _name,
                      enabled: !locked,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.nickname],
                      maxLength: 50,
                      validator: validateDisplayName,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppTextField(
                      label: S.email,
                      controller: _email,
                      enabled: !locked,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newUsername],
                      errorText: _emailError,
                      onChanged: (_) {
                        if (_emailError != null) setState(() => _emailError = null);
                      },
                      validator: validateEmail,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppTextField(
                      label: S.password,
                      controller: _password,
                      enabled: !locked,
                      obscure: true,
                      helper: S.passwordHint,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      errorText: _passwordError,
                      onChanged: (_) {
                        if (_passwordError != null) setState(() => _passwordError = null);
                      },
                      validator: validatePassword,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _adult,
                      onChanged: locked ? null : (v) => setState(() => _adult = v ?? false),
                      title: const Text(S.adultLabel),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _consent,
                      onChanged: locked ? null : (v) => setState(() => _consent = v ?? false),
                      title: const Text('${S.consentPrefix}${S.policy} ${S.and}${S.terms}'),
                    ),
                    // Pushed (not go) so the entered form data survives.
                    Wrap(
                      children: [
                        TextButton(
                          onPressed: () => context.push(Routes.policy),
                          child: const Text(S.policy),
                        ),
                        TextButton(
                          onPressed: () => context.push(Routes.terms),
                          child: const Text(S.terms),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppButton(
                      label: S.signUp,
                      loading: _submitting,
                      onPressed: _complete ? _submit : null,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppButton(
                      label: S.haveAccount,
                      variant: AppButtonVariant.text,
                      onPressed: locked ? null : () => context.pop(),
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
