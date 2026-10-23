import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme.dart';

/// Our own vector illustrations, drawn in the theme's colors, for the places
/// the original shows illustrations (placement and snooze tips, settings
/// heroes, Benefits) and for sleep-aid / program cover art. No bitmaps.
enum Art { placementMic, placementBed, snooze, gift, sleepGoal, alarm, weeklyReport, sleepNotes, motion }

class Illustration extends StatelessWidget {
  final Art art;
  final double size;
  const Illustration(this.art, {super.key, this.size = 240});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _IllustrationPainter(art, context.palette)),
      );
}

class _IllustrationPainter extends CustomPainter {
  final Art art;
  final SleepPalette p;
  _IllustrationPainter(this.art, this.p);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    // backdrop disc
    canvas.drawCircle(
        c,
        s / 2,
        Paint()
          ..shader = LinearGradient(colors: [p.light, p.deep], begin: Alignment.topLeft, end: Alignment.bottomRight)
              .createShader(Offset.zero & size));
    canvas.save();
    canvas.clipPath(Path()..addOval(Offset.zero & size));
    switch (art) {
      case Art.placementMic:
        _nightstand(canvas, s);
      case Art.placementBed:
        _bed(canvas, s);
      case Art.snooze:
        _snooze(canvas, s);
      case Art.gift:
        _gift(canvas, s);
      case Art.sleepGoal:
        _target(canvas, s);
      case Art.alarm:
        _clock(canvas, s);
      case Art.weeklyReport:
        _report(canvas, s);
      case Art.sleepNotes:
        _notes(canvas, s);
      case Art.motion:
        _bed(canvas, s, waves: true);
    }
    canvas.restore();
  }

  Paint get _ink => Paint()..color = Colors.white;
  Paint get _soft => Paint()..color = Colors.white.withValues(alpha: 0.35);
  Paint _line(double w) => Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round;

  Path _phone(double x, double y, double w, double h) =>
      Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(w * 0.14)));

  void _stars(Canvas canvas, double s, int n, {double top = 0.45}) {
    final rng = math.Random(5);
    for (var i = 0; i < n; i++) {
      canvas.drawCircle(Offset(rng.nextDouble() * s, rng.nextDouble() * s * top), 1 + rng.nextDouble() * 1.6, _soft);
    }
  }

  // phone lying screen-down on a nightstand next to the bed, cable plugged in
  void _nightstand(Canvas canvas, double s) {
    _stars(canvas, s, 18);
    canvas.drawCircle(Offset(s * 0.72, s * 0.24), s * 0.07, _ink);
    canvas.drawRect(Rect.fromLTWH(s * 0.18, s * 0.58, s * 0.38, s * 0.06), _ink); // table top
    canvas.drawRect(Rect.fromLTWH(s * 0.22, s * 0.64, s * 0.3, s * 0.36), _soft);
    canvas.drawPath(_phone(s * 0.26, s * 0.535, s * 0.2, s * 0.045), Paint()..color = p.deep);
    final cable = Path()
      ..moveTo(s * 0.46, s * 0.56)
      ..quadraticBezierTo(s * 0.56, s * 0.56, s * 0.54, s * 0.8);
    canvas.drawPath(cable, _line(s * 0.012));
    // bed edge on the right
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.6, s * 0.5, s * 0.6, s * 0.22), Radius.circular(s * 0.04)), _soft);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.62, s * 0.44, s * 0.22, s * 0.08), Radius.circular(s * 0.04)),
        _ink);
    // sound waves going up from the phone
    for (var i = 1; i <= 3; i++) {
      canvas.drawArc(Rect.fromCircle(center: Offset(s * 0.36, s * 0.5), radius: s * 0.05 * i), -math.pi * 0.8,
          math.pi * 0.6, false, _line(s * 0.01)..color = Colors.white.withValues(alpha: 1 - i * 0.25));
    }
  }

  // phone on the mattress by the pillow
  void _bed(Canvas canvas, double s, {bool waves = false}) {
    _stars(canvas, s, 14, top: 0.35);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.08, s * 0.5, s * 0.84, s * 0.3), Radius.circular(s * 0.05)), _soft);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.14, s * 0.42, s * 0.3, s * 0.12), Radius.circular(s * 0.06)), _ink);
    canvas.drawPath(_phone(s * 0.5, s * 0.46, s * 0.2, s * 0.05), Paint()..color = p.deep);
    if (waves) {
      for (var i = 1; i <= 3; i++) {
        canvas.drawArc(Rect.fromCircle(center: Offset(s * 0.6, s * 0.48), radius: s * 0.06 * i), math.pi * 1.15,
            math.pi * 0.7, false, _line(s * 0.01)..color = Colors.white.withValues(alpha: 1 - i * 0.25));
      }
    }
  }

  // a hand tapping a phone, with notes
  void _snooze(Canvas canvas, double s) {
    canvas.drawPath(_phone(s * 0.34, s * 0.3, s * 0.32, s * 0.52), _ink);
    canvas.drawPath(_phone(s * 0.37, s * 0.34, s * 0.26, s * 0.42), Paint()..color = p.deep);
    final tp = TextPainter(
        text:
            TextSpan(text: 'Zz', style: TextStyle(color: Colors.white, fontSize: s * 0.1, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, Offset(s * 0.45, s * 0.48));
    // finger
    final finger = Path()
      ..moveTo(s * 0.62, s * 0.95)
      ..lineTo(s * 0.62, s * 0.62)
      ..arcToPoint(Offset(s * 0.72, s * 0.62), radius: Radius.circular(s * 0.05))
      ..lineTo(s * 0.72, s * 0.95);
    canvas.drawPath(finger, Paint()..color = p.warn);
    for (var i = 1; i <= 2; i++) {
      canvas.drawArc(Rect.fromCircle(center: Offset(s * 0.67, s * 0.6), radius: s * 0.05 * i), -math.pi * 0.9,
          math.pi * 0.8, false, _line(s * 0.012));
    }
    _note(canvas, Offset(s * 0.22, s * 0.3), s * 0.06);
    _note(canvas, Offset(s * 0.8, s * 0.36), s * 0.05);
  }

  void _note(Canvas canvas, Offset at, double r) {
    canvas.drawOval(Rect.fromCenter(center: at, width: r * 1.4, height: r), _ink);
    canvas.drawLine(at + Offset(r * 0.65, 0), at + Offset(r * 0.65, -r * 2.2), _line(r * 0.25));
    canvas.drawLine(at + Offset(r * 0.65, -r * 2.2), at + Offset(r * 1.4, -r * 1.7), _line(r * 0.25));
  }

  void _gift(Canvas canvas, double s) {
    _stars(canvas, s, 16);
    final box = Rect.fromLTWH(s * 0.27, s * 0.45, s * 0.46, s * 0.34);
    canvas.drawRect(box, _ink);
    canvas.drawRect(Rect.fromLTWH(s * 0.23, s * 0.37, s * 0.54, s * 0.1), _ink);
    final ribbon = Paint()..color = p.warn;
    canvas.drawRect(Rect.fromLTWH(s * 0.47, s * 0.37, s * 0.06, s * 0.42), ribbon);
    canvas.drawOval(Rect.fromLTWH(s * 0.35, s * 0.27, s * 0.15, s * 0.1), _line(s * 0.02)..color = p.warn);
    canvas.drawOval(Rect.fromLTWH(s * 0.5, s * 0.27, s * 0.15, s * 0.1), _line(s * 0.02)..color = p.warn);
  }

  void _target(Canvas canvas, double s) {
    final c = Offset(s / 2, s * 0.52);
    for (var i = 3; i >= 1; i--) {
      canvas.drawCircle(c, s * 0.1 * i, i.isOdd ? _ink : (Paint()..color = p.deep));
    }
    canvas.drawLine(Offset(s * 0.78, s * 0.24), c, _line(s * 0.02)..color = p.warn);
    canvas.drawCircle(Offset(s * 0.2, s * 0.25), s * 0.06, _soft); // moon
    canvas.drawCircle(Offset(s * 0.82, s * 0.78), s * 0.05, Paint()..color = p.warn); // sun
  }

  void _clock(Canvas canvas, double s) {
    final c = Offset(s / 2, s * 0.53);
    canvas.drawCircle(c, s * 0.26, _ink);
    canvas.drawCircle(c, s * 0.22, Paint()..color = p.deep);
    canvas.drawLine(c, c + Offset(0, -s * 0.15), _line(s * 0.025));
    canvas.drawLine(c, c + Offset(s * 0.1, s * 0.04), _line(s * 0.025));
    canvas.drawCircle(Offset(s * 0.32, s * 0.27), s * 0.07, _ink);
    canvas.drawCircle(Offset(s * 0.68, s * 0.27), s * 0.07, _ink);
  }

  void _report(Canvas canvas, double s) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.28, s * 0.22, s * 0.44, s * 0.58), Radius.circular(s * 0.04)),
        _ink);
    final bar = Paint()..color = p.deep;
    final hs = [0.18, 0.28, 0.14, 0.24, 0.3];
    for (var i = 0; i < hs.length; i++) {
      canvas.drawRect(Rect.fromLTWH(s * (0.33 + i * 0.075), s * (0.72 - hs[i]), s * 0.05, s * hs[i]), bar);
    }
    canvas.drawLine(Offset(s * 0.33, s * 0.32), Offset(s * 0.6, s * 0.32), _line(s * 0.02)..color = p.light);
  }

  void _notes(Canvas canvas, double s) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.26, s * 0.24, s * 0.48, s * 0.56), Radius.circular(s * 0.04)),
        _ink);
    for (var i = 0; i < 4; i++) {
      canvas.drawLine(Offset(s * 0.33, s * (0.36 + i * 0.1)), Offset(s * 0.66, s * (0.36 + i * 0.1)),
          _line(s * 0.015)..color = p.light);
    }
    final pen = Path()
      ..moveTo(s * 0.62, s * 0.78)
      ..lineTo(s * 0.82, s * 0.44)
      ..lineTo(s * 0.86, s * 0.47)
      ..lineTo(s * 0.66, s * 0.81)
      ..close();
    canvas.drawPath(pen, Paint()..color = p.warn);
  }

  @override
  bool shouldRepaint(_IllustrationPainter o) => o.art != art || o.p != p;
}

