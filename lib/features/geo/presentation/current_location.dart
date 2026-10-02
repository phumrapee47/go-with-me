import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_constants.dart';
import '../../../core/error/failure_messages.dart';
import '../../../core/geo/geo.dart';
import '../../../core/l10n/strings_trip.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../privacy/presentation/consent_providers.dart';
import '../domain/location_service.dart';
import 'geo_providers.dart';

/// Returns the current position or null (with a snackbar explaining why).
/// The OS prompt is preceded by our own rationale, and the consent is logged
/// (`record_consent`) before the first request. Denial never blocks the flow.
Future<LatLng?> obtainCurrentLocation(BuildContext context, WidgetRef ref) async {
  final loc = ref.read(locationServiceProvider);
  var state = await loc.permission();

  if (state == LocationPermissionState.denied) {
    if (!context.mounted) return null;
    final ok = await showConfirmDialog(
      context,
      title: T.locConsentTitle,
      body: T.locConsentBody,
      safeLabel: T.locConsentNot,
      confirmLabel: T.locConsentAllow,
      destructive: false,
    );
    if (!ok || !context.mounted) return null;
    final rec = await ref
        .read(consentRepositoryProvider)
        .recordLocationConsent(granted: true, policyVersion: AppConstants.policyVersion);
    final failure = rec.when(ok: (_) => null, err: (f) => f);
    if (failure != null) {
      if (context.mounted) _snack(context, failureMessage(failure));
      return null;
    }
    state = await loc.request();
  }

  if (state != LocationPermissionState.granted) {
    if (context.mounted) _snack(context, T.locOpenSettings);
    return null;
  }
  final pos = await loc.currentPosition();
  return pos.when(
    ok: (p) => p,
    err: (f) {
      if (context.mounted) _snack(context, failureMessage(f));
      return null;
    },
  );
}

/// Reverse-geocode label; never throws: falls back to short coordinates so a
/// failing geocoder cannot block saving a trip (design-api 9.2).
Future<String> labelFor(WidgetRef ref, LatLng p) async {
  try {
    return await ref.read(geocodingServiceProvider).reverse(p);
  } catch (_) {
    return coordLabel(p);
  }
}

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// Before a trip starts: makes sure location consent is logged and the OS
/// permission asked (rationale first). Returns true when live tracking can
/// run. False never blocks the trip: it only means no position on the map
/// (design-spec S-21 gps-off-or-denied) and SOS/"arrived" still work.
Future<bool> ensureTrackingReady(BuildContext context, WidgetRef ref) async {
  final consent = await ref.read(consentRepositoryProvider).locationConsentGranted();
  final granted = consent.when(ok: (v) => v, err: (_) => false);
  if (!granted) {
    if (!context.mounted) return false;
    final ok = await showConfirmDialog(
      context,
      title: T.locConsentTitle,
      body: T.locConsentBody,
      safeLabel: T.locConsentNot,
      confirmLabel: T.locConsentAllow,
      destructive: false,
    );
    if (!ok) return false;
    final rec = await ref
        .read(consentRepositoryProvider)
        .recordLocationConsent(granted: true, policyVersion: AppConstants.policyVersion);
    if (rec.when(ok: (_) => false, err: (_) => true)) return false;
    ref.invalidate(locationConsentProvider);
  }
  final loc = ref.read(locationServiceProvider);
  var state = await loc.permission();
  if (state == LocationPermissionState.denied) state = await loc.request();
  return state == LocationPermissionState.granted;
}
