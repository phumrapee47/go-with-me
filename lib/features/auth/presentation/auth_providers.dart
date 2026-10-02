import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/config/app_config.dart';
import '../../../core/providers.dart';
import '../data/supabase_auth_repository.dart';
import '../domain/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (ref.watch(configProvider) is! ConfigReady) {
    return const UnavailableAuthRepository();
  }
  return SupabaseAuthRepository(Supabase.instance.client);
});

final authUserProvider = StreamProvider<AuthUser?>(
  (ref) => ref.watch(authRepositoryProvider).authChanges(),
);