/// Procedural cover art for sleep-aid tracks and programs: a night (or dusk)
/// landscape seeded by [seed], so each item gets its own stable scene in its
/// two colors: hills or waves, a moon or a low sun, stars.
class SceneArt extends CustomPainter {
  final List<Color> colors;
  final int seed;
  SceneArt(this.colors, this.seed);

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final w = size.width, h = size.height;
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = LinearGradient(colors: colors, begin: Alignment.topCenter, end: Alignment.bottomCenter)
              .createShader(Offset.zero & size));
    final star = Paint()..color = Colors.white.withValues(alpha: 0.6);
    for (var i = 0; i < 24; i++) {
      canvas.drawCircle(Offset(rng.nextDouble() * w, rng.nextDouble() * h * 0.5), 0.5 + rng.nextDouble(), star);
    }
    final orb = Offset(w * (0.2 + rng.nextDouble() * 0.6), h * (0.22 + rng.nextDouble() * 0.18));
    final r = math.min(w, h) * (0.08 + rng.nextDouble() * 0.06);
    canvas.drawCircle(
        orb,
        r * 2.4,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    canvas.drawCircle(orb, r, Paint()..color = Colors.white.withValues(alpha: 0.9));
    final waves = rng.nextBool();
    for (var layer = 0; layer < 3; layer++) {
      final base = h * (0.62 + layer * 0.12);
      final amp = h * (waves ? 0.025 : 0.06 + rng.nextDouble() * 0.05);
      final freq = waves ? 3 + rng.nextInt(3) : 1 + rng.nextInt(2);
      final ph = rng.nextDouble() * math.pi * 2;
      final path = Path()..moveTo(0, h);
      for (var x = 0.0; x <= w; x += w / 40) {
        path.lineTo(x, base + amp * math.sin(ph + x / w * math.pi * 2 * freq));
      }
      path
        ..lineTo(w, h)
        ..close();
      final shade = Color.lerp(colors.last, Colors.black, 0.15 + layer * 0.2)!;
      canvas.drawPath(path, Paint()..color = shade.withValues(alpha: 0.75 + layer * 0.08));
    }
  }

  @override
  bool shouldRepaint(SceneArt o) => o.seed != seed || o.colors != colors;
}

