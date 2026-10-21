import 'package:flutter/material.dart';
import '../data/models.dart';

class AlarmSettingsScreen extends StatefulWidget {
  final AlarmSettings settings;
  const AlarmSettingsScreen({super.key, required this.settings});
  @override
  State<AlarmSettingsScreen> createState() => _AlarmSettingsScreenState();
}

class _AlarmSettingsScreenState extends State<AlarmSettingsScreen> {
  late int hour = widget.settings.alarmTime.hour;
  late int minute = widget.settings.alarmTime.minute;
  late int window = widget.settings.windowMinutes;
  late bool smart = widget.settings.smartAlarmEnabled;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alarm settings'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              AlarmSettings(
                alarmTime: TimeOfDayLike(hour, minute),
                windowMinutes: window,
                smartAlarmEnabled: smart,
              ),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ListTile(
            title: const Text('Alarm time'),
            trailing: Text('${hour.toString().padLeft(2, '0')}:'
                '${minute.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 20)),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(hour: hour, minute: minute),
              );
              if (picked != null) {
                setState(() {
                  hour = picked.hour;
                  minute = picked.minute;
                });
              }
            },
          ),
          SwitchListTile(
            title: const Text('Smart alarm'),
            subtitle: const Text('Wake at a light moment before the alarm'),
            value: smart,
            onChanged: (v) => setState(() => smart = v),
          ),
          const SizedBox(height: 8),
          Text('Wake window: $window min', style: Theme.of(context).textTheme.titleMedium),
          Slider(
            value: window.toDouble(),
            min: 10,
            max: 45,
            divisions: 7,
            label: '$window min',
            onChanged: smart ? (v) => setState(() => window = v.round()) : null,
          ),
        ],
      ),
    );
  }
}
