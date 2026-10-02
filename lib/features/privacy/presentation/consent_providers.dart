import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../data/supabase_consent_repository.dart';
import '../domain/consent_repository.dart';

final consentRepositoryProvider = Provider<ConsentRepository>(
  (ref) => SupabaseConsentRepository(Supabase.instance.client),
);

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => SupabaseAccountRepository(Supabase.instance.client),
);

/// Whether the user currently consents to location use (latest consent row).
/// Errors fail closed (false) so a flaky network never starts tracking.
final locationConsentProvider = FutureProvider<bool>((ref) async {
  final res = await ref.watch(consentRepositoryProvider).locationConsentGranted();
  return res.when(ok: (v) => v, err: (_) => false);
});
