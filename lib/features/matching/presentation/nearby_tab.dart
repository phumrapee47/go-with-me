import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/l10n/strings_dual.dart';
import '../../../core/l10n/strings_r5.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/l10n/strings_trip.dart';
import '../../../core/map/app_map.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/theme/tone_scope.dart';
import '../../../core/widgets/role_badge.dart';
import '../../../core/widgets/state_view.dart';
import '../../mascot/models/mascot_state.dart';
import '../../mascot/widgets/mascot_widget.dart';
import '../../roles/presentation/role_strip.dart';
import '../../trip/domain/trip.dart';
import '../../trip/domain/trip_form.dart';
import '../../trip/presentation/trip_providers.dart';
import '../../trip/presentation/trip_tone.dart';
import '../domain/match_models.dart';
import 'commute_card_deck.dart';
import 'deck_controller.dart';
import 'matching_providers.dart';
import 'matching_widgets.dart';
import 'no_match_hint.dart';

/// S-13: candidates from find_matches (blurred), map on top, list below.
class NearbyTab extends ConsumerStatefulWidget {
  const NearbyTab({super.key, this.initialView});

  /// `?view=list` opens the list directly (US-34, Q4).
  final String? initialView;

  @override
  ConsumerState<NearbyTab> createState() => _NearbyTabState();
}

class _NearbyTabState extends ConsumerState<NearbyTab> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    if (widget.initialView == 'list') {
      Future.microtask(() {
        if (mounted) ref.read(nearbyViewProvider.notifier).set(NearbyView.list);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = ref.watch(activeTripProvider);
    final nearby = ref.watch(nearbyProvider);
    final pending = ref.watch(incomingPendingCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(S.nearbyTitle),
        actions: [
          IconButton(
            tooltip: T.requestsTitle,
            onPressed: () => context.push(Routes.nearbyRequests),
            icon: Badge(
              isLabelVisible: pending > 0,
              label: Text('$pending'),
              child: const Icon(Icons.inbox_outlined),
            ),
          ),
        ],
      ),
      body: withRoleStrip(trip.when(
        loading: () => const StateView.loading(),
        error: (e, _) => StateView.failure(
          e is AppFailure ? e : const AppFailure(FailureCode.unknown),
          onRetry: () => ref.invalidate(activeTripProvider),
        ),
        data: (t) {
          if (t == null) {
            return StateView.empty(
              icon: Icons.route_outlined,
              title: T.nearbyNoTrip,
              actionLabel: T.homeCreateTrip,
              onAction: () => context.push(Routes.tripNew),
            );
          }
          // F-R3.7: an old car trip without a role is never matched (not an error).
          if (t.isLegacyCarWithoutRole) {
            return StateView.empty(
              key: const Key('legacy-no-role'),
              icon: Icons.info_outline,
              title: R.legacyNoRole,
              actionLabel: R.viewMyTrips,
              onAction: () => context.go(Routes.trips),
            );
          }
          // F-R3.4: a car trip that already has its one companion leaves the search.
          final paired = t.isCar ? _acceptedMatchOf(t) : null;
          if (paired != null) {
            return StateView.empty(
              key: const Key('nearby-matched'),
              icon: Icons.handshake_outlined,
              title: R.matchedTitle,
              message: R.matchedBody,
              actionLabel: R.viewMatch,
              onAction: () => context.push(Routes.match(paired.id)),
            );
          }
          return nearby.when(
            loading: () => const _SearchingView(),
            error: (e, _) => StateView.failure(
              e is AppFailure ? e : const AppFailure(FailureCode.unknown),
              onRetry: () => ref.read(nearbyProvider.notifier).refresh(force: true),
            ),
            data: (items) => _content(items, t),
          );
        },
      )),
    );
  }

  MatchSummary? _acceptedMatchOf(Trip t) {
    final inbox = ref.watch(inboxProvider).valueOrNull ?? const <MatchSummary>[];
    for (final m in inbox) {
      if (m.myTripId == t.id && m.status == MatchStatus.accepted) return m;
    }
    return null;
  }

