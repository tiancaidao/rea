import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../app_state.dart';
import '../data/sleep_aid_catalog.dart';
import '../theme.dart';
import 'welcome_screen.dart' show TrialScreen;
import 'widgets/common.dart';
import 'widgets/illustrations.dart';

/// The pill at the top of the Sleep and tracking screens. Shows "Sleep aid"
/// (or the chosen track with its art); tapping opens the catalog sheet, the
/// trailing button plays/pauses.
class SleepAidPill extends StatelessWidget {
  const SleepAidPill({super.key});
  @override
  Widget build(BuildContext context) {
    return Watch((context, s) {
      final item = s.sleepAid;
      return Container(
        height: 56,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: context.palette.surface,
          border: Border.all(color: context.palette.stroke),
          borderRadius: BorderRadius.circular(28),
          gradient:
              item == null ? null : LinearGradient(colors: [context.palette.surface, item.art.first.withOpacity(0.7)]),
        ),
        child: Row(children: [
          Expanded(
            child: InkWell(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(28)),
              onTap: () => showSleepAidCatalog(context),
              child: Padding(
                padding: EdgeInsets.only(left: item == null ? 24 : 6),
                child: Row(children: [
                  if (item != null) ...[
                    SizedBox(
                        width: 44, height: 44, child: ArtBox(image: item.image, colors: item.art, radius: 22, seed: item.id.hashCode)),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(item?.title ?? 'Sleep aid',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: context.palette.accent, fontSize: 17, fontWeight: FontWeight.w600)),
                  ),
                  if (item != null && s.sleepAidPlaying) ...[
                    EqBars(color: context.palette.accent),
                    const SizedBox(width: 12),
                  ],
                ]),
              ),
            ),
          ),
          Container(width: 1, height: 28, color: context.palette.textFaint),
          IconButton(
            iconSize: 30,
            color: context.palette.accent,
            icon: Icon(s.sleepAidPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: () => item == null ? showSleepAidCatalog(context) : s.toggleSleepAid(),
          ),
          const SizedBox(width: 8),
        ]),
      );
    });
  }
}

/// Opens a track, or the paywall for Premium content on a free account.
void openItem(BuildContext context, SleepAidItem it) {
  if (it.premium && !AppState.I.premium) {
    push(context, const TrialScreen());
    return;
  }
  showTrackSheet(context, it);
}

/// The small "Premium" badge on catalog art (a check once unlocked).
class PremiumBadge extends StatelessWidget {
  const PremiumBadge({super.key});
  @override
  Widget build(BuildContext context) => Watch((context, s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(s.premium ? Icons.check : Icons.lock, size: 12, color: Colors.white),
          const SizedBox(width: 3),
          const Text('PREMIUM', style: TextStyle(fontSize: 9, letterSpacing: 0.8, color: Colors.white)),
        ]),
      ));
}

Future<void> showSleepAidCatalog(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const FractionallySizedBox(heightFactor: 0.97, child: _CatalogSheet()),
    );

class _CatalogSheet extends StatefulWidget {
  const _CatalogSheet();
  @override
  State<_CatalogSheet> createState() => _CatalogSheetState();
}

class _CatalogSheetState extends State<_CatalogSheet> {
  int _chip = 0; // 0 = All, else section index + 1

