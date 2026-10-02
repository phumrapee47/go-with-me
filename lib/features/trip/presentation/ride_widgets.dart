import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/result.dart';
import '../../../core/l10n/strings_p4.dart';
import '../../../core/l10n/strings_r5.dart';
import '../../../core/l10n/strings_r6.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../chat/domain/chat_models.dart';
import '../../chat/domain/thank_you_sticker.dart';
import '../../chat/presentation/chat_providers.dart';
import '../../matching/domain/match_models.dart';
import '../../matching/presentation/matching_providers.dart';
import '../../reviews/presentation/review_providers.dart';
import '../../reviews/presentation/review_widgets.dart';
import '../../safety/presentation/sos_widgets.dart';
import '../domain/ride_logic.dart';
import '../domain/shared_impact.dart';
import '../domain/trip.dart';
import '../domain/trip_form.dart';
import 'trip_lifecycle_providers.dart' show acceptedPartnersOf;

/// F-3: back, "text view" pill and SOS above the map and above the sheet at EVERY level.
/// Position does not depend on the sheet, so nothing can cover it (US-30).
class RideTopOverlay extends StatelessWidget {
  const RideTopOverlay({super.key, required this.onBack, required this.onTextView, this.tripId, this.showSos = true});
  final VoidCallback onBack;
  final VoidCallback onTextView;
  final String? tripId;
  final bool showSos;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    final tone = context.tone;
    Widget round(Widget child) => Material(color: tone.surface, shape: const CircleBorder(), elevation: 3, child: child);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Reading order: back, then SOS (F.11), then the rest.
            Semantics(
              sortKey: const OrdinalSortKey(0),
              child: round(
                IconButton(
                  key: const Key('ride-back'),
                  tooltip: R6.back,
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.arrow_back),
                  onPressed: onBack,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  sortKey: const OrdinalSortKey(2),
                  child: compact
                      ? round(
                          IconButton(
                            key: const Key('ride-text-view'),
                            tooltip: R5.textAltOpen,
                            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                            icon: const Icon(Icons.notes),
                            onPressed: onTextView,
                          ),
                        )
                      : Material(
                          color: tone.surface,
                          elevation: 3,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          child: InkWell(
                            key: const Key('ride-text-view'),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            onTap: onTextView,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.notes, size: 20),
                                  const SizedBox(width: AppSpacing.xs),
                                  Flexible(
                                    child: Text(
                                      R5.textAltOpen,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.labelLarge,
                                    ),
                                  ),
                                ]),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            if (showSos)
              Semantics(
                sortKey: const OrdinalSortKey(1),
                child: Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm),
                  // SosMiniButton keeps its own right padding (spacing to the screen edge).
                  child: SosMiniButton(key: const Key('ride-sos'), tripId: tripId),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum PickupButtonPhase { ready, sending, cooldown, disabled }

/// F-6 (US-33, Driver only): one tap tells the Rider "คนขับมารอที่จุดรับแล้วนะ" through the existing
/// chat. No slider (it is not an irreversible status change), no coordinates.
class ArrivedAtPickupButton extends StatelessWidget {
  const ArrivedAtPickupButton({
    super.key,
    required this.phase,
    required this.onPressed,
    this.secondsLeft = 0,
    this.disabledReason,
  });
  final PickupButtonPhase phase;
  final VoidCallback onPressed;
  final int secondsLeft;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final theme = Theme.of(context);
    final sent = phase == PickupButtonPhase.cooldown;
    final enabled = phase == PickupButtonPhase.ready;
    final label = sent ? R6.arrivedAtPickupSent : R6.arrivedAtPickupButton;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          enabled: enabled,
          label: R6.arrivedAtPickupSemantics,
          value: sent ? R6.arrivedAtPickupSentAnnounce : null,
          excludeSemantics: true,
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            height: 56,
            child: FilledButton.icon(
              key: const Key('arrived-at-pickup'),
              style: FilledButton.styleFrom(
                backgroundColor: tone.primary,
                foregroundColor: tone.onPrimary,
                disabledBackgroundColor: tone.border,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: enabled ? onPressed : null,
              icon: phase == PickupButtonPhase.sending
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: tone.onPrimary))
                  : Icon(sent ? Icons.check : Icons.pin_drop_outlined),
              label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
        ),
        if (sent)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Semantics(
              liveRegion: true,
              child: Text(
                R6.arrivedAtPickupCooldown(secondsLeft),
                key: const Key('arrived-at-pickup-cooldown'),
                style: theme.textTheme.bodyMedium?.copyWith(color: tone.textSecondary),
              ),
            ),
          )
        else if (phase == PickupButtonPhase.disabled && disabledReason != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              disabledReason!,
              key: const Key('arrived-at-pickup-reason'),
              style: theme.textTheme.bodyMedium?.copyWith(color: tone.textSecondary),
            ),
          ),
      ],
    );
  }
}

