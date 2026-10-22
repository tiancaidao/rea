import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Pale blue gradient behind every screen.
class GradientBackground extends StatelessWidget {
  const GradientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(gradient: AppColors.pageGradient),
    child: child,
  );
}

/// White rounded square holding an icon, used for back and toolbar actions.
class SquareIconButton extends StatelessWidget {
  const SquareIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color = AppColors.surface,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  /// Use a tint such as [AppColors.background] when sitting on white.
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(6),
    child: Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Tooltip(
          message: tooltip ?? '',
          child: SizedBox.square(
            dimension: 40,
            child: Icon(icon, size: 20, color: AppColors.text),
          ),
        ),
      ),
    ),
  );
}

/// Circular icon badge. Soft badges sit on a pale tint of [color]; solid ones
/// are filled with it, like the rows of a results list.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    this.color = AppColors.primary,
    this.size = 48,
    this.solid = false,
  });

  final IconData icon;
  final Color color;
  final double size;
  final bool solid;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: solid ? color : color.withValues(alpha: 0.12),
      boxShadow: solid
          ? softShadow(blur: 12, y: 4, color: color.withValues(alpha: 0.35))
          : null,
    ),
    child: Icon(icon, size: size * 0.48, color: solid ? Colors.white : color),
  );
}

/// White rounded card with the soft blue shadow.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.radius = AppRadii.card,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      boxShadow: softShadow(blur: 20, y: 6),
    ),
    child: Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

/// Blue gradient call-to-action with a glow underneath. [pill] gives the
/// fully rounded variant used for the hero action.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.pill = false,
    this.loading = false,
    this.height = 54,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool pill;
  final bool loading;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final radius = BorderRadius.circular(pill ? height : AppRadii.button);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled || loading ? 1 : 0.45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: AppColors.buttonGradient,
          boxShadow: enabled
              ? softShadow(
                  blur: 22,
                  y: 10,
                  color: AppColors.primary.withValues(alpha: 0.35),
                )
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (loading)
                      const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    else if (icon != null)
                      Icon(icon, size: 20, color: Colors.white),
                    if (loading || icon != null) const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Large circular progress ring with a gradient arc and a few floating dots.
/// A null [value] spins an indeterminate arc.
class ProgressRing extends StatefulWidget {
  const ProgressRing({
    super.key,
    required this.value,
    required this.child,
    this.size = 220,
    this.stroke = 14,
  });

  final double? value;
  final Widget child;
  final double size;
  final double stroke;

  @override
  State<ProgressRing> createState() => _ProgressRingState();
}

class _ProgressRingState extends State<ProgressRing>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.value == null) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: AnimatedBuilder(
      animation: _spin,
      builder: (_, child) => TweenAnimationBuilder<double>(
        tween: Tween(end: widget.value ?? 0.28),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        builder: (_, v, _) => CustomPaint(
          painter: _RingPainter(
            value: v,
            rotation: widget.value == null ? _spin.value : 0,
            stroke: widget.stroke,
          ),
          child: child,
        ),
      ),
      child: Center(child: widget.child),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.rotation,
    required this.stroke,
  });

  final double value;
  final double rotation;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - stroke;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius - stroke * 1.4,
      Paint()
        ..color = AppColors.surface
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 18),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AppColors.ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.55,
    );

    final start = -math.pi / 2 + rotation * 2 * math.pi;
    final sweep = 2 * math.pi * value.clamp(0.0, 1.0);
    if (sweep > 0) {
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..shader = SweepGradient(
            startAngle: 0,
            endAngle: 2 * math.pi,
            transform: GradientRotation(start),
            colors: const [AppColors.primaryLight, AppColors.primary],
          ).createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = stroke,
      );
      final end = start + sweep;
      canvas.drawCircle(
        center + Offset(math.cos(end), math.sin(end)) * radius,
        stroke * 0.32,
        Paint()..color = Colors.white,
      );
    }

    // Decorative dots, as in the reference.
    final dot = Paint()..color = AppColors.primary;
    for (final (angle, r) in const [(-2.3, 6.0), (-0.75, 7.0), (2.3, 2.0)]) {
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * (radius + stroke),
        r,
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.rotation != rotation || old.stroke != stroke;
}

/// Layered translucent blue circles behind a centred label, for summaries.
class GlowOrb extends StatefulWidget {
  const GlowOrb({super.key, required this.child, this.size = 230});

  final Widget child;
  final double size;

  @override
  State<GlowOrb> createState() => _GlowOrbState();
}

class _GlowOrbState extends State<GlowOrb> with SingleTickerProviderStateMixin {
  late final _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox.square(
      dimension: s,
      child: AnimatedBuilder(
        animation: _drift,
        builder: (_, child) => Stack(
          alignment: Alignment.center,
          children: [
            for (var i = 0; i < 4; i++)
              Transform.translate(
                offset: Offset.fromDirection(
                  _drift.value * 2 * math.pi + i * math.pi / 2,
                  s * 0.035,
                ),
                child: Container(
                  width: s * 0.92,
                  height: s * 0.92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.primaryLight.withValues(alpha: 0.05),
                        AppColors.primaryLight.withValues(alpha: 0.28),
                      ],
                    ),
                  ),
                ),
              ),
            Container(
              width: s * 0.62,
              height: s * 0.62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.background,
                boxShadow: softShadow(
                  blur: 30,
                  y: 0,
                  color: AppColors.primary.withValues(alpha: 0.35),
                ),
              ),
              child: child,
            ),
          ],
        ),
        child: Center(child: widget.child),
      ),
    );
  }
}

/// Stacked blue rounded diamonds with a broom, the app's illustration.
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 200, this.icon});

  final double size;

  /// Replaces the broom, e.g. for tutorial slides.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tile = size * 0.58;
    Widget layer(double dy, double alpha, {Widget? child, bool top = false}) =>
        Transform.translate(
          offset: Offset(0, dy),
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: tile,
              height: tile,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(tile * 0.24),
                gradient: top
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF3D9BFF), AppColors.primaryDeep],
                      )
                    : null,
                color: top ? null : AppColors.primary.withValues(alpha: alpha),
                boxShadow: top
                    ? softShadow(
                        blur: 30,
                        y: 12,
                        color: AppColors.primary.withValues(alpha: 0.4),
                      )
                    : null,
              ),
              child: Transform.rotate(angle: -math.pi / 4, child: child),
            ),
          ),
        );
    return SizedBox(
      width: size,
      height: size * 1.12,
      child: Stack(
        alignment: Alignment.center,
        children: [
          layer(size * 0.2, 0.18),
          layer(size * 0.1, 0.35),
          layer(
            0,
            1,
            top: true,
            child: Icon(
              icon ?? Icons.cleaning_services,
              size: tile * 0.5,
              color: icon == null ? const Color(0xFFFFC83D) : Colors.white,
            ),
          ),
          Positioned(
            left: size * 0.2,
            top: size * 0.22,
            child: Icon(
              Icons.auto_awesome,
              size: size * 0.09,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
