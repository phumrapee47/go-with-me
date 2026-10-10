import 'dart:async';

import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/net/throttle.dart';
import '../domain/safety_models.dart';
import '../domain/safety_repository.dart';

class FlushResult {
  const FlushResult({this.sent = 0, this.dropped = 0, this.remaining = 0, this.failure});
  final int sent;
  final int dropped;
  final int remaining;

  /// Last transient failure (why [remaining] > 0), if any.
  final AppFailure? failure;
}

/// Failures that will never succeed on retry (design-api 7.1 d): drop them.
bool isPermanentSosFailure(AppFailure f) => const {
      'GWM_FORBIDDEN',
      FailureCode.forbiddenRls,
      FailureCode.forbiddenColumn,
      FailureCode.validation,
    }.contains(f.code);

/// Exponential backoff for the background retry: 2s, 4s ... capped at 60s.
Duration sosBackoff(int attempt) {
  final secs = 2 * (1 << attempt.clamp(0, 5));
  return Duration(seconds: secs > 60 ? 60 : secs);
}

/// Persistent local queue for SOS incidents ("must not be lost" beats "must
/// not be duplicated"; the row id makes duplicates harmless).
class SosOutbox {
  SosOutbox(this._prefs, {Clock? clock, this.maxAge = const Duration(hours: 24), this.sendTimeout = const Duration(seconds: 15)})
      : _clock = clock ?? DateTime.now;

  static const _key = 'sos_outbox_v1';

  final SharedPreferences _prefs;
  final Clock _clock;

  /// Older incidents are dropped: help is no longer relevant and the server
  /// clamps `client_created_at` to [now-24h, now+5m] anyway.
  final Duration maxAge;
  final Duration sendTimeout;
  Future<FlushResult>? _inFlight;

  List<SosEvent> pending() => [...decodeSosEvents(_prefs.getString(_key))];

  bool contains(String id) => pending().any((e) => e.id == id);

  Future<void> _save(List<SosEvent> l) =>
      l.isEmpty ? _prefs.remove(_key) : _prefs.setString(_key, encodeSosEvents(l));

  /// False when this id is already queued (idempotent enqueue).
  Future<bool> enqueue(SosEvent e) async {
    final l = pending();
    if (l.any((x) => x.id == e.id)) return false;
    await _save([...l, e]);
    return true;
  }

  /// Adds a late GPS fix to a still-unsent incident. False = already sent.
  Future<bool> attachLocation(String id, LatLng p) async {
    final l = pending();
    final i = l.indexWhere((e) => e.id == id);
    if (i < 0) return false;
    l[i] = l[i].copyWith(location: p);
    await _save(l);
    return true;
  }

  /// Sends everything queued, oldest first. Concurrent calls share one run.
  Future<FlushResult> flush(SosRepository repo) {
    final running = _inFlight;
    if (running != null) {
      _rerun = true; // something may have been queued after the run took its snapshot
      return running;
    }
    return _inFlight = _runLoop(repo).whenComplete(() => _inFlight = null);
  }

  bool _rerun = false;

  Future<FlushResult> _runLoop(SosRepository repo) async {
    var total = const FlushResult();
    do {
      _rerun = false;
      final r = await _flush(repo);
      total = FlushResult(
        sent: total.sent + r.sent,
        dropped: total.dropped + r.dropped,
        remaining: r.remaining,
        failure: r.failure,
      );
      if (r.failure != null) break;
    } while (_rerun);
    return total;
  }

  Future<FlushResult> _flush(SosRepository repo) async {
    var sent = 0;
    var dropped = 0;
    AppFailure? last;
    final queue = pending()..sort((a, b) => a.clientCreatedAt.compareTo(b.clientCreatedAt));
    for (var event in queue) {
      if (_clock().difference(event.clientCreatedAt) > maxAge) {
        await _remove(event.id);
        dropped++;
        continue;
      }
      var attempts = 0;
      while (true) {
        attempts++;
        final res = await _submit(repo, event);
        final failure = res;
        if (failure == null) {
          await _remove(event.id);
          sent++;
          break;
        }
        if (isPermanentSosFailure(failure)) {
          await _remove(event.id);
          dropped++;
          break;
        }
        if (failure.code == FailureCode.staleReference && event.tripId != null && attempts < 2) {
          // The trip row is gone: keep the alert, drop the dangling reference.
          event = event.copyWith(clearTrip: true);
          continue;
        }
        last = failure;
        break;
      }
      if (last != null) break; // keep order; retry later
    }
    return FlushResult(sent: sent, dropped: dropped, remaining: pending().length, failure: last);
  }

