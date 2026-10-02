import '../../../core/error/result.dart';
import '../../matching/domain/match_models.dart' show VerificationBadge;
import 'gender.dart';

class Profile {
  const Profile({required this.id, required this.displayName, this.avatarPath});
  final String id;
  final String displayName;
  final String? avatarPath;

  /// Guard rule (design-spec 2.3 step 4): setup is needed only while there is
  /// no usable display name. Photo and emergency contacts stay optional.
  bool get needsSetup => displayName.trim().isEmpty;

  static Profile? fromJson(Map<String, dynamic>? j) {
    if (j == null || j['id'] is! String) return null;
    return Profile(
      id: j['id'] as String,
      displayName: ((j['display_name'] as String?) ?? '').trim(),
      avatarPath: j['avatar_path'] as String?,
    );
  }
}

abstract class ProfileRepository {
  /// Null when no readable profile row exists.
  Future<Result<Profile?>> getMe();

  Future<Result<Profile>> updateDisplayName(String name);

  /// The caller's own verified badges (email, organization, phone) from `verifications`.
  Future<Result<List<VerificationBadge>>> myBadges();

  /// US-45: self-view only (design-roles §14.6 `get_my_gender()`). Null = never set.
  Future<Result<Gender?>> getMyGender();

  /// US-45: self-declare/change. Never readable by anyone else.
  Future<Result<void>> setMyGender(Gender g);

  /// US-45 (Q7): clears the field; server auto-cancels any pending/accepted
  /// Women-Only match with a neutral notice on both sides (not reimplemented here).
  Future<Result<void>> clearMyGender();
}
