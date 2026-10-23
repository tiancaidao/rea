import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../data/night.dart';
import '../theme.dart';
import 'widgets/common.dart';

/// The morning alertness test ("Awake" in the original): about a minute of
/// tapping stars as soon as they appear and leaving clouds alone. Reaction
/// time (median of the hits) and accuracy are saved on the night and compared
/// with your own average, which is what the Journal's Alertness card shows.
class AlertnessGame extends StatefulWidget {
  final Night night;
  const AlertnessGame({super.key, required this.night});
  @override
  State<AlertnessGame> createState() => _AlertnessGameState();
}

enum _Phase { intro, playing, done }

class _Target {
  final Offset at; // 0..1 in the play area
  final bool star; // false = a cloud: don't tap
  final DateTime shown;
  _Target(this.at, this.star, this.shown);
}

class _AlertnessGameState extends State<AlertnessGame> with TickerProviderStateMixin {
  static const trials = 20;
  static const visibleFor = Duration(milliseconds: 1300);
  final _rng = math.Random();
  _Phase _phase = _Phase.intro;
  _Target? _target;
  int _trial = 0;
  final List<int> _rts = [];
  int _correct = 0;
  Timer? _next, _expire;
  final List<(Offset, AnimationController)> _bursts = [];
  late final _confetti = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  AlertnessResult? _result;

  @override
  void dispose() {
    _next?.cancel();
    _expire?.cancel();
    for (final b in _bursts) {
      b.$2.dispose();
    }
    _confetti.dispose();
    super.dispose();
  }

  void _start() {
    setState(() {
      _phase = _Phase.playing;
      _trial = 0;
      _rts.clear();
      _correct = 0;
    });
    _schedule();
  }

  void _schedule() {
    _next = Timer(Duration(milliseconds: 600 + _rng.nextInt(1400)), _show);
  }

  void _show() {
    if (!mounted) return;
    final star = _rng.nextDouble() > 0.25;
    setState(() => _target =
        _Target(Offset(0.12 + _rng.nextDouble() * 0.76, 0.1 + _rng.nextDouble() * 0.8), star, DateTime.now()));
    _expire = Timer(visibleFor, () => _resolve(tapped: false));
  }

  void _resolve({required bool tapped, Offset? where}) {
    final t = _target;
    if (t == null) return;
    _expire?.cancel();
    if (tapped && t.star) {
      _rts.add(DateTime.now().difference(t.shown).inMilliseconds);
      _correct++;
      if (where != null) _burst(where);
    } else if (!tapped && !t.star) {
      _correct++; // left the cloud alone
    }
    setState(() {
      _target = null;
      _trial++;
    });
    if (_trial >= trials) {
      _finish();
    } else {
      _schedule();
    }
  }

  void _burst(Offset at) {
    final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    final entry = (at, c);
    _bursts.add(entry);
    c.forward().whenComplete(() {
      if (!mounted) return;
      setState(() => _bursts.remove(entry));
      c.dispose();
    });
  }

  void _finish() {
    final rts = [..._rts]..sort();
    final r = AlertnessResult(
        reactionMs: rts.isEmpty ? 999 : rts[rts.length ~/ 2], accuracy: _correct / trials, at: DateTime.now());
    AppState.I.saveAlertness(widget.night, r);
    setState(() {
      _result = r;
      _phase = _Phase.done;
    });
    _confetti.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: StarryBackground(
        child: SafeArea(
          child: Column(children: [
            Row(children: [
              IconButton(icon: Icon(Icons.close, color: p.accent), onPressed: () => Navigator.pop(context)),
              const Spacer(),
              if (_phase == _Phase.playing)
                Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: Text('${_trial + 1} / $trials', style: TextStyle(color: p.textMuted)),
                ),
            ]),
            Expanded(
              child: switch (_phase) {
                _Phase.intro => _intro(p),
                _Phase.playing => _play(p),
                _Phase.done => _done(p),
              },
            ),
          ]),
        ),
      ),
    );
  }

  Widget _intro(SleepPalette p) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(children: [
          const Spacer(),
          const _FallingStars(),
          const SizedBox(height: 24),
          const Text('Awake', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text('Tap each star as fast as you can. Leave the clouds alone.\nIt takes about a minute.',
              textAlign: TextAlign.center, style: TextStyle(color: p.textMuted, fontSize: 17, height: 1.4)),
          const Spacer(),
          PillButton('Start', width: 220, onPressed: _start),
          const SizedBox(height: 40),
        ]),
      );

  Widget _play(SleepPalette p) => LayoutBuilder(builder: (context, box) {
        final t = _target;
        Offset pos(Offset f) => Offset(f.dx * box.maxWidth, f.dy * box.maxHeight);
        // raw pointer-downs: the reaction time is taken at first touch, and a
        // touch off the star while one is up counts as a miss
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            if (t == null) return;
            final hit = (e.localPosition - pos(t.at)).distance < 52;
            if (hit) {
              _resolve(tapped: true, where: pos(t.at));
            } else if (t.star) {
              _resolve(tapped: false);
            }
          },
          child: Stack(children: [
            if (t != null)
              Positioned(
                left: pos(t.at).dx - 40,
                top: pos(t.at).dy - 40,
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: CustomPaint(painter: t.star ? _StarPainter(p.warn) : _CloudPainter(p.textMuted)),
                ),
              ),
            for (final b in _bursts)
              Positioned(
                left: b.$1.dx - 60,
                top: b.$1.dy - 60,
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: b.$2,
                    builder: (_, __) =>
                        CustomPaint(size: const Size(120, 120), painter: _BurstPainter(b.$2.value, p.warn)),
                  ),
                ),
              ),
          ]),
        );
      });

  Widget _done(SleepPalette p) {
    final r = _result!;
    final past = [
      for (final n in AppState.I.nights)
        if (n.alertness != null && n != widget.night) n.alertness!
    ];
    final avgRt = past.isEmpty ? null : past.map((a) => a.reactionMs).reduce((a, b) => a + b) ~/ past.length;
    final avgAcc = past.isEmpty ? null : past.map((a) => a.accuracy).reduce((a, b) => a + b) / past.length;
    final verdict = avgRt == null
        ? 'This is your first alertness score. Play again tomorrow to get your baseline.'
        : r.reactionMs < avgRt * 0.95
            ? 'Sharper than usual today. A good day for demanding things.'
            : r.reactionMs > avgRt * 1.05
                ? 'A little slower than usual today. Go easy on yourself.'
                : 'Right on your usual level today.';
    return Stack(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(children: [
          const Spacer(),
          Text('${r.score}', style: const TextStyle(fontSize: 88, fontWeight: FontWeight.w700)),
          Text('Alertness', style: TextStyle(color: p.textMuted, fontSize: 18)),
          const SizedBox(height: 28),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _stat('${r.reactionMs} ms', 'Reaction time', avgRt == null ? null : 'Average $avgRt ms', p),
            _stat('${(r.accuracy * 100).round()}%', 'Accuracy',
                avgAcc == null ? null : 'Average ${(avgAcc * 100).round()}%', p),
          ]),
          const SizedBox(height: 28),
          Text(verdict, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, height: 1.4)),
          const Spacer(),
          PillButton('Done', width: 220, onPressed: () => Navigator.pop(context)),
          const SizedBox(height: 40),
        ]),
      ),
      Positioned.fill(
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: _confetti,
            builder: (_, __) =>
                CustomPaint(painter: _ConfettiPainter(_confetti.value, [p.warn, p.rem, p.light, p.awake])),
          ),
        ),
      ),
    ]);
  }

  Widget _stat(String v, String k, String? avg, SleepPalette p) => Column(children: [
        Text(v, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
        Text(k, style: TextStyle(color: p.textMuted)),
        if (avg != null) Text(avg, style: TextStyle(color: p.textFaint, fontSize: 13)),
      ]);
}

