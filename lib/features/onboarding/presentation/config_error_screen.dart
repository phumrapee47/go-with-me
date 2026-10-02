import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/state_view.dart';

/// S-02. Never prints the URL or key, only which setting is wrong.
class ConfigErrorScreen extends ConsumerWidget {
  const ConfigErrorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(configProvider);
    final detail = switch (state) {
      ConfigProblem(:final issue) => switch (issue) {
          ConfigIssue.missing => null,
          ConfigIssue.invalidUrl => S.configInvalidUrl,
          ConfigIssue.insecureUrl => S.configInsecureUrl,
          ConfigIssue.notAnonKey => S.configNotAnon,
          ConfigIssue.invalidKey => S.configInvalidKey,
          ConfigIssue.initFailed => S.configInitFailed,
        },
      _ => null,
    };
    return Scaffold(
      body: SafeArea(
        child: StateView.error(
          icon: Icons.settings_suggest_outlined,
          title: S.configErrorTitle,
          message: detail == null ? S.configErrorBody : '$detail\n\n${S.configErrorBody}',
          actionLabel: null,
        ),
      ),
    );
  }
}
