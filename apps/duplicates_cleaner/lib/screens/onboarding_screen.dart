import 'package:flutter/material.dart';

import '../app.dart';
import '../widgets/illustrations.dart';
import '../widgets/themed.dart';
import 'home_screen.dart';
import 'paywall_screen.dart';

/// First-launch walkthrough (`TutorialActivity`): four illustrated slides,
/// then the paywall for free users.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

typedef _Slide = (Widget art, String? eyebrow, String title, String body);

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const List<_Slide> _slides = [
    (
      AppMark(size: 210),
      'Welcome to the',
      'Duplicate Sweep',
      'Free up space by removing exact copies of your photos, music, '
          'videos and documents.',
    ),
    (
      CategoriesIllustration(),
      null,
      'Scan every file type',
      'Images, audio, video, documents, APKs or your own extensions. '
          'Pick a category and we do the rest.',
    ),
    (
      DuplicateSetIllustration(),
      null,
      'Only genuine duplicates',
      'Files are matched by their content, not their name, so only 100% '
          'identical copies are grouped together.',
    ),
    (
      SafeCleanIllustration(),
      null,
      'You stay in control',
      'Preview any file before cleaning. Only the files you check are '
          'deleted and the original is always kept.',
    ),
  ];

  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _last => _page == _slides.length - 1;

  void _next() => _controller.nextPage(
    duration: const Duration(milliseconds: 380),
    curve: Curves.easeOutCubic,
  );

  void _finish() {
    final scope = AppScope.of(context);
    scope.settings.firstLaunch = false;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => scope.premium.isPremium
            ? const HomeScreen()
            : const PaywallScreen(fromOnboarding: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => GradientBackground(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Align(
                alignment: Alignment.centerRight,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _last ? 0 : 1,
                  child: TextButton(
                    onPressed: _last ? null : _finish,
                    child: const Text('Skip'),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (p) => setState(() => _page = p),
                itemBuilder: (_, i) => _SlideView(
                  slide: _slides[i],
                  index: i,
                  controller: _controller,
                ),
              ),
            ),
            _Dots(count: _slides.length, active: _page),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: _last ? 'Get started' : 'Continue',
                  icon: _last ? Icons.auto_awesome : null,
                  pill: true,
                  onPressed: _last ? _finish : _next,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// One slide, with the art drifting and fading against the swipe.
class _SlideView extends StatelessWidget {
  const _SlideView({
    required this.slide,
    required this.index,
    required this.controller,
  });

  final _Slide slide;
  final int index;
  final PageController controller;

  @override
  Widget build(BuildContext context) {
    final (art, eyebrow, title, body) = slide;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final page = controller.hasClients && controller.position.haveDimensions
            ? controller.page ?? 0
            : 0.0;
        final delta = (page - index).clamp(-1.0, 1.0);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              Expanded(
                child: Opacity(
                  opacity: 1 - delta.abs() * 0.7,
                  child: Transform.translate(
                    offset: Offset(delta * 80, 0),
                    child: Transform.scale(
                      scale: 1 - delta.abs() * 0.12,
                      child: Center(
                        child: FittedBox(fit: BoxFit.scaleDown, child: art),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (eyebrow != null)
                Text(
                  eyebrow,
                  style: const TextStyle(fontSize: 15, color: AppColors.text),
                ),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        );
      },
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < count; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.all(4),
          width: i == active ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: i == active
                ? AppColors.primary
                : AppColors.primary.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
    ],
  );
}
