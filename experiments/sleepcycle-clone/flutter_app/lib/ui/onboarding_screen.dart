import 'package:flutter/material.dart';
import '../theme.dart';

/// A guided, animated multi-step onboarding — the kind of flow a polished sleep
/// app opens with (welcome → goal → profile → permissions). Returns when done.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pager = PageController();
  int _page = 0;

  final _steps = const [
    _Step(Icons.nightlight_round, 'Sleep better',
        'Track your nights and wake up gently, at the lightest moment.'),
    _Step(Icons.flag_outlined, 'Your goal',
        'Aim for a consistent schedule. We’ll learn your rhythm over time.'),
    _Step(Icons.favorite_outline, 'Your profile',
        'A few basics help tailor insights. You can change them anytime.'),
    _Step(Icons.mic_none, 'Permissions',
        'Motion and microphone let us detect movement and snoring overnight.'),
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
                      child: Text(_page == _steps.length - 1 ? 'Get started' : 'Continue'),
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
  final IconData icon;
  final String title;
  final String body;
  const _Step(this.icon, this.title, this.body);
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
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.8, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutBack,
            builder: (context, s, child) => Transform.scale(scale: s, child: child),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.surfaceHi,
              ),
              child: Icon(step.icon, size: 72, color: AppTheme.accent),
            ),
          ),
          const SizedBox(height: 40),
          Text(step.title,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(step.body,
              style: const TextStyle(color: Colors.white70, height: 1.4),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
