import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/geo/presentation/geo_providers.dart';
import '../theme/tokens.dart';
import '../theme/tone.dart';
import '../widgets/app_button.dart';

/// Default view when there is no position yet (central Bangkok).
const defaultMapCenter = LatLng(13.7563, 100.5018);

/// A blurred-area circle for other people (never a single pin, C-6).
class MapArea {
  const MapArea({required this.center, required this.radiusM, this.highlighted = false});
  final LatLng center;
  final double radiusM;
  final bool highlighted;
}

class MapPin {
  const MapPin({required this.point, this.icon = Icons.place, this.color = AppColors.blue});
  final LatLng point;
  final IconData icon;
  final Color color;
}

/// C-6: shared OSM map. Attribution is always visible; if tiles fail to load a
/// message card replaces the tiles while the rest of the screen stays usable.
class AppMap extends ConsumerStatefulWidget {
  const AppMap({
    super.key,
    this.controller,
    this.center = defaultMapCenter,
    this.zoom = 13,
    this.route = const [],
    this.areas = const [],
    this.pins = const [],
    this.markers = const [],
    this.onTap,
    this.onPositionChanged,
    this.onMyLocation,
    this.interactive = true,
    this.showZoomButtons = true,
    this.routeTone,
  });

  final MapController? controller;
  final LatLng center;
  final double zoom;
  final List<LatLng> route;
  final List<MapArea> areas;
  final List<MapPin> pins;

  /// Free-form markers (live map icons: car, person pin...), drawn above [pins].
  final List<Marker> markers;
  final void Function(LatLng point)? onTap;
  final void Function(LatLng center, bool byUser)? onPositionChanged;
  final VoidCallback? onMyLocation;
  final bool interactive;
  final bool showZoomButtons;

  /// Tone whose route colour is used (the TRIP's role). null = the tone of the surrounding theme.
  final AppTone? routeTone;

  @override
  ConsumerState<AppMap> createState() => _AppMapState();
}

class _AppMapState extends ConsumerState<AppMap> {
  late final MapController _own = MapController();
  MapController get _c => widget.controller ?? _own;
  int _tileErrors = 0;
  int _reloadKey = 0;

