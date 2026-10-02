import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings_r6_cd.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/providers.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../avatar/presentation/user_avatar.dart';
import '../../profile/presentation/profile_providers.dart';
import '../../trip/domain/trip.dart' show TripStatus;
import '../../trip/presentation/trip_providers.dart';
import '../domain/match_models.dart';
import 'matching_providers.dart';

const _maxKept = 60;

/// US-37: decides WHICH accepted match earns the celebration, once.
///
/// Only for the person who SENT the request ("after the other side accepts"): the accepter already gets
/// "ไปด้วยกันเลย!" and lands on the match page. A match qualifies when this device saw its request
/// (pending in the inbox, or just sent), it is now accepted, my trip is still the active one, nobody boarded,
/// and it was not shown before. The flags live in SharedPreferences per user (ids only, no personal data).
class MatchMomentController extends Notifier<MatchSummary?> {
  final _queue = <String>[];
  final _seen = <String>{};
  final _tracked = <String>{};
  String? _uid;

  static String seenKey(String uid) => 'gwm.mm.seen.$uid';
  static String trackedKey(String uid) => 'gwm.mm.tracked.$uid';

  @override
  MatchSummary? build() {
    final uid = ref.watch(authUserProvider.select((a) => a.valueOrNull?.id));
    _uid = uid;
    _queue.clear();
    _seen.clear();
    _tracked.clear();
    if (uid == null) return null;
    final prefs = ref.read(sharedPrefsProvider);
    _seen.addAll(prefs.getStringList(seenKey(uid)) ?? const []);
    _tracked.addAll(prefs.getStringList(trackedKey(uid)) ?? const []);
    ref.listen<AsyncValue<List<MatchSummary>>>(inboxProvider, (_, _) => _evaluate());
    ref.listen(activeTripProvider, (_, _) => _evaluate());
    var disposed = false;
    ref.onDispose(() => disposed = true);
    // Not inside build(): the state may not be set before build returns.
    Future.microtask(() {
      if (!disposed) _evaluate();
    });
    return null;
  }

  void _save(String key, Set<String> ids) {
    final uid = _uid;
    if (uid == null) return;
    final list = ids.toList();
    final kept = list.length > _maxKept ? list.sublist(list.length - _maxKept) : list;
    ref.read(sharedPrefsProvider).setStringList(key, kept);
  }

  /// A request of mine exists (called right after a successful send).
  void track(String matchId) {
    final uid = _uid;
    if (uid == null || !_tracked.add(matchId)) return;
    _save(trackedKey(uid), _tracked);
  }

  void _evaluate() {
    final uid = _uid;
    if (uid == null) return;
    final list = ref.read(inboxProvider).valueOrNull;
    if (list == null) return;
    var trackedChanged = false;
    for (final m in list) {
      if (m.status == MatchStatus.pending && m.iAmRequester && _tracked.add(m.id)) trackedChanged = true;
    }
    if (trackedChanged) _save(trackedKey(uid), _tracked);

    final trip = ref.read(activeTripProvider).valueOrNull;
    final byId = {for (final m in list) m.id: m};
    // A queued match that got cancelled before it was shown is dropped (no wrong celebration).
    _queue.removeWhere((id) => byId[id]?.status != MatchStatus.accepted);
    if (trip != null && trip.status != TripStatus.completed) {
      for (final m in list) {
        if (m.status == MatchStatus.accepted &&
            m.iAmRequester &&
            !m.boarded &&
            m.myTripId == trip.id &&
            _tracked.contains(m.id) &&
            !_seen.contains(m.id) &&
            !_queue.contains(m.id)) {
          _queue.add(m.id);
        }
      }
    }
    _publish(byId);
  }

  void _publish(Map<String, MatchSummary> byId) {
    final current = state;
    if (current != null && byId[current.id]?.status != MatchStatus.accepted) {
      // Cancelled while the dialog is up: keep it simple, the host closes it via dismiss().
      state = null;
    }
    if (state == null && _queue.isNotEmpty) state = byId[_queue.first];
  }

  /// Every way out counts as "seen" (X, scrim, back, a button).
  void dismiss() {
    final uid = _uid;
    final cur = state;
    if (cur == null) return;
    _queue.remove(cur.id);
    _seen.add(cur.id);
    if (uid != null) _save(seenKey(uid), _seen);
    state = null;
    final list = ref.read(inboxProvider).valueOrNull ?? const <MatchSummary>[];
    _publish({for (final m in list) m.id: m});
  }
}

final matchMomentProvider = NotifierProvider<MatchMomentController, MatchSummary?>(MatchMomentController.new);

enum _MomentExit { close, greet, map }

/// Shows the Match Moment above whatever screen is current (app level, like the match-ended alert).
class MatchMomentHost extends ConsumerStatefulWidget {
  const MatchMomentHost({super.key, required this.router, required this.child});
  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<MatchMomentHost> createState() => _MatchMomentHostState();
}

class _MatchMomentHostState extends ConsumerState<MatchMomentHost> {
  bool _showing = false;

