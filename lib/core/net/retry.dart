import 'dart:math';

import '../error/app_failure.dart';
import '../error/error_mapper.dart';
import 'throttle.dart';

/// Retries [task] while it fails with a retryable [AppFailure]
/// (design-api section 7: 500ms * 2^n + jitter, capped at 8s).
/// Only use for idempotent operations.
Future<T> retryTransient<T>(
  Future<T> Function() task, {
  int maxRetries = 2,
  Duration base = const Duration(milliseconds: 500),
  Sleeper? sleep,
  Random? random,
}) async {
  final doSleep = sleep ?? realSleep;
  final rnd = random ?? Random();
  var attempt = 0;
  while (true) {
    try {
      return await task();
    } catch (e) {
      final f = mapError(e);
      if (!f.retryable || attempt >= maxRetries) {
        if (e is AppFailure) rethrow;
        throw f;
      }
      final backoff = base * pow(2, attempt).toInt();
      final capped = backoff > const Duration(seconds: 8) ? const Duration(seconds: 8) : backoff;
      await doSleep(capped + Duration(milliseconds: rnd.nextInt(250)));
      attempt++;
    }
  }
}

/// Opens after [threshold] consecutive failures within [window]; while open,
/// calls fail fast until [openFor] elapses, then one probe is let through.
class CircuitBreaker {
  CircuitBreaker({
    this.threshold = 3,
    this.window = const Duration(seconds: 60),
    this.openFor = const Duration(seconds: 60),
    Clock? clock,
  }) : _clock = clock ?? DateTime.now;

  final int threshold;
  final Duration window;
  final Duration openFor;
  final Clock _clock;
  final _failures = <DateTime>[];
  DateTime? _openedAt;

  bool get isOpen {
    final at = _openedAt;
    return at != null && _clock().difference(at) < openFor;
  }

  void recordSuccess() {
    _failures.clear();
    _openedAt = null;
  }

  void recordFailure() {
    final now = _clock();
    _failures
      ..removeWhere((t) => now.difference(t) > window)
      ..add(now);
    if (_failures.length >= threshold) _openedAt = now;
  }
}
