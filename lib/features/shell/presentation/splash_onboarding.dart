import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/data/auth_repository.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});
  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('onboarding_seen') ?? false;
    if (!mounted) return;
    if (!seen) {
      context.go('/onboarding');
      return;
    }
    final loggedIn = ref.read(authControllerProvider).isLoggedIn;
    context.go(loggedIn ? '/home' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 150,
              height: 150,
              child: Lottie.asset(
                'assets/lottie/recycle_hero.json',
                errorBuilder: (_, _, _) => const Icon(
                  Icons.recycling,
                  size: 96,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text('RecyGo', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 6),
            const Text('Turn used items into something new.'),
          ],
        ),
      ),
    );
  }
}

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    (
      'assets/lottie/recycle_hero.json',
      'Snap. Separate. Save.',
      'Take one photo of many used items — AI separates them into clean catalog items automatically.',
    ),
    (
      'assets/lottie/ai_thinking.json',
      'Fuse with AI',
      'Combine your used items into brand-new creations, complete with steps and illustrations.',
    ),
    (
      'assets/lottie/success.json',
      'Share & Earn',
      'Publish to the Community, chat via WhatsApp, or sell to the nearest waste bank.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;
    return Scaffold(
      appBar: AppBar(
        actions: [TextButton(onPressed: _finish, child: const Text('Skip'))],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) {
                final (asset, title, subtitle) = _pages[i];
                return Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 200,
                        height: 200,
                        child: Lottie.asset(
                          asset,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.recycling,
                            size: 110,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(subtitle, textAlign: TextAlign.center),
                    ],
                  ),
                );
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = 0; i < _pages.length; i++)
                Container(
                  width: _page == i ? 22 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: _page == i
                        ? AppColors.primary
                        : AppColors.muted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              child: AppButton(
                label: isLast ? 'Get Started' : 'Next',
                onPressed: () {
                  if (isLast) {
                    _finish();
                  } else {
                    _controller.nextPage(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOut,
                    );
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
