import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/error/failure_messages.dart';
import '../../../core/l10n/strings_p4.dart';
import '../../../core/l10n/strings_r5.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/map/app_map.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/role_badge.dart';
import '../../../core/widgets/state_view.dart';
import '../../avatar/presentation/user_avatar.dart';
import '../../matching/domain/match_models.dart';
import '../../matching/presentation/matching_providers.dart';
import '../domain/detour.dart';
import '../domain/trip.dart';
import '../domain/trip_form.dart';
import 'create_trip_widgets.dart';
import 'trip_flows.dart';
import 'trip_lifecycle_providers.dart';
import 'trip_providers.dart';
import 'trip_widgets.dart';

/// S-20: one trip, actions depend on the state machine.
class TripDetailScreen extends ConsumerStatefulWidget {
  const TripDetailScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<TripDetailScreen> createState() => _TripDetailState();
}

class _TripDetailState extends ConsumerState<TripDetailScreen> {
  bool _busy = false;

  Future<void> _guard(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    await job();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final trip = ref.watch(tripByIdProvider(widget.tripId));
    return Scaffold(
      appBar: AppBar(title: const Text(P.tripDetail)),
      body: trip.when(
        loading: () => const StateView.loading(),
        error: (e, _) => StateView.failure(
          e is AppFailure ? e : const AppFailure(FailureCode.unknown),
          onRetry: () => ref.invalidate(tripByIdProvider(widget.tripId)),
        ),
        data: (t) => t == null
            ? StateView.empty(
                icon: Icons.route_outlined,
                title: P.tripNotFound,
                actionLabel: P.backHome,
                onAction: () => context.go(Routes.trips),
              )
            : _body(t),
      ),
    );
  }

  Widget _body(Trip t) {
    final theme = Theme.of(context);
    final inbox = ref.watch(inboxProvider).valueOrNull ?? const [];
    final partners = acceptedPartnersOf(inbox, t.id);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.pageH),
      children: [
        SizedBox(
          height: 200,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: AppMap(
              center: t.origin,
              zoom: 12,
              route: t.route,
              pins: [
                MapPin(point: t.origin, icon: Icons.trip_origin),
                MapPin(point: t.dest, icon: Icons.place, color: AppColors.danger),
              ],
              showZoomButtons: false,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Align(alignment: Alignment.centerLeft, child: TripStatusChip(t.status)),
        const SizedBox(height: AppSpacing.md),
        _row(P.tripFrom, t.originLabel.isEmpty ? '-' : t.originLabel),
        _row(P.tripTo, t.destLabel.isEmpty ? '-' : t.destLabel),
        _row('เวลา', formatDeparture(t.departAt, DateTime.now())),
        _row('วิธีเดินทาง', t.mode.label),
        if (t.role != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 96, child: Text(R.roleLabel, style: TextStyle(color: context.tone.textSecondary))),
              Expanded(
                child: Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
                  RoleRow(t.role!),
                  // Locked: shown with a lock icon + text (never colour alone).
                  const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.lock_outline, size: 16),
                    SizedBox(width: 4),
                    Flexible(child: Text(R.roleFixedRow)),
                  ]),
                ]),
              ),
            ]),
          ),
        if (t.isLegacyCarWithoutRole)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.sm),
            child: Text(R.legacyNoRole, key: Key('detail-legacy-no-role')),
          ),
        if (t.role == TripRole.driver && t.status == TripStatus.scheduled && t.maxDropoffM != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: _DropoffEditor(
              key: ValueKey('dropoff-${t.id}-${t.maxDropoffM}'),
              trip: t,
              locked: inbox.any((m) =>
                  m.myTripId == t.id && (m.status == MatchStatus.pending || m.status == MatchStatus.accepted)),
            ),
          ),
        if (t.role == TripRole.driver && t.status == TripStatus.scheduled && t.detourToleranceM != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: _DetourEditor(
              key: ValueKey('detour-${t.id}-${t.detourToleranceM}'),
              trip: t,
              locked: inbox.any((m) =>
                  m.myTripId == t.id && (m.status == MatchStatus.pending || m.status == MatchStatus.accepted)),
            ),
          ),
        if (t.distanceM > 0) _row('ระยะทาง', formatRouteSummary(t.distanceM, t.durationS)),
        const SizedBox(height: AppSpacing.lg),
        Text(P.tripPartners, style: theme.textTheme.titleMedium),
        if (t.role == TripRole.driver)
          const Text(R.matchedPairDriverHint, key: Key('seat-hint')),
        if (partners.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.sm), child: Text(P.tripNoPartners))
        else
          for (final m in partners)
            Card(
              child: ListTile(
                minTileHeight: AppSpacing.minTap,
                leading: UserAvatar.partner(name: m.displayName, matchId: m.id, size: 40),
                title: Text(m.displayName),
                subtitle: m.partnerRole == null ? null : Align(alignment: Alignment.centerLeft, child: RoleBadge(m.partnerRole!)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.match(m.id)),
              ),
            ),
        const SizedBox(height: AppSpacing.xl),
        ..._actions(t),
      ],
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 96, child: Text(k, style: TextStyle(color: context.tone.textSecondary))),
          Expanded(child: Text(v)),
        ]),
      );

  /// Q-1(a): a Driver whose Rider boarded cannot cancel; say why (and what to do).
  bool _driverLockedByBoarding(Trip t) {
    if (t.role != TripRole.driver) return false;
    final inbox = ref.read(inboxProvider).valueOrNull ?? const [];
    return acceptedPartnersOf(inbox, t.id).any((m) => m.isCar && m.boarded);
  }

  Widget _cancelControl(Trip t, {bool pop = false}) {
    if (_driverLockedByBoarding(t)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(R.cannotCancelAfterBoarded, key: Key('cancel-locked-boarded')),
      );
    }
    return TextButton(
      onPressed: _busy
          ? null
          : () => _guard(() async {
                if (await cancelTripFlow(context, ref, t) && pop && mounted) context.pop();
              }),
      child: Text(P.cancelTrip, style: TextStyle(color: context.tone.dangerInk)),
    );
  }

  List<Widget> _actions(Trip t) => switch (t.status) {
        TripStatus.scheduled => [
            AppButton(
              label: P.startTrip,
              icon: Icons.play_arrow,
              onPressed: _busy
                  ? null
                  : () => _guard(() async {
                        await startTripFlow(context, ref, t);
                      }),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: P.shareTripButton,
              variant: AppButtonVariant.secondary,
              icon: Icons.ios_share,
              onPressed: () => context.push(Routes.tripShare(t.id)),
            ),
            const SizedBox(height: AppSpacing.sm),
            _cancelControl(t, pop: true),
          ],
        TripStatus.inProgress => [
            AppButton(
              label: P.goActive,
              variant: AppButtonVariant.success,
              onPressed: () => context.push(Routes.tripActive(t.id)),
            ),
            const SizedBox(height: AppSpacing.sm),
            _cancelControl(t),
          ],
        _ => [
            AppButton(
              label: P.deleteTrip,
              variant: AppButtonVariant.secondary,
              icon: Icons.delete_outline,
              onPressed: _busy
                  ? null
                  : () => _guard(() async {
                        if (await deleteTripFlow(context, ref, t) && mounted) context.pop();
                      }),
            ),
          ],
      };
}

