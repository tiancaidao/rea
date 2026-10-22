import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../data/night.dart';
import '../backend/backend.dart';
import '../data/recorded_night.dart';
import '../theme.dart';
import 'settings_pages.dart';
import 'widgets/common.dart';
import 'widgets/hypnogram.dart';
import 'widgets/themed.dart';

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Dims [child], blocks taps on it, and pins a hint near the bottom — the
/// empty state Journal and Statistics show before the first tracked night.
class DemoOverlay extends StatelessWidget {
  final Widget child;
  final String hint;
  const DemoOverlay({super.key, required this.child, required this.hint});
  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(child: AbsorbPointer(child: Opacity(opacity: 0.35, child: child))),
      Positioned(
        left: 32,
        right: 32,
        bottom: 40,
        child: Text(hint,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, height: 1.35, fontWeight: FontWeight.w500)),
      ),
    ]);
  }
}

Future<void> showInfoSheet(BuildContext context, String title, String body) => showModalBottomSheet(
      context: context,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(body, style: TextStyle(color: c.palette.textMuted, height: 1.45)),
        ]),
      ),
    );

/// Journal tab: one night at a time, chosen from the week strip or calendar.
class JournalTab extends StatelessWidget {
  const JournalTab({super.key});

  static final Night _demo =
      sampleNight(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 7, 30), 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Watch((context, s) {
          final night = s.currentNight;
          if (night == null) {
            return DemoOverlay(
              hint: 'Your sleep graph and analysis will show up here after your first night.',
              child: _NightView(night: _demo, demo: true),
            );
          }
          return _NightView(night: night);
        }),
      ),
    );
  }
}

