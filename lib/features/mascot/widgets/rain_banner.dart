import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// Mascot dangling from a blank sign, with the message rendered as real text
/// (never baked into the AI-generated art — non-Latin text from image models
/// is unreliable) positioned over the sign's blank card.
class RainBanner extends StatelessWidget {
  const RainBanner({super.key, this.width = 220, this.message = 'วันนี้ฝนตก หาคนกลับบ้านด้วยดีกว่าน้าา'});

  final double width;
  final String message;

  static const _asset = 'assets/mascot/banners/rain_sign.png';
  static const _aspect = 864 / 1184;
  // Fractional bounds of the blank sign card within the source image
  // (measured once from the asset's alpha/pixel data).
  static const _signTop = 223 / 1184;
  static const _signBottom = 599 / 1184;
  static const _signLeft = 132 / 864;
  static const _signRight = 718 / 864;

  @override
  Widget build(BuildContext context) {
    final height = width / _aspect;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Image.asset(_asset, width: width, height: height, fit: BoxFit.contain, semanticLabel: message),
          Positioned(
            top: height * _signTop,
            bottom: height * (1 - _signBottom),
            left: width * _signLeft,
            right: width * (1 - _signRight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w600, height: 1.3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
