import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/error/failure_messages.dart';
import '../../../core/l10n/strings_r6_cd.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/providers.dart';
import '../../trip/domain/trip.dart';
import '../../trip/presentation/trip_providers.dart';
import '../domain/match_models.dart';
import 'matching_providers.dart';

/// Deck (default) or the old list (Q4). Remembered on this device; the query `?view=list` opens the list.
enum NearbyView { deck, list }

const _viewKey = 'gwm.nearbyView';

class NearbyViewController extends Notifier<NearbyView> {
  @override
  NearbyView build() {
    final v = ref.read(sharedPrefsProvider).getString(_viewKey);
    return v == 'list' ? NearbyView.list : NearbyView.deck;
  }

  void set(NearbyView v) {
    state = v;
    ref.read(sharedPrefsProvider).setString(_viewKey, v.name);
  }
}

final nearbyViewProvider = NotifierProvider<NearbyViewController, NearbyView>(NearbyViewController.new);

/// Phases of the banner above the action bar (F-10).
enum InvitePhase {
  /// request_match in flight: "กำลังชวน…", undo disabled.
  sending,

  /// Sent, undo window open.
  undoable,

  /// Window over: plain "ชวนเพื่อนแล้ว!" for a moment.
  confirmed,

  /// Undo in flight (button disabled, no double press).
  cancelling,

  /// Cancelled: "เลิกชวนแล้ว".
  undone,

  /// The other side answered first: nothing was cancelled (polite explanation).
  blocked,

  /// Mutual request: matched at once, no undo.
  matched,
}

class DeckInvite {
  const DeckInvite({
    required this.candidate,
    required this.phase,
    this.matchId,
    this.secondsLeft = 0,
    this.windowSeconds = 5,
    this.message,
  });

  final MatchCandidate candidate;
  final InvitePhase phase;
  final String? matchId;
  final int secondsLeft;
  final int windowSeconds;

  /// Phase text override (blocked / matched).
  final String? message;

  DeckInvite copyWith({InvitePhase? phase, String? matchId, int? secondsLeft, String? message}) => DeckInvite(
        candidate: candidate,
        phase: phase ?? this.phase,
        matchId: matchId ?? this.matchId,
        secondsLeft: secondsLeft ?? this.secondsLeft,
        windowSeconds: windowSeconds,
        message: message ?? this.message,
      );
}

class DeckState {
  const DeckState({
    this.skipped = const {},
    this.invited = const {},
    this.gone = const {},
    this.banner,
    this.sentCount = 0,
    this.notice,
    this.capReached = false,
    this.capAt = 0,
    this.paused = false,
    this.announce,
  });

  /// Card ids decided in THIS session. Skips are not stored anywhere (no behaviour tracking) and come back on refresh.
  final Set<String> skipped;

  /// Cards whose request is sent / in flight (and not undone).
  final Set<String> invited;

  /// Cards that can no longer be invited (someone else took them, rules changed): never shown again in this deck.
  final Set<String> gone;
  final DeckInvite? banner;

  /// "ชวนไป N คน" on the end-of-deck page (on screen only).
  final int sentCount;

  /// One transient message (errors); cleared after a few seconds or by the user.
  final String? notice;
  final bool capReached;

  /// Outgoing pending count when the cap was hit; the bar clears when it drops below.
  final int capAt;

  /// The undo button has focus: the timer waits (a11y).
  final bool paused;

  /// Screen-reader announcement for the last skip.
  final String? announce;

  int get decided => skipped.length + invited.length + gone.length;

  DeckState copyWith({
    Set<String>? skipped,
    Set<String>? invited,
    Set<String>? gone,
    Object? banner = _keep,
    int? sentCount,
    Object? notice = _keep,
    bool? capReached,
    int? capAt,
    bool? paused,
    Object? announce = _keep,
  }) =>
      DeckState(
        skipped: skipped ?? this.skipped,
        invited: invited ?? this.invited,
        gone: gone ?? this.gone,
        banner: identical(banner, _keep) ? this.banner : banner as DeckInvite?,
        sentCount: sentCount ?? this.sentCount,
        notice: identical(notice, _keep) ? this.notice : notice as String?,
        capReached: capReached ?? this.capReached,
        capAt: capAt ?? this.capAt,
        paused: paused ?? this.paused,
        announce: identical(announce, _keep) ? this.announce : announce as String?,
      );
}

const Object _keep = Object();

/// The cards still to decide: never myself, no duplicates, nobody with an existing request (pending / accepted /
/// declined / cancelled) and nobody already decided in this session.
List<MatchCandidate> deckCards(List<MatchCandidate> items, Trip trip, DeckState s) {
  final seen = <String>{};
  return [
    for (final c in items)
      if (c.tripId != trip.id &&
          c.requestStatus == null &&
          !s.skipped.contains(c.tripId) &&
          !s.invited.contains(c.tripId) &&
          !s.gone.contains(c.tripId) &&
          seen.add(c.tripId))
        c,
  ];
}

