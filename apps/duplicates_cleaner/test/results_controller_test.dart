import 'package:duplicates_cleaner/models/duplicate_item.dart';
import 'package:duplicates_cleaner/models/enums.dart';
import 'package:duplicates_cleaner/services/results_controller.dart';
import 'package:flutter_test/flutter_test.dart';

DuplicateGroup group(String name, int size, int count) => DuplicateGroup([
      for (var i = 0; i < count; i++)
        DuplicateItem(
          path: '/$i/$name',
          name: name,
          size: size,
          modified: DateTime(2024, 1, i + 1),
          isMainFile: i == 0,
        ),
    ]);

void main() {
  test('auto selection checks everything except the original', () {
    final c = ResultsController([group('a', 10, 3)], autoSelect: true);
    expect(c.selectedCount, 2);
    expect(c.groups.single.items.first.checked, isFalse);
  });

  test('free tier blocks more than 100 files per delete', () {
    final c = ResultsController([group('a', 10, 102)], autoSelect: true);
    expect(c.freeTierBlockReason(isPremium: false), isNotNull);
    expect(c.freeTierBlockReason(isPremium: true), isNull);
  });

  test('free tier blocks a selection totalling 500 MB or more', () {
    final c = ResultsController([group('big', 200 * 1048576, 4)], autoSelect: true);
    expect(c.selectedBytes, 600 * 1048576);
    expect(c.freeTierBlockReason(isPremium: false), contains('500 MB'));
    final small = ResultsController([group('ok', 100 * 1048576, 4)], autoSelect: true);
    expect(small.freeTierBlockReason(isPremium: false), isNull);
  });

  test('sorting orders groups by their original file', () {
    final c = ResultsController(
        [group('bb', 5, 2), group('a', 50, 2), group('ccc', 20, 2)],
        autoSelect: false);
    c.sort(SortField.size, ascending: false);
    expect(c.groups.map((g) => g.items.first.size), [50, 20, 5]);
    c.sort(SortField.nameLength, ascending: true);
    expect(c.groups.map((g) => g.items.first.name), ['a', 'bb', 'ccc']);
  });
}
