import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/night.dart';
import '../data/recorded_night.dart';
import '../theme.dart';
import 'journal_tab.dart' show DemoOverlay;
import 'widgets/common.dart';

/// Statistics tab: Days / Weeks / Months / All segmented control over a stack
/// of per-metric charts, each with "More ›" into a detail page. Before the
/// first night it renders demo data behind the empty-state overlay.
class StatisticsTab extends StatefulWidget {
  const StatisticsTab({super.key});
  @override
  State<StatisticsTab> createState() => _StatisticsTabState();
}

enum ChartKind { bar, line, range }

class Metric {
  final String title;
  final ChartKind kind;
  final Color color;
  final double Function(Night) value;
  final double Function(Night)? low; // range charts: value = high end
  final String Function(double) fmt;
  final String about;
  final double? maxY; // hard ceiling for the axis, e.g. 100 for percentages
  const Metric(this.title, this.kind, this.color, this.value, this.fmt, this.about, {this.low, this.maxY});
}

// minutes after 18:00 so evening→morning times sort on one axis
double _clock(DateTime t) => ((t.hour - 18) % 24) * 60.0 + t.minute;
String _clockFmt(double v) {
  final m = (v.round() + 18 * 60) % (24 * 60);
  return fmtTime(m ~/ 60, m % 60);
}

final metrics = <Metric>[
  Metric('Sleep quality', ChartKind.bar, const Color(0xFFD08A2E), (n) => n.quality.toDouble(),
      (v) => '${v.round()}%', 'Your nightly quality score.', maxY: 100),
  Metric('Regularity', ChartKind.range, const Color(0xFF2C7F98), (n) => _clock(n.wokeUp),
      _clockFmt, 'Each bar spans bedtime to wake-up. Shorter spread between nights means a steadier rhythm.',
      low: (n) => _clock(n.wentToBed)),
  Metric('Went to bed', ChartKind.line, const Color(0xFF7FA6B8), (n) => _clock(n.wentToBed), _clockFmt,
      'When you started tracking.'),
  Metric('Woke up', ChartKind.line, const Color(0xFF7FA6B8), (n) => _clock(n.wokeUp), _clockFmt,
      'When tracking stopped.'),
  Metric('Time in bed', ChartKind.bar, const Color(0xFF2C7F98), (n) => n.inBedMinutes / 60,
      (v) => '${v.toStringAsFixed(1)}h', 'Total time tracked each night.'),
  Metric('Asleep', ChartKind.bar, const Color(0xFF2C7F98), (n) => n.asleepMinutes / 60,
      (v) => '${v.toStringAsFixed(1)}h', 'Time actually asleep.'),
  Metric('Asleep after', ChartKind.line, const Color(0xFF7FA6B8), (n) => n.asleepAfterMinutes.toDouble(),
      (v) => '${v.round()}m', 'How long it took to fall asleep.'),
  Metric('Snore', ChartKind.bar, const Color(0xFF2C7F98), (n) => n.snoreMinutes.toDouble(),
      (v) => '${v.round()}m', 'Minutes of snoring per night.'),
  Metric('Coughing', ChartKind.bar, const Color(0xFF2C7F98), (n) => n.coughs.toDouble(),
      (v) => v.toStringAsFixed(0), 'Coughs detected per night.'),
  Metric('Steps', ChartKind.bar, const Color(0xFF2C7F98), (n) => (n.steps ?? 0).toDouble(),
      (v) => v.round().toString(), 'Steps the day before each night.'),
  Metric('Deep sleep', ChartKind.bar, const Color(0xFF8C8A4E),
      (n) => (n.session.phaseMinutes['deep'] ?? 0) / 60, (v) => '${v.toStringAsFixed(1)}h',
      'Hours in deep sleep.'),
  Metric('Breathing disruptions', ChartKind.bar, const Color(0xFF2E7D5B), (n) => n.breathingPerHour,
      (v) => v.toStringAsFixed(1), 'Breathing disruptions per hour of sleep.'),
];

class _Point {
  final String label;
  final double v;
  final double? lo;
  _Point(this.label, this.v, [this.lo]);
}

