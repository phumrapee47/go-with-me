import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/l10n/strings_r6_cd.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/l10n/strings_trip.dart';
import '../../../core/map/app_map.dart';
import '../../../core/providers.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/global_verified_badge.dart';
import '../../../core/widgets/initials_avatar.dart' show avatarInitial;
import '../../../core/widgets/role_badge.dart';
import '../../../core/widgets/state_view.dart';
import '../../trip/domain/trip.dart';
import '../../trip/domain/trip_form.dart';
import '../../trip/presentation/vibe_mood_widgets.dart';
import '../domain/match_models.dart';
import 'deck_controller.dart';
import 'matching_providers.dart';
import 'no_match_hint.dart';

const _coachKey = 'gwm.deckCoachSeen';

/// F-7: one big card at a time. Swipe right / heart = invite now (undo window), swipe left / X = skip.
class CommuteCardDeck extends ConsumerStatefulWidget {
  const CommuteCardDeck({super.key, required this.trip, required this.items});
  final Trip trip;
  final List<MatchCandidate> items;

  @override
  ConsumerState<CommuteCardDeck> createState() => _CommuteCardDeckState();
}

class _CommuteCardDeckState extends ConsumerState<CommuteCardDeck> {
  final _cardKey = GlobalKey<DeckSwipeCardState>();
  bool _coachSeen = false;

  @override
  void initState() {
    super.initState();
    _coachSeen = ref.read(sharedPrefsProvider).getBool(_coachKey) ?? false;
  }

  void _seenCoach() {
    if (_coachSeen) return;
    setState(() => _coachSeen = true);
    ref.read(sharedPrefsProvider).setBool(_coachKey, true);
  }

  int _outgoing() => outgoingPendingCount(
    ref.read(inboxProvider).valueOrNull ?? const <MatchSummary>[],
    widget.trip.id,
  );

  void _skip(MatchCandidate c, List<MatchCandidate> cards) {
    _seenCoach();
    final next = cards.length > 1 ? cards[1].displayName : null;
    ref.read(deckProvider.notifier).skip(c, nextName: next);
  }

  void _flingOr({required bool right, required VoidCallback fallback}) {
    final st = _cardKey.currentState;
    if (st == null) {
      fallback();
    } else {
      st.fling(right: right);
    }
  }

  void _invite(MatchCandidate c) {
    _seenCoach();
    final window = MediaQuery.accessibleNavigationOf(context) ? 8 : 5;
    ref.read(deckProvider.notifier).invite(c, windowSeconds: window);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(deckProvider);
    final inbox =
        ref.watch(inboxProvider).valueOrNull ?? const <MatchSummary>[];
    final cards = deckCards(widget.items, widget.trip, s);
    final capActive = deckCapActive(
      s,
      outgoingPendingCount(inbox, widget.trip.id),
    );
    final now = DateTime.now();
    final theme = Theme.of(context);

    Widget area;
    if (widget.items.isEmpty) {
      area = _Empty(trip: widget.trip);
    } else if (cards.isEmpty) {
      area = _EndOfDeck(
        sent: s.sentCount,
        onRefresh: () {
          ref.read(deckProvider.notifier).resetSkipped();
          ref.read(nearbyProvider.notifier).refresh(force: true);
        },
      );
    } else {
      final c = cards.first;
      area = Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.pageH,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.trip.mode.label} · ${formatDeparture(widget.trip.departAt, now)}',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    R6C.counter(s.decided + 1, s.decided + cards.length),
                    key: const Key('deck-counter'),
                    style: theme.textTheme.labelLarge,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                // The next card peeks out behind (no content: nothing leaks).
                if (cards.length > 1)
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        0,
                        AppSpacing.xl,
                        0,
                      ),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: 0.97,
                          child: DecoratedBox(
                            key: const Key('deck-shadow-card'),
                            decoration: BoxDecoration(
                              color: context.tone.surfaceRaised,
                              borderRadius: AppShape.cardRadius,
                              boxShadow: context.tone.cardShadowPressed,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pageH,
                    0,
                    AppSpacing.pageH,
                    AppSpacing.sm,
                  ),
                  child: DeckSwipeCard(
                    key: _cardKey,
                    cardKey: ValueKey('card-${c.tripId}'),
                    canInvite: () => ref
                        .read(deckProvider.notifier)
                        .canInvite(c, outgoingPending: _outgoing()),
                    onSkip: () => _skip(c, cards),
                    onInvite: () => _invite(c),
                    child: CommuteCard(
                      candidate: c,
                      now: now,
                      onDetail: () => context.push(Routes.candidate(c.tripId)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // The hint is decoration: it gives way at large text sizes so the card and the buttons keep the room.
        if (!_coachSeen && MediaQuery.textScalerOf(context).scale(10) <= 13)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
              child: Text(
                R6C.coach,
                key: const Key('deck-coach'),
                textAlign: TextAlign.center,
                style: TextStyle(color: context.tone.textSecondary),
              ),
            ),
          if (capActive)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageH,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Text(R6C.capBar, key: Key('deck-cap-bar')),
                  ),
                  TextButton(
                    onPressed: () => context.push(Routes.nearbyRequests),
                    child: const Text(R6C.endToRequests),
                  ),
                ],
              ),
            ),
          _ActionBar(
            onSkip: () =>
                _flingOr(right: false, fallback: () => _skip(c, cards)),
            onDetail: () => context.push(Routes.candidate(c.tripId)),
            onInvite: capActive
                ? null
                : () => _flingOr(right: true, fallback: () => _invite(c)),
          ),
        ],
      );
    }

    return Column(
      children: [
        // Hidden announcement for screen readers (skip -> next card).
        if (s.announce != null)
          Semantics(
            liveRegion: true,
            label: s.announce,
            child: const SizedBox(width: 0, height: 0),
          ),
        if (s.notice != null)
          _NoticeBar(
            text: s.notice!,
            onClose: () => ref.read(deckProvider.notifier).dismissNotice(),
          ),
        Expanded(child: area),
        if (s.banner != null) UndoBanner(invite: s.banner!),
      ],
    );
  }
}

