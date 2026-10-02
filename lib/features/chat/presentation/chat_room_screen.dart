import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure_messages.dart';
import '../../../core/error/result.dart';
import '../../../core/l10n/strings_p4.dart';
import '../../../core/l10n/strings_r5.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/role_badge.dart';
import '../../../core/widgets/state_view.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../avatar/presentation/avatar_screens.dart';
import '../../avatar/presentation/user_avatar.dart';
import '../../matching/domain/match_models.dart';
import '../../matching/presentation/matching_providers.dart';
import '../../matching/presentation/matching_widgets.dart';
import '../../safety/presentation/safety_providers.dart';
import '../../safety/presentation/sos_widgets.dart';
import '../../trip/presentation/trip_lifecycle_providers.dart';
import '../../vehicle/presentation/vehicle_providers.dart';
import '../../vehicle/presentation/vehicle_widgets.dart';
import '../domain/chat_models.dart';
import '../domain/quick_voice.dart';
import 'audio_note_button.dart';
import 'chat_providers.dart';
import 'quick_voice_providers.dart';

/// S-18: per-match chat. Sending is gated by `chat_state`; anything other
/// than `open` turns the composer into a read-only banner.
class ChatRoomScreen extends ConsumerStatefulWidget {
  const ChatRoomScreen({super.key, required this.matchId, this.initialText});
  final String matchId;

  /// Filled into the message box on open (never sent automatically).
  final String? initialText;

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomState();
}

class _ChatRoomState extends ConsumerState<ChatRoomScreen> {
  final _text = TextEditingController();
  String? _hint;

