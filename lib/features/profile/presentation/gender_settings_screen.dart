import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../domain/gender.dart';
import 'profile_providers.dart';

/// G-9 GenderSettingsScreen (/me/settings/gender, design-spec-round7 G.4.3).
/// Self-declare, optional, private — used only to gate the Women-Only trip
/// switch (US-45). Deliberately placed next to privacy settings, NOT next to
/// verification (Q-G3): this is not something the user "verifies".
class GenderSettingsScreen extends ConsumerStatefulWidget {
  const GenderSettingsScreen({super.key});

  @override
  ConsumerState<GenderSettingsScreen> createState() => _GenderSettingsScreenState();
}

class _GenderSettingsScreenState extends ConsumerState<GenderSettingsScreen> {
  bool _saving = false;

  Future<void> _save(Gender g) async {
    if (_saving) return;
    setState(() => _saving = true);
    final res = await saveMyGender(ref, g);
    if (!mounted) return;
    setState(() => _saving = false);
    res.when(
      ok: (_) => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('บันทึกแล้ว'))),
      err: (f) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ (${f.code})'))),
    );
  }

  Future<void> _clear() async {
    final ok = await showConfirmDialog(
      context,
      title: 'ล้างค่าเพศของฉัน?',
      body: 'สวิตช์ "เดินทางเฉพาะผู้หญิงด้วยกัน" จะถูกปิดโดยอัตโนมัติด้วย',
      safeLabel: 'ยกเลิก',
      confirmLabel: 'ล้างค่า',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    final res = await clearMyGender(ref);
    if (!mounted) return;
    setState(() => _saving = false);
    res.when(
      ok: (_) => ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ล้างค่าแล้ว สวิตช์เดินทางเฉพาะผู้หญิงถูกปิดด้วย'))),
      err: (f) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ล้างค่าไม่สำเร็จ (${f.code})'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gender = ref.watch(myGenderProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('ข้อมูลเพศ (ส่วนตัว)')),
      body: gender.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('โหลดข้อมูลไม่สำเร็จ')),
        data: (current) => ListView(
          padding: const EdgeInsets.all(AppSpacing.pageH),
          children: [
            Card(
              color: context.tone.infoBg,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(children: [
                  Icon(Icons.privacy_tip_outlined, color: context.tone.accentInk),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Text('ใช้เพื่อจับคู่เท่านั้น ไม่แสดงบนโปรไฟล์', semanticsLabel: 'ใช้เพื่อจับคู่เท่านั้น ไม่แสดงบนโปรไฟล์'),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final g in Gender.values)
              RadioListTile<Gender>(
                key: Key('gender-${g.db}'),
                contentPadding: EdgeInsets.zero,
                title: Text(g.label),
                value: g,
                // ignore: deprecated_member_use
                groupValue: current,
                // ignore: deprecated_member_use
                onChanged: _saving ? null : (v) => v == null ? null : _save(v),
              ),
            const SizedBox(height: AppSpacing.xl),
            if (current != null)
              OutlinedButton(
                key: const Key('gender-clear-btn'),
                onPressed: _saving ? null : _clear,
                style: OutlinedButton.styleFrom(foregroundColor: context.tone.dangerInk, side: BorderSide(color: context.tone.dangerInk)),
                child: const Text('ล้างค่าเพศของฉัน'),
              ),
          ],
        ),
      ),
    );
  }
}