class _NoticeBar extends StatelessWidget {
  const _NoticeBar({required this.text, required this.onClose});
  final String text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.pageH,
      AppSpacing.xs,
      AppSpacing.pageH,
      0,
    ),
    child: Container(
      key: const Key('deck-notice'),
      padding: const EdgeInsets.only(left: AppSpacing.md),
      decoration: BoxDecoration(
        color: context.tone.warningTint,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Semantics(
        liveRegion: true,
        container: true,
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: context.tone.warningInk),
              ),
            ),
            IconButton(
              tooltip: R6C.dismiss,
              onPressed: onClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Empty extends ConsumerWidget {
  const _Empty({required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      children: [
        const SizedBox(height: AppSpacing.xl),
        switch (trip.role) {
          TripRole.driver => const StateView.empty(
            icon: Icons.people_outline,
            title: R.emptyDriverTitle,
            message: R.emptyDriverBody,
          ),
          TripRole.rider => const StateView.empty(
            icon: Icons.people_outline,
            title: R.emptyRiderTitle,
            message: R.emptyRiderBody,
          ),
          null => const StateView.empty(
            icon: Icons.people_outline,
            title: T.nearbyEmpty,
            message: T.nearbyEmptyHint,
          ),
        },
        NoMatchHint(trip: trip),
      ],
    );
  }
}

class _EndOfDeck extends ConsumerWidget {
  const _EndOfDeck({required this.sent, required this.onRefresh});
  final int sent;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.pageH),
      children: [
        const SizedBox(height: AppSpacing.xl),
        const Icon(Icons.check_circle_outline, size: 64),
        const SizedBox(height: AppSpacing.md),
        Text(
          R6C.endTitle,
          key: const Key('deck-end'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (sent > 0)
          Text(
            R6C.endSummary(sent),
            key: const Key('deck-end-sent'),
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          key: const Key('deck-end-list'),
          label: R6C.endToList,
          onPressed: () =>
              ref.read(nearbyViewProvider.notifier).set(NearbyView.list),
        ),
        AppButton(
          key: const Key('deck-end-requests'),
          label: R6C.endToRequests,
          variant: AppButtonVariant.secondary,
          onPressed: () => context.push(Routes.nearbyRequests),
        ),
        AppButton(
          key: const Key('deck-end-refresh'),
          label: R6C.endRefresh,
          variant: AppButtonVariant.text,
          onPressed: onRefresh,
        ),
      ],
    );
  }
}

