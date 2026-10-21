import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../theme.dart';
import '../strings.dart';
import '../data/sleep_aid_catalog.dart';

/// Sleep-aid catalog with real playback. Free tracks that have a bundled file
/// play (looped) via just_audio; premium/streamed tracks show a lock, matching
/// the original's free/premium split. A now-playing bar controls playback.
class SleepAidScreen extends StatefulWidget {
  const SleepAidScreen({super.key});
  @override
  State<SleepAidScreen> createState() => _SleepAidScreenState();
}

class _SleepAidScreenState extends State<SleepAidScreen> {
  final _player = AudioPlayer()..setLoopMode(LoopMode.one);
  late Future<SleepAidCatalog> _catalog;
  SleepAidTrack? _current;

  @override
  void initState() {
    super.initState();
    _catalog = SleepAidCatalog.load();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle(SleepAidTrack t) async {
    if (_current?.id == t.id) {
      await _player.stop();
      setState(() => _current = null);
      return;
    }
    if (t.premium || t.asset == null) {
      _lockedSnack();
      return;
    }
    try {
      await _player.setAsset(t.asset!);
      await _player.play();
      setState(() => _current = t);
    } catch (_) {
      _lockedSnack(msg: 'Audio unavailable in this build');
    }
  }

  void _lockedSnack({String? msg}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg ?? '${S.get('get_premium', 'Get Premium')} to unlock')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.get('tab_sleep_aid', 'Sleep aid'))),
      body: FutureBuilder<SleepAidCatalog>(
        future: _catalog,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final cat = snap.data!;
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text(cat.categoryTitle,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              for (final t in cat.tracks)
                Container(
                  color: _current?.id == t.id
                      ? AppTheme.primary.withOpacity(0.14)
                      : null,
                  child: ListTile(
                    leading: Icon(
                      _current?.id == t.id ? Icons.pause_circle_filled : Icons.play_circle,
                      size: 38,
                      color: t.premium ? Colors.white24 : AppTheme.primary,
                    ),
                    title: Text(t.title,
                        style: TextStyle(
                            fontWeight:
                                _current?.id == t.id ? FontWeight.w700 : FontWeight.normal)),
                    subtitle: _current?.id == t.id
                        ? const Text('Playing', style: TextStyle(color: AppTheme.accent))
                        : null,
                    trailing: t.premium
                        ? const Icon(Icons.lock_outline, size: 18, color: Colors.white38)
                        : null,
                    onTap: () => _toggle(t),
                  ),
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: _current == null
          ? null
          : Container(
              color: AppTheme.surface,
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  const Icon(Icons.graphic_eq, color: AppTheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Playing · ${_current!.title}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(
                    icon: const Icon(Icons.stop),
                    onPressed: () => _toggle(_current!),
                  ),
                ],
              ),
            ),
    );
  }
}
