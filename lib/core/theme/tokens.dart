import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/material.dart';

/// Design tokens from docs/design-spec.md section 1.
abstract final class AppColors {
  static const navy = Color(0xFF0B2545);
  static const blue = Color(0xFF1E6FD9);
  static const teal = Color(0xFF1D8FA8);
  static const green = Color(0xFF22C08A);
  static const mint = Color(0xFFE0F7F1);
  // Round 9 (US-7/G9.7.2, PM ruling item 8): F7FAFC -> F8F9FC, approved token value change.
  static const bg = Color(0xFFF8F9FC);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFD8E2EC);
  static const textSecondary = Color(0xFF4A5A70);
  static const blueTint = Color(0xFFE7F0FC);
  static const greenDark = Color(0xFF0E7A57);
  static const tealDark = Color(0xFF12708A);
  static const danger = Color(0xFFC53030);
  static const dangerTint = Color(0xFFFDECEC);
  static const warning = Color(0xFFB45309);
  static const warningTint = Color(0xFFFFF4E0);
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const huge = 48.0;
  static const pageH = 16.0;
  static const minTap = 48.0;
}

abstract final class AppRadius {
  // Bumped up from 12/16/24 (round7): at the old sizes the squircle's continuous
  // corner was only a couple of px different from a plain rounded rect — too subtle
  // to read as a deliberate style at phone scale. Bigger radius makes the flattened
  // diagonal on each corner actually visible.
  static const control = 16.0;
  static const card = 22.0;
  static const sheet = 28.0;
  static const pill = 999.0;
}

/// Continuous "squircle" (superellipse) shapes — replaces plain [BorderRadius.circular]
/// so cards/controls/sheets read as soft-depth, not stock Material rounded rects.
/// `cornerSmoothing` maxed toward 1.0 (Figma's own max) so the corner treatment is
/// unmistakable, not just a slightly-different rounded rect.
abstract final class AppShape {
  static const _smoothing = 0.85;

  static SmoothRectangleBorder control({BorderSide side = BorderSide.none}) => SmoothRectangleBorder(
        borderRadius: SmoothBorderRadius(cornerRadius: AppRadius.control, cornerSmoothing: _smoothing),
        side: side,
      );

  static SmoothRectangleBorder card({BorderSide side = BorderSide.none}) => SmoothRectangleBorder(
        borderRadius: SmoothBorderRadius(cornerRadius: AppRadius.card, cornerSmoothing: _smoothing),
        side: side,
      );

  /// Top-only rounding for bottom sheets.
  static SmoothRectangleBorder sheet({BorderSide side = BorderSide.none}) => SmoothRectangleBorder(
        borderRadius: SmoothBorderRadius.only(
          topLeft: SmoothRadius(cornerRadius: AppRadius.sheet, cornerSmoothing: _smoothing),
          topRight: SmoothRadius(cornerRadius: AppRadius.sheet, cornerSmoothing: _smoothing),
        ),
        side: side,
      );

  static final BorderRadius controlRadius = SmoothBorderRadius(cornerRadius: AppRadius.control, cornerSmoothing: _smoothing);
  static final BorderRadius cardRadius = SmoothBorderRadius(cornerRadius: AppRadius.card, cornerSmoothing: _smoothing);
}
