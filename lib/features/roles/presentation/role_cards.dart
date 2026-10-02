import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/l10n/strings_dual.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../matching/domain/match_models.dart';
import '../../matching/presentation/matching_providers.dart';
import '../../trip/domain/trip.dart';
import '../../trip/presentation/trip_providers.dart';
import '../../vehicle/presentation/vehicle_providers.dart';
import '../domain/role_state.dart';
import 'role_providers.dart';
import 'role_strip.dart';

// ---------------------------------------------------------------------------------------------
// D-11 BlockedReasonSheet

enum BlockedReason { activeTrip, activeMatch, both, vehicleRegistered }

class BlockedReasonContent extends StatelessWidget {
  const BlockedReasonContent({super.key, required this.reason, required this.onPrimary, required this.onClose});
  final BlockedReason reason;
  final VoidCallback onPrimary;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final vehicle = reason == BlockedReason.vehicleRegistered;
    Widget line(String t) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(t),
        );
    return Column(
      key: const Key('blocked-reason'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, color: tone.warningInk),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              vehicle ? D.vehicleDeleteBlockedRegistered : D.blockedTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ]),
        const SizedBox(height: AppSpacing.sm),
        if (reason == BlockedReason.activeTrip || reason == BlockedReason.both) line(D.blockedTrip),
        if (reason == BlockedReason.activeMatch || reason == BlockedReason.both) line(D.blockedMatch),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          key: const Key('blocked-primary'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.minTap)),
          onPressed: onPrimary,
          child: Text(vehicle ? D.vehicleDeleteBlockedCta : D.blockedCta),
        ),
        TextButton(
          key: const Key('blocked-close'),
          autofocus: true,
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.minTap)),
          onPressed: onClose,
          child: const Text(D.blockedClose),
        ),
      ],
    );
  }
}

/// [onPrimary] runs after the sheet closed (default: go to "my trips").
Future<void> showBlockedReasonSheet(BuildContext context, BlockedReason reason, {VoidCallback? onPrimary}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, 0, AppSpacing.pageH, AppSpacing.xl),
        child: BlockedReasonContent(
          reason: reason,
          onClose: () => Navigator.of(ctx).pop(),
          onPrimary: () {
            Navigator.of(ctx).pop();
            (onPrimary ?? () => context.go(Routes.trips))();
          },
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------------------------
// D-10 UnregisterConfirmDialog

enum _UnregPhase { confirm, submitting, blocked, error }

class UnregisterDialog extends ConsumerStatefulWidget {
  const UnregisterDialog({super.key});

  @override
  ConsumerState<UnregisterDialog> createState() => _UnregisterDialogState();
}

class _UnregisterDialogState extends ConsumerState<UnregisterDialog> {
  _UnregPhase _phase = _UnregPhase.confirm;
  BlockedReason _reason = BlockedReason.activeTrip;

  Future<void> _submit() async {
    setState(() => _phase = _UnregPhase.submitting);
    final res = await ref.read(roleControllerProvider.notifier).unregister();
    if (!mounted) return;
    final f = res.failureOrNull;
    if (f == null) {
      Navigator.of(context).pop(true);
      return;
    }
    final block = unregisterBlockOf(f);
    setState(() {
      if (block != null) {
        _reason = switch (block) {
          UnregisterBlock.activeTrip => BlockedReason.activeTrip,
          UnregisterBlock.activeMatch => BlockedReason.activeMatch,
          UnregisterBlock.both => BlockedReason.both,
        };
        _phase = _UnregPhase.blocked;
      } else {
        _phase = _UnregPhase.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    if (_phase == _UnregPhase.blocked) {
      return AlertDialog(
        content: SingleChildScrollView(
          child: BlockedReasonContent(
            reason: _reason,
            onClose: () => Navigator.of(context).pop(false),
            onPrimary: () {
              Navigator.of(context).pop(false);
              context.go(Routes.trips);
            },
          ),
        ),
      );
    }
    final busy = _phase == _UnregPhase.submitting;
    Widget item(String t) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('• '),
            Expanded(child: Text(t)),
          ]),
        );
    return AlertDialog(
      key: const Key('unregister-dialog'),
      title: const Text(D.unregTitle),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          item(D.unregItem1),
          item(D.unregItem2),
          item(D.unregItem3),
          item(D.unregItem4),
          if (_phase == _UnregPhase.error) ...[
            const SizedBox(height: AppSpacing.md),
            Text(D.unregErrNetwork, key: const Key('unregister-error'), style: TextStyle(color: tone.dangerInk)),
          ],
          if (busy) ...[
            const SizedBox(height: AppSpacing.md),
            const Center(child: CircularProgressIndicator()),
          ],
        ]),
      ),
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: AppSpacing.sm,
      actions: [
        FilledButton(
          key: const Key('unregister-stay'),
          autofocus: true,
          onPressed: busy ? null : () => Navigator.of(context).pop(false),
          child: const Text(D.unregStay),
        ),
        OutlinedButton(
          key: const Key('unregister-confirm'),
          style: OutlinedButton.styleFrom(
            foregroundColor: tone.dangerInk,
            side: BorderSide(color: tone.dangerInk, width: 1.5),
          ),
          onPressed: busy ? null : _submit,
          child: Text(_phase == _UnregPhase.error ? D.unregRetry : D.unregConfirm),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// D-4 DriverRegisterCard / D-5 MyRolesCard

/// Entry for an unregistered account (Me tab only): one primary button, no promotion styling.
class DriverRegisterCard extends ConsumerWidget {
  const DriverRegisterCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(roleControllerProvider);
    final hasVehicle = s.registration?.hasVehicle ?? ref.watch(myVehicleProvider).valueOrNull != null;
    final theme = Theme.of(context);
    return AppCard(
      key: const Key('driver-register-card'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.drive_eta, color: context.tone.accentInk),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(D.driverCardTitle, style: theme.textTheme.titleMedium)),
        ]),
        const SizedBox(height: AppSpacing.xs),
        const Text(D.driverCardBody),
        if (hasVehicle) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(D.driverCardPrefill, key: const Key('driver-card-prefill'), style: theme.textTheme.bodyMedium?.copyWith(color: context.tone.textSecondary)),
        ],
        if (s.registration == null && s.loadFailed) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            Expanded(child: Text(D.driverCardError, style: TextStyle(color: context.tone.dangerInk))),
            TextButton(
              onPressed: () => ref.read(roleControllerProvider.notifier).refresh(),
              child: const Text(D.unregRetry),
            ),
          ]),
        ],
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const Key('driver-card-cta'),
          label: D.driverCardCta,
          onPressed: () => context.push(Routes.driverRegister),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(D.driverCardNote, style: theme.textTheme.bodySmall),
      ]),
    );
  }
}

