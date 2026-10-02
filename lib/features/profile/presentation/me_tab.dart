import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/l10n/strings_dual.dart';
import '../../../core/l10n/strings_p4.dart';
import '../../../core/l10n/strings_r5.dart';
import '../../../core/l10n/strings_r6_cd.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/l10n/strings_trip.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/global_verified_badge.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../avatar/presentation/user_avatar.dart';
import '../../matching/domain/match_models.dart' show VerificationBadge;
import '../../presets/presentation/preset_providers.dart';
import '../../push/presentation/push_providers.dart';
import '../../roles/presentation/role_cards.dart';
import '../../roles/presentation/role_providers.dart';
import '../../roles/presentation/role_strip.dart';
import '../../vehicle/presentation/vehicle_providers.dart';
import 'profile_providers.dart';

/// S-27: identity summary, safety/settings entries and sign-out.
class MeTab extends ConsumerWidget {
  const MeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider).valueOrNull;
    final name = ref.watch(currentProfileProvider).valueOrNull?.displayName ?? user?.displayName ?? '';
    final badges = ref.watch(myBadgesProvider).valueOrNull ?? const [];
    final theme = Theme.of(context);
    final role = ref.watch(roleControllerProvider);
    final registered = role.registered;
    final hasVehicle = ref.watch(myVehicleProvider).valueOrNull != null;
    return Scaffold(
      appBar: AppBar(title: const Text(S.tabMe)),
      body: withRoleStrip(ListView(
        padding: const EdgeInsets.all(AppSpacing.pageH),
        children: [
          // RC-11 ProfileHeroCard (round 9 US-5): avatar + name + Global Verified badge + stats row.
          _ProfileHeroCard(name: name, badges: badges),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: T.editProfile,
            variant: AppButtonVariant.tonal,
            icon: Icons.edit_outlined,
            onPressed: () => context.push(Routes.meEdit),
          ),
          const SizedBox(height: AppSpacing.md),
          // US-4 (round 4): the roles I hold. Only the owner ever sees this.
          Text(
            registered == true ? D.profileRoleBoth : D.profileRoleRiderOnly,
            key: const Key('me-roles-text'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          if (registered == true)
            const MyRolesCard()
          else if (registered == false || role.loadFailed)
            const DriverRegisterCard()
          else
            const SizedBox(
              key: Key('roles-loading'),
              height: 72,
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: AppSpacing.xl),
          // RC-12 SettingsGroupCard x3 (round 9 US-5): every old menu row kept, just grouped.
          _SettingsGroupCard(
            title: 'การเดินทาง',
            iconTint: context.tone.primaryTint,
            iconColor: context.tone.primaryInk,
            rows: [
              // S-27: vehicle info; hidden while there is nothing to show and no registration.
              if (registered == true || hasVehicle)
                _RowData(
                  key: const Key('me-vehicle-row'),
                  icon: Icons.directions_car_outlined,
                  label: R.vehicleTitle,
                  subtitle: ref.watch(myVehicleProvider).valueOrNull == null ? R.rowStatusNone : R.rowStatusSet,
                  route: Routes.vehicle,
                ),
              _RowData(icon: Icons.photo_camera_outlined, label: R5.photoTitle, route: Routes.mePhoto),
              _RowData(icon: Icons.home_work_outlined, label: R6C.placesTitle, route: Routes.mePlaces),
              _RowData(icon: Icons.star_outline_rounded, label: R5.reviewMineRow, route: Routes.meReviews),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _SettingsGroupCard(
            title: 'ความปลอดภัย',
            iconTint: context.tone.dangerTint,
            iconColor: context.tone.dangerInk,
            rows: [
              _RowData(icon: Icons.shield_outlined, label: P.meSafety, route: Routes.safety),
              _RowData(icon: Icons.contact_phone_outlined, label: P.meContacts, route: Routes.safetyContacts),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _SettingsGroupCard(
            title: 'ระบบ',
            iconTint: context.tone.surfaceRaised,
            iconColor: context.tone.textSecondary,
            rows: [
              _RowData(icon: Icons.settings_outlined, label: P.meSettings, route: Routes.settings),
              _RowData(icon: Icons.block, label: P.meBlocked, route: Routes.blocked),
              _RowData(icon: Icons.description_outlined, label: S.policy, route: Routes.policy),
              _RowData(icon: Icons.gavel_outlined, label: S.terms, route: Routes.terms),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: S.signOut,
            variant: AppButtonVariant.secondary,
            icon: Icons.logout,
            onPressed: () async {
              final ok = await showConfirmDialog(
                context,
                title: S.signOutTitle,
                body: S.signOutBody,
                safeLabel: S.signOutStay,
                confirmLabel: S.signOut,
              );
              // Saved places live on this device only: wipe them before the session ends (US-38).
              if (ok) await ref.read(presetsProvider.notifier).clearAll();
              // R7.4 (Q1): only this device's token, never every device.
              if (ok) await ref.read(pushControllerProvider).unregisterThisDevice();
              // Auth change triggers the router guard -> sign-in, stack replaced.
              if (ok) await ref.read(authRepositoryProvider).signOut();
            },
          ),
        ],
      )),
    );
  }
}

/// RC-11 ProfileHeroCard: 84dp avatar, name, Global Verified badge, 3-column stats row.
class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({required this.name, required this.badges});
  final String name;
  final List<VerificationBadge> badges;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(color: tone.surface, borderRadius: AppShape.cardRadius, boxShadow: tone.cardShadow),
      child: Column(
        children: [
          UserAvatar.mine(
            key: const Key('me-avatar'),
            name: name,
            size: 84,
            onTap: () => context.push(Routes.mePhoto),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          GlobalVerifiedBadge(badges),
          const SizedBox(height: AppSpacing.lg),
          const _StatsRow(),
        ],
      ),
    );
  }
}

/// RC-11 StatsRow: rating / trip count / CO2 saved. Round 9 ประเด็น 7 (PM ruling): no
/// cumulative-stats provider exists yet anywhere in the codebase for "my" totals (only
/// per-trip data) — falls back to a meaningful per-column placeholder instead of blocking
/// the rest of T7/US-5. Flagged in docs/dev-notes.md for a future round to add real data.
class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    Widget col(String value, String label) => Expanded(
          child: Column(
            children: [
              Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tone.textSecondary), textAlign: TextAlign.center),
            ],
          ),
        );
    return Row(
      key: const Key('me-stats-row'),
      children: [
        col('ยังไม่มีคะแนน', 'คะแนนรีวิว'),
        col('เร็ว ๆ นี้', 'จำนวนทริป'),
        col('เร็ว ๆ นี้', 'CO₂ ที่ลดได้'),
      ],
    );
  }
}

