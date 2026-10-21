import 'dart:async';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../data/sleep_aid_catalog.dart';
import '../theme.dart';
import 'widgets/common.dart';

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
          color: const Color(0xFF0A1B26),
          borderRadius: BorderRadius.circular(28),
          gradient: item == null
              ? null
              : LinearGradient(colors: [const Color(0xFF0A1B26), item.art.first.withOpacity(0.7)]),
        ),
        child: Row(children: [
          Expanded(
            child: InkWell(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(28)),
              onTap: () => showSleepAidCatalog(context),
              child: Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(item?.title ?? 'Sleep aid',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppTheme.accent, fontSize: 17, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ),
          Container(width: 1, height: 28, color: Colors.white24),
          IconButton(
            iconSize: 30,
            color: AppTheme.accent,
            icon: Icon(s.sleepAidPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: () => item == null ? showSleepAidCatalog(context) : s.toggleSleepAid(),
          ),
          const SizedBox(width: 8),
        ]),
      );
    });
  }
}

Future<void> showSleepAidCatalog(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF0C1E2B),
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
    final sections = _chip == 0
        ? SleepAidCatalog.current
        : [SleepAidCatalog.current[_chip - 1]];
    return Column(children: [
      _SheetHeader(title: 'Sleep aid'),
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
                  selectedColor: AppTheme.accent,
                  backgroundColor: const Color(0xFF15303F),
                  labelStyle: TextStyle(color: _chip == i ? Colors.black : AppTheme.accent),
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
            icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.accent, size: 32),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
              child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          IconButton(
            icon: Icon(s.sleepAidPlaying ? Icons.pause : Icons.play_arrow,
                color: AppTheme.accent, size: 30),
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
      onTap: () => showTrackSheet(context, item),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: const Color(0xFF4C7D93), borderRadius: BorderRadius.circular(4)),
            child: const Text('FEATURED',
                style: TextStyle(fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text(item.title,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 150, height: 96, child: ArtBox(colors: item.art, icon: Icons.air)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(item.description,
                  style: const TextStyle(color: Colors.white70, height: 1.35))),
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
    final preview = section.layout == SectionLayout.grid
        ? section.items.take(4).toList()
        : section.items.take(2).toList();
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
        labelStyle: const TextStyle(color: AppTheme.accent),
        backgroundColor: const Color(0xFF15303F),
        shape: const StadiumBorder(side: BorderSide.none),
        onPressed: () => push(context, _SectionPage(section: section)),
      ),
      const SizedBox(height: 8),
      const Divider(color: Colors.white12),
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
            onTap: () => showTrackSheet(context, it),
            child: Stack(children: [
              Positioned.fill(child: ArtBox(colors: it.art, label: it.title)),
              Positioned(
                right: 8,
                top: 8,
                child: Watch((c, s) => s.sleepAid?.id == it.id
                    ? const Icon(Icons.check_circle, size: 20, color: Colors.white)
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
      onTap: () => showTrackSheet(context, item),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(aspectRatio: 2.3, child: ArtBox(colors: item.art, radius: 16)),
          const SizedBox(height: 10),
          Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 2),
          Text('${item.description} (${item.minutes} min)',
              style: const TextStyle(color: Colors.white60, height: 1.35)),
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
      backgroundColor: const Color(0xFF0C1E2B),
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

  @override
  void initState() {
    super.initState();
    if (AppState.I.sleepAid?.id == widget.item.id) {
      _progress = null; // already downloaded
    } else {
      _t = Timer.periodic(const Duration(milliseconds: 60), (t) {
        setState(() => _progress = (_progress ?? 0) + 0.04);
        if ((_progress ?? 0) >= 1) {
          t.cancel();
          setState(() => _progress = null);
          AppState.I.chooseSleepAid(widget.item);
        }
      });
    }
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
          Positioned.fill(child: ArtBox(colors: it.art, radius: 0)),
          Positioned(
            left: 4,
            top: 4,
            child: IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.accent, size: 32),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Positioned.fill(
            top: 90,
            child: Column(children: [
              Text(it.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
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
                    child: CircularProgressIndicator(
                        value: _progress, strokeWidth: 4, color: AppTheme.accent),
                  ),
                  const SizedBox(width: 16),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel download',
                        style: TextStyle(color: AppTheme.accent, fontSize: 16)),
                  ),
                ])
              else
                Watch((c, s) => IconButton.filledTonal(
                      iconSize: 44,
                      style: IconButton.styleFrom(backgroundColor: Colors.white24),
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
                    leading: SizedBox(width: 72, child: ArtBox(colors: other.art, radius: 8)),
                    title: Text(other.title),
                    onTap: () {
                      Navigator.pop(context);
                      showTrackSheet(context, other);
                    },
                  )
                : HeroCard(item: other),
        ]),
      ),
    ]);
  }

  Widget _credit(String k, String v) => Column(children: [
        Text(k, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 2),
        Text(v, style: const TextStyle(fontSize: 16)),
      ]);
}
