import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../profile/presentation/profile_providers.dart';

/// G-8 SafetyFilterSwitchGroup (design-spec-round7 G.4.3) — **Women-Only only**
/// this round: the "same institution" row was dropped entirely per the user's
/// decision (see `docs/requirements-round7-ba.md` US-45 scope note). Keeping
/// the group header/wrapper so a future filter can slot back in without a
/// layout rewrite.
class SafetyFilterSwitchGroup extends ConsumerWidget {
  const SafetyFilterSwitchGroup({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gender = ref.watch(myGenderProvider).valueOrNull;
    final eligible = gender?.unlocksWomenOnly ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ตัวกรองความปลอดภัย (ไม่บังคับ)', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Semantics(
          label: eligible
              ? 'เดินทางเฉพาะผู้หญิงด้วยกัน'
              : 'เดินทางเฉพาะผู้หญิงด้วยกัน: ต้องตั้งค่าเพศของคุณเป็น "หญิง" ก่อนถึงจะเปิดใช้ตัวกรองนี้ได้',
          child: SwitchListTile(
            key: const Key('safety-filter-women-only'),
            contentPadding: EdgeInsets.zero,
            title: const Text('เดินทางเฉพาะผู้หญิงด้วยกัน'),
            subtitle: eligible
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      Expanded(
                        child: Text('ต้องตั้งค่าเพศของคุณเป็น "หญิง" ก่อนถึงจะเปิดใช้ตัวกรองนี้ได้',
                            style: TextStyle(color: context.tone.textSecondary)),
                      ),
                      TextButton(
                        key: const Key('safety-filter-go-gender'),
                        onPressed: () => context.push(Routes.settingsGender),
                        child: const Text('ไปตั้งค่าข้อมูลเพศ'),
                      ),
                    ]),
                  ),
            value: eligible && value,
            onChanged: eligible ? onChanged : null,
          ),
        ),
      ],
    );
  }
}
