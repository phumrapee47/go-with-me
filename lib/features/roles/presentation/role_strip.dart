import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings_dual.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../trip/domain/trip.dart' show TripRole;
import '../../trip/presentation/trip_providers.dart';
import '../domain/role_state.dart';
import 'role_providers.dart';

/// Darker-amber border for the driver badge — amber-on-amber (fill vs border) needs its own
/// contrast step that no existing tone token provides; there is no rider equivalent because
/// the rider badge borders with `accentInk` instead.
const _driverBadgeBorder = Color(0xFF8A5A00);

/// D-1: which mode the app is in. Icon + text + colour (never colour alone). The text is never
/// ellipsised (it wraps), so it survives text scale 2.0.
class RoleModeBadge extends StatelessWidget {
  const RoleModeBadge(this.role, {super.key});
  final ActiveRole role;

  @override
  Widget build(BuildContext context) {
    final driver = role == ActiveRole.driver;
    final label = driver ? D.modeDriver : D.modeRider;
    final icon = driver ? Icons.drive_eta : Icons.event_seat;
    final c = context.tone;
    final fg = driver ? c.onPrimary : c.accentInk;
    return Semantics(
      label: D.a11yModeCurrent(driver ? D.roleWordDriver : D.roleWordRider),
      excludeSemantics: true,
      child: Container(
        key: Key(driver ? 'mode-badge-driver' : 'mode-badge-rider'),
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: driver ? c.primary : c.selectedFill,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: driver ? _driverBadgeBorder : c.accentInk),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Runs the 1-tap switch and reports the result the same way from every entry point
/// (strip, Me tab, registration success). Returns the outcome for callers that navigate.
Future<RoleSwitchOutcome> performRoleSwitch(BuildContext context, WidgetRef ref, ActiveRole target) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ctrl = ref.read(roleControllerProvider.notifier);
  final outcome = await ctrl.switchTo(target);
  if (messenger == null) {
    ctrl.dismissSwitchFailure();
    return outcome;
  }
  final active = ref.read(activeTripProvider).valueOrNull;
  final activeRole = active?.role;
  String? text;
  switch (outcome) {
    case RoleSwitchOutcome.switched:
      if (activeRole != null && active!.status.isActive) {
        text = D.switchedActiveTrip(
          target == ActiveRole.driver ? D.modeDriver : D.modeRider,
          activeRole == TripRole.driver ? D.roleWordDriver : D.roleWordRider,
        );
      } else {
        text = target == ActiveRole.driver ? D.switchedDriver : D.switchedRider;
      }
    case RoleSwitchOutcome.switchedSavedLater:
      text = D.switchedRiderOffline;
    case RoleSwitchOutcome.offlineToDriver:
      text = D.errOfflineDriver;
    case RoleSwitchOutcome.notRegistered:
      text = D.errNotRegistered;
    case RoleSwitchOutcome.failed:
      text = D.errSwitch;
    case RoleSwitchOutcome.unchanged:
      text = null;
  }
  if (text != null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(key: const Key('role-switch-snack'), content: Text(text)));
  }
  ctrl.dismissSwitchFailure();
  return outcome;
}

/// D-3: the row under the app bar of the 5 shell tabs. Left = mode badge, right = 1-tap switch.
/// An unregistered account only sees the badge (Q-D3): the way to register is the Me tab and the
/// role picker of the create-trip form, never a permanent promotion here.
class RoleStrip extends ConsumerWidget {
  const RoleStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(roleControllerProvider);
    final tone = context.tone;
    final active = s.active;
    final decoration = BoxDecoration(
      color: tone.surface,
      border: Border(bottom: BorderSide(color: tone.border)),
    );

    if (active == null) {
      // Loading-neutral: no guessed mode.
      return Container(
        key: const Key('role-strip-loading'),
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH, vertical: AppSpacing.sm),
        decoration: decoration,
        alignment: Alignment.centerLeft,
        child: Semantics(
          label: D.roleStripUnknown,
          child: Container(
            width: 150,
            height: 32,
            decoration: BoxDecoration(color: tone.border, borderRadius: BorderRadius.circular(AppRadius.pill)),
          ),
        ),
      );
    }

    final target = active == ActiveRole.driver ? ActiveRole.rider : ActiveRole.driver;
    final canSwitch = s.registered == true || active == ActiveRole.driver;
    final switching = s.switching.isSwitching;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final stacked = scale >= 1.3;

    final badge = RoleModeBadge(active);
    final button = canSwitch
        ? _SwitchButton(
            key: const Key('role-switch'),
            target: target,
            switching: switching,
            onPressed: switching ? null : () => performRoleSwitch(context, ref, target),
          )
        : null;

    return Container(
      key: const Key('role-strip'),
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH, vertical: AppSpacing.xs),
      decoration: decoration,
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [badge, ?button],
            )
          : Row(children: [
              Flexible(child: badge),
              if (button != null) ...[
                const Spacer(),
                Flexible(flex: 2, child: Align(alignment: Alignment.centerRight, child: button)),
              ],
            ]),
    );
  }
}

class _SwitchButton extends StatelessWidget {
  const _SwitchButton({super.key, required this.target, required this.switching, required this.onPressed});
  final ActiveRole target;
  final bool switching;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final toDriver = target == ActiveRole.driver;
    final label = switching ? D.switching : (toDriver ? D.switchToDriver : D.switchToRider);
    return Semantics(
      button: true,
      label: switching ? D.switching : '${toDriver ? D.switchToDriver : D.switchToRider} ${D.switchToDriverHint}',
      excludeSemantics: true,
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(minimumSize: const Size(AppSpacing.minTap, AppSpacing.minTap)),
        icon: switching
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.swap_horiz, size: 20),
        label: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}

/// D-12 (strip variant): bottom sheet offered when a switch to Driver is impossible for lack of registration.
Future<void> showDriverGateSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, 0, AppSpacing.pageH, AppSpacing.xl),
        child: Column(
          key: const Key('driver-gate-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(D.gateTitle, style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            const Text(D.gateBody),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              key: const Key('gate-register'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.minTap)),
              onPressed: () {
                Navigator.of(ctx).pop();
                context.push(Routes.driverRegister);
              },
              child: const Text(D.gateCta),
            ),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.minTap)),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(D.gateLater),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Tiny helper so shell tabs can put the strip directly under their app bar.
Widget withRoleStrip(Widget body) => Column(children: [const RoleStrip(), Expanded(child: body)]);
