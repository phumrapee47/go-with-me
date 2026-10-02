import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/redirect.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/push_models.dart';
import 'push_providers.dart';

/// G-3 NotificationTapHandler (design-spec-round7 G.1.3/G.1.4): pure mapping
/// of a [PushMessage] to one of the EXISTING routes for its `kind`. No new
/// guard is added on purpose — each destination already has its own
/// "gone/expired" handling from earlier rounds (e.g. `PickupScreen`'s
/// `pickupMatchGone`, `MatchDetailScreen`'s not-found state), which is
/// exactly what runs when a stale push points at a withdrawn/expired item.
///
/// Returns null when the payload is malformed (missing the id its `kind`
/// needs) — callers must drop the notification silently rather than
/// navigate anywhere (fail-open, never crash on a bad payload).
String? routeForPushMessage(PushMessage msg) {
  switch (msg.kind) {
    case PushKind.newRequest:
      return Routes.nearbyRequests;
    case PushKind.matchAccepted:
    case PushKind.matchCancelled:
      final id = msg.matchId;
      return id == null || id.isEmpty ? null : Routes.match(id);
    case PushKind.driverArrived:
      final id = msg.matchId;
      return id == null || id.isEmpty ? null : Routes.live(id);
    case PushKind.newMessage:
      final id = msg.matchId;
      return id == null || id.isEmpty ? null : Routes.chat(id);
  }
}

/// G.1.2 "แตะการแจ้งเตือน": signed-in -> go straight to the destination,
/// replacing the current stack (same as the existing round-6 deep link).
/// Session stale/missing -> stash the destination and send to sign-in; it is
/// consumed exactly once by the router right after the next successful
/// sign-in (reuses the `returnTo` idea from D.9, no second guard mechanism).
void handlePushTap(WidgetRef ref, GoRouter router, PushMessage msg) {
  final path = routeForPushMessage(msg);
  if (path == null) return;
  final signedIn = ref.read(authUserProvider).valueOrNull != null;
  if (!signedIn) {
    ref.read(pendingDeepLinkProvider.notifier).state = path;
    router.go(Routes.signIn);
    return;
  }
  router.go(path);
}
