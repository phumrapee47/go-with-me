import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/l10n/strings_r5.dart';
import '../../../core/theme/tone.dart';
import '../domain/live_map_logic.dart';

const _navy = Color(0xFF0B1B33);
const _amber = Color(0xFFF5A623);
const _mint = Color(0xFFCFF5E4);
const _personEdge = Color(0xFF12708A);

/// Top-down car (E-7): body, windshield, four wheels. Points "up" at heading 0; rotated by [heading].
class TopDownCarPainter extends CustomPainter {
  const TopDownCarPainter({this.color = _navy});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(w * .22, h * .06, w * .56, h * .88), Radius.circular(w * .2));
    final p = Paint()..color = color;
    // wheels
    for (final y in [h * .2, h * .66]) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * .14, y, w * .12, h * .16), Radius.circular(w * .04)), p);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * .74, y, w * .12, h * .16), Radius.circular(w * .04)), p);
    }
    canvas.drawRRect(body, p);
    final glass = Paint()..color = Colors.white.withValues(alpha: .85);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * .3, h * .24, w * .4, h * .18), Radius.circular(w * .06)), glass);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * .32, h * .64, w * .36, h * .12), Radius.circular(w * .05)), glass);
  }

  @override
  bool shouldRepaint(covariant TopDownCarPainter old) => old.color != color;
}

/// Partner icon. Driver = car (rotates with heading), Rider = person pin (never rotates). Shape AND the label
/// differ, so colour is never the only cue. Stale: 60 % opacity, dashed-look border, small clock.
class PeerIcon extends StatelessWidget {
  const PeerIcon({super.key, required this.driver, required this.stale, this.heading});
  final bool driver;
  final bool stale;
  final double? heading;

  @override
  Widget build(BuildContext context) {
    final label = driver ? R5.liveRoleDriver : R5.liveRoleRider;
    final circle = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: driver ? _amber : _mint,
        border: Border.all(color: driver ? Colors.white : _personEdge, width: 2),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Color(0x40000000))],
      ),
      child: driver
          ? Transform.rotate(
              angle: (heading ?? 0) * math.pi / 180,
              child: const Padding(padding: EdgeInsets.all(8), child: CustomPaint(painter: TopDownCarPainter(), key: Key('car-icon'))),
            )
          : const Icon(Icons.person_pin_circle, size: 30, color: _navy, key: Key('person-icon')),
    );
    // 96 x 96 box, circle centred (so the marker point is the circle centre), label under it.
    return Semantics(
      label: stale ? '$label ตำแหน่งเก่า' : label,
      excludeSemantics: true,
      child: Opacity(
        opacity: stale ? .6 : 1,
        child: SizedBox(
          width: 96,
          height: 96,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            circle,
            if (stale)
              const Positioned(
                right: 18,
                top: 18,
                child: CircleAvatar(radius: 9, backgroundColor: Colors.white, child: Icon(Icons.access_time, size: 13, color: _navy)),
              ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: context.tone.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: context.tone.border)),
                  child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.tone.text, height: 1.2)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

Marker _marker(LatLng p, Widget child, {double w = 64, double h = 72, Alignment alignment = Alignment.center}) =>
    Marker(point: p, width: w, height: h, alignment: alignment, child: child);

/// Flutter-map markers for [buildLiveMarkers]; [peerPoint] overrides the peer position with the
/// interpolated one so the icon glides between fixes.
List<Marker> toFlutterMarkers(List<LiveMarker> markers, {LatLng? peerPoint}) {
  return [
    for (final m in markers)
      switch (m.kind) {
        LiveMarkerKind.me => _marker(
            m.point,
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1976D2),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [BoxShadow(blurRadius: 4, color: Color(0x50000000))],
              ),
            ),
            w: 30,
            h: 30,
          ),
        LiveMarkerKind.peerDriver || LiveMarkerKind.peerRider => _marker(
            peerPoint ?? m.point,
            PeerIcon(driver: m.kind == LiveMarkerKind.peerDriver, stale: m.stale, heading: m.heading),
            w: 96,
            h: 96,
          ),
        LiveMarkerKind.pickup => _marker(
            m.point,
            const _Pin(icon: Icons.flag, label: R5.livePickupLabel, color: Color(0xFF2E7D32)),
            alignment: Alignment.topCenter,
            w: 96,
            h: 90,
          ),
        LiveMarkerKind.myDestination => _marker(
            m.point,
            const _Pin(icon: Icons.place, label: R5.liveDestLabel, color: Color(0xFFD32F2F)),
            alignment: Alignment.topCenter,
            w: 120,
            h: 90,
          ),
      },
  ];
}

class _Pin extends StatelessWidget {
  const _Pin({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 36, color: color),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: context.tone.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: context.tone.border)),
          // Map marker label in a fixed-size marker box: capped scale (the same info is in the text view).
          child: Text(label, textScaler: TextScaler.linear(MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3)), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.tone.text, height: 1.2)),
        ),
      ]);
}

/// 48 dp round map control with a tooltip label (E-12).
class MapControlButton extends StatelessWidget {
  const MapControlButton({super.key, required this.icon, required this.tooltip, required this.onTap, this.active = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Material(
          color: active ? context.tone.primary : context.tone.surface,
          elevation: 3,
          shape: const CircleBorder(),
          child: IconButton(
            tooltip: tooltip,
            icon: Icon(icon, color: active ? context.tone.onPrimary : context.tone.text),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: onTap,
          ),
        ),
      );
}
