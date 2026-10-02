import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/geo/geo.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/l10n/strings_trip.dart';
import '../../../core/map/app_map.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../trip/domain/travel_mode.dart';
import '../../trip/domain/trip.dart';
import '../domain/location_service.dart';
import 'current_location.dart';
import 'geo_providers.dart';

/// Marker state for US-43 road-snap (G.2.2/G.2.3). `none` = feature off
/// ([PickPointScreen.snapMode] not set, e.g. plain trip origin/destination
/// picking, which US-43 does not touch).
enum SnapMarkerState { none, snapping, snapped, rawRejected, rawFallbackError }

/// Full-screen pin picker: the pin stays in the middle, the map moves under it.
/// Pops with a [Place]. Used for trip origin/destination and meeting points.
class PickPointScreen extends ConsumerStatefulWidget {
  const PickPointScreen({
    super.key,
    required this.title,
    this.initial,
    this.route = const [],
    this.confirmLabel,
    this.note,
    this.onPicked,
    this.snapMode,
  });

  final String title;
  final LatLng? initial;

  /// Optional line drawn under the pin (e.g. the Driver's own route for a pickup point).
  final List<LatLng> route;

  /// Overrides "ใช้จุดนี้".
  final String? confirmLabel;
  final String? note;

  /// When set, called instead of popping with the [Place]; the caller decides
  /// what happens next (send to server, warn, pop). Returns true to close.
  final Future<bool> Function(Place place)? onPicked;

  /// US-43 (R7.11/Q4): when set, one OSRM `nearest` lookup runs when the user
  /// taps the confirm button (not on every drag) using this travel mode's
  /// OSRM profile. Null = road-snap is off (e.g. plain origin/destination
  /// picking outside PickupScreen, unaffected by US-43).
  final TravelMode? snapMode;

  @override
  ConsumerState<PickPointScreen> createState() => _PickPointScreenState();
}

class _PickPointScreenState extends ConsumerState<PickPointScreen> {
  final _map = MapController();
  late LatLng _center = widget.initial ?? defaultMapCenter;
  String? _label;
  bool _resolving = false;
  Timer? _timer;
  int _gen = 0;

  SnapMarkerState _snapState = SnapMarkerState.none;
  String? _snapCaption;
  Timer? _captionTimer;

  @override
  void initState() {
    super.initState();
    _scheduleReverse();
    if (widget.initial == null) _tryStartFromCurrent();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _captionTimer?.cancel();
    _map.dispose();
    super.dispose();
  }

  // Never prompts: only centres on the user when permission is already granted.
  Future<void> _tryStartFromCurrent() async {
    final loc = ref.read(locationServiceProvider);
    if (await loc.permission() != LocationPermissionState.granted) return;
    final r = await loc.currentPosition();
    r.when(ok: _moveTo, err: (_) {});
  }

  void _moveTo(LatLng p) {
    if (!mounted) return;
    _map.move(p, 16);
  }

  void _onMoved(LatLng c, bool byUser) {
    _center = c;
    // A fresh manual drag invalidates any earlier snap result (G.2.1 step 6):
    // back to "raw" until the next confirm tap snaps again.
    if (byUser && _snapState != SnapMarkerState.none) {
      _snapState = SnapMarkerState.none;
    }
    _scheduleReverse();
  }

