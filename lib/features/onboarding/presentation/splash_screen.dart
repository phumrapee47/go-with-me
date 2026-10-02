import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/tokens.dart';

/// Plays the brand mascot intro video once on every cold app open. Router's
/// splashElapsedProvider (AppConstants.splashDuration) navigates away on its
/// own timer — keep that duration matched to this video's length so the clip
/// finishes right as the app moves on, never cut off and never lingering.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset('assets/mascot/video/splash_intro.mp4')
      ..setVolume(0) // muted: no unexpected sound blast on app open
      ..initialize().then((_) {
        if (mounted) setState(() {});
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.mint,
      body: Center(
        child: _controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