class _RowData {
  const _RowData({this.key, required this.icon, required this.label, this.subtitle, required this.route});
  final Key? key;
  final IconData icon;
  final String label;
  final String? subtitle;
  final String route;
}

/// RC-12 SettingsGroupCard: one rounded white card per menu group, dividers between rows
/// instead of a flat page-long list. Every route/label/key from the old flat `_Row` list
/// is preserved 1:1 — only the grouping/chrome changed (round 9 US-5).
class _SettingsGroupCard extends StatelessWidget {
  const _SettingsGroupCard({required this.title, required this.rows, required this.iconTint, required this.iconColor});
  final String title;
  final List<_RowData> rows;
  final Color iconTint;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.xs),
          child: Text(title, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: tone.textSecondary)),
        ),
        Container(
          decoration: BoxDecoration(color: tone.surface, borderRadius: AppShape.cardRadius, boxShadow: tone.cardShadow),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, color: tone.border, indent: AppSpacing.huge + AppSpacing.md),
                _SettingsRow(data: rows[i], iconTint: iconTint, iconColor: iconColor),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.data, required this.iconTint, required this.iconColor});
  final _RowData data;
  final Color iconTint;
  final Color iconColor;

  @override
  Widget build(BuildContext context) => ListTile(
        key: data.key,
        minTileHeight: AppSpacing.minTap,
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: iconTint, shape: BoxShape.circle),
          child: Icon(data.icon, size: 18, color: iconColor),
        ),
        title: Text(data.label),
        subtitle: data.subtitle == null ? null : Text(data.subtitle!),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(data.route),
      );
}
