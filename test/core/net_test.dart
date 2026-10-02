import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/net/lru_cache.dart';
import 'package:gowithme/core/net/retry.dart';
import 'package:gowithme/core/net/throttle.dart';

class _Clock {
  DateTime now = DateTime(2026, 1, 1);
  DateTime call() => now;
  Future<void> sleep(Duration d) async => now = now.add(d);
}

void main() {
  group('Throttle', () {
    test('spaces task starts by at least minInterval (1 req/s)', () async {
      final c = _Clock();
      final t = Throttle(const Duration(milliseconds: 1100), clock: c.call, sleep: c.sleep);
      final starts = <DateTime>[];
      await Future.wait([
        for (var i = 0; i < 3; i++) t.run(() async => starts.add(c.now)),
      ]);
      expect(starts[1].difference(starts[0]), const Duration(milliseconds: 1100));
      expect(starts[2].difference(starts[1]), const Duration(milliseconds: 1100));
    });

    test('a failing task does not block the queue', () async {
      final c = _Clock();
      final t = Throttle(Duration.zero, clock: c.call, sleep: c.sleep);
      final bad = t.run<int>(() async => throw StateError('x'));
      final good = t.run(() async => 7);
      await expectLater(bad, throwsStateError);
      expect(await good, 7);
    });
  });

  test('RefreshGate allows one call per 10 s', () {
    final c = _Clock();
    final g = RefreshGate(const Duration(seconds: 10), clock: c.call);
    expect(g.tryAcquire(), isTrue);
    c.now = c.now.add(const Duration(seconds: 9));
    expect(g.tryAcquire(), isFalse);
    c.now = c.now.add(const Duration(seconds: 2));
    expect(g.tryAcquire(), isTrue);
  });

  group('LruCache', () {
    test('evicts least recently used and honours TTL', () {
      final c = _Clock();
      final cache = LruCache<String, int>(capacity: 2, ttl: const Duration(minutes: 1), clock: c.call);
      cache.put('a', 1);
      cache.put('b', 2);
      expect(cache.get('a'), 1); // a becomes most recent
      cache.put('c', 3); // evicts b
      expect(cache.get('b'), isNull);
      expect(cache.get('a'), 1);
      c.now = c.now.add(const Duration(minutes: 2));
      expect(cache.get('a'), isNull);
    });

    test('per-entry ttl override', () {
      final c = _Clock();
      final cache = LruCache<String, int>(capacity: 5, ttl: const Duration(hours: 1), clock: c.call);
      cache.put('empty', 0, ttl: const Duration(minutes: 10));
      c.now = c.now.add(const Duration(minutes: 11));
      expect(cache.get('empty'), isNull);
    });
  });

  group('retryTransient', () {
    test('retries retryable failures with backoff then succeeds', () async {
      var calls = 0;
      final waits = <Duration>[];
      final r = await retryTransient(
        () async {
          calls++;
          if (calls < 3) throw const AppFailure(FailureCode.networkTimeout, retryable: true);
          return 'ok';
        },
        sleep: (d) async => waits.add(d),
      );
      expect(r, 'ok');
      expect(calls, 3);
      expect(waits.length, 2);
      expect(waits[1], greaterThan(waits[0]));
    });

    test('does not retry non-retryable failures', () async {
      var calls = 0;
      await expectLater(
        retryTransient(() async {
          calls++;
          throw const AppFailure('GWM_NOT_ELIGIBLE');
        }, sleep: (_) async {}),
        throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'GWM_NOT_ELIGIBLE')),
      );
      expect(calls, 1);
    });

    test('gives up after maxRetries', () async {
      var calls = 0;
      await expectLater(
        retryTransient(() async {
          calls++;
          throw const AppFailure(FailureCode.serverUnavailable, retryable: true);
        }, maxRetries: 1, sleep: (_) async {}),
        throwsA(isA<AppFailure>()),
      );
      expect(calls, 2);
    });
  });

  test('CircuitBreaker opens after 3 failures and closes after the window', () {
    final c = _Clock();
    final b = CircuitBreaker(clock: c.call);
    b.recordFailure();
    b.recordFailure();
    expect(b.isOpen, isFalse);
    b.recordFailure();
    expect(b.isOpen, isTrue);
    c.now = c.now.add(const Duration(seconds: 61));
    expect(b.isOpen, isFalse);
    b.recordSuccess();
    expect(b.isOpen, isFalse);
  });
}
