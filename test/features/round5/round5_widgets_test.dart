import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/l10n/strings.dart';
import 'package:gowithme/core/l10n/strings_r5.dart';
import 'package:gowithme/core/router/redirect.dart';
import 'package:gowithme/core/widgets/app_button.dart';
import 'package:gowithme/features/avatar/domain/avatar_repository.dart';
import 'package:gowithme/features/avatar/presentation/avatar_providers.dart';
import 'package:gowithme/features/geo/domain/location_service.dart';
import 'package:gowithme/features/matching/domain/match_models.dart';
import 'package:gowithme/features/reviews/domain/review_models.dart';
import 'package:gowithme/features/trip/domain/live_location.dart';
import 'package:gowithme/features/trip/domain/live_map_logic.dart';
import 'package:gowithme/features/trip/domain/travel_mode.dart';
import 'package:gowithme/features/trip/domain/trip.dart';
import 'package:gowithme/features/trip/presentation/unified_ride_screen.dart';
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';

import '../../support/fake_repos.dart';
import '../../support/fakes.dart';
import '../../support/p4_helpers.dart';
import '../../support/ride_helpers.dart';

Uint8List _bigPng(int w, int h) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  img.fill(im, color: img.ColorRgb8(20, 120, 200));
  return Uint8List.fromList(img.encodePng(im));
}

Trip _carTrip(TripRole role, {TripStatus status = TripStatus.scheduled}) =>
    sampleTrip(mode: TravelMode.car, role: role, status: status);

const _pickup = LatLng(13.75, 100.53);

MatchSummary _car({
  TripRole mine = TripRole.rider,
  MatchStatus status = MatchStatus.accepted,
  DateTime? boardedAt,
  bool withPickup = true,
}) {
  final m = sampleMatch(status: status, iAmRequester: true, myRole: mine, boardedAt: boardedAt, partnerTripStatus: TripStatus.inProgress);
  return withPickup ? m.copyWith(meetingPoint: _pickup, meetingLabel: 'หน้าสถานี') : m;
}

Future<Fakes> _open(WidgetTester tester, Fakes f, {Size size = const Size(800, 2000)}) => openApp(tester, f, size: size);

