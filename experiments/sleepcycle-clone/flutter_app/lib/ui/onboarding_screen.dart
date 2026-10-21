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
    _Step(
      icon: Icons.alarm,
      title: S.get('wake_window_headline', "Set tomorrow's wake-up time"),
      body: S.get('wake_window_help', 'Wake me during light sleep no later than'),
      bigValue: '07:30',
      footnote: 'We wake you in a ±30 min window, at your lightest moment. '
          'Fine-tune it anytime in Alarm settings.',
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
  final String? bigValue;
  const _Step({
    this.lottie,
    required this.icon,
    required this.title,
    this.body = '',
    this.perks = const [],
    this.footnote,
    this.bigValue,
  });
}

class _StepView extends StatelessWidget {
  final _Step step;
  const _StepView({required this.step});

  @override
  Widget build(BuildContext context) {
    // The intro page is full-bleed: the animation fills the page area with the
    // headline overlaid at the bottom over a scrim (like the real app's intro).
    if (step.lottie != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Lottie.asset(step.lottie!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const DecoratedBox(decoration: BoxDecoration(gradient: AppTheme.nightGradient))),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xCC080B18)],
                ),
              ),
            ),
          ),
          Positioned(
            left: 28,
            right: 28,
            bottom: 36,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(step.title,
                    style: Theme.of(context)
                        .textTheme
                        .displaySmall
                        ?.copyWith(fontWeight: FontWeight.w800, height: 1.05)),
                if (step.body.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(step.body,
                      style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.4)),
                ],
              ],
            ),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: step.lottie != null ? 300 : 170,
            child: _Art(step: step),
          ),
          const SizedBox(height: 32),
          Text(step.title,
              style: (step.lottie != null
                      ? Theme.of(context).textTheme.headlineMedium
                      : Theme.of(context).textTheme.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
          if (step.body.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(step.body,
                style: const TextStyle(color: Colors.white70, height: 1.4),
                textAlign: TextAlign.center),
          ],
          if (step.bigValue != null) ...[
            const SizedBox(height: 16),
            Text(step.bigValue!,
                style: const TextStyle(
                    fontSize: 56, fontWeight: FontWeight.bold, color: AppTheme.accent)),
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