  @override
  void initState() {
    super.initState();
    final t = widget.initialText;
    if (t != null && t.isNotEmpty) {
      _text.text = t;
      _text.selection = TextSelection.collapsed(offset: t.length);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  MatchSummary? _match() {
    for (final m in ref.read(inboxProvider).valueOrNull ?? const <MatchSummary>[]) {
      if (m.id == widget.matchId) return m;
    }
    return null;
  }

  void _send() {
    final res = ref.read(chatRoomProvider(widget.matchId).notifier).send(_text.text);
    switch (res) {
      case SendResult.queued:
        _text.clear();
        setState(() => _hint = null);
      case SendResult.throttled:
        // Keep the text: nothing is lost, the user just waits a moment.
        setState(() => _hint = P.chatThrottled);
      case SendResult.tooLong:
        setState(() => _hint = P.chatLimit);
      case SendResult.empty || SendResult.closed:
        break;
    }
  }

  /// Z-2: the Driver never sees the Rider's drop-off, so it is agreed in chat. These are ready-made
  /// sentences that fill the message box (nothing is sent until the user presses send).
  Future<void> _pickQuickReply() async {
    final q = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final r in R5.quickReplies)
            ListTile(key: Key('quick-$r'), minTileHeight: 56, title: Text(r), onTap: () => Navigator.pop(ctx, r)),
        ]),
      ),
    );
    if (q == null || !mounted) return;
    setState(() {
      _text.text = q;
      _text.selection = TextSelection.collapsed(offset: q.length);
      _hint = null;
    });
  }

  /// US-48(B): unlike the free-text quick-reply above, a quick-voice preset is
  /// sent immediately (design-roles/requirements US-48 AC: "เมื่อกดวลี ข้อความถูกส่ง...")
  /// — it is still a completely normal chat message; only the recipient's device
  /// recognises it and reads it aloud (see `QuickVoiceTtsService`). Throttled 1/10s/match (Q16).
  Future<void> _pickQuickVoice() async {
    final throttle = ref.read(quickVoiceThrottleProvider);
    if (!throttle.canSend(widget.matchId)) {
      setState(() => _hint = 'ส่งวลีเสียงด่วนถี่เกินไป ลองใหม่อีกครั้งในอีกสักครู่');
      return;
    }
    final phrase = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final p in QuickVoicePresets.phrases)
            ListTile(key: Key('quick-voice-$p'), minTileHeight: 56, title: Text(p), onTap: () => Navigator.pop(ctx, p)),
        ]),
      ),
    );
    if (phrase == null || !mounted) return;
    final res = ref.read(chatRoomProvider(widget.matchId).notifier).send(phrase);
    if (res == SendResult.queued) throttle.recordSent(widget.matchId);
  }

  Future<void> _block(MatchSummary m) async {
    final partnerId = m.partnerId;
    if (partnerId == null) return;
    final ok = await showConfirmDialog(
      context,
      title: P.chatBlockTitle,
      body: P.chatBlockBody,
      safeLabel: P.chatBlockKeep,
      confirmLabel: P.chatBlockConfirm,
    );
    if (!ok || !mounted) return;
    final res = await ref.read(safetyRepositoryProvider).block(partnerId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.when(ok: (_) => P.chatBlocked, err: failureMessage))));
    if (res is Ok) {
      // Chat turns read-only for both sides and sharing to this partner stops.
      await ref.read(chatRoomProvider(widget.matchId).notifier).refreshState();
      ref
        ..invalidate(sharingPartnersProvider)
        ..invalidate(blockedUsersProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = ref.watch(chatRoomProvider(widget.matchId));
    final inbox = ref.watch(inboxProvider);
    final m = _match();
    final name = m?.displayName ?? 'แชท';
    final myUid = ref.watch(authUserProvider).valueOrNull?.id;

    return Scaffold(
      appBar: AppBar(
        // Tapping the header opens the match detail (badges, meeting point).
        title: InkWell(
          key: const Key('chat-header'),
          onTap: m == null ? null : () => context.push(Routes.match(m.id)),
          child: Row(children: [
            if (m != null)
              UserAvatar.partner(
                name: name,
                matchId: m.id,
                size: 40,
                onTap: m.partnerId == null
                    ? null
                    : () => showPartnerPhotoSheet(context,
                        matchId: m.id, partnerId: m.partnerId!, name: name, role: m.partnerRole),
              )
            else
              AvatarInitial(name: name, radius: 20),
            const SizedBox(width: AppSpacing.sm),
            Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
          ]),
        ),
        actions: [
          SosMiniButton(tripId: m?.myTripId, fromChat: true),
          if (m?.partnerId != null)
            PopupMenuButton<String>(
              tooltip: 'เมนู',
              onSelected: (v) {
                if (v == 'report') {
                  context.push(Routes.report(m!.partnerId!, matchId: m.id, name: m.displayName));
                } else {
                  _block(m!);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'report', child: Text(P.chatMenuReport)),
                PopupMenuItem(value: 'block', child: Text(P.chatMenuBlock)),
              ],
            ),
        ],
      ),
      body: Column(children: [
        const _NoticeBar(),
        if (m != null && m.isCar) _CarInfoBar(match: m),
        Expanded(child: _body(room, inbox.isLoading && m == null, myUid)),
        _composer(room),
      ]),
    );
  }

  Widget _body(ChatRoomState room, bool inboxLoading, String? myUid) {
    if (room.loading && room.messages.isEmpty) return const StateView.loading();
    if (room.loadError != null && room.messages.isEmpty) {
      return StateView.failure(room.loadError!, onRetry: () => ref.read(chatRoomProvider(widget.matchId).notifier).load());
    }
    if (room.messages.isEmpty) {
      return const StateView.empty(icon: Icons.chat_bubble_outline, title: P.chatEmpty);
    }
    final items = room.messages.reversed.toList(); // newest first, list is reversed
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(AppSpacing.pageH),
      itemCount: items.length + (room.hasMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == items.length) {
          return TextButton(
            onPressed: room.loadingMore ? null : () => ref.read(chatRoomProvider(widget.matchId).notifier).loadOlder(),
            child: Text(room.loadingMore ? 'กำลังโหลด...' : P.chatLoadOlder),
          );
        }
        final msg = items[i];
        return _Bubble(
          message: msg,
          mine: !msg.isSystem && msg.senderId == myUid,
          onRetry: msg.status == SendStatus.failed
              ? () {
                  final r = ref.read(chatRoomProvider(widget.matchId).notifier).retry(msg.clientMsgId!);
                  if (r == SendResult.throttled) setState(() => _hint = P.chatThrottled);
                }
              : null,
        );
      },
    );
  }

  Widget _composer(ChatRoomState room) {
    if (!room.loading && !room.chatState.canSend) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: SizedBox(
            width: double.infinity,
            child: AppCard(
              tone: AppCardTone.warning,
              child: Row(children: [
                Icon(Icons.lock_outline, color: context.tone.warningInk),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text(room.chatState.readOnlyBanner, key: const Key('chat-readonly'))),
              ]),
            ),
          ),
        ),
      );
    }
    final len = _text.text.trim().length;
    final remaining = chatMaxLength - _text.text.length;
    final over = _text.text.length > chatMaxLength;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_hint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(_hint!, style: TextStyle(color: context.tone.dangerInk)),
            ),
          if (_match()?.isCar ?? false)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Wrap(spacing: AppSpacing.xs, children: [
                  ActionChip(
                    key: const Key('chat-quick-replies'),
                    avatar: const Icon(Icons.flash_on_outlined, size: 18),
                    label: const Text(R5.quickTitle),
                    onPressed: _pickQuickReply,
                  ),
                  ActionChip(
                    key: const Key('chat-quick-voice'),
                    avatar: const Icon(Icons.record_voice_over_outlined, size: 18),
                    label: const Text('วลีเสียงด่วน'),
                    onPressed: _pickQuickVoice,
                  ),
                  ActionChip(
                    key: const Key('chat-audio-note'),
                    avatar: const Icon(Icons.mic_none_outlined, size: 18),
                    label: const Text('บันทึกเสียงสั้น'),
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      builder: (_) => const Padding(
                        padding: EdgeInsets.all(AppSpacing.xl),
                        child: AudioNoteButton(),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                controller: _text,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: P.chatHint,
                  counterText: remaining < 100 ? '${_text.text.length}/$chatMaxLength' : '',
                  counterStyle: TextStyle(color: over ? context.tone.dangerInk : context.tone.textSecondary),
                ),
                onChanged: (_) => setState(() => _hint = null),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filled(
              tooltip: P.chatSend,
              onPressed: (len == 0 || over || room.loading) ? null : _send,
              icon: const Icon(Icons.send),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _NoticeBar extends StatelessWidget {
  const _NoticeBar();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: context.tone.primaryTint,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH, vertical: AppSpacing.sm),
        child: const Text(P.chatNotice, textAlign: TextAlign.center),
      );
}

String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// C-16.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine, this.onRetry});
  final ChatMessage message;
  final bool mine;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Center(
          child: Text(
            message.displayText,
            style: theme.textTheme.bodyMedium?.copyWith(color: context.tone.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final failed = message.status == SendStatus.failed;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: mine ? context.tone.primaryTint : context.tone.surface,
        border: mine ? null : Border.all(color: context.tone.border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message.body),
          const SizedBox(height: 2),
          Text(
            failed
                ? P.chatSendFailed
                : message.status == SendStatus.sending
                    ? P.chatSending
                    : _hhmm(message.createdAt),
            style: theme.textTheme.bodySmall?.copyWith(color: failed ? context.tone.dangerInk : context.tone.textSecondary),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (failed) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.error, color: context.tone.dangerInk, size: 20)),
          Flexible(child: onRetry == null ? bubble : InkWell(onTap: onRetry, child: bubble)),
        ],
      ),
    );
  }
}


