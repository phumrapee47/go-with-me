import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings_roles.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import 'matching_providers.dart';

/// Sits above the whole navigator (MaterialApp `builder`) so the "match ended"
/// alert (DriverCancelledAlert, C-37) shows from ANY screen (Q-7). Wording is
/// neutral: no reason, no name, no plate. It stays until acknowledged or a
/// shortcut is used; it never auto-dismisses.
class MatchAlertHost extends ConsumerWidget {
  const MatchAlertHost({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alert = ref.watch(matchAlertProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (alert != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: _AlertCard(
                  onSos: () => _go(ref, Routes.sosFor(tripId: alert.tripId)),
                  onShare: () => _go(ref, Routes.tripShare(alert.tripId)),
                  onArrived: () => _go(ref, Routes.tripActive(alert.tripId)),
                  onCancelTrip: () => _go(ref, Routes.tripDetail(alert.tripId)),
                  onAck: () => ref.read(matchAlertProvider.notifier).dismiss(),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _go(WidgetRef ref, String location) {
    ref.read(matchAlertProvider.notifier).dismiss();
    router.push(location);
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.onSos,
    required this.onShare,
    required this.onArrived,
    required this.onCancelTrip,
    required this.onAck,
  });

  final VoidCallback onSos;
  final VoidCallback onShare;
  final VoidCallback onArrived;
  final VoidCallback onCancelTrip;
  final VoidCallback onAck;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const Key('match-alert'),
      elevation: 6,
      color: context.tone.dangerTint,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        // Assertive, announced once (built once; never re-announced by rebuilds).
        child: Semantics(
          liveRegion: true,
          container: true,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.warning_amber_rounded, color: context.tone.dangerInk),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(R.alertTitle, style: theme.textTheme.titleMedium)),
                ]),
                const SizedBox(height: AppSpacing.sm),
                const Text(R.alertSafety),
                const SizedBox(height: AppSpacing.md),
                // SOS first in focus order; all three >= 56 dp.
                Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
                  SizedBox(
                    height: 56,
                    child: AppButton(
                      key: const Key('alert-sos'),
                      label: 'SOS',
                      expand: false,
                      variant: AppButtonVariant.danger,
                      icon: Icons.sos_outlined,
                      onPressed: onSos,
                    ),
                  ),
                  SizedBox(
                    height: 56,
                    child: AppButton(
                      key: const Key('alert-share'),
                      label: R.alertShare,
                      expand: false,
                      variant: AppButtonVariant.secondary,
                      icon: Icons.ios_share,
                      onPressed: onShare,
                    ),
                  ),
                  SizedBox(
                    height: 56,
                    child: AppButton(
                      key: const Key('alert-arrived'),
                      label: R.alertArrived,
                      expand: false,
                      variant: AppButtonVariant.success,
                      icon: Icons.home_outlined,
                      onPressed: onArrived,
                    ),
                  ),
                ]),
                Wrap(children: [
                  TextButton(
                    key: const Key('alert-cancel-trip'),
                    style: TextButton.styleFrom(minimumSize: const Size(0, AppSpacing.minTap)),
                    onPressed: onCancelTrip,
                    child: const Text(R.alertCancelTrip),
                  ),
                  TextButton(
                    key: const Key('alert-ack'),
                    style: TextButton.styleFrom(minimumSize: const Size(0, AppSpacing.minTap)),
                    onPressed: onAck,
                    child: const Text(R.alertAck),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
