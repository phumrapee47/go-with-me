import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/geo/geo.dart';
import '../../../core/l10n/strings_p4.dart';
import '../../../core/l10n/strings_r5.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/map/app_map.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/role_badge.dart';
import '../../../core/widgets/state_view.dart';
import '../../avatar/presentation/avatar_screens.dart';
import '../../avatar/presentation/user_avatar.dart';
import '../../geo/presentation/geo_providers.dart';
import '../../matching/domain/match_models.dart';
import '../../matching/presentation/boarding_widgets.dart';
import '../../matching/presentation/matching_providers.dart';
import '../../safety/presentation/sos_widgets.dart';
import '../domain/live_map_logic.dart';
import '../domain/trip.dart';
import '../domain/trip_state_machine.dart';
import 'live_map_widgets.dart';
import 'navigate_button.dart';
import 'trip_lifecycle_providers.dart';
import 'trip_providers.dart';
import 'trip_tone.dart' show toneOfTripRole;

enum EtaKind { pickupRider, pickupDriver, destination }

/// ETA text for the chip (whole minutes, "(ไม่แม่น)" for the straight-line fallback).
String etaLine(EtaKind kind, EtaResult r) {
  if (r.minutes < 1) return R5.etaSoon;
  final base = switch (kind) {
    EtaKind.pickupRider => R5.etaPickupRider(r.minutes),
    EtaKind.pickupDriver => R5.etaPickupDriver(r.minutes),
    EtaKind.destination => R5.etaDest(r.minutes),
  };
  return r.approximate ? '$base ${R5.etaApproxTag}' : base;
}

/// One EtaService per screen (throttled to one routing call / 45 s).
final etaServiceProvider = Provider.autoDispose<EtaService>(
  (ref) => EtaService(routing: ref.watch(routingServiceProvider), clock: ref.watch(refreshClockProvider)),
);

/// S-37: shared live map of one accepted match.
class LiveMapScreen extends ConsumerStatefulWidget {
  const LiveMapScreen({super.key, required this.matchId});
  final String matchId;

  @override
  ConsumerState<LiveMapScreen> createState() => _LiveMapState();
}

class _LiveMapState extends ConsumerState<LiveMapScreen> with SingleTickerProviderStateMixin {
  final _mc = MapController();
  late final Ticker _ticker;
  final _interp = PositionInterpolator();
  final _heading = HeadingTracker();
  Timer? _clockTimer;
  Timer? _etaTimer;

