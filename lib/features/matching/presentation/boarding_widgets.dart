import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/error/failure_messages.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../trip/domain/trip.dart';
import '../domain/match_models.dart';
import 'matching_providers.dart';

String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// C-36 as a pure widget so every state can be tested without providers.
/// [disabledReason] must always be visible text (TalkBack skips disabled buttons).
class BoardingButton extends StatelessWidget {
  const BoardingButton({
    super.key,
    required this.boardedAt,
    required this.busy,
    required this.disabledReason,
    required this.onPressed,
    this.error,
  });

  final DateTime? boardedAt;
  final bool busy;
  final String? disabledReason;
  final VoidCallback onPressed;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (boardedAt != null) {
      return Semantics(
        liveRegion: true,
        child: AppCard(
          tone: AppCardTone.info,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.check_circle, color: AppColors.greenDark),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  R.boardDone(_hhmm(boardedAt!)),
                  key: const Key('boarded-done'),
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ]),
            const SizedBox(height: AppSpacing.xs),
            const Text(R.boardLocationStopped, key: Key('board-location-stopped')),
          ]),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 56,
        child: AppButton(
          key: const Key('board-button'),
          label: R.boardButton,
          icon: Icons.airline_seat_recline_normal,
          variant: AppButtonVariant.success,
          loading: busy,
          onPressed: disabledReason == null ? onPressed : null,
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Text(
          disabledReason ?? R.boardOptionalNote,
          key: const Key('board-note'),
          style: theme.textTheme.bodyMedium?.copyWith(color: context.tone.textSecondary),
        ),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(error!, key: const Key('board-error'), style: TextStyle(color: context.tone.dangerInk)),
        ),
    ]);
  }
}

/// Rider side of the active-trip page: "ขึ้นรถแล้ว".
class RiderBoardingSection extends ConsumerStatefulWidget {
  const RiderBoardingSection({super.key, required this.match, required this.myTrip});
  final MatchSummary match;
  final Trip myTrip;

  @override
  ConsumerState<RiderBoardingSection> createState() => _RiderBoardingState();
}

class _RiderBoardingState extends ConsumerState<RiderBoardingSection> {
  bool _busy = false;
  String? _error;

  Future<void> _board() async {
    if (_busy) return;
    final ok = await showConfirmDialog(
      context,
      title: R.boardConfirmTitle,
      body: R.boardConfirmBody,
      safeLabel: R.boardConfirmNo,
      confirmLabel: R.boardConfirmYes,
      destructive: false,
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await ref.read(inboxProvider.notifier).markBoarded(widget.match.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = res.when(
        ok: (_) => null,
        err: (f) => f.code == 'GWM_TRIP_NOT_STARTED' ? R.boardDisabledDriver : _boardErrorFor(f),
      );
    });
  }

  String _boardErrorFor(AppFailure f) {
    final m = failureMessage(f);
    return f.code == FailureCode.unknown ? R.boardError : m;
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    String? reason;
    if (!m.boarded) {
      if (widget.myTrip.status != TripStatus.inProgress) {
        reason = R.boardDisabledMine;
      } else if (m.partnerTripStatus != null && m.partnerTripStatus != TripStatus.inProgress) {
        reason = R.boardDisabledDriver;
      }
    }
    return BoardingButton(
      boardedAt: m.boardedAt,
      busy: _busy,
      disabledReason: reason,
      onPressed: _board,
      error: _error,
    );
  }
}

/// Driver side: shows whether the Rider boarded and, until then, a quiet
/// "คนนั่งไม่มาตามนัด" text button (kept away from "ถึงแล้ว" and SOS).
class DriverRiderStatusSection extends ConsumerStatefulWidget {
  const DriverRiderStatusSection({super.key, required this.match});
  final MatchSummary match;

  @override
  ConsumerState<DriverRiderStatusSection> createState() => _DriverStatusState();
}

class _DriverStatusState extends ConsumerState<DriverRiderStatusSection> {
  bool _busy = false;

  Future<void> _noShow() async {
    if (_busy) return;
    final ok = await showConfirmDialog(
      context,
      title: R.noShowTitle,
      body: R.noShowBody,
      safeLabel: R.noShowKeep,
      confirmLabel: R.noShowConfirm,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final res = await ref.read(inboxProvider.notifier).reportNoShow(widget.match.id);
    if (!mounted) return;
    setState(() => _busy = false);
    res.when(
      ok: (_) {},
      err: (f) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failureMessage(f)))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    final ended = m.status != MatchStatus.accepted;
    if (ended && !m.boarded) {
      return const Padding(
        padding: EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(R.endedDriverSide, key: Key('driver-match-ended')),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(m.boarded ? Icons.check_circle_outline : Icons.hourglass_empty, size: 20, color: context.tone.text),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            m.boarded ? R.driverStatusDone : R.driverStatusWaiting,
            key: const Key('rider-boarded-status'),
          ),
        ),
      ]),
      if (!m.boarded)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('no-show-button'),
            style: TextButton.styleFrom(minimumSize: const Size(0, AppSpacing.minTap)),
            onPressed: _busy ? null : _noShow,
            child: Text(R.noShowButton, style: TextStyle(color: context.tone.dangerInk)),
          ),
        ),
      // Distance from the "arrived" button below (>= 16 dp, spec R.6).
      const SizedBox(height: AppSpacing.lg),
    ]);
  }
}
