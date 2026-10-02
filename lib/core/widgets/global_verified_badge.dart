import 'package:flutter/material.dart';

import '../../features/matching/domain/match_models.dart';
import '../theme/tokens.dart';
import '../theme/tone.dart';

/// Round 9 (US-6/T2, RC-4): single merged "verified" badge shown everywhere a
/// [VerificationBadge] list used to be rendered one-by-one. Organization/institution
/// badges (`kind == 'organization'`) are ALWAYS filtered out here and never reach the
/// screen (US-6 AC) — this is a presentation-layer filter only, `verifications`/
/// `org_domains` and `parseBadges()` themselves are untouched.
///
/// PM ruling (design-spec-round9.md, ประเด็น 5): unlike the draft RC-4, "no email/phone
/// badge at all" is NOT silent — it shows a neutral "ยังไม่ยืนยันตัวตน" (not-verified,
/// grey/neutral tone, never red) state, same as the old `BadgeWrap` behaviour. This does
/// not fake a verified status (still no "✓ ยืนยันตัวตนแล้ว" shown), it just keeps telling
/// the truth instead of going blank.
class GlobalVerifiedBadge extends StatelessWidget {
  const GlobalVerifiedBadge(this.badges, {super.key, this.onGlass = false, this.loading = false});

  final List<VerificationBadge> badges;

  /// US-1: badge sits on top of a photo/gradient — use a frosted-glass chrome
  /// instead of the normal tone-tinted pill so it reads on any photo colour.
  final bool onGlass;

  /// Edge case only (RC-4 "hidden" state): data not loaded yet — render nothing
  /// rather than a possibly-wrong "not verified" flash. NOT used for "no badges".
  final bool loading;

  static bool isVerified(List<VerificationBadge> badges) =>
      badges.any((b) => b.kind == 'email' || b.kind == 'phone');

  @override
  Widget build(BuildContext context) {
    if (loading) return const SizedBox.shrink();
    final verified = isVerified(badges);
    final tone = context.tone;
    final bg = onGlass
        ? Colors.white.withValues(alpha: 0.22)
        : (verified ? tone.primaryTint : tone.surfaceRaised);
    final fg = onGlass ? Colors.white : (verified ? tone.primaryInk : tone.textSecondary);
    final label = verified ? 'ยืนยันตัวตนแล้ว' : 'ยังไม่ยืนยันตัวตน';
    return Semantics(
      label: verified ? 'ยืนยันตัวตนแล้ว ด้วยอีเมลหรือเบอร์โทร' : 'ยังไม่ยืนยันตัวตน',
      excludeSemantics: true,
      child: Container(
        key: const Key('global-verified-badge'),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(verified ? Icons.verified_outlined : Icons.help_outline, size: 16, color: fg),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg)),
            ),
          ],
        ),
      ),
    );
  }
}
