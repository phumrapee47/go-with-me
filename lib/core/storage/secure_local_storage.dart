import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the Supabase session in Keychain/Keystore instead of
/// SharedPreferences (design-security section 5).
class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  static const _key = 'gwm_supabase_session';
  final FlutterSecureStorage _storage;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => (await _storage.read(key: _key)) != null;

  @override
  Future<String?> accessToken() => _storage.read(key: _key);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}
