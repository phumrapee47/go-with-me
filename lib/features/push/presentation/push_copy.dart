import '../../../core/l10n/strings_roles.dart';
import '../domain/push_models.dart';

/// Single source of truth for push copy (R7.5/G.1.2): the server payload is
/// opaque (`kind` + one id only); every place that shows push text — a real
/// FCM tap, the in-app banner, a demo simulation — renders through here.
String pushKindText(PushKind kind) => switch (kind) {
      PushKind.newRequest => R.pushNewRequest,
      PushKind.matchAccepted => R.pushMatchAccepted,
      PushKind.driverArrived => R.pushDriverArrived,
      PushKind.matchCancelled => R.pushMatchCancelled,
      PushKind.newMessage => R.pushNewMessage,
    };
