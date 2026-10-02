import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Reasons the app refuses to talk to Supabase. Never carries the URL/key.
enum ConfigIssue { missing, invalidUrl, insecureUrl, notAnonKey, invalidKey, initFailed }

sealed class ConfigState {
  const ConfigState();
}

class ConfigReady extends ConfigState {
  const ConfigReady({required this.url, required this.anonKey});
  final String url;
  final String anonKey;
}

class ConfigProblem extends ConfigState {
  const ConfigProblem(this.issue);
  final ConfigIssue issue;
}

const _envUrl = String.fromEnvironment('SUPABASE_URL');
const _envKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const _envAllowInsecure = bool.fromEnvironment('ALLOW_INSECURE_LOCAL');

/// Reads --dart-define / --dart-define-from-file values.
ConfigState loadConfigFromEnvironment() => evaluateConfig(
      url: _envUrl,
      anonKey: _envKey,
      allowInsecureLocal: _envAllowInsecure,
      isDebug: kDebugMode,
    );

/// Pure validation so it can be unit-tested (design-security section 5).
ConfigState evaluateConfig({
  required String url,
  required String anonKey,
  bool allowInsecureLocal = false,
  bool isDebug = false,
}) {
  final u = url.trim();
  final k = anonKey.trim();
  if (u.isEmpty || k.isEmpty) return const ConfigProblem(ConfigIssue.missing);

  final uri = Uri.tryParse(u);
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
    return const ConfigProblem(ConfigIssue.invalidUrl);
  }
  final secure = uri.scheme == 'https';
  final insecureOk = uri.scheme == 'http' && allowInsecureLocal && isDebug;
  if (!secure && !insecureOk) {
    return const ConfigProblem(ConfigIssue.insecureUrl);
  }

  final keyIssue = _checkAnonKey(k);
  if (keyIssue != null) return ConfigProblem(keyIssue);
  return ConfigReady(url: u, anonKey: k);
}

ConfigIssue? _checkAnonKey(String key) {
  // New-style Supabase API keys are opaque, not JWTs.
  if (key.startsWith('sb_publishable_')) return null;
  if (key.startsWith('sb_secret_')) return ConfigIssue.notAnonKey;

  final parts = key.split('.');
  if (parts.length != 3) return ConfigIssue.invalidKey;
  try {
    final payload = json.decode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is! Map || payload['role'] != 'anon') {
      return ConfigIssue.notAnonKey;
    }
    return null;
  } catch (_) {
    return ConfigIssue.invalidKey;
  }
}
