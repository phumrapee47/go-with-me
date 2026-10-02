import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_settings.dart';
import '../tokens.dart';

/// G-10 ThemeSettingsToggle (/me/settings/theme, design-spec-round7 G.5.3).
/// 4 modes (US-46 AC1, updated): System / Light / Dark / Auto-by-time (18:00-06:00, Q17).
class ThemeSettingsScreen extends ConsumerWidget {
  const ThemeSettingsScreen({super.key});

  static const _labels = {
    ThemeModeSetting.system: 'ตามระบบ',
    ThemeModeSetting.light: 'สว่างตลอด',
    ThemeModeSetting.dark: 'มืดตลอด',
    ThemeModeSetting.autoByTime: 'มืดอัตโนมัติตามเวลา (18:00–06:00)',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('รูปแบบธีม')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.pageH),
        children: [
          Semantics(
            liveRegion: true,
            label: 'กำลังใช้: ${_labels[current]}',
            child: Text('กำลังใช้: ${_labels[current]}', style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final m in ThemeModeSetting.values)
            RadioListTile<ThemeModeSetting>(
              key: Key('theme-mode-${m.storageValue}'),
              contentPadding: EdgeInsets.zero,
              title: Text(_labels[m]!),
              value: m,
              groupValue: current,
              onChanged: (v) {
                if (v != null) ref.read(themeSettingsProvider.notifier).setMode(v);
              },
            ),
        ],
      ),
    );
  }
}