  void _maybeShow(MatchSummary? m) {
    if (m == null || _showing) return;
    _showing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _show(m));
  }

  Future<void> _show(MatchSummary m, {int attempt = 0}) async {
    final ctx = widget.router.routerDelegate.navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      if (attempt < 10 && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _show(m, attempt: attempt + 1));
      } else {
        _showing = false;
      }
      return;
    }
    final myName = ref.read(currentProfileProvider).valueOrNull?.displayName ?? '';
    final exit = await showDialog<_MomentExit>(
      context: ctx,
      barrierDismissible: true,
      builder: (dctx) => MatchMomentDialog(match: m, myName: myName),
    );
    if (!mounted) return;
    ref.read(matchMomentProvider.notifier).dismiss();
    _showing = false;
    switch (exit) {
      case _MomentExit.greet:
        unawaited(widget.router.push(Routes.chat(m.id), extra: R6C.momentGreetText));
      case _MomentExit.map:
        _openMap(m);
      case _MomentExit.close || null:
        break;
    }
    // Several matches at once: one dialog at a time.
    _maybeShow(ref.read(matchMomentProvider));
  }

  void _openMap(MatchSummary m) {
    final trip = ref.read(activeTripProvider).valueOrNull;
    final ready = trip != null && trip.id == m.myTripId && trip.status.isActive && m.status == MatchStatus.accepted;
    if (ready) {
      widget.router.push(Routes.tripActiveNow);
    } else {
      widget.router.push(Routes.match(m.id));
      final nav = widget.router.routerDelegate.navigatorKey.currentContext;
      if (nav != null) {
        ScaffoldMessenger.maybeOf(nav)?.showSnackBar(const SnackBar(content: Text(R6C.momentMapUnavailable)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<MatchSummary?>(matchMomentProvider, (_, next) => _maybeShow(next));
    return widget.child;
  }
}

/// F-13: both people (photos are allowed now: the match is accepted), title, two actions.
class MatchMomentDialog extends ConsumerWidget {
  const MatchMomentDialog({super.key, required this.match, required this.myName});
  final MatchSummary match;
  final String myName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final reduce = MediaQuery.disableAnimationsOf(context);
    final name = match.displayName;
    return Dialog(
      key: const Key('match-moment'),
      backgroundColor: context.tone.surface,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Stack(children: [
          if (!reduce) const Positioned.fill(child: IgnorePointer(child: _Confetti())),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.lg),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: AppSpacing.md),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                UserAvatar.mine(name: myName.isEmpty ? 'ฉัน' : myName, size: 80),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: ExcludeSemantics(child: Icon(reduce ? Icons.celebration : Icons.favorite, color: context.tone.successInk)),
                ),
                UserAvatar.partner(name: name, matchId: match.id, size: 80),
              ]),
              const SizedBox(height: AppSpacing.lg),
              // Focus starts here; the spoken text has no emoji name.
              Focus(
                autofocus: true,
                child: Semantics(
                  header: true,
                  liveRegion: true,
                  label: R6C.momentTitleSemantics,
                  excludeSemantics: true,
                  child: Text(R6C.momentTitle, key: const Key('match-moment-title'), textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(R6C.momentSub(name), textAlign: TextAlign.center, style: TextStyle(color: context.tone.textSecondary)),
              const SizedBox(height: AppSpacing.lg),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: AppButton(
                  key: const Key('moment-greet'),
                  label: R6C.momentGreet,
                  icon: Icons.chat_bubble_outline,
                  onPressed: () => Navigator.of(context).pop(_MomentExit.greet),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: AppButton(
                  key: const Key('moment-map'),
                  label: R6C.momentMap,
                  variant: AppButtonVariant.secondary,
                  icon: Icons.map_outlined,
                  onPressed: () => Navigator.of(context).pop(_MomentExit.map),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Existing safety line (meet in a public place) stays visible.
              Text(
                R.pickupPublicNote,
                key: const Key('moment-safety'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: context.tone.textSecondary),
              ),
            ]),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              key: const Key('moment-close'),
              tooltip: R6C.momentClose,
              iconSize: 24,
              constraints: const BoxConstraints(minWidth: AppSpacing.minTap, minHeight: AppSpacing.minTap),
              onPressed: () => Navigator.of(context).pop(_MomentExit.close),
              icon: const Icon(Icons.close),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Decorative, 1.5 s, never when the system asks to remove animations.
class _Confetti extends StatefulWidget {
  const _Confetti();
  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: AnimatedBuilder(animation: _c, builder: (_, _) => CustomPaint(painter: _ConfettiPainter(_c.value))),
      );
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t);
  final double t;
  static const _colors = [Color(0xFF22C08A), Color(0xFFF5A623), Color(0xFF1E6FD9), Color(0xFFE0568B)];

  @override
  void paint(Canvas canvas, Size size) {
    if (t >= 1) return;
    final rnd = math.Random(7);
    for (var i = 0; i < 28; i++) {
      final x = rnd.nextDouble() * size.width;
      final speed = 0.6 + rnd.nextDouble() * 0.8;
      final y = -12 + (size.height + 24) * (t * speed).clamp(0.0, 1.0);
      final paint = Paint()..color = _colors[i % _colors.length].withValues(alpha: 1 - t * 0.6);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * 6 + i);
      canvas.drawRect(const Rect.fromLTWH(-3, -5, 6, 10), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
