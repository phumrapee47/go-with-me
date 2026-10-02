import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'tone.dart';

/// D-13 ToneScope: everything below reads the token set of [tone], whatever the app-level tone is.
/// Always keeps the same widget position so a tone change never rebuilds the child's state.
class ToneScope extends StatelessWidget {
  const ToneScope({super.key, required this.tone, required this.child});

  /// null = keep the ambient tone (role not known yet, or a trip without a role).
  final AppTone? tone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ambient = context.tone;
    final t = tone ?? ambient.tone;
    if (t == ambient.tone) {
      // Same tone as the app: still wrap (stable tree) but reuse the ambient theme untouched.
      return Theme(data: Theme.of(context), child: child);
    }
    return Theme(
      data: themeForTone(t, useGoogleFonts: ambient.googleFonts, brightness: ambient.brightness),
      child: child,
    );
  }
}