/// C-35: agreed pickup (with a tick) or a way to agree one.
class RidePickupCard extends StatelessWidget {
  const RidePickupCard({super.key, required this.match});
  final MatchSummary match;

  @override
  Widget build(BuildContext context) {
    final m = match;
    final theme = Theme.of(context);
    if (m.meetingPoint != null) {
      return AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(children: [
          Icon(Icons.check_circle, color: context.tone.successInk),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(R6.pickupCardTitle, style: theme.textTheme.labelLarge),
              Text(R.pickupAgreed(m.meetingLabel ?? ''), key: const Key('active-pickup')),
              Text(R6.pickupAgreedTag, style: theme.textTheme.bodySmall?.copyWith(color: context.tone.textSecondary)),
            ]),
          ),
        ]),
      );
    }
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(R6.pickupCardTitle, style: theme.textTheme.labelLarge),
        const Text(R6.pickupNotSet, key: Key('pickup-not-set')),
        // The way to agree a pickup is the navigation button's link right below (US-24), not repeated here.
      ]),
    );
  }
}

/// Chat inside the Full sheet: the same rooms, messages, gating and throttle as S-18.
/// The text lives in a controller owned by the screen, so it survives sheet level changes.
class RideChatSection extends ConsumerStatefulWidget {
  const RideChatSection({super.key, required this.match, required this.text, this.maxMessages = 20});
  final MatchSummary match;
  final TextEditingController text;
  final int maxMessages;

  @override
  ConsumerState<RideChatSection> createState() => _RideChatState();
}

class _RideChatState extends ConsumerState<RideChatSection> {
  String? _hint;

