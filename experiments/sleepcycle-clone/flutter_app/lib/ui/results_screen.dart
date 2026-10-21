import 'package:flutter/material.dart';
import '../sensing/sleep_tracker.dart';
import '../data/models.dart';
import '../strings.dart';

const _phaseColors = {
  'awake': Color(0xFFFF8A80),
  'rem': Color(0xFF8C9EFF),
  'light': Color(0xFF6C7BFF),
  'deep': Color(0xFF3949AB),
};

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
          const SizedBox(height: 20),
          Text(S.get('wake_up_mood', 'Wake-up mood'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const _MoodRow(),
          const SizedBox(height: 20),
          Text(S.get('sleep_notes', 'Sleep notes'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(S.get('add_sleep_notes', 'Tag what might have affected your night'),
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 8),
          const _SleepNotes(),
        ],
      ),
    );
  }
}

/// Five-point wake-up mood, as in the original. Local state only here; a real
/// build logs it with the night and correlates it in Statistics.
class _MoodRow extends StatefulWidget {
  const _MoodRow();
  @override
  State<_MoodRow> createState() => _MoodRowState();
}

class _MoodRowState extends State<_MoodRow> {
  static const _faces = [
    ['😖', 'Awful'],
    ['🙁', 'Poor'],
    ['😐', 'Okay'],
    ['🙂', 'Good'],
    ['😄', 'Great'],
  ];
  int? _selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < _faces.length; i++)
          GestureDetector(
            onTap: () => setState(() => _selected = i),
            child: Column(
              children: [
                AnimatedScale(
                  scale: _selected == i ? 1.25 : 1,
                  duration: const Duration(milliseconds: 180),
                  child: Opacity(
                    opacity: _selected == null || _selected == i ? 1 : 0.4,
                    child: Text(_faces[i][0], style: const TextStyle(fontSize: 30)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(_faces[i][1],
                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Selectable sleep-note tags loaded from the string table (the comparison build
/// uses the real set; otherwise our own). Tapping shows the note's tip.
class _SleepNotes extends StatefulWidget {
  const _SleepNotes();
  @override
  State<_SleepNotes> createState() => _SleepNotesState();
}

class _SleepNotesState extends State<_SleepNotes> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final notes = S.sleepNotes;
    final tags = notes.isNotEmpty
        ? notes
        : const [
            SleepNote('coffee', 'Coffee', ''),
            SleepNote('stress', 'Stress', ''),
            SleepNote('exercise', 'Exercise', ''),
            SleepNote('alcohol', 'Alcohol', ''),
          ];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final n in tags)
          FilterChip(
            label: Text(n.title),
            selected: _selected.contains(n.id),
            onSelected: (v) {
              setState(() => v ? _selected.add(n.id) : _selected.remove(n.id));
              if (v && n.about.isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(n.about), duration: const Duration(seconds: 3)),
                );
              }
            },
          ),
      ],
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
                Text(S.get('sleep_quality', 'Sleep score')),
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

/// Smooth "wave" hypnogram: a soft depth curve (awake at the top, deep at the
/// bottom) with a gradient fill, instead of hard stepped bars — the look a
/// polished sleep app uses. Depth per epoch is smoothed so transitions read as
/// curves. Stage colors are conveyed by the legend chips below the chart.
class _HypnogramPainter extends CustomPainter {
  final List<PhasePoint> phases;
  _HypnogramPainter(this.phases);

  // depth: awake=0 (top) ... deep=3 (bottom)
  static const _depth = {'awake': 0.0, 'rem': 1.0, 'light': 2.0, 'deep': 3.0};

  @override
  void paint(Canvas canvas, Size size) {
    if (phases.isEmpty) return;
    final n = phases.length;
    // raw depth then a light moving-average smoothing
    final raw = [for (final p in phases) _depth[p.phase] ?? 0.0];
    final sm = <double>[];
    const r = 4;
    for (var i = 0; i < n; i++) {
      var acc = 0.0, cnt = 0;
      for (var j = i - r; j <= i + r; j++) {
        if (j >= 0 && j < n) {
          acc += raw[j];
          cnt++;
        }
      }
      sm.add(acc / cnt);
    }
    double x(int i) => size.width * i / (n - 1).clamp(1, 1 << 30);
    double y(double d) => 6 + (d / 3.0) * (size.height - 12);
    final pts = [for (var i = 0; i < n; i++) Offset(x(i), y(sm[i]))];

    // gridlines per stage row
    final grid = Paint()..color = Colors.white10..strokeWidth = 1;
    for (var l = 0; l <= 3; l++) {
      final yy = y(l.toDouble());
      canvas.drawLine(Offset(0, yy), Offset(size.width, yy), grid);
    }

    // smooth path via midpoint quadratics
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final mid = Offset((pts[i - 1].dx + pts[i].dx) / 2, (pts[i - 1].dy + pts[i].dy) / 2);
      line.quadraticBezierTo(pts[i - 1].dx, pts[i - 1].dy, mid.dx, mid.dy);
    }
    line.lineTo(pts.last.dx, pts.last.dy);

    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x668C9EFF), Color(0x11050814)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = const Color(0xFF8C9EFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_HypnogramPainter old) => old.phases != phases;
}