/// Edit the drop-off limit of a scheduled Driver trip; read-only while a request is pending / a match accepted.
class _DropoffEditor extends ConsumerStatefulWidget {
  const _DropoffEditor({super.key, required this.trip, required this.locked});
  final Trip trip;
  final bool locked;

  @override
  ConsumerState<_DropoffEditor> createState() => _DropoffEditorState();
}

class _DropoffEditorState extends ConsumerState<_DropoffEditor> {
  late int _value = widget.trip.maxDropoffM ?? dropoffDefaultM;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final res = await ref.read(tripRepositoryProvider).updateMaxDropoff(widget.trip.id, _value);
    if (!mounted) return;
    setState(() => _saving = false);
    final msg = res.when(ok: (_) => R5.dropoffSaved, err: (f) => failureMessage(f));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    if (res.valueOrNull != null) ref.invalidate(tripByIdProvider(widget.trip.id));
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DropoffLimitControl(
        value: _value,
        onChanged: (v) => setState(() => _value = v),
        lockedReason: widget.locked ? R5.dropoffLockedReason : null,
      ),
      if (!widget.locked) ...[
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          key: const Key('dropoff-save'),
          label: R5.dropoffSave,
          variant: AppButtonVariant.tonal,
          onPressed: _saving || _value == widget.trip.maxDropoffM ? null : _save,
        ),
      ],
    ]);
  }
}

/// Edit the US-50 route detour tolerance of a scheduled Driver trip; read-only while a request is
/// pending / a match accepted (same lock rule as `_DropoffEditor`, a fully independent setting).
class _DetourEditor extends ConsumerStatefulWidget {
  const _DetourEditor({super.key, required this.trip, required this.locked});
  final Trip trip;
  final bool locked;

  @override
  ConsumerState<_DetourEditor> createState() => _DetourEditorState();
}

class _DetourEditorState extends ConsumerState<_DetourEditor> {
  late int _value = widget.trip.detourToleranceM ?? detourDefaultM;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final res = await ref.read(tripRepositoryProvider).updateDetourTolerance(widget.trip.id, _value);
    if (!mounted) return;
    setState(() => _saving = false);
    final msg = res.when(ok: (_) => 'บันทึกระยะเบี่ยงแล้ว', err: (f) => failureMessage(f));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    if (res.valueOrNull != null) ref.invalidate(tripByIdProvider(widget.trip.id));
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DetourToleranceControl(
        value: _value,
        onChanged: (v) => setState(() => _value = v),
        lockedReason: widget.locked ? R5.dropoffLockedReason : null,
      ),
      if (!widget.locked) ...[
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          key: const Key('detour-save'),
          label: 'บันทึกระยะเบี่ยง',
          variant: AppButtonVariant.tonal,
          onPressed: _saving || _value == widget.trip.detourToleranceM ? null : _save,
        ),
      ],
    ]);
  }
}
