import 'package:flutter/material.dart';
import '../sensing/sleep_tracker.dart';
import '../data/models.dart';

const _phaseColors = {
  'awake': Color(0xFFFF8A80),
  'rem': Color(0xFF8C9EFF),
  'light': Color(0xFF6C7BFF),
  'deep': Color(0xFF3949AB),
};
const _phaseLevel = {'awake': 0, 'rem': 1, 'light': 2, 'deep': 3};

/// Loads a sample night (SimulatedNight) then shows ResultsScreen.
class ResultsDemoLoader extends StatelessWidget {
  const ResultsDemoLoader({super.key});
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TrackingResult>(
      future: SleepTracker().run(SimulatedNight(hours: 8)),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return ResultsScreen(result: snap.data!);
      },
    );
  }
}

class ResultsScreen extends StatelessWidget {
  final TrackingResult result;
  const ResultsScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final s = result.session;
    final pm = s.phaseMinutes;
    return Scaffold(
      appBar: AppBar(title: const Text('Last night')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _ScoreCard(score: s.sleepScore, asleep: s.minutesAsleep),
          const SizedBox(height: 20),
          Text('Sleep stages', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            height: 140,
            child: CustomPaint(
              painter: _HypnogramPainter(s.phases),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final e in pm.entries)
                _LegendChip(label: e.key, minutes: e.value),
            ],
          ),
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: const Icon(Icons.graphic_eq),
              title: const Text('Snoring'),
              subtitle: Text(s.snoreEvents == 0
                  ? 'No snore model connected (plug in your own)'
                  : '${s.snoreEvents} events · ${s.snorePercent.toStringAsFixed(0)}% of sleep'),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.bed),
              title: const Text('Time in bed'),
              subtitle: Text('${s.timeInBed.inHours}h '
                  '${s.timeInBed.inMinutes.remainder(60)}m'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final int score;
  final int asleep;
  const _ScoreCard({required this.score, required this.asleep});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Text('$score', style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold)),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sleep score'),
                Text('${asleep ~/ 60}h ${asleep.remainder(60)}m asleep',
                    style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final String label;
  final int minutes;
  const _LegendChip({required this.label, required this.minutes});
  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: CircleAvatar(backgroundColor: _phaseColors[label], radius: 7),
      label: Text('$label  ${minutes}m'),
    );
  }
}

class _HypnogramPainter extends CustomPainter {
  final List<PhasePoint> phases;
  _HypnogramPainter(this.phases);

  @override
  void paint(Canvas canvas, Size size) {
    if (phases.isEmpty) return;
    final n = phases.length;
    final rowH = size.height / 4;
    final paint = Paint()..strokeWidth = 2;
    for (var i = 0; i < n; i++) {
      final level = _phaseLevel[phases[i].phase] ?? 0;
      final x = size.width * i / n;
      final w = size.width / n + 1;
      paint.color = _phaseColors[phases[i].phase]!;
      final y = rowH * level;
      canvas.drawRect(Rect.fromLTWH(x, y, w, rowH), paint);
    }
  }

  @override
  bool shouldRepaint(_HypnogramPainter old) => old.phases != phases;
}
