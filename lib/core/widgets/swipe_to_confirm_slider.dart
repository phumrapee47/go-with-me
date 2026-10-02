import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../l10n/strings_r6.dart';
import '../theme/tokens.dart';
import '../theme/tone.dart';

/// Result of a confirm attempt: `null` = success, a Thai message = failure
/// (the slider returns to idle and shows the message above the track).
typedef SliderConfirm = Future<String?> Function();

/// Return this from [SliderConfirm] when the flow was abandoned on purpose (the user
/// backed out of a prerequisite dialog): the slider resets without any message.
const String sliderCancelled = '';

enum SliderPhase { idle, dragging, holding, submitting, success }

/// F-4 (US-31): swipe (or press-and-hold 1.5 s, or a screen-reader activate /
/// custom action) to confirm a ROUTINE status change. It must never be used for
/// SOS, cancel, report, delete or sign-out (those keep their dialogs).
///
/// - dragging >= 95 % of the track calls [onConfirm] once; releasing early springs back
/// - a plain tap does nothing (shows a hint for 3 s)
/// - while a confirm is running or shown as done nothing can be started again
/// - reduce motion: no bounce/scale/fade animation; state is conveyed by text and icon
class SwipeToConfirmSlider extends StatefulWidget {
  const SwipeToConfirmSlider({
    super.key,
    required this.label,
    required this.onConfirm,
    required this.successLabel,
    this.successSemanticsLabel,
    this.onSucceeded,
    this.disabledReason,
    this.near = false,
    this.nearLabel = R6.sliderNearDest,
    this.showHelp = true,
    this.holdDuration = const Duration(milliseconds: 1500),
    this.successHold = const Duration(milliseconds: 600),
  });

  /// What the slider does ("สไลด์เพื่อขึ้นรถแล้ว"); also the screen-reader label.
  final String label;
  final SliderConfirm onConfirm;

  /// Shown in the track after success (may contain an emoji).
  final String successLabel;

  /// Screen-reader text for [successLabel] without the emoji name.
  final String? successSemanticsLabel;

  /// Called [successHold] after a successful confirm (the caller changes the screen state).
  final VoidCallback? onSucceeded;

  /// Non-null = disabled; the reason is always shown as visible text under the track.
  final String? disabledReason;

  /// Geofence highlight (presentation only, never affects [onConfirm]).
  final bool near;
  final String nearLabel;

  /// Caption "ลากไม่ได้? กดค้าง..." under the track (hidden in the Collapsed sheet).
  final bool showHelp;
  final Duration holdDuration;
  final Duration successHold;

  @override
  State<SwipeToConfirmSlider> createState() => _SwipeState();
}

const double _thumb = 56;
const double _inset = 4;
const double _confirmAt = 0.95;

