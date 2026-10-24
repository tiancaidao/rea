/// A file inside a duplicate group (`DCAndroid.Data.Models.DuplicateItemModel`).
class DuplicateItem {
  DuplicateItem({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
    this.assetId,
    this.isMainFile = false,
    this.checked = false,
  });

  final String path;
  final String name;
  final int size;
  final DateTime modified;

  /// The Photos library asset this file was exported from (iOS), or null for
  /// a file on disk. Such items are shown and deleted through PhotoKit.
  final String? assetId;

  /// The first file of each group is treated as the original and is never
  /// auto-selected for deletion.
  bool isMainFile;
  bool checked;

  Map<String, Object?> toJson() => {
    'path': path,
    'name': name,
    'size': size,
    'modified': modified.millisecondsSinceEpoch,
    'assetId': assetId,
    'isMainFile': isMainFile,
    'checked': checked,
  };

  factory DuplicateItem.fromJson(Map<String, Object?> j) => DuplicateItem(
    path: j['path']! as String,
    name: j['name']! as String,
    size: j['size']! as int,
    modified: DateTime.fromMillisecondsSinceEpoch(j['modified']! as int),
    assetId: j['assetId'] as String?,
    isMainFile: j['isMainFile'] as bool? ?? false,
    checked: j['checked'] as bool? ?? false,
  );
}

class DuplicateGroup {
  DuplicateGroup(this.items);

  final List<DuplicateItem> items;

  int get wastedBytes =>
      items.where((i) => !i.isMainFile).fold(0, (sum, i) => sum + i.size);
}
