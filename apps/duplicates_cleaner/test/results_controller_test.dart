import 'dart:io';

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
    final c = ResultsController([
      group('big', 200 * 1048576, 4),
    ], autoSelect: true);
    expect(c.selectedBytes, 600 * 1048576);
    expect(c.freeTierBlockReason(isPremium: false), contains('500 MB'));
    final small = ResultsController([
      group('ok', 100 * 1048576, 4),
    ], autoSelect: true);
    expect(small.freeTierBlockReason(isPremium: false), isNull);
  });

  test('sorting orders groups by their original file', () {
    final c = ResultsController([
      group('bb', 5, 2),
      group('a', 50, 2),
      group('ccc', 20, 2),
    ], autoSelect: false);
    c.sort(SortField.size, ascending: false);
    expect(c.groups.map((g) => g.items.first.size), [50, 20, 5]);
    c.sort(SortField.nameLength, ascending: true);
    expect(c.groups.map((g) => g.items.first.name), ['a', 'bb', 'ccc']);
  });

  test('sorting reorders each group and keeps its first file', () {
    final c = ResultsController([group('a', 10, 3)], autoSelect: true);
    c.groups.single.items[1].checked = false;
    c.sort(SortField.dateCreated, ascending: false);
    final items = c.groups.single.items;
    // Newest first: Jan 3 is now the file that is kept.
    expect(items.map((i) => i.modified.day), [3, 2, 1]);
    expect(items.map((i) => i.isMainFile), [true, false, false]);
    // The selection is reset to the auto-select setting, as in the original.
    expect(items.map((i) => i.checked), [false, true, true]);
  });

  test('path sort orders by path length and ties keep scan order', () {
    DuplicateItem item(String path) =>
        DuplicateItem(path: path, name: 'x', size: 1, modified: DateTime(2024));
    final c = ResultsController([
      DuplicateGroup([item('/long/dir/x'), item('/b/x'), item('/a/x')]),
    ], autoSelect: false);
    c.sort(SortField.path, ascending: true);
    expect(c.groups.single.items.map((i) => i.path), [
      '/b/x',
      '/a/x',
      '/long/dir/x',
    ]);
    expect(c.selectedCount, 0);
  });

  test('deletion reports progress and the deleted paths', () async {
    final dir = Directory.systemTemp.createTempSync('dc_del');
    addTearDown(() => dir.deleteSync(recursive: true));
    DuplicateItem file(String n, {bool main = false}) {
      final f = File('${dir.path}/$n')..writeAsStringSync('x');
      return DuplicateItem(
        path: f.path,
        name: n,
        size: 1,
        modified: DateTime(2024),
        isMainFile: main,
      );
    }

    final c = ResultsController([
      DuplicateGroup([file('a', main: true), file('b'), file('c')]),
    ], autoSelect: true);
    final progress = <int>[];
    final outcome = await c.deleteSelected(onProgress: progress.add);
    expect(progress, [0, 50, 100]);
    expect(outcome.deletedPaths, ['${dir.path}/b', '${dir.path}/c']);
  });

  test('Photos items are deleted in one batch through the library', () async {
    DuplicateItem asset(String id, {bool main = false}) => DuplicateItem(
      path: '/cache/$id.heic',
      name: '$id.heic',
      size: 100,
      modified: DateTime(2024),
      assetId: id,
      isMainFile: main,
    );
    final c = ResultsController([
      DuplicateGroup([asset('a', main: true), asset('b'), asset('c')]),
    ], autoSelect: true);
    final batches = <List<String>>[];
    final outcome = await c.deleteSelected(
      deleteAssets: (ids) async {
        batches.add(ids);
        return ids.where((id) => id == 'b').toList();
      },
    );
    expect(batches, [
      ['b', 'c'],
    ]);
    expect(outcome.deleted, 1);
    expect(outcome.freedBytes, 100);
    expect(outcome.failed, ['c.heic']);
    expect(c.groups.single.items.map((i) => i.assetId), ['a', 'c']);
  });
}
