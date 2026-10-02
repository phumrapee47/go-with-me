import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

const _key = 'onboarding_done';

/// First-run flag (non-sensitive, so SharedPreferences is fine).
class OnboardingDoneNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(sharedPrefsProvider).getBool(_key) ?? false;

  Future<void> complete() async {
    state = true;
    await ref.read(sharedPrefsProvider).setBool(_key, true);
  }
}

final onboardingDoneProvider =
    NotifierProvider<OnboardingDoneNotifier, bool>(OnboardingDoneNotifier.new);
