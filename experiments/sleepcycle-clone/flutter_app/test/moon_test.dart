import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/ui/tracking_screen.dart';

void main() {
  test('moon phase frame follows the real lunar cycle', () {
    // new moon 11 Jan 2024 11:57 UTC, full moon 25 Jan 2024 17:54 UTC
    expect(moonPhaseIndex(DateTime.utc(2024, 1, 11, 12)), anyOf(0, 29));
    expect(moonPhaseIndex(DateTime.utc(2024, 1, 25, 18)), inInclusiveRange(14, 15));
    // first quarter 18 Jan 2024
    expect(moonPhaseIndex(DateTime.utc(2024, 1, 18, 3)), inInclusiveRange(7, 8));
  });
}
