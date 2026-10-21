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

/// Deep teal night sky with twinkle-free stars and, when the local comparison
/// placeholders are present, a soft cloud layer.
class StarryBackground extends StatelessWidget {
  final Widget child;
  const StarryBackground({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0F2B3A), Color(0xFF071620)],
        ),
      ),
      child: Stack(children: [
        const Positioned.fill(child: CustomPaint(painter: _StarsPainter())),
        Positioned.fill(
          child: Opacity(
            opacity: 0.35,
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
  const _StarsPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(11);
    final p = Paint();
    for (var i = 0; i < 70; i++) {
      p.color = const Color(0xFF6FD6FF).withOpacity(0.15 + rng.nextDouble() * 0.5);
      canvas.drawCircle(Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height * 0.8),
          0.6 + rng.nextDouble() * 1.2, p);
    }
  }

  @override
  bool shouldRepaint(_StarsPainter old) => false;
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
          icon: const Icon(Icons.arrow_back, color: AppTheme.accent),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: actions,
        bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1), child: Divider(height: 1, color: Colors.white12)),
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
    return Column(children: [
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: icon == null ? null : Icon(icon, color: AppTheme.accent),
        title: Text(title, style: TextStyle(color: titleColor)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (value != null)
            Text(value!, style: const TextStyle(color: Colors.white60, fontSize: 14)),
          if (onTap != null) const Icon(Icons.chevron_right, color: Colors.white60),
        ]),
        onTap: onTap,
      ),
      const Divider(height: 1, indent: 20, endIndent: 20, color: Colors.white12),
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
              child: Text(header!, style: const TextStyle(color: Colors.white70, fontSize: 15)),
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
                      color: AppTheme.accent, size: 22),
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
        const Divider(color: Colors.white12),
        const SizedBox(height: 12),
        const Text('About', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(text, style: const TextStyle(color: Colors.white60, height: 1.45)),
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
  final List<Color> colors;
  const CircleArt(
      {super.key,
      this.asset,
      required this.icon,
      this.size = 220,
      this.colors = const [Color(0xFF2B6E86), Color(0xFF173246)]});
  @override
  Widget build(BuildContext context) {
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
          shape: BoxShape.circle, gradient: LinearGradient(colors: colors, begin: Alignment.topLeft)),
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

/// Full-width rounded primary button (orange by default).
class PillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final double width;
  const PillButton(this.label,
      {super.key, this.onPressed, this.color = AppTheme.cta, this.width = double.infinity});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 52,
      child: FilledButton(
        style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        onPressed: onPressed,
        child: Text(label),
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
