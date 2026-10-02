import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings_p4.dart';
import '../../../core/platform/external_actions.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../profile/presentation/profile_providers.dart';
import '../../sharing/domain/share_companion.dart';
import '../../sharing/presentation/sharing_providers.dart';
import '../../trip/presentation/trip_providers.dart';
import '../domain/safety_models.dart';
import 'safety_providers.dart';
import 'sos_widgets.dart';

/// S-24. Two steps at most: open (tap 1), hold 2 s or tap confirm (tap 2).
/// After confirming, the phone buttons show immediately and nothing waits for
/// the network: the incident is saved locally first and sent in background.
class SosScreen extends ConsumerStatefulWidget {
  const SosScreen({super.key, this.tripId, this.fromChat = false});
  final String? tripId;
  final bool fromChat;

  @override
  ConsumerState<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends ConsumerState<SosScreen> {
  bool _autoShared = false;

  void _confirm() => ref.read(sosControllerProvider.notifier).trigger(
        source: widget.fromChat ? SosSource.chat : SosSource.trip,
        tripId: widget.tripId,
      );

  String? get _tripKey => widget.tripId ?? ref.read(activeTripProvider).valueOrNull?.id;

  /// Best effort and synchronous: whatever is already loaded. Nothing here
  /// may delay or block an SOS (F-R11.4); no data = no driver lines.
  ShareCompanion _companion() {
    final id = _tripKey;
    if (id == null) return const ShareCompanion.none();
    return ref.read(shareCompanionProvider(id)).valueOrNull ?? const ShareCompanion.none();
  }

  String _message(SosUiState s) => buildSosMessage(
        name: ref.read(currentProfileProvider).valueOrNull?.displayName ?? '',
        at: s.event?.clientCreatedAt ?? DateTime.now(),
        location: s.location,
        extraLines: companionLines(_companion()),
      );

  Future<void> _call(String number) async {
    final ok = await ref.read(externalActionsProvider).call(number);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(P.sosCallFailed)));
    }
  }

  Future<void> _share(SosUiState s) => ref.read(externalActionsProvider).shareText(_message(s));

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sosControllerProvider);
    // Local copy first: the list must be usable with no network at all.
    final contacts = ref.watch(contactsProvider).valueOrNull ?? ref.read(contactCacheProvider).read();
    // Prefetch so the text/preview are ready; never awaited by the SOS flow.
    final key = _tripKey;
    final companionAsync = key == null ? null : ref.watch(shareCompanionProvider(key));

    // Open the share sheet once, as soon as the position is known (or known
    // to be unavailable), so the text carries the map link when possible.
    ref.listen(sosControllerProvider, (prev, next) {
      if (next.triggered && next.loc != SosLoc.resolving && !_autoShared && contacts.isNotEmpty) {
        _autoShared = true;
        _share(next);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text(P.sos),
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.pageH),
          children: s.triggered ? _done(s, contacts) : _confirmView(companionAsync),
        ),
      ),
    );
  }

  List<Widget> _confirmView(AsyncValue<ShareCompanion>? companion) {
    final theme = Theme.of(context);
    // While loading (or failed) the rider still gets the honest "name only" line.
    final previewLine = companion == null
        ? null
        : (companion.valueOrNull != null
            ? sosPreviewLine(companion.valueOrNull!)
            : (companion.hasError ? sosPreviewLine(const ShareCompanion.rider(partnerName: '', statusKnown: false)) : null));
    return [
      const SizedBox(height: AppSpacing.lg),
      Text(P.sosTitle, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
      const SizedBox(height: AppSpacing.sm),
      Text(
        P.sosDanger,
        style: theme.textTheme.bodyLarge?.copyWith(color: context.tone.dangerInk, fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: AppSpacing.xl),
      Center(child: HoldToConfirmButton(onConfirmed: _confirm)),
      const SizedBox(height: AppSpacing.xl),
      // Alternative for people who cannot hold (switch access, voice control).
      AppButton(label: P.sosTapConfirm, variant: AppButtonVariant.danger, icon: Icons.sos_outlined, onPressed: _confirm),
      if (previewLine != null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Text(
            previewLine,
            key: const Key('sos-preview-line'),
            style: theme.textTheme.bodyMedium?.copyWith(color: context.tone.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      const SizedBox(height: AppSpacing.md),
      AppButton(
        label: P.sosCancel,
        variant: AppButtonVariant.secondary,
        onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home),
      ),
    ];
  }

  List<Widget> _done(SosUiState s, List<EmergencyContact> contacts) {
    final theme = Theme.of(context);
    final locText = switch (s.loc) {
      SosLoc.resolving => P.sosLocating,
      SosLoc.found => '',
      SosLoc.unavailable => P.sosNoLocation,
    };
    final logText = switch (s.log) {
      SosLog.none || SosLog.saving => P.sosSaving,
      SosLog.saved => P.sosSaved,
      SosLog.queued => P.sosQueued,
    };
    return [
      Row(children: [
        Icon(Icons.check_circle, color: context.tone.dangerInk),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(P.sosDone, style: theme.textTheme.titleLarge)),
      ]),
      const SizedBox(height: AppSpacing.lg),
      // Phone buttons first and large: reachable without scrolling.
      _CallButton(label: P.sosCall191, onPressed: () => _call('191')),
      const SizedBox(height: AppSpacing.md),
      _CallButton(label: P.sosCall1669, onPressed: () => _call('1669')),
      const SizedBox(height: AppSpacing.lg),
      if (locText.isNotEmpty)
        AppCard(
          tone: s.loc == SosLoc.unavailable ? AppCardTone.warning : AppCardTone.plain,
          child: Text(locText),
        ),
      const SizedBox(height: AppSpacing.sm),
      Row(children: [
        Icon(
          s.log == SosLog.queued ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
          size: 18,
          color: s.log == SosLog.queued ? context.tone.warningInk : context.tone.textSecondary,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(logText, key: const Key('sos-log-status'))),
      ]),
      const SizedBox(height: AppSpacing.lg),
      if (contacts.isEmpty)
        AppCard(
          tone: AppCardTone.warning,
          onTap: () => context.push(Routes.safetyContacts),
          child: Row(children: [
            Icon(Icons.person_add_alt, color: context.tone.warningInk),
            const SizedBox(width: AppSpacing.md),
            const Expanded(child: Text(P.sosSetupContacts)),
          ]),
        )
      else ...[
        AppButton(
          label: P.sosShareContacts,
          icon: Icons.ios_share,
          variant: AppButtonVariant.secondary,
          onPressed: () => _share(s),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(P.sosContactsHeader, style: theme.textTheme.titleMedium),
        for (final c in contacts)
          Card(
            child: ListTile(
              minTileHeight: AppSpacing.minTap,
              title: Text(c.name),
              subtitle: Text(c.maskedPhone),
              trailing: Wrap(children: [
                IconButton(
                  tooltip: 'โทรหา ${c.name}',
                  icon: const Icon(Icons.call),
                  onPressed: () => _call(c.phone),
                ),
                IconButton(
                  tooltip: P.sosSmsContact.replaceFirst('%s', c.name),
                  icon: const Icon(Icons.sms_outlined),
                  onPressed: () => ref.read(externalActionsProvider).sms(c.phone, _message(s)),
                ),
              ]),
            ),
          ),
      ],
    ];
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.danger,
            foregroundColor: Colors.white,
            side: context.tone.isDriver ? const BorderSide(color: Colors.white, width: 2) : null,
            minimumSize: const Size.fromHeight(64),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
            textStyle: Theme.of(context).textTheme.titleMedium,
          ),
          onPressed: onPressed,
          icon: const Icon(Icons.call),
          label: Text(label),
        ),
      );
}
