import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/error/result.dart';
import '../../../core/logging/log.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../matching/domain/match_models.dart' show VerificationBadge;
import '../data/supabase_profile_repository.dart';
import '../domain/gender.dart';
import '../domain/profile_repository.dart';

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => SupabaseProfileRepository(Supabase.instance.client),
);

/// The signed-in user's profile row. Rebuilt when the user changes.
/// Null = signed out or no readable row.
final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  final user = ref.watch(authUserProvider.select((a) => a.valueOrNull?.id));
  final confirmed = ref.watch(authUserProvider.select((a) => a.valueOrNull?.emailConfirmed ?? false));
  if (user == null || !confirmed) return null;
  final res = await ref.watch(profileRepositoryProvider).getMe();
  return res.when(
    ok: (p) => p,
    // A failed read must not lock the user out: the guard is UX only and the
    // server enforces everything that matters (fail-open, logged by code).
    err: (f) {
      Log.d('profile load failed: ${f.code}');
      return null;
    },
  );
});

/// Own verified badges for the Me tab (empty on failure: never claim a badge we could not read).
final myBadgesProvider = FutureProvider<List<VerificationBadge>>((ref) async {
  final user = ref.watch(authUserProvider.select((a) => a.valueOrNull?.id));
  if (user == null) return const [];
  final res = await ref.watch(profileRepositoryProvider).myBadges();
  return res.when(ok: (b) => b, err: (_) => const <VerificationBadge>[]);
});

enum ProfileGate { loading, needsSetup, ready }

/// Drives the router guard (design-spec 2.3): no display name -> /setup/profile.
final profileGateProvider = Provider<ProfileGate>((ref) {
  final p = ref.watch(currentProfileProvider);
  if (p.isLoading && !p.hasValue) return ProfileGate.loading;
  final profile = p.valueOrNull;
  if (profile != null && profile.needsSetup) return ProfileGate.needsSetup;
  return ProfileGate.ready;
});

/// US-45: the caller's own gender (self-view only). Null on any failure —
/// never blocks the rest of the app on a read error (fail-open, UX only).
final myGenderProvider = FutureProvider<Gender?>((ref) async {
  final user = ref.watch(authUserProvider.select((a) => a.valueOrNull?.id));
  if (user == null) return null;
  final res = await ref.watch(profileRepositoryProvider).getMyGender();
  return res.when(ok: (g) => g, err: (_) => null);
});

/// Saves/clears the gender and refreshes dependants (Women-Only eligibility).
Future<Result<void>> saveMyGender(WidgetRef ref, Gender g) async {
  final res = await ref.read(profileRepositoryProvider).setMyGender(g);
  if (res case Ok()) ref.invalidate(myGenderProvider);
  return res;
}

Future<Result<void>> clearMyGender(WidgetRef ref) async {
  final res = await ref.read(profileRepositoryProvider).clearMyGender();
  if (res case Ok()) ref.invalidate(myGenderProvider);
  return res;
}

/// Saves the name and refreshes the profile so the guard/greeting update.
Future<Result<void>> saveDisplayName(WidgetRef ref, String name) async {
  final res = await ref.read(profileRepositoryProvider).updateDisplayName(name);
  return res.when(
    ok: (p) {
      ref.invalidate(currentProfileProvider);
      return const Ok(null);
    },
    err: (f) => Err(f),
  );
}
