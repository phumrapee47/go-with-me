import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings_dual.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../roles/presentation/role_providers.dart';
import '../../vehicle/presentation/vehicle_providers.dart';
import '../../vehicle/presentation/vehicle_widgets.dart';
import '../domain/trip.dart';

/// C-31: choose Driver or Rider for a car trip. The form starts on the role of the active mode
/// (US-20; the user can change it and their choice is never overwritten, see `roleTouched`).
/// An unregistered account sees "Driver" locked with the way to register (D-12); the way there and
/// back keeps the trip draft because it lives in a provider. A Driver also needs a saved vehicle.
class RolePicker extends ConsumerStatefulWidget {
  const RolePicker({
    super.key,
    required this.role,
    required this.onChanged,
    this.showRequiredError = false,
    this.prefilled = false,
  });

  final TripRole? role;
  final ValueChanged<TripRole> onChanged;
  final bool showRequiredError;

  /// The current value came from the active-role default, not from the user.
  final bool prefilled;

  @override
  ConsumerState<RolePicker> createState() => _RolePickerState();
}

class _RolePickerState extends ConsumerState<RolePicker> {
  bool _gateShown = false;

  @override
  Widget build(BuildContext context) {
    final role = widget.role;
    final onChanged = widget.onChanged;
    final showRequiredError = widget.showRequiredError;
    final theme = Theme.of(context);
    final vehicle = ref.watch(myVehicleProvider);
    // Unknown (still loading) counts as not registered for the LOCK, but the server decides anyway.
    final locked = ref.watch(driverRegisteredProvider) != true;
    return Semantics(
      container: true,
      label: R.roleGroupLabel,
      child: Column(
        key: const Key('role-picker'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(R.rolePickerTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          _RoleTile(
            key: const Key('role-driver'),
            role: TripRole.driver,
            title: R.roleDriver,
            description: R.roleDriverDesc,
            selected: role == TripRole.driver,
            locked: locked,
            onTap: locked ? () => setState(() => _gateShown = true) : () => onChanged(TripRole.driver),
          ),
          if (locked && _gateShown) ...[
            const SizedBox(height: AppSpacing.sm),
            _DriverGateCard(onUseRider: () {
              setState(() => _gateShown = false);
              onChanged(TripRole.rider);
            }),
          ],
          const SizedBox(height: AppSpacing.sm),
          _RoleTile(
            key: const Key('role-rider'),
            role: TripRole.rider,
            title: R.roleRider,
            description: R.roleRiderDesc,
            selected: role == TripRole.rider,
            onTap: () => onChanged(TripRole.rider),
          ),
          if (widget.prefilled && role != null) ...[
            const SizedBox(height: AppSpacing.sm),
            const Text(D.pickerPrefillNote, key: Key('role-prefill-note')),
          ],
          const SizedBox(height: AppSpacing.sm),
          const Text(R.roleOneOnly),
          Text(R.roleNoMoney, style: theme.textTheme.bodyMedium?.copyWith(color: context.tone.textSecondary)),
          Text(R.roleLockedNote, style: theme.textTheme.bodyMedium?.copyWith(color: context.tone.textSecondary)),
          if (role == null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                showRequiredError ? R.roleRequired : R.nextDisabledRole,
                key: const Key('role-required'),
                style: TextStyle(color: showRequiredError ? context.tone.dangerInk : context.tone.textSecondary),
              ),
            ),
          if (role == TripRole.driver) ...[
            const SizedBox(height: AppSpacing.md),
            vehicle.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => VehicleLoadError(onRetry: () => ref.invalidate(myVehicleProvider)),
              data: (v) => v == null
                  ? AppCard(
                      tone: AppCardTone.warning,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text(R.needsVehicle, key: Key('needs-vehicle')),
                        const SizedBox(height: AppSpacing.sm),
                        AppButton(
                          key: const Key('fill-vehicle'),
                          label: R.fillVehicle,
                          variant: AppButtonVariant.secondary,
                          onPressed: () => context.push(Routes.vehicleFor(returnTo: Routes.tripOptions)),
                        ),
                      ]),
                    )
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      VehicleInfoCard.ownerPreview(v),
                      const Padding(
                        padding: EdgeInsets.only(top: AppSpacing.sm),
                        child: Text(R.rowSummaryDriver, key: Key('seat-one-note')),
                      ),
                    ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({
    super.key,
    required this.role,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
    this.locked = false,
  });

  final bool locked;
  final TripRole role;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: locked ? '$title ${D.pickerLocked}' : '$title $description',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTap),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: selected ? context.tone.primaryTint : context.tone.surface,
            border: Border.all(color: selected ? context.tone.primaryInk : context.tone.border, width: selected ? 2 : 1),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(role.icon, color: selected ? context.tone.primaryInk : context.tone.text),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: theme.textTheme.titleMedium),
                Text(description, style: theme.textTheme.bodyMedium?.copyWith(color: context.tone.textSecondary)),
                if (locked)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Row(children: [
                      Icon(Icons.lock_outline, size: 16, color: context.tone.warningInk),
                      const SizedBox(width: AppSpacing.xs),
                      const Flexible(child: Text(D.pickerLocked, key: Key('role-driver-locked'))),
                    ]),
                  ),
              ]),
            ),
            if (selected) Icon(Icons.check_circle, color: context.tone.primaryInk),
          ]),
        ),
      ),
    );
  }
}

/// D-12: in-context card (not a modal, the form stays) when Driver is tapped without registration.
class _DriverGateCard extends StatelessWidget {
  const _DriverGateCard({required this.onUseRider});
  final VoidCallback onUseRider;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const Key('driver-gate-card'),
      tone: AppCardTone.info,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text(D.pickerGate),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const Key('gate-card-register'),
          label: D.gateCta,
          onPressed: () => context.push(Routes.driverRegisterFor(returnTo: Routes.tripOptions)),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          key: const Key('gate-card-use-rider'),
          label: D.pickerUseRider,
          variant: AppButtonVariant.text,
          onPressed: onUseRider,
        ),
      ]),
    );
  }
}
