import 'package:flutter/material.dart';
import '../data/models.dart';
import '../sensing/sleep_tracker.dart';
import 'results_screen.dart';
import 'night_view.dart';

/// "Tracking" screen. In a real build this runs overnight off the native
/// sensing service; here it runs a SimulatedNight so you can see the full
/// pipeline and the resulting hypnogram immediately.
class SleepSessionScreen extends StatefulWidget {
  final AlarmSettings settings;
  const SleepSessionScreen({super.key, required this.settings});

  @override
  State<SleepSessionScreen> createState() => _SleepSessionScreenState();
}

class _SleepSessionScreenState extends State<SleepSessionScreen> {
  bool _running = false;

  Future<void> _simulate() async {
    setState(() => _running = true);
    final tracker = SleepTracker();
    final result = await tracker.run(SimulatedNight(hours: 8));
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => ResultsScreen(result: result)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: NightView(caption: 'Phone on the mattress, screen down')),
          SafeArea(
            child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            Text('Alarm ${widget.settings.alarmTime}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 32),
            if (_running)
              const Column(children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Analyzing a simulated night…'),
              ])
            else
              FilledButton(
                onPressed: _simulate,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  child: Text('Simulate the night → results'),
                ),
              ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Real tracking samples the accelerometer and microphone through a '
                'native background service; the simulator exercises the same '
                'analysis pipeline without a device.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
