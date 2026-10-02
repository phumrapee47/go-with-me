import 'package:flutter/foundation.dart';

/// Only logger allowed in the app: silent in release. Callers must never pass
/// PII, coordinates, tokens, keys or chat text (design-security section 5).
abstract final class Log {
  static void d(String message) {
    if (kReleaseMode) return;
    debugPrint('[gwm] $message');
  }

  /// Logs an error *code* only, never the exception body.
  static void e(String context, {String? code}) {
    if (kReleaseMode) return;
    debugPrint('[gwm][error] $context${code == null ? '' : ' code=$code'}');
  }
}