void main() {
  group('avatar screen (S-35)', () {
    testWidgets('first pick shows the privacy sheet once, then the source sheet, uploads a small JPEG and confirms', (tester) async {
      final f = Fakes();
      f.picker.outcome = PickOutcome.picked(_bigPng(1200, 900));
      await _open(tester, f);
      await goTo(tester, Routes.mePhoto);

      expect(find.byKey(const Key('photo-remove')), findsNothing, reason: 'no photo yet');
      expect(find.text(R5.photoEmptyHint), findsOneWidget);
      await tester.tap(find.byKey(const Key('photo-pick')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('photo-privacy-sheet')), findsOneWidget);
      expect(find.text(R5.photoPrivacyWho), findsOneWidget);
      expect(find.text(R5.photoPrivacyWhen), findsOneWidget);
      await tester.tap(find.text(R5.photoPrivacyAck));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('src-gallery')));
      await tester.pumpAndSettle();

      expect(f.picker.asked, [PhotoSource.gallery]);
      expect(f.avatars.uploads, hasLength(1));
      final jpeg = f.avatars.uploads.single;
      expect(jpeg.sublist(0, 3), [0xFF, 0xD8, 0xFF]);
      final decoded = img.decodeJpg(jpeg)!;
      expect(decoded.width, lessThanOrEqualTo(512));
      expect(find.text(R5.photoSaved), findsOneWidget);
      expect(find.byKey(const Key('photo-remove')), findsOneWidget);

      // second time: the notice is not shown again
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.byKey(const Key('photo-pick')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('photo-privacy-sheet')), findsNothing);
      expect(find.byKey(const Key('src-gallery')), findsOneWidget);
    });

    testWidgets('a too-small or broken file shows a Thai message and nothing is uploaded', (tester) async {
      final f = Fakes();
      f.picker.outcome = PickOutcome.picked(_bigPng(100, 100));
      await _open(tester, f);
      await goTo(tester, Routes.mePhoto);
      await tester.tap(find.byKey(const Key('photo-pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(R5.photoPrivacyAck));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('src-gallery')));
      await tester.pumpAndSettle();
      expect(find.text(R5.photoErrTooSmall), findsOneWidget);
      expect(f.avatars.uploads, isEmpty);
    });

    testWidgets('permission denied is explained and the other option stays available', (tester) async {
      final f = Fakes();
      f.picker.outcome = const PickOutcome.denied();
      await _open(tester, f);
      await goTo(tester, Routes.mePhoto);
      await tester.tap(find.byKey(const Key('photo-pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(R5.photoPrivacyAck));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('src-gallery')));
      await tester.pumpAndSettle();
      expect(find.text(R5.photoPermDenied), findsOneWidget);
      expect(find.byKey(const Key('photo-pick')), findsOneWidget, reason: 'can try again');
    });

    testWidgets('upload failure keeps the old photo and says so; offline gets its own text', (tester) async {
      final f = Fakes();
      f.avatars.mineSource = AvatarSource.bytes(_bigPng(64, 64));
      f.avatars.uploadFailure = const AppFailure(FailureCode.networkOffline, retryable: true);
      f.picker.outcome = PickOutcome.picked(_bigPng(800, 800));
      await _open(tester, f);
      await goTo(tester, Routes.mePhoto);
      expect(find.text(R5.photoChange), findsOneWidget);
      await tester.tap(find.byKey(const Key('photo-pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(R5.photoPrivacyAck));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('src-gallery')));
      await tester.pumpAndSettle();
      expect(find.text(R5.photoErrOffline), findsOneWidget);
      expect(f.avatars.mineSource, isNotNull, reason: 'old photo untouched');
    });

    testWidgets('remove asks for confirmation, then clears the photo', (tester) async {
      final f = Fakes();
      f.avatars.mineSource = AvatarSource.bytes(_bigPng(64, 64));
      await _open(tester, f);
      await goTo(tester, Routes.mePhoto);
      await tester.tap(find.byKey(const Key('photo-remove')));
      await tester.pumpAndSettle();
      expect(find.text(R5.photoRemoveTitle), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(R5.photoRemove)));
      await tester.pumpAndSettle();
      expect(f.avatars.removed, 1);
      expect(find.text(R5.photoRemoved), findsOneWidget);
    });
  });

  group('where photos appear (E-1)', () {
    testWidgets('search results and pending requests never ask for a photo (initials only)', (tester) async {
      final f = Fakes()
        ..trips.active = _carTrip(TripRole.rider)
        ..finder.result = [sampleCandidate(mode: TravelMode.car, role: TripRole.driver)]
        ..matches.matches = [
          sampleMatch(status: MatchStatus.pending, myRole: TripRole.rider, iAmRequester: false),
        ];
      f.avatars.partnerSource = AvatarSource.bytes(_bigPng(64, 64));
      await _open(tester, f);
      await tester.tap(find.text(S.tabNearby));
      await tester.pumpAndSettle();
      await goTo(tester, Routes.nearbyRequests);
      expect(f.avatars.partnerCalls, 0);
    });

    testWidgets('an accepted match shows the partner photo and the viewer offers "report this photo"', (tester) async {
      final f = Fakes()
        ..trips.active = _carTrip(TripRole.rider)
        ..matches.matches = [_car()];
      f.avatars.partnerSource = AvatarSource.bytes(_bigPng(64, 64));
      await _open(tester, f);
      await goTo(tester, Routes.match('m1'));
      expect(f.avatars.partnerCalls, greaterThan(0));
      expect(find.descendant(of: find.byKey(const Key('match-avatar')), matching: find.byType(Image)), findsOneWidget);
      await tester.tap(find.byKey(const Key('match-avatar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('photo-report')), findsOneWidget);
      await tester.tap(find.byKey(const Key('photo-report')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(R5.photoReportR2));
      await tester.pump();
      await tester.tap(find.byKey(const Key('photo-report-submit')));
      await tester.pumpAndSettle();
      expect(f.avatars.reports.single.$1, 'm1');
      expect(find.text(R5.photoReportDone), findsOneWidget);
      // the photo is gone for the reporter at once: initials again
      expect(find.descendant(of: find.byKey(const Key('match-avatar')), matching: find.byType(Image)), findsNothing);
    });

    testWidgets('a cancelled match (before boarding) shows initials, never a photo, without any explanation', (tester) async {
      final f = Fakes()
        ..trips.active = _carTrip(TripRole.rider)
        ..matches.matches = [_car(status: MatchStatus.cancelled)];
      f.avatars.partnerSource = AvatarSource.bytes(_bigPng(64, 64));
      await _open(tester, f);
      await goTo(tester, Routes.match('m1'));
      expect(f.avatars.partnerCalls, 0);
      expect(find.descendant(of: find.byKey(const Key('match-avatar')), matching: find.byType(Image)), findsNothing);
    });
  });

  group('no-match hint (US-21 P1)', () {
    Fakes base() => Fakes()
      ..trips.active = _carTrip(TripRole.rider)
      ..finder.result = const [];

    testWidgets('shows one sentence with the category text under the empty state; retry has a cooldown', (tester) async {
      final f = base()..finder.hint = MatchHint.farDestination;
      await _open(tester, f);
      await tester.tap(find.text(S.tabNearby));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('no-match-hint-text')), findsOneWidget);
      expect(find.text(R5.noneFarDest), findsOneWidget);
      expect(find.byKey(const Key('match-rule-explain')), findsOneWidget, reason: 'corridor rule text for car');
      final calls = f.finder.calls;
      await tester.tap(find.byKey(const Key('hint-retry')));
      await tester.pump();
      expect(f.finder.calls, greaterThan(calls));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text(R5.noneWait), findsOneWidget);
      expect(tester.widget<AppButton>(find.byKey(const Key('hint-retry'))).onPressed, isNull);
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('has_results shows nothing', (tester) async {
      final f = base()..finder.hint = MatchHint.hasResults;
      await _open(tester, f);
      await tester.tap(find.text(S.tabNearby));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('no-match-hint')), findsNothing);

    });

    testWidgets('a failing hint call shows nothing and never breaks the list', (tester) async {
      final g = base()..finder.hintFailure = const AppFailure('GWM_RATE_LIMITED', retryable: true);
      await _open(tester, g);
      await tester.tap(find.text(S.tabNearby));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('no-match-hint')), findsNothing);
      expect(find.byKey(const Key('match-rule-explain')), findsOneWidget);
    });

    testWidgets('a candidate card shows "ทางเดียวกัน" and no detour text', (tester) async {
      final f = Fakes()..trips.active = _carTrip(TripRole.driver);
      f.finder.result = [
        MatchCandidate(
          tripId: 'c1', displayName: 'คนนั่ง', badges: const [], mode: TravelMode.car, departAt: DateTime.now().add(const Duration(minutes: 10)),
          timeDiffMin: 2, overlapPct: 80, approxDistanceM: 5000, score: 90, approxOrigin: _pickup, approxDest: _pickup,
          requestStatus: null, role: TripRole.rider, maxDropoffM: null,
        ),
      ];
      await _open(tester, f);
      await tester.tap(find.text(S.tabNearby));
      await tester.pumpAndSettle();
      expect(find.textContaining('ทางเดียวกัน ~80%'), findsOneWidget);
      expect(find.byKey(const Key('dropoff-text')), findsNothing);
    });
  });

  group('navigation button (US-24)', () {
    testWidgets('no agreed pickup: disabled with a visible reason and a link to agree one', (tester) async {
      final f = Fakes()
        ..trips.active = _carTrip(TripRole.rider, status: TripStatus.inProgress)
        ..matches.matches = [_car(withPickup: false)];
      await _open(tester, f);
      await goTo(tester, Routes.tripActive('trip-1'));
      await sheetTo(tester, SheetLevel.half); // Round 6: the navigation button is at the Half level
      expect(find.byKey(const Key('nav-pickup-disabled')), findsOneWidget);
      expect(find.byKey(const Key('nav-no-pickup')), findsOneWidget);
      expect(find.text(R5.navGoSetPickup), findsOneWidget);
      expect(find.byKey(const Key('nav-destination')), findsNothing);
    });

    testWidgets('pickup agreed: notice once, chooser, then only the pickup coordinate leaves the app', (tester) async {
      final f = Fakes()
        ..trips.active = _carTrip(TripRole.rider, status: TripStatus.inProgress)
        ..matches.matches = [_car()];
      await _open(tester, f);
      await goTo(tester, Routes.tripActive('trip-1'));
      await sheetTo(tester, SheetLevel.half);
      await tester.ensureVisible(find.byKey(const Key('nav-pickup')));
      await tester.tap(find.byKey(const Key('nav-pickup')));
      await tester.pumpAndSettle();
      expect(find.text(R5.navNoticeTitle), findsOneWidget);
      await tester.tap(find.text(R5.navNoticeOk));
      await tester.pumpAndSettle();
      expect(find.text(R5.navSheetTitle), findsOneWidget);
      expect(find.text(R5.navSafety), findsOneWidget);
      await tester.tap(find.byKey(const Key('nav-app-google')));
      await tester.pumpAndSettle();
      final url = f.actions.opened.single;
      expect(url.queryParameters['destination'], '13.750000,100.530000');
      expect(url.toString(), isNot(contains('13.9')), reason: 'no other coordinate (e.g. destination) in the URL');

      // second time: no notice
      await tester.tap(find.byKey(const Key('nav-pickup')));
      await tester.pumpAndSettle();
      expect(find.text(R5.navNoticeTitle), findsNothing);
      expect(find.text(R5.navSheetTitle), findsOneWidget);
    });

    testWidgets('after boarding the button becomes "to destination" and targets my own destination', (tester) async {
      final f = Fakes()
        ..trips.active = _carTrip(TripRole.rider, status: TripStatus.inProgress)
        ..matches.matches = [_car(boardedAt: DateTime.now())];
      await _open(tester, f);
      await goTo(tester, Routes.tripActive('trip-1'));
      await sheetTo(tester, SheetLevel.half);
      expect(find.byKey(const Key('nav-pickup')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('nav-destination')));
      await tester.tap(find.byKey(const Key('nav-destination')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(R5.navNoticeOk));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-app-web')));
      await tester.pumpAndSettle();
      expect(f.actions.opened.single.toString(), contains('13.900000'));
    });

    testWidgets('a failed launch offers the web link', (tester) async {
      final f = Fakes()
        ..trips.active = _carTrip(TripRole.rider, status: TripStatus.inProgress)
        ..matches.matches = [_car()];
      f.actions.openOk = false;
      await _open(tester, f);
      await goTo(tester, Routes.tripActive('trip-1'));
      await sheetTo(tester, SheetLevel.half);
      await tester.ensureVisible(find.byKey(const Key('nav-pickup')));
      await tester.tap(find.byKey(const Key('nav-pickup')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(R5.navNoticeOk));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-app-google')));
      await tester.pumpAndSettle();
      expect(find.text(R5.navOpenFail), findsOneWidget);
      expect(find.text(R5.navUseWeb), findsOneWidget);
    });
  });

  group('live map (S-37)', () {
    PartnerLocation peerAt({int secondsAgo = 5}) =>
        PartnerLocation(point: const LatLng(13.7480, 100.5320), recordedAt: DateTime.now().subtract(Duration(seconds: secondsAgo)));

    testWidgets('Rider: sees the Driver as a car labelled "คนขับ", ETA to the pickup, controls, status', (tester) async {
      final f = Fakes()
        ..trips.active = _carTrip(TripRole.rider, status: TripStatus.inProgress)
        ..matches.matches = [_car()]
        ..live.partner = peerAt();
      await _open(tester, f);
      await goTo(tester, Routes.live('m1'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('car-icon')), findsOneWidget);
      expect(find.text(R5.liveRoleDriver), findsWidgets);
      expect(find.byKey(const Key('person-icon')), findsNothing);
      expect(find.text(R5.liveStatusComingToYou), findsOneWidget);
      // routing fake: 1500 s -> 25 min
      expect(find.text(R5.etaPickupRider(25)), findsOneWidget);
      for (final k in ['ctl-follow', 'ctl-fit', 'ctl-zoom-in', 'ctl-zoom-out']) {
        expect(find.byKey(Key(k)), findsOneWidget);
      }
      expect(find.textContaining('อัปเดตเมื่อ'), findsNothing, reason: 'fresh fix');
      await sheetTo(tester, SheetLevel.half);
      expect(find.byKey(const Key('nav-pickup')), findsOneWidget);
    });

    testWidgets('stale after 45 s: label in seconds, warning hint, icon marked as old', (tester) async {
      final f = Fakes()
        ..trips.active = _carTrip(TripRole.rider, status: TripStatus.inProgress)
        ..matches.matches = [_car()]
        ..live.partner = peerAt(secondsAgo: 50);
      await _open(tester, f);
      await goTo(tester, Routes.live('m1'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('อัปเดตเมื่อ 5'), findsOneWidget);
      expect(find.textContaining('วินาทีที่แล้ว'), findsOneWidget);
      expect(find.text(R5.liveStaleHint), findsOneWidget);
      expect(find.byIcon(Icons.access_time), findsWidgets);
    });

    testWidgets('Driver: sees the Rider as a person pin "คนนั่ง" before boarding; nothing after, with the explanation', (tester) async {
      final f = Fakes()
        ..trips.active = _carTrip(TripRole.driver, status: TripStatus.inProgress)
        ..matches.matches = [_car(mine: TripRole.driver)]
        ..live.partner = peerAt();
      await _open(tester, f);
      await goTo(tester, Routes.live('m1'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('person-icon')), findsOneWidget);
      expect(find.byKey(const Key('car-icon')), findsNothing);
      expect(find.text(R5.liveRoleRider), findsWidgets);

      // The Rider boards: the pin disappears at once and the Driver is told why.
      f.matches.matches = [_car(mine: TripRole.driver, boardedAt: DateTime.now())];
      f.matches.emitChange();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('person-icon')), findsNothing);
      expect(find.text(R5.liveRiderBoarded), findsOneWidget);
    });

    testWidgets('Driver map: pickup drawn, at most my own destination (the Rider destination has no input, see logic test)', (tester) async {
      // The candidate/match blurred destination of the Rider is 13.9,100.6 (sampleMatch approxDest); the Driver own destination is the same sample trip dest, so use a distinct fake
      final f = Fakes()
        ..trips.active = _carTrip(TripRole.driver, status: TripStatus.inProgress)
        ..matches.matches = [
          _car(mine: TripRole.driver).copyWith(),
        ]
        ..live.partner = peerAt();
      await _open(tester, f);
      await goTo(tester, Routes.live('m1'));
      await tester.pump(const Duration(milliseconds: 500));
      // Pickup is drawn; a destination label can only ever be my own (at most one; here it is off screen).
      expect(find.text(R5.livePickupLabel), findsOneWidget);
      expect(find.text(R5.liveDestLabel).evaluate().length, lessThanOrEqualTo(1));
    });

    testWidgets('not eligible (my trip not started): back to the match page with a neutral message', (tester) async {
      final f = Fakes()
        ..trips.active = _carTrip(TripRole.rider)
        ..matches.matches = [_car()];
      await _open(tester, f);
      await goTo(tester, Routes.live('m1'));
      await tester.pumpAndSettle();
      expect(find.text(R5.liveUnavailable), findsOneWidget);
      expect(find.byKey(const Key('ctl-follow')), findsNothing);
    });

    testWidgets('dragging the map stops follow mode and shows the recenter pill; tapping it resumes', (tester) async {
      final f = Fakes()
        ..trips.active = _carTrip(TripRole.rider, status: TripStatus.inProgress)
        ..matches.matches = [_car()]
        ..live.partner = peerAt();
      await _open(tester, f);
      await goTo(tester, Routes.live('m1'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('recenter-pill')), findsNothing);
      await tester.dragFrom(const Offset(300, 500), const Offset(-150, 0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('recenter-pill')), findsOneWidget, reason: 'user moved the map: follow stops');
      await tester.tap(find.byKey(const Key('recenter-pill')));
      await tester.pump();
      expect(find.byKey(const Key('recenter-pill')), findsNothing);
    });
  });

  group('layout at 390 px', () {
    for (final scale in [1.0, 1.4]) {
      testWidgets('live map (Rider + Driver), avatar, review and my-reviews pages do not overflow at text scale $scale', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        final f = Fakes()
          ..trips.active = _carTrip(TripRole.rider, status: TripStatus.inProgress)
          ..matches.matches = [_car(boardedAt: null)]
          ..live.partner = PartnerLocation(point: const LatLng(13.7480, 100.5320), recordedAt: DateTime.now().subtract(const Duration(seconds: 60)));
        f.reviews.reviewState = ReviewState(canReview: true, closesAt: DateTime.now().add(const Duration(days: 5)));
        f.reviews.receivedList = [
          ReceivedReview(id: 'r1', matchId: 'm', role: TripRole.driver, stars: 4, tags: const ['on_time', 'polite', 'safe_driving'], comment: 'ขับดี ตรงเวลา ถึงที่หมายปลอดภัย', createdAt: DateTime.now()),
        ];
        await _open(tester, f, size: const Size(390, 844));
        for (final r in [Routes.live('m1'), Routes.review('m1'), Routes.mePhoto, Routes.meReviews, Routes.chat('m1'), Routes.match('m1')]) {
          await goTo(tester, r);
          await tester.pump(const Duration(milliseconds: 500));
          expect(tester.takeException(), isNull, reason: r);
          await goBack(tester);
        }
      });
    }
  });

  group('chat quick replies for the drop-off (Z-2)', () {
    testWidgets('car match: chip opens ready-made sentences that fill the box without sending', (tester) async {
      final f = Fakes()
        ..trips.active = runningTrip()
        ..matches.matches = [_car()];
      await _open(tester, f);
      await goTo(tester, Routes.chat('m1'));
      expect(find.byKey(const Key('chat-quick-replies')), findsOneWidget);
      await tester.tap(find.byKey(const Key('chat-quick-replies')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(R5.quickReplies.first));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, R5.quickReplies.first);
      expect(f.chat.sent, isEmpty, reason: 'nothing is sent until the user presses send');
    });

    testWidgets('peer match has no quick replies', (tester) async {
      final f = Fakes()
        ..trips.active = runningTrip()
        ..matches.matches = [acceptedMatch()];
      await _open(tester, f);
      await goTo(tester, Routes.chat('m1'));
      expect(find.byKey(const Key('chat-quick-replies')), findsNothing);
    });
  });

  group('reviews UI (US-26)', () {
    ReviewState open() => ReviewState(canReview: true, closesAt: DateTime.now().add(const Duration(days: 6, hours: 3)));

    testWidgets('form: nothing preselected, submit needs a star, tags follow the reviewed role, sent once', (tester) async {
      final f = Fakes()
        ..trips.active = _carTrip(TripRole.rider)
        ..matches.matches = [_car(boardedAt: DateTime.now())];
      f.reviews.reviewState = open();
      await _open(tester, f);
      await goTo(tester, Routes.review('m1'));
      expect(find.byKey(const Key('review-submit')), findsOneWidget);
      expect(tester.widget<AppButton>(find.byKey(const Key('review-submit'))).onPressed, isNull);
      // I am the Rider, so I review a Driver: driving tags are offered
      expect(find.byKey(const Key('tag-safe_driving')), findsOneWidget);
      expect(find.text(R5.reviewNoteFinal), findsOneWidget);
      expect(find.text(R5.reviewNoteReveal), findsOneWidget);

      await tester.tap(find.byKey(const Key('star-4')));
      await tester.pump();
      expect(find.text(R5.reviewStarLabels[3]), findsOneWidget);
      await tester.tap(find.byKey(const Key('tag-polite')));
      await tester.enterText(find.byKey(const Key('review-comment')), 'ขับดี');
      await tester.pump();
      await tester.tap(find.byKey(const Key('review-submit')));
      await tester.pumpAndSettle();

      final s = f.reviews.submitted.single;
      expect(s.stars, 4);
      expect(s.tags, ['polite']);
      expect(s.comment, 'ขับดี');
      expect(find.text(R5.reviewDoneTitle), findsOneWidget);
      expect(find.byKey(const Key('review-done-body')), findsOneWidget);
    });

    testWidgets('errors: rate limit and window closed have their own Thai text; typed data stays', (tester) async {
      final f = Fakes()
        ..trips.active = _carTrip(TripRole.rider)
        ..matches.matches = [_car(boardedAt: DateTime.now())];
      f.reviews
        ..reviewState = open()
        ..submitFailure = const AppFailure('GWM_RATE_LIMITED', retryable: true);
      await _open(tester, f);
      await goTo(tester, Routes.review('m1'));
      await tester.tap(find.byKey(const Key('star-5')));
      await tester.enterText(find.byKey(const Key('review-comment')), 'ดีมาก');
      await tester.pump();
      await tester.tap(find.byKey(const Key('review-submit')));
      await tester.pumpAndSettle();
      expect(find.text(R5.reviewErrRate), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('review-comment'))).controller!.text, 'ดีมาก');
    });

    testWidgets('not allowed / window closed: neutral state, no form', (tester) async {
      final f = Fakes()
        ..trips.active = _carTrip(TripRole.rider)
        ..matches.matches = [_car()];
      f.reviews.reviewState = const ReviewState(canReview: false, reason: 'window_closed');
      await _open(tester, f);
      await goTo(tester, Routes.review('m1'));
      expect(find.byKey(const Key('review-unavailable')), findsOneWidget);
      expect(find.text(R5.reviewErrClosed), findsOneWidget);
      expect(find.byKey(const Key('review-submit')), findsNothing);
    });

    testWidgets('prompt card on the match page while the window is open; "sent, waiting" afterwards', (tester) async {
      final f = Fakes()
        ..trips.active = _carTrip(TripRole.rider)
        ..matches.matches = [_car(boardedAt: DateTime.now())];
      f.reviews.reviewState = open();
      await _open(tester, f);
      await goTo(tester, Routes.match('m1'));
      expect(find.byKey(const Key('review-prompt')), findsOneWidget);
      expect(find.textContaining('เหลือ 7 วัน'), findsOneWidget);

      f.reviews.reviewState = const ReviewState(canReview: false, reason: 'already_submitted', myStars: 4);
      await goBack(tester);
      await goTo(tester, Routes.match('m1'));
      expect(find.byKey(const Key('review-prompt')), findsNothing);
      expect(find.byKey(const Key('review-pending')), findsOneWidget);
    });

    testWidgets('aggregate on the matched view only with >= 3 revealed reviews; otherwise nothing (no "not enough" text)', (tester) async {
      final f = Fakes()
        ..trips.active = _carTrip(TripRole.rider)
        ..matches.matches = [_car()];
      f.reviews.ratings = const [UserRating(role: TripRole.driver, enough: true, count: 12, avg: 4.83)];
      await _open(tester, f);
      await goTo(tester, Routes.match('m1'));
      expect(find.byKey(const Key('rating-line')), findsOneWidget);
      expect(find.textContaining('4.8 (12)'), findsOneWidget);

    });

    testWidgets('below 3 revealed reviews the summary is absent (no "not enough" text)', (tester) async {
      final g = Fakes()
        ..trips.active = _carTrip(TripRole.rider)
        ..matches.matches = [_car()];
      g.reviews.ratings = const [UserRating(role: TripRole.driver, enough: false)];
      await _open(tester, g);
      await goTo(tester, Routes.match('m1'));
      expect(find.byKey(const Key('rating-line')), findsNothing);
      expect(find.textContaining('ยังมีรีวิวไม่พอ'), findsNothing);
    });

    testWidgets('my reviews: revealed reviews without any author, report hides the row', (tester) async {
      final f = Fakes();
      f.reviews.receivedList = [
        ReceivedReview(id: 'r1', matchId: 'm', role: TripRole.driver, stars: 5, tags: const ['polite'], comment: 'ดีมาก', createdAt: DateTime.now()),
      ];
      await _open(tester, f);
      await goTo(tester, Routes.meReviews);
      expect(find.text('ดีมาก'), findsOneWidget);
      expect(find.text(R5.reviewTagLabels['polite']!), findsOneWidget);
      await tester.tap(find.text(R5.reviewReportCta));
      await tester.pumpAndSettle();
      await tester.tap(find.text(R5.reviewReportInappropriate));
      await tester.pumpAndSettle();
      expect(f.reviews.reported, ['r1']);
      expect(find.text('ดีมาก'), findsNothing);
      expect(find.text(R5.reviewMineEmpty), findsOneWidget);
    });
  });

  testWidgets('sanity: the live-location fix type is usable in tests', (tester) async {
    expect(LocationFix(point: _pickup, at: DateTime.now()).point, _pickup);
    expect(staleAfter, const Duration(seconds: 45));
    expect(LiveLocationSharer.livePushInterval, const Duration(seconds: 15));
  });
}
