import 'package:flutter/material.dart';

/// US-27 brand mark (transparent rounded square cropped from the supplied artwork; see tool/make_logo.py).
/// Never wrap it in another circle/border/shadow and never stretch it (design-spec round 5 section 8.2).
/// Splash 120, onboarding first slide 96, sign-in/up 72 (56 when the keyboard is up).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 72});
  final double size;

  static const asset = 'assets/branding/logo_mark.png';
  static const alt = 'กลับด้วยกันมั้ย';

  @override
  Widget build(BuildContext context) => Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        semanticLabel: alt,
        errorBuilder: (_, _, _) => SizedBox(width: size, height: size, child: const Icon(Icons.route_outlined)),
      );
}
