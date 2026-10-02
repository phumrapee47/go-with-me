import 'dart:async';

typedef Sleeper = Future<void> Function(Duration d);
typedef Clock = DateTime Function();

Future<void> realSleep(Duration d) => Future<void>.delayed(d);

/// Serialises tasks and guarantees at least [minInterval] between the START
/// of consecutive tasks (Nominatim policy: 1 req/s for the whole app).
class Throttle {
  Throttle(this.minInterval, {Clock? clock, Sleeper? sleep})
      : _clock = clock ?? DateTime.now,
        _sleep = sleep ?? realSleep;

  final Duration minInterval;
  final Clock _clock;
  final Sleeper _sleep;
  DateTime? _lastStart;
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      final last = _lastStart;
      if (last != null) {
        final wait = minInterval - _clock().difference(last);
        if (wait > Duration.zero) await _sleep(wait);
      }
      _lastStart = _clock();
      try {
        completer.complete(await task());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}

/// Client-side budget for read RPCs (design-api section 8): calls closer than
/// [minInterval] to the previous accepted one are skipped.
class RefreshGate {
  RefreshGate(this.minInterval, {Clock? clock}) : _clock = clock ?? DateTime.now;

  final Duration minInterval;
  final Clock _clock;
  DateTime? _last;

  bool tryAcquire() {
    final now = _clock();
    final last = _last;
    if (last != null && now.difference(last) < minInterval) return false;
    _last = now;
    return true;
  }

  void reset() => _last = null;
}