class _NightView extends StatelessWidget {
  final Night night;
  final bool demo;
  const _NightView({required this.night, this.demo = false});

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final p = context.palette;
    final start = night.wentToBed, end = night.wokeUp;
    final range = start.day == end.day
        ? '${end.day} ${_months[end.month - 1]}'
        : '${start.day}-${end.day} ${_months[end.month - 1]}';
    final mins = night.session.phaseMinutes;
    final asleep = night.asleepMinutes == 0 ? 1 : night.asleepMinutes;
    double share(String k) => (mins[k] ?? 0) / asleep;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 40), children: [
      // ── header ───────────────────────────────────────────────────────────
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(_weekdays[end.weekday - 1],
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text(range, style: TextStyle(color: p.textMuted)),
        ),
        const Spacer(),
        IconButton(
          icon: Icon(Icons.ios_share, color: p.accent),
          onPressed: () => toast(context, 'Share card (not wired in the prototype)'),
        ),
        IconButton(
          icon: Icon(Icons.calendar_month, color: p.accent),
          onPressed: () => _calendar(context),
        ),
      ]),
      const SizedBox(height: 8),
      _WeekStrip(night: night),
      const SizedBox(height: 28),
      // ── report hero ──────────────────────────────────────────────────────
      Text(_greeting(end), textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text(_verdict(night.quality),
          textAlign: TextAlign.center, style: TextStyle(color: p.textMuted, fontSize: 15, height: 1.4)),
      const SizedBox(height: 24),
      Center(
        child: GestureDetector(
          onTap: () => showInfoSheet(context, 'Quality · ${night.quality}%',
              'A 0–100% score from how long you slept, how often you woke and how much time you spent in deeper sleep.'),
          child: StageRing(
            phases: night.session.phases,
            quality: night.quality,
            subtitle: fmtDuration(night.asleepMinutes),
          ),
        ),
      ),
      const SizedBox(height: 18),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.nightlight_round, size: 18, color: p.textMuted),
        const SizedBox(width: 6),
        Text(fmtDt(start), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        const SizedBox(width: 28),
        Icon(Icons.wb_sunny_outlined, size: 18, color: p.textMuted),
        const SizedBox(width: 6),
        Text(fmtDt(end), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      ]),
      const SizedBox(height: 24),
      // ── stage tiles ──────────────────────────────────────────────────────
      _TileGrid(children: [
        StatTile(color: p.deep, label: 'Deep sleep', minutes: mins['deep'] ?? 0,
            status: share('deep') >= 0.13 ? 'In range' : 'Below avg',
            statusIcon: share('deep') >= 0.13 ? Icons.check_circle : Icons.arrow_circle_down),
        StatTile(color: p.light, label: 'Light sleep', minutes: mins['light'] ?? 0,
            status: share('light') <= 0.6 ? 'In range' : 'Above avg',
            statusIcon: share('light') <= 0.6 ? Icons.check_circle : Icons.arrow_circle_up),
        StatTile(color: p.rem, label: 'REM', minutes: mins['rem'] ?? 0,
            status: share('rem') >= 0.18 ? 'In range' : 'Below avg',
            statusIcon: share('rem') >= 0.18 ? Icons.check_circle : Icons.arrow_circle_down),
        StatTile(color: p.awake, label: 'Awake', minutes: mins['awake'] ?? 0,
            status: (mins['awake'] ?? 0) <= 30 ? 'Low' : 'High',
            statusIcon: (mins['awake'] ?? 0) <= 30 ? Icons.check_circle : Icons.arrow_circle_up),
      ]),
      const SizedBox(height: 16),
      // ── graph ────────────────────────────────────────────────────────────
      GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Sleep graph', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${fmtDuration(night.inBedMinutes)} in bed', style: TextStyle(color: p.textMuted)),
          ]),
          const SizedBox(height: 16),
          Hypnogram(phases: night.session.phases, start: start),
          const SizedBox(height: 10),
          _SnoreRow(night: night),
        ]),
      ),
      const SizedBox(height: 16),
      // ── stat grid ────────────────────────────────────────────────────────
      GlassCard(padding: const EdgeInsets.fromLTRB(16, 8, 8, 8), child: _StatGrid(night: night)),
      const SizedBox(height: 16),
      _Card(
        child: ListTile(
          leading: Icon(Icons.track_changes, color: p.accent),
          title: const Text('Sleep Goal'),
          trailing: Text(s.pref('sleep_goal') == 'Not set' ? 'Add new ›' : s.pref('sleep_goal'),
              style: TextStyle(color: p.accent)),
          onTap: () => push(context, const SleepGoalPage()),
        ),
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          avatar: Icon(Icons.edit, size: 18, color: p.accent),
          label: const Text('Add sleep notes'),
          labelStyle: TextStyle(color: p.accent),
          backgroundColor: p.surface,
          shape: StadiumBorder(side: BorderSide(color: p.stroke)),
          onPressed: () => _notesSheet(context),
        ),
      ),
      if (night.notes.isNotEmpty)
        Wrap(spacing: 8, children: [for (final n in night.notes) Chip(label: Text(n))]),
      const SizedBox(height: 16),
      GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Sounds', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Snoring and other sounds from the night will appear here.',
              style: TextStyle(color: p.textMuted)),
        ]),
      ),
      const SizedBox(height: 16),
      const _AlertnessCard(),
      const SizedBox(height: 16),
      _Card(
        child: InkWell(
          onTap: () => showInfoSheet(context, 'Breathing disruptions',
              'Pauses or changes in breathing per hour of sleep, estimated from sound. Not a medical diagnosis.'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('Breathing disruptions', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                const Spacer(),
                Icon(Icons.swap_vert, color: p.accent),
              ]),
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(night.breathingPerHour.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
                Text(' /h', style: TextStyle(color: p.textMuted)),
                const Spacer(),
                _Level(value: night.breathingPerHour),
              ]),
              Text('Average', style: TextStyle(color: p.textMuted)),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 20),
      Row(children: [
        Text('Online backup  ', style: TextStyle(color: p.textMuted)),
        Icon(Icons.circle, size: 10, color: s.pref('online_backup') == 'On' ? p.positive : p.textFaint),
        const SizedBox(width: 6),
        Text(s.pref('online_backup') == 'On' ? 'Backed up' : 'Off', style: TextStyle(color: p.textMuted)),
      ]),
      if (!demo)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () async {
              if (await confirm(context, 'Delete night?', 'This night will be removed permanently.', 'Delete')) {
                s.deleteNight(night);
              }
            },
            child: Text('Delete night', style: TextStyle(color: p.awake)),
          ),
        ),
    ]);
  }

  static String _greeting(DateTime wokeUp) =>
      wokeUp.hour < 12 ? 'Good morning' : (wokeUp.hour < 18 ? 'Good afternoon' : 'Good evening');

  static String _verdict(int q) => q >= 85
      ? 'Your sleep report is in, and it looks great.'
      : q >= 70
          ? 'Your sleep report is in, and it\'s looking good.'
          : q >= 50
              ? 'Your sleep report is in. A fair night, with room to improve.'
              : 'Your sleep report is in. A rough night; go easy today.';

  void _calendar(BuildContext context) {
    final s = AppState.I;
    showModalBottomSheet(
      context: context,
      builder: (c) => ListView(children: [
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text('All nights', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ),
        for (var i = s.nights.length - 1; i >= 0; i--)
          ListTile(
            title: Text(
                '${_weekdays[s.nights[i].wokeUp.weekday - 1]} ${s.nights[i].wokeUp.day} ${_months[s.nights[i].wokeUp.month - 1]}'),
            trailing: Text('${s.nights[i].quality}%'),
            onTap: () {
              s.selectNight(i);
              Navigator.pop(c);
            },
          ),
      ]),
    );
  }

  void _notesSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setSt) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Sleep notes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final n in AppState.I.sleepNotes)
                FilterChip(
                  label: Text(n),
                  selected: night.notes.contains(n),
                  onSelected: (v) {
                    setSt(() => v ? night.notes.add(n) : night.notes.remove(n));
                    AppState.I.nightChanged(night);
                  },
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  final Night night;
  const _WeekStrip({required this.night});
  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final p = context.palette;
    final day = night.day;
    final sunday = day.subtract(Duration(days: day.weekday % 7));
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      for (var i = 0; i < 7; i++)
        Builder(builder: (context) {
          final d = sunday.add(Duration(days: i));
          final idx = s.nights.indexWhere((n) => n.day == d);
          final n = idx >= 0 ? s.nights[idx] : (d == day ? night : null);
          final selected = d == day;
          return GestureDetector(
            onTap: idx >= 0 ? () => s.selectNight(idx) : null,
            child: SizedBox(
              width: 38,
              height: 38,
              child: CustomPaint(
                foregroundPainter:
                    n == null ? null : _RingPainter(n.quality / 100, p.quality, p.surfaceHi, stroke: 3, track: false),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? p.segThumb : p.surface,
                    border: Border.all(color: p.stroke),
                  ),
                  child: Text('SMTWTFS'[i],
                      style: TextStyle(
                          color: selected ? p.segThumbText : p.textMuted,
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
                ),
              ),
            ),
          );
        }),
      IconButton(
        icon: Icon(Icons.description_outlined, color: p.accent),
        onPressed: () => _weeklyReport(context, sunday),
      ),
    ]);
  }

  Future<void> _weeklyReport(BuildContext context, DateTime sunday) async {
    if (Backend.I.user != null) {
      try {
        // the server report weeks start on Monday
        final r = await Backend.I.weeklyReport(sunday.add(const Duration(days: 1)));
        if (r != null && context.mounted) {
          final n = r['nights'] as int;
          showInfoSheet(
              context,
              'Weekly report',
              n == 0
                  ? (r['highlights'] as List).join('\n')
                  : '$n ${n == 1 ? 'night' : 'nights'} tracked\nAverage quality: ${r['avgQuality']}%\n'
                      'Average asleep: ${fmtDuration(r['avgAsleepMin'] as int)}\n'
                      'Regularity: ${r['regularity']}%\n\n${(r['highlights'] as List).join('\n')}');
          return;
        }
      } catch (_) {
        // fall back to the on-device summary
      }
    }
    if (!context.mounted) return;
    final week = AppState.I.nights
        .where((n) => !n.day.isBefore(sunday) && n.day.isBefore(sunday.add(const Duration(days: 7))))
        .toList();
    if (week.isEmpty) {
      showInfoSheet(context, 'Weekly report',
          'Track a few nights this week and a summary will be ready on Monday morning.');
      return;
    }
    final q = week.map((n) => n.quality).reduce((a, b) => a + b) ~/ week.length;
    final a = week.map((n) => n.asleepMinutes).reduce((a, b) => a + b) ~/ week.length;
    showInfoSheet(context, 'Weekly report',
        '${week.length} ${week.length == 1 ? 'night' : 'nights'} tracked\nAverage quality: $q%\nAverage asleep: ${fmtDuration(a)}\n\n'
        'Your most consistent bedtime keeps your quality steady — keep it up.');
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;
  final Color trackColor;
  final double stroke;
  final bool track;
  _RingPainter(this.value, this.color, this.trackColor, {this.stroke = 12, this.track = true});
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    if (track) canvas.drawArc(r, 0, 2 * math.pi, false, p..color = trackColor);
    canvas.drawArc(r, -math.pi / 2, 2 * math.pi * value.clamp(0, 1), false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color;
}

class _SnoreRow extends StatelessWidget {
  final Night night;
  const _SnoreRow({required this.night});
  @override
  Widget build(BuildContext context) {
    final rng = math.Random(night.wentToBed.millisecondsSinceEpoch);
    final p = context.palette;
    return Row(children: [
      SizedBox(width: 62, child: Text('Snore', style: TextStyle(color: p.textMuted, fontSize: 12))),
      Expanded(
        child: SizedBox(
          height: 14,
          child: LayoutBuilder(
            builder: (c, b) => Stack(children: [
              for (var i = 0; i < night.snoreMinutes ~/ 2; i++)
                Positioned(
                  left: rng.nextDouble() * (b.maxWidth - 6),
                  top: 4,
                  child: Container(width: 6, height: 6, decoration: BoxDecoration(color: p.textFaint, shape: BoxShape.circle)),
                ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _StatGrid extends StatelessWidget {
  final Night night;
  const _StatGrid({required this.night});

  static const _moods = ['Bad', 'Okay', 'Good'];

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String, String)>[
      (Icons.bar_chart, '${night.regularity}%', 'Regularity',
          'How consistent your bed and wake times are compared with recent nights.'),
      (Icons.timelapse, '${night.asleepAfterMinutes} min', 'Asleep after',
          'Time from going to bed until you fell asleep.'),
      (Icons.nightlight, fmtDt(night.wentToBed), 'Went to bed', 'When you started tracking.'),
      (Icons.alarm, fmtDt(night.wokeUp), 'Woke up', 'When tracking stopped.'),
      (Icons.graphic_eq, '${night.snoreMinutes} min', 'Snore', 'Minutes of detected snoring.'),
      (Icons.directions_walk, night.steps == null ? '—' : '${night.steps}', 'Steps', 'Steps the day before, from Health Connect.'),
      (Icons.sentiment_satisfied, night.mood == null ? 'Add' : _moods[night.mood!], 'Wake up mood', ''),
      (Icons.cloud, night.weatherF == null ? '—' : '${night.weatherF} °F', 'Weather', 'Morning weather at your location.'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.6,
      children: [
        for (final it in items)
          InkWell(
            onTap: () => it.$3 == 'Wake up mood' ? _mood(context) : showInfoSheet(context, it.$3, it.$4),
            child: Row(children: [
              Icon(it.$1, color: context.palette.accent, size: 26),
              const SizedBox(width: 12),
              Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.$2, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                Text('${it.$3} ›', style: TextStyle(color: context.palette.textMuted, fontSize: 13)),
              ]),
            ]),
          ),
      ],
    );
  }

  void _mood(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('How do you feel this morning?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (var i = 0; i < 3; i++)
              GestureDetector(
                onTap: () {
                  night.mood = i;
                  AppState.I.nightChanged(night);
                  Navigator.pop(c);
                },
                child: Column(children: [
                  Text(['☹️', '😐', '🙂'][i], style: const TextStyle(fontSize: 44)),
                  Text(_moods[i]),
                ]),
              ),
          ]),
        ]),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => GlassCard(padding: EdgeInsets.zero, child: child);
}

/// Two-column grid of equal-height tiles.
class _TileGrid extends StatelessWidget {
  final List<Widget> children;
  const _TileGrid({required this.children});
  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < children.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: children[i]),
              const SizedBox(width: 12),
              Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
            ]),
          ),
        ],
      ]);
}

