import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/push_models.dart';
import 'notification_tap_handler.dart';
import 'push_copy.dart';
import 'push_permission_sheet.dart';
import 'push_providers.dart';
import 'push_service.dart' show InitialTapSource;

/// Sits above the whole navigator (same slot as `MatchAlertHost`), so a push
/// tap is handled from ANY screen (US-42, G-1/G-3):
/// - a background/closed-app tap routes via [handlePushTap];
/// - a foreground message (app already open on another screen) shows a
///   small non-blocking in-app banner (G.1.5) that navigates the same way
///   when tapped, and otherwise just fades — it never steals focus;
/// - the G-1 permission sheet is offered once per device right after the
///   first sign-in of a session (G.1.1 step 1: "เข้าสู่ระบบครั้งแรก... หรือ
///   กด 'สร้างทริป' เป็นครั้งแรก" — this covers the login trigger; the
///   create-trip trigger is the same `everAsked` guard, so whichever screen
///   calls `maybeShowPushPermissionSheet` first wins and the other is a
///   no-op).
class PushTapHost extends ConsumerStatefulWidget {
  const PushTapHost({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<PushTapHost> createState() => _PushTapHostState();
}

class _PushTapHostState extends ConsumerState<PushTapHost> {
  StreamSubscription<PushMessage>? _tapSub;
  StreamSubscription<PushMessage>? _fgSub;
  PushMessage? _banner;

  @override
  void initState() {
    super.initState();
    final service = ref.read(pushServiceProvider);
    _tapSub = service.onMessageTap.listen((m) => handlePushTap(ref, widget.router, m));
    _fgSub = service.onForegroundMessage.listen((m) {
      if (mounted) setState(() => _banner = m);
    });
    if (service is InitialTapSource) {
      // Cold start: the tap that opened the app never reaches onMessageTap. Run after the first frame so the
      // router exists; an unauthenticated user is redirected to login by the router as for any deep link.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final m = await (service as InitialTapSource).initialTap();
        if (m != null && mounted) handlePushTap(ref, widget.router, m);
      });
    }
  }

  @override
  void dispose() {
    _tapSub?.cancel();
    _fgSub?.cancel();
    super.dispose();
  }

  void _tapBanner() {
    final m = _banner;
    if (m == null) return;
    setState(() => _banner = null);
    handlePushTap(ref, widget.router, m);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authUserProvider, (prev, next) {
      final user = next.valueOrNull;
      if (user == null) return;
      final wasSignedOut = prev == null || prev.valueOrNull == null;
      ref.read(pushControllerProvider).ensureRegisteredIfEnabled();
      if (wasSignedOut) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // `context` here sits ABOVE the router's own Navigator (this host
          // wraps the whole `MaterialApp.router`), so `showDialog` needs the
          // router's navigator context instead (same fix as
          // `match_moment.dart`'s `_MomentExit` dialog).
          final navCtx = widget.router.routerDelegate.navigatorKey.currentContext;
          if (mounted && navCtx != null) maybeShowPushPermissionSheet(navCtx, ref);
        });
      }
    });
    final banner = _banner;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (banner != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Material(
                  color: context.tone.snackbarBg,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  child: InkWell(
                    key: const Key('push-in-app-banner'),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    onTap: _tapBanner,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Row(children: [
                        Icon(Icons.notifications, color: context.tone.snackbarText, size: 18),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            pushKindText(banner.kind),
                            style: TextStyle(color: context.tone.snackbarText),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: context.tone.snackbarText, size: 16),
                          onPressed: () => setState(() => _banner = null),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