/// RC-3 CommuteActionCluster: X (64dp) / info (56dp) / heart (80dp, clearly the
/// biggest — AC "ใหญ่เด่นกว่าปุ่มอื่นอย่างชัดเจน") as floating circles. Same
/// callbacks/semantics labels as the old `_ActionBar` text-link version — only the
/// chrome changed (round 9 US-1/T3; PM ruling ประเด็น 2: ℹ️ still pushes the full
/// detail page, it does not open a bottom sheet).
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.onSkip,
    required this.onDetail,
    required this.onInvite,
  });
  final VoidCallback? onSkip;
  final VoidCallback onDetail;
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageH,
          AppSpacing.xs,
          AppSpacing.pageH,
          AppSpacing.lg,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Semantics(
              button: true,
              label: R6C.skip,
              excludeSemantics: true,
              onTap: onSkip,
              child: SizedBox(
                width: 64,
                height: 64,
                child: OutlinedButton(
                  key: const Key('deck-skip'),
                  style: OutlinedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: EdgeInsets.zero,
                    backgroundColor: tone.surface,
                    side: BorderSide(color: tone.borderStrong, width: 2),
                  ),
                  onPressed: onSkip,
                  child: Icon(Icons.close, size: 28, color: tone.text),
                ),
              ),
            ),
            Semantics(
              button: true,
              label: R6C.invite,
              excludeSemantics: true,
              onTap: onInvite,
              child: SizedBox(
                width: 80,
                height: 80,
                child: FilledButton(
                  key: const Key('deck-invite'),
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: EdgeInsets.zero,
                    backgroundColor: tone.successFill,
                    foregroundColor: tone.onSuccessFill,
                    elevation: 6,
                  ),
                  onPressed: onInvite,
                  child: const Icon(Icons.favorite, size: 36),
                ),
              ),
            ),
            Semantics(
              button: true,
              label: R6C.detailLink,
              excludeSemantics: true,
              onTap: onDetail,
              child: SizedBox(
                width: 56,
                height: 56,
                child: DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: tone.surface, boxShadow: tone.cardShadow),
                  child: IconButton(
                    key: const Key('deck-detail'),
                    onPressed: onDetail,
                    icon: Icon(Icons.info_outline, color: tone.textSecondary),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// F-10, drawn on the deck (not a SnackBar) so the timer can wait while the button has focus.
class UndoBanner extends ConsumerWidget {
  const UndoBanner({super.key, required this.invite});
  final DeckInvite invite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = invite.candidate.displayName;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final phase = invite.phase;
    final text = switch (phase) {
      InvitePhase.sending => R6C.inviting(name),
      InvitePhase.undoable || InvitePhase.confirmed => T.requestSent,
      InvitePhase.cancelling => R6C.inviting(name),
      InvitePhase.undone => R6C.undone,
      InvitePhase.blocked => invite.message ?? R6C.undoUnknown,
      InvitePhase.matched => T.requestMatchedNow,
    };
    final showUndo =
        phase == InvitePhase.sending ||
        phase == InvitePhase.undoable ||
        phase == InvitePhase.cancelling;
    final undoEnabled = phase == InvitePhase.undoable;
    final tone = context.tone;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageH,
        0,
        AppSpacing.pageH,
        AppSpacing.sm,
      ),
      child: Material(
        key: const Key('undo-banner'),
        color: tone.snackbarBg,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      label: phase == InvitePhase.undoable
                          ? R6C.announceInviting(name, invite.windowSeconds)
                          : text,
                      excludeSemantics: true,
                      child: Text(
                        text,
                        key: const Key('undo-text'),
                        style: TextStyle(color: tone.snackbarText),
                      ),
                    ),
                  ),
                  if (showUndo)
                    Focus(
                      onFocusChange: (f) =>
                          ref.read(deckProvider.notifier).setPaused(f),
                      child: TextButton(
                        key: const Key('undo-button'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(
                            AppSpacing.minTap,
                            AppSpacing.minTap,
                          ),
                          foregroundColor: tone.snackbarText,
                        ),
                        onPressed: undoEnabled
                            ? () => ref.read(deckProvider.notifier).undo()
                            : null,
                        child: const Text(R6C.undo),
                      ),
                    ),
                ],
              ),
              if (phase == InvitePhase.undoable) ...[
                const SizedBox(height: AppSpacing.xs),
                if (reduce)
                  Text(
                    R6C.undoLeft(invite.secondsLeft),
                    key: const Key('undo-left'),
                    style: TextStyle(color: tone.snackbarText),
                  )
                else
                  LinearProgressIndicator(
                    value: invite.secondsLeft / invite.windowSeconds,
                    minHeight: 3,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Round 9 (US-1/T3): which slide of [_CommutePhotoDeck] is showing. Number of slides
/// is always data-driven (RC-1 AC: "จำนวนขีด = จำนวนภาพจริง") — avatar is always
/// present, vehicle only for a car Driver candidate, route only when `approxDest`
/// is non-null (PM ruling ประเด็น 3: nullability-driven, not role-driven).
enum _CardSlide { avatar, vehicle, route }

/// RC-1..RC-4: Tinder-style full-bleed card (vector avatar / vector vehicle / mini
/// route map, story bar, gradient info overlay). Business logic/semantics contract
/// unchanged from the old text-card version (F-8): same root `Key`, same outer
/// `Semantics` label, same `onDetail` callback (still a full-page push per PM
/// ruling ประเด็น 2, not a bottom sheet).
class CommuteCard extends StatefulWidget {
  const CommuteCard({
    super.key,
    required this.candidate,
    required this.now,
    required this.onDetail,
  });
  final MatchCandidate candidate;
  final DateTime now;
  final VoidCallback onDetail;

  /// Short driver wording on the card; the long form is on the detail page.
  static String roleText(MatchCandidate c) {
    if (c.role == TripRole.driver) {
      final d = c.maxDropoffM;
      return d == null ? R6C.seatOne : R6C.driverShortLimit(formatMetres(d));
    }
    if (c.role == TripRole.rider) return R6C.riderLine;
    return '';
  }

  @override
  State<CommuteCard> createState() => _CommuteCardState();
}

class _CommuteCardState extends State<CommuteCard> {
  int _slide = 0;

  List<_CardSlide> _slidesFor(MatchCandidate c) => [
        _CardSlide.avatar,
        if (c.role == TripRole.driver) _CardSlide.vehicle,
        if (c.approxDest != null) _CardSlide.route,
      ];

  void _go(int target, int len) {
    if (target < 0 || target >= len) return; // no-op at either end (RC-1 AC)
    setState(() => _slide = target);
  }

  @override
  void didUpdateWidget(CommuteCard old) {
    super.didUpdateWidget(old);
    if (old.candidate.tripId != widget.candidate.tripId) _slide = 0;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.candidate;
    final tone = context.tone;
    final when = formatDeparture(c.departAt, widget.now);
    final badgeText = c.badges.isEmpty ? 'บุคคลทั่วไป' : c.badges.map((b) => b.label).join(', ');
    final roleText0 = CommuteCard.roleText(c);
    final slides = _slidesFor(c);
    final idx = _slide.clamp(0, slides.length - 1);
    final reduce = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      container: true,
      label: R6C.cardSemantics(
        name: c.displayName,
        role: c.role?.label ?? c.mode.label,
        badges: badgeText,
        pct: c.overlapPct,
        when: when,
        roleText: roleText0,
      ),
      child: Container(
        key: Key('commute-card-${c.tripId}'),
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: ShapeDecoration(shape: AppShape.card(), shadows: tone.cardShadow),
        child: ExcludeSemantics(
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedSwitcher(
                duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
                child: KeyedSubtree(
                  key: ValueKey(slides[idx]),
                  child: _SlideBackground(slide: slides[idx], candidate: c),
                ),
              ),
              // Tap zones (left = previous slide, right = next); swipe-to-skip/invite
              // on the card is still handled by the outer DeckSwipeCard's pan recognizer.
              if (slides.length > 1)
                Positioned.fill(
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () => _go(idx - 1, slides.length),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () => _go(idx + 1, slides.length),
                        ),
                      ),
                    ],
                  ),
                ),
              if (slides.length > 1)
                Positioned(
                  top: AppSpacing.md,
                  left: AppSpacing.md,
                  right: AppSpacing.md,
                  child: _StoryBar(count: slides.length, index: idx),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _CommuteInfoOverlay(candidate: c, when: when, roleText: roleText0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// RC-1 CommutePhotoDeck background: one of the 3 vector slide kinds.
class _SlideBackground extends StatelessWidget {
  const _SlideBackground({required this.slide, required this.candidate});
  final _CardSlide slide;
  final MatchCandidate candidate;

  @override
  Widget build(BuildContext context) {
    switch (slide) {
      case _CardSlide.avatar:
        return _AvatarVectorSlide(name: candidate.displayName);
      case _CardSlide.vehicle:
        return const _VehicleVectorSlide();
      case _CardSlide.route:
        return _RouteSnapshotSlide(origin: candidate.approxOrigin, dest: candidate.approxDest!);
    }
  }
}

/// Photo 1 (sampoolmuha A / round9 ratify): a permanent vector fallback — no photo field
/// exists anywhere in the data model. A pastel gradient (stable per name) + the same
/// initial letter as [AvatarInitial], just full-bleed instead of a small circle.
class _AvatarVectorSlide extends StatelessWidget {
  const _AvatarVectorSlide({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final hue = (name.codeUnits.fold<int>(0, (a, b) => a + b) * 37) % 360;
    final c1 = HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.72).toColor();
    final c2 = HSLColor.fromAHSL(1, (hue + 45) % 360, 0.5, 0.48).toColor();
    return DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c1, c2])),
      child: Center(
        child: Text(
          avatarInitial(name),
          style: TextStyle(fontSize: 120, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.9)),
        ),
      ),
    );
  }
}

