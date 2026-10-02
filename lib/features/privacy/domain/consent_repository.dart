import '../../../core/error/result.dart';

/// Append-only PDPA consent log (`record_consent` RPC).
abstract class ConsentRepository {
  Future<Result<void>> recordLocationConsent({required bool granted, required String policyVersion});

  /// Latest logged location consent; false when never granted or withdrawn.
  Future<Result<bool>> locationConsentGranted();
}

/// PDPA account operations (US-15).
abstract class AccountRepository {
  /// `export_my_data` RPC as pretty JSON text.
  Future<Result<String>> exportMyData();

  /// `request_account_deletion` RPC (immediate anonymisation, hard delete
  /// after the retention window). The caller signs out afterwards.
  Future<Result<void>> requestAccountDeletion();
}
