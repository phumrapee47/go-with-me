import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings_p4.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';

/// C-18: fixed SOS entry point (tap 1 = open /sos). Always the same red,
/// never moves with the layout.
class SosMiniButton extends StatelessWidget {
  const SosMiniButton({super.key, this.tripId, this.fromChat = false});
  final String? tripId;
  final bool fromChat;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Semantics(
        button: true,
        label: P.chatSos,
        excludeSemantics: true,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.danger,
            foregroundColor: Colors.white,
            // Driver tone: white ring so the red keeps 3:1 against the navy surface (design-spec D.1.3).
            side: context.tone.isDriver ? const BorderSide(color: Colors.white, width: 2) : null,
            minimumSize: const Size(AppSpacing.minTap + 8, AppSpacing.minTap),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
          ),
          onPressed: () => context.push(Routes.sosFor(tripId: tripId, fromChat: fromChat)),
          icon: const Icon(Icons.shield_outlined, size: 20),
          label: const Text(P.sos, style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

/// Press-and-hold confirm (2 s) with a progress ring; releasing early
/// cancels. Progress is user-driven (not decorative), so it is kept under
/// "reduce motion". Screen-reader users get a plain activate action, and the
/// SOS screen also offers a single-tap confirm button.
class HoldToConfirmButton extends StatefulWidget {
  const HoldToConfirmButton({
    super.key,
    required this.onConfirmed,
    this.duration = const Duration(seconds: 2),
    this.size = 200,
  });

  final VoidCallback onConfirmed;
  final Duration duration;
  final double size;

  @override
  State<HoldToConfirmButton> createState() => _HoldToConfirmState();
}

class _HoldToConfirmState extends State<HoldToConfirmButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        HapticFeedback.heavyImpact();
        widget.onConfirmed();
      }
    });

  bool _holding = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _down() {
    HapticFeedback.mediumImpact();
    setState(() => _holding = true);
    _c.forward(from: 0);
  }

  void _release() {
    if (_c.status != AnimationStatus.completed) _c.reset();
    if (mounted) setState(() => _holding = false);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: P.sosHold,
      onTap: widget.onConfirmed,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _down(),
        onTapUp: (_) => _release(),
        onTapCancel: _release,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: CircularProgressIndicator(
                    value: _c.value,
                    strokeWidth: 10,
                    backgroundColor: AppColors.dangerTint,
                    color: AppColors.danger,
                  ),
                ),
                Container(
                  width: widget.size - 32,
                  height: widget.size - 32,
                  decoration: BoxDecoration(
                    color: _holding ? const Color(0xFF9B2626) : AppColors.danger,
                    shape: BoxShape.circle,
                    border: context.tone.isDriver ? Border.all(color: Colors.white, width: 2) : null,
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  // Scales down instead of overflowing at large text sizes.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: widget.size - 64,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.shield_outlined, color: Colors.white, size: 44),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            _holding ? P.sosRelease : P.sosHold,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
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
