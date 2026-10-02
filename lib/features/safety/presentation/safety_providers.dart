import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/error/app_failure.dart';
import '../../../core/error/result.dart';
import '../../../core/providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../geo/presentation/geo_providers.dart';
import '../data/sos_outbox.dart';
import '../data/supabase_safety_repositories.dart';
import '../domain/safety_models.dart';
import '../domain/safety_repository.dart';

final safetyRepositoryProvider = Provider<SafetyRepository>(
  (ref) => SupabaseSafetyRepository(Supabase.instance.client),
);

final emergencyContactRepositoryProvider = Provider<EmergencyContactRepository>(
  (ref) => SupabaseEmergencyContactRepository(Supabase.instance.client),
);

final sosRepositoryProvider = Provider<SosRepository>(
  (ref) => SupabaseSosRepository(Supabase.instance.client),
);

/// How long the first send may wait for a GPS fix (the incident is already
/// stored locally; this only avoids sending a second "position" row).
final sosFlushGraceProvider = Provider<Duration>((ref) => const Duration(milliseconds: 1500));

/// Tests set this false so no real timer is left behind by the SOS retry.
final sosAutoRetryProvider = Provider<bool>((ref) => true);

final sosOutboxProvider = Provider<SosOutbox>((ref) => SosOutbox(ref.watch(sharedPrefsProvider)));

final sosServiceProvider = Provider<SosService>((ref) {
  final s = SosService(
    outbox: ref.watch(sosOutboxProvider),
    repo: ref.watch(sosRepositoryProvider),
    autoRetry: ref.watch(sosAutoRetryProvider),
  );
  ref.onDispose(s.dispose);
  return s;
});

// ---- blocked users --------------------------------------------------------

class BlockedController extends AsyncNotifier<List<BlockedUser>> {
  @override
  Future<List<BlockedUser>> build() async {
    if (ref.watch(authUserProvider.select((a) => a.valueOrNull?.id)) == null) return const [];
    final res = await ref.watch(safetyRepositoryProvider).blocked();
    return res.when(ok: (l) => l, err: (f) => throw f);
  }

  Future<Result<void>> unblock(String userId) async {
    final res = await ref.read(safetyRepositoryProvider).unblock(userId);
    if (res is Ok) {
      state = AsyncData([for (final b in state.valueOrNull ?? const <BlockedUser>[]) if (b.userId != userId) b]);
    }
    return res;
  }
}

final blockedUsersProvider = AsyncNotifierProvider<BlockedController, List<BlockedUser>>(BlockedController.new);

// ---- emergency contacts ---------------------------------------------------

/// Local copy of the contacts so SOS can read them with no network at all.
class ContactCache {
  ContactCache(this._read, this._write);
  static const key = 'emergency_contacts_cache_v1';
  final String? Function() _read;
  final Future<void> Function(String) _write;

  List<EmergencyContact> read() {
    final raw = _read();
    if (raw == null) return const [];
    try {
      return [for (final x in jsonDecode(raw) as List) ?EmergencyContact.fromJson(x as Map<String, dynamic>)];
    } catch (_) {
      return const [];
    }
  }

  Future<void> write(List<EmergencyContact> l) => _write(jsonEncode([for (final c in l) c.toJson()]));
}

final contactCacheProvider = Provider<ContactCache>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return ContactCache(() => prefs.getString(ContactCache.key), (v) => prefs.setString(ContactCache.key, v));
});

class ContactsController extends AsyncNotifier<List<EmergencyContact>> {
  @override
  Future<List<EmergencyContact>> build() async {
    if (ref.watch(authUserProvider.select((a) => a.valueOrNull?.id)) == null) return const [];
    final cache = ref.watch(contactCacheProvider);
    final res = await ref.watch(emergencyContactRepositoryProvider).list();
    switch (res) {
      case Ok(:final value):
        unawaited(cache.write(value));
        return value;
      case Err(:final failure):
        final cached = cache.read();
        if (cached.isNotEmpty) return cached; // SOS must still see them offline
        throw failure;
    }
  }

  List<EmergencyContact> get _current => state.valueOrNull ?? const [];

  Future<void> _set(List<EmergencyContact> l) async {
    state = AsyncData(l);
    await ref.read(contactCacheProvider).write(l);
  }

  Future<Result<EmergencyContact>> add(String name, String phone) async {
    if (!ContactRules.canAdd(_current.length)) return const Err(AppFailure('GWM_EMERGENCY_CONTACT_LIMIT'));
    if (ContactRules.isDuplicate(_current, phone)) return const Err(AppFailure(FailureCode.duplicate));
    final res = await ref.read(emergencyContactRepositoryProvider).add(name: name, phone: phone);
    if (res case Ok(:final value)) await _set([..._current, value]);
    return res;
  }

