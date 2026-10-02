import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the saved places live: on THIS device only, namespaced by user id (US-38, Q2).
/// Nothing here ever reaches the network, a log or an analytics event.
abstract class PresetStorage {
  Future<String?> read(String uid);
  Future<void> write(String uid, String json);
  Future<void> delete(String uid);

  /// Removes the saved places of EVERY user on this device (sign-out / account deletion).
  Future<void> deleteAll();
}

const _prefix = 'gwm.presets.';

/// Keychain / Keystore (web: encrypted local storage of the plugin). Only keys with our prefix are touched:
/// the Supabase session key is never deleted from here.
class SecurePresetStorage implements PresetStorage {
  SecurePresetStorage([FlutterSecureStorage? storage])
      : _s = storage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            );

  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String uid) => _s.read(key: '$_prefix$uid');

  @override
  Future<void> write(String uid, String json) => _s.write(key: '$_prefix$uid', value: json);

  @override
  Future<void> delete(String uid) => _s.delete(key: '$_prefix$uid');

  @override
  Future<void> deleteAll() async {
    final all = await _s.readAll();
    for (final k in all.keys) {
      if (k.startsWith(_prefix)) await _s.delete(key: k);
    }
  }
}

/// Tests and demo mode.
class MemoryPresetStorage implements PresetStorage {
  final Map<String, String> data = {};
  bool failWrites = false;

  @override
  Future<String?> read(String uid) async => data[uid];

  @override
  Future<void> write(String uid, String json) async {
    if (failWrites) throw StateError('storage unavailable');
    data[uid] = json;
  }

  @override
  Future<void> delete(String uid) async => data.remove(uid);

  @override
  Future<void> deleteAll() async => data.clear();
}