const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

List<_Point> _series(Metric m, List<Night> nights, int period) {
  if (nights.isEmpty) return [];
  double avg(Iterable<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
  if (period == 0) {
    final last = nights.length > 7 ? nights.sublist(nights.length - 7) : nights;
    return [
      for (final n in last)
        _Point('${_wd[n.day.weekday - 1]}\n${n.day.day}/${n.day.month}', m.value(n), m.low?.call(n))
    ];
  }
  final groups = <String, List<Night>>{};
  for (final n in nights) {
    final key = period == 1
        ? (() {
            final mon = n.day.subtract(Duration(days: n.day.weekday - 1));
            return '${mon.day}/${mon.month}';
          })()
        : '${_mo[n.day.month - 1]}\n${n.day.year % 100}';
    groups.putIfAbsent(key, () => []).add(n);
  }
  var entries = groups.entries.toList();
  final cap = period == 1 ? 8 : (period == 2 ? 6 : 24);
  if (entries.length > cap) entries = entries.sublist(entries.length - cap);
  return [
    for (final e in entries)
      _Point(e.key, avg(e.value.map(m.value)), m.low == null ? null : avg(e.value.map(m.low!)))
  ];
}

class _StatisticsTabState extends State<StatisticsTab> {
  int _period = 0;

  static final List<Night> _demo = () {
    final today = DateTime.now();
    return [
      for (var d = 120; d >= 1; d--)
        sampleNight(DateTime(today.year, today.month, today.day - d + 1, 6 + d % 2, (d * 7) % 60), d)
    ];
  }();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Watch((context, s) {
          final demo = s.nights.isEmpty;
          final nights = demo ? _demo : s.nights;
          final content = ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 120), children: [
            const Text('Statistics', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            _Segments(value: _period, onChanged: (v) => setState(() => _period = v)),
            for (final m in metrics) _ChartCard(metric: m, points: _series(m, nights, _period), demo: demo, nights: nights),
          ]);
          return demo
              ? DemoOverlay(hint: 'Your statistics will be available here after your first night.', child: content)
              : content;
        }),
      ),
    );
  }
}

class _Segments extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _Segments({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    const labels = ['Days', 'Weeks', 'Months', 'All'];
    return Container(
      height: 40,
      decoration: BoxDecoration(color: const Color(0xFF102633), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: value == i ? const Color(0xFF2A5C70) : null, borderRadius: BorderRadius.circular(8)),
                child: Text(labels[i], style: TextStyle(color: value == i ? Colors.white : Colors.white60)),
              ),
            ),
          ),
      ]),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final Metric metric;
  final List<_Point> points;
  final bool demo;
  final List<Night> nights;
  const _ChartCard({required this.metric, required this.points, required this.demo, required this.nights});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(metric.title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
          if (demo)
            const Padding(
              padding: EdgeInsets.only(left: 6, bottom: 3),
              child: Text('(DEMO DATA)', style: TextStyle(fontSize: 11, color: Colors.white60)),
            ),
          const Spacer(),
          ActionChip(
            label: const Text('More ›'),
            labelStyle: const TextStyle(color: AppTheme.accent, fontSize: 13),
            backgroundColor: const Color(0xFF102633),
            shape: const StadiumBorder(side: BorderSide.none),
            onPressed: () => push(context, _MetricDetail(metric: metric, nights: nights)),
          ),
        ]),
        const SizedBox(height: 8),
        SizedBox(height: 170, child: CustomPaint(painter: _ChartPainter(metric, points), size: Size.infinite)),
      ]),
    );
  }
}

class _MetricDetail extends StatefulWidget {
  final Metric metric;
  final List<Night> nights;
  const _MetricDetail({required this.metric, required this.nights});
  @override
  State<_MetricDetail> createState() => _MetricDetailState();
}

