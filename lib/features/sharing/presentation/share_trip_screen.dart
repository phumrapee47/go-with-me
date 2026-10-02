import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/error/failure_messages.dart';
import '../../../core/error/result.dart';
import '../../../core/l10n/strings_p4.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/platform/external_actions.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/state_view.dart';
import '../../geo/presentation/geo_providers.dart';
import '../../profile/presentation/profile_providers.dart';
import '../../trip/presentation/trip_lifecycle_providers.dart';
import '../domain/share_companion.dart';
import '../domain/trip_share.dart';
import 'sharing_providers.dart';

/// S-23. P0 = plain-text snapshot through the system share sheet: once sent it
/// cannot be recalled and the screen says so. "Stop sharing" exists only for
/// backend links (created when a share page is configured), because only those
/// can really be revoked (PM P-5).
class ShareTripScreen extends ConsumerStatefulWidget {
  const ShareTripScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<ShareTripScreen> createState() => _ShareTripState();
}

class _ShareTripState extends ConsumerState<ShareTripScreen> {
  bool _busy = false;
  bool _sentSnapshot = false;

  void _toast(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _send() async {
    if (_busy) return;
    final trip = ref.read(tripByIdProvider(widget.tripId)).valueOrNull;
    if (trip == null) return;
    setState(() => _busy = true);
    // The plate decision is re-read right before sending (the Driver may have
    // withdrawn consent while this page was open). If the text would differ
    // from the preview the user just saw, show the new preview and stop.
    final shown = ref.read(shareCompanionProvider(widget.tripId)).valueOrNull ?? const ShareCompanion.none();
    ShareCompanion companion = shown;
    var refreshed = true;
    try {
      companion = await ref.refresh(shareCompanionProvider(widget.tripId).future);
    } catch (_) {
      refreshed = false;
      // Unknown status: fall back to what was shown, minus any plate (never blocks).
      companion = shown.kind == CompanionKind.riderSide
          ? ShareCompanion.rider(partnerName: shown.partnerName!, statusKnown: false)
          : shown;
    }
    if (!mounted) return;
    if (refreshed && !companion.sameTextAs(shown)) {
      setState(() => _busy = false); // the provider listener shows the "changed" snackbar
      return;
    }
    Uri? link;
    final base = ref.read(shareWebBaseUrlProvider);
    if (base.isNotEmpty) {
      final res = await ref.read(tripShareRepositoryProvider).create(widget.tripId);
      switch (res) {
        case Ok(:final value):
          link = shareUrl(base, value.token); // token lives only in this local variable
          ref.invalidate(activeSharesProvider);
        case Err():
          if (mounted) {
            setState(() => _busy = false);
            _toast(P.shareFailed);
          }
          return;
      }
    }
    final text = buildTripShareText(
      name: ref.read(currentProfileProvider).valueOrNull?.displayName ?? '',
      trip: trip,
      now: DateTime.now(),
      lastPosition: ref.read(lastFixProvider)?.point,
      link: link,
      companion: companion,
    );
    final ok = await ref.read(externalActionsProvider).shareText(text, subject: P.shareTitle);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok && link == null) _sentSnapshot = true;
    });
    if (!ok) _toast(P.shareUnavailable);
  }

  Future<void> _stop(ActiveShare s) async {
    final ok = await showConfirmDialog(
      context,
      title: P.shareStopTitle,
      body: P.shareStopBody,
      safeLabel: P.shareStopKeep,
      confirmLabel: P.shareStop,
    );
    if (!ok || !mounted) return;
    final res = await ref.read(tripShareRepositoryProvider).revoke(s.id);
    ref.invalidate(activeSharesProvider);
    if (mounted) _toast(res.when(ok: (_) => P.shareStopped, err: failureMessage));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trip = ref.watch(tripByIdProvider(widget.tripId));
    final hasWebPage = ref.watch(shareWebBaseUrlProvider).isNotEmpty;
    final companion = ref.watch(shareCompanionProvider(widget.tripId)).valueOrNull ?? const ShareCompanion.none();
    final previewLine = sharePreviewLine(companion);
    // Q-10: if the Driver flips the switch while this page is open, say so quietly.
    ref.listen<AsyncValue<ShareCompanion>>(shareCompanionProvider(widget.tripId), (prev, next) {
      final a = prev?.valueOrNull;
      final b = next.valueOrNull;
      if (a != null && b != null && !a.sameTextAs(b)) _toast(R.shareChangedSnack);
    });
    final mine = (ref.watch(activeSharesProvider).valueOrNull ?? const <ActiveShare>[])
        .where((s) => s.tripId == widget.tripId)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text(P.shareTitle)),
      body: trip.when(
        loading: () => const StateView.loading(),
        error: (e, _) => StateView.failure(
          e is AppFailure ? e : const AppFailure(FailureCode.unknown),
          onRetry: () => ref.invalidate(tripByIdProvider(widget.tripId)),
        ),
        data: (t) => t == null
            ? const StateView.empty(icon: Icons.route_outlined, title: P.tripNotFound)
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.pageH),
                children: [
                  Text(P.shareIntro, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: AppSpacing.lg),
                  AppCard(
                    tone: AppCardTone.info,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(P.shareWillShare, style: theme.textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.xs),
                      const Text(P.shareWillShareBody),
                      const SizedBox(height: AppSpacing.sm),
                      const Text(P.shareWontShare),
                      if (previewLine != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(previewLine, key: const Key('share-preview-line')),
                      ],
                    ]),
                  ),
                  AppCard(
                    tone: AppCardTone.warning,
                    child: Text(hasWebPage ? P.shareLinkWarning : P.shareSnapshotWarning),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(label: P.shareSend, icon: Icons.ios_share, loading: _busy, onPressed: _send),
                  if (_sentSnapshot)
                    const Padding(
                      padding: EdgeInsets.only(top: AppSpacing.md),
                      child: AppCard(
                        child: Row(children: [
                          Icon(Icons.check_circle_outline, color: AppColors.greenDark),
                          SizedBox(width: AppSpacing.md),
                          Expanded(child: Text(P.shareSentSnapshot)),
                        ]),
                      ),
                    ),
                  for (final s in mine)
                    AppCard(
                      tone: AppCardTone.info,
                      child: Row(children: [
                        Icon(Icons.share_location, color: context.tone.accentInk),
                        const SizedBox(width: AppSpacing.md),
                        const Expanded(child: Text(P.shareActive)),
                        TextButton(onPressed: () => _stop(s), child: const Text(P.shareStop)),
                      ]),
                    ),
                ],
              ),
      ),
    );
  }
}
