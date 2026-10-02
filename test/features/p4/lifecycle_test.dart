import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/l10n/strings.dart';
import 'package:gowithme/core/l10n/strings_p4.dart';
import 'package:gowithme/core/l10n/strings_r5.dart';
import 'package:gowithme/core/l10n/strings_r6.dart';
import 'package:gowithme/core/router/redirect.dart';
import 'package:gowithme/features/chat/domain/chat_models.dart';
import 'package:gowithme/features/geo/domain/location_service.dart';
import 'package:gowithme/features/geo/presentation/geo_providers.dart';
import 'package:gowithme/features/safety/domain/safety_models.dart';
import 'package:gowithme/features/trip/domain/live_location.dart';
import 'package:gowithme/features/trip/domain/trip.dart';
import 'package:gowithme/features/trip/presentation/trip_lifecycle_providers.dart';
import 'package:gowithme/features/trip/presentation/unified_ride_screen.dart';
import 'package:latlong2/latlong.dart';

import '../../support/fake_repos.dart';
import '../../support/fakes.dart';
import '../../support/p4_helpers.dart';
import '../../support/ride_helpers.dart';

Trip _finished(String id, TripStatus s, String dest) => sampleTrip(id: id).copyWith(status: s, endedAt: DateTime.now());

Fakes _withContacts(Fakes f) {
  f.contacts.items.add(const EmergencyContact(id: 'c1', name: 'แม่', phone: '0812345678'));
  return f;
}

Future<void> _tapTripsTab(WidgetTester tester) async {
  await tester.tap(find.text(S.tabTrips));
  await tester.pumpAndSettle();
}

