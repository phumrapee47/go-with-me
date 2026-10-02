import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/error/failure_messages.dart';
import '../../../core/l10n/strings_p4.dart';
import '../../../core/platform/external_actions.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/state_view.dart';
import '../../sharing/domain/trip_share.dart';
import '../../sharing/presentation/sharing_providers.dart';
import '../domain/safety_models.dart';
import 'safety_providers.dart';

/// S-25: contacts, emergency numbers, active share links and tips.
class SafetyScreen extends ConsumerWidget {
  const SafetyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final contacts = ref.watch(contactsProvider);
    final shares = ref.watch(activeSharesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(P.safetyTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.pageH),
        children: [
          AppCard(
            onTap: () => context.push(Routes.safetyContacts),
            child: Row(children: [
              Icon(Icons.contact_phone_outlined, color: context.tone.primaryInk),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(P.contactsTitle, style: theme.textTheme.titleMedium),
                  Text(contacts.when(
                    loading: () => '...',
                    error: (_, _) => 'โหลดไม่สำเร็จ แตะเพื่อลองใหม่',
                    data: (l) => l.isEmpty ? P.contactsEmptyBody : P.contactsCount.replaceFirst('%s', '${l.length}'),
                  )),
                ]),
              ),
              const Icon(Icons.chevron_right),
            ]),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(P.emergencyNumbers, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          const Row(children: [
            Expanded(child: _CallTile(P.sosCall191, '191')),
            SizedBox(width: AppSpacing.md),
            Expanded(child: _CallTile(P.sosCall1669, '1669')),
          ]),
          const SizedBox(height: AppSpacing.lg),
          Text(P.activeShares, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          ...shares.when(
            loading: () => [const SizedBox(height: 60, child: StateView.loading())],
            error: (e, _) => [
              StateView.failure(e is AppFailure ? e : const AppFailure(FailureCode.unknown),
                  onRetry: () => ref.invalidate(activeSharesProvider)),
            ],
            data: (l) => l.isEmpty
                ? const [Text(P.noShares)]
                : [for (final s in l) _ShareTile(share: s)],
          ),
          const SizedBox(height: AppSpacing.lg),
          Card(
            child: ExpansionTile(
              title: Text(P.safetyTips, style: theme.textTheme.titleMedium),
              initiallyExpanded: true,
              childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _Tip(P.tip1),
                _Tip(P.tip2),
                _Tip(P.tip3),
                _Tip(P.tip4),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: P.meBlocked,
            variant: AppButtonVariant.secondary,
            icon: Icons.block,
            onPressed: () => context.push(Routes.blocked),
          ),
        ],
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.check, size: 18, color: AppColors.greenDark),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text)),
        ]),
      );
}

class _CallTile extends ConsumerWidget {
  const _CallTile(this.label, this.number);
  final String label;
  final String number;

  @override
  Widget build(BuildContext context, WidgetRef ref) => FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.danger,
          foregroundColor: Colors.white,
          side: context.tone.isDriver ? const BorderSide(color: Colors.white, width: 2) : null,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
        ),
        onPressed: () => ref.read(externalActionsProvider).call(number),
        icon: const Icon(Icons.call),
        label: Text(label, textAlign: TextAlign.center),
      );
}

/// C-21 for a backend share link: "หยุดแชร์" only exists here, because only a
/// link with a server-side token can be revoked (PM P-5).
class _ShareTile extends ConsumerWidget {
  const _ShareTile({required this.share});
  final ActiveShare share;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      tone: AppCardTone.info,
      child: Row(children: [
        Icon(Icons.share_location, color: context.tone.accentInk),
        const SizedBox(width: AppSpacing.md),
        const Expanded(child: Text(P.shareActive)),
        TextButton(
          onPressed: () async {
            final ok = await showConfirmDialog(
              context,
              title: P.shareStopTitle,
              body: P.shareStopBody,
              safeLabel: P.shareStopKeep,
              confirmLabel: P.shareStop,
            );
            if (!ok || !context.mounted) return;
            final res = await ref.read(tripShareRepositoryProvider).revoke(share.id);
            ref.invalidate(activeSharesProvider);
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(res.when(ok: (_) => P.shareStopped, err: failureMessage))));
            }
          },
          child: const Text(P.shareStop),
        ),
      ]),
    );
  }
}

/// S-32: report a user (optionally block at the same time).
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key, required this.userId, this.matchId, this.name});
  final String userId;
  final String? matchId;
  final String? name;

  @override
  ConsumerState<ReportScreen> createState() => _ReportState();
}

class _ReportState extends ConsumerState<ReportScreen> {
  ReportReason? _reason;
  final _details = TextEditingController();
  bool _alsoBlock = false;
  bool _busy = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || _busy) return;
    setState(() => _busy = true);
    final repo = ref.read(safetyRepositoryProvider);
    final res = await repo.report(
      userId: widget.userId,
      matchId: widget.matchId,
      reason: reason,
      details: _details.text,
    );
    if (res.when(ok: (_) => false, err: (_) => true)) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.when(ok: (_) => '', err: failureMessage))));
      }
      return;
    }
    if (_alsoBlock) {
      await repo.block(widget.userId);
      ref.invalidate(blockedUsersProvider);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(P.reportThanks)));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.name == null ? P.reportTitle : '${P.reportTitle}: ${widget.name}')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.pageH),
        children: [
          Text(P.reportReason, style: theme.textTheme.titleMedium),
          RadioGroup<ReportReason>(
            groupValue: _reason,
            onChanged: (v) => setState(() => _reason = v),
            child: Column(children: [
              for (final r in ReportReason.values)
                RadioListTile<ReportReason>(value: r, title: Text(r.label), contentPadding: EdgeInsets.zero),
            ]),
          ),
          TextField(
            controller: _details,
            maxLength: 1000,
            maxLines: 4,
            decoration: const InputDecoration(labelText: P.reportDetails),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _alsoBlock,
            onChanged: (v) => setState(() => _alsoBlock = v ?? false),
            title: const Text(P.reportAlsoBlock),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(label: P.reportSubmit, loading: _busy, onPressed: _reason == null ? null : _submit),
        ],
      ),
    );
  }
}

/// /me/blocked: list and unblock.
class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(blockedUsersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(P.blockedTitle)),
      body: list.when(
        loading: () => const StateView.loading(),
        error: (e, _) => StateView.failure(
          e is AppFailure ? e : const AppFailure(FailureCode.unknown),
          onRetry: () => ref.invalidate(blockedUsersProvider),
        ),
        data: (l) => l.isEmpty
            ? const StateView.empty(icon: Icons.block, title: P.blockedEmpty)
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.pageH),
                children: [
                  for (final b in l)
                    Card(
                      child: ListTile(
                        minTileHeight: AppSpacing.minTap,
                        leading: const Icon(Icons.block),
                        title: Text(b.displayName ?? P.blockedUnknownName),
                        trailing: TextButton(
                          onPressed: () async {
                            final ok = await showConfirmDialog(
                              context,
                              title: P.unblockTitle,
                              body: P.unblockBody,
                              safeLabel: P.chatBlockKeep,
                              confirmLabel: P.unblock,
                              destructive: false,
                            );
                            if (!ok || !context.mounted) return;
                            final res = await ref.read(blockedUsersProvider.notifier).unblock(b.userId);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(res.when(ok: (_) => P.unblockDone, err: failureMessage))));
                            }
                          },
                          child: const Text(P.unblock),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