/// Photo 2: a minimal vector car (driver candidates only) — no vehicle photo exists.
class _VehicleVectorSlide extends StatelessWidget {
  const _VehicleVectorSlide();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2C4A78), Color(0xFF0B1B33)]),
        ),
        child: Center(child: Icon(Icons.directions_car_filled_rounded, size: 140, color: Colors.white70)),
      );
}

/// Photo 3 (RC-1): a non-interactive embedded mini map instead of a rasterised image
/// (no static-map-snapshot service in the project — reusing `AppMap` avoids adding a
/// new dependency, per tasks-round9.md T3 / PM "skip architect" ruling).
class _RouteSnapshotSlide extends StatelessWidget {
  const _RouteSnapshotSlide({required this.origin, required this.dest});
  final LatLng origin;
  final LatLng dest;

  double _zoomFor(LatLng a, LatLng b) {
    final d = const Distance().as(LengthUnit.Meter, a, b);
    if (d > 20000) return 11;
    if (d > 10000) return 12;
    if (d > 5000) return 13;
    if (d > 2000) return 14;
    if (d > 800) return 15;
    return 16;
  }

  @override
  Widget build(BuildContext context) {
    final center = LatLng((origin.latitude + dest.latitude) / 2, (origin.longitude + dest.longitude) / 2);
    return AbsorbPointer(
      child: AppMap(
        center: center,
        zoom: _zoomFor(origin, dest),
        interactive: false,
        showZoomButtons: false,
        pins: [
          MapPin(point: origin, icon: Icons.trip_origin, color: AppColors.green),
          MapPin(point: dest, icon: Icons.place, color: AppColors.danger),
        ],
      ),
    );
  }
}