  // One reverse lookup per pause (800 ms), shares the app-wide 1 req/s limit.
  void _scheduleReverse() {
    _timer?.cancel();
    final gen = ++_gen;
    // May be called from a map callback during layout: defer the rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && gen == _gen) {
        setState(() {
          _resolving = true;
          _label = null;
        });
      }
    });
    _timer = Timer(const Duration(milliseconds: 800), () async {
      final at = _center;
      final label = await labelFor(ref, at);
      if (!mounted || gen != _gen) return;
      setState(() {
        _label = label;
        _resolving = false;
      });
    });
  }

  bool _submitting = false;

  void _showCaption(String text) {
    _captionTimer?.cancel();
    setState(() => _snapCaption = text);
    _captionTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _snapCaption = null);
    });
  }

  /// US-43 (R7.11/12, Q4): one OSRM `nearest` call, only here (confirm tap),
  /// never on drag. Fail-open in every branch: the raw point is always usable.
  Future<void> _trySnapOnce() async {
    final mode = widget.snapMode;
    if (mode == null) return;
    _captionTimer?.cancel();
    setState(() {
      _snapState = SnapMarkerState.snapping;
      _snapCaption = null;
    });
    final raw = _center;
    try {
      final result = await ref.read(roadSnapServiceProvider).nearest(mode: mode, point: raw);
      if (!mounted) return;
      final limit = ref.read(serviceConfigProvider).snapMaxDeviationM;
      if (result.deviationM <= limit) {
        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        setState(() {
          _center = result.point;
          _snapState = SnapMarkerState.snapped;
        });
        if (reduceMotion) {
          _map.move(result.point, _map.camera.zoom);
        } else {
          await _animateMoveTo(result.point);
        }
        if (mounted) _showCaption(R.pickupSnappedToast);
      } else {
        // Deviation beyond the safe threshold (e.g. across a river/highway):
        // silent, keep the raw point (G.2.1 branch ก).
        if (mounted) setState(() => _snapState = SnapMarkerState.rawRejected);
      }
    } on AppFailure {
      // Service down/timeout/rate-limited: silent fallback to the raw point,
      // one small non-blocking caption (G.2.1 branch ค).
      if (!mounted) return;
      setState(() => _snapState = SnapMarkerState.rawFallbackError);
      _showCaption(R.pickupSnapFallbackToast);
    }
  }

  /// Short (150-200 ms) move animation; skipped entirely under reduce-motion
  /// (caller already jumps directly in that case).
  Future<void> _animateMoveTo(LatLng target) async {
    final from = _map.camera.center;
    final zoom = _map.camera.zoom;
    const steps = 8;
    for (var i = 1; i <= steps; i++) {
      if (!mounted) return;
      final t = i / steps;
      _map.move(
        LatLng(
          from.latitude + (target.latitude - from.latitude) * t,
          from.longitude + (target.longitude - from.longitude) * t,
        ),
        zoom,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> _confirm(BuildContext context) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    if (widget.snapMode != null) await _trySnapOnce();
    if (!mounted || !context.mounted) return;
    final place = Place(point: _center, label: _label ?? coordLabel(_center));
    final cb = widget.onPicked;
    if (cb == null) {
      setState(() => _submitting = false);
      Navigator.of(context).pop(place);
      return;
    }
    final close = await cb(place);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (close && context.mounted) Navigator.of(context).pop(place);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          AppMap(
            controller: _map,
            center: _center,
            zoom: 16,
            route: widget.route,
            onPositionChanged: _onMoved,
            onMyLocation: () async {
              final p = await obtainCurrentLocation(context, ref);
              if (p != null) _moveTo(p);
            },
          ),
          IgnorePointer(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 36),
                child: _PickupMarker(state: _snapState),
              ),
            ),
          ),
          if (_snapState == SnapMarkerState.snapping || _snapCaption != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    margin: const EdgeInsets.only(top: AppSpacing.md),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: context.tone.surface,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      boxShadow: const [BoxShadow(blurRadius: 6, color: Color(0x22000000))],
                    ),
                    child: Text(
                      _snapState == SnapMarkerState.snapping ? R.pickupSnapping : _snapCaption!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(AppSpacing.lg),
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: context.tone.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  boxShadow: const [BoxShadow(blurRadius: 8, color: Color(0x33000000))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _resolving ? T.resolvingAddress : (_label ?? coordLabel(_center)),
                      style: theme.textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (widget.note != null) ...[
                      Text(widget.note!, style: theme.textTheme.bodySmall),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    AppButton(
                      key: const Key('pick-confirm'),
                      label: widget.confirmLabel ?? T.usePoint,
                      loading: _submitting,
                      onPressed: () => _confirm(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// G.2.2/G.2.3: marker style difference is shape-based (ring + small road
/// icon), not colour-only, plus an a11y label that announces the change.
class _PickupMarker extends StatelessWidget {
  const _PickupMarker({required this.state});
  final SnapMarkerState state;

  @override
  Widget build(BuildContext context) {
    final color = context.tone.dangerInk;
    final snapped = state == SnapMarkerState.snapped;
    final label = snapped ? R.pickupMarkerA11ySnapped : R.pickupMarkerA11yRaw;
    return Semantics(
      liveRegion: true,
      label: label,
      child: SizedBox(
        width: 52,
        height: 52,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (snapped)
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
              ),
            Icon(Icons.place, size: 44, color: color),
            if (snapped)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(color: context.tone.surface, shape: BoxShape.circle),
                  child: Icon(Icons.add_road, size: 12, color: color),
                ),
              ),
            if (state == SnapMarkerState.snapping)
              Positioned(
                top: 0,
                right: 0,
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
