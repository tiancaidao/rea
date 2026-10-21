import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// An animated night sky with a slow "breathing" moon and drifting stars, used
/// on the tracking screen. Pure CustomPaint + a looping controller — no assets.
class NightView extends StatefulWidget {
  final String caption;
  const NightView({super.key, this.caption = 'Tracking your sleep'});
  @override
  State<NightView> createState() => _NightViewState();
}

class _NightViewState extends State<NightView> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  late final List<Offset> _stars;

  @override
  void initState() {
    super.initState();
    final rng = math.Random(7);
    _stars = List.generate(60, (_) => Offset(rng.nextDouble(), rng.nextDouble()));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Container(
          decoration: const BoxDecoration(gradient: AppTheme.nightGradient),
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _SkyPainter(_c.value, _stars))),
              Align(
                alignment: const Alignment(0, 0.6),
                child: Text(widget.caption,
                    style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SkyPainter extends CustomPainter {
  final double t;
  final List<Offset> stars;
  _SkyPainter(this.t, this.stars);

  @override
  void paint(Canvas canvas, Size size) {
    final star = Paint()..color = Colors.white;
    for (var i = 0; i < stars.length; i++) {
      final s = stars[i];
      final twinkle = 0.3 + 0.7 * (0.5 + 0.5 * math.sin(2 * math.pi * (t + i / stars.length)));
      star.color = Colors.white.withOpacity(0.15 + 0.5 * twinkle);
      canvas.drawCircle(Offset(s.dx * size.width, s.dy * size.height * 0.7), 1.2, star);
    }
    // breathing moon
    final breath = 0.5 + 0.5 * math.sin(2 * math.pi * t);
    final r = 34 + 4 * breath;
    final c = Offset(size.width * 0.5, size.height * 0.33);
    canvas.drawCircle(c, r + 18, Paint()
      ..color = AppTheme.primary.withOpacity(0.12 + 0.08 * breath)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24));
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFE9ECFF));
    canvas.drawCircle(Offset(c.dx + 12, c.dy - 10), r, Paint()..color = const Color(0xFF131A3A));
  }

  @override
  bool shouldRepaint(_SkyPainter old) => old.t != t;
}
