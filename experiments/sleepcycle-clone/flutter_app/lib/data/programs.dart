import 'package:flutter/material.dart';
import 'free_art.dart';

/// Programs: short guided courses. Two lesson formats, as in the original:
/// a video lesson (one clip + caption) and a stack of full-colour text cards
/// the user pages through. All content below is our own placeholder copy.
enum LessonKind { video, cards }

class LessonCard {
  final String text;
  final IconData icon;
  final Color color;
  const LessonCard(this.text, this.icon, this.color);
}

class Lesson {
  final String id;
  final String title;
  final LessonKind kind;
  final List<LessonCard> cards; // cards lessons
  final String caption; // video lessons
  const Lesson(this.id, this.title, this.kind, {this.cards = const [], this.caption = ''});
}

class Program {
  final String id;
  final String title;
  final String subtitle;
  final String intro;
  final List<Color> colors;
  final IconData icon;
  final List<Lesson> lessons;
  const Program(this.id, this.title, this.subtitle, this.intro, this.colors, this.icon, this.lessons);

  /// Cover photo (assets/free/images/covers), or null for the gradient.
  String? get image => programCovers[id];
}

const _plum = Color(0xFF6E3F63);
const _teal = Color(0xFF2C6F73);
const _slate = Color(0xFF3B4A7A);

List<LessonCard> _cards(List<String> texts, IconData icon) => [
      for (var i = 0; i < texts.length; i++)
        LessonCard(texts[i], icon, [_plum, _teal, _slate][i % 3]),
    ];

final programs = <Program>[
  Program(
    'coaching',
    'Sleep coaching',
    'Short talks from a sleep clinician for every stage of life.',
    'Practical advice on the sleep problems people ask about most, in a few minutes each.',
    const [Color(0xFF1B1F2B), Color(0xFF3A3F55)],
    Icons.record_voice_over,
    const [
      Lesson('c1', 'Little ones, longer nights', LessonKind.video,
          caption: 'Why young children wake at night, and a gradual routine that helps them settle.'),
      Lesson('c2', 'Teens and late bedtimes', LessonKind.video,
          caption: 'Body clocks shift later in the teenage years. Here is how to work with it.'),
      Lesson('c3', 'Resetting adult sleep', LessonKind.video,
          caption: 'Small, consistent changes that bring a drifting schedule back on track.'),
    ],
  ),
  Program(
    'stress',
    'Ease stress',
    'Simple physical exercises to help you fall asleep.',
    'Stress keeps the body alert. These lessons give you tools to switch it off before bed.',
    const [Color(0xFF2B6E86), Color(0xFF1C3A57)],
    Icons.spa,
    [
      Lesson('s1', 'Stress and sleep', LessonKind.cards,
          cards: _cards([
            'A stressful day leaves your body on alert, which makes it harder to drift off.',
            'The good news: you can **teach your body to stand down**, and it gets easier with practice.',
            'Over the next lessons you will learn three quick techniques to try tonight.',
          ], Icons.psychology)),
      Lesson('s2', 'Breathe, scan, release', LessonKind.cards,
          cards: _cards([
            'Lie down and breathe out a little longer than you breathe in.',
            'Move your attention from your toes to your head, relaxing each part as you go.',
          ], Icons.self_improvement)),
      Lesson('s3', 'Breathing I', LessonKind.cards,
          cards: _cards(['In for four, out for six. Repeat ten times.'], Icons.air)),
      Lesson('s4', 'Breathing II', LessonKind.cards,
          cards: _cards(['Hum softly on each out-breath to slow it even more.'], Icons.air)),
    ],
  ),
  Program(
    'daytime',
    'Daytime habits',
    'What you do while awake shapes how you sleep.',
    'Light, movement, caffeine and naps: the daytime levers that matter most.',
    const [Color(0xFF7A4A6B), Color(0xFF3E2442)],
    Icons.wb_sunny,
    [
      Lesson('d1', 'Morning light', LessonKind.cards,
          cards: _cards(['Get outside within an hour of waking. Daylight anchors your body clock.'], Icons.wb_sunny)),
      Lesson('d2', 'Caffeine timing', LessonKind.cards,
          cards: _cards(['Caffeine lingers for hours. Try a 2 p.m. cut-off for a week.'], Icons.local_cafe)),
    ],
  ),
  Program(
    'mind',
    'Quiet the mind',
    'Simple thinking exercises to help you fall asleep.',
    'When your thoughts race at bedtime, these exercises give them somewhere else to go.',
    const [Color(0xFFB0662F), Color(0xFF5A2E16)],
    Icons.psychology_alt,
    [
      Lesson('m1', 'The worry list', LessonKind.cards,
          cards: _cards(['Write tomorrow\'s worries down an hour before bed, then close the notebook.'], Icons.edit_note)),
      Lesson('m2', 'Counting backwards', LessonKind.cards,
          cards: _cards(['Count down from 300 in threes. It is boring on purpose.'], Icons.numbers)),
    ],
  ),
  Program(
    'bedroom',
    'Better bedroom',
    'Small changes that make your bedroom easier to sleep in.',
    'Temperature, light and noise: tune your room for sleep.',
    const [Color(0xFF2F7A63), Color(0xFF173D33)],
    Icons.bed,
    [
      Lesson('b1', 'Cool and dark', LessonKind.cards,
          cards: _cards(['Aim for a cool room and block stray light, even small LEDs.'], Icons.thermostat)),
    ],
  ),
  Program(
    'screens',
    'Screens at night',
    'Phones and screens at bedtime, and how to use them well.',
    'Not all screen time is equal. Learn what actually affects your sleep.',
    const [Color(0xFF26415F), Color(0xFF111E30)],
    Icons.phone_iphone,
    [
      Lesson('t1', 'Wind-down mode', LessonKind.cards,
          cards: _cards(['Pick calm, familiar content in the last half hour and dim the screen.'], Icons.nights_stay)),
    ],
  ),
  Program(
    'parents',
    'Sleep for new parents',
    'Looking after your own sleep while you care for a baby or toddler.',
    'Broken nights are part of parenting. These lessons help you recover where you can.',
    const [Color(0xFF2E8A86), Color(0xFF14403E)],
    Icons.child_friendly,
    [
      Lesson('p1', 'Take turns', LessonKind.cards,
          cards: _cards(['If you can, split the night into shifts so each adult gets one long block of sleep.'], Icons.swap_horiz)),
    ],
  ),
];
