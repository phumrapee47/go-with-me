import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_logo.dart';
import 'onboarding_providers.dart';

class _Slide {
  const _Slide(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

const _slides = [
  _Slide(Icons.people_alt_outlined, S.onboard1Title, S.onboard1Body),
  _Slide(Icons.shield_outlined, S.onboard2Title, S.onboard2Body),
  _Slide(Icons.location_searching_outlined, S.onboard3Title, S.onboard3Body),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _last => _page == _slides.length - 1;

  // Setting the flag makes the router redirect to sign-in.
  void _finish() => ref.read(onboardingDoneProvider.notifier).complete();

  void _next() {
    if (_last) {
      _finish();
    } else {
      final reduce = MediaQuery.of(context).disableAnimations;
      _controller.nextPage(
        duration: reduce ? Duration.zero : const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _finish, child: const Text(S.skip)),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final s = _slides[i];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: AppSpacing.xl),
                        if (i == 0)
                          const AppLogo(size: 96)
                        else
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.xxl),
                            decoration: const BoxDecoration(
                              color: AppColors.mint,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(s.icon, size: 72, color: AppColors.tealDark),
                          ),
                        const SizedBox(height: AppSpacing.xxl),
                        Text(s.title, style: theme.textTheme.displayMedium, textAlign: TextAlign.center),
                        const SizedBox(height: AppSpacing.md),
                        Text(s.body, style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _slides.length; i++)
                  Container(
                    margin: const EdgeInsets.all(AppSpacing.xs),
                    width: i == _page ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page ? AppColors.blue : AppColors.border,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: AppButton(label: _last ? S.onboardStart : S.next, onPressed: _next),
            ),
          ],
        ),
      ),
    );
  }
}