  Future<AppFailure?> _submit(SosRepository repo, SosEvent e) async {
    try {
      final res = await repo.submit(e).timeout(sendTimeout);
      // ignore: unawaited_return_in_try_block
      return res.when(ok: (_) => null, err: (f) => f);
    } on TimeoutException {
      return const AppFailure(FailureCode.networkTimeout, retryable: true);
    } catch (_) {
      return const AppFailure(FailureCode.unknown, retryable: true);
    }
  }

  Future<void> _remove(String id) async => _save(pending().where((e) => e.id != id).toList());
}

class SosTriggerResult {
  const SosTriggerResult({required this.event, required this.deduped});
  final SosEvent event;

  /// True when a press within the debounce window reused the earlier incident.
  final bool deduped;
}

typedef RetryScheduler = void Function(Duration delay, void Function() run);

/// Orchestrates enqueue + background flush. [trigger] returns as soon as the
/// incident is stored locally; the network part is fire-and-forget.
class SosService {
  SosService({
    required SosOutbox outbox,
    required SosRepository repo,
    Clock? clock,
    Uuid? uuid,
    this.debounce = const Duration(seconds: 10),
    RetryScheduler? scheduler,
    this.autoRetry = true,
  })  : _outbox = outbox,
        _repo = repo,
        _clock = clock ?? DateTime.now,
        _uuid = uuid ?? const Uuid(),
        _scheduler = scheduler ?? _defaultScheduler;

  final SosOutbox _outbox;
  final SosRepository _repo;
  final Clock _clock;
  final Uuid _uuid;
  final Duration debounce;
  final RetryScheduler _scheduler;
  final bool autoRetry;
  final _changes = StreamController<int>.broadcast();
  final _recent = <String, (SosEvent, DateTime)>{};
  int _attempt = 0;
  bool _retryScheduled = false;
  bool _disposed = false;

  static void _defaultScheduler(Duration d, void Function() run) {
    Timer(d, run);
  }

  /// Emits the number of unsent incidents after every flush.
  Stream<int> get pendingChanges => _changes.stream;
  int get pendingCount => _outbox.pending().length;
  bool isPending(String id) => _outbox.contains(id);

  /// One id per "incident window" (the confirm screen session).
  String newIncidentId() => _uuid.v4();

  Future<SosTriggerResult> trigger({
    required String incidentId,
    String? tripId,
    LatLng? location,
    SosSource source = SosSource.trip,
    bool flush = true,
  }) async {
    final key = tripId ?? '-';
    final now = _clock();
    final recent = _recent[key];
    if (recent != null && now.difference(recent.$2) < debounce) {
      return SosTriggerResult(event: recent.$1, deduped: true);
    }
    final event = SosEvent(
      id: incidentId,
      tripId: tripId,
      location: location,
      source: source,
      clientCreatedAt: now,
    );
    _recent[key] = (event, now);
    await _outbox.enqueue(event); // false = same incident id already queued
    // [flush] false: the caller starts the send itself a moment later so a
    // GPS fix can still be attached (the row is already safe on the device).
    if (flush) unawaited(kick());
    return SosTriggerResult(event: event, deduped: false);
  }

  /// A GPS fix that arrived after the press: update the unsent row, or send a
  /// follow-up incident (new id) when the first one already left the device.
  Future<void> attachLocation(SosEvent event, LatLng p) async {
    if (await _outbox.attachLocation(event.id, p)) return;
    final followUp = SosEvent(
      id: _uuid.v4(),
      tripId: event.tripId,
      location: p,
      source: event.source,
      note: 'ตำแหน่งอัปเดตของเหตุการณ์ก่อนหน้า',
      clientCreatedAt: _clock(),
    );
    await _outbox.enqueue(followUp);
    unawaited(kick());
  }

  /// Flush now (also called at app start / resume). Schedules a backoff retry
  /// while anything remains queued.
  Future<FlushResult> kick() async {
    final r = await _outbox.flush(_repo);
    if (!_disposed) _changes.add(r.remaining);
    if (r.remaining == 0 || r.failure == null) {
      _attempt = 0;
    } else if (autoRetry && !_retryScheduled && !_disposed) {
      _retryScheduled = true;
      _scheduler(sosBackoff(_attempt++), () {
        _retryScheduled = false;
        if (!_disposed) unawaited(kick());
      });
    }
    return r;
  }

  void dispose() {
    _disposed = true;
    _changes.close();
  }
}
