import 'package:flutter/material.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_card.dart';

/// Placeholder for S-07 until the legal text is provided (T3.x / T4.x).
class PolicyScreen extends StatelessWidget {
  const PolicyScreen({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.pageH),
        children: [
          AppCard(
            tone: AppCardTone.warning,
            child: Row(
              children: [
                Icon(Icons.info_outline, color: context.tone.warningInk),
                const SizedBox(width: AppSpacing.md),
                const Expanded(child: Text(S.draftNotice)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(body, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

const policyBody =
    'เราใช้ตำแหน่งของคุณเพื่อจับคู่คนที่กลับทางเดียวกัน แสดงตำแหน่งสดเฉพาะขณะทริปกำลังเดินทาง '
    'และใช้เมื่อคุณกด SOS เท่านั้น คนอื่นเห็นเพียงบริเวณกว้างจนกว่าคุณจะยอมรับการจับคู่ '
    'คุณขอลบบัญชีและข้อมูลได้ทุกเมื่อในหน้าตั้งค่า';

const termsBody =
    'แอปนี้ช่วยให้คนที่กลับทางเดียวกันได้พบกัน ไม่ใช่บริการรับส่ง '
    'กรุณาใช้วิจารณญาณ แชร์ทริปให้คนที่ไว้ใจ และโทร 191 หรือ 1669 เมื่อเกิดเหตุฉุกเฉิน';
