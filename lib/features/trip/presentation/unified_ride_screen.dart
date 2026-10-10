import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/error/failure_messages.dart';
import '../../../core/error/result.dart';
import '../../../core/geo/geo.dart';
import '../../../core/l10n/strings_p4.dart';
import '../../../core/l10n/strings_r5.dart';
import '../../../core/l10n/strings_r6.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/map/app_map.dart';
import '../../../core/notify/local_notifier.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/role_badge.dart';
import '../../../core/widgets/state_view.dart';
import '../../../core/widgets/swipe_to_confirm_slider.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../avatar/presentation/avatar_screens.dart';
import '../../avatar/presentation/user_avatar.dart';
import '../../chat/presentation/chat_providers.dart';
import '../../matching/domain/match_models.dart';
import '../../matching/presentation/boarding_widgets.dart';
import '../../matching/presentation/lateness_card.dart';
import '../../matching/presentation/matching_providers.dart';
import '../../sharing/presentation/sharing_providers.dart';
import '../../vehicle/presentation/vehicle_providers.dart';
import '../../vehicle/presentation/vehicle_widgets.dart';
import '../domain/lateness.dart';
import '../domain/live_location.dart';
import '../domain/live_map_logic.dart';
import '../domain/ride_logic.dart';
import '../domain/trip.dart';
import '../domain/trip_form.dart';
import '../domain/trip_state_machine.dart';
import 'live_map_screen.dart' show EtaKind, etaLine, etaServiceProvider;
import 'live_map_widgets.dart';
import 'navigate_button.dart';
import 'ride_widgets.dart';
import 'trip_flows.dart';
import 'trip_lifecycle_providers.dart';
import 'trip_providers.dart';
import 'trip_tone.dart' show toneOfTripRole;

const _uuid = Uuid();

/// Sheet levels (F-2).
enum SheetLevel { collapsed, half, full }

class _Snap {
  const _Snap(this.trip, this.match);
  final Trip trip;
  final MatchSummary? match;
}

/// F-1 / US-29: ONE screen for a trip that is scheduled or under way. Full-screen live map
/// behind a 3-level [DraggableScrollableSheet]; SOS floats above the sheet at every level.
///
/// - `/trips/active` -> [tripId] null: my active trip
/// - `/matches/:id/live` -> [matchId] set: same screen, with the old live-map guard
/// - `/trips/:id/arrived` -> [arrived] true: the Arrived state of that trip
class UnifiedRideScreen extends ConsumerStatefulWidget {
  const UnifiedRideScreen({super.key, this.tripId, this.matchId, this.arrived = false});
  final String? tripId;
  final String? matchId;
  final bool arrived;

  @override
  ConsumerState<UnifiedRideScreen> createState() => _UnifiedRideState();
}

class _UnifiedRideState extends ConsumerState<UnifiedRideScreen> with SingleTickerProviderStateMixin {
  // ---- map (logic carried over from the old LiveMapScreen) ----
  final _mc = MapController();
  late final Ticker _ticker;
  final _interp = PositionInterpolator();
  final _heading = HeadingTracker();
  Timer? _clockTimer;
  Timer? _etaTimer;
  bool _follow = true;
  bool _didFit = false;
  bool _mapReady = false;
  bool _redirected = false;
  bool _shownOnce = false;
  LatLng? _lastFollowed;
  EtaResult? _eta;
  EtaKind? _etaKind;
  bool _etaBusy = false;
  bool _hadFix = false;

  // ---- sheet ----
  final _sheetCtl = DraggableScrollableController();
  final _extent = ValueNotifier<double>(0.3);
  final _levelN = ValueNotifier<SheetLevel>(SheetLevel.collapsed);
  SheetLevel? _userLevel;
  RideState? _lastState;
  double _headerH = 0;
  final _headerKey = GlobalKey();
  double _fracCollapsed = 0.3;
  double _fracHalf = 0.52;
  double _fracFull = 0.9;
  bool _initialLevelSet = false;
  double _initialFrac = 0.3; // constant after first layout: changing initialChildSize re-creates the sheet extent

  // ---- chat text (survives level changes) ----
  final _chatText = TextEditingController();

  // ---- state that must outlive a status change until the slider finished its success animation ----
  _Snap? _freeze;

  // ---- geofence + "arrived at pickup" ----
  final _gateBoard = NearGate();
  final _gateArrive = NearGate();
  final _pickupGate = CooldownGate();
  bool _pickupSending = false;
  bool _pickupSent = false;
  bool _driverArrived = false;
  final _driverArrivedIds = <String>{};

  // ---- US-49 (round 7): client-side lateness hint (server re-verifies on cancel) ----
  final _lateSamples = <LocationSample>[];
  LatenessTrigger _lateTrigger = LatenessTrigger.none;
  final _lateSnooze = LatenessSnooze();
  bool _lateBusy = false;
  String? _lateError;

  Set<String> _unread = const {};
  bool _sharingLink = false;