class _AlertnessCard extends StatefulWidget {
  const _AlertnessCard();
  @override
  State<_AlertnessCard> createState() => _AlertnessCardState();
}

class _AlertnessCardState extends State<_AlertnessCard> {
  bool _remind = false;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Beta ', style: TextStyle(color: p.warn, fontWeight: FontWeight.w700)),
            Text('Alertness', style: TextStyle(color: p.textMuted)),
            const Spacer(),
            Icon(Icons.bolt, color: p.textFaint),
          ]),
          const SizedBox(height: 8),
          const Text('Test available tomorrow', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('A one-minute reaction test after you wake shows how rested you really are. '
              'Track tonight to take it tomorrow morning.',
              style: TextStyle(color: p.textMuted, height: 1.4)),
          TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => setState(() => _remind = !_remind),
            icon: Icon(_remind ? Icons.notifications_active : Icons.notifications, color: p.accent),
            label: Text(_remind ? 'Reminder set' : 'Remind me tomorrow', style: TextStyle(color: p.accent)),
          ),
        ]),
      ),
    );
  }
}

class _Level extends StatelessWidget {
  final double value;
  const _Level({required this.value});
  @override
  Widget build(BuildContext context) {
    final level = value < 5 ? 0 : (value < 15 ? 1 : 2);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(['LOW', 'MEDIUM', 'HIGH'][level],
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1)),
      const SizedBox(height: 4),
      Row(children: [
        for (var i = 0; i < 4; i++)
          Container(
            width: 26,
            height: 6,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: i == level + (level == 2 ? 1 : 0) ? context.palette.warn : context.palette.surfaceHi,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ]),
    ]);
  }
}