/// For a registered account: the roles I hold, the segmented 1-tap switch, my vehicle, unregister.
class MyRolesCard extends ConsumerStatefulWidget {
  const MyRolesCard({super.key});

  @override
  ConsumerState<MyRolesCard> createState() => _MyRolesCardState();
}

class _MyRolesCardState extends ConsumerState<MyRolesCard> {
  bool _checking = false;

  Future<void> _startUnregister() async {
    if (_checking) return;
    setState(() => _checking = true);
    BlockedReason? block;
    try {
      // Fresh local view of my trips/matches; the server re-checks on submit anyway.
      ref
        ..invalidate(activeTripProvider)
        ..invalidate(inboxProvider);
      final trip = await ref.read(activeTripProvider.future);
      final inbox = await ref.read(inboxProvider.future);
      final tripBlocks = trip != null && trip.role == TripRole.driver && trip.status.isActive;
      final matchBlocks = inbox.any((m) => m.status == MatchStatus.accepted && m.iAmDriver);
      block = tripBlocks && matchBlocks
          ? BlockedReason.both
          : tripBlocks
              ? BlockedReason.activeTrip
              : matchBlocks
                  ? BlockedReason.activeMatch
                  : null;
    } catch (e) {
      if (e is! AppFailure) rethrow;
      // Could not pre-check: let the server decide.
    }
    if (!mounted) return;
    setState(() => _checking = false);
    if (block != null) {
      await showBlockedReasonSheet(context, block);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final done = await showDialog<bool>(context: context, builder: (_) => const UnregisterDialog());
    if (done == true) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(D.unregDone)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(roleControllerProvider);
    final tone = context.tone;
    final theme = Theme.of(context);
    final active = s.active ?? ActiveRole.rider;
    final switching = s.switching.isSwitching;
    return AppCard(
      key: const Key('my-roles-card'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(D.rolesTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        const Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
          _RoleChip(Icons.event_seat, D.roleChipRider),
          _RoleChip(Icons.drive_eta, D.roleChipDriver),
        ]),
        const SizedBox(height: AppSpacing.md),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: _SegCell(
                key: const Key('seg-rider'),
                role: ActiveRole.rider,
                selected: active == ActiveRole.rider,
                busy: switching && s.switching.target == ActiveRole.rider,
                onTap: switching ? null : () => performRoleSwitch(context, ref, ActiveRole.rider),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _SegCell(
                key: const Key('seg-driver'),
                role: ActiveRole.driver,
                selected: active == ActiveRole.driver,
                busy: switching && s.switching.target == ActiveRole.driver,
                onTap: switching ? null : () => performRoleSwitch(context, ref, ActiveRole.driver),
              ),
            ),
          ]),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(D.switchToDriverHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: AppSpacing.lg),
        // Destructive action sits last and apart from the switch (>= 16 dp).
        ListTile(
          key: const Key('unregister-row'),
          minTileHeight: AppSpacing.minTap,
          contentPadding: EdgeInsets.zero,
          leading: _checking
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(Icons.no_accounts_outlined, color: tone.dangerInk),
          title: Text(D.unregisterRow, style: TextStyle(color: tone.dangerInk)),
          onTap: _checking ? null : _startUnregister,
        ),
      ]),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: tone.infoBg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: tone.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: tone.accentInk),
        const SizedBox(width: AppSpacing.xs),
        Flexible(child: Text(label)),
      ]),
    );
  }
}

/// One cell of the segmented switch: icon + text + check when selected (never colour alone).
class _SegCell extends StatelessWidget {
  const _SegCell({super.key, required this.role, required this.selected, required this.busy, required this.onTap});
  final ActiveRole role;
  final bool selected;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final driver = role == ActiveRole.driver;
    final label = driver ? D.modeDriver : D.modeRider;
    final bg = selected ? (driver ? const Color(0xFFF5A623) : ToneColors.rider.primary) : Colors.transparent;
    final fg = selected ? (driver ? const Color(0xFF0B1B33) : Colors.white) : tone.text;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        customBorder: AppShape.control(),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: AppShape.controlRadius,
            border: Border.all(color: selected ? bg : tone.borderStrong, width: 1.5),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (busy)
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
            else
              Icon(selected ? Icons.check_circle : (driver ? Icons.drive_eta : Icons.event_seat), size: 20, color: fg),
            const SizedBox(width: AppSpacing.xs),
            Flexible(child: Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg))),
          ]),
        ),
      ),
    );
  }
}