  Widget _content(List<MatchCandidate> items, Trip trip) {
    final view = ref.watch(nearbyViewProvider);
    final toggle = ViewToggle(value: view, onChanged: (v) => ref.read(nearbyViewProvider.notifier).set(v));
    if (view == NearbyView.deck) {
      return Column(children: [
        toggle,
        Expanded(child: CommuteCardDeck(trip: trip, items: items)),
      ]);
    }
    return Column(children: [toggle, Expanded(child: _listContent(items, trip))]);
  }

  Widget _listContent(List<MatchCandidate> items, Trip trip) {
    final now = DateTime.now();
    final areas = [
      for (final c in items)
        MapArea(center: c.approxOrigin, radiusM: blurAreaRadiusM, highlighted: c.tripId == _selected),
    ];
    return Column(
      children: [
        // D-14 TripContextBar: the search belongs to the TRIP, so it carries the trip's role and tone
        // even when the app-level mode is the other one.
        ToneScope(
          tone: toneOfTripRole(trip.role),
          child: Builder(
            builder: (ctx) => Container(
              key: const Key('trip-context-bar'),
              width: double.infinity,
              color: ctx.tone.surface,
              padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, AppSpacing.sm, AppSpacing.pageH, AppSpacing.sm),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Chip(
                    avatar: Icon(trip.mode.icon, size: 18),
                    label: Text('${trip.mode.label} · ${formatDeparture(trip.departAt, now)}'),
                  ),
                  if (trip.role != null) RoleRow(trip.role!),
                ]),
                if (trip.role != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      trip.role == TripRole.driver
                          ? D.tripctxSearchingRider(formatDeparture(trip.departAt, now))
                          : D.tripctxSearchingDriver(formatDeparture(trip.departAt, now)),
                      key: const Key('tripctx-text'),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        SizedBox(
          height: 150,
          child: AppMap(
            center: trip.origin,
            zoom: 12,
            areas: areas,
            showZoomButtons: false,
          ),
        ),
        if (trip.role != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH, vertical: AppSpacing.xs),
            child: Text(
              trip.role == TripRole.driver ? R.listForDriver : R.listForRider,
              key: const Key('nearby-list-header'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH, vertical: AppSpacing.xs),
          child: Text(T.nearbyPrivacy, style: TextStyle(color: context.tone.textSecondary)),
        ),
        // Round 5 corridor rule: the destination does not have to match, only the way.
        if (trip.isCar)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(R5.matchRuleExplain, key: const Key('match-rule-explain'), style: TextStyle(color: context.tone.textSecondary))),
            ]),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.read(nearbyProvider.notifier).refresh(),
            child: items.isEmpty
                ? ListView(children: [
                    const SizedBox(height: AppSpacing.xxl),
                    switch (trip.role) {
                      TripRole.driver => const StateView.empty(
                          icon: Icons.people_outline,
                          title: R.emptyDriverTitle,
                          message: R.emptyDriverBody,
                        ),
                      TripRole.rider => const StateView.empty(
                          icon: Icons.people_outline,
                          title: R.emptyRiderTitle,
                          message: R.emptyRiderBody,
                        ),
                      null => const StateView.empty(
                          icon: Icons.people_outline,
                          title: T.nearbyEmpty,
                          message: T.nearbyEmptyHint,
                        ),
                    },
                    NoMatchHint(trip: trip),
                  ])
                : ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.pageH),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final c = items[i];
                      return CandidateCard(
                        key: ValueKey(c.tripId),
                        candidate: c,
                        now: now,
                        selected: c.tripId == _selected,
                        onTap: () {
                          setState(() => _selected = c.tripId);
                          context.push(Routes.candidate(c.tripId));
                        },
                        onRequest: () => confirmAndSendRequest(context, ref, c),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

/// F-R3 candidate search in flight: mascot replaces the bare spinner while
/// `nearbyProvider` loads (see mascot spec: searching state).
class _SearchingView extends StatelessWidget {
  const _SearchingView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MascotWidget(state: MascotState.searching, size: 140),
          const SizedBox(height: AppSpacing.lg),
          Text('กำลังค้นหาคู่เดินทาง...', style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}
