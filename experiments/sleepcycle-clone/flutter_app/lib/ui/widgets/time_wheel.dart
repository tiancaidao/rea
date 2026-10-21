import 'package:flutter/material.dart';

/// Hour : minute AM/PM picker drawn as three scroll wheels with a framed
/// selection band — the alarm input used on the Sleep tab and in the
/// "Change alarm" sheet. Minutes move in 5-minute steps.
class TimeWheel extends StatefulWidget {
  final int hour; // 0..23
  final int minute;
  final void Function(int hour, int minute) onChanged;
  const TimeWheel({super.key, required this.hour, required this.minute, required this.onChanged});
  @override
  State<TimeWheel> createState() => _TimeWheelState();
}

class _TimeWheelState extends State<TimeWheel> {
  static const _item = 64.0;
  late int _h12 = widget.hour % 12 == 0 ? 12 : widget.hour % 12;
  late int _min = (widget.minute ~/ 5) * 5;
  late bool _pm = widget.hour >= 12;

  late final _hc = FixedExtentScrollController(initialItem: _h12 - 1);
  late final _mc = FixedExtentScrollController(initialItem: _min ~/ 5);
  late final _pc = FixedExtentScrollController(initialItem: _pm ? 1 : 0);

  void _emit() {
    final h = (_h12 % 12) + (_pm ? 12 : 0);
    widget.onChanged(h, _min);
  }

  @override
  void dispose() {
    _hc.dispose();
    _mc.dispose();
    _pc.dispose();
    super.dispose();
  }

  Widget _wheel(FixedExtentScrollController c, int count, String Function(int) label,
      ValueChanged<int> onSel, {bool loop = true, double width = 70}) {
    return SizedBox(
      width: width,
      child: ListWheelScrollView.useDelegate(
        controller: c,
        itemExtent: _item,
        diameterRatio: 1.6,
        perspective: 0.004,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: onSel,
        childDelegate: loop
            ? ListWheelChildLoopingListDelegate(
                children: [for (var i = 0; i < count; i++) _text(label(i))])
            : ListWheelChildListDelegate(
                children: [for (var i = 0; i < count; i++) _text(label(i))]),
      ),
    );
  }

  Widget _text(String s) => Center(
        child: Text(s,
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w400, color: Colors.white)),
      );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _item * 3,
      child: Stack(alignment: Alignment.center, children: [
        Container(
          height: _item,
          width: 250,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24),
            color: Colors.black12,
          ),
        ),
        ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.white38, Colors.white, Colors.white38, Colors.transparent],
            stops: [0, 0.22, 0.5, 0.78, 1],
          ).createShader(r),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _wheel(_hc, 12, (i) => '${i + 1}', (i) {
              _h12 = i % 12 + 1;
              _emit();
            }),
            const Text(':', style: TextStyle(fontSize: 34)),
            _wheel(_mc, 12, (i) => (i * 5).toString().padLeft(2, '0'), (i) {
              _min = (i % 12) * 5;
              _emit();
            }),
            _wheel(_pc, 2, (i) => i == 0 ? 'AM' : 'PM', (i) {
              _pm = i == 1;
              _emit();
            }, loop: false, width: 80),
          ]),
        ),
      ]),
    );
  }
}