  void _send() {
    final res = ref.read(chatRoomProvider(widget.match.id).notifier).send(widget.text.text);
    setState(() {
      switch (res) {
        case SendResult.queued:
          widget.text.clear();
          _hint = null;
        case SendResult.throttled:
          _hint = P.chatThrottled;
        case SendResult.tooLong:
          _hint = P.chatLimit;
        case SendResult.empty || SendResult.closed:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final room = ref.watch(chatRoomProvider(widget.match.id));
    final myUid = ref.watch(authUserProvider).valueOrNull?.id;
    final theme = Theme.of(context);
    final tone = context.tone;
    final msgs = room.messages.length > widget.maxMessages
        ? room.messages.sublist(room.messages.length - widget.maxMessages)
        : room.messages;
    final canSend = room.chatState.canSend;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(R6.chatSection, style: theme.textTheme.titleMedium),
      const SizedBox(height: AppSpacing.sm),
      if (room.loading && msgs.isEmpty)
        const Padding(padding: EdgeInsets.all(AppSpacing.md), child: Center(child: CircularProgressIndicator()))
      else if (msgs.isEmpty)
        Text(R6.chatEmpty, key: const Key('ride-chat-empty'), style: TextStyle(color: tone.textSecondary))
      else
        for (final m in msgs) _bubble(context, m, mine: !m.isSystem && m.senderId == myUid),
      const SizedBox(height: AppSpacing.sm),
      if (!room.loading && !canSend)
        AppCard(
          tone: AppCardTone.warning,
          child: Row(children: [
            Icon(Icons.lock_outline, color: tone.warningInk),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(room.chatState.readOnlyBanner, key: const Key('ride-chat-readonly'))),
          ]),
        )
      else ...[
        if (_hint != null) Text(_hint!, style: TextStyle(color: tone.dangerInk)),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: TextField(
              key: const Key('ride-chat-input'),
              controller: widget.text,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(hintText: P.chatHint),
              onChanged: (_) => setState(() => _hint = null),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton.filled(
            key: const Key('ride-chat-send'),
            tooltip: P.chatSend,
            onPressed: (widget.text.text.trim().isEmpty || room.loading) ? null : _send,
            icon: const Icon(Icons.send),
          ),
        ]),
      ],
      TextButton(
        key: const Key('ride-open-chat'),
        style: TextButton.styleFrom(minimumSize: const Size(0, AppSpacing.minTap)),
        onPressed: () => context.push(Routes.chat(widget.match.id)),
        child: const Text(R5.liveChat),
      ),
    ]);
  }

  Widget _bubble(BuildContext context, ChatMessage m, {required bool mine}) {
    final tone = context.tone;
    final theme = Theme.of(context);
    if (m.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Center(
          child: Text(m.body, textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: tone.textSecondary)),
        ),
      );
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        decoration: BoxDecoration(
          color: mine ? tone.selectedFill : tone.surfaceRaised,
          border: mine ? null : Border.all(color: tone.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(m.body, style: TextStyle(color: mine ? tone.onSelectedFill : tone.text)),
      ),
    );
  }
}

/// F-6b: arrived summary (state 5). Same review offer as the old S-22 page: once as a sheet,
/// plus a card that can be hidden with "later".
class ArrivedSummary extends ConsumerStatefulWidget {
  const ArrivedSummary({super.key, required this.trip, required this.homeMatch});
  final Trip trip;
  final HomeMatch homeMatch;

  @override
  ConsumerState<ArrivedSummary> createState() => _ArrivedSummaryState();
}

class _ArrivedSummaryState extends ConsumerState<ArrivedSummary> {
  bool _hideCard = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final inbox = await ref.read(inboxProvider.future).catchError((_) => const <MatchSummary>[]);
      if (!mounted) return;
      final m = reviewableMatchFor(inbox, widget.trip.id);
      if (m != null) await maybeShowReviewSheet(context, ref, m);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trip = widget.trip;
    final inbox = ref.watch(inboxProvider).valueOrNull ?? const <MatchSummary>[];
    final reviewMatch = reviewableMatchFor(inbox, trip.id);
    final took = (trip.startedAt != null && trip.endedAt != null) ? trip.endedAt!.difference(trip.startedAt!) : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: const BoxDecoration(color: AppColors.mint, shape: BoxShape.circle),
          child: const Icon(Icons.check_circle, size: 56, color: AppColors.green),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      Semantics(
        header: true,
        liveRegion: true,
        label: arrivedMessageSemantics(widget.homeMatch),
        excludeSemantics: true,
        child: Text(
          arrivedMessage(widget.homeMatch),
          key: const Key('arrived-title'),
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(P.arrivedBody, key: const Key('arrived-body'), textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
      if (took != null || trip.distanceM > 0) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(
          [
            if (took != null) 'ใช้เวลา ${took.inMinutes} นาที',
            if (trip.distanceM > 0) formatRouteSummary(trip.distanceM, trip.durationS),
          ].join(' · '),
          textAlign: TextAlign.center,
        ),
      ],
      if (reviewMatch != null && !_hideCard) ...[
        const SizedBox(height: AppSpacing.md),
        ReviewPromptCard(match: reviewMatch, onLater: () => setState(() => _hideCard = true)),
      ],
      _SharedImpactSection(trip: trip, inbox: inbox),
      const SizedBox(height: AppSpacing.lg),
      AppButton(key: const Key('arrived-home'), label: P.backHome, onPressed: () => context.go(Routes.home)),
    ]);
  }
}

