import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../theme.dart';
import '../strings.dart';

/// Guided onboarding. The first step plays the app's real vector animation
/// (Lottie) when the asset is present, matching the original's animated intro;
/// the consent steps use the real microphone/notification perk copy from the
/// string table, falling back to an icon when no animation is bundled.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pager = PageController();
  int _page = 0;

  late final List<_Step> _steps = [
    _Step(
      lottie: 'assets/lottie/animated_onboarding.json',
      icon: Icons.nightlight_round,
      title: S.get('app_name', 'Sleep Tracker'),
      body: 'Track every night and wake up gently, at your lightest moment.',
      perks: const [],
    ),
    _Step(
      icon: Icons.mic_none,
      title: S.get('ob_mic_headline', 'Allow microphone access to:'),
      perks: [
        S.get('ob_mic_perk_analysis'),
        S.get('ob_mic_perk_discovery'),
        S.get('ob_mic_perk_alarm'),
      ].where((e) => e.isNotEmpty).toList(),
      footnote: S.get('ob_privacy'),
    ),
    _Step(
      icon: Icons.notifications_none,
      title: S.get('ob_notif_headline', 'Turn on notifications to:'),
      perks: [
        S.get('ob_notif_perk_reminders'),
        S.get('ob_notif_perk_patterns'),
      ].where((e) => e.isNotEmpty).toList(),
    ),
  ];

  void _next() {
    if (_page == _steps.length - 1) {
      Navigator.pop(context, true);
    } else {
      _pager.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppTheme.nightGradient),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pager,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemCount: _steps.length,
                  itemBuilder: (context, i) => _StepView(step: _steps[i]),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _steps.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.all(4),
                      width: i == _page ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page ? AppTheme.primary : Colors.white24,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _next,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(_page == _steps.length - 1
                          ? 'Get started'
                          : S.get('ob_next', 'Next')),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step {
  final String? lottie;
  final IconData icon;
  final String title;
  final String body;
  final List<String> perks;
  final String? footnote;
  const _Step({
    this.lottie,
    required this.icon,
    required this.title,
    this.body = '',
    this.perks = const [],
    this.footnote,
  });
}

class _StepView extends StatelessWidget {
  final _Step step;
  const _StepView({required this.step});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: 180, child: _Art(step: step)),
          const SizedBox(height: 36),
          Text(step.title,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center),
          if (step.body.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(step.body,
                style: const TextStyle(color: Colors.white70, height: 1.4),
                textAlign: TextAlign.center),
          ],
          if (step.perks.isNotEmpty) ...[
            const SizedBox(height: 20),
            for (final p in step.perks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle, size: 20, color: AppTheme.accent),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(p, style: const TextStyle(color: Colors.white, height: 1.3))),
                  ],
                ),
              ),
          ],
          if (step.footnote != null && step.footnote!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(step.footnote!,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

/// Plays the Lottie animation if bundled; otherwise an animated icon badge so
/// the flow still looks alive without the asset.
class _Art extends StatelessWidget {
  final _Step step;
  const _Art({required this.step});

  @override
  Widget build(BuildContext context) {
    if (step.lottie != null) {
      return Lottie.asset(
        step.lottie!,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _iconBadge(),
      );
    }
    return _iconBadge();
  }

  Widget _iconBadge() => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.8, end: 1),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutBack,
        builder: (context, s, child) => Transform.scale(scale: s, child: child),
        child: Container(
          width: 140,
          height: 140,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.surfaceHi),
          child: Icon(step.icon, size: 68, color: AppTheme.accent),
        ),
      );
}
