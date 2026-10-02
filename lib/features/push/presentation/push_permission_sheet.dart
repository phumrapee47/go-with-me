import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/strings_roles.dart';
import '../../../core/widgets/confirm_dialog.dart';
import 'push_providers.dart';
import 'push_service.dart';

/// G-1 PushPermissionSheet (design-spec-round7 G.1.1/G.1.3): re-uses the
/// existing ConsentSheet/PermissionRationale pattern (C-24, same as the
/// live-location consent in `trip_flows.dart`) rather than a new component.
///
/// Shown once (at login or first "สร้างทริป" — whichever the caller decides
/// is first, per G.1.1 step 1). Both "อนุญาตการแจ้งเตือน" and "ไว้ทีหลัง"
/// mark the sheet as decided so it never appears again automatically; the
/// user can still change their mind later at G-2 NotificationSettingsScreen.
Future<void> maybeShowPushPermissionSheet(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(pushControllerProvider);
  if (controller.everAsked) return;

  final allow = await showConfirmDialog(
    context,
    title: R.pushRationaleTitle,
    body: R.pushRationaleBody,
    safeLabel: R.pushLater,
    confirmLabel: R.pushAllow,
    destructive: false,
  );
  await controller.markAsked();
  if (!allow) return;

  final status = await controller.requestPermission();
  if (status == PushPermissionStatus.granted && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(R.pushGranted)));
  }
  // denied/notDetermined/unsupported: silent, never an error (G-1 states).
}
