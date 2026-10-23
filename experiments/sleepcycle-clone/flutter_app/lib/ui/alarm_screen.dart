import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../alarm/alarm_plan.dart';
import '../alarm/alarm_ringer.dart';
import '../device/device_sensors.dart';
import '../device/notifications.dart';
import '../theme.dart';
import 'widgets/common.dart';

/// The ringing alarm, full screen and over the lock screen: the time, a
/// Snooze button and a slide-up "Stop alarm". As in the original you can
/// also snooze by tapping the phone twice or by picking it up. While snoozed
/// it shows when it rings again; the screen pops (returning normally) only
/// once the alarm is stopped.
class AlarmScreen extends StatefulWidget {
  final AlarmPlan plan;
  const AlarmScreen({super.key, required this.plan});
  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  late Timer _clock;
  DateTime _now = DateTime.now();
  DateTime? _snoozedUntil;
  Timer? _snoozeTimer;
  StreamSubscription<AccelerometerEvent>? _accel;
  DateTime _armedAt = DateTime.now();
  int _snoozes = 0;
  double _drag = 0;
  bool _done = false;
  DateTime? _lastTap;

  bool get _ringing => _snoozedUntil == null;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now()));
    showOverLockScreen(true);
    _ring();
    try {
      _accel = accelerometerEventStream().listen(_onAccel, onError: (_) {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _clock.cancel();
    _snoozeTimer?.cancel();
    _accel?.cancel();
    AlarmRinger.I.stop();
    showOverLockScreen(false);
    super.dispose();
  }

  void _ring() {
    _snoozedUntil = null;
    _armedAt = DateTime.now();
    AlarmRinger.I.start();
    Notifications.I.showAlarmNow();
  }

  // a sharp jolt well away from resting gravity, after a short grace period
  void _onAccel(AccelerometerEvent e) {
    if (!_ringing || !widget.plan.canSnooze) return;
    if (DateTime.now().difference(_armedAt) < const Duration(seconds: 3)) return;
    final g = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if ((g - 9.81).abs() > 4.0) _snooze();
  }

  void _snooze() {
    if (!_ringing || !widget.plan.canSnooze) return;
    final d = widget.plan.snoozeFor(DateTime.now());
    AlarmRinger.I.stop();
    Notifications.I.cancel(Notifications.alarmId);
    setState(() {
      _snoozes++;
      _snoozedUntil = DateTime.now().add(d);
    });
    _snoozeTimer?.cancel();
    _snoozeTimer = Timer(d, () {
      if (mounted) setState(_ring);
    });
  }

  void _stop() {
    if (_done) return;
    _done = true;
    _snoozeTimer?.cancel();
    AlarmRinger.I.stop();
    Notifications.I.cancel(Notifications.alarmId);
    Navigator.pop(context, _snoozes);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PopScope(
      canPop: false,
      child: Scaffold(
        // two quick taps anywhere snooze; a raw Listener so the buttons below
        // don't wait out a double-tap gesture
        body: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) {
            final now = DateTime.now();
            if (_lastTap != null && now.difference(_lastTap!) < const Duration(milliseconds: 400)) {
              _lastTap = null;
              _snooze();
            } else {
              _lastTap = now;
            }
          },
          child: StarryBackground(
            child: SafeArea(
              child: Column(children: [
                const SizedBox(height: 56),
                Text(_ringing ? 'Good morning' : 'Snoozing',
                    style: TextStyle(fontSize: 22, color: p.textMuted, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Text(fmtDt(_now), style: const TextStyle(fontSize: 84, fontWeight: FontWeight.w300)),
                if (!_ringing)
                  Text('Alarm rings again at ${fmtDt(_snoozedUntil!)}',
                      style: TextStyle(fontSize: 17, color: p.textMuted)),
                const Spacer(),
                _RingingSun(active: _ringing),
                const Spacer(),
                if (widget.plan.canSnooze && _ringing) ...[
                  PillButton('Snooze', width: 220, onPressed: _snooze),
                  const SizedBox(height: 12),
                  Text('Or tap the phone twice, or pick it up', style: TextStyle(color: p.textMuted, fontSize: 14)),
                ],
                const SizedBox(height: 36),
                GestureDetector(
                  onVerticalDragUpdate: (d) => setState(() => _drag = (_drag - d.delta.dy).clamp(0, 200)),
                  onVerticalDragEnd: (d) {
                    if (_drag > 90 || (d.primaryVelocity ?? 0) < -600) {
                      _stop();
                    } else {
                      setState(() => _drag = 0);
                    }
                  },
                  onTap: () => toast(context, 'Swipe up to stop the alarm'),
                  child: Transform.translate(
                    offset: Offset(0, -_drag),
                    child: SizedBox(
                      width: 200,
                      height: 90,
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.keyboard_arrow_up, color: p.textMuted, size: 32),
                        const Text('Stop alarm', style: TextStyle(fontSize: 20)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A rising sun with slowly pulsing rays while ringing (dim while snoozed).
class _RingingSun extends StatefulWidget {
  final bool active;
  const _RingingSun({required this.active});
  @override
  State<_RingingSun> createState() => _RingingSunState();
}

class _RingingSunState extends State<_RingingSun> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => CustomPaint(
        size: const Size(220, 220),
        painter: _SunPainter(widget.active ? _c.value : 0, p.warn, p.glow, widget.active),
      ),
    );
  }
}

class _SunPainter extends CustomPainter {
  final double t;
  final Color sun, glow;
  final bool active;
  _SunPainter(this.t, this.sun, this.glow, this.active);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 0.22;
    final a = active ? 1.0 : 0.35;
    canvas.drawCircle(
        c,
        r * (1.9 + 0.25 * t),
        Paint()
          ..color = glow.withValues(alpha: 0.25 * a)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30));
    final ray = Paint()
      ..color = sun.withValues(alpha: (0.45 + 0.4 * t) * a)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final ang = i * math.pi / 6;
      final d = Offset(math.cos(ang), math.sin(ang));
      canvas.drawLine(c + d * (r * 1.3), c + d * (r * (1.6 + 0.2 * t)), ray);
    }
    canvas.drawCircle(c, r, Paint()..color = sun.withValues(alpha: a));
  }

  @override
  bool shouldRepaint(_SunPainter o) => o.t != t || o.active != active;
}