/// The now-playing equaliser: four bars bouncing out of step.
class EqBars extends StatefulWidget {
  final Color color;
  final double size;
  final bool playing;
  const EqBars({super.key, required this.color, this.size = 18, this.playing = true});
  @override
  State<EqBars> createState() => _EqBarsState();
}

class _EqBarsState extends State<EqBars> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(EqBars old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) _c.repeat();
    if (!widget.playing) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
            size: Size.square(widget.size), painter: _EqPainter(widget.playing ? _c.value : 0, widget.color)),
      );
}

class _EqPainter extends CustomPainter {
  final double t;
  final Color color;
  _EqPainter(this.t, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final bw = size.width / 6;
    for (var i = 0; i < 4; i++) {
      final f = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(2 * math.pi * (t * (1 + i * 0.37)) + i * 1.3));
      final hh = size.height * (t == 0 ? 0.3 : f);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(i * bw * 1.5, size.height - hh, bw, hh), Radius.circular(bw / 2)), p);
    }
  }

  @override
  bool shouldRepaint(_EqPainter o) => o.t != t;
}

/// Our own animated intro for onboarding (used when the comparison Lottie
/// isn't bundled): twinkling stars, a moon, and a sleep wave that draws
/// itself across the night, deep troughs early and REM peaks late.
class NightIntro extends StatefulWidget {
  const NightIntro({super.key});
  @override
  State<NightIntro> createState() => _NightIntroState();
}

