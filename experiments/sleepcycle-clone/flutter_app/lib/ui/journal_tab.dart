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
      backgroundColor: const Color(0xFF0E2230),
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(body, style: const TextStyle(color: Colors.white70, height: 1.45)),
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
    final start = night.wentToBed, end = night.wokeUp;
    final range = start.day == end.day
        ? '${end.day} ${_months[end.month - 1]}'
        : '${start.day}-${end.day} ${_months[end.month - 1]}';
    return ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 40), children: [
      // ── header ───────────────────────────────────────────────────────────
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(_weekdays[end.weekday - 1],
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text(range, style: const TextStyle(color: Colors.white70)),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.calendar_month, color: AppTheme.accent),
          onPressed: () => _calendar(context),
        ),
      ]),
      const SizedBox(height: 8),
      _WeekStrip(night: night),
      const Divider(height: 28, color: Colors.white12),
      // ── summary ──────────────────────────────────────────────────────────
      Row(children: [
        GestureDetector(
          onTap: () => showInfoSheet(context, 'Quality',
              'A 0–100% score from how long you slept, how often you woke and how much time you spent in deeper sleep.'),
          child: SizedBox(
            width: 120,
            height: 120,
            child: CustomPaint(
              painter: _RingPainter(night.quality / 100),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${night.quality}%', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const Text('Quality ›', style: TextStyle(color: Colors.white60, fontSize: 12)),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _big(fmtDuration(night.inBedMinutes), 'In bed ›'),
            const SizedBox(height: 12),
            _big(fmtDuration(night.asleepMinutes), 'Asleep ›'),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.share, color: AppTheme.accent),
          onPressed: () => toast(context, 'Share card (not wired in the prototype)'),
        ),
      ]),
      const SizedBox(height: 24),
      Hypnogram(phases: night.session.phases, start: start),
      const SizedBox(height: 10),
      _SnoreRow(night: night),
      const SizedBox(height: 24),
      // ── stat grid ────────────────────────────────────────────────────────
      _StatGrid(night: night),
      const SizedBox(height: 16),
      _Card(
        child: ListTile(
          leading: const Icon(Icons.track_changes, color: AppTheme.accent),
          title: const Text('Sleep Goal'),
          trailing: Text(s.pref('sleep_goal') == 'Not set' ? 'Add new ›' : s.pref('sleep_goal'),
              style: const TextStyle(color: AppTheme.accent)),
          onTap: () => push(context, const SleepGoalPage()),
        ),
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          avatar: const Icon(Icons.edit, size: 18, color: AppTheme.accent),
          label: const Text('Add sleep notes'),
          labelStyle: const TextStyle(color: AppTheme.accent),
          backgroundColor: const Color(0xFF15303F),
          shape: const StadiumBorder(side: BorderSide.none),
          onPressed: () => _notesSheet(context),
        ),
      ),
      if (night.notes.isNotEmpty)
        Wrap(spacing: 8, children: [for (final n in night.notes) Chip(label: Text(n))]),
      const SizedBox(height: 16),
      const _Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Sounds', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text('Snoring and other sounds from the night will appear here.',
                style: TextStyle(color: Colors.white60)),
          ]),
        ),
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
              const Row(children: [
                Text('Breathing disruptions', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                Spacer(),
                Icon(Icons.swap_vert, color: AppTheme.accent),
              ]),
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(night.breathingPerHour.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
                const Text(' /h', style: TextStyle(color: Colors.white60)),
                const Spacer(),
                _Level(value: night.breathingPerHour),
              ]),
              const Text('Average', style: TextStyle(color: Colors.white60)),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 20),
      Row(children: [
        const Text('Online backup  ', style: TextStyle(color: Colors.white60)),
        Icon(Icons.circle, size: 10, color: s.pref('online_backup') == 'On' ? Colors.greenAccent : Colors.white24),
        const SizedBox(width: 6),
        Text(s.pref('online_backup') == 'On' ? 'Backed up' : 'Off',
            style: const TextStyle(color: Colors.white60)),
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
            child: const Text('Delete night', style: TextStyle(color: Colors.redAccent)),
          ),
        ),
    ]);
  }

  Widget _big(String v, String k) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(v, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
        Text(k, style: const TextStyle(color: Colors.white60)),
      ]);

  void _calendar(BuildContext context) {
    final s = AppState.I;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0E2230),
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
      backgroundColor: const Color(0xFF0E2230),
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
                foregroundPainter: n == null ? null : _RingPainter(n.quality / 100, stroke: 3, track: false),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? const Color(0xFF1C3A4A) : const Color(0xFF102633),
                  ),
                  child: Text('SMTWTFS'[i],
                      style: TextStyle(color: selected ? Colors.white : Colors.white54, fontSize: 13)),
                ),
              ),
            ),
          );
        }),
      IconButton(
        icon: const Icon(Icons.description_outlined, color: AppTheme.accent),
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
                  : '$n nights tracked\nAverage quality: ${r['avgQuality']}%\n'
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
        '${week.length} nights tracked\nAverage quality: $q%\nAverage asleep: ${fmtDuration(a)}\n\n'
        'Your most consistent bedtime keeps your quality steady — keep it up.');
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final double stroke;
  final bool track;
  _RingPainter(this.value, {this.stroke = 12, this.track = true});
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    if (track) canvas.drawArc(r, 0, 2 * math.pi, false, p..color = const Color(0xFF1C3442));
    canvas.drawArc(r, -math.pi / 2, 2 * math.pi * value.clamp(0, 1), false, p..color = const Color(0xFFD08A2E));
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value;
}

class _SnoreRow extends StatelessWidget {
  final Night night;
  const _SnoreRow({required this.night});
  @override
  Widget build(BuildContext context) {
    final rng = math.Random(night.wentToBed.millisecondsSinceEpoch);
    return Row(children: [
      const SizedBox(width: 62, child: Text('Snore', style: TextStyle(color: Colors.white60, fontSize: 12))),
      Expanded(
        child: SizedBox(
          height: 14,
          child: LayoutBuilder(
            builder: (c, b) => Stack(children: [
              for (var i = 0; i < night.snoreMinutes ~/ 2; i++)
                Positioned(
                  left: rng.nextDouble() * (b.maxWidth - 6),
                  top: 4,
                  child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.white38, shape: BoxShape.circle)),
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
              Icon(it.$1, color: AppTheme.accent, size: 28),
              const SizedBox(width: 12),
              Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.$2, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                Text('${it.$3} ›', style: const TextStyle(color: Colors.white60, fontSize: 13)),
              ]),
            ]),
          ),
      ],
    );
  }

  void _mood(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0E2230),
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
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF102633),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
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
    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Text('Beta ', style: TextStyle(color: Color(0xFFE8B04A), fontWeight: FontWeight.w700)),
            Text('Alertness', style: TextStyle(color: Colors.white60)),
            Spacer(),
            Icon(Icons.bolt, color: Colors.white38),
          ]),
          const SizedBox(height: 8),
          const Text('Test available tomorrow', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('A one-minute reaction test after you wake shows how rested you really are. '
              'Track tonight to take it tomorrow morning.',
              style: TextStyle(color: Colors.white60, height: 1.4)),
          TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => setState(() => _remind = !_remind),
            icon: Icon(_remind ? Icons.notifications_active : Icons.notifications, color: AppTheme.accent),
            label: Text(_remind ? 'Reminder set' : 'Remind me tomorrow',
                style: const TextStyle(color: AppTheme.accent)),
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
            color: i == level + (level == 2 ? 1 : 0) ? const Color(0xFFE8B04A) : Colors.white24,
          ),
      ]),
    ]);
  }
}
