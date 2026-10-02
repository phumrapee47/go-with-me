import 'package:latlong2/latlong.dart';

import '../../../core/geo/geo.dart';

/// US-24 external navigation (D14). Only the coordinates of the target are ever placed in a URL:
/// the agreed pickup, or the caller's own destination. Never the partner's position or destination.
enum MapApp { google, apple, web }

/// Which single navigation button to show (E-9): chosen by state, hidden within 50 m of the pickup.
enum NavButtonState { toPickup, toPickupDisabledNoPoint, toDestination, hidden }

const pickupHideRadiusM = 50.0;

NavButtonState navButtonState({
  required bool matchAccepted,
  required bool riderBoarded,
  required bool myTripInProgress,
  required LatLng? pickup,
  required LatLng? myPosition,
}) {
  if (!myTripInProgress) return NavButtonState.hidden;
  final waitingForPickup = matchAccepted && !riderBoarded;
  if (!waitingForPickup) return NavButtonState.toDestination;
  if (pickup == null) return NavButtonState.toPickupDisabledNoPoint;
  if (myPosition != null && haversineM(myPosition, pickup) <= pickupHideRadiusM) return NavButtonState.hidden;
  return NavButtonState.toPickup;
}

String _c(LatLng p) => '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}';

/// Directions URL for [app] to [target]. All three use https so they work on every platform: the
/// Google URL opens the app when it is installed, Apple's opens Maps on iOS/macOS.
Uri mapLink(MapApp app, LatLng target) => switch (app) {
      MapApp.google => Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${_c(target)}&travelmode=driving'),
      MapApp.apple => Uri.parse('https://maps.apple.com/?daddr=${_c(target)}&dirflg=d'),
      MapApp.web => Uri.parse(
          'https://www.openstreetmap.org/directions?engine=fossgis_osrm_car&route=%3B${target.latitude.toStringAsFixed(6)}%2C${target.longitude.toStringAsFixed(6)}',
        ),
    };

/// Apps offered on this platform. Apple Maps only on iOS/macOS; the web link is always the fallback.
List<MapApp> availableMapApps({required bool isApple}) => [
      MapApp.google,
      if (isApple) MapApp.apple,
      MapApp.web,
    ];