/// RC-1: Instagram-style story indicator bar, one segment per real slide.
class _StoryBar extends StatelessWidget {
  const _StoryBar({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var i = 0; i < count; i++)
            Expanded(
              child: Container(
                key: Key('story-dot-$i'),
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: i <= index ? 0.95 : 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      );
}

/// RC-2 CommuteInfoOverlay: the 4 info blocks on the black gradient scrim. Height is
/// intrinsic (Column, not a fixed box) so the scrim only covers exactly the text that's
/// actually shown (AC: gradient height follows the real content).
class _CommuteInfoOverlay extends StatelessWidget {
  const _CommuteInfoOverlay({required this.candidate, required this.when, required this.roleText});
  final MatchCandidate candidate;
  final String when;
  final String roleText;

  @override
  Widget build(BuildContext context) {
    final c = candidate;
    const white = Colors.white;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0x59000000)], // ~35% black at the bottom edge
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xxl, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Block 1: name (+age is permanently omitted — no such field, round9 ประเด็น 1) + verified badge + rating.
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                Text(
                  c.displayName,
                  key: const Key('card-name'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: white, fontWeight: FontWeight.w700),
                ),
                GlobalVerifiedBadge(c.badges, onGlass: true),
                CardRatingSlot(avg: c.ratingAvg, count: c.ratingCount, color: white, align: MainAxisAlignment.start),
              ],
            ),
            // Block 2: vehicle/role info, driver-only.
            if (c.role == TripRole.driver) ...[
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                children: [
                  RoleBadge(c.role!),
                  // Wrap (not Row) so a long driver limit string reflows onto its own
                  // line at large text scales instead of overflowing the card (US-1 AC:
                  // must survive text scale 2.0 — same rule as the rest of the app).
                  Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpacing.xs, children: [
                    const Icon(Icons.drive_eta, size: 18, color: white),
                    Text(roleText, key: const Key('card-role-text'), style: const TextStyle(color: white)),
                  ]),
                ],
              ),
            ] else if (c.role == TripRole.rider) ...[
              const SizedBox(height: AppSpacing.xs),
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpacing.xs, children: [
                const Icon(Icons.event_seat, size: 18, color: white),
                Text(roleText, key: const Key('card-role-text'), style: const TextStyle(color: white)),
              ]),
            ],
            // Block 3: route + time + overlap.
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpacing.xs, children: [
                  const Icon(Icons.alt_route, size: 18, color: white),
                  Text(R6C.overlapLine(c.overlapPct), key: const Key('card-overlap'), style: const TextStyle(color: white)),
                ]),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpacing.xs, children: [
                  const Icon(Icons.schedule, size: 18, color: white),
                  Text(R6C.departLine(when), key: const Key('card-depart'), style: const TextStyle(color: white)),
                ]),
              ],
            ),
            // Block 4: vibe tags, frosted chips — hidden entirely when empty.
            if (c.vibeTags.isNotEmpty || (c.moodText?.isNotEmpty ?? false)) ...[
              const SizedBox(height: AppSpacing.sm),
              DefaultTextStyle(
                style: const TextStyle(color: white),
                child: IconTheme(
                  data: const IconThemeData(color: white),
                  child: TripVibeSummaryRow(vibeTags: c.vibeTags, moodText: c.moodText),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_outline, size: 14, color: Colors.white70),
              SizedBox(width: AppSpacing.xs),
              Flexible(child: Text(R6C.privacyCaption, style: TextStyle(color: Colors.white70, fontSize: 12))),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Anonymous rating line (US-36): '★ 4.6 (5 รีวิว)'. Drawn ONLY when both values are present (the server already
/// requires >= 3 revealed reviews); otherwise nothing at all (no gap, no "not enough reviews" text).
class CardRatingSlot extends StatelessWidget {
  const CardRatingSlot({super.key, this.avg, this.count, this.align = MainAxisAlignment.center, this.color});
  final double? avg;
  final int? count;
  final MainAxisAlignment align;

  /// Round 9: lets US-1's full-bleed card show the rating in white on the photo gradient
  /// instead of the default `tone.textSecondary` used everywhere else.
  final Color? color;

  static bool visible(double? avg, int? count) => avg != null && count != null && count > 0;

  @override
  Widget build(BuildContext context) {
    final a = avg;
    final n = count;
    if (a == null || n == null || !visible(a, n)) return const SizedBox.shrink();
    final tone = context.tone;
    return Semantics(
      container: true,
      label: R6C.ratingSemantics(a, n),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Row(
          key: const Key('card-rating'),
          mainAxisAlignment: align,
          mainAxisSize: MainAxisSize.max,
          children: [
            Flexible(
              child: Text(
                R6C.ratingLine(a, n),
                key: const Key('card-rating-text'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color ?? tone.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Drag / fling wrapper with stamps. Skip = left, invite = right; both thresholds: 35 % of the width or 700 dp/s.
class DeckSwipeCard extends StatefulWidget {
  const DeckSwipeCard({
    super.key,
    required this.cardKey,
    required this.child,
    required this.onSkip,
    required this.onInvite,
    required this.canInvite,
  });

  final Key cardKey;
  final Widget child;
  final VoidCallback onSkip;
  final VoidCallback onInvite;

  /// Checked before an invite goes out (cap / double send); false = the card snaps back.
  final bool Function() canInvite;

  @override
  State<DeckSwipeCard> createState() => DeckSwipeCardState();
}

class DeckSwipeCardState extends State<DeckSwipeCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  double _dx = 0;
  double _width = 320;
  Animation<double>? _anim;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(DeckSwipeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cardKey != widget.cardKey) {
      // A new front card starts in the middle.
      _c.stop();
      _dx = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool get _reduce => MediaQuery.disableAnimationsOf(context);

  void _animateTo(double target, Duration d, VoidCallback? done) {
    if (_reduce || d == Duration.zero) {
      setState(() => _dx = target);
      done?.call();
      return;
    }
    _c.duration = d;
    final from = _dx;
    _anim = Tween<double>(begin: from, end: target).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeOut),
    )..addListener(() => setState(() => _dx = _anim!.value));
    _c.forward(from: 0).whenComplete(() {
      if (mounted) done?.call();
    });
  }

  /// Button path: same result as a swipe.
  void fling({required bool right}) {
    if (right && !widget.canInvite()) return;
    // US-47 (round 7): haptics respect reduce-motion/haptics (a11y setting) — never a forced buzz.
    if (!_reduce) HapticFeedback.selectionClick();
    _animateTo(
      right ? _width * 1.4 : -_width * 1.4,
      const Duration(milliseconds: 180),
      right ? widget.onInvite : widget.onSkip,
    );
  }

  void _end(double velocity) {
    final far = _dx.abs() > _width * 0.35 || velocity.abs() > 700;
    if (!far) {
      _animateTo(0, const Duration(milliseconds: 200), null);
      return;
    }
    final right = (_dx != 0 ? _dx : velocity) > 0;
    if (right && !widget.canInvite()) {
      _animateTo(0, const Duration(milliseconds: 200), null);
      return;
    }
    _animateTo(
      right ? _width * 1.4 : -_width * 1.4,
      const Duration(milliseconds: 180),
      right ? widget.onInvite : widget.onSkip,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        _width = box.maxWidth;
        final t = (_dx.abs() / (_width * 0.3)).clamp(0.0, 1.0);
        final right = _dx > 0;
        final tone = context.tone;
        final angle = _reduce ? 0.0 : (_dx / _width) * 0.14;
        return GestureDetector(
          key: widget.cardKey,
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) {
            _c.stop();
            // US-47: light selection haptic when the user starts dragging the card (reduce-motion respected).
            if (!_reduce) HapticFeedback.selectionClick();
          },
          onHorizontalDragUpdate: (d) => setState(() => _dx += d.delta.dx),
          onHorizontalDragEnd: (d) => _end(d.primaryVelocity ?? 0),
          onHorizontalDragCancel: () =>
              _animateTo(0, const Duration(milliseconds: 200), null),
          child: Transform.translate(
            offset: Offset(_dx, 0),
            child: Transform.rotate(
              angle: angle,
              child: Stack(
                children: [
                  DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      borderRadius: AppShape.cardRadius,
                      border: _dx == 0
                          ? null
                          : Border.all(
                              color: right
                                  ? AppColors.green
                                  : tone.borderStrong,
                              width: 3,
                            ),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      child: widget.child,
                    ),
                  ),
                  if (_dx != 0)
                    Positioned(
                      top: AppSpacing.lg,
                      left: right ? AppSpacing.lg : null,
                      right: right ? null : AppSpacing.lg,
                      child: Opacity(
                        opacity: t,
                        child: _Stamp(
                          key: Key(right ? 'stamp-invite' : 'stamp-skip'),
                          icon: right ? Icons.favorite : Icons.close,
                          text: right ? R6C.stampInvite : R6C.stampSkip,
                          color: right ? AppColors.greenDark : tone.text,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: context.tone.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: color),
          ),
        ],
      ),
    ),
  );
}

/// Segmented "การ์ด | รายการ" (F-12).
class ViewToggle extends StatelessWidget {
  const ViewToggle({super.key, required this.value, required this.onChanged});
  final NearbyView value;
  final ValueChanged<NearbyView> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.pageH,
      AppSpacing.sm,
      AppSpacing.pageH,
      AppSpacing.xs,
    ),
    child: Semantics(
      container: true,
      label: R6C.viewGroup,
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<NearbyView>(
          key: const Key('view-toggle'),
          showSelectedIcon: true,
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(0, AppSpacing.minTap)),
          ),
          segments: const [
            ButtonSegment(
              value: NearbyView.deck,
              icon: Icon(Icons.style_outlined),
              label: Text(R6C.viewCard, key: Key('view-card')),
            ),
            ButtonSegment(
              value: NearbyView.list,
              icon: Icon(Icons.view_list_outlined),
              label: Text(R6C.viewList, key: Key('view-list')),
            ),
          ],
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      ),
    ),
  );
}