class _SwipeState extends State<SwipeToConfirmSlider>
    with TickerProviderStateMixin {
  SliderPhase _phase = SliderPhase.idle;
  double _dx = 0; // thumb travel in dp
  String? _error;
  bool _hintVisible = false;
  bool _pressed = false;
  bool _focused = false;
  Timer? _hintTimer;
  Timer? _successTimer;
  late final AnimationController _hold =
      AnimationController(vsync: this, duration: widget.holdDuration)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed && _phase == SliderPhase.holding) {
            unawaited(_confirm(viaHold: true));
          }
        });
  late final AnimationController _back = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  double _backFrom = 0;
  double _travel = 1;

  bool get _disabled => widget.disabledReason != null;
  bool get _locked =>
      _phase == SliderPhase.submitting || _phase == SliderPhase.success;
  bool get _reduce => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    _back.addListener(() {
      if (!mounted) return;
      setState(
        () => _dx = _backFrom * (1 - Curves.easeOut.transform(_back.value)),
      );
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _successTimer?.cancel();
    _hold.dispose();
    _back.dispose();
    super.dispose();
  }

  // ---- drag ----
  void _dragStart(DragStartDetails d) {
    if (_disabled || _locked) return;
    _back.stop();
    _hold.reset();
    // US-47 (round 7): haptics respect reduce-motion/haptics (a11y setting) — never a forced buzz.
    if (!_reduce) unawaited(HapticFeedback.lightImpact());
    setState(() {
      _phase = SliderPhase.dragging;
      _pressed = true;
      _error = null;
      _hintVisible = false;
    });
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (_phase != SliderPhase.dragging) return;
    final next = (_dx + d.delta.dx).clamp(0.0, _travel);
    setState(() => _dx = next);
    if (_travel > 0 && next / _travel >= _confirmAt) {
      // US-47: heavy impact at the 95% confirm threshold (respects reduce-motion/haptics).
      if (!_reduce) unawaited(HapticFeedback.heavyImpact());
      unawaited(_confirm());
    }
  }

  void _dragEnd([Object? _]) {
    if (_phase != SliderPhase.dragging) return;
    _springBack();
  }

  void _springBack() {
    setState(() {
      _phase = SliderPhase.idle;
      _pressed = false;
    });
    if (_reduce || _dx == 0) {
      setState(() => _dx = 0);
      return;
    }
    _backFrom = _dx;
    _back.forward(from: 0);
  }

  // ---- press and hold (accessible alternative) ----
  void _pressDown(TapDownDetails d) {
    if (_disabled || _locked || _phase == SliderPhase.dragging) return;
    if (!_reduce) unawaited(HapticFeedback.lightImpact());
    setState(() {
      _phase = SliderPhase.holding;
      _error = null;
    });
    _hold.forward(from: 0);
  }

  void _pressCancel() {
    if (_phase != SliderPhase.holding) return;
    _hold.stop();
    _hold.reset();
    setState(() => _phase = SliderPhase.idle);
  }

  void _pressUp(TapUpDetails d) {
    if (_phase != SliderPhase.holding) return;
    _pressCancel();
    // A plain tap never confirms: show the hint as TEXT for 3 s.
    if (_disabled) return;
    _hintTimer?.cancel();
    setState(() => _hintVisible = true);
    _hintTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _hintVisible = false);
    });
  }

  // ---- confirm ----
  Future<void> _confirm({bool viaHold = false}) async {
    if (_disabled || _locked) return; // busy lock: no double call
    if (viaHold && !_reduce) unawaited(HapticFeedback.heavyImpact());
    _hold.stop();
    setState(() {
      _phase = SliderPhase.submitting;
      _dx = _travel;
      _pressed = false;
      _error = null;
    });
    String? err;
    try {
      err = await widget.onConfirm();
    } catch (_) {
      err = R6.sliderOfflineError;
    }
    if (!mounted) return;
    if (err == null) {
      if (!_reduce) unawaited(HapticFeedback.heavyImpact());
      setState(() => _phase = SliderPhase.success);
      _successTimer = Timer(widget.successHold, () {
        if (mounted) widget.onSucceeded?.call();
      });
    } else {
      final quiet = err == sliderCancelled;
      if (!quiet && !_reduce) unawaited(HapticFeedback.vibrate());
      setState(() {
        _error = quiet ? null : err;
        _phase = SliderPhase.idle;
      });
      _hold.reset();
      _backFrom = _dx;
      if (_reduce) {
        setState(() => _dx = 0);
      } else {
        unawaited(_back.forward(from: 0));
      }
    }
  }

  // ---- build ----
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final trackH = scale > 1.3 ? (64 * scale / 1.3).clamp(64.0, 96.0) : 64.0;
    final near = widget.near && !_disabled;
    final success = _phase == SliderPhase.success;

    final Color rail;
    final Color border;
    final Color thumb;
    final Color thumbIcon;
    final Color fill;
    if (_disabled) {
      rail = tone.isDriver ? tone.surface : tone.bg;
      border = tone.border;
      thumb = tone.isDriver
          ? tone.textDisabled
          : tone.textSecondary.withValues(alpha: .6);
      thumbIcon = tone.isDriver ? tone.surface : Colors.white;
      fill = Colors.transparent;
    } else if (near || success) {
      rail = tone.isDriver ? tone.surface : AppColors.mint;
      border = tone.isDriver ? tone.successFill : AppColors.greenDark;
      thumb = tone.successFill;
      thumbIcon = const Color(0xFF0B1B33);
      fill = tone.successFill.withValues(alpha: tone.isDriver ? .22 : .20);
    } else {
      rail = tone.isDriver ? tone.surface : tone.primaryTint;
      border = tone.isDriver ? tone.borderStrong : tone.primary;
      thumb = tone.primary;
      thumbIcon = tone.onPrimary;
      fill = tone.primary.withValues(alpha: tone.isDriver ? .25 : .20);
    }
    final borderW = (near || _pressed || _focused) ? 2.0 : 1.5;
    final dur = _reduce ? Duration.zero : const Duration(milliseconds: 250);

    final holdP = _phase == SliderPhase.holding ? _hold.value : 0.0;

    final String shownLabel = switch (_phase) {
      SliderPhase.submitting => R6.sliderSubmitting,
      SliderPhase.success => widget.successLabel,
      SliderPhase.holding => R6.sliderHoldingLabel,
      _ => widget.label,
    };

    final semanticsLabel = success
        ? (widget.successSemanticsLabel ?? widget.successLabel)
        : widget.label;
    final value = switch (_phase) {
      _ when _disabled => R6.sliderValueDisabled(widget.disabledReason!),
      SliderPhase.submitting => R6.sliderSubmittingAnnounce,
      SliderPhase.success => '',
      SliderPhase.holding => R6.sliderHoldAnnounce,
      _ => near ? R6.sliderNearDest : R6.sliderValueReady,
    };
    void activate() => _confirm();

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 20,
                    color: tone.dangerInk,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _error!,
                          key: const Key('slider-error'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: tone.dangerInk,
                          ),
                        ),
                        Text(
                          R6.sliderRetryHint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: tone.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        FocusableActionDetector(
          enabled: !_disabled && !_locked,
          onShowFocusHighlight: (v) => setState(() => _focused = v),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) => _confirm(),
            ),
          },
          child: Semantics(
            container: true,
            button: true,
            enabled: !_disabled,
            label: semanticsLabel,
            value: value,
            hint: _disabled || _locked ? null : R6.sliderSemanticsHint,
            liveRegion: success || near || _phase == SliderPhase.submitting,
            onTap: _disabled || _locked ? null : activate,
            customSemanticsActions: _disabled || _locked
                ? const {}
                : {
                    CustomSemanticsAction(
                      label: R6.sliderActionName(widget.label),
                    ): activate,
                  },
            child: ExcludeSemantics(
              child: LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth.isFinite ? c.maxWidth : 288.0;
                  _travel = (w - _thumb - _inset * 2).clamp(
                    1.0,
                    double.infinity,
                  );
                  final shownDx = success || _phase == SliderPhase.submitting
                      ? _travel
                      : _dx;
                  final dragFill = shownDx + _thumb + _inset;
                  final fillW = success
                      ? w
                      : (holdP > 0 ? (holdP * w).clamp(dragFill, w) : dragFill);
                  final textOpacity = (1 - (shownDx / _travel) / 0.6).clamp(
                    0.0,
                    1.0,
                  );
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: _pressDown,
                    onTapUp: _pressUp,
                    onTapCancel: _pressCancel,
                    child: AnimatedBuilder(
                      animation: _hold,
                      builder: (context, _) => AnimatedContainer(
                        duration: dur,
                        // Grows with the text (never clips it); 64 dp at normal text size.
                        constraints: BoxConstraints(minHeight: trackH),
                        decoration: BoxDecoration(
                          color: rail,
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: border,
                            width: _focused ? 3 : borderW,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            // fill
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: (_phase == SliderPhase.holding
                                  ? (_hold.value * w).clamp(dragFill, w)
                                  : fillW),
                              child: ColoredBox(color: fill),
                            ),
                            // destination marker
                            if (!success)
                              Positioned(
                                right: 20,
                                top: 0,
                                bottom: 0,
                                child: Center(
                                  child: Icon(
                                    Icons.check_circle_outline,
                                    size: 24,
                                    color: _disabled
                                        ? tone.textDisabled
                                        : tone.textSecondary,
                                  ),
                                ),
                              ),
                            // label
                            Padding(
                              padding: const EdgeInsets.fromLTRB(72, 6, 56, 6),
                              child: Center(
                                child: Opacity(
                                  opacity: success
                                      ? 1
                                      : (_phase == SliderPhase.dragging
                                            ? textOpacity
                                            : 1),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (near &&
                                          !success &&
                                          _phase == SliderPhase.idle)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.where_to_vote_outlined,
                                              size: 16,
                                              color: tone.text,
                                            ),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                widget.nearLabel,
                                                key: const Key('slider-near'),
                                                textAlign: TextAlign.center,
                                                style: theme
                                                    .textTheme
                                                    .labelMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: tone.text,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      Text(
                                        shownLabel,
                                        key: const Key('slider-label'),
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.bodyLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: _disabled
                                                  ? tone.textDisabled
                                                  : tone.text,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // thumb
                            Positioned(
                              left: _inset + (success ? _travel : shownDx),
                              top: 0,
                              bottom: 0,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: GestureDetector(
                                  key: const Key('slider-thumb'),
                                  behavior: HitTestBehavior.opaque,
                                  onHorizontalDragStart: _dragStart,
                                  onHorizontalDragUpdate: _dragUpdate,
                                  onHorizontalDragEnd: _dragEnd,
                                  onHorizontalDragCancel: _dragEnd,
                                  child: AnimatedScale(
                                    scale: _pressed && !_reduce ? 1.06 : 1,
                                    duration: const Duration(milliseconds: 100),
                                    child: Container(
                                      width: _thumb,
                                      height: _thumb,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: thumb,
                                      ),
                                      alignment: Alignment.center,
                                      child: switch (_phase) {
                                        SliderPhase.submitting => SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 3,
                                            color: thumbIcon,
                                          ),
                                        ),
                                        SliderPhase.success => Icon(
                                          Icons.check,
                                          size: 28,
                                          color: thumbIcon,
                                        ),
                                        _ when _disabled => Icon(
                                          Icons.lock_outline,
                                          size: 24,
                                          color: thumbIcon,
                                        ),
                                        _ => Icon(
                                          Icons.keyboard_double_arrow_right,
                                          size: 28,
                                          color: thumbIcon,
                                        ),
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (_disabled)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              widget.disabledReason!,
              key: const Key('slider-disabled-reason'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tone.textSecondary,
              ),
            ),
          )
        else if (_hintVisible)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Semantics(
              liveRegion: true,
              child: Text(
                R6.sliderTapHint,
                key: const Key('slider-hint'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          )
        else if (widget.showHelp && !_locked)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              R6.sliderHelp,
              key: const Key('slider-help'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: tone.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}
