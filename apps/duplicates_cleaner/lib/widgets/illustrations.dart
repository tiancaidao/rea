import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'themed.dart';

/// Vector illustrations for onboarding, drawn from the theme's shapes so
/// they stay crisp at any size and follow palette changes.

/// The six scan categories orbiting a glowing magnifier.
class CategoriesIllustration extends StatefulWidget {
  const CategoriesIllustration({super.key, this.size = 260});

  final double size;

  @override
  State<CategoriesIllustration> createState() => _CategoriesIllustrationState();
}

class _CategoriesIllustrationState extends State<CategoriesIllustration>
    with SingleTickerProviderStateMixin {
  static const _icons = [
    Icons.image_outlined,
    Icons.audiotrack_outlined,
    Icons.movie_outlined,
    Icons.description_outlined,
    Icons.android,
    Icons.extension_outlined,
  ];

  late final _orbit = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 40),
  )..repeat();

  @override
  void dispose() {
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final radius = s * 0.4;
    return SizedBox.square(
      dimension: s,
      child: AnimatedBuilder(
        animation: _orbit,
        builder: (_, _) => Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.square(s),
              painter: _DashedRingPainter(radius: radius),
            ),
            GlowOrb(
              size: s * 0.62,
              child: const Icon(
                Icons.manage_search,
                size: 44,
                color: AppColors.primary,
              ),
            ),
            for (var i = 0; i < _icons.length; i++)
              Transform.translate(
                offset: Offset.fromDirection(
                  _orbit.value * 2 * math.pi +
                      i * 2 * math.pi / _icons.length -
                      math.pi / 2,
                  radius,
                ),
                child: IconBadge(
                  icon: _icons[i],
                  color: AppColors.badges[i],
                  size: s * 0.18,
                  solid: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DashedRingPainter extends CustomPainter {
  _DashedRingPainter({required this.radius});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    const dashes = 48;
    const sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * sweep,
        sweep * 0.45,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter old) => old.radius != radius;
}

/// A set of identical files: the original on top, its copies fanned out
/// below with matching content fingerprints.
class DuplicateSetIllustration extends StatelessWidget {
  const DuplicateSetIllustration({super.key, this.width = 280});

  final double width;

  @override
  Widget build(BuildContext context) {
    Widget card(double dy, double scale, {required bool original}) =>
        Transform.translate(
          offset: Offset(0, dy),
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: original ? 1 : 0.55 + scale * 0.4,
              child: _FileCard(width: width * 0.86, original: original),
            ),
          ),
        );
    return SizedBox(
      width: width,
      height: width * 0.92,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(child: CustomPaint(painter: _SparklePainter())),
          card(width * 0.3, 0.84, original: false),
          card(width * 0.1, 0.92, original: false),
          card(-width * 0.12, 1, original: true),
          Positioned(
            right: width * 0.02,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                gradient: AppColors.buttonGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: softShadow(
                  blur: 14,
                  y: 5,
                  color: AppColors.primary.withValues(alpha: 0.35),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fingerprint, size: 16, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    '100% match',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({required this.width, required this.original});

  final double width;
  final bool original;

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, {double h = 8, Color? color}) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: color ?? AppColors.ring,
        borderRadius: BorderRadius.circular(h),
      ),
    );
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: softShadow(blur: 22, y: 8),
      ),
      child: Row(
        children: [
          IconBadge(
            icon: Icons.image_outlined,
            color: AppColors.badges[0],
            size: 46,
            solid: true,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: bar(
                        width * 0.26,
                        h: 10,
                        color: const Color(0xFFCAD5E6),
                      ),
                    ),
                    if (original) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Original',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                bar(width * 0.36),
              ],
            ),
          ),
          Icon(
            original ? Icons.radio_button_unchecked : Icons.check_circle,
            color: original ? AppColors.textMuted : AppColors.primary,
          ),
        ],
      ),
    );
  }
}

/// A few four-point sparkles scattered around an illustration.
class _SparklePainter extends CustomPainter {
  static const _spots = [
    (0.06, 0.12, 9.0),
    (0.92, 0.08, 6.0),
    (0.02, 0.78, 6.0),
    (0.86, 0.5, 4.0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.primaryLight;
    for (final (x, y, r) in _spots) {
      final c = Offset(size.width * x, size.height * y);
      final path = Path()
        ..moveTo(c.dx, c.dy - r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => false;
}

/// A shield over a half-filled storage ring: review first, clean safely.
class SafeCleanIllustration extends StatelessWidget {
  const SafeCleanIllustration({super.key, this.size = 260});

  final double size;

  @override
  Widget build(BuildContext context) {
    Widget chip(IconData icon, String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: softShadow(blur: 16, y: 5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.badges[4]),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    return SizedBox(
      width: size * 1.1,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ProgressRing(
            value: 0.68,
            size: size * 0.86,
            child: CustomPaint(
              size: Size(size * 0.3, size * 0.36),
              painter: _ShieldPainter(),
            ),
          ),
          Positioned(
            left: 0,
            top: size * 0.12,
            child: chip(Icons.visibility_outlined, 'Preview'),
          ),
          Positioned(
            right: 0,
            bottom: size * 0.1,
            child: chip(Icons.verified_outlined, 'Original kept'),
          ),
        ],
      ),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final shield = Path()
      ..moveTo(w / 2, 0)
      ..lineTo(w, h * 0.16)
      ..lineTo(w, h * 0.46)
      ..cubicTo(w, h * 0.74, w * 0.72, h * 0.92, w / 2, h)
      ..cubicTo(w * 0.28, h * 0.92, 0, h * 0.74, 0, h * 0.46)
      ..lineTo(0, h * 0.16)
      ..close();
    canvas.drawShadow(shield, AppColors.primary, 10, false);
    canvas.drawPath(
      shield,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3D9BFF), AppColors.primaryDeep],
        ).createShader(Offset.zero & size),
    );
    final tick = Path()
      ..moveTo(w * 0.28, h * 0.5)
      ..lineTo(w * 0.44, h * 0.65)
      ..lineTo(w * 0.73, h * 0.36);
    canvas.drawPath(
      tick,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.1
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ShieldPainter old) => false;
}