  bool _follow = true;
  bool _didFit = false;
  bool _redirected = false;
  bool _mapReady = false;
  LatLng? _lastFollowed;
  EtaResult? _eta;
  EtaKind? _etaKind;
  bool _etaBusy = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (!mounted) return;
      setState(() {});
      if (!_interp.isAnimating(DateTime.now())) _ticker.stop();
    });
    _clockTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {}); // refreshes "อัปเดตเมื่อ N วินาทีที่แล้ว"
    });
    _etaTimer = Timer.periodic(const Duration(seconds: 15), (_) => _refreshEta());
    ref.listenManual<PartnerView>(partnerLocationProvider(widget.matchId), (prev, next) {
      final p = next.point;
      if (p == null || p == prev?.point) return;
      _heading.update(p);
      _interp.moveTo(p);
      if (_interp.isAnimating(DateTime.now()) && !_ticker.isActive) _ticker.start();
      _refreshEta();
    }, fireImmediately: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapReady = true;
      _refreshEta();
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _etaTimer?.cancel();
    _ticker.dispose();
    _mc.dispose();
    super.dispose();
  }

  MatchSummary? _match() {
    for (final m in ref.read(inboxProvider).valueOrNull ?? const <MatchSummary>[]) {
      if (m.id == widget.matchId) return m;
    }
    return null;
  }

  ({LatLng from, LatLng to, EtaKind kind})? _etaPlan(MatchSummary m, Trip t, LatLng? me, LatLng? peer) {
    if (m.status != MatchStatus.accepted && !m.boarded) return null;
    final pickup = m.meetingPoint;
    if (!m.boarded) {
      if (pickup == null) return null;
      if (m.iAmDriver) return me == null ? null : (from: me, to: pickup, kind: EtaKind.pickupDriver);
      if (m.iAmRider) return peer == null ? null : (from: peer, to: pickup, kind: EtaKind.pickupRider);
      return null;
    }
    return me == null ? null : (from: me, to: t.dest, kind: EtaKind.destination);
  }

  Future<void> _refreshEta() async {
    if (!mounted || _etaBusy) return;
    final m = _match();
    final t = ref.read(activeTripProvider).valueOrNull;
    if (m == null || t == null) return;
    final me = ref.read(tripTrackingProvider).fix?.point;
    final peer = ref.read(partnerLocationProvider(widget.matchId)).point;
    final plan = _etaPlan(m, t, me, peer);
    if (plan == null) {
      if (_eta != null) setState(() => _eta = null);
      return;
    }
    _etaBusy = true;
    try {
      final r = await ref.read(etaServiceProvider).eta(from: plan.from, to: plan.to);
      if (mounted) {
        setState(() {
          _eta = r;
          _etaKind = plan.kind;
        });
      }
    } finally {
      _etaBusy = false;
    }
  }

  void _moveCamera(LatLng p, {double? zoom}) {
    if (!_mapReady) return;
    try {
      _mc.move(p, zoom ?? _mc.camera.zoom);
    } catch (_) {
      /* map not laid out yet */
    }
  }

  void _fitBoth(LatLng? me, LatLng? peer, String peerName) {
    final pts = [?me, ?peer];
    if (pts.isEmpty) return;
    try {
      if (pts.length == 1) {
        _moveCamera(pts.first, zoom: 15);
        if (peer == null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(R5.liveCtlFitNoPeer(peerName))));
        }
      } else {
        _mc.fitCamera(CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(64), maxZoom: 17));
      }
    } catch (_) {}
  }

  void _zoom(double d) {
    try {
      _mc.move(_mc.camera.center, (_mc.camera.zoom + d).clamp(3, 19));
    } catch (_) {}
  }

  Future<void> _arrive(Trip t) async {
    final ok = await showConfirmDialog(
      context,
      title: P.arrivedConfirmTitle,
      body: P.arrivedConfirmBody,
      safeLabel: P.arrivedConfirmNo,
      confirmLabel: P.arrivedConfirmYes,
      destructive: false,
    );
    if (!ok || !mounted) return;
    final res = await ref.read(tripActionsProvider).run(t.id, TripAction.complete);
    if (!mounted) return;
    res.when(
      ok: (_) => context.go(Routes.tripArrived(t.id)),
      err: (_) => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(P.arriveFailed))),
    );
  }

  void _showTextAlt(MatchSummary m, Trip t, LatLng? me, LatLng? peer, String? stale) {
    final rows = <(IconData, String)>[];
    if (me != null && peer != null) {
      final d = haversineM(me, peer);
      rows.add((
        Icons.near_me_outlined,
        R5.textAltDistance(m.displayName, coarseDistanceText(d), compassThai(bearingDeg(me, peer))),
      ));
    } else {
      rows.add((Icons.near_me_disabled_outlined, R5.liveNoPeer(m.displayName)));
    }
    if (_eta != null && _etaKind != null) rows.add((Icons.schedule, etaLine(_etaKind!, _eta!)));
    if (m.meetingLabel != null) rows.add((Icons.flag_outlined, '${R5.livePickupLabel}: ${m.meetingLabel}'));
    rows.add((stale == null ? Icons.wifi_tethering : Icons.access_time, stale ?? R5.liveStatusNearbyFresh));
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (final r in rows) ListTile(minTileHeight: 56, leading: Icon(r.$1), title: Text(r.$2))],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inboxAsync = ref.watch(inboxProvider);
    final tripAsync = ref.watch(activeTripProvider);
    final m = _match();
    final t = tripAsync.valueOrNull;
    if (m == null || t == null) {
      if (inboxAsync.isLoading || tripAsync.isLoading) {
        return Scaffold(
          appBar: AppBar(),
          body: const StateView.loading(message: R5.liveLoading),
        );
      }
      return _redirectOut();
    }
    // Guard: only for an accepted match while my own trip is in progress.
    final allowed = m.myTripId == t.id && t.status == TripStatus.inProgress && (m.status == MatchStatus.accepted || m.boarded);
    if (!allowed && !_didFit) return _redirectOut();

    final tracking = ref.watch(tripTrackingProvider);
    final me = tracking.fix?.point;
    final peerView = ref.watch(partnerLocationProvider(widget.matchId));
    final reduce = MediaQuery.disableAnimationsOf(context);
    _interp.reduceMotion = reduce;
    final now = DateTime.now();
    final matchEnded = m.status != MatchStatus.accepted;
    // A Driver stops seeing the Rider on boarding; an ended match removes the icon immediately.
    final peerRaw = matchEnded ? null : peerView.point;
    final shownPeer = peerRaw == null ? null : (_interp.valueAt(now) ?? peerRaw);
    final stale = (peerView.at == null || peerRaw == null) ? null : staleLabel(now, peerView.at!);
    final isStale = stale != null;

    final markers = buildLiveMarkers(
      iAmDriver: m.iAmDriver,
      riderBoarded: m.boarded,
      me: me,
      peer: peerRaw,
      peerStale: isStale,
      peerHeading: _heading.heading,
      pickup: m.meetingPoint,
      myDestination: t.dest,
    );

    // First view = both parties once, then follow me (E-12).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_didFit && me != null) {
        _didFit = true;
        _fitBoth(me, peerRaw, m.displayName);
        _lastFollowed = me;
      } else if (_follow && me != null && (_lastFollowed == null || haversineM(_lastFollowed!, me) > 5)) {
        _lastFollowed = me;
        _moveCamera(me);
      }
    });

    final tone = toneOfTripRole(t.role);
    final route = _eta?.geometry ?? const <LatLng>[];
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: AppMap(
              controller: _mc,
              center: me ?? m.meetingPoint ?? t.origin,
              zoom: 15,
              route: route,
              routeTone: tone,
              markers: toFlutterMarkers(markers, peerPoint: shownPeer),
              showZoomButtons: false,
              onPositionChanged: (c, byUser) {
                if (byUser && _follow) setState(() => _follow = false);
              },
            ),
          ),
          // top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Row(
                  children: [
                    Material(
                      color: context.tone.surface,
                      shape: const CircleBorder(),
                      elevation: 3,
                      child: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.tripActive(t.id))),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: context.tone.surface,
                          borderRadius: BorderRadius.circular(AppRadius.control),
                        ),
                        child: Text(
                          R5.liveTitle(m.displayName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    ),
                    MapControlButton(
                      icon: Icons.notes,
                      tooltip: R5.textAltOpen,
                      onTap: () => _showTextAlt(m, t, me, peerRaw, stale),
                    ),
                    SosMiniButton(tripId: t.id),
                  ],
                ),
              ),
            ),
          ),
          // right controls
          Positioned(
            right: AppSpacing.md,
            bottom: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MapControlButton(
                  key: const Key('ctl-follow'),
                  icon: _follow ? Icons.my_location : Icons.location_searching,
                  tooltip: _follow ? R5.liveCtlFollowing : R5.liveCtlRecenter,
                  active: _follow,
                  onTap: () {
                    setState(() => _follow = true);
                    if (me != null) {
                      _lastFollowed = me;
                      _moveCamera(me);
                    }
                  },
                ),
                MapControlButton(
                  key: const Key('ctl-fit'),
                  icon: Icons.zoom_out_map,
                  tooltip: R5.liveCtlFitBoth,
                  onTap: (me == null && peerRaw == null) ? null : () => _fitBoth(me, peerRaw, m.displayName),
                ),
                MapControlButton(
                  key: const Key('ctl-zoom-in'),
                  icon: Icons.add,
                  tooltip: R5.liveCtlZoomIn,
                  onTap: () => _zoom(1),
                ),
                MapControlButton(
                  key: const Key('ctl-zoom-out'),
                  icon: Icons.remove,
                  tooltip: R5.liveCtlZoomOut,
                  onTap: () => _zoom(-1),
                ),
              ],
            ),
          ),
          if (!_follow)
            Positioned(
              top: 96,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Center(
                  child: ActionChip(
                    key: const Key('recenter-pill'),
                    avatar: const Icon(Icons.my_location, size: 18),
                    label: const Text(R5.liveCtlRecenter),
                    onPressed: () {
                      setState(() => _follow = true);
                      if (me != null) _moveCamera(me);
                    },
                  ),
                ),
              ),
            ),
          // bottom card
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _PeerCard(
                  match: m,
                  trip: t,
                  peerPoint: peerRaw,
                  peerLoaded: peerView.loaded,
                  staleText: stale,
                  riderBoardedHidden: m.iAmDriver && m.boarded,
                  matchEnded: matchEnded,
                  gpsDenied: tracking.status == TrackStatus.denied,
                  etaText: _eta == null || _etaKind == null ? null : etaLine(_etaKind!, _eta!),
                  myPosition: me,
                  onArrive: () => _arrive(t),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _redirectOut() {
    if (!_redirected) {
      _redirected = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(R5.liveUnavailable)));
        context.go(Routes.match(widget.matchId));
      });
    }
    return const Scaffold(body: StateView.loading(message: R5.liveLoading));
  }
}