void main() {
  group('my trips tab', () {
    testWidgets('current: card with status chip and partner count, create is disabled while a trip is active',
        (tester) async {
      final f = Fakes()
        ..trips.active = sampleTrip()
        ..matches.matches = [acceptedMatch()];
      await openApp(tester, f);
      await _tapTripsTab(tester);

      expect(find.text(P.statusScheduled), findsOneWidget);
      expect(find.text('รังสิต'), findsOneWidget);
      expect(find.text('จับคู่แล้ว 1/3'), findsOneWidget);
      expect(find.text(P.createTripDisabled), findsOneWidget);
      final fab = tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));
      expect(fab.onPressed, isNull);
    });

    testWidgets('current: empty state offers to create a trip, FAB enabled', (tester) async {
      await openApp(tester, Fakes());
      await _tapTripsTab(tester);
      expect(find.text(P.tripsEmptyCurrent), findsOneWidget);
      expect(tester.widget<FloatingActionButton>(find.byType(FloatingActionButton)).onPressed, isNotNull);
    });

    testWidgets('history: completed, cancelled and expired trips, each with its state', (tester) async {
      final f = Fakes();
      f.trips.finished.addAll([
        _finished('h1', TripStatus.completed, 'ก'),
        _finished('h2', TripStatus.cancelled, 'ข'),
        _finished('h3', TripStatus.expired, 'ค'),
      ]);
      await openApp(tester, f);
      await _tapTripsTab(tester);
      await tester.tap(find.text(P.segHistory));
      await tester.pumpAndSettle();
      expect(find.text(P.statusCompleted), findsOneWidget);
      expect(find.text(P.statusCancelled), findsOneWidget);
      expect(find.text(P.statusExpired), findsOneWidget);
      expect(find.text(P.recreateTrip), findsOneWidget, reason: 'expired trips can be recreated');
    });

    testWidgets('history empty state', (tester) async {
      await openApp(tester, Fakes());
      await _tapTripsTab(tester);
      await tester.tap(find.text(P.segHistory));
      await tester.pumpAndSettle();
      expect(find.text(P.tripsEmptyHistory), findsOneWidget);
    });
  });

  group('start / cancel / arrive', () {
    testWidgets('start: one-time emergency-contact nudge (skippable), then in progress and the active screen',
        (tester) async {
      final f = Fakes()..trips.active = sampleTrip();
      await openApp(tester, f);
      await _tapTripsTab(tester);
      await tester.tap(find.text(P.startTrip));
      await tester.pumpAndSettle();

      expect(find.text(P.noContactsTitle), findsOneWidget);
      await tester.tap(find.text(P.noContactsSkip));
      await tester.pumpAndSettle();

      expect(f.trips.transitions.single.$2.name, 'start');
      expect(f.trips.active!.status, TripStatus.inProgress);
      expect(find.text(P.activeTitle), findsOneWidget);
      // Round 6: the "arrived" confirm is the slider on the unified ride screen.
      expect(find.byKey(sliderArriveKey), findsOneWidget);
    });

    testWidgets('start: choosing "set up now" opens contacts and does not start', (tester) async {
      final f = Fakes()..trips.active = sampleTrip();
      await openApp(tester, f);
      await _tapTripsTab(tester);
      await tester.tap(find.text(P.startTrip));
      await tester.pumpAndSettle();
      await tester.tap(find.text(P.noContactsSetup));
      await tester.pumpAndSettle();
      expect(find.text(P.contactsAdd), findsOneWidget);
      expect(f.trips.transitions, isEmpty);
    });

    testWidgets('start with contacts: no nudge; denied location never blocks the trip', (tester) async {
      final f = _withContacts(Fakes()..trips.active = sampleTrip());
      f.location
        ..state = LocationPermissionState.denied
        ..afterRequest = LocationPermissionState.denied;
      await openApp(tester, f);
      await _tapTripsTab(tester);
      await tester.tap(find.text(P.startTrip));
      await tester.pumpAndSettle();
      expect(find.text(P.noContactsTitle), findsNothing);
      expect(f.trips.active!.status, TripStatus.inProgress);
      expect(find.text(P.gpsDenied), findsOneWidget, reason: 'banner, not a blocker');
      expect(find.byKey(sliderArriveKey), findsOneWidget);
    });

    testWidgets('start failure is reported and the trip stays scheduled', (tester) async {
      final f = _withContacts(Fakes()..trips.active = sampleTrip());
      f.trips.transitionFailure = const AppFailure('GWM_INVALID_TRIP_TRANSITION');
      await openApp(tester, f);
      await _tapTripsTab(tester);
      await tester.tap(find.text(P.startTrip));
      await tester.pumpAndSettle();
      expect(find.text('ตอนนี้เปลี่ยนสถานะทริปนี้ไม่ได้'), findsOneWidget);
      expect(f.trips.active!.status, TripStatus.scheduled);
    });

    testWidgets('cancel: dialog tells how many partners are notified; confirming cancels', (tester) async {
      final f = Fakes()
        ..trips.active = sampleTrip()
        ..matches.matches = [acceptedMatch()];
      await openApp(tester, f);
      await goTo(tester, Routes.tripDetail('trip-1'));
      await tester.tap(find.text(P.cancelTrip));
      await tester.pumpAndSettle();
      expect(find.text('คู่ของคุณ 1 คนจะได้รับข้อความแจ้งว่าทริปถูกยกเลิก'), findsOneWidget);

      await tester.tap(find.text(P.cancelTripKeep));
      await tester.pumpAndSettle();
      expect(f.trips.active!.status, TripStatus.scheduled);

      await tester.tap(find.text(P.cancelTrip));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, P.cancelTrip));
      await tester.pumpAndSettle();
      expect(f.trips.active, isNull);
      expect(f.trips.finished.single.status, TripStatus.cancelled);
    });

    testWidgets('arrive: confirm, trip completes, warm arrived screen', (tester) async {
      final f = _withContacts(Fakes()..trips.active = runningTrip());
      await openApp(tester, f);
      await goTo(tester, Routes.tripActive('trip-1'));

      // Round 6: no confirm dialog, the slider confirms the routine status change.
      await dragSlider(tester, sliderArriveKey);
      expect(find.text(P.arrivedConfirmTitle), findsNothing);

      expect(find.text(R6.arrivedDest), findsOneWidget);
      expect(f.trips.finished.single.status, TripStatus.completed);
      expect(f.trips.active, isNull);
      await tester.tap(find.text(P.backHome));
      await tester.pumpAndSettle();
      expect(find.text(S.homeGreeting), findsOneWidget);
    });

    testWidgets('arrive failure keeps the trip in progress with a retry message', (tester) async {
      final f = Fakes()..trips.active = runningTrip();
      await openApp(tester, f);
      await goTo(tester, Routes.tripActive('trip-1'));
      f.trips.transitionFailure = const AppFailure('GWM_INVALID_TRIP_TRANSITION');
      await dragSlider(tester, sliderArriveKey);
      expect(find.text(P.arriveFailed), findsOneWidget);
      expect(f.trips.active!.status, TripStatus.inProgress);
      // back to idle: it can be tried again
      f.trips.transitionFailure = null;
      await dragSlider(tester, sliderArriveKey);
      expect(f.trips.finished.single.status, TripStatus.completed);
    });

    testWidgets('arrive while offline: the slider says it is not saved and the trip is not finished', (tester) async {
      final f = Fakes()..trips.active = runningTrip();
      await openApp(tester, f);
      await goTo(tester, Routes.tripActive('trip-1'));
      f.trips.transitionFailure = const AppFailure(FailureCode.networkOffline, retryable: true);
      await dragSlider(tester, sliderArriveKey);
      expect(find.text(R6.sliderOfflineError), findsOneWidget);
      expect(f.trips.active!.status, TripStatus.inProgress);
    });

    testWidgets('finished trip can be deleted from its detail page', (tester) async {
      final f = Fakes();
      f.trips.finished.add(_finished('h1', TripStatus.completed, 'ก'));
      await openApp(tester, f);
      await goTo(tester, Routes.tripDetail('h1'));
      await tester.tap(find.text(P.deleteTrip));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, P.deleteTrip));
      await tester.pumpAndSettle();
      expect(f.trips.deleted, ['h1']);
    });
  });

  group('active trip: tracking, sharing, arrival prompt', () {
    LocationFix fixAt(LatLng p) => LocationFix(point: p, at: DateTime.now(), accuracyM: 8);

    testWidgets('near the destination the slider turns green (presentation only); far away it does not',
        (tester) async {
      final f = Fakes()..trips.active = runningTrip();
      f.location.state = LocationPermissionState.granted;
      await openApp(tester, f);
      await goTo(tester, Routes.tripActive('trip-1'));
      expect(find.byKey(const Key('slider-near')), findsNothing);

      final dest = f.trips.active!.dest;
      f.location.fixes.add(fixAt(LatLng(dest.latitude + 0.05, dest.longitude)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('slider-near')), findsNothing);

      f.location.fixes.add(fixAt(LatLng(dest.latitude + 0.001, dest.longitude))); // ~111 m
      await tester.pumpAndSettle();
      expect(find.text(R6.sliderNearDest), findsOneWidget);
      // the highlight never gates the action: the slider is still the same enabled slider
      expect(find.byKey(const Key('slider-disabled-reason')), findsNothing);
    });

    testWidgets('positions go to the server only with an accepted, open match, throttled to one per 15 s',
        (tester) async {
      final f = Fakes()
        ..trips.active = runningTrip()
        ..matches.matches = [acceptedMatch()];
      f.location.state = LocationPermissionState.granted;
      await openApp(tester, f);
      await goTo(tester, Routes.tripActive('trip-1'));
      await sheetTo(tester, SheetLevel.half);
      expect(find.text(P.trackingSharing), findsOneWidget);

      f.location.fixes.add(fixAt(const LatLng(13.75, 100.53)));
      await tester.pumpAndSettle();
      f.location.fixes.add(fixAt(const LatLng(13.751, 100.531)));
      await tester.pumpAndSettle();
      expect(f.live.pushes, hasLength(1), reason: 'second fix inside the 15 s window is not sent');
      expect(f.live.pushes.single.$1, 'trip-1');
    });

    testWidgets('no partner: positions are used locally but never sent', (tester) async {
      final f = Fakes()..trips.active = runningTrip();
      f.location.state = LocationPermissionState.granted;
      await openApp(tester, f);
      await goTo(tester, Routes.tripActive('trip-1'));
      await sheetTo(tester, SheetLevel.half);
      expect(find.text(P.trackingNoPartner), findsOneWidget);
      f.location.fixes.add(fixAt(const LatLng(13.75, 100.53)));
      await tester.pumpAndSettle();
      expect(f.live.pushes, isEmpty);
      expect(containerOf(tester).read(lastFixProvider), isNotNull);
    });

    testWidgets('a block stops sharing: no more pushes after chat_state turns blocked', (tester) async {
      final f = Fakes()
        ..trips.active = runningTrip()
        ..matches.matches = [acceptedMatch()];
      f.location.state = LocationPermissionState.granted;
      await openApp(tester, f);
      await goTo(tester, Routes.tripActive('trip-1'));
      await sheetTo(tester, SheetLevel.half);
      f.location.fixes.add(fixAt(const LatLng(13.75, 100.53)));
      await tester.pumpAndSettle();
      expect(f.live.pushes, hasLength(1));

      f.chat.chatState = ChatState.blocked;
      containerOf(tester).invalidate(sharingPartnersProvider);
      await tester.pumpAndSettle();
      expect(find.text(P.trackingNoPartner), findsOneWidget);
      f.location.fixes.add(fixAt(const LatLng(13.76, 100.54)));
      await tester.pumpAndSettle();
      expect(f.live.pushes, hasLength(1), reason: 'nothing sent after the block');
    });

    testWidgets('ending the trip stops tracking and sharing', (tester) async {
      final f = _withContacts(Fakes()
        ..trips.active = runningTrip()
        ..matches.matches = [acceptedMatch()]);
      f.location.state = LocationPermissionState.granted;
      await openApp(tester, f);
      await goTo(tester, Routes.tripActive('trip-1'));
      f.location.fixes.add(fixAt(const LatLng(13.75, 100.53)));
      await tester.pumpAndSettle();
      expect(f.live.pushes, hasLength(1));

      await dragSlider(tester, sliderArriveKey);
      expect(f.trips.active, isNull);

      f.location.fixes.add(fixAt(const LatLng(13.9, 100.6)));
      await tester.pumpAndSettle();
      expect(f.live.pushes, hasLength(1));
      expect(containerOf(tester).read(tripTrackingProvider).status, TrackStatus.idle);
    });

    testWidgets('withdrawn location consent: no tracking, banner shown, trip still usable', (tester) async {
      final f = Fakes()
        ..trips.active = runningTrip()
        ..matches.matches = [acceptedMatch()];
      f.consent.locationGranted = false;
      f.location.state = LocationPermissionState.granted;
      await openApp(tester, f);
      await goTo(tester, Routes.tripActive('trip-1'));
      f.location.fixes.add(fixAt(const LatLng(13.75, 100.53)));
      await tester.pumpAndSettle();
      expect(f.live.pushes, isEmpty);
      expect(find.text(P.gpsDenied), findsOneWidget);
    });

    testWidgets('partner live view: position and time, or a clear "not visible" note', (tester) async {
      final f = Fakes()
        ..trips.active = runningTrip()
        ..matches.matches = [acceptedMatch()];
      f.location.state = LocationPermissionState.granted;
      await openApp(tester, f);
      await goTo(tester, Routes.tripActive('trip-1'));
      expect(find.text(R5.liveNoPeer('นุ่น')), findsOneWidget);

      f.live.partner = PartnerLocation(point: const LatLng(13.76, 100.53), recordedAt: DateTime(2026, 1, 1, 18, 5));
      containerOf(tester).invalidate(partnerLocationProvider('m1'));
      await tester.pumpAndSettle();
      expect(find.textContaining('18:05'), findsWidgets);
    });

    testWidgets('overdue prompt offers "arrived" and SOS', (tester) async {
      final late = sampleTrip().copyWith(
        status: TripStatus.inProgress,
        startedAt: DateTime.now().subtract(const Duration(hours: 2)),
      );
      final f = Fakes()..trips.active = late;
      f.location.state = LocationPermissionState.granted;
      await openApp(tester, f);
      await goTo(tester, Routes.tripActive('trip-1'));
      expect(find.text(P.arrivalOverdue), findsOneWidget);
      expect(find.widgetWithText(FilledButton, P.sos), findsWidgets);
    });

    testWidgets('banner on other tabs takes you back, with SOS two taps away', (tester) async {
      final f = Fakes()..trips.active = runningTrip();
      f.location.state = LocationPermissionState.granted;
      await openApp(tester, f);
      expect(find.text(P.bannerActiveTrip), findsOneWidget);
      await tester.tap(find.text(P.sos).first);
      await tester.pumpAndSettle();
      expect(find.text(P.sosTitle), findsOneWidget);
    });
  });
}