/// True while the "too many open requests" bar must show and the invite button stays off.
bool deckCapActive(DeckState s, int outgoingPending) => s.capReached && outgoingPending >= s.capAt;

/// Outgoing pending requests of MY trip (the server enforces the cap; this only mirrors it for the UI).
int outgoingPendingCount(List<MatchSummary> inbox, String tripId) =>
    inbox.where((m) => m.iAmRequester && m.status == MatchStatus.pending && m.myTripId == tripId).length;

/// Rules broken for this card: it never comes back in this deck.
const _dropCodes = {
  'GWM_NOT_ELIGIBLE',
  'GWM_TRIP_UNAVAILABLE',
  'GWM_MATCH_LIMIT',
  'GWM_TRIP_NOT_FOUND',
  'GWM_MATCH_CLOSED',
  'GWM_TRIP_FINISHED',
};

class DeckController extends Notifier<DeckState> {
  Timer? _ticker;
  Timer? _noticeTimer;
  final _inflight = <String>{};

  @override
  DeckState build() {
    // A different trip = a new deck.
    ref.watch(activeTripProvider.select((a) => a.valueOrNull?.id));
    ref.onDispose(() {
      _ticker?.cancel();
      _noticeTimer?.cancel();
    });
    return const DeckState();
  }

  // ---- skip -------------------------------------------------------------

  /// Nothing is sent to anybody and nothing is stored.
  void skip(MatchCandidate c, {String? nextName}) {
    state = state.copyWith(
      skipped: {...state.skipped, c.tripId},
      announce: nextName == null ? R6C.announceSkipped(c.displayName) : '${R6C.announceSkipped(c.displayName)} ${R6C.announceNext(nextName)}',
    );
  }

  /// Refresh: skipped cards may come back (only skips are forgotten).
  void resetSkipped() => state = state.copyWith(skipped: const {}, announce: null);

  // ---- invite -----------------------------------------------------------

  /// Whether a swipe / press may go ahead now. Shows the reason when not.
  bool canInvite(MatchCandidate c, {required int outgoingPending}) {
    if (state.invited.contains(c.tripId) || _inflight.contains(c.tripId)) return false;
    if (deckCapActive(state, outgoingPending)) {
      _notice(R.pendingCap);
      return false;
    }
    return true;
  }

  /// Sends the request NOW through the existing idempotent path (1 card = 1 request), then opens the undo window.
  Future<void> invite(MatchCandidate c, {required int windowSeconds}) async {
    final id = c.tripId;
    if (state.invited.contains(id) || _inflight.contains(id)) return;
    _inflight.add(id);
    _stopTicker();
    state = state.copyWith(
      invited: {...state.invited, id},
      banner: DeckInvite(candidate: c, phase: InvitePhase.sending, windowSeconds: windowSeconds),
      notice: null,
      paused: false,
    );

    final res = await ref.read(nearbyProvider.notifier).request(c);
    _inflight.remove(id);

    final failure = res.failureOrNull;
    if (failure != null) {
      _onInviteFailed(c, failure);
      return;
    }
    final outcome = res.valueOrNull!;
    final isLatest = state.banner?.candidate.tripId == id;
    final sent = state.sentCount + 1;
    if (outcome.status == MatchStatus.accepted) {
      // Mutual request: matched at once (the Match Moment follows from the inbox).
      state = state.copyWith(
        sentCount: sent,
        banner: isLatest
            ? DeckInvite(candidate: c, phase: InvitePhase.matched, matchId: outcome.matchId, secondsLeft: 5, message: null)
            : state.banner,
      );
      if (isLatest) _startTicker();
      return;
    }
    state = state.copyWith(
      sentCount: sent,
      banner: isLatest
          ? DeckInvite(
              candidate: c,
              phase: InvitePhase.undoable,
              matchId: outcome.matchId,
              secondsLeft: windowSeconds,
              windowSeconds: windowSeconds,
            )
          : state.banner,
    );
    if (isLatest) _startTicker();
  }

  void _onInviteFailed(MatchCandidate c, AppFailure f) {
    final id = c.tripId;
    final isLatest = state.banner?.candidate.tripId == id;
    final drop = _dropCodes.contains(f.code);
    final message = switch (f.code) {
      'GWM_PENDING_LIMIT' => R.pendingCap,
      'GWM_RATE_LIMITED' || FailureCode.rateLimited => R6C.throttled,
      _ => drop ? R6C.inviteFailed(failureMessage(f)) : failureMessage(f),
    };
    var cap = state.capReached;
    var capAt = state.capAt;
    if (f.code == 'GWM_PENDING_LIMIT') {
      final inbox = ref.read(inboxProvider).valueOrNull ?? const <MatchSummary>[];
      final tripId = ref.read(activeTripProvider).valueOrNull?.id;
      cap = true;
      capAt = tripId == null ? 1 : outgoingPendingCount(inbox, tripId).clamp(1, 1 << 20);
    }
    // The card comes back unless the rules say it cannot be invited any more.
    state = state.copyWith(
      invited: {...state.invited}..remove(id),
      gone: drop ? {...state.gone, id} : null,
      banner: isLatest ? null : state.banner,
      capReached: cap,
      capAt: capAt,
    );
    if (isLatest) _stopTicker();
    _notice(message);
  }