/// E-8 PeerStatusChip: who, status, ETA, chat, navigation, boarding/arrive.
class _PeerCard extends StatelessWidget {
  const _PeerCard({
    required this.match,
    required this.trip,
    required this.peerPoint,
    required this.peerLoaded,
    required this.staleText,
    required this.riderBoardedHidden,
    required this.matchEnded,
    required this.gpsDenied,
    required this.etaText,
    required this.myPosition,
    required this.onArrive,
  });

  final MatchSummary match;
  final Trip trip;
  final LatLng? peerPoint;
  final bool peerLoaded;
  final String? staleText;
  final bool riderBoardedHidden;
  final bool matchEnded;
  final bool gpsDenied;
  final String? etaText;
  final LatLng? myPosition;
  final VoidCallback onArrive;

  String _status() {
    if (matchEnded) return R5.liveEnded;
    if (riderBoardedHidden) return R5.liveRiderBoarded;
    if (staleText != null) return staleText!;
    if (peerPoint == null) return peerLoaded ? R5.liveNoPeer(match.displayName) : R5.liveLoading;
    if (match.boarded) return R5.liveStatusTogether;
    return match.iAmRider ? R5.liveStatusComingToYou : R5.liveStatusGoingToPickup;
  }

  @override
  Widget build(BuildContext context) {
    final m = match;
    final theme = Theme.of(context);
    return Material(
      color: context.tone.surface,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  UserAvatar.partner(
                    name: m.displayName,
                    matchId: m.id,
                    size: 56,
                    onTap: m.partnerId == null
                        ? null
                        : () => showPartnerPhotoSheet(
                            context,
                            matchId: m.id,
                            partnerId: m.partnerId!,
                            name: m.displayName,
                            role: m.partnerRole,
                          ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(m.displayName, style: theme.textTheme.titleMedium),
                            if (m.partnerRole != null) RoleBadge(m.partnerRole!),
                          ],
                        ),
                        Text(
                          _status(),
                          key: const Key('peer-status'),
                          style: theme.textTheme.bodyMedium?.copyWith(color: staleText != null ? context.tone.warningInk : null),
                        ),
                        if (staleText != null)
                          Text(R5.liveStaleHint, style: theme.textTheme.bodySmall?.copyWith(color: context.tone.textSecondary)),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('live-chat'),
                    tooltip: R5.liveChat,
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: const Icon(Icons.chat_bubble_outline),
                    onPressed: () => context.push(Routes.chat(m.id)),
                  ),
                ],
              ),
              if (etaText != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule, size: 20),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(etaText!, key: const Key('eta-chip'), style: theme.textTheme.titleSmall),
                      ),
                    ],
                  ),
                ),
              if (gpsDenied)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(R5.liveLocationOff),
                ),
              const SizedBox(height: AppSpacing.sm),
              NavigateButton(trip: trip, match: m, myPosition: myPosition),
              if (m.iAmRider && !matchEnded && !m.boarded) ...[
                const SizedBox(height: AppSpacing.sm),
                RiderBoardingSection(match: m, myTrip: trip),
              ],
              if (riderBoardedHidden)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(R.riderInCar),
                ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                key: const Key('live-arrive'),
                label: R5.liveArrived,
                variant: AppButtonVariant.success,
                icon: Icons.home_outlined,
                onPressed: onArrive,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small link used on the active-trip and match pages.
class OpenLiveMapButton extends StatelessWidget {
  const OpenLiveMapButton({super.key, required this.matchId});
  final String matchId;

  @override
  Widget build(BuildContext context) => AppButton(
    key: const Key('open-live-map'),
    label: R5.liveOpen,
    icon: Icons.map_outlined,
    variant: AppButtonVariant.tonal,
    onPressed: () => context.push(Routes.live(matchId)),
  );
}