  @override
  void initState() {
    super.initState();
    // server-driven catalog with streamed media when the backend is on
    SleepAidCatalog.refresh().then((changed) {
      if (changed && mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final sections = _chip == 0 ? SleepAidCatalog.current : [SleepAidCatalog.current[_chip - 1]];
    return Column(children: [
      const _SheetHeader(title: 'Sleep aid'),
      SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          children: [
            for (var i = 0; i <= SleepAidCatalog.current.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(i == 0 ? 'All' : SleepAidCatalog.current[i - 1].title),
                  selected: _chip == i,
                  showCheckmark: false,
                  selectedColor: context.palette.segThumb,
                  backgroundColor: context.palette.surfaceHi,
                  labelStyle: TextStyle(color: _chip == i ? context.palette.segThumbText : context.palette.accent),
                  shape: const StadiumBorder(side: BorderSide.none),
                  onSelected: (_) => setState(() => _chip = i),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
          if (_chip == 0) _Featured(item: SleepAidCatalog.currentFeatured),
          for (final s in sections) _Section(section: s),
        ]),
      ),
    ]);
  }
}

class _SheetHeader extends StatelessWidget {
  final String title;
  const _SheetHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    return Watch((context, s) => Row(children: [
          IconButton(
            icon: Icon(Icons.keyboard_arrow_down, color: context.palette.accent, size: 32),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          IconButton(
            icon: Icon(s.sleepAidPlaying ? Icons.pause : Icons.play_arrow, color: context.palette.accent, size: 30),
            onPressed: s.sleepAid == null ? null : s.toggleSleepAid,
          ),
        ]));
  }
}

class _Featured extends StatelessWidget {
  final SleepAidItem item;
  const _Featured({required this.item});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openItem(context, item),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: context.palette.surfaceHi, borderRadius: BorderRadius.circular(4)),
            child:
                const Text('FEATURED', style: TextStyle(fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(item.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 150, height: 96, child: ArtBox(image: item.image, colors: item.art, seed: item.id.hashCode)),
          const SizedBox(width: 12),
          Expanded(child: Text(item.description, style: TextStyle(color: context.palette.textMuted, height: 1.35))),
        ]),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  final SleepAidSection section;
  const _Section({required this.section});
  @override
  Widget build(BuildContext context) {
    final preview =
        section.layout == SectionLayout.grid ? section.items.take(4).toList() : section.items.take(2).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 28),
      Text(section.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
      const SizedBox(height: 14),
      if (section.layout == SectionLayout.grid)
        _Grid(items: preview)
      else
        for (final it in preview) HeroCard(item: it),
      const SizedBox(height: 8),
      ActionChip(
        label: Text('Show all (${section.items.length})'),
        labelStyle: TextStyle(color: context.palette.accent),
        backgroundColor: context.palette.surfaceHi,
        shape: const StadiumBorder(side: BorderSide.none),
        onPressed: () => push(context, _SectionPage(section: section)),
      ),
      const SizedBox(height: 8),
      const Divider(),
    ]);
  }
}

class _Grid extends StatelessWidget {
  final List<SleepAidItem> items;
  const _Grid({required this.items});
  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.7,
      children: [
        for (final it in items)
          InkWell(
            onTap: () => openItem(context, it),
            child: Stack(children: [
              Positioned.fill(child: ArtBox(image: it.image, colors: it.art, label: it.title, seed: it.id.hashCode)),
              if (it.premium) const Positioned(left: 8, top: 8, child: PremiumBadge()),
              Positioned(
                right: 8,
                top: 8,
                child: Watch((c, s) => s.sleepAid?.id == it.id
                    ? (s.sleepAidPlaying
                        ? const EqBars(color: Colors.white)
                        : const Icon(Icons.check_circle, size: 20, color: Colors.white))
                    : const SizedBox()),
              ),
            ]),
          ),
      ],
    );
  }
}

class HeroCard extends StatelessWidget {
  final SleepAidItem item;
  const HeroCard({super.key, required this.item});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openItem(context, item),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: 2.3,
            child: Stack(children: [
              Positioned.fill(child: ArtBox(image: item.image, colors: item.art, radius: 16, seed: item.id.hashCode)),
              if (item.premium) const Positioned(left: 10, top: 10, child: PremiumBadge()),
            ]),
          ),
          const SizedBox(height: 10),
          Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 2),
          Text('${item.description} (${item.minutes} min)',
              style: TextStyle(color: context.palette.textMuted, height: 1.35)),
        ]),
      ),
    );
  }
}

class _SectionPage extends StatelessWidget {
  final SleepAidSection section;
  const _SectionPage({required this.section});
  @override
  Widget build(BuildContext context) {
    return SettingsPage(title: section.title, children: [
      Padding(
        padding: const EdgeInsets.all(20),
        child: section.layout == SectionLayout.grid
            ? _Grid(items: section.items)
            : Column(children: [for (final it in section.items) HeroCard(item: it)]),
      ),
    ]);
  }
}

Future<void> showTrackSheet(BuildContext context, SleepAidItem item) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => FractionallySizedBox(heightFactor: 0.97, child: _TrackSheet(item: item)),
    );

/// Track detail: full-bleed art header with title and credits; a fake
/// download ring (streamed content is cached before playback in the
/// original), then a play/pause control. Below, the rest of its section.
class _TrackSheet extends StatefulWidget {
  final SleepAidItem item;
  const _TrackSheet({required this.item});
  @override
  State<_TrackSheet> createState() => _TrackSheetState();
}

