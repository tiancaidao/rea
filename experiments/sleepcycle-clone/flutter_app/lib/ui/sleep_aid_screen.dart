import 'package:flutter/material.dart';
import '../data/api_client.dart';

/// Sleep-aid catalog from the backend. Tapping a track would start playback via
/// an audio package (e.g. just_audio) and an `AVAudioSession` / foreground media
/// service for background playback; here it shows the catalog + a mock player bar.
class SleepAidScreen extends StatefulWidget {
  final SleepApi api;
  const SleepAidScreen({super.key, required this.api});
  @override
  State<SleepAidScreen> createState() => _SleepAidScreenState();
}

class _SleepAidScreenState extends State<SleepAidScreen> {
  late Future<List<Map<String, dynamic>>> _packages;
  String? _playing;

  @override
  void initState() {
    super.initState();
    _packages = widget.api.sleepAidPackages();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sleep aid')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _packages,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;
          return ListView(
            children: [
              for (final p in items)
                ListTile(
                  leading: Icon(_playing == p['id'] ? Icons.pause_circle : Icons.play_circle,
                      size: 36, color: const Color(0xFF6C7BFF)),
                  title: Text(p['title'] as String),
                  subtitle: Text('${p['durationMin']} min'),
                  onTap: () => setState(() =>
                      _playing = _playing == p['id'] ? null : p['id'] as String),
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: _playing == null
          ? null
          : Container(
              color: const Color(0xFF1A1E3A),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.graphic_eq, color: Color(0xFF6C7BFF)),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Playing $_playing (mock)')),
                  IconButton(
                    icon: const Icon(Icons.stop),
                    onPressed: () => setState(() => _playing = null),
                  ),
                ],
              ),
            ),
    );
  }
}
