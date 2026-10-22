import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../data/models.dart';
import '../../theme.dart';

/// Theme-aware building blocks shared by the redesigned screens: glass cards,
/// the pill segmented control, the stage ring, stacked stage bars, stat tiles
/// and the insight card. All colors come from `context.palette`.

/// Rounded card with a hairline border, the base surface of every theme.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = BorderRadius.circular(p.radius);
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: p.stroke)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// Small caps label with a sparkle, as above "Personal insights".
class Eyebrow extends StatelessWidget {
  final String text;
  final IconData icon;
  const Eyebrow(this.text, {super.key, this.icon = Icons.auto_awesome});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(children: [
      Icon(icon, size: 13, color: p.textMuted),
      const SizedBox(width: 6),
      Text(text.toUpperCase(),
          style:
              TextStyle(color: p.textMuted, fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w500)),
    ]);
  }
}

/// Pill-shaped segmented control: a rounded track with a contrasting thumb.
class SegmentedPill extends StatelessWidget {
  final List<String> labels;
  final int value;
  final ValueChanged<int> onChanged;
  const SegmentedPill({super.key, required this.labels, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.segTrack,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: p.stroke),
      ),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: value == i ? p.segThumb : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: value == i && !p.isDark
                      ? [
                          BoxShadow(
                              color: p.text.withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 3))
                        ]
                      : null,
                ),
                child: Text(labels[i],
                    style: TextStyle(
                        color: value == i ? p.segThumbText : p.textMuted,
                        fontSize: 15,
                        fontWeight: value == i ? FontWeight.w600 : FontWeight.w400)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Majority vote over a sliding window so stage charts read as bands rather
/// than per-epoch flicker. Display only; the stored night is untouched.
List<String> smoothStages(List<PhasePoint> phases, {int window = 15}) {
  final n = phases.length, half = window ~/ 2;
  return [
    for (var i = 0; i < n; i++)
      () {
        final counts = <String, int>{};
        for (var j = math.max(0, i - half); j <= math.min(n - 1, i + half); j++) {
          counts.update(phases[j].phase, (c) => c + 1, ifAbsent: () => 1);
        }
        return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
      }()
  ];
}

/// Word for a 0–100 quality score.
String scoreWord(int q) => q >= 85
    ? 'Great'
    : q >= 70
        ? 'Good'
        : q >= 50
            ? 'Fair'
            : 'Poor';

/// The night as a ring: the stage sequence wraps clockwise from bedtime
/// (moon badge) to wake-up (sun badge), with the score word and time asleep
/// in a softly lit center.
class StageRing extends StatelessWidget {
  final List<PhasePoint> phases;
  final int quality;
  final String subtitle;
  final double size;
  const StageRing(
      {super.key, required this.phases, required this.quality, required this.subtitle, this.size = 260});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _StageRingPainter(phases, p),
        child: Stack(children: [
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(scoreWord(quality),
                  style: TextStyle(fontSize: size * 0.135, fontWeight: FontWeight.w600, color: p.text)),
              Text(subtitle, style: TextStyle(fontSize: size * 0.07, color: p.textMuted)),
            ]),
          ),
          // badges at the start and end of the arc
          for (final (angle, icon, color) in [
            (_StageRingPainter.start, Icons.nightlight_round, p.deep),
            (_StageRingPainter.start + _StageRingPainter.sweep, Icons.wb_sunny_outlined, p.rem),
          ])
            Positioned(
              left: size / 2 + math.cos(angle) * (size / 2 - size * 0.06) - 15,
              top: size / 2 + math.sin(angle) * (size / 2 - size * 0.06) - 15,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                    color: color, shape: BoxShape.circle, border: Border.all(color: p.bg, width: 2)),
                child: Icon(icon, size: 16, color: p.isDark ? Colors.white : Colors.white),
              ),
            ),
        ]),
      ),
    );
  }
}

