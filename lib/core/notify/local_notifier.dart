import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/strings_roles.dart';

/// Kinds of local notification. Only "a match ended while my trip is in
/// progress" exists for now (Q-7).
enum LocalNoticeKind { matchEndedDuringTrip, driverArrivedAtPickup }

/// Payload of a local notification. By construction it can carry NO plate,
/// name or location: only a kind and fixed neutral copy (design-spec R.6, Q-7).
@immutable
class LocalNotice {
  const LocalNotice(this.kind);
  final LocalNoticeKind kind;

  String get title => R.notifyTitle;
  String get body => switch (kind) {
        LocalNoticeKind.matchEndedDuringTrip => R.notifyBody,
        LocalNoticeKind.driverArrivedAtPickup => R.driverArrivedPickup,
      };
}

/// Seam for a real package (e.g. flutter_local_notifications) later; the app
/// logic only talks to this interface. MVP has no remote push (Q-7): a user
/// who closed the app sees the change when the app is next opened.
abstract class LocalNotifier {
  Future<void> show(LocalNotice notice);
}

/// Default implementation: does nothing visible, logs the kind in debug builds only.
class DebugLocalNotifier implements LocalNotifier {
  const DebugLocalNotifier();

  @override
  Future<void> show(LocalNotice notice) async {
    if (kDebugMode) debugPrint('[local-notice] ${notice.kind.name}');
  }
}

final localNotifierProvider = Provider<LocalNotifier>((ref) => const DebugLocalNotifier());
