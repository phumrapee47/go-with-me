import 'package:flutter/material.dart';

import '../../features/trip/domain/trip.dart' show TripRole;
import '../l10n/strings_roles.dart';
import '../theme/tokens.dart';

/// C-32. Role is always icon + text (never colour alone); text is navy on a tint.
class RoleBadge extends StatelessWidget {
  const RoleBadge(this.role, {super.key});
  final TripRole role;

  @override
  Widget build(BuildContext context) {
    final driver = role == TripRole.driver;
    final label = driver ? R.roleBadgeDriver : R.roleBadgeRider;
    return Semantics(
      label: 'บทบาท $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          // Fixed colours in every tone (design-spec D.2): amber + navy for Driver, mint + navy for Rider.
          color: driver ? const Color(0xFFF5A623) : AppColors.mint,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: driver ? const Color(0xFF8A5A00) : AppColors.tealDark),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(role.icon, size: 16, color: const Color(0xFF0B1B33)),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: const Color(0xFF0B1B33)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "รับได้ 1 คน": Driver trips only; the number is fixed (no seat input anywhere).
class SeatChip extends StatelessWidget {
  const SeatChip({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        label: R.roleOneOnly,
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.person_outline, size: 16, color: AppColors.navy),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                R.seatOne,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.navy),
              ),
            ),
          ]),
        ),
      );
}

/// Role row used on cards: badge (+ seat chip for drivers) that wraps at large text scales.
class RoleRow extends StatelessWidget {
  const RoleRow(this.role, {super.key});
  final TripRole role;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [RoleBadge(role), if (role == TripRole.driver) const SeatChip()],
      );
}
