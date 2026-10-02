import '../../../core/error/result.dart';
import 'safety_models.dart';

/// Block / report (US-8, US-14). Blocking twice is a success (idempotent).
abstract class SafetyRepository {
  Future<Result<void>> block(String userId);
  Future<Result<void>> unblock(String userId);
  Future<Result<List<BlockedUser>>> blocked();
  Future<Result<void>> report({
    required String userId,
    String? matchId,
    required ReportReason reason,
    String? details,
  });
}

/// Emergency contacts CRUD; max [ContactRules.maxContacts] (server enforces
/// `GWM_EMERGENCY_CONTACT_LIMIT` too).
abstract class EmergencyContactRepository {
  Future<Result<List<EmergencyContact>>> list();
  Future<Result<EmergencyContact>> add({required String name, required String phone});
  Future<Result<EmergencyContact>> update(String id, {required String name, required String phone});
  Future<Result<void>> delete(String id);
}

/// Remote sink for SOS rows. Must be idempotent on [SosEvent.id].
abstract class SosRepository {
  Future<Result<void>> submit(SosEvent event);
}
