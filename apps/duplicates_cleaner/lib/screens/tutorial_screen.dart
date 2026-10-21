import 'package:flutter/material.dart';

import '../app.dart';
import 'home_screen.dart';

/// First-launch walkthrough (`TutorialActivity`), using the original copy.
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  static const _slides = [
    (
      Icons.waving_hand,
      'Welcome',
      'We request you to go through each slide prior to using the application.',
    ),
    (
      Icons.home_outlined,
      'Home Page',
      'Click on required option to scan duplicates.',
    ),
    (
      Icons.check_box_outlined,
      'Duplicate Selection',
      'Only checked files are deleted, you can check (or) uncheck any file.',
    ),
    (
      Icons.visibility_outlined,
      'View Files',
      'Click on image icon to view any file (image, audio, video, doc) in full screen.',
    ),
    (
      Icons.settings_outlined,
      'Settings',
      'Configure application settings at one place.',
    ),
    (
      Icons.verified_outlined,
      'Clean Genuine Duplicates',
      "Our app finds only 'Genuine Duplicates' (100% content match) rather than similar files.",
    ),
    (
      Icons.cleaning_services_outlined,
      'Stay Clean',
      'Keeping your device clean from WhatsApp, Facebook and other social media junk is our responsibility.',
    ),
    (
      Icons.workspace_premium_outlined,
      'Premium Version',
      'An optional premium version unlocks extra scan locations, scan types and filters.',
    ),
  ];

  final _controller = PageController();
  int _page = 0;

  void _finish() {
    AppScope.of(context).settings.firstLaunch = false;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen(showFreeLimits: true)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('Skip tutorial'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (p) => setState(() => _page = p),
                itemBuilder: (_, i) {
                  final (icon, title, desc) = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 64,
                          backgroundColor: AppColors.primary,
                          child: Icon(icon, size: 64, color: Colors.black87),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(desc, textAlign: TextAlign.center),
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
                    margin: const EdgeInsets.all(4),
                    width: i == _page ? 18 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page ? AppColors.accent : Colors.black26,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: last
                      ? _finish
                      : () => _controller.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        ),
                  child: Text(last ? 'Finish tutorial' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