  static const _errorThreshold = 4;

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  void _zoom(double delta) {
    final cam = _c.camera;
    _c.move(cam.center, (cam.zoom + delta).clamp(3, 19));
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(serviceConfigProvider);
    final tiles = ref.watch(mapTilesEnabledProvider);
    final failed = _tileErrors >= _errorThreshold;
    // US-46 (round 7): dark tile swap follows the effective app brightness (rider/driver-dark),
    // config-swappable the same way as the light tile URL (design-roles G.5).
    // No TILE_URL_DARK override -> no external dark-tile dependency at all:
    // the light OSM tiles are rendered through _darkTileFilter below instead
    // (see service_config.dart for why there's no default dark tile URL).
    final dark = context.tone.isDark;
    final hasDarkOverride = cfg.tileUrlTemplateDark.isNotEmpty;
    final tileUrl = dark && hasDarkOverride ? cfg.tileUrlTemplateDark : cfg.tileUrlTemplate;
    final tintTilesDark = dark && !hasDarkOverride;

    return Stack(
      children: [
        FlutterMap(
          mapController: _c,
          options: MapOptions(
            initialCenter: widget.center,
            initialZoom: widget.zoom,
            minZoom: 3,
            maxZoom: 19,
            backgroundColor: const Color(0xFFE9EEF3),
            interactionOptions: InteractionOptions(
              flags: widget.interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none,
            ),
            onTap: widget.onTap == null ? null : (_, p) => widget.onTap!(p),
            onPositionChanged: widget.onPositionChanged == null
                ? null
                : (cam, byUser) => widget.onPositionChanged!(cam.center, byUser),
          ),
          children: [
            if (tiles)
              _MaybeDarkTiles(
                dark: tintTilesDark,
                child: TileLayer(
                  key: ValueKey((_reloadKey, dark)),
                  urlTemplate: tileUrl,
                  userAgentPackageName: cfg.tileUserAgentPackage,
                  errorTileCallback: (_, _, _) {
                    if (mounted && _tileErrors < _errorThreshold) setState(() => _tileErrors++);
                  },
                ),
              ),
            if (widget.route.length >= 2)
              PolylineLayer(polylines: [
                // Route colour follows the role of the trip (blue = Rider, amber + navy casing = Driver on a light map; light casing on a dark map).
                () {
                  final rt = widget.routeTone == null ? context.tone : ToneColors.of(widget.routeTone!);
                  return Polyline(
                    points: widget.route,
                    strokeWidth: rt.routeWidth,
                    color: rt.routeColor,
                    borderColor: rt.routeCasing,
                    borderStrokeWidth: rt.isDriver ? 2 : 1.5,
                  );
                }(),
              ]),
            if (widget.areas.isNotEmpty)
              CircleLayer(circles: [
                for (final a in widget.areas)
                  CircleMarker(
                    point: a.center,
                    radius: a.radiusM,
                    useRadiusInMeter: true,
                    color: (a.highlighted ? AppColors.green : AppColors.teal).withValues(alpha: 0.25),
                    borderColor: a.highlighted ? AppColors.greenDark : AppColors.tealDark,
                    borderStrokeWidth: a.highlighted ? 3 : 1.5,
                  ),
              ]),
            if (widget.pins.isNotEmpty)
              MarkerLayer(markers: [
                for (final p in widget.pins)
                  Marker(
                    point: p.point,
                    width: 40,
                    height: 40,
                    alignment: Alignment.topCenter,
                    // G.5.2 (round 7): subtle white glow behind every pin on dark tiles so it
                    // clears the WCAG AA >= 3:1 bar against the dark basemap.
                    child: dark
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: Colors.white.withValues(alpha: 0.55), blurRadius: 8, spreadRadius: 1),
                              ],
                            ),
                            child: Icon(p.icon, size: 36, color: p.color),
                          )
                        : Icon(p.icon, size: 36, color: p.color),
                  ),
              ]),
            if (widget.markers.isNotEmpty) MarkerLayer(markers: widget.markers),
            RichAttributionWidget(
              alignment: AttributionAlignment.bottomLeft,
              showFlutterMapAttribution: false,
              attributions: [
                TextSourceAttribution(
                  '© OpenStreetMap contributors',
                  onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
                ),
              ],
            ),
          ],
        ),
        if (failed)
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.lg,
            child: Card(
              color: context.tone.warningTint,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Icon(Icons.wifi_off_outlined, color: context.tone.warningInk),
                    const SizedBox(width: AppSpacing.md),
                    const Expanded(child: Text('โหลดแผนที่ไม่ได้ในตอนนี้ ส่วนอื่นของหน้ายังใช้งานได้')),
                    AppButton(
                      label: 'ลองใหม่',
                      expand: false,
                      variant: AppButtonVariant.text,
                      onPressed: () => setState(() {
                        _tileErrors = 0;
                        _reloadKey++;
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          right: AppSpacing.md,
          bottom: AppSpacing.xxl + AppSpacing.md,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.onMyLocation != null)
                _MapButton(icon: Icons.my_location, tooltip: 'ไปที่ตำแหน่งของฉัน', onTap: widget.onMyLocation!),
              if (widget.showZoomButtons) ...[
                _MapButton(icon: Icons.add, tooltip: 'ซูมเข้า', onTap: () => _zoom(1)),
                _MapButton(icon: Icons.remove, tooltip: 'ซูมออก', onTap: () => _zoom(-1)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Material(
        color: context.tone.surface,
        elevation: 2,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          icon: Icon(icon, color: context.tone.text),
          constraints: const BoxConstraints(minWidth: AppSpacing.minTap, minHeight: AppSpacing.minTap),
          onPressed: onTap,
        ),
      ),
    );
  }
}

/// Renders the standard OSM light tiles as a dark map with no external
/// dark-tile provider (and so no API key/policy dependency): colour-invert
/// then hue-rotate 180°, the same trick many map apps use for a "free" dark
/// mode. Roads/labels stay legible; water/parks land close to their natural
/// hue after the rotation. Only used when no TILE_URL_DARK override is set.
class _MaybeDarkTiles extends StatelessWidget {
  const _MaybeDarkTiles({required this.dark, required this.child});
  final bool dark;
  final Widget child;

  // Invert (c' = 255-c) composed with a 180° hue rotation, derived from the
  // standard SVG feColorMatrix hueRotate formula at cosA=-1, sinA=0. Every
  // row of the underlying hue matrix sums to 1 (gray-preserving); verified
  // by hand: feeding grey (128,128,128) through this combined matrix must
  // return (≈127,≈127,≈127), not a tinted colour. (An earlier version of
  // this matrix had an arithmetic error in the G/B rows that broke this —
  // fixed 2026-09-28.)
  static const _invertHueRotate180 = <double>[
    0.574, -1.430, -0.144, 0, 255,
    -0.426, -0.430, -0.144, 0, 255,
    -0.426, -1.430, 0.856, 0, 255,
    0, 0, 0, 1, 0,
  ];

  @override
  Widget build(BuildContext context) {
    if (!dark) return child;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(_invertHueRotate180),
      child: child,
    );
  }
}
