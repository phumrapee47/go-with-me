import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/logging/log.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/preset_storage.dart';
import '../domain/preset.dart';

final presetStorageProvider = Provider<PresetStorage>((ref) => SecurePresetStorage());

/// Saved places of the signed-in user (device-local). Signing out (user id goes from a value to null)
/// wipes every saved place on the device; another account never sees them (namespaced by user id).
class PresetController extends AsyncNotifier<PresetData> {
  String? _uid;

  @override
  Future<PresetData> build() async {
    final uid = ref.watch(authUserProvider.select((a) => a.valueOrNull?.id));
    final was = _uid;
    _uid = uid;
    final storage = ref.read(presetStorageProvider);
    if (uid == null) {
      // A real sign-out (we had a user before): clear. Cold start / loading (never had one): leave alone.
      if (was != null) await _quiet(storage.deleteAll);
      return PresetData.empty;
    }
    try {
      return PresetData.decode(await storage.read(uid));
    } catch (e) {
      Log.d('preset read failed');
      return PresetData.empty;
    }
  }

  PresetData get _current => state.valueOrNull ?? PresetData.empty;

  Future<void> _quiet(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {
      Log.d('preset storage clear failed');
    }
  }

  /// Writes [next]; on failure the old state stays and false is returned.
  Future<bool> _commit(PresetData next) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await ref.read(presetStorageProvider).write(uid, next.encode());
      state = AsyncData(next);
      return true;
    } catch (_) {
      Log.d('preset write failed');
      return false;
    }
  }

  Future<bool> save(PresetKind kind, PlacePreset p) => _commit(
        kind == PresetKind.home ? _current.copyWith(home: p, noticeSeen: true) : _current.copyWith(start: p, noticeSeen: true),
      );

  Future<bool> remove(PresetKind kind) => _commit(
        kind == PresetKind.home ? _current.copyWith(home: null) : _current.copyWith(start: null),
      );

  Future<void> markNoticeSeen() async {
    if (_current.noticeSeen) return;
    await _commit(_current.copyWith(noticeSeen: true));
  }

  /// Last one-tap choices (fixed time or "now", Driver limit). Failures are silent (only a convenience).
  Future<void> rememberChoices({int? departMinutes, int? maxDropoffM}) async {
    final c = _current;
    if (c.isEmpty) return;
    await _commit(c.copyWith(lastDepartMinutes: departMinutes, lastMaxDropoffM: maxDropoffM ?? c.lastMaxDropoffM));
  }

  /// Explicit wipe (sign-out and account deletion call this before the session ends).
  Future<void> clearAll() async {
    await _quiet(ref.read(presetStorageProvider).deleteAll);
    state = const AsyncData(PresetData.empty);
  }
}

final presetsProvider = AsyncNotifierProvider<PresetController, PresetData>(PresetController.new);

/// The Home preset point for the arrival wording (Q5). Null = none saved.
final homePresetPointProvider = Provider<LatLng?>((ref) => ref.watch(presetsProvider).valueOrNull?.home?.point);
