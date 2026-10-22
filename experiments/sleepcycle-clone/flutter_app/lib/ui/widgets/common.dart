import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app_state.dart';
import '../../theme.dart';

/// Shared building blocks so every screen follows the same templates as the
/// original: starry night backdrop, back-arrow settings pages built from a
/// radio list + "About" block, grouped navigation rows with trailing values.

void push(BuildContext context, Widget page) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));

String fmtTime(int hour, int minute) {
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h:${minute.toString().padLeft(2, '0')} ${hour < 12 ? 'AM' : 'PM'}';
}

String fmtDt(DateTime t) => fmtTime(t.hour, t.minute);

String fmtDuration(int minutes) => '${minutes ~/ 60}h ${minutes.remainder(60)}m';

/// Rebuilds [builder] whenever [AppState] changes.
class Watch extends StatelessWidget {
  final Widget Function(BuildContext, AppState) builder;
  const Watch(this.builder, {super.key});
  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: AppState.I, builder: (c, _) => builder(c, AppState.I));
}

/// The theme's backdrop: its sky gradient, a soft bloom behind the hero,
/// stars on dark themes and, when the local comparison placeholders are
/// present, a soft cloud layer.
class StarryBackground extends StatelessWidget {
  final Widget child;
  const StarryBackground({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: p.backdrop,
        ),
      ),
      child: Stack(children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.25),
                radius: 0.9,
                colors: [p.glow, p.glow.withOpacity(0)],
              ),
            ),
          ),
        ),
        if (p.stars != null) Positioned.fill(child: CustomPaint(painter: _StarsPainter(p.stars!))),
        Positioned.fill(
          child: Opacity(
            opacity: p.isDark ? 0.35 : 0.2,
            child: Image.asset('assets/images/night_clouds_bg.webp',
                fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
          ),
        ),
        Positioned.fill(child: child),
      ]),
    );
  }
}

class _StarsPainter extends CustomPainter {
  final Color color;
  const _StarsPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(11);
    final p = Paint();
    for (var i = 0; i < 70; i++) {
      p.color = color.withOpacity(0.1 + rng.nextDouble() * 0.45);
      canvas.drawCircle(Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height * 0.8),
          0.5 + rng.nextDouble() * 1.1, p);
    }
  }

  @override
  bool shouldRepaint(_StarsPainter old) => old.color != color;
}

/// Back-arrow page with a centered title — the template every settings and
/// detail screen in the original uses.
class SettingsPage extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final List<Widget>? actions;
  const SettingsPage({super.key, required this.title, required this.children, this.actions});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.palette.accent),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: actions,
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1)),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: children),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
        child: Text(text, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      );
}

/// Icon · title · trailing value · chevron, separated by hairlines.
class NavRow extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;
  final Color? titleColor;
  const NavRow({super.key, this.icon, required this.title, this.value, this.onTap, this.titleColor});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(children: [
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: icon == null ? null : Icon(icon, color: p.accent),
        title: Text(title, style: TextStyle(color: titleColor)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (value != null) Text(value!, style: TextStyle(color: p.textMuted, fontSize: 14)),
          if (onTap != null) Icon(Icons.chevron_right, color: p.textMuted),
        ]),
        onTap: onTap,
      ),
      const Divider(height: 1, indent: 20, endIndent: 20),
    ]);
  }
}

/// Single-choice list bound to a preference key.
class PrefRadioList extends StatelessWidget {
  final String? header;
  final String prefKey;
  final List<String> options;
  final void Function(String)? onPicked;
  const PrefRadioList(
      {super.key, this.header, required this.prefKey, required this.options, this.onPicked});
  @override
  Widget build(BuildContext context) {
    return Watch((context, s) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(header!, style: TextStyle(color: context.palette.textMuted, fontSize: 15)),
            ),
          for (final o in options)
            InkWell(
              onTap: () {
                s.setPref(prefKey, o);
                onPicked?.call(o);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  Icon(s.pref(prefKey) == o ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: context.palette.accent, size: 22),
                  const SizedBox(width: 16),
                  Expanded(child: Text(o, style: const TextStyle(fontSize: 16))),
                ]),
              ),
            ),
        ]),
      );
    });
  }
}

class AboutBlock extends StatelessWidget {
  final String text;
  final Widget? art;
  const AboutBlock(this.text, {super.key, this.art});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Divider(),
        const SizedBox(height: 12),
        const Text('About', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(text, style: TextStyle(color: context.palette.textMuted, height: 1.45)),
        if (art != null) ...[const SizedBox(height: 24), Center(child: art!)],
      ]),
    );
  }
}

/// Circular illustration: a local placeholder image if extracted, otherwise a
/// gradient disc with an icon.
class CircleArt extends StatelessWidget {
  final String? asset;
  final IconData icon;
  final double size;
  final List<Color>? colors; // defaults to the theme's light → deep stage blend
  const CircleArt({super.key, this.asset, required this.icon, this.size = 220, this.colors});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: colors ?? [p.light, p.deep], begin: Alignment.topLeft)),
      child: Center(child: Icon(icon, size: size * 0.4, color: Colors.white)),
    );
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: asset == null
            ? fallback
            : Image.asset(asset!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
      ),
    );
  }
}

/// Gradient cover art with an optional centered label.
class ArtBox extends StatelessWidget {
  final List<Color> colors;
  final String? label;
  final double radius;
  final IconData? icon;
  const ArtBox({super.key, required this.colors, this.label, this.radius = 14, this.icon});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(colors: colors, begin: Alignment.topCenter, end: Alignment.bottomCenter),
      ),
      alignment: Alignment.center,
      child: label != null
          ? Text(label!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 6)]))
          : (icon != null ? Icon(icon, color: Colors.white70, size: 36) : null),
    );
  }
}

/// Full-width rounded primary button in the theme's call-to-action fill
/// (a gradient on Midnight), or a solid [color] when given.
class PillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final double width;
  const PillButton(this.label, {super.key, this.onPressed, this.color, this.width = double.infinity});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      width: width,
      height: 52,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: const StadiumBorder(),
          gradient: color == null ? p.ctaGradient : null,
          color: color,
        ),
        child: FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: p.onCta,
              shape: const StadiumBorder(),
              textStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, fontFamily: p.fontFamily)),
          onPressed: onPressed,
          child: Text(label),
        ),
      ),
    );
  }
}

Future<bool> confirm(BuildContext context, String title, String body, String action) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
      ],
    ),
  );
  return r ?? false;
}

void toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