  Future<Result<EmergencyContact>> edit(String id, String name, String phone) async {
    if (ContactRules.isDuplicate(_current, phone, exceptId: id)) return const Err(AppFailure(FailureCode.duplicate));
    final res = await ref.read(emergencyContactRepositoryProvider).update(id, name: name, phone: phone);
    if (res case Ok(:final value)) await _set([for (final c in _current) c.id == id ? value : c]);
    return res;
  }

  Future<Result<void>> delete(String id) async {
    final res = await ref.read(emergencyContactRepositoryProvider).delete(id);
    if (res is Ok) await _set([for (final c in _current) if (c.id != id) c]);
    return res;
  }
}

final contactsProvider =
    AsyncNotifierProvider<ContactsController, List<EmergencyContact>>(ContactsController.new);

// ---- SOS screen state -----------------------------------------------------

enum SosLog { none, saving, saved, queued }

enum SosLoc { resolving, found, unavailable }

class SosUiState {
  const SosUiState({
    this.triggered = false,
    this.event,
    this.log = SosLog.none,
    this.loc = SosLoc.resolving,
    this.location,
  });
  final bool triggered;
  final SosEvent? event;
  final SosLog log;
  final SosLoc loc;
  final LatLng? location;

  SosUiState copyWith({bool? triggered, SosEvent? event, SosLog? log, SosLoc? loc, LatLng? location}) => SosUiState(
        triggered: triggered ?? this.triggered,
        event: event ?? this.event,
        log: log ?? this.log,
        loc: loc ?? this.loc,
        location: location ?? this.location,
      );
}

/// Drives the SOS screen. [trigger] flips the UI to "done" synchronously
/// (call buttons appear at once); saving and locating run in the background.
class SosController extends AutoDisposeNotifier<SosUiState> {
  late String _incidentId;
  StreamSubscription<int>? _sub;
  bool _disposed = false;

  @override
  SosUiState build() {
    _disposed = false;
    final service = ref.read(sosServiceProvider);
    _incidentId = service.newIncidentId();
    ref.onDispose(() {
      _disposed = true;
      _sub?.cancel();
    });
    return const SosUiState();
  }

  void _set(SosUiState s) {
    if (!_disposed) state = s;
  }

  Future<void> trigger({required SosSource source, String? tripId}) async {
    if (state.triggered) return;
    final service = ref.read(sosServiceProvider);
    final cached = ref.read(lastFixProvider)?.point;
    _set(state.copyWith(triggered: true, log: SosLog.saving, location: cached, loc: cached != null ? SosLoc.found : SosLoc.resolving));
    unawaited(_run(service, source, tripId, cached));
  }

  Future<void> _run(SosService service, SosSource source, String? tripId, LatLng? cached) async {
    // 1. Store locally (fast, no network). 2. Give GPS a moment. 3. Send.
    final res = await service.trigger(
      incidentId: _incidentId,
      tripId: tripId,
      location: cached,
      source: source,
      flush: false,
    );
    if (_disposed) return;
    final event = res.event;
    _set(state.copyWith(event: event));
    // A flush that completes while the event is still queued means it failed.
    _sub = service.pendingChanges.listen((_) => _afterFlush(service));

    final locating = _locate(service, event, cached != null);
    final grace = ref.read(sosFlushGraceProvider);
    if (cached == null && grace > Duration.zero) {
      final wake = Completer<void>();
      final t = Timer(grace, () {
        if (!wake.isCompleted) wake.complete();
      });
      await Future.any([locating, wake.future]);
      t.cancel();
    }
    await service.kick();
    _afterFlush(service);
    await locating;
  }

  void _afterFlush(SosService service) {
    final e = state.event;
    if (e == null) return;
    _set(state.copyWith(log: service.isPending(e.id) ? SosLog.queued : SosLog.saved));
  }

  Future<void> _locate(SosService service, SosEvent event, bool hadCached) async {
    // GPS only; never waits on the network. A few seconds at most.
    final r = await ref
        .read(locationServiceProvider)
        .currentPosition()
        .timeout(const Duration(seconds: 4), onTimeout: () => const Err(AppFailure(FailureCode.locationUnavailable)));
    if (_disposed) return;
    switch (r) {
      case Ok(:final value):
        _set(state.copyWith(loc: SosLoc.found, location: value));
        await service.attachLocation(event, value);
      case Err():
        if (!hadCached) _set(state.copyWith(loc: SosLoc.unavailable));
    }
  }
}

final sosControllerProvider = NotifierProvider.autoDispose<SosController, SosUiState>(SosController.new);
