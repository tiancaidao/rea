import 'package:flutter/material.dart';
import '../theme.dart';
import '../sensing/sleep_tracker.dart';
import '../data/models.dart';

/// Trends over several nights: a sleep-score line chart + average stage
/// breakdown, both hand-painted (no chart dependency). Generates a week of
/// simulated nights so the screen is populated; a real build reads your session
/// history from the backend / local store.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  List<SleepSession>? _nights;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tracker = SleepTracker();
    final out = <SleepSession>[];
    for (var i = 0; i < 7; i++) {
      final r = await tracker.run(SimulatedNight(hours: 7, seed: 10 + i));
      out.add(r.session);
    }
    if (mounted) setState(() => _nights = out);
  }

  @override
  Widget build(BuildContext context) {
    final nights = _nights;
    return Scaffold(
      appBar: AppBar(title: const Text('Trends')),
      body: nights == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Sleep score · last ${nights.length} nights',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                SizedBox(
                  height: 160,
                  child: CustomPaint(
                    painter: _LinePainter(nights.map((n) => n.sleepScore.toDouble()).toList()),
                    size: Size.infinite,
                  ),
                ),
                const SizedBox(height: 28),
                Text('Average time in each stage',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                _StageBars(nights: nights),
                const SizedBox(height: 28),
                _AverageRow(nights: nights),
              ],
            ),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<double> values;
  _LinePainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const maxV = 100.0;
    final dx = size.width / (values.length - 1).clamp(1, 999);
    final pts = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(i * dx, size.height - (values[i] / maxV) * size.height),
    ];
    // gridlines
    final grid = Paint()..color = Colors.white10..strokeWidth = 1;
    for (var g = 0; g <= 4; g++) {
      final y = size.height * g / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    // area fill
    final fill = Path()..moveTo(pts.first.dx, size.height);
    for (final p in pts) {
      fill.lineTo(p.dx, p.dy);
    }
    fill.lineTo(pts.last.dx, size.height);
    fill.close();
    canvas.drawPath(fill, Paint()..color = AppTheme.primary.withOpacity(0.18));
    // line
    final line = Paint()
      ..color = AppTheme.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, line);
    final dot = Paint()..color = AppTheme.accent;
    for (final p in pts) {
      canvas.drawCircle(p, 3.5, dot);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.values != values;
}

class _StageBars extends StatelessWidget {
  final List<SleepSession> nights;
  const _StageBars({required this.nights});

  @override
  Widget build(BuildContext context) {
    final totals = {'deep': 0, 'light': 0, 'rem': 0, 'awake': 0};
    for (final n in nights) {
      n.phaseMinutes.forEach((k, v) => totals[k] = (totals[k] ?? 0) + v);
    }
    final avg = totals.map((k, v) => MapEntry(k, v ~/ nights.length));
    final maxV = (avg.values.isEmpty ? 1 : avg.values.reduce((a, b) => a > b ? a : b)).clamp(1, 9999);
    return Column(
      children: [
        for (final e in avg.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(width: 56, child: Text(e.key)),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: e.value / maxV,
                      minHeight: 14,
                      backgroundColor: Colors.white10,
                      color: AppTheme.phaseColors[e.key],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(width: 56, child: Text('${e.value ~/ 60}h ${e.value % 60}m',
                    textAlign: TextAlign.right)),
              ],
            ),
          ),
      ],
    );
  }
}

class _AverageRow extends StatelessWidget {
  final List<SleepSession> nights;
  const _AverageRow({required this.nights});
  @override
  Widget build(BuildContext context) {
    final avgScore = nights.map((n) => n.sleepScore).reduce((a, b) => a + b) ~/ nights.length;
    final avgAsleep = nights.map((n) => n.minutesAsleep).reduce((a, b) => a + b) ~/ nights.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _Stat(label: 'Avg score', value: '$avgScore'),
        _Stat(label: 'Avg asleep', value: '${avgAsleep ~/ 60}h ${avgAsleep % 60}m'),
        _Stat(label: 'Nights', value: '${nights.length}'),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }
}
