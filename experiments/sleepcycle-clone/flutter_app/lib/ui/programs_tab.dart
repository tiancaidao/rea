import 'package:flutter/material.dart';
import '../app_state.dart';
import '../data/programs.dart';
import '../theme.dart';
import 'widgets/common.dart';
import 'widgets/looping_video.dart';

/// Programs tab: a vertical list of illustrated program cards.
class ProgramsTab extends StatelessWidget {
  const ProgramsTab({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 24), children: [
          const Text('Programs', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          for (final p in programs) _ProgramCard(program: p),
        ]),
      ),
    );
  }
}

class _ProgramCard extends StatelessWidget {
  final Program program;
  const _ProgramCard({required this.program});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => push(context, ProgramDetail(program: program)),
        child: Container(
          height: 150,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(colors: program.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          padding: const EdgeInsets.all(18),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(program.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(program.subtitle, style: TextStyle(color: context.palette.textMuted, height: 1.3)),
              ]),
            ),
            Icon(program.icon, size: 72, color: context.palette.textFaint),
          ]),
        ),
      ),
    );
  }
}

class ProgramDetail extends StatelessWidget {
  final Program program;
  const ProgramDetail({super.key, required this.program});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Watch((context, s) {
        final done = program.lessons.where((l) => s.completedLessons.contains(l.id)).length;
        return CustomScrollView(slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: program.colors.last,
            leading: IconButton(
                icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: program.colors, begin: Alignment.topCenter, end: Alignment.bottomCenter)),
                child: Icon(program.icon, size: 140, color: context.palette.textFaint),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList.list(children: [
              Text(program.title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('$done/${program.lessons.length} COMPLETED',
                  style: const TextStyle(fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              Text(program.intro, style: const TextStyle(fontSize: 17, height: 1.4)),
              const SizedBox(height: 24),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 1.05,
                children: [
                  for (final l in program.lessons)
                    InkWell(
                      onTap: () => push(
                          context,
                          l.kind == LessonKind.video
                              ? _VideoLesson(lesson: l, program: program)
                              : _CardsLesson(lesson: l)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Stack(children: [
                            Positioned.fill(
                                child: ArtBox(
                                    colors: program.colors,
                                    icon: l.kind == LessonKind.video ? Icons.play_circle : program.icon)),
                            if (s.completedLessons.contains(l.id))
                              Positioned(
                                  right: 6, top: 6, child: Icon(Icons.check_circle, color: context.palette.accent)),
                          ]),
                        ),
                        const SizedBox(height: 6),
                        Text(l.title,
                            maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                    ),
                ],
              ),
            ]),
          ),
        ]);
      }),
    );
  }
}

/// Video lesson: full-screen clip area with a caption and an Unmute pill.
/// (No video is bundled; the clip area is a placeholder.)
class _VideoLesson extends StatefulWidget {
  final Lesson lesson;
  final Program program;
  const _VideoLesson({required this.lesson, required this.program});
  @override
  State<_VideoLesson> createState() => _VideoLessonState();
}

class _VideoLessonState extends State<_VideoLesson> {
  bool _muted = true;
  @override
  void initState() {
    super.initState();
    // watching the clip counts as completing it
    WidgetsBinding.instance.addPostFrameCallback((_) => AppState.I.completeLesson(widget.lesson.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(
          child: LoopingVideo(
            // the one clip bundled in the APK (local placeholder); a real
            // build streams each lesson's own video
            asset: 'assets/video/mic_snooze_reminder.mp4',
            muted: _muted,
            fallback: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [widget.program.colors.last, Colors.black],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter),
              ),
              child: const Icon(Icons.person, size: 260, color: Colors.white10),
            ),
          ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black87],
                  begin: Alignment.center,
                  end: Alignment.bottomCenter),
            ),
          ),
        ),
        SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              Expanded(
                  child: Text(widget.lesson.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
              const SizedBox(width: 48),
            ]),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(widget.lesson.caption, style: const TextStyle(fontSize: 18, height: 1.4)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: context.palette.cta.first, foregroundColor: context.palette.onCta),
                onPressed: () => setState(() => _muted = !_muted),
                icon: Icon(_muted ? Icons.volume_off : Icons.volume_up),
                label: Text(_muted ? 'Unmute' : 'Mute'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Card lesson: full-colour pages with an illustration and short text; the
/// chevron at the bottom advances, the last page completes the lesson.
class _CardsLesson extends StatefulWidget {
  final Lesson lesson;
  const _CardsLesson({required this.lesson});
  @override
  State<_CardsLesson> createState() => _CardsLessonState();
}

class _CardsLessonState extends State<_CardsLesson> {
  final _pager = PageController();
  int _i = 0;

  void _next() {
    if (_i == widget.lesson.cards.length - 1) {
      AppState.I.completeLesson(widget.lesson.id);
      Navigator.pop(context);
    } else {
      _pager.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.lesson.cards;
    final color = cards[_i].color;
    return Scaffold(
      backgroundColor: color,
      body: SafeArea(
        child: Column(children: [
          Row(children: [
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            Expanded(
                child: Text(widget.lesson.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
            const SizedBox(width: 48),
          ]),
          Expanded(
            child: PageView.builder(
              controller: _pager,
              scrollDirection: Axis.vertical,
              onPageChanged: (i) => setState(() => _i = i),
              itemCount: cards.length,
              itemBuilder: (c, i) => Padding(
                padding: const EdgeInsets.all(24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SizedBox(height: 40),
                  Center(child: Icon(cards[i].icon, size: 160, color: context.palette.textMuted)),
                  const SizedBox(height: 48),
                  _rich(cards[i].text),
                ]),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            color: Colors.black12,
            child: IconButton(
              icon: Icon(_i == cards.length - 1 ? Icons.check : Icons.keyboard_arrow_down, size: 30),
              onPressed: _next,
            ),
          ),
        ]),
      ),
    );
  }

  /// Minimal **bold** support for lesson copy.
  Widget _rich(String text) {
    final parts = text.split('**');
    return Text.rich(
      TextSpan(children: [
        for (var i = 0; i < parts.length; i++)
          TextSpan(text: parts[i], style: TextStyle(fontWeight: i.isOdd ? FontWeight.w700 : FontWeight.w400)),
      ]),
      style: const TextStyle(fontSize: 19, height: 1.45),
    );
  }
}
