import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure_messages.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/l10n/strings_r5.dart';
import '../../../core/l10n/strings_trip.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/auth_validators.dart';
import '../../avatar/presentation/user_avatar.dart';
import 'profile_providers.dart';

/// S-08 / S-28: display name backed by the `profiles` row (the router guard
/// reads the same row, so there is no local "setup done" flag any more).
/// Photo upload and emergency contacts are not part of this round.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key, this.editMode = false});

  /// True when opened from /me/edit (back button, returns to previous page).
  final bool editMode;

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: ref.read(currentProfileProvider).valueOrNull?.displayName.isNotEmpty == true
        ? ref.read(currentProfileProvider).value!.displayName
        : (ref.read(authUserProvider).valueOrNull?.displayName ?? ''),
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final res = await saveDisplayName(ref, _name.text);
    if (!mounted) return;
    res.when(
      ok: (_) {
        setState(() => _saving = false);
        if (widget.editMode) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(T.profileSaved)));
          if (context.canPop()) context.pop();
        }
        // Setup mode: the guard sees a usable name and redirects to /home.
      },
      err: (f) => setState(() {
        _saving = false;
        _error = failureMessage(f);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: widget.editMode ? AppBar(title: const Text(T.editProfile)) : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!widget.editMode) ...[
                      Text(S.setupTitle, style: theme.textTheme.titleLarge),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                    Center(
                      child: widget.editMode
                          ? Column(mainAxisSize: MainAxisSize.min, children: [
                              UserAvatar.mine(name: _name.text, size: 96, onTap: () => context.push(Routes.mePhoto)),
                              TextButton(
                                key: const Key('edit-photo-link'),
                                onPressed: () => context.push(Routes.mePhoto),
                                child: const Text(R5.photoChange),
                              ),
                            ])
                          : AvatarInitial(name: _name.text, radius: 40),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AppTextField(
                      label: S.displayName,
                      controller: _name,
                      enabled: !_saving,
                      maxLength: 50,
                      validator: validateDisplayName,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AppCard(
                      tone: AppCardTone.info,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(S.setupContacts, style: theme.textTheme.titleMedium),
                          const SizedBox(height: AppSpacing.sm),
                          const Text(S.setupContactsBody),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Text(_error!, style: TextStyle(color: context.tone.dangerInk)),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    AppButton(
                      label: widget.editMode ? T.save : S.setupDone,
                      loading: _saving,
                      onPressed: _save,
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