  // ---- undo -------------------------------------------------------------

  /// "เลิกชวน". Never cancels a match the other side already accepted: the server RPC cancel_pending_match only
  /// touches a pending request (the local re-read first is UX only); the button is disabled while sending / cancelling.
  Future<void> undo() async {
    final inv = state.banner;
    if (inv == null || inv.phase != InvitePhase.undoable || inv.matchId == null) return;
    final matchId = inv.matchId!;
    final c = inv.candidate;
    state = state.copyWith(banner: inv.copyWith(phase: InvitePhase.cancelling), paused: true);

    await ref.read(inboxProvider.notifier).refresh();
    final list = ref.read(inboxProvider).valueOrNull ?? const <MatchSummary>[];
    final m = list.where((x) => x.id == matchId).firstOrNull;
    if (m == null || m.status != MatchStatus.pending) {
      _blocked(c, matchId, m?.status);
      return;
    }
    // The pre-read above is UX only; the server RPC is the guard (it never cancels an accepted match).
    final res = await ref.read(inboxProvider.notifier).cancelPending(matchId);
    final failure = res.failureOrNull;
    if (failure != null) {
      if (failure.code == 'GWM_MATCH_NOT_PENDING') {
        // The other side answered first. Nothing was changed. Polite message unless the re-read shows it was declined.
        await ref.read(inboxProvider.notifier).refresh();
        final again = (ref.read(inboxProvider).valueOrNull ?? const <MatchSummary>[]).where((x) => x.id == matchId).firstOrNull;
        final st = again?.status;
        _blocked(c, matchId, st == MatchStatus.declined || st == MatchStatus.cancelled ? st : MatchStatus.accepted);
        return;
      }
      // Could not cancel (network...): the request is still there; try again while the window lasts.
      final cur = state.banner;
      final left = cur?.secondsLeft ?? 0;
      state = state.copyWith(
        banner: cur?.copyWith(phase: left > 0 ? InvitePhase.undoable : InvitePhase.confirmed),
        paused: false,
      );
      _notice(failureMessage(failure));
      return;
    }
    // Cancelled: the card comes back; it does not count against the pending cap (no longer pending) but the
    // server-side send throttle already counted it.
    ref.read(nearbyProvider.notifier).clearRequest(c.tripId);
    state = state.copyWith(
      invited: {...state.invited}..remove(c.tripId),
      sentCount: state.sentCount > 0 ? state.sentCount - 1 : 0,
      banner: DeckInvite(candidate: c, phase: InvitePhase.undone, secondsLeft: 3),
      paused: false,
    );
    _startTicker();
  }

  void _blocked(MatchCandidate c, String matchId, MatchStatus? status) {
    final accepted = status == MatchStatus.accepted;
    state = state.copyWith(
      // Accepted: the card stays gone (it is a match now). Closed otherwise: it never comes back either.
      gone: {...state.gone, c.tripId},
      banner: DeckInvite(
        candidate: c,
        phase: InvitePhase.blocked,
        matchId: matchId,
        secondsLeft: 6,
        message: accepted ? R6C.undoAccepted : (status == null ? R6C.undoUnknown : R6C.undoClosed),
      ),
      paused: false,
    );
    _startTicker();
  }

  /// The undo button has (or lost) keyboard / screen reader focus: the timer waits.
  void setPaused(bool v) {
    if (state.paused == v) return;
    if (v && state.banner?.phase != InvitePhase.undoable) return;
    state = state.copyWith(paused: v);
  }

  // ---- timers -----------------------------------------------------------

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _tick() {
    final b = state.banner;
    if (b == null) {
      _stopTicker();
      return;
    }
    switch (b.phase) {
      case InvitePhase.undoable:
        if (state.paused) return;
        final left = b.secondsLeft - 1;
        if (left <= 0) {
          state = state.copyWith(banner: b.copyWith(phase: InvitePhase.confirmed, secondsLeft: 4));
        } else {
          state = state.copyWith(banner: b.copyWith(secondsLeft: left));
        }
      case InvitePhase.confirmed || InvitePhase.undone || InvitePhase.blocked || InvitePhase.matched:
        final left = b.secondsLeft - 1;
        if (left <= 0) {
          state = state.copyWith(banner: null);
          _stopTicker();
        } else {
          state = state.copyWith(banner: b.copyWith(secondsLeft: left));
        }
      case InvitePhase.sending || InvitePhase.cancelling:
        break;
    }
  }

  void _notice(String text) {
    _noticeTimer?.cancel();
    state = state.copyWith(notice: text);
    _noticeTimer = Timer(const Duration(seconds: 6), () {
      if (state.notice == text) state = state.copyWith(notice: null);
    });
  }

  void dismissNotice() {
    _noticeTimer?.cancel();
    if (state.notice != null) state = state.copyWith(notice: null);
  }
}

final deckProvider = NotifierProvider<DeckController, DeckState>(DeckController.new);