class _MetricDetailState extends State<_MetricDetail> {
  int _period = 0;
  @override
  Widget build(BuildContext context) {
    final m = widget.metric;
    final pts = _series(m, widget.nights, _period);
    final vals = pts.map((p) => p.v).toList();
    String stat(double Function(List<double>) f) => vals.isEmpty ? '—' : m.fmt(f(vals));
    return SettingsPage(title: m.title, children: [
      Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Segments(value: _period, onChanged: (v) => setState(() => _period = v)),
          const SizedBox(height: 20),
          SizedBox(height: 260, child: CustomPaint(painter: _ChartPainter(m, pts), size: Size.infinite)),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _kv('Average', stat((v) => v.reduce((a, b) => a + b) / v.length)),
            _kv('Highest', stat((v) => v.reduce(math.max))),
            _kv('Lowest', stat((v) => v.reduce(math.min))),
          ]),
        ]),
      ),
      AboutBlock(m.about),
    ]);
  }

  Widget _kv(String k, String v) => Column(children: [
        Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        Text(k, style: const TextStyle(color: Colors.white60)),
      ]);
}

class _ChartPainter extends CustomPainter {
  final Metric m;
  final List<_Point> pts;
  _ChartPainter(this.m, this.pts);

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.isEmpty) return;
    const left = 58.0, bottom = 34.0;
    final w = size.width - left, h = size.height - bottom;
    final all = [for (final p in pts) ...[p.v, if (p.lo != null) p.lo!]];
    var lo = all.reduce(math.min), hi = all.reduce(math.max);
    if (m.kind == ChartKind.bar) lo = math.min(0, lo);
    // keep a sensible span so a single night (or flat data) doesn't zoom in to noise
    final minSpan = math.max(hi.abs() * 0.2, 1.0);
    if (hi - lo < minSpan) {
      final mid = (hi + lo) / 2;
      lo = m.kind == ChartKind.bar ? lo : mid - minSpan / 2;
      hi = m.kind == ChartKind.bar ? lo + math.max(hi - lo, minSpan) : mid + minSpan / 2;
    }
    final pad = (hi - lo) * 0.1;
    if (m.kind != ChartKind.bar) lo -= pad;
    hi += pad;
    if (m.maxY != null) hi = math.min(hi, m.maxY!);
    double y(double v) => h - (v - lo) / (hi - lo) * h;
    final slot = w / pts.length;
    double x(int i) => left + slot * (i + 0.5);

    final tp = TextPainter(textDirection: TextDirection.ltr, textAlign: TextAlign.center);
    final grid = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    for (var g = 0; g <= 3; g++) {
      final v = lo + (hi - lo) * g / 3;
      final yy = y(v);
      canvas.drawLine(Offset(left, yy), Offset(size.width, yy), grid);
      tp.text = TextSpan(text: m.fmt(v), style: const TextStyle(color: Colors.white60, fontSize: 10));
      tp.layout(maxWidth: left - 4);
      tp.paint(canvas, Offset(0, yy - tp.height / 2));
    }

    final paint = Paint()..color = m.color;
    if (m.kind == ChartKind.line) {
      final path = Path();
      for (var i = 0; i < pts.length; i++) {
        final o = Offset(x(i), y(pts[i].v));
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, Paint()
        ..color = m.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
      for (var i = 0; i < pts.length; i++) {
        canvas.drawCircle(Offset(x(i), y(pts[i].v)), 4, paint);
      }
    } else {
      final bw = math.min(slot * 0.55, 26.0);
      for (var i = 0; i < pts.length; i++) {
        final top = y(pts[i].v);
        final base = m.kind == ChartKind.range ? y(pts[i].lo ?? lo) : y(lo);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTRB(x(i) - bw / 2, math.min(top, base), x(i) + bw / 2, math.max(top, base)),
                const Radius.circular(4)),
            paint);
      }
    }

    final every = (pts.length / 8).ceil();
    for (var i = 0; i < pts.length; i += every) {
      tp.text = TextSpan(text: pts[i].label, style: const TextStyle(color: Colors.white60, fontSize: 10));
      tp.layout(maxWidth: slot * every);
      tp.paint(canvas, Offset(x(i) - tp.width / 2, h + 6));
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) => old.pts != pts;
}