class _TrackSheetState extends State<_TrackSheet> {
  double? _progress = 0;
  Timer? _t;
  http.Client? _client;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    final s = AppState.I;
    final it = widget.item;
    if (s.sleepAid?.id == it.id || s.sleepAidCache.containsKey(it.id)) {
      _progress = null; // already downloaded
      if (s.sleepAid?.id != it.id) s.chooseSleepAid(it);
    } else if (it.url != null) {
      _download(it);
    } else {
      // bundled audio: a short "preparing" ring, then play
      _t = Timer.periodic(const Duration(milliseconds: 40), (t) {
        setState(() => _progress = (_progress ?? 0) + 0.08);
        if ((_progress ?? 0) >= 1) {
          t.cancel();
          setState(() => _progress = null);
          s.chooseSleepAid(it);
        }
      });
    }
  }

  /// Streamed tracks are downloaded to the cache before playing, with real
  /// progress and a working Cancel (as the original's sleep-aid downloads).
  Future<void> _download(SleepAidItem it) async {
    final client = _client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(it.url!)));
      if (res.statusCode >= 400) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength ?? 0;
      final dir = await getApplicationCacheDirectory();
      final f = File('${dir.path}/sleepaid_${it.id}');
      final sink = f.openWrite();
      var got = 0;
      await for (final chunk in res.stream) {
        if (_cancelled) break;
        sink.add(chunk);
        got += chunk.length;
        if (total > 0 && mounted) setState(() => _progress = got / total);
      }
      await sink.close();
      if (_cancelled) {
        await f.delete();
        return;
      }
      AppState.I.sleepAidCache[it.id] = f.path;
    } catch (_) {
      // download failed: stream it instead
    } finally {
      client.close();
    }
    if (_cancelled || !mounted) return;
    setState(() => _progress = null);
    AppState.I.chooseSleepAid(it);
  }

  void _cancel() {
    _cancelled = true;
    _t?.cancel();
    _client?.close();
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final section =
        SleepAidCatalog.current.firstWhere((s) => s.items.contains(it), orElse: () => SleepAidCatalog.current.first);
    return ListView(padding: EdgeInsets.zero, children: [
      SizedBox(
        height: 400,
        child: Stack(children: [
          Positioned.fill(child: ArtBox(image: it.image, colors: it.art, radius: 0, seed: it.id.hashCode)),
          // scrim so the title and credits stay readable over the art
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x33000000), Color(0x99000000), Color(0x33000000)],
                  stops: [0.1, 0.35, 0.7],
                ),
              ),
            ),
          ),
          Positioned(
            left: 4,
            top: 4,
            child: IconButton(
              icon: Icon(Icons.keyboard_arrow_down, color: context.palette.accent, size: 32),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Positioned.fill(
            top: 90,
            child: Column(children: [
              Text(it.title,
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _credit('Author', it.author),
                if (it.narrator.isNotEmpty) _credit('Narrator', it.narrator),
              ]),
              const SizedBox(height: 40),
              if (_progress != null)
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: CircularProgressIndicator(value: _progress, strokeWidth: 4, color: context.palette.accent),
                  ),
                  const SizedBox(width: 16),
                  TextButton(
                    onPressed: _cancel,
                    child: Text('Cancel download', style: TextStyle(color: context.palette.accent, fontSize: 16)),
                  ),
                ])
              else
                Watch((c, s) => IconButton.filledTonal(
                      iconSize: 44,
                      style: IconButton.styleFrom(backgroundColor: context.palette.textFaint),
                      icon: Icon(s.sleepAidPlaying ? Icons.pause : Icons.play_arrow),
                      onPressed: s.toggleSleepAid,
                    )),
            ]),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          for (final other in section.items.where((o) => o.id != it.id))
            section.layout == SectionLayout.grid
                ? ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: SizedBox(width: 72, child: ArtBox(image: other.image, colors: other.art, radius: 8, seed: other.id.hashCode)),
                    title: Text(other.title),
                    trailing: other.premium ? const PremiumBadge() : null,
                    onTap: () {
                      Navigator.pop(context);
                      openItem(context, other);
                    },
                  )
                : HeroCard(item: other),
        ]),
      ),
    ]);
  }

  Widget _credit(String k, String v) => Column(children: [
        Text(k, style: TextStyle(color: context.palette.textMuted)),
        const SizedBox(height: 2),
        Text(v, style: const TextStyle(fontSize: 16)),
      ]);
}
