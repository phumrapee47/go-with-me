import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure_messages.dart';
import '../../../core/l10n/strings_p4.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/providers.dart';
import '../../../core/router/redirect.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../geo/presentation/current_location.dart';
import '../../matching/domain/match_models.dart';
import '../../matching/presentation/matching_providers.dart';
import '../../safety/domain/safety_models.dart';
import '../../safety/presentation/safety_providers.dart';
import '../domain/trip.dart';
import '../domain/trip_state_machine.dart';
import 'trip_lifecycle_providers.dart';

const noContactsPromptKey = 'no_contacts_prompt_seen';

/// Q-8: the "your matched partner sees your live position" notice is shown once.
const carLiveConsentSeenKey = 'car_live_consent_seen';

void _snack(BuildContext c, String t) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(t)));

/// Start flow (US-9): one-time nudge to set emergency contacts (PM P-3, can
/// be skipped), location consent + permission (never blocks), then the
/// guarded PATCH. Returns true when the trip is now in progress.
Future<bool> startTripFlow(BuildContext context, WidgetRef ref, Trip trip) async {
  final prefs = ref.read(sharedPrefsProvider);
  List<EmergencyContact>? contacts;
  try {
    contacts = await ref.read(contactsProvider.future);
  } catch (_) {
    contacts = null; // unknown: do not nag on a failed read
  }
  if (!context.mounted) return false;
  if (contacts != null && contacts.isEmpty && !(prefs.getBool(noContactsPromptKey) ?? false)) {
    await prefs.setBool(noContactsPromptKey, true);
    if (!context.mounted) return false;
    final setup = await showConfirmDialog(
      context,
      title: P.noContactsTitle,
      body: P.noContactsBody,
      safeLabel: P.noContactsSkip,
      confirmLabel: P.noContactsSetup,
      destructive: false,
    );
    if (!context.mounted) return false;
    if (setup) {
      await context.push<void>(Routes.safetyContacts);
      return false; // they come back and press start again
    }
  }
  if (trip.isCar) {
    if (!await _carStartChecks(context, ref, trip)) return false;
    if (!context.mounted) return false;
  }
  await ensureTrackingReady(context, ref);
  if (!context.mounted) return false;
  final res = await ref.read(tripActionsProvider).run(trip.id, TripAction.start);
  if (!context.mounted) return false;
  return res.when(
    ok: (_) {
      context.go(Routes.tripActive(trip.id));
      return true;
    },
    err: (f) {
      _snack(context, failureMessage(f));
      return false;
    },
  );
}

/// Car-only steps before starting: the live-position notice (Q-8, once) and,
/// for a Driver with a matched Rider and no agreed pickup, a non-blocking
/// reminder (F-R5.8: starting is always allowed).
Future<bool> _carStartChecks(BuildContext context, WidgetRef ref, Trip trip) async {
  final prefs = ref.read(sharedPrefsProvider);
  final inbox = ref.read(inboxProvider).valueOrNull ?? const <MatchSummary>[];
  final match = inbox.where((m) => m.myTripId == trip.id && m.isCar && m.status == MatchStatus.accepted).firstOrNull;

  if (match != null && !(prefs.getBool(carLiveConsentSeenKey) ?? false)) {
    final ok = await showConfirmDialog(
      context,
      title: R.consentSheetTitle,
      body: R.consentSheetBody,
      safeLabel: R.consentSheetBack,
      confirmLabel: R.consentSheetOk,
      destructive: false,
    );
    if (!ok || !context.mounted) return false;
    await prefs.setBool(carLiveConsentSeenKey, true);
    if (!context.mounted) return false;
  }
  if (match != null && trip.role == TripRole.driver && match.meetingPoint == null) {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('pickup-start-warning'),
        title: const Text(R.pickupStartWarnTitle),
        content: const Text(R.pickupStartWarnBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop('chat'), child: const Text(R.pickupOpenChat)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop('start'), child: const Text(R.pickupStartAnyway)),
        ],
      ),
    );
    if (!context.mounted) return false;
    if (choice == 'chat') {
      await context.push<void>(Routes.chat(match.id));
      return false; // they come back and press start again
    }
    if (choice != 'start') return false;
  }
  return context.mounted;
}

/// Cancel with a dialog that says what happens to partners.
Future<bool> cancelTripFlow(BuildContext context, WidgetRef ref, Trip trip) async {
  final inbox = ref.read(inboxProvider).valueOrNull ?? const <MatchSummary>[];
  final partners = acceptedPartnersOf(inbox, trip.id);
  final carMatch = trip.isCar ? partners.where((m) => m.isCar).firstOrNull : null;

  // Q-1(a): a Driver cannot cancel once the Rider boarded. The server refuses
  // too (GWM_ALREADY_BOARDED); this just says why without a round trip.
  if (carMatch != null && trip.role == TripRole.driver && carMatch.boarded) {
    _snack(context, R.cannotCancelAfterBoarded);
    return false;
  }
  final String title;
  final String body;
  final String confirm;
  final String keep;
  if (carMatch != null && trip.role == TripRole.driver && trip.status == TripStatus.inProgress) {
    // A Rider may be waiting at the pickup or already in the car: stronger wording.
    title = R.cancelDuringTripTitle;
    body = R.cancelDuringTripBody;
    confirm = R.cancelDuringTripConfirm;
    keep = R.cancelKeep;
  } else if (carMatch != null) {
    title = P.cancelTripTitle;
    body = R.cancelTripWithMatchBody;
    confirm = P.cancelTrip;
    keep = P.cancelTripKeep;
  } else {
    title = P.cancelTripTitle;
    body = partners.isNotEmpty
        ? P.cancelTripBodyPartner.replaceFirst('%s', '${partners.length}')
        : P.cancelTripBodyNoPartner;
    confirm = P.cancelTrip;
    keep = P.cancelTripKeep;
  }
  final ok = await showConfirmDialog(
    context,
    title: title,
    body: body,
    safeLabel: keep,
    confirmLabel: confirm,
  );
  if (!ok || !context.mounted) return false;
  final res = await ref.read(tripActionsProvider).run(trip.id, TripAction.cancel);
  if (!context.mounted) return false;
  _snack(context, res.when(ok: (_) => P.tripCancelled, err: failureMessage));
  return res.when(ok: (_) => true, err: (_) => false);
}

Future<bool> deleteTripFlow(BuildContext context, WidgetRef ref, Trip trip) async {
  final ok = await showConfirmDialog(
    context,
    title: P.deleteTripTitle,
    body: P.deleteTripBody,
    safeLabel: P.deleteTripKeep,
    confirmLabel: P.deleteTrip,
  );
  if (!ok || !context.mounted) return false;
  final res = await ref.read(tripActionsProvider).delete(trip.id);
  if (!context.mounted) return false;
  _snack(context, res.when(ok: (_) => P.tripDeleted, err: failureMessage));
  return res.when(ok: (_) => true, err: (_) => false);
}
