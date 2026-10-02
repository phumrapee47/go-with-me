import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_constants.dart';
import '../../../core/error/failure_messages.dart';
import '../../../core/error/result.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/l10n/strings_p4.dart';
import '../../../core/l10n/strings_r5.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/platform/external_actions.dart';
import '../../../core/providers.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../presets/presentation/preset_providers.dart';
import '../../push/presentation/push_providers.dart';
import 'consent_providers.dart';

/// /me/settings (S-31).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(P.settingsTitle)),
      body: ListView(children: [
        ListTile(
          minTileHeight: AppSpacing.minTap,
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text(P.settingsPrivacy),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.settingsPrivacy),
        ),
        ListTile(
          minTileHeight: AppSpacing.minTap,
          leading: const Icon(Icons.notifications_outlined),
          title: const Text(R.notifSettingsRow),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.settingsNotifications),
        ),
        ListTile(
          minTileHeight: AppSpacing.minTap,
          leading: const Icon(Icons.wc_outlined),
          title: const Text('ข้อมูลเพศ (ส่วนตัว)'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.settingsGender),
        ),
        ListTile(
          key: const Key('settings-theme-row'),
          minTileHeight: AppSpacing.minTap,
          leading: const Icon(Icons.dark_mode_outlined),
          title: const Text('รูปแบบธีม'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.settingsTheme),
        ),
        ListTile(
          minTileHeight: AppSpacing.minTap,
          leading: const Icon(Icons.description_outlined),
          title: const Text(S.policy),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.policy),
        ),
        ListTile(
          minTileHeight: AppSpacing.minTap,
          leading: const Icon(Icons.gavel_outlined),
          title: const Text(S.terms),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.terms),
        ),
        const ListTile(leading: Icon(Icons.language), title: Text(P.settingsLanguage)),
        const ListTile(leading: Icon(Icons.map_outlined), title: Text(P.settingsCredit)),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('${AppConstants.appName}  (${P.policyVersionLabel} ${AppConstants.policyVersion})'),
        ),
        const Divider(),
        ListTile(
          minTileHeight: AppSpacing.minTap,
          leading: Icon(Icons.delete_forever_outlined, color: context.tone.dangerInk),
          title: Text(P.deleteAccountRow, style: TextStyle(color: context.tone.dangerInk)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.settingsDeleteAccount),
        ),
      ]),
    );
  }
}

/// /me/settings/privacy: location consent switch, export stub, policy links.
class PrivacySettingsScreen extends ConsumerStatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  ConsumerState<PrivacySettingsScreen> createState() => _PrivacyState();
}

enum _Export { idle, preparing, ready, error }

class _PrivacyState extends ConsumerState<PrivacySettingsScreen> {
  bool _busy = false;
  _Export _export = _Export.idle;
  String? _exportText;

  Future<void> _toggle(bool on) async {
    if (_busy) return;
    if (!on) {
      final ok = await showConfirmDialog(
        context,
        title: P.locationSwitchOffTitle,
        body: P.locationSwitchOffBody,
        safeLabel: P.locationSwitchOffKeep,
        confirmLabel: P.locationSwitchOffConfirm,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    final res = await ref
        .read(consentRepositoryProvider)
        .recordLocationConsent(granted: on, policyVersion: AppConstants.policyVersion);
    ref.invalidate(locationConsentProvider);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(res.when(ok: (_) => P.consentUpdated, err: failureMessage))));
  }

