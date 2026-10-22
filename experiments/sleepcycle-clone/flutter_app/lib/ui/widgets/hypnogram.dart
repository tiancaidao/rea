import 'package:flutter/material.dart';
import '../../data/models.dart';
import '../../theme.dart';

/// Smooth "wave" hypnogram: depth curve (Awake at top, Deep sleep at bottom)
/// drawn as a moving-average of per-epoch stages so transitions read as waves
/// rather than steps. Optional row labels on the left and hour ticks below,
/// like the Journal graph.
class Hypnogram extends StatelessWidget {
  final List<PhasePoint> phases;
  final DateTime? start;
  final double height;
  final bool labels;
  const Hypnogram(
      {super.key, required this.phases, this.start, this.height = 150, this.labels = true});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = TextStyle(color: p.textMuted, fontSize: 12);
    final chart = SizedBox(
      height: height,
      child: CustomPaint(painter: HypnogramPainter(phases, p), size: Size.infinite),
    );
    if (!labels) return chart;
    final hours = <int>[];
    if (start != null && phases.isNotEmpty) {
      final end = start!.add(Duration(seconds: 30 * phases.length));
      var t = DateTime(start!.year, start!.month, start!.day, start!.hour + 1);
      while (t.isBefore(end)) {
        hours.add(t.hour);
        t = t.add(const Duration(hours: 1));
      }
    }
    return Column(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 62,
          height: height,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Awake', style: style),
              Text('Sleep', style: style),
              Text('Deep\nsleep', style: style),
            ],
          ),
        ),
        Expanded(child: chart),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        SizedBox(width: 62, child: Text('Time', style: style)),
        Expanded(
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            for (final h in hours) Text('${h % 12 == 0 ? 12 : h % 12}', style: style),
          ]),
        ),
      ]),
    ]);
  }
}

class HypnogramPainter extends CustomPainter {
  final List<PhasePoint> phases;
  final SleepPalette p;
  HypnogramPainter(this.phases, this.p);

  // depth: awake=0 (top) ... deep=3 (bottom)
  static const _depth = {'awake': 0.0, 'rem': 1.0, 'light': 2.0, 'deep': 3.0};

  @override
  void paint(Canvas canvas, Size size) {
    if (phases.isEmpty) return;
    final n = phases.length;
    final raw = [for (final p in phases) _depth[p.phase] ?? 0.0];
    final sm = <double>[];
    final r = (n / 40).round().clamp(4, 40);
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
    double y(double d) => 4 + (d / 3.0) * (size.height - 8);
    final pts = [for (var i = 0; i < n; i++) Offset(x(i), y(sm[i]))];

    final grid = Paint()
      ..color = p.divider
      ..strokeWidth = 1;
    for (var l = 0; l <= 3; l++) {
      final yy = y(l.toDouble());
      canvas.drawLine(Offset(0, yy), Offset(size.width, yy), grid);
    }

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
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.light.withOpacity(0.35), p.deep.withOpacity(0.02)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        // stroke shades by depth: awake at the top through to deep sleep
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.awake, p.rem, p.light, p.deep],
        ).createShader(Offset.zero & size)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(HypnogramPainter old) => old.phases != phases || old.p != p;
}
