import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../models/duplicate_item.dart';
import '../models/enums.dart';

class DeletionResult {
  const DeletionResult(
    this.deleted,
    this.freedBytes,
    this.failed, {
    this.deletedPaths = const [],
  });
  final int deleted;
  final int freedBytes;
  final List<String> failed;

  /// Files removed from disk (not Photos assets), so the media index can be
  /// told about them as the original does with `MediaScannerConnection`.
  final List<String> deletedPaths;
}

/// Holds scan results and the selection / sort / delete behaviour of the
/// original `ScannerPageActivity`.
class ResultsController extends ChangeNotifier {
  ResultsController(this.groups, {required this.autoSelect}) {
    _applySelection(
      autoSelect ? SelectFilter.selectDuplicates : SelectFilter.unselectAll,
    );
  }

  final List<DuplicateGroup> groups;

  /// The Auto Select Duplicates setting, re-applied after every sort.
  final bool autoSelect;
  SortField? sortField;
  bool ascending = false;

  Iterable<DuplicateItem> get _all => groups.expand((g) => g.items);
  Iterable<DuplicateItem> get selected => _all.where((i) => i.checked);
  int get selectedCount => selected.length;
  int get selectedBytes => selected.fold(0, (s, i) => s + i.size);
  int get duplicateCount => _all.where((i) => !i.isMainFile).length;
  int get wastedBytes => groups.fold(0, (s, g) => s + g.wastedBytes);

  void toggle(DuplicateItem item) {
    item.checked = !item.checked;
    notifyListeners();
  }

  void applySelection(SelectFilter f) {
    _applySelection(f);
    notifyListeners();
  }

  void _applySelection(SelectFilter f) {
    for (final i in _all) {
      i.checked = switch (f) {
        SelectFilter.selectAll => true,
        SelectFilter.unselectAll => false,
        SelectFilter.selectDuplicates => !i.isMainFile,
      };
    }
  }

  /// `GetSortedGroupsBy*` followed by `AggregateResults`: every file is
  /// ordered by [field] (a stable sort), the groups are rebuilt in that order,
  /// and the first file of each group becomes the one that is kept. So the
  /// sort also picks the original, e.g. Date created - Old keeps the oldest
  /// copy. Like the original, the selection is then reset to the auto-select
  /// setting. "Path" orders by path length, as the original does.
  void sort(SortField field, {required bool ascending}) {
    sortField = field;
    this.ascending = ascending;
    int compare(DuplicateItem x, DuplicateItem y) => switch (field) {
      SortField.size => x.size.compareTo(y.size),
      SortField.nameLength => x.name.length.compareTo(y.name.length),
      SortField.nameAlphabetical => _compareNames(x.name, y.name),
      SortField.path => x.path.length.compareTo(y.path.length),
      SortField.dateCreated => x.modified.compareTo(y.modified),
    };

    // Each group's position is that of its first file in the sorted list.
    final order = <DuplicateItem, int>{};
    final all = [
      for (final (g, group) in groups.indexed)
        for (final (i, item) in group.items.indexed) (g, i, item),
    ];
    all.sort((a, b) {
      final c = ascending ? compare(a.$3, b.$3) : compare(b.$3, a.$3);
      if (c != 0) return c;
      return a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2;
    });
    for (final (i, e) in all.indexed) {
      order[e.$3] = i;
    }
    for (final g in groups) {
      g.items.sort((a, b) => order[a]! - order[b]!);
      for (final (i, item) in g.items.indexed) {
        item.isMainFile = i == 0;
      }
    }
    groups.sort((a, b) => order[a.items.first]! - order[b.items.first]!);
    _applySelection(
      autoSelect ? SelectFilter.selectDuplicates : SelectFilter.unselectAll,
    );
    notifyListeners();
  }

  /// Close to .NET's culture-aware default string order: case only breaks
  /// ties.
  static int _compareNames(String a, String b) {
    final c = a.toLowerCase().compareTo(b.toLowerCase());
    return c != 0 ? c : a.compareTo(b);
  }

  /// Returns a reason the free tier blocks this deletion, or null.
  String? freeTierBlockReason({required bool isPremium}) {
    if (isPremium) return null;
    if (selectedCount > AppConstants.freeDeleteMaxFilesPerOperation) {
      return 'In the free version you can delete up to '
          '${AppConstants.freeDeleteMaxFilesPerOperation} files per operation. '
          'Upgrade to remove this limit.';
    }
    if (selectedBytes >= AppConstants.freeFileSizeLimit) {
      return 'To delete 500 MB or more at a time you need the premium version.';
    }
    return null;
  }

  /// [fallback] is tried when a plain delete is refused, e.g. on an SD card.
  /// Photos library items are removed in one batch by [deleteAssets], which
  /// returns the ids it deleted. [onProgress] gets the percentage done, like
  /// the original's "Deleting files..." indicator.
  Future<DeletionResult> deleteSelected({
    Future<bool> Function(String path)? fallback,
    Future<List<String>> Function(List<String> ids)? deleteAssets,
    void Function(int percent)? onProgress,
  }) async {
    var deleted = 0, freed = 0;
    final failed = <String>[];
    final deletedPaths = <String>[];
    void removed(DuplicateItem item) {
      deleted++;
      freed += item.size;
      for (final g in groups) {
        g.items.remove(item);
      }
    }

    final assets = selected.where((i) => i.assetId != null).toList();
    if (assets.isNotEmpty) {
      var gone = const <String>{};
      if (deleteAssets != null) {
        try {
          gone = (await deleteAssets([for (final i in assets) i.assetId!]))
              .toSet();
        } catch (_) {}
      }
      for (final item in assets) {
        if (gone.contains(item.assetId)) {
          removed(item);
          try {
            await File(item.path).delete();
          } on FileSystemException {
            // Only the exported copy; the asset itself is already gone.
          }
        } else {
          failed.add(item.name);
        }
      }
    }

    final files = selected.where((i) => i.assetId == null).toList();
    for (final (n, item) in files.indexed) {
      onProgress?.call(n * 100 ~/ files.length);
      try {
        try {
          await File(item.path).delete();
        } on FileSystemException {
          if (fallback == null || !await fallback(item.path)) rethrow;
        }
        removed(item);
        deletedPaths.add(item.path);
      } on FileSystemException {
        failed.add(item.path);
      }
    }
    onProgress?.call(100);
    groups.removeWhere((g) => g.items.length < 2);
    for (final g in groups) {
      if (!g.items.any((i) => i.isMainFile)) g.items.first.isMainFile = true;
    }
    notifyListeners();
    return DeletionResult(deleted, freed, failed, deletedPaths: deletedPaths);
  }
}
