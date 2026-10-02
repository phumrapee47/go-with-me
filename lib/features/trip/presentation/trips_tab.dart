import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/l10n/strings_p4.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/state_view.dart';
import '../../matching/presentation/matching_providers.dart';
import '../../roles/presentation/role_strip.dart';
import '../domain/trip.dart';
import 'trip_flows.dart';
import 'trip_lifecycle_providers.dart';
import 'trip_providers.dart';
import 'trip_widgets.dart';

/// S-19: my trips, "current" and "history".
class TripsTab extends ConsumerStatefulWidget {
  const TripsTab({super.key});

  @override
  ConsumerState<TripsTab> createState() => _TripsTabState();
}

class _TripsTabState extends ConsumerState<TripsTab> {
  bool _history = false;
  final _busy = <String>{};

  Future<void> _run(String id, Future<void> Function() job) async {
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    await job();
    if (mounted) setState(() => _busy.remove(id));
  }

  void _recreate(Trip t) {
    ref.read(tripFormProvider.notifier)
      ..reset()
      ..setOrigin(Place(point: t.origin, label: t.originLabel))
      ..setDest(Place(point: t.dest, label: t.destLabel))
      ..setMode(t.mode);
    context.push(Routes.tripNew);
  }

  @override
  Widget build(BuildContext context) {
    final trips = ref.watch(myTripsProvider(_history));
    final active = ref.watch(activeTripProvider).valueOrNull;
    final inbox = ref.watch(inboxProvider).valueOrNull ?? const [];
    final hasActive = active != null;

    return Scaffold(
      appBar: AppBar(title: const Text('ทริปของฉัน')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: hasActive ? null : () => context.push(Routes.tripNew),
        backgroundColor: hasActive ? context.tone.border : context.tone.primary,
        foregroundColor: hasActive ? context.tone.textSecondary : context.tone.onPrimary,
        icon: const Icon(Icons.add),
        label: const Text(P.createTripFab),
      ),
      body: withRoleStrip(Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, AppSpacing.md, AppSpacing.pageH, AppSpacing.sm),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text(P.segCurrent)),
                ButtonSegment(value: true, label: Text(P.segHistory)),
              ],
              selected: {_history},
              onSelectionChanged: (s) => setState(() => _history = s.first),
            ),
          ),
        ),
        if (hasActive)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
            child: Text(P.createTripDisabled, style: TextStyle(color: context.tone.textSecondary)),
          ),
        Expanded(
          child: trips.when(
            loading: () => const StateView.loading(),
            error: (e, _) => StateView.failure(
              e is AppFailure ? e : const AppFailure(FailureCode.unknown),
              onRetry: () => ref.invalidate(myTripsProvider(_history)),
            ),
            data: (list) => RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(myTripsProvider(_history));
                await ref.read(myTripsProvider(_history).future);
              },
              child: list.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: AppSpacing.xxl),
                      StateView.empty(
                        icon: Icons.route_outlined,
                        title: _history ? P.tripsEmptyHistory : P.tripsEmptyCurrent,
                        message: _history ? P.tripsEmptyHistoryBody : P.tripsEmptyCurrentBody,
                        actionLabel: (!_history && !hasActive) ? P.createTripFab : null,
                        onAction: (!_history && !hasActive) ? () => context.push(Routes.tripNew) : null,
                      ),
                    ])
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.pageH, AppSpacing.sm, AppSpacing.pageH, 96),
                      children: [
                        for (final t in list)
                          TripCard(
                            trip: t,
                            matchedCount: acceptedPartnersOf(inbox, t.id).length,
                            onTap: () => context.push(Routes.tripDetail(t.id)),
                            actions: [
                              if (t.status == TripStatus.scheduled)
                                AppButton(
                                  label: P.startTrip,
                                  expand: false,
                                  icon: Icons.play_arrow,
                                  // Disabled (not a spinner) while the start flow, which
                                  // may be waiting on a dialog, is running.
                                  onPressed: _busy.contains(t.id)
                                      ? null
                                      : () => _run(t.id, () async {
                                            await startTripFlow(context, ref, t);
                                          }),
                                ),
                              if (t.status == TripStatus.inProgress)
                                AppButton(
                                  label: P.goActive,
                                  expand: false,
                                  variant: AppButtonVariant.success,
                                  onPressed: () => context.push(Routes.tripActive(t.id)),
                                ),
                              if (t.isLegacyCarWithoutRole && t.status.isActive)
                                AppButton(
                                  key: const Key('legacy-cancel'),
                                  label: R.legacyCancelRecreate,
                                  expand: false,
                                  variant: AppButtonVariant.secondary,
                                  onPressed: () => _run(t.id, () async {
                                    await cancelTripFlow(context, ref, t);
                                  }),
                                ),
                              if (t.status == TripStatus.expired && !hasActive)
                                AppButton(
                                  label: P.recreateTrip,
                                  expand: false,
                                  variant: AppButtonVariant.secondary,
                                  onPressed: () => _recreate(t),
                                ),
                            ],
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ])),
    );
  }
}

