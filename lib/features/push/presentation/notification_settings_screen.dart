import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/strings_roles.dart';
import '../../../core/theme/tokens.dart';
import '../../chat/presentation/quick_voice_providers.dart';
import 'push_permission_sheet.dart';
import 'push_providers.dart';
import 'push_service.dart';

/// G-2 NotificationSettingsScreen (/me/settings/notifications, design-spec-
/// round7 G.1.3). Single master toggle only this round (Q-G1) — the DB
/// schema (`device_tokens`) has no per-kind preference column, and per-kind
/// would need a new /db-architect pass out of this stage's scope.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen> {
  PushPermissionStatus? _os;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final status = await ref.read(pushControllerProvider).currentPermission();
    if (mounted) setState(() => _os = status);
  }

  Future<void> _toggleMaster(bool on) async {
    if (_saving) return;
    setState(() => _saving = true);
    if (on && _os != PushPermissionStatus.granted) {
      // OS never asked yet: reuse G-1 instead of a second permission flow.
      await maybeShowPushPermissionSheet(context, ref);
      await _load();
      if (mounted) setState(() => _saving = false);
      return;
    }
    await ref.read(pushControllerProvider).setMasterEnabled(on);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(on ? R.notifMasterOn : R.notifMasterOff)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final os = _os;
    final osDenied = os == PushPermissionStatus.denied;
    final masterOn = ref.read(pushControllerProvider).masterEnabled && !osDenied;
    return Scaffold(
      appBar: AppBar(title: const Text(R.notifSettingsTitle)),
      body: os == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.pageH),
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(osDenied ? Icons.notifications_off_outlined : Icons.notifications_active_outlined),
                  title: Text(osDenied ? R.notifOsOff : R.notifOsOn),
                  trailing: osDenied
                      ? TextButton(
                          onPressed: () => ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text(R.notifOsOpenSettings))),
                          child: const Text(R.notifOsOpenSettings),
                        )
                      : null,
                ),
                const Divider(),
                SwitchListTile(
                  key: const Key('notif-master-toggle'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text(R.notifMaster),
                  subtitle: Text(masterOn ? R.notifMasterOn : R.notifMasterOff),
                  value: masterOn,
                  onChanged: (osDenied || _saving) ? null : _toggleMaster,
                ),
                const Divider(),
                // US-48(B) round 7: reads incoming quick-voice preset chat messages aloud
                // on this device via on-device TTS. Off = normal message/notification only.
                SwitchListTile(
                  key: const Key('quick-voice-tts-toggle'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('อ่านข้อความด่วนออกเสียง'),
                  subtitle: const Text('อ่านวลีสำเร็จรูป (เช่น "ถึงจุดนัดรับแล้ว") ออกเสียงอัตโนมัติเมื่อได้รับ'),
                  value: ref.watch(quickVoiceTtsEnabledProvider),
                  onChanged: (v) => ref.read(quickVoiceTtsEnabledProvider.notifier).setEnabled(v),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(R.notifEventsListTitle, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                const _EventRow(R.notifEventNewRequest),
                const _EventRow(R.notifEventMatchAccepted),
                const _EventRow(R.notifEventNewMessage),
                const _EventRow(R.notifEventDriverArrived),
                const _EventRow(R.notifEventCancelled),
              ],
            ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          const Icon(Icons.check, size: 16),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text)),
        ]),
      );
}
