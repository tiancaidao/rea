import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../models/duplicate_item.dart';
import '../models/enums.dart';

class DeletionResult {
  const DeletionResult(this.deleted, this.freedBytes, this.failed);
  final int deleted;
  final int freedBytes;
  final List<String> failed;
}

/// Holds scan results and the selection / sort / delete behaviour of the
/// original `ScannerPageActivity`.
class ResultsController extends ChangeNotifier {
  ResultsController(this.groups, {required bool autoSelect}) {
    _applySelection(
      autoSelect ? SelectFilter.selectDuplicates : SelectFilter.unselectAll,
    );
  }

  final List<DuplicateGroup> groups;
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

  /// Sorts groups by their first (main) file, like `GetSortedGroupsBy*`.
  void sort(SortField field, {required bool ascending}) {
    sortField = field;
    this.ascending = ascending;
    int key(DuplicateGroup a, DuplicateGroup b) {
      final x = a.items.first, y = b.items.first;
      return switch (field) {
        SortField.size => x.size.compareTo(y.size),
        SortField.nameLength => x.name.length.compareTo(y.name.length),
        SortField.nameAlphabetical => x.name.toLowerCase().compareTo(
          y.name.toLowerCase(),
        ),
        SortField.path => x.path.toLowerCase().compareTo(y.path.toLowerCase()),
        SortField.dateCreated => x.modified.compareTo(y.modified),
      };
    }

    groups.sort((a, b) => ascending ? key(a, b) : key(b, a));
    notifyListeners();
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

  Future<DeletionResult> deleteSelected() async {
    var deleted = 0, freed = 0;
    final failed = <String>[];
    for (final item in selected.toList()) {
      try {
        await File(item.path).delete();
        deleted++;
        freed += item.size;
        for (final g in groups) {
          g.items.remove(item);
        }
      } on FileSystemException {
        failed.add(item.path);
      }
    }
    groups.removeWhere((g) => g.items.length < 2);
    for (final g in groups) {
      if (!g.items.any((i) => i.isMainFile)) g.items.first.isMainFile = true;
    }
    notifyListeners();
    return DeletionResult(deleted, freed, failed);
  }
}