/// S-18 (car): partner's role, the vehicle for a matched Rider (collapsible, so
/// the plate is not on screen unless asked for) and the agreed pickup point.
/// When the match ended before boarding the vehicle row is gone.
class _CarInfoBar extends ConsumerWidget {
  const _CarInfoBar({required this.match});
  final MatchSummary match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = match;
    final accepted = m.status == MatchStatus.accepted;
    final showVehicle = m.iAmRider && (accepted || (m.boarded && m.status == MatchStatus.cancelled));
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, AppSpacing.xs, AppSpacing.pageH, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (m.partnerRole != null) RoleRow(m.partnerRole!),
        if (showVehicle)
          ExpansionTile(
            key: const Key('chat-vehicle-tile'),
            tilePadding: EdgeInsets.zero,
            title: const Text(R.showVehicle),
            children: [
              ref.watch(matchVehicleProvider(m.id)).when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => VehicleLoadError(onRetry: () => ref.invalidate(matchVehicleProvider(m.id))),
                    data: (v) => v == null ? const SizedBox.shrink() : VehicleInfoCard.forRider(v, compact: true),
                  ),
            ],
          ),
        if (accepted && m.meetingPoint != null)
          InkWell(
            key: const Key('chat-pickup-row'),
            onTap: () => context.push(Routes.match(m.id)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text('${R.pickupTitle}: ${m.meetingLabel ?? ''}'),
            ),
          ),
      ]),
    );
  }
}