  // last values for timers
  Trip? _curTrip;
  MatchSummary? _curMatch;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (!mounted) return;
      setState(() {});
      if (!_interp.isAnimating(DateTime.now())) _ticker.stop();
    });
    _clockTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final t = _curTrip;
      if (t != null) _updateLateness(t, _curMatch, ref.read(tripTrackingProvider).fix?.point);
      setState(() {}); // stale label, cooldown countdown
    });
    _etaTimer = Timer.periodic(const Duration(seconds: 15), (_) => _refreshEta());
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
    _sheetCtl.dispose();
    _extent.dispose();
    _levelN.dispose();
    _chatText.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ ETA / map

  ({LatLng from, LatLng to, EtaKind kind})? _etaPlan(MatchSummary? m, Trip t, LatLng? me, LatLng? peer) {
    if (t.status != TripStatus.inProgress) return null;
    final hasPeer = m != null && (m.status == MatchStatus.accepted || m.boarded);
    if (!hasPeer) return me == null ? null : (from: me, to: t.dest, kind: EtaKind.destination);
    // Peer (walk / transit) matches have no pickup: the ETA is to my own destination.
    if (!m.isCar) return me == null ? null : (from: me, to: t.dest, kind: EtaKind.destination);
    final pickup = m.meetingPoint;
    if (!m.boarded) {
      if (pickup == null) return null;
      if (m.iAmDriver) return me == null ? null : (from: me, to: pickup, kind: EtaKind.pickupDriver);
      if (m.iAmRider) return peer == null ? null : (from: peer, to: pickup, kind: EtaKind.pickupRider);
      return me == null ? null : (from: me, to: t.dest, kind: EtaKind.destination);
    }
    return me == null ? null : (from: me, to: t.dest, kind: EtaKind.destination);
  }

  Future<void> _refreshEta() async {
    if (!mounted || _etaBusy) return;
    final t = _curTrip;
    if (t == null) return;
    final m = _curMatch;
    final me = ref.read(tripTrackingProvider).fix?.point;
    final peer = m == null ? null : ref.read(partnerLocationProvider(m.id)).point;
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

  void _fitBoth(LatLng? me, LatLng? peer, String peerName, {bool notify = true}) {
    final pts = [?me, ?peer];
    if (pts.isEmpty) return;
    try {
      if (pts.length == 1) {
        _moveCamera(pts.first, zoom: 15);
        if (notify && peer == null && _curMatch != null) {
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

  // ------------------------------------------------------------------ sheet

  double _frac(SheetLevel l) => switch (l) {
        SheetLevel.collapsed => _fracCollapsed,
        SheetLevel.half => _fracHalf,
        SheetLevel.full => _fracFull,
      };

  SheetLevel _nearest(double extent) {
    var best = SheetLevel.collapsed;
    var d = double.infinity;
    for (final l in SheetLevel.values) {
      final x = (extent - _frac(l)).abs();
      if (x < d) {
        d = x;
        best = l;
      }
    }
    return best;
  }

  Future<void> _animateTo(SheetLevel l) async {
    _userLevel = l;
    if (!_sheetCtl.isAttached) {
      _levelN.value = l;
      return;
    }
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) {
      _sheetCtl.jumpTo(_frac(l));
    } else {
      await _sheetCtl.animateTo(_frac(l), duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
    _levelN.value = l;
  }

  void _cycleLevel() {
    final next = SheetLevel.values[(_levelN.value.index + 1) % 3];
    _animateTo(next);
  }

  void _measureHeader() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final h = _headerKey.currentContext?.size?.height;
      if (h != null && (h - _headerH).abs() > 1) setState(() => _headerH = h);
    });
  }

  SheetLevel _defaultLevel(RideState s) => switch (s) {
        RideState.scheduled || RideState.arrived || RideState.peerEnded => SheetLevel.half,
        RideState.onTheWay || RideState.boarded => SheetLevel.collapsed,
      };

  // ------------------------------------------------------------------ actions

  bool _isNetwork(AppFailure f) => f.code == FailureCode.networkOffline || f.code == FailureCode.networkTimeout;

  Future<String?> _confirmStart(Trip t, MatchSummary? m) async {
    _freeze = _Snap(t, m);
    final ok = await startTripFlow(context, ref, t);
    if (!ok) {
      _freeze = null;
      return sliderCancelled; // the flow already told the user why (or they backed out)
    }
    return null;
  }

  Future<String?> _confirmBoard(Trip t, MatchSummary m) async {
    _freeze = _Snap(t, m);
    final res = await ref.read(inboxProvider.notifier).markBoarded(m.id);
    return res.when(
      ok: (_) => null,
      err: (f) {
        _freeze = null;
        if (f.code == 'GWM_TRIP_NOT_STARTED') return R.boardDisabledDriver;
        if (_isNetwork(f)) return R6.sliderOfflineError;
        return f.code == FailureCode.unknown ? R.boardError : failureMessage(f);
      },
    );
  }

  Future<String?> _confirmArrive(Trip t, MatchSummary? m) async {
    _freeze = _Snap(t, m);
    final res = await ref.read(tripActionsProvider).run(t.id, TripAction.complete);
    return res.when(
      ok: (_) => null,
      err: (f) {
        _freeze = null;
        return _isNetwork(f) ? R6.sliderOfflineError : P.arriveFailed; // the trip is still in progress
      },
    );
  }

  Future<void> _sendArrivedAtPickup(MatchSummary m) async {
    if (_pickupSending) return;
    final now = ref.read(refreshClockProvider)();
    if (!_pickupGate.tryAcquire(now)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(R6.arrivedAtPickupThrottled)));
      return;
    }
    setState(() => _pickupSending = true);
    // Same channel as the chat (no new RPC): a ready-made sentence, no coordinates, no destination.
    final res = await ref.read(chatRepositoryProvider).send(m.id, R6.arrivedAtPickupMessage, _uuid.v4(), kind: 'driver_arrived');
    if (!mounted) return;
    switch (res) {
      case Ok():
        unawaited(HapticFeedback.mediumImpact());
        setState(() {
          _pickupSending = false;
          _pickupSent = true;
        });
      case Err():
        _pickupGate.release();
        setState(() => _pickupSending = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(R6.arrivedAtPickupFailed)));
    }
  }

  // ---- US-49 (round 7): lateness detection (client hint only; server is the authority) ----

  void _updateLateness(Trip t, MatchSummary? m, LatLng? me) {
    final carMatch = (m != null && m.isCar && m.status == MatchStatus.accepted && !m.boarded) ? m : null;
    if (carMatch == null || t.status != TripStatus.inProgress || carMatch.partnerTripStatus != TripStatus.inProgress) {
      if (_lateTrigger != LatenessTrigger.none) setState(() => _lateTrigger = LatenessTrigger.none);
      _lateSamples.clear();
      return;
    }
    final now = DateTime.now();
    if (me != null) {
      _lateSamples.add(LocationSample(point: me, at: now));
      _lateSamples.removeWhere((s) => now.difference(s.at) > LatenessRules.staleWindow * 2);
    }
    if (_lateSnooze.isSnoozed) return;
    final meet = carMatch.meetingPoint ?? carMatch.approxOrigin ?? t.dest;
    final trigger = checkLateness(
      driverDepartAt: carMatch.iAmDriver ? t.departAt : (carMatch.departAt ?? t.departAt),
      riderDepartAt: carMatch.iAmRider ? t.departAt : (carMatch.departAt ?? t.departAt),
      now: now,
      samples: _lateSamples,
      meetingPoint: meet,
    );
    if (trigger != _lateTrigger) setState(() => _lateTrigger = trigger);
  }

  void _waitMoreLateness() {
    _lateSnooze.snooze();
    setState(() {
      _lateTrigger = LatenessTrigger.none;
      _lateError = null;
    });
  }

  Future<void> _cancelNoFault(MatchSummary m) async {
    setState(() {
      _lateBusy = true;
      _lateError = null;
    });
    final res = await ref.read(matchRepositoryProvider).cancelNoFault(m.id);
    if (!mounted) return;
    setState(() => _lateBusy = false);
    res.when(
      ok: (_) {
        setState(() => _lateTrigger = LatenessTrigger.none);
        ref.invalidate(inboxProvider);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ยกเลิกการเดินทางแล้ว (ไม่เสียประวัติ)')));
      },
      err: (f) {
        // GWM_NOT_OVERDUE: the server double-checked and disagrees with the client's local timing —
        // handled gracefully (card stays up, no crash, no blame), per design-roles.md #15.3.
        setState(() => _lateError = failureMessage(f));
      },
    );
  }

  void _pickQuick(String q) {
    _chatText.text = q;
    _chatText.selection = TextSelection.collapsed(offset: q.length);
    _animateTo(SheetLevel.full); // never sent automatically
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final inboxAsync = ref.watch(inboxProvider);
    final inbox = inboxAsync.valueOrNull ?? const <MatchSummary>[];
    final tracking = ref.watch(tripTrackingProvider); // keeps GPS + live sharing running while open
    final AsyncValue<Trip?> tripAsync = widget.arrived && widget.tripId != null
        ? ref.watch(tripByIdProvider(widget.tripId!))
        : ref.watch(activeTripProvider);
    final t = _freeze?.trip ?? tripAsync.valueOrNull;

    if (t == null) {
      if (tripAsync.isLoading || (widget.matchId != null && inboxAsync.isLoading)) {
        return const Scaffold(body: StateView.loading(message: R5.liveLoading));
      }
      if (tripAsync.hasError && widget.matchId == null) {
        final e = tripAsync.error;
        return Scaffold(
          appBar: AppBar(),
          body: StateView.failure(
            e is AppFailure ? e : const AppFailure(FailureCode.unknown),
            onRetry: () => ref.invalidate(activeTripProvider),
          ),
        );
      }
      if (widget.matchId != null) return _redirectOut();
      return Scaffold(
        appBar: AppBar(leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home))),
        body: StateView.empty(
          icon: Icons.route_outlined,
          title: R6.tripNotFound,
          actionLabel: P.backHome,
          onAction: () => context.go(Routes.home),
        ),
      );
    }

    MatchSummary? m = _freeze?.match;
    if (m == null) {
      if (widget.matchId != null) {
        for (final x in inbox) {
          if (x.id == widget.matchId) m = x;
        }
      } else {
        m = rideMatchFor(t, inbox);
      }
    }
    if (widget.matchId != null) {
      // Old live-map guard: only for an accepted match while my own trip is in progress.
      final allowed =
          m != null && m.myTripId == t.id && t.status == TripStatus.inProgress && (m.status == MatchStatus.accepted || m.boarded);
      if (!allowed && !_shownOnce && _freeze == null) return _redirectOut();
    }
    _shownOnce = true;
    _curTrip = t;
    _curMatch = m;

    final arrivedState = widget.arrived || t.status == TripStatus.completed;
    final hasPeer = m != null && m.status == MatchStatus.accepted;
    final peerEnded = m != null && m.status != MatchStatus.accepted;
    final RideState state = arrivedState
        ? RideState.arrived
        : peerEnded
            ? RideState.peerEnded
            : t.status == TripStatus.scheduled
                ? RideState.scheduled
                : (m != null && m.boarded)
                    ? RideState.boarded
                    : RideState.onTheWay;

    final now = DateTime.now();
    final me = tracking.fix?.point;
    final reduce = MediaQuery.disableAnimationsOf(context);
    _interp.reduceMotion = reduce;

    // ---- partner live position (unchanged rules: server decides visibility; ended = icon gone) ----
    PartnerView peerView = const PartnerView();
    if (m != null) {
      peerView = ref.watch(partnerLocationProvider(m.id));
      ref.listen<PartnerView>(partnerLocationProvider(m.id), (prev, next) {
        final p = next.point;
        if (p == null || p == prev?.point) return;
        _heading.update(p);
        _interp.moveTo(p);
        if (_interp.isAnimating(DateTime.now()) && !_ticker.isActive) _ticker.start();
        _refreshEta();
      });
    }
    final matchEnded = m != null && m.status != MatchStatus.accepted;
    final peerRaw = (m == null || matchEnded || arrivedState) ? null : peerView.point;
    final shownPeer = peerRaw == null ? null : (_interp.valueAt(now) ?? peerRaw);
    final stale = (peerView.at == null || peerRaw == null) ? null : staleLabel(now, peerView.at!);

    // ---- geofence highlight (presentation only) ----
    final nearBoard = _gateBoard.update(now: now, me: me, target: m?.meetingPoint, accuracyM: tracking.fix?.accuracyM);
    final nearArrive = _gateArrive.update(now: now, me: me, target: t.dest, accuracyM: tracking.fix?.accuracyM);

    // ---- Rider: driver said "arrived at pickup" (latest chat message; local notification once) ----
    if (m != null && m.iAmRider && !m.boarded && hasPeer) {
      final uid = ref.watch(authUserProvider).valueOrNull?.id;
      final latest = ref.watch(chatInboxProvider).valueOrNull?[m.id];
      if (latest != null &&
          !latest.isSystem &&
          latest.senderId != uid &&
          latest.body == R6.arrivedAtPickupMessage &&
          now.difference(latest.createdAt) < const Duration(minutes: 30) &&
          _driverArrivedIds.add(latest.id)) {
        _driverArrived = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(HapticFeedback.lightImpact());
          unawaited(ref.read(localNotifierProvider).show(const LocalNotice(LocalNoticeKind.driverArrivedAtPickup)));
        });
      }
    }
    if (m == null || m.boarded || !hasPeer) _driverArrived = false;

    final markers = buildLiveMarkers(
      iAmDriver: m?.iAmDriver ?? false,
      riderBoarded: m?.boarded ?? false,
      me: arrivedState ? null : me,
      peer: peerRaw,
      peerStale: stale != null,
      peerHeading: _heading.heading,
      pickup: (arrivedState || m == null) ? null : m.meetingPoint,
      myDestination: t.dest,
    );

    // The first GPS fix: compute the ETA right away instead of waiting for the 15 s timer.
    if (me != null && !_hadFix) {
      _hadFix = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_refreshEta()));
    }

    // First view = both parties once, then follow me (E-12).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_didFit && me != null) {
        _didFit = true;
        _fitBoth(me, peerRaw, m?.displayName ?? '', notify: false); // silent: a snackbar would cover the slider
        _lastFollowed = me;
      } else if (_follow && me != null && (_lastFollowed == null || haversineM(_lastFollowed!, me) > 5)) {
        _lastFollowed = me;
        _moveCamera(me);
      }
    });

    final tone = toneOfTripRole(t.role);
    final homeMatch = ref.watch(homeDestinationMatcherProvider).match(t);
    final primary = ridePrimaryFor(trip: t, match: m, arrivedState: arrivedState);
    final route = arrivedState ? t.route : (_eta?.geometry.isNotEmpty ?? false ? _eta!.geometry : t.route);

    // State change -> default level (first build), or open at Half when the trip becomes Arrived / peer-ended.
    if (_lastState != state) {
      final first = _lastState == null;
      _lastState = state;
      if (first) {
        _levelN.value = _userLevel ?? _defaultLevel(state);
      } else if (state == RideState.arrived || state == RideState.peerEnded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _animateTo(SheetLevel.half);
        });
      }
    }
    _unread = ref.watch(unreadMatchIdsProvider);
    _sharingLink = (ref.watch(activeSharesProvider).valueOrNull ?? const []).any((s) => s.tripId == t.id);

    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final l = _levelN.value;
        if (l == SheetLevel.full) {
          _animateTo(SheetLevel.half);
        } else if (l == SheetLevel.half && !arrivedState && state != RideState.scheduled) {
          _animateTo(SheetLevel.collapsed);
        } else {
          _goBack(t);
        }
      },
      child: Scaffold(
        body: LayoutBuilder(builder: (context, box) {
          final H = box.maxHeight;
          final top = MediaQuery.paddingOf(context).top;
          final bottom = MediaQuery.paddingOf(context).bottom;
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final est = (hasPeer || peerEnded ? 200.0 : 180.0) * (scale > 1 ? scale.clamp(1.0, 1.6) : 1.0);
          final headerH = _headerH > 0 ? _headerH : est;
          // <= 40 % of the screen at normal text size; grows with very large text so the slider is never cut off.
          _fracCollapsed = ((headerH + bottom) / H).clamp(0.1, scale > 1.3 ? 0.7 : 0.42);
          _fracHalf = (0.52 > 360 / H ? 0.52 : 360 / H).clamp(_fracCollapsed + 0.08, 0.9);
          _fracFull = ((H - top - 72) / H).clamp(_fracHalf + 0.05, 1.0);
          if (!_initialLevelSet) {
            _initialLevelSet = true;
            _extent.value = _frac(_levelN.value);
            _initialFrac = _extent.value;
          }

          return Stack(fit: StackFit.expand, children: [
            Positioned.fill(
              key: const ValueKey('ride-map-layer'),
              child: AppMap(
                controller: _mc,
                center: me ?? m?.meetingPoint ?? t.origin,
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
            if (!arrivedState)
              ValueListenableBuilder<double>(
                valueListenable: _extent,
                builder: (_, ext, _) => ext >= _fracFull - 0.02
                    ? const Positioned(width: 0, height: 0, child: SizedBox.shrink())
                    : Positioned(
                        right: AppSpacing.md,
                        bottom: ext * H + 12,
                        child: _mapControls(me, peerRaw, m?.displayName ?? ''),
                      ),
              ),
            if (!arrivedState && (tracking.status == TrackStatus.denied || (t.status == TripStatus.inProgress && tracking.fix == null)))
              Positioned(
                top: top + 64,
                left: AppSpacing.md,
                right: AppSpacing.md,
                child: tracking.status == TrackStatus.denied
                    ? const _Banner(P.gpsDenied, AppCardTone.warning, Icons.location_off_outlined, key: Key('gps-banner'))
                    : const _Banner(P.gpsSearching, AppCardTone.info, Icons.gps_not_fixed, key: Key('gps-banner')),
              ),
            if (!_follow && !arrivedState)
              Positioned(
                top: top + 128,
                left: 0,
                right: 0,
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
            Positioned.fill(
              key: const ValueKey('ride-sheet-layer'), // stable identity: the sheet must never be re-created
              child: NotificationListener<DraggableScrollableNotification>(
                onNotification: (n) {
                  _extent.value = n.extent;
                  final l = _nearest(n.extent);
                  if (l != _levelN.value) _levelN.value = l;
                  return false;
                },
                child: DraggableScrollableSheet(
                  controller: _sheetCtl,
                  initialChildSize: _initialFrac.clamp(_fracCollapsed, _fracFull),
                  minChildSize: _fracCollapsed,
                  maxChildSize: _fracFull,
                  snap: true,
                  snapSizes: [_fracHalf],
                  builder: (context, sc) => _sheet(
                    sc,
                    t: t,
                    m: m,
                    state: state,
                    primary: primary,
                    hasPeer: hasPeer,
                    tracking: tracking,
                    stale: stale,
                    peerView: peerView,
                    peerRaw: peerRaw,
                    me: me,
                    nearBoard: nearBoard,
                    nearArrive: nearArrive,
                    homeMatch: homeMatch,
                    keyboardOpen: keyboardOpen,
                    height: H,
                    tone: tone,
                  ),
                ),
              ),
            ),
            // Above the sheet at EVERY level (US-30). Shown from Scheduled until my own trip is over.
            Positioned(
              key: const ValueKey('ride-top-layer'),
              top: 0,
              left: 0,
              right: 0,
              child: RideTopOverlay(
                key: const Key('ride-top-overlay'),
                tripId: t.id,
                showSos: !arrivedState,
                onBack: () => _goBack(t),
                onTextView: () => _animateTo(SheetLevel.half),
              ),
            ),
          ]);
        }),
      ),
    );
  }

  void _goBack(Trip t) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.home);
    }
  }

  Widget _redirectOut() {
    if (!_redirected) {
      _redirected = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(R5.liveUnavailable)));
        if (widget.matchId != null) {
          // push (not go): keep the back stack so the user isn't stranded on
          // match detail with no way back into the app.
          context.push(Routes.match(widget.matchId!));
        } else {
          context.go(Routes.home);
        }
      });
    }
    return const Scaffold(body: StateView.loading(message: R5.liveLoading));
  }

  Widget _mapControls(LatLng? me, LatLng? peer, String peerName) => Column(
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
            onTap: (me == null && peer == null) ? null : () => _fitBoth(me, peer, peerName),
          ),
          MapControlButton(key: const Key('ctl-zoom-in'), icon: Icons.add, tooltip: R5.liveCtlZoomIn, onTap: () => _zoom(1)),
          MapControlButton(key: const Key('ctl-zoom-out'), icon: Icons.remove, tooltip: R5.liveCtlZoomOut, onTap: () => _zoom(-1)),
        ],
      );

  // ------------------------------------------------------------------ sheet content

  String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _statusText({
    required Trip t,
    required MatchSummary? m,
    required RideState state,
    required String? stale,
    required PartnerView peerView,
    required LatLng? peerRaw,
  }) {
    if (state == RideState.arrived) return R6.soloStatusInProgress;
    if (m == null) return t.status == TripStatus.scheduled ? R6.soloStatusScheduled : R6.soloStatusInProgress;
    if (m.status != MatchStatus.accepted) return R5.liveEnded;
    if (t.status == TripStatus.scheduled) return '${R6.waitingDepart} ${_hhmm(t.departAt)}';
    if (!m.isCar) {
      // Peer (walk / transit): nobody is picked up, so just how fresh the partner's position is.
      if (stale != null) return stale;
      if (peerRaw == null) return peerView.loaded ? R5.liveNoPeer(m.displayName) : R5.liveLoading;
      return R5.liveStatusNearbyFresh;
    }
    if (m.iAmDriver && m.boarded) return R5.liveRiderBoarded;
    if (m.boarded) return R5.liveStatusTogether;
    if (m.iAmRider && _driverArrived) return R6.driverArrivedStatus;
    if (stale != null) return stale;
    if (peerRaw == null) return peerView.loaded ? R5.liveNoPeer(m.displayName) : R5.liveLoading;
    return m.iAmRider ? R5.liveStatusComingToYou : R5.liveStatusGoingToPickup;
  }

  Widget _sheet(
    ScrollController sc, {
    required Trip t,
    required MatchSummary? m,
    required RideState state,
    required RidePrimary primary,
    required bool hasPeer,
    required TrackingState tracking,
    required String? stale,
    required PartnerView peerView,
    required LatLng? peerRaw,
    required LatLng? me,
    required bool nearBoard,
    required bool nearArrive,
    required HomeMatch homeMatch,
    required bool keyboardOpen,
    required double height,
    required AppTone? tone,
  }) {
    final tc = context.tone;
    final sheetColor = tc.isDriver ? tc.surfaceRaised : tc.surface;
    final hideSlider = keyboardOpen && height < 600;
    final overdue = t.status == TripStatus.inProgress &&
        arrivalPromptFor(trip: t, now: DateTime.now()) == ArrivalPrompt.overdue;
    _measureHeader();
    final header = Column(
      key: _headerKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _handle(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _peerRow(t, m, state, stale, peerView, peerRaw),
            if (state != RideState.arrived && !hideSlider) ...[
              const SizedBox(height: AppSpacing.md),
              _primaryAction(t, m, primary, nearBoard: nearBoard, nearArrive: nearArrive, homeMatch: homeMatch, help: false),
              if (overdue)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(P.arrivalOverdue, key: const Key('arrival-overdue'), style: Theme.of(context).textTheme.bodyMedium),
                ),
            ],
            const SizedBox(height: AppSpacing.md),
          ]),
        ),
      ],
    );

    return Material(
      color: sheetColor,
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        side: tc.isDriver ? BorderSide(color: tc.border) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomScrollView(
        key: const Key('ride-sheet'),
        controller: sc,
        slivers: [
          // Sizes to its content (no fixed extent), stays at the top of the sheet while the body scrolls.
          PinnedHeaderSliver(child: ColoredBox(color: sheetColor, child: header)),
          SliverToBoxAdapter(
            child: ValueListenableBuilder<SheetLevel>(
              valueListenable: _levelN,
              builder: (context, level, _) => level == SheetLevel.collapsed
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        AppSpacing.lg + MediaQuery.paddingOf(context).bottom,
                      ),
                      child: _body(
                        level,
                        t: t,
                        m: m,
                        state: state,
                        primary: primary,
                        hasPeer: hasPeer,
                        tracking: tracking,
                        stale: stale,
                        peerRaw: peerRaw,
                        me: me,
                        nearArrive: nearArrive,
                        homeMatch: homeMatch,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _handle() => ValueListenableBuilder<SheetLevel>(valueListenable: _levelN, builder: (_, l, _) => _handleFor(l));

  Widget _handleFor(SheetLevel l) {
    final name = switch (l) {
      SheetLevel.collapsed => R6.sheetLevelCollapsed,
      SheetLevel.half => R6.sheetLevelHalf,
      SheetLevel.full => R6.sheetLevelFull,
    };
    final tc = context.tone;
    return Semantics(
      container: true,
      button: true,
      label: R6.sheetLabel,
      value: name,
      liveRegion: true,
      onTap: _cycleLevel,
      customSemanticsActions: {
        if (l != SheetLevel.full)
          const CustomSemanticsAction(label: R6.sheetExpand): () => _animateTo(SheetLevel.values[l.index + 1]),
        if (l != SheetLevel.collapsed)
          const CustomSemanticsAction(label: R6.sheetCollapse): () => _animateTo(SheetLevel.values[l.index - 1]),
      },
      child: ExcludeSemantics(
        child: InkWell(
          key: const Key('ride-sheet-handle'),
          onTap: _cycleLevel,
          child: SizedBox(
            height: 48,
            width: double.infinity,
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: tc.borderStrong, borderRadius: BorderRadius.circular(2)),
                ),
                // Marker of the current level (tests / debugging); zero size.
                SizedBox.shrink(key: Key('ride-level-${l.name}')),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _peerRow(Trip t, MatchSummary? m, RideState state, String? stale, PartnerView peerView, LatLng? peerRaw) {
    final theme = Theme.of(context);
    final status = _statusText(t: t, m: m, state: state, stale: stale, peerView: peerView, peerRaw: peerRaw);
    final eta = (_eta == null || _etaKind == null || state == RideState.arrived) ? null : etaLine(_etaKind!, _eta!);
    final ended = m != null && m.status != MatchStatus.accepted;
    if (m == null || ended && !m.boarded && !m.iAmDriver) {
      // Solo / Peer-less trip: no partner row, no chat.
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(R6.soloTitle, style: theme.textTheme.titleMedium),
        Text(status, key: const Key('peer-status'), style: theme.textTheme.bodyMedium),
        if (eta != null) _etaRow(eta),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        UserAvatar.partner(
          name: m.displayName,
          matchId: m.id,
          size: 40,
          onTap: m.partnerId == null || ended
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: AppSpacing.sm, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(m.displayName, style: theme.textTheme.titleMedium),
              if (m.partnerRole != null) RoleBadge(m.partnerRole!),
            ]),
            Text(
              status,
              key: const Key('peer-status'),
              style: theme.textTheme.bodyMedium?.copyWith(color: stale != null ? context.tone.warningInk : null),
            ),
            if (stale != null && !ended)
              Text(R5.liveStaleHint, style: theme.textTheme.bodySmall?.copyWith(color: context.tone.textSecondary)),
          ]),
        ),
        if (!ended)
          IconButton(
            key: const Key('live-chat'),
            tooltip: R5.liveChat,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: Stack(clipBehavior: Clip.none, children: [
              const Icon(Icons.chat_bubble_outline),
              if (_unread.contains(m.id))
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: context.tone.danger, shape: BoxShape.circle),
                  ),
                ),
            ]),
            onPressed: () => _animateTo(SheetLevel.full),
          ),
      ]),
      if (eta != null) _etaRow(eta),
    ]);
  }

  Widget _etaRow(String eta) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Row(children: [
          const Icon(Icons.schedule, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(eta, key: const Key('eta-chip'), style: Theme.of(context).textTheme.titleSmall)),
        ]),
      );

  Widget _primaryAction(
    Trip t,
    MatchSummary? m,
    RidePrimary primary, {
    required bool nearBoard,
    required bool nearArrive,
    required HomeMatch homeMatch,
    required bool help,
  }) {
    switch (primary) {
      case RidePrimary.sliderStart:
        return SwipeToConfirmSlider(
          key: const ValueKey('slider-start'),
          label: R6.sliderStart,
          successLabel: R6.startedSuccess,
          showHelp: help,
          onConfirm: () => _confirmStart(t, m),
          onSucceeded: () => setState(() => _freeze = null),
        );
      case RidePrimary.sliderBoard:
        String? reason;
        if (m!.partnerTripStatus != null && m.partnerTripStatus != TripStatus.inProgress) reason = R.boardDisabledDriver;
        return SwipeToConfirmSlider(
          key: const ValueKey('slider-board'),
          label: R6.sliderBoard,
          successLabel: R6.boardedSuccess,
          successSemanticsLabel: R6.boardedSuccessSemantics,
          near: nearBoard,
          nearLabel: R6.sliderNearPickup,
          disabledReason: reason,
          showHelp: help,
          onConfirm: () => _confirmBoard(t, m),
          onSucceeded: () => setState(() => _freeze = null),
        );
      case RidePrimary.arrivedAtPickup:
        final now = ref.read(refreshClockProvider)();
        final left = _pickupGate.secondsLeft(now);
        final cooldown = _pickupSent && left > 0;
        if (!cooldown && _pickupSent) _pickupSent = false;
        final noPoint = m!.meetingPoint == null;
        final phase = _pickupSending
            ? PickupButtonPhase.sending
            : cooldown
                ? PickupButtonPhase.cooldown
                : noPoint
                    ? PickupButtonPhase.disabled
                    : PickupButtonPhase.ready;
        return ArrivedAtPickupButton(
          phase: phase,
          secondsLeft: left,
          disabledReason: noPoint ? R6.arrivedAtPickupNoPoint : null,
          onPressed: () => _sendArrivedAtPickup(m),
        );
      case RidePrimary.sliderArrive:
        return _arriveSlider(t, m, nearArrive: nearArrive, homeMatch: homeMatch, help: help);
      case RidePrimary.none:
      case RidePrimary.waiting:
      case RidePrimary.arrivedSummary:
        return const SizedBox.shrink();
    }
  }

  Widget _arriveSlider(Trip t, MatchSummary? m,
      {required bool nearArrive, required HomeMatch homeMatch, required bool help}) {
    return SwipeToConfirmSlider(
      key: const ValueKey('slider-arrive'),
      label: arriveSliderLabel(homeMatch),
      successLabel: arrivedMessage(homeMatch),
      successSemanticsLabel: arrivedMessageSemantics(homeMatch),
      near: nearArrive,
      nearLabel: R6.sliderNearDest,
      showHelp: help,
      onConfirm: () => _confirmArrive(t, m),
      onSucceeded: () {
        setState(() => _freeze = null);
        context.go(Routes.tripArrived(t.id));
      },
    );
  }

  Widget _body(
    SheetLevel level, {
    required Trip t,
    required MatchSummary? m,
    required RideState state,
    required RidePrimary primary,
    required bool hasPeer,
    required TrackingState tracking,
    required String? stale,
    required LatLng? peerRaw,
    required LatLng? me,
    required bool nearArrive,
    required HomeMatch homeMatch,
  }) {
    final theme = Theme.of(context);
    final tc = context.tone;
    const gap = SizedBox(height: AppSpacing.md);

    if (state == RideState.arrived) {
      return ArrivedSummary(trip: t, homeMatch: homeMatch);
    }

    final sharingLink = _sharingLink;
    final carMatch = (m != null && m.isCar) ? m : null;
    final inProgress = t.status == TripStatus.inProgress;

    final children = <Widget>[
      // -------- Half: status banners / notices --------
      // US-49: hidden once close to the destination so it never fights the arrive slider for space.
      if (_lateTrigger != LatenessTrigger.none && carMatch != null && !nearArrive) ...[
        LatenessCard(
          busy: _lateBusy,
          errorText: _lateError,
          onWaitMore: _waitMoreLateness,
          onCancelNoFault: () => _cancelNoFault(carMatch),
        ),
        gap,
      ],
      if (sharingLink) const _Banner(P.shareActive, AppCardTone.info, Icons.share_location),
      // Rider whose Driver finished first: neutral notice, own trip goes on (US-18).
      if (m != null && m.status != MatchStatus.accepted && m.iAmRider && m.boarded) ...[
        const AppCard(tone: AppCardTone.info, child: Text(R.partnerArrived, key: Key('partner-arrived'))),
        gap,
      ],
      // The routine "arrived" slider is always reachable (US-12) even when it is not the primary action.
      if (inProgress && primary != RidePrimary.sliderArrive) ...[
        _arriveSlider(t, m, nearArrive: nearArrive, homeMatch: homeMatch, help: true),
        gap,
      ] else if (inProgress) ...[
        const Text(R6.sliderHelp, key: Key('slider-help-body')),
        gap,
      ],
      if (carMatch != null && carMatch.iAmDriver && (carMatch.status == MatchStatus.accepted || carMatch.boarded || !carMatch.autoClosed)) ...[
        DriverRiderStatusSection(match: carMatch),
        if (carMatch.boarded) const Padding(padding: EdgeInsets.only(bottom: AppSpacing.sm), child: Text(R.riderInCar)),
      ],
      // Rider: "boarded" status card + "your location is no longer shown to the Driver" (US-18).
      if (carMatch != null && carMatch.iAmRider && carMatch.boarded) ...[
        BoardingButton(boardedAt: carMatch.boardedAt, busy: false, disabledReason: null, onPressed: () {}),
        gap,
      ],
      if (carMatch != null && carMatch.iAmRider && (carMatch.status == MatchStatus.accepted || carMatch.boarded)) ...[
        Consumer(
          builder: (context, ref, _) => ref.watch(matchVehicleProvider(carMatch.id)).when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => VehicleLoadError(onRetry: () => ref.invalidate(matchVehicleProvider(carMatch.id))),
                data: (view) => view == null ? const SizedBox.shrink() : VehicleInfoCard.forRider(view, compact: true),
              ),
        ),
        gap,
      ],
      if (carMatch != null && carMatch.status == MatchStatus.accepted) ...[
        RidePickupCard(match: carMatch),
        gap,
      ],
      if (carMatch != null && carMatch.iAmRider && carMatch.status == MatchStatus.accepted && !carMatch.boarded)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Text(R.boardShareNote, style: theme.textTheme.bodyMedium?.copyWith(color: tc.textSecondary)),
        ),
      if (carMatch != null && carMatch.status == MatchStatus.accepted) ...[
        Text(R6.quickRepliesTitle, style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: 48,
          child: ListView(
            key: const Key('quick-chips'),
            scrollDirection: Axis.horizontal,
            children: [
              for (final r in R5.quickReplies)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ActionChip(key: Key('quick-$r'), label: Text(r), onPressed: () => _pickQuick(r)),
                ),
            ],
          ),
        ),
        gap,
      ],
      NavigateButton(trip: t, match: m, myPosition: me),
      gap,
      _textStatus(t, m, me, peerRaw, stale),
      const SizedBox(height: AppSpacing.sm),
      Text(
        tracking.sharing ? P.trackingSharing : P.trackingNoPartner,
        style: theme.textTheme.bodyMedium?.copyWith(color: tc.textSecondary),
      ),
      Text(P.trackingNote, style: theme.textTheme.bodyMedium?.copyWith(color: tc.textSecondary)),
    ];

    if (level == SheetLevel.full) {
      children.addAll([
        const Divider(height: AppSpacing.xl),
        Text(R6.detailsSection, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        _detailRow(R6.routeFrom, t.originLabel),
        _detailRow(R6.routeTo, t.destLabel),
        _detailRow('เวลา', '${_hhmm(t.departAt)} · ${t.mode.label}'),
        if (t.distanceM > 0) _detailRow('ระยะทาง', formatRouteSummary(t.distanceM, t.durationS)),
        gap,
        AppButton(
          key: const Key('ride-share'),
          label: P.shareTripButton,
          variant: AppButtonVariant.secondary,
          icon: Icons.ios_share,
          onPressed: () => context.push(Routes.tripShare(t.id)),
        ),
        const Divider(height: AppSpacing.xl),
        Text(R6.safetySection, style: theme.textTheme.titleMedium),
        ListTile(
          key: const Key('ride-sos-tile'),
          minTileHeight: 56,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.shield_outlined, color: tc.danger),
          title: const Text(R6.sosTile),
          onTap: () => context.push(Routes.sosFor(tripId: t.id)),
        ),
        if (m != null && m.status == MatchStatus.accepted) ...[
          const Divider(height: AppSpacing.xl),
          RideChatSection(match: m, text: _chatText),
        ],
        const Divider(height: AppSpacing.xl),
        Text(R6.moreActions, style: theme.textTheme.titleMedium),
        if (m != null && m.partnerId != null)
          TextButton.icon(
            key: const Key('ride-report'),
            style: TextButton.styleFrom(minimumSize: const Size(0, AppSpacing.minTap)),
            icon: const Icon(Icons.flag_outlined),
            label: const Text(R6.reportPartnerAction),
            onPressed: () => context.push(Routes.report(m.partnerId!, matchId: m.id, name: m.displayName)),
          ),
        if (m != null && m.status == MatchStatus.accepted && !m.boarded)
          TextButton.icon(
            key: const Key('ride-match-detail'),
            style: TextButton.styleFrom(minimumSize: const Size(0, AppSpacing.minTap)),
            icon: const Icon(Icons.link_off),
            label: const Text(R6.cancelMatchAction),
            onPressed: () => context.push(Routes.match(m.id)),
          ),
        TextButton.icon(
          key: const Key('ride-cancel-trip'),
          style: TextButton.styleFrom(minimumSize: const Size(0, AppSpacing.minTap), foregroundColor: tc.dangerInk),
          icon: const Icon(Icons.cancel_outlined),
          label: const Text(R6.cancelTripAction),
          onPressed: () async {
            final ok = await cancelTripFlow(context, ref, t);
            if (ok && mounted) context.go(Routes.trips);
          },
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _detailRow(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 72, child: Text(k, style: TextStyle(color: context.tone.textSecondary))),
          Expanded(child: Text(v)),
        ]),
      );

  /// E-13: everything the map shows, as text (for screen-reader users).
  Widget _textStatus(Trip t, MatchSummary? m, LatLng? me, LatLng? peer, String? stale) {
    final rows = <(IconData, String)>[];
    if (m != null && m.status == MatchStatus.accepted) {
      if (me != null && peer != null) {
        final d = haversineM(me, peer);
        rows.add((Icons.near_me_outlined, R5.textAltDistance(m.displayName, coarseDistanceText(d), compassThai(bearingDeg(me, peer)))));
      } else if (t.status == TripStatus.inProgress) {
        rows.add((Icons.near_me_disabled_outlined, R5.liveNoPeer(m.displayName)));
      }
      if (m.meetingLabel != null) rows.add((Icons.flag_outlined, '${R5.livePickupLabel}: ${m.meetingLabel}'));
    }
    if (_eta != null && _etaKind != null) rows.add((Icons.schedule, etaLine(_etaKind!, _eta!)));
    if (m != null && m.status == MatchStatus.accepted && t.status == TripStatus.inProgress) {
      rows.add((stale == null ? Icons.wifi_tethering : Icons.access_time, stale ?? R5.liveStatusNearbyFresh));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Semantics(
      container: true,
      label: R6.textStatusTitle,
      child: Column(
        key: const Key('ride-text-status'),
        children: [for (final r in rows) ListTile(minTileHeight: 48, contentPadding: EdgeInsets.zero, leading: Icon(r.$1), title: Text(r.$2))],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.text, this.tone, this.icon, {super.key});
  final String text;
  final AppCardTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: AppCard(
          tone: tone,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(children: [
            Icon(icon, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(text)),
          ]),
        ),
      );
}