  Future<void> _prepareExport() async {
    setState(() => _export = _Export.preparing);
    final res = await ref.read(accountRepositoryProvider).exportMyData();
    if (!mounted) return;
    switch (res) {
      case Ok(:final value):
        setState(() {
          _export = _Export.ready;
          _exportText = value;
        });
      case Err():
        setState(() => _export = _Export.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final consent = ref.watch(locationConsentProvider);
    final on = consent.valueOrNull ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text(P.privacyTitle)),
      body: ListView(padding: const EdgeInsets.all(AppSpacing.pageH), children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(P.locationSwitch),
          subtitle: Text(on ? P.consentGranted : P.consentNotGranted),
          value: on,
          onChanged: (consent.isLoading || _busy) ? null : _toggle,
        ),
        const Text(P.locationNote),
        const SizedBox(height: AppSpacing.lg),
        // US-24 / E-10: what leaves the app when navigating in an external map app.
        Text(R5.navNoticeTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(R5.navNoticeBody('จุดรับหรือปลายทางของคุณ')),
        const SizedBox(height: AppSpacing.lg),
        Text(P.exportData, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        const Text(P.exportNote),
        const SizedBox(height: AppSpacing.sm),
        switch (_export) {
          _Export.idle || _Export.error => Column(children: [
              if (_export == _Export.error)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text('เตรียมข้อมูลไม่สำเร็จ ลองใหม่อีกครั้ง', style: TextStyle(color: context.tone.dangerInk)),
                ),
                AppButton(
                  label: P.exportData,
                  variant: AppButtonVariant.secondary,
                  icon: Icons.download_outlined,
                  onPressed: _prepareExport,
                ),
              ]),
          _Export.preparing => const AppButton(label: P.exportPreparing, loading: true, onPressed: null),
          _Export.ready => Column(children: [
              const Text(P.exportReady),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: P.exportShare,
                icon: Icons.ios_share,
                onPressed: () => ref.read(externalActionsProvider).shareText(_exportText ?? ''),
              ),
            ]),
        },
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: P.viewPolicy,
          variant: AppButtonVariant.text,
          onPressed: () => context.push(Routes.policy),
        ),
        AppButton(
          label: P.viewTerms,
          variant: AppButtonVariant.text,
          onPressed: () => context.push(Routes.terms),
        ),
      ]),
    );
  }
}

/// /me/settings/delete-account (PM P-8): explain, type the phrase, confirm,
/// delete immediately and sign out. Irreversible, so two deliberate steps.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountState();
}

class _DeleteAccountState extends ConsumerState<DeleteAccountScreen> {
  final _phrase = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _phrase.dispose();
    super.dispose();
  }

  bool get _matches => _phrase.text.trim() == P.deletePhrase;

  Future<void> _delete() async {
    if (!_matches || _busy) return;
    final ok = await showConfirmDialog(
      context,
      title: P.deleteConfirmTitle,
      body: P.deleteConfirmBody,
      safeLabel: P.deleteConfirmKeep,
      confirmLabel: P.deleteConfirmYes,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final res = await ref.read(accountRepositoryProvider).requestAccountDeletion();
    if (!mounted) return;
    switch (res) {
      case Ok():
        // Clear everything kept on this device (contacts cache, SOS queue,
        // chat markers), then sign out: the router guard shows sign-in.
        // R7.4 (Q1): only this device's token, never every device.
        await ref.read(pushControllerProvider).unregisterThisDevice();
        await ref.read(sharedPrefsProvider).clear();
        await ref.read(presetsProvider.notifier).clearAll();
        await ref.read(authRepositoryProvider).signOut();
      case Err(:final failure):
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failureMessage(failure))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(P.deleteTitle)),
      body: ListView(padding: const EdgeInsets.all(AppSpacing.pageH), children: [
        const AppCard(tone: AppCardTone.error, child: Text(P.deleteWhat)),
        const SizedBox(height: AppSpacing.md),
        Text(P.deleteNote, style: theme.textTheme.bodyLarge),
        const SizedBox(height: AppSpacing.sm),
        Text(P.deleteIrreversible, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _phrase,
          decoration: const InputDecoration(labelText: P.deleteTypeHint),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: P.deleteButton,
          variant: AppButtonVariant.danger,
          loading: _busy,
          onPressed: _matches ? _delete : null,
        ),
      ]),
    );
  }
}