class _StageRingPainter extends CustomPainter {
  final List<PhasePoint> phases;
  final SleepPalette p;
  _StageRingPainter(this.phases, this.p);

  // a small gap at the top-left keeps the start/end badges apart
  static const start = -math.pi / 2 - 0.55;
  static const sweep = 2 * math.pi - 0.62;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final stroke = size.width * 0.12;
    final r = size.width / 2 - stroke / 2;
    // center bloom
    canvas.drawCircle(
        c,
        r - stroke / 2,
        Paint()
          ..shader = RadialGradient(
              colors: [p.glow, p.glow.withOpacity(0), p.bg.withOpacity(0)],
              stops: const [0, 0.8, 1]).createShader(Rect.fromCircle(center: c, radius: r)));
    canvas.drawCircle(
        c,
        r - stroke / 2 - 1,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = p.stroke);
    final rect = Rect.fromCircle(center: c, radius: r);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = p.surfaceHi;
    canvas.drawArc(rect, start, sweep, false, track);
    if (phases.isEmpty) return;
    // merge runs so the ring reads as bands, not hundreds of slivers
    final runs = <(String, int)>[];
    for (final ph in smoothStages(phases)) {
      if (runs.isNotEmpty && runs.last.$1 == ph) {
        runs[runs.length - 1] = (ph, runs.last.$2 + 1);
      } else {
        runs.add((ph, 1));
      }
    }
    final n = phases.length;
    var a = start;
    final seg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    for (final (phase, len) in runs) {
      final s = sweep * len / n;
      // awake moments are drawn as thin markers like the reference
      seg.color = p.phase(phase);
      canvas.drawArc(rect, a, phase == 'awake' ? math.max(s, 0.03) : s + 0.004, false, seg);
      a += s;
    }
    // smoothing hides brief wake-ups; mark any that lasted a minute or more
    seg.color = p.awake;
    for (var i = 0; i < n - 1; i++) {
      if (phases[i].phase == 'awake' &&
          phases[i + 1].phase == 'awake' &&
          (i == 0 || phases[i - 1].phase != 'awake')) {
        canvas.drawArc(rect, start + sweep * i / n, 0.025, false, seg);
      }
    }
  }

  @override
  bool shouldRepaint(_StageRingPainter old) => old.phases != phases || old.p != p;
}

/// One vertical rounded bar per night, banded by stage from bedtime (top) to
/// wake-up (bottom), aligned on a shared clock axis.
class StageBars extends StatelessWidget {
  final List<(String, DateTime, List<PhasePoint>)> nights; // label, start, phases
  final double height;
  const StageBars({super.key, required this.nights, this.height = 180});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(children: [
      SizedBox(
          height: height, child: CustomPaint(painter: _StageBarsPainter(nights, p), size: Size.infinite)),
      const SizedBox(height: 10),
      Row(children: [
        for (final n in nights)
          Expanded(
              child: Text(n.$1,
                  textAlign: TextAlign.center, style: TextStyle(color: p.textMuted, fontSize: 12))),
        const SizedBox(width: 44),
      ]),
    ]);
  }
}

class _StageBarsPainter extends CustomPainter {
  final List<(String, DateTime, List<PhasePoint>)> nights;
  final SleepPalette p;
  _StageBarsPainter(this.nights, this.p);

  // minutes after 18:00 so evening → morning sorts on one axis
  static double _clock(DateTime t) => ((t.hour - 18) % 24) * 60.0 + t.minute;