/// US-47 (round 7 Stage C): CO2 card + "thank-you sticker" row. Only shown when there is a friend to
/// thank — an ACCEPTED match on this trip (car or peer); a solo trip, a match that never got
/// accepted, or one cancelled/blocked before arrival shows nothing here (AC: "ไม่แสดงส่วนเพื่อนเมื่อ
/// ทริปไม่มีคู่ตอบรับ/ยกเลิกก่อนถึง/บล็อกกันแล้ว").
class _SharedImpactSection extends StatelessWidget {
  const _SharedImpactSection({required this.trip, required this.inbox});
  final Trip trip;
  final List<MatchSummary> inbox;

  @override
  Widget build(BuildContext context) {
    final partner = acceptedPartnersOf(inbox, trip.id).firstOrNull;
    if (partner == null) return const SizedBox.shrink();
    final kg = co2KgFor(trip.distanceM);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (kg != null) SharedImpactCard(partnerName: partner.displayName, co2Kg: kg),
        const SizedBox(height: AppSpacing.md),
        ThankYouStickerRow(matchId: partner.id),
      ]),
    );
  }
}

/// "คุณและ [ชื่อเล่นเพื่อน] ร่วมกันลดก๊าซคาร์บอนไดออกไซด์ไป ~X kg CO2 ในการเดินทางครั้งนี้!"
/// + "(โดยประมาณ)" label + a one-line disclaimer footnote (Q9, PM confirmed — not a scientific/legal
/// claim, just an inspiration number).
class SharedImpactCard extends StatelessWidget {
  const SharedImpactCard({super.key, required this.partnerName, required this.co2Kg});
  final String partnerName;
  final double co2Kg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      key: const Key('shared-impact-card'),
      tone: AppCardTone.info,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.eco_outlined),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'คุณและ $partnerName ร่วมกันลดก๊าซคาร์บอนไดออกไซด์ไป ${formatCo2Kg(co2Kg)} CO₂ ในการเดินทางครั้งนี้!',
              key: const Key('shared-impact-text'),
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ]),
        const SizedBox(height: AppSpacing.xs),
        Text('(โดยประมาณ)', key: const Key('shared-impact-approx'), style: theme.textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'ตัวเลขนี้เป็นค่าประมาณเพื่อสร้างแรงบันดาลใจ ไม่ใช่ค่าที่รับรองทางวิทยาศาสตร์',
          key: const Key('shared-impact-disclaimer'),
          style: theme.textTheme.bodySmall?.copyWith(color: context.tone.textSecondary),
        ),
      ]),
    );
  }
}

/// US-47: fixed thank-you-sticker presets, reusing the EXISTING chat send path (US-8/US-24 pattern —
/// no new message `kind`, no free-text entry).
class ThankYouStickerRow extends ConsumerStatefulWidget {
  const ThankYouStickerRow({super.key, required this.matchId});
  final String matchId;

  @override
  ConsumerState<ThankYouStickerRow> createState() => _ThankYouStickerRowState();
}

class _ThankYouStickerRowState extends ConsumerState<ThankYouStickerRow> {
  String? _sentText;
  bool _sending = false;

  Future<void> _send(String text) async {
    if (_sending) return;
    setState(() => _sending = true);
    final res = await ref.read(chatRepositoryProvider).send(widget.matchId, text, UniqueKey().toString());
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (res is Ok) _sentText = text;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('ส่งสติกเกอร์ขอบคุณ', style: theme.textTheme.labelLarge),
      const SizedBox(height: AppSpacing.xs),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          for (final t in ThankYouStickerPresets.messages)
            ActionChip(
              key: Key('sticker-$t'),
              label: Text(t),
              avatar: _sentText == t ? const Icon(Icons.check, size: 16) : null,
              onPressed: _sending ? null : () => _send(t),
            ),
        ],
      ),
    ]);
  }
}