/// Offer the test if this night's morning window is still open.
bool alertnessAvailable(Night n) =>
    n.alertness == null &&
    DateTime.now().difference(n.wokeUp) < AppState.alertnessWindow &&
    !n.wokeUp.isAfter(DateTime.now());

class _StarPainter extends CustomPainter {
  final Color color;
  _StarPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? size.width * 0.45 : size.width * 0.2;
      final a = -math.pi / 2 + i * math.pi / 5;
      final pt = c + Offset(math.cos(a), math.sin(a)) * r;
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_StarPainter o) => o.color != color;
}

class _CloudPainter extends CustomPainter {
  final Color color;
  _CloudPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color.withValues(alpha: 0.9);
    final w = size.width, h = size.height;
    canvas.drawCircle(Offset(w * 0.35, h * 0.55), w * 0.2, p);
    canvas.drawCircle(Offset(w * 0.55, h * 0.45), w * 0.25, p);
    canvas.drawCircle(Offset(w * 0.72, h * 0.58), w * 0.17, p);
    canvas.drawRRect(RRect.fromLTRBR(w * 0.18, h * 0.55, w * 0.88, h * 0.75, Radius.circular(h * 0.1)), p);
  }

  @override
  bool shouldRepaint(_CloudPainter o) => o.color != color;
}

/// Sparks flying out from a tapped star.
class _BurstPainter extends CustomPainter {
  final double t;
  final Color color;
  _BurstPainter(this.t, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final p = Paint()
      ..color = color.withValues(alpha: 1 - t)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 10; i++) {
      final a = i * math.pi / 5;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (10 + 40 * t), c + d * (18 + 52 * t), p);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter o) => o.t != t;
}

class _ConfettiPainter extends CustomPainter {
  final double t;
  final List<Color> colors;
  _ConfettiPainter(this.t, this.colors);
  @override
  void paint(Canvas canvas, Size size) {
    if (t == 0 || t == 1) return;
    final rng = math.Random(3);
    for (var i = 0; i < 90; i++) {
      final x = rng.nextDouble() * size.width + math.sin(t * 8 + i) * 18;
      final y = -20 + (size.height + 40) * (t * (0.6 + rng.nextDouble() * 0.6)) % (size.height + 40);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * 10 + i);
      canvas.drawRect(
          const Rect.fromLTWH(-4, -2, 8, 4), Paint()..color = colors[i % colors.length].withValues(alpha: 1 - t * 0.6));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter o) => o.t != t;
}

/// The title screen's slowly falling stars.
class _FallingStars extends StatefulWidget {
  const _FallingStars();
  @override
  State<_FallingStars> createState() => _FallingStarsState();
}

class _FallingStarsState extends State<_FallingStars> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) =>
            CustomPaint(size: const Size(260, 180), painter: _FallPainter(_c.value, context.palette.warn)),
      );
}

class _FallPainter extends CustomPainter {
  final double t;
  final Color color;
  _FallPainter(this.t, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(11);
    for (var i = 0; i < 7; i++) {
      final x = rng.nextDouble() * size.width;
      final phase = (t + i / 7) % 1;
      final y = phase * size.height;
      final s = 10 + rng.nextDouble() * 14;
      canvas.save();
      canvas.translate(x - s / 2, y - s / 2);
      _StarPainter(color.withValues(alpha: 1 - phase * 0.7)).paint(canvas, Size(s, s));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_FallPainter o) => o.t != t;
}
