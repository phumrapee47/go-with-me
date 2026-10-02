import '../../../core/config/app_constants.dart';
import '../../../core/l10n/strings.dart';

final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? validateEmail(String? v) =>
    (v == null || !_emailRe.hasMatch(v.trim())) ? S.errEmail : null;

String? validatePassword(String? v) =>
    (v == null || v.length < AppConstants.minPasswordLength) ? S.errPasswordShort : null;

String? validateDisplayName(String? v) =>
    (v == null || v.trim().isEmpty) ? S.errName : null;
