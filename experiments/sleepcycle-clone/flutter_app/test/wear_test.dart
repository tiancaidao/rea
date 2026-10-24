import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/device/wear.dart';

void main() {
  test('alarm type: Automatic vibrates only for nights started on the watch', () {
    expect(Wear.vibrateFor('Automatic', startedFromWatch: true), isTrue);
    expect(Wear.vibrateFor('Automatic', startedFromWatch: false), isFalse);
    expect(Wear.vibrateFor('Vibrate', startedFromWatch: false), isTrue);
    expect(Wear.vibrateFor('Melody', startedFromWatch: true), isFalse);
  });
}
