import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/error/result.dart';
import 'package:gowithme/core/l10n/strings_p4.dart';
import 'package:gowithme/core/router/redirect.dart';
import 'package:gowithme/features/safety/data/sos_outbox.dart';
import 'package:gowithme/features/safety/domain/safety_models.dart';
import 'package:gowithme/features/safety/domain/safety_repository.dart';
import 'package:gowithme/features/safety/presentation/safety_providers.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repos_p4.dart';
import '../../support/fakes.dart';
import '../../support/p4_helpers.dart';

SosEvent _event(String id, {DateTime? at, String? trip = 'trip-1', LatLng? loc}) =>
    SosEvent(id: id, clientCreatedAt: at ?? DateTime.now(), tripId: trip, location: loc);

void main() {
  late SharedPreferences prefs;
  late FakeSosRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    repo = FakeSosRepository();
  });

  group('SOS outbox', () {
    test('enqueue is idempotent on the incident id', () async {
      final box = SosOutbox(prefs);
      expect(await box.enqueue(_event('a')), isTrue);
      expect(await box.enqueue(_event('a')), isFalse);
      expect(box.pending(), hasLength(1));
    });

    test('sending the same id twice never creates a second row', () async {
      final box = SosOutbox(prefs);
      await box.enqueue(_event('a'));
      await box.flush(repo);
      // A retry after a timeout: the same id goes out again.
      await box.enqueue(_event('a'));
      final r = await box.flush(repo);
      expect(r.sent, 1);
      expect(repo.submitCalls, 2);
      expect(repo.rows.keys, ['a'], reason: 'ignore-duplicates keeps a single row');
    });

    test('offline: stays queued (and survives a restart), then is delivered', () async {
      repo.failure = const AppFailure(FailureCode.networkOffline, retryable: true);
      final box = SosOutbox(prefs);
      await box.enqueue(_event('a'));
      final r1 = await box.flush(repo);
      expect(r1.remaining, 1);
      expect(r1.failure?.code, FailureCode.networkOffline);

      final afterRestart = SosOutbox(prefs);
      expect(afterRestart.pending().single.id, 'a');

      repo.failure = null;
      final r2 = await afterRestart.flush(repo);
      expect((r2.sent, r2.remaining), (1, 0));
      expect(repo.rows.containsKey('a'), isTrue);
      expect(afterRestart.pending(), isEmpty);
    });

    test('a transient failure keeps order: later events wait behind the failed one', () async {
      repo.failure = const AppFailure(FailureCode.serverUnavailable, retryable: true);
      final box = SosOutbox(prefs);
      final t = DateTime.now();
      await box.enqueue(_event('second', at: t));
      await box.enqueue(_event('first', at: t.subtract(const Duration(minutes: 1))));
      await box.flush(repo);
      expect(repo.submitCalls, 1, reason: 'stops at the first failure');
      repo.failure = null;
      await box.flush(repo);
      expect(repo.rows.keys.toList(), ['first', 'second']);
    });

    test('permanent failures (403) are dropped, not retried forever', () async {
      repo.failure = const AppFailure('GWM_FORBIDDEN');
      final box = SosOutbox(prefs);
      await box.enqueue(_event('a'));
      final r = await box.flush(repo);
      expect((r.dropped, r.remaining), (1, 0));
    });

    test('a vanished trip reference is stripped and the alert still goes out', () async {
      var calls = 0;
      final custom = _ScriptedSos((e) {
        calls++;
        return e.tripId != null ? const AppFailure(FailureCode.staleReference) : null;
      });
      final box = SosOutbox(prefs);
      await box.enqueue(_event('a'));
      final r = await box.flush(custom);
      expect(r.sent, 1);
      expect(calls, 2);
      expect(custom.delivered.single.tripId, isNull);
    });

    test('incidents older than 24 h are dropped', () async {
      final box = SosOutbox(prefs);
      await box.enqueue(_event('old', at: DateTime.now().subtract(const Duration(hours: 25))));
      final r = await box.flush(repo);
      expect((r.dropped, repo.submitCalls), (1, 0));
    });

    test('concurrent flushes share one run (no double submit)', () async {
      final box = SosOutbox(prefs);
      await box.enqueue(_event('a'));
      final rs = await Future.wait([box.flush(repo), box.flush(repo)]);
      expect(repo.submitCalls, 1);
      expect(rs[0].sent, 1);
    });

    test('a hanging request times out and stays queued', () async {
      repo.hang = Completer<void>();
      final box = SosOutbox(prefs, sendTimeout: const Duration(milliseconds: 50));
      await box.enqueue(_event('a'));
      final r = await box.flush(repo);
      expect(r.remaining, 1);
      expect(r.failure?.code, FailureCode.networkTimeout);
    });

    test('backoff grows and is capped at 60 s', () {
      expect([for (var i = 0; i < 7; i++) sosBackoff(i).inSeconds], [2, 4, 8, 16, 32, 60, 60]);
    });
  });

  group('SOS service', () {
    test('trigger returns without waiting for the network', () async {
      repo.hang = Completer<void>(); // the server never answers
      final svc = SosService(outbox: SosOutbox(prefs), repo: repo, autoRetry: false);
      final res = await svc.trigger(incidentId: 'i1', tripId: 't1').timeout(const Duration(seconds: 1));
      expect(res.deduped, isFalse);
      expect(svc.pendingCount, 1, reason: 'saved locally first');
      repo.hang!.complete();
    });

    test('panic tapping within 10 s reuses the incident', () async {
      var now = DateTime(2026, 1, 1, 12);
      final svc = SosService(outbox: SosOutbox(prefs, clock: () => now), repo: repo, clock: () => now, autoRetry: false);
      final a = await svc.trigger(incidentId: 'i1', tripId: 't1');
      now = now.add(const Duration(seconds: 3));
      final b = await svc.trigger(incidentId: 'i2', tripId: 't1');
      expect(b.deduped, isTrue);
      expect(b.event.id, 'i1');
      now = now.add(const Duration(seconds: 8));
      final c = await svc.trigger(incidentId: 'i3', tripId: 't1');
      expect(c.deduped, isFalse);
      await svc.kick();
      expect(repo.rows.keys.toSet(), {a.event.id, c.event.id});
    });

    test('failed flush schedules a backoff retry that eventually delivers', () async {
      repo.failure = const AppFailure(FailureCode.networkOffline, retryable: true);
      final scheduled = <Duration>[];
      void Function()? pendingRun;
      final svc = SosService(
        outbox: SosOutbox(prefs),
        repo: repo,
        scheduler: (d, run) {
          scheduled.add(d);
          pendingRun = run;
        },
      );
      await svc.trigger(incidentId: 'i1');
      await svc.kick();
      expect(scheduled, [const Duration(seconds: 2)]);
      pendingRun!();
      await Future<void>.delayed(Duration.zero);
      await svc.kick();
      expect(scheduled.length, greaterThanOrEqualTo(2));
      expect(scheduled[1], const Duration(seconds: 4));
      repo.failure = null;
      pendingRun!();
      await svc.kick();
      expect(repo.rows.containsKey('i1'), isTrue);
      expect(svc.pendingCount, 0);
    });

    test('late GPS fix updates an unsent incident, else sends a follow-up', () async {
      repo.failure = const AppFailure(FailureCode.networkOffline, retryable: true);
      final svc = SosService(outbox: SosOutbox(prefs), repo: repo, autoRetry: false);
      final r = await svc.trigger(incidentId: 'i1', tripId: 't1');
      await svc.kick();
      await svc.attachLocation(r.event, const LatLng(13.7, 100.5));
      repo.failure = null;
      await svc.kick();
      expect(repo.rows['i1']!.location, const LatLng(13.7, 100.5));

      final r2 = await svc.trigger(incidentId: 'i9', tripId: 't2');
      await svc.kick(); // already sent, without a position
      await svc.attachLocation(r2.event, const LatLng(13.8, 100.6));
      await svc.kick();
      expect(repo.rows.length, 3, reason: 'a follow-up incident carries the late position');
    });

    test('message includes an OSM link only when a position is known', () {
      final with_ = buildSosMessage(name: 'มิ้นท์', at: DateTime(2026, 1, 1, 18, 5), location: const LatLng(13.7, 100.5));
      final without = buildSosMessage(name: 'มิ้นท์', at: DateTime(2026, 1, 1, 18, 5));
      expect(with_, contains('openstreetmap.org'));
      expect(with_, contains('18:05'));
      expect(with_, contains('มิ้นท์'));
      expect(without, isNot(contains('http')));
    });
  });

  group('SOS screen', () {
    Future<Fakes> open(WidgetTester tester, {bool contacts = true}) async {
      final f = Fakes()..trips.active = runningTrip();
      if (contacts) f.contacts.items.add(const EmergencyContact(id: 'c1', name: 'แม่', phone: '0812345678'));
      await openApp(tester, f);
      await goTo(tester, Routes.sosFor(tripId: 'trip-1'));
      return f;
    }

    Future<void> holdFor(WidgetTester tester, Duration d) async {
      final g = await tester.startGesture(tester.getCenter(find.text(P.sosHold)));
      // Tap-down fires after the 100 ms press timeout; the ticker then starts
      // on the next frame, so advance in two steps like a real device would.
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      await tester.pump(d);
      await g.up();
      await tester.pump();
    }

    testWidgets('releasing early cancels: nothing is sent', (tester) async {
      final f = await open(tester);
      await holdFor(tester, const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text(P.sosCall191), findsNothing);
      expect(f.sos.submitCalls, 0);
    });

    testWidgets('hold 2 s: 191/1669 appear at once, incident saved with a client id, share sheet opens',
        (tester) async {
      final f = await open(tester);
      expect(find.text(P.sosCall191), findsNothing);
      await holdFor(tester, const Duration(milliseconds: 2100));
      await tester.pumpAndSettle();

      expect(find.text(P.sosCall191), findsOneWidget);
      expect(find.text(P.sosCall1669), findsOneWidget);
      expect(f.sos.rows, hasLength(1));
      final row = f.sos.rows.values.single;
      expect(row.id, matches(RegExp(r'^[0-9a-f-]{36}$')), reason: 'client generated UUID');
      expect(row.tripId, 'trip-1');
      expect(find.text(P.sosSaved), findsOneWidget);
      // Contacts exist: the share sheet opened with an OSM link to the position.
      expect(f.actions.shared.single, contains('openstreetmap.org'));

      await tester.tap(find.text(P.sosCall191));
      await tester.tap(find.text(P.sosCall1669));
      expect(f.actions.calls, ['191', '1669']);
    });

    testWidgets('single tap confirm works for people who cannot hold', (tester) async {
      final f = await open(tester);
      await tester.tap(find.text(P.sosTapConfirm));
      await tester.pumpAndSettle();
      expect(find.text(P.sosCall191), findsOneWidget);
      expect(f.sos.rows, hasLength(1));
    });

    testWidgets('never blocks on the network: phone buttons work while saving hangs', (tester) async {
      final f = await open(tester);
      f.sos.hang = Completer<void>();
      await tester.tap(find.text(P.sosTapConfirm));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(P.sosCall191), findsOneWidget);
      await tester.tap(find.text(P.sosCall191));
      expect(f.actions.calls, ['191']);
      expect(find.text(P.sosSaving), findsOneWidget);
      f.sos.hang!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('offline: incident is queued locally and delivered later with the same id', (tester) async {
      final f = await open(tester);
      f.sos.failure = const AppFailure(FailureCode.networkOffline, retryable: true);
      await tester.tap(find.text(P.sosTapConfirm));
      await tester.pumpAndSettle();
      expect(find.text(P.sosQueued), findsOneWidget);
      expect(find.text(P.sosCall191), findsOneWidget, reason: 'calls still work offline');
      final svc = containerOf(tester).read(sosServiceProvider);
      expect(svc.pendingCount, 1);
      final id = containerOf(tester).read(sosOutboxProvider).pending().single.id;

      f.sos.failure = null;
      await tester.runAsync(() => svc.kick());
      await tester.pumpAndSettle();
      expect(f.sos.rows.keys, [id]);
      expect(svc.pendingCount, 0);
      expect(find.text(P.sosSaved), findsOneWidget);
    });

    testWidgets('no contacts: phone buttons plus a setup card, no share sheet', (tester) async {
      final f = await open(tester, contacts: false);
      await tester.tap(find.text(P.sosTapConfirm));
      await tester.pumpAndSettle();
      expect(find.text(P.sosCall191), findsOneWidget);
      expect(find.text(P.sosSetupContacts), findsOneWidget);
      expect(f.actions.shared, isEmpty);
    });
  });
}

class _ScriptedSos implements SosRepository {
  _ScriptedSos(this._decide);
  final AppFailure? Function(SosEvent) _decide;
  final delivered = <SosEvent>[];

  @override
  Future<Result<void>> submit(SosEvent event) async {
    final f = _decide(event);
    if (f != null) return Err(f);
    delivered.add(event);
    return const Ok(null);
  }
}
