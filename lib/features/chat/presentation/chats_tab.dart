import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/l10n/strings_p4.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/state_view.dart';
import '../../avatar/presentation/user_avatar.dart';
import '../../matching/domain/match_models.dart';
import '../../matching/presentation/matching_providers.dart';
import '../../roles/presentation/role_strip.dart';
import '../../trip/domain/trip.dart' show TripRole;
import '../../trip/domain/trip_form.dart';
import '../domain/chat_models.dart';
import 'chat_providers.dart';

/// S-17: accepted matches with the latest message and an unread dot.
/// Tapping opens the chat room; the match detail is one tap further.
///
/// Round 9 (US-3/T5, RC-8 BorderlessChatRow): borderless rows separated by a hairline
/// divider instead of one `Card` per row — same data/actions/keys as before, chrome only.
class ChatsTab extends ConsumerWidget {
  const ChatsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(inboxProvider);
    final latest = ref.watch(chatInboxProvider).valueOrNull ?? const <String, ChatMessage>{};
    final unread = ref.watch(unreadMatchIdsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(P.chatsTitle)),
      body: withRoleStrip(inbox.when(
        loading: () => const StateView.loading(),
        error: (e, _) => StateView.failure(
          e is AppFailure ? e : const AppFailure(FailureCode.unknown),
          onRetry: () => ref.invalidate(inboxProvider),
        ),
        data: (all) {
          final matched = all.where((m) => m.status == MatchStatus.accepted).toList();
          return RefreshIndicator(
            onRefresh: () => ref.read(inboxProvider.notifier).refresh(),
            child: matched.isEmpty
                ? ListView(children: const [
                    SizedBox(height: AppSpacing.xxl),
                    StateView.empty(
                      icon: Icons.chat_bubble_outline,
                      title: P.chatsEmpty,
                      message: P.chatsEmptyBody,
                    ),
                  ])
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH, vertical: AppSpacing.sm),
                    itemCount: matched.length,
                    separatorBuilder: (context, _) => Divider(height: 1, color: context.tone.border),
                    itemBuilder: (_, i) {
                      final m = matched[i];
                      final last = latest[m.id];
                      final hasUnread = unread.contains(m.id);
                      final subtitle = last != null
                          ? last.displayText
                          : (m.mode != null && m.departAt != null
                              ? '${m.mode!.label} · ${formatDeparture(m.departAt!, DateTime.now())}'
                              : P.noMessagesYet);
                      return _ChatRow(
                        match: m,
                        subtitle: subtitle,
                        hasUnread: hasUnread,
                        time: last == null ? null : _shortTime(last.createdAt),
                        onTap: () => context.push(Routes.chat(m.id)),
                      );
                    },
                  ),
          );
        },
      )),
    );
  }
}

/// "14:32" today, "เมื่อวาน" yesterday, "DD/MM" otherwise — short enough for the trailing slot.
String _shortTime(DateTime t) {
  final now = DateTime.now();
  final local = t.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  if (day == today) return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  if (today.difference(day).inDays == 1) return 'เมื่อวาน';
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
}

/// RC-8 BorderlessChatRow: 56dp avatar (+ small car badge when the partner is a Driver),
/// bold name, subtitle 1-line ellipsis, time top-right, unread dot (same `unread-<id>` key
/// and red-dot chrome as before — `unreadMatchIdsProvider` is a `Set<String>` with no
/// per-chat count, so a dot is all the real data supports, per the round9 design spec).
class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.match, required this.subtitle, required this.hasUnread, required this.time, required this.onTap});
  final MatchSummary match;
  final String subtitle;
  final bool hasUnread;
  final String? time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final isDriver = match.partnerRole == TripRole.driver;
    return Semantics(
      container: true,
      label: '${P.chatsTitle} กับ ${match.displayName}${hasUnread ? ', มีข้อความใหม่' : ''}, $subtitle${time != null ? ', $time' : ''}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    UserAvatar.partner(name: match.displayName, matchId: match.id, size: 56),
                    if (isDriver)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          key: const Key('chat-driver-badge'),
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(color: tone.primary, shape: BoxShape.circle, border: Border.all(color: tone.surface, width: 2)),
                          child: Icon(Icons.directions_car, size: 12, color: tone.onPrimary),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              match.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (time != null) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Text(time!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tone.textSecondary)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: tone.textSecondary,
                                    fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w400,
                                  ),
                            ),
                          ),
                          if (hasUnread) ...[
                            const SizedBox(width: AppSpacing.xs),
                            Semantics(
                              label: P.unreadDot,
                              child: Container(
                                key: Key('unread-${match.id}'),
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