class _NightIntroState extends State<NightIntro> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(painter: _NightIntroPainter(_c.value, context.palette), size: Size.infinite),
      );
}

class _NightIntroPainter extends CustomPainter {
  final double t;
  final SleepPalette p;
  _NightIntroPainter(this.t, this.p);
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = LinearGradient(colors: p.backdrop, begin: Alignment.topCenter, end: Alignment.bottomCenter)
              .createShader(Offset.zero & size));
    final rng = math.Random(9);
    for (var i = 0; i < 60; i++) {
      final tw = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(2 * math.pi * (t * 2 + rng.nextDouble())));
      canvas.drawCircle(Offset(rng.nextDouble() * w, rng.nextDouble() * h * 0.55), 0.6 + rng.nextDouble() * 1.4,
          Paint()..color = Colors.white.withValues(alpha: 0.7 * tw));
    }
    final moon = Offset(w * 0.75, h * 0.18);
    canvas.drawCircle(
        moon,
        w * 0.12,
        Paint()
          ..color = p.glow.withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30));
    canvas.drawCircle(moon, w * 0.07, Paint()..color = Colors.white);
    canvas.drawCircle(moon + Offset(w * 0.03, -w * 0.015), w * 0.065, Paint()..color = p.backdrop.first);
    // the night's sleep wave, drawn progressively
    final top = h * 0.42, depth = h * 0.18;
    double y(double f) {
      final cycle = math.sin(f * math.pi * 2 * 4.5 - math.pi / 2); // ~4.5 cycles a night
      final deepEarly = 1 - f * 0.7; // deeper troughs early in the night
      return top + depth * (0.5 + 0.5 * -cycle * deepEarly);
    }

    final path = Path()..moveTo(0, y(0));
    final upto = (t * 1.25).clamp(0.0, 1.0);
    for (var x = 0.0; x <= w * upto; x += 3) {
      path.lineTo(x, y(x / w));
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..shader =
              LinearGradient(colors: [p.rem, p.light, p.deep], begin: Alignment.topCenter, end: Alignment.bottomCenter)
                  .createShader(Rect.fromLTWH(0, top, w, depth)));
  }

  @override
  bool shouldRepaint(_NightIntroPainter o) => o.t != t;
}
