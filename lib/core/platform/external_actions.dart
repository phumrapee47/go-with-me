import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Everything that leaves the app (phone dialer, SMS, share sheet, browser).
/// Behind an interface so tests and demo mode never touch the platform.
/// Every method returns false instead of throwing: the caller decides how to
/// tell the user (SOS must keep working when one of these is unavailable).
abstract class ExternalActions {
  Future<bool> call(String number);
  Future<bool> sms(String number, String body);
  Future<bool> shareText(String text, {String? subject});
  Future<bool> openUrl(Uri url);
}

class PlatformExternalActions implements ExternalActions {
  const PlatformExternalActions();

  Future<bool> _launch(Uri uri) async {
    try {
      return await launchUrl(uri);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> call(String number) => _launch(Uri(scheme: 'tel', path: number));

  @override
  Future<bool> sms(String number, String body) =>
      _launch(Uri.parse('sms:$number?body=${Uri.encodeComponent(body)}'));

  @override
  Future<bool> shareText(String text, {String? subject}) async {
    try {
      await SharePlus.instance.share(ShareParams(text: text, subject: subject));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openUrl(Uri url) => _launch(url);
}

final externalActionsProvider = Provider<ExternalActions>((ref) => const PlatformExternalActions());