  @override
  void paint(Canvas canvas, Size size) {
    if (nights.isEmpty) return;
    const axisW = 44.0;
    final w = size.width - axisW;
    var lo = double.infinity, hi = -double.infinity;
    for (final n in nights) {
      final s = _clock(n.$2);
      lo = math.min(lo, s);
      hi = math.max(hi, s + n.$3.length / 2);
    }
    lo = (lo / 60).floor() * 60;
    hi = (hi / 60).ceil() * 60;
    double y(double m) => (m - lo) / (hi - lo) * size.height;

    // clock labels every few hours on the right
    final tp = TextPainter(textDirection: TextDirection.ltr);
    final step = ((hi - lo) / 60 / 3).ceil().clamp(1, 6) * 60;
    for (var m = lo; m <= hi; m += step) {
      final hh = ((m ~/ 60) + 18) % 24;
      tp.text = TextSpan(
          text: '${hh.toString().padLeft(2, '0')}:00',
          style: TextStyle(color: p.textMuted, fontSize: 11, fontFamily: p.fontFamily));
      tp.layout();
      tp.paint(
          canvas, Offset(size.width - tp.width, (y(m) - tp.height / 2).clamp(0, size.height - tp.height)));
    }

    final slot = w / nights.length;
    final bw = math.min(slot * 0.62, 30.0);
    for (var i = 0; i < nights.length; i++) {
      final (_, start, phases) = nights[i];
      if (phases.isEmpty) continue;
      final x = slot * (i + 0.5);
      final top = y(_clock(start)), bottom = y(_clock(start) + phases.length / 2);
      final bar = RRect.fromRectAndRadius(
          Rect.fromLTRB(x - bw / 2, top, x + bw / 2, bottom), Radius.circular(bw * 0.28));
      canvas.save();
      canvas.clipRRect(bar);
      final stages = smoothStages(phases);
      final per = (bottom - top) / stages.length;
      var j = 0;
      while (j < stages.length) {
        var k = j;
        while (k < stages.length && stages[k] == stages[j]) {
          k++;
        }
        final ph = stages[j];
        final y0 = top + j * per, y1 = top + k * per;
        canvas.drawRect(
            Rect.fromLTRB(x - bw / 2, y0, x + bw / 2, ph == 'awake' ? math.max(y1, y0 + 2.5) : y1 + 0.5),
            Paint()..color = p.phase(ph));
        j = k;
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_StageBarsPainter old) => old.nights != nights || old.p != p;
}

/// Stage tile: colored chip + label, a big value with small units, and a
/// one-line status ("In range", "Below avg").
class StatTile extends StatelessWidget {
  final Color color;
  final String label;
  final int minutes;
  final String? status;
  final IconData statusIcon;
  const StatTile(
      {super.key,
      required this.color,
      required this.label,
      required this.minutes,
      this.status,
      this.statusIcon = Icons.check_circle});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final h = minutes ~/ 60, m = minutes.remainder(60);
    final big = TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: p.text, height: 1.1);
    final small = TextStyle(fontSize: 15, color: p.textMuted);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: p.textMuted, fontSize: 14)),
        ]),
        const SizedBox(height: 14),
        Text.rich(TextSpan(children: [
          if (h > 0) ...[TextSpan(text: '$h', style: big), TextSpan(text: ' h ', style: small)],
          TextSpan(text: '$m', style: big),
          TextSpan(text: ' min', style: small),
        ])),
        if (status != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            Icon(statusIcon, size: 15, color: p.textMuted),
            const SizedBox(width: 5),
            Text(status!, style: TextStyle(color: p.textMuted, fontSize: 13)),
          ]),
        ],
      ]),
    );
  }
}

/// Icon disc + bold title + supporting text.
class InsightCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const InsightCard({super.key, required this.icon, required this.title, required this.body});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GlassCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          height: 44,
          decoration:
              BoxDecoration(color: p.surfaceHi, shape: BoxShape.circle, border: Border.all(color: p.stroke)),
          child: Icon(icon, color: p.text, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.text)),
            const SizedBox(height: 6),
            Text(body, style: TextStyle(color: p.textMuted, height: 1.45)),
          ]),
        ),
      ]),
    );
  }
}

/// Little legend dot + label.
class LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const LegendDot(this.color, this.label, {super.key});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: context.palette.textMuted, fontSize: 12)),
      ]);
}
