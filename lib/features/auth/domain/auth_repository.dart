import '../../../core/error/result.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.emailConfirmed,
  });

  final String id;
  final String email;
  final String displayName;
  final bool emailConfirmed;
}

class SignUpOutcome {
  const SignUpOutcome({required this.needsEmailVerification});

  /// True when the server did not return a session (Confirm email = ON, P-4).
  final bool needsEmailVerification;
}

abstract class AuthRepository {
  /// Emits the current user first, then every auth change (null = signed out).
  Stream<AuthUser?> authChanges();

  Future<Result<SignUpOutcome>> signUp({
    required String email,
    required String password,
    required String displayName,
  });

  Future<Result<void>> signIn({required String email, required String password});

  Future<Result<void>> signOut();

  Future<Result<void>> resendVerification(String email);

}
