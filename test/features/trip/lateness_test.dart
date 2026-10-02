import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/features/trip/domain/lateness.dart';
import 'package:latlong2/latlong.dart';

const _meet = LatLng(13.7455, 100.5345);

void main() {
  group('isOverdueByTime (Q11(a))', () {
    test('not overdue right at the agreed time', () {
      final agreed = DateTime(2026, 1, 1, 8, 0);
      expect(
        isOverdueByTime(driverDepartAt: agreed, riderDepartAt: agreed, now: agreed),
        isFalse,
      );
    });

    test('not overdue at exactly 9 minutes past (< overdueMin)', () {
      final agreed = DateTime(2026, 1, 1, 8, 0);
      expect(
        isOverdueByTime(driverDepartAt: agreed, riderDepartAt: agreed, now: agreed.add(const Duration(minutes: 9))),
        isFalse,
      );
    });

    test('overdue past 10 minutes (> overdueMin)', () {
      final agreed = DateTime(2026, 1, 1, 8, 0);
      expect(
        isOverdueByTime(driverDepartAt: agreed, riderDepartAt: agreed, now: agreed.add(const Duration(minutes: 11))),
        isTrue,
      );
    });

    test('uses the LATER of the two depart times as the agreed-time proxy', () {
      final driver = DateTime(2026, 1, 1, 8, 0);
      final rider = DateTime(2026, 1, 1, 8, 20); // later
      final now = DateTime(2026, 1, 1, 8, 29); // 9 min past rider's, not overdue yet
      expect(isOverdueByTime(driverDepartAt: driver, riderDepartAt: rider, now: now), isFalse);
      expect(
        isOverdueByTime(driverDepartAt: driver, riderDepartAt: rider, now: now.add(const Duration(minutes: 2))),
        isTrue,
      );
    });
  });

  group('isEtaStalled (Q11(b))', () {
    final now = DateTime(2026, 1, 1, 8, 0);

    test('fewer than 3 samples in the window: never stalled', () {
      final samples = [
        LocationSample(point: const LatLng(13.80, 100.60), at: now.subtract(const Duration(minutes: 1))),
        LocationSample(point: const LatLng(13.79, 100.59), at: now.subtract(const Duration(minutes: 2))),
      ];
      expect(isEtaStalled(samples: samples, meetingPoint: _meet, now: now), isFalse);
    });

    test('3 samples getting steadily closer (>= 100 m shrink): not stalled', () {
      final samples = [
        LocationSample(point: const LatLng(13.80, 100.60), at: now.subtract(const Duration(minutes: 4))),
        LocationSample(point: const LatLng(13.77, 100.55), at: now.subtract(const Duration(minutes: 2))),
        LocationSample(point: const LatLng(13.746, 100.535), at: now),
      ];
      expect(isEtaStalled(samples: samples, meetingPoint: _meet, now: now), isFalse);
    });

    test('3 samples barely moving (< 100 m shrink between oldest and newest): stalled', () {
      final samples = [
        LocationSample(point: const LatLng(13.7500, 100.5400), at: now.subtract(const Duration(minutes: 4))),
        LocationSample(point: const LatLng(13.7498, 100.5398), at: now.subtract(const Duration(minutes: 2))),
        LocationSample(point: const LatLng(13.7497, 100.5397), at: now),
      ];
      expect(isEtaStalled(samples: samples, meetingPoint: _meet, now: now), isTrue);
    });

    test('samples outside the stale window are ignored', () {
      final samples = [
        LocationSample(point: const LatLng(13.7497, 100.5397), at: now.subtract(const Duration(minutes: 30))),
        LocationSample(point: const LatLng(13.7498, 100.5398), at: now.subtract(const Duration(minutes: 29))),
        LocationSample(point: const LatLng(13.7500, 100.5400), at: now.subtract(const Duration(minutes: 28))),
      ];
      expect(isEtaStalled(samples: samples, meetingPoint: _meet, now: now), isFalse);
    });
  });

  group('checkLateness: (a) OR (b)', () {
    test('neither condition: none', () {
      final t = DateTime(2026, 1, 1, 8, 0);
      final trigger = checkLateness(
        driverDepartAt: t,
        riderDepartAt: t,
        now: t.add(const Duration(minutes: 1)),
        samples: const [],
        meetingPoint: _meet,
      );
      expect(trigger, LatenessTrigger.none);
    });

    test('overdue by time wins even with no samples', () {
      final t = DateTime(2026, 1, 1, 8, 0);
      final trigger = checkLateness(
        driverDepartAt: t,
        riderDepartAt: t,
        now: t.add(const Duration(minutes: 15)),
        samples: const [],
        meetingPoint: _meet,
      );
      expect(trigger, LatenessTrigger.overdue);
    });

    test('eta-stalled alone (not yet overdue by time)', () {
      final t = DateTime(2026, 1, 1, 8, 0);
      final now = t.add(const Duration(minutes: 2));
      final samples = [
        LocationSample(point: const LatLng(13.7500, 100.5400), at: now.subtract(const Duration(minutes: 4))),
        LocationSample(point: const LatLng(13.7498, 100.5398), at: now.subtract(const Duration(minutes: 2))),
        LocationSample(point: const LatLng(13.7497, 100.5397), at: now),
      ];
      final trigger = checkLateness(
        driverDepartAt: t,
        riderDepartAt: t,
        now: now,
        samples: samples,
        meetingPoint: _meet,
      );
      expect(trigger, LatenessTrigger.etaStalled);
    });
  });

  group('LatenessSnooze', () {
    test('snoozing hides the card until the window elapses', () {
      var now = DateTime(2026, 1, 1, 8, 0);
      final s = LatenessSnooze(clock: () => now);
      expect(s.isSnoozed, isFalse);
      s.snooze();
      expect(s.isSnoozed, isTrue);
      now = now.add(const Duration(minutes: 9));
      expect(s.isSnoozed, isTrue, reason: 'still inside the 10-minute snooze window');
      now = now.add(const Duration(minutes: 2));
      expect(s.isSnoozed, isFalse, reason: 'the window elapsed');
    });

    test('clear() ends the snooze immediately', () {
      var now = DateTime(2026, 1, 1, 8, 0);
      final s = LatenessSnooze(clock: () => now);
      s.snooze();
      s.clear();
      expect(s.isSnoozed, isFalse);
    });

    test('a fresh snooze after the window elapsed extends it again', () {
      var now = DateTime(2026, 1, 1, 8, 0);
      final s = LatenessSnooze(clock: () => now);
      s.snooze(const Duration(minutes: 10));
      now = now.add(const Duration(minutes: 15));
      expect(s.isSnoozed, isFalse);
      s.snooze(const Duration(minutes: 10));
      expect(s.isSnoozed, isTrue);
    });
  });
}
