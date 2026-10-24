import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/constants.dart';
import '../models/duplicate_item.dart';
import '../models/enums.dart';
import 'content_fingerprint.dart';
import 'image_similarity.dart';

/// Everything a scan needs. Plain data so it can cross an isolate boundary.
class ScanRequest {
  const ScanRequest({
    required this.roots,
    required this.extensions,
    required this.algorithm,
    required this.sizeExclusion,
    this.verifyContent = true,
    this.extraFiles = const [],
    this.listedPaths,
  });

  final List<String> roots;
  final Set<String> extensions;
  final ScanAlgorithm algorithm;
  final FileSizeExclusion sizeExclusion;

  /// Confirm "same content" groups byte-for-byte. The original trusts its
  /// sampled hash alone; turning this off reproduces that exactly.
  final bool verifyContent;

  /// Files found outside [roots], such as assets exported from the iOS
  /// Photos library, scanned together with the walked files.
  final List<DuplicateItem> extraFiles;

  /// Files to scan instead of walking [roots]. An image scan of Android's
  /// internal storage reads them from the MediaStore index, as the original's
  /// `FetchInternalStorageImageFilesIndexBased` does; these paths skip the
  /// extension filter, since the index only lists images.
  final List<String>? listedPaths;
}

enum ScanPhase { enumerating, analyzing, comparing }

class ScanProgress {
  const ScanProgress(this.phase, this.percent, this.path);
  final ScanPhase phase;
  final int percent;
  final String path;
}

typedef ProgressCallback = void Function(ScanProgress progress);

/// Directories that are unreadable or never contain user files.
const _skippedDirs = {'Android/data', 'Android/obb'};

/// `FileCheck.GetXhash` returns 0 for files shorter than this, and the
/// original never stores a file whose hash is 0, so the same content and same
/// size scans skip them.
const _minHashableSize = 2048;

/// Pure-Dart port of the original `FilesScanner` pipeline. It walks the roots,
/// filters by extension and size, then groups files by the chosen algorithm.
class ScanEngine {
  ScanEngine(this.request, {this.onProgress, this.isCancelled});

  final ScanRequest request;
  final ProgressCallback? onProgress;
  final bool Function()? isCancelled;

  bool get _cancelled => isCancelled?.call() ?? false;

  Future<List<DuplicateGroup>> run() async {
    var files = [...await enumerate(), ...request.extraFiles];
    if (_cancelled) return const [];
    // Same size goes through the original's content pipeline too
    // (`ProcessFiles`), so it shares the hash's size floor.
    if (request.algorithm == ScanAlgorithm.sameContent ||
        request.algorithm == ScanAlgorithm.sameSize) {
      files = [
        for (final f in files)
          if (f.size >= _minHashableSize) f,
      ];
    }
    final groups = switch (request.algorithm) {
      ScanAlgorithm.sameContent => await _bySameContent(files),
      ScanAlgorithm.sameName => _bySameName(files),
      // `NSHash`: lower-cased name followed by the size, with no separator.
      ScanAlgorithm.sameNameAndSize => _groupBy(
        files,
        (f) => '${f.name.toLowerCase()}${f.size}',
      ),
      ScanAlgorithm.sameSize => _groupBy(files, (f) => '${f.size}'),
      ScanAlgorithm.sameAppearance => await _bySameAppearance(files),
    };
    for (final g in groups) {
      g.items.first.isMainFile = true;
    }
    return groups;
  }

  /// Breadth-first walk, like `FileUtility.FetchStorageFilesIterative`
  /// (a queue, hidden files included), so the first copy found, which is kept,
  /// is the one nearest the root.
  Future<List<DuplicateItem>> enumerate() async {
    final result = <DuplicateItem>[];
    final seen = <String>{};
    final listed = request.listedPaths;
    if (listed != null) {
      for (final path in listed) {
        if (_cancelled) break;
        await _add(File(path), result, seen, filterExtension: false);
      }
      return result;
    }
    final queue = Queue<Directory>.of([
      for (final r in request.roots) Directory(r),
    ]);
    var visited = 0;
    while (queue.isNotEmpty && !_cancelled) {
      final dir = queue.removeFirst();
      List<FileSystemEntity> entries;
      try {
        entries = await dir.list(followLinks: false).toList();
      } on FileSystemException {
        continue;
      }
      // Files first, then subfolders, as the original enumerates them.
      final subdirs = <Directory>[];
      for (final e in entries) {
        if (e is Directory) {
          if (_skippedDirs.any((s) => e.path.endsWith(s))) continue;
          subdirs.add(e);
        } else if (e is File) {
          await _add(e, result, seen);
        }
      }
      queue.addAll(subdirs);
      if (++visited % 25 == 0) {
        onProgress?.call(ScanProgress(ScanPhase.enumerating, 0, dir.path));
      }
    }
    return result;
  }

  Future<void> _add(
    File file,
    List<DuplicateItem> result,
    Set<String> seen, {
    bool filterExtension = true,
  }) async {
    final name = p.basename(file.path);
    if (filterExtension) {
      final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
      if (!request.extensions.contains(ext)) return;
    }
    FileStat stat;
    try {
      stat = await file.stat();
    } on FileSystemException {
      return;
    }
    if (stat.type != FileSystemEntityType.file) return;
    if (!request.sizeExclusion.allows(stat.size)) return;
    if (!seen.add(file.absolute.path)) return;
    result.add(
      DuplicateItem(
        path: file.path,
        name: name,
        size: stat.size,
        modified: stat.modified,
      ),
    );
  }

  List<DuplicateGroup> _groupBy(
    List<DuplicateItem> files,
    String Function(DuplicateItem) key,
  ) {
    final map = <String, List<DuplicateItem>>{};
    for (final f in files) {
      map.putIfAbsent(key(f), () => []).add(f);
    }
    return [
      for (final v in map.values)
        if (v.length > 1) DuplicateGroup(v),
    ];
  }

  /// `ProcessFileByName`: candidates are found by lower-cased name, but the
  /// stored rows are grouped by the name as written, so "IMG.jpg" and
  /// "img.jpg" end up in separate groups.
  List<DuplicateGroup> _bySameName(List<DuplicateItem> files) {
    final candidates = _groupBy(
      files,
      (f) => f.name.toLowerCase(),
    ).expand((g) => g.items).toList();
    return _groupBy(candidates, (f) => f.name);
  }

  /// `ProcessFileSizeAndContent`: files sharing a size are hashed with
  /// `FileCheck.GetXhash`, and the stored rows are grouped by that hash alone.
  Future<List<DuplicateGroup>> _bySameContent(List<DuplicateItem> files) async {
    final candidates = _groupBy(
      files,
      (f) => '${f.size}',
    ).expand((g) => g.items).toList();
    final byHash = <int, List<DuplicateItem>>{};
    for (var i = 0; i < candidates.length && !_cancelled; i++) {
      final f = candidates[i];
      _report(ScanPhase.analyzing, i, candidates.length, f.path);
      try {
        final hash = await originalContentHash(File(f.path));
        byHash.putIfAbsent(hash, () => []).add(f);
      } on FileSystemException {
        continue;
      }
    }
    final buckets = byHash.values.where((b) => b.length > 1).toList();
    if (!request.verifyContent) {
      return [for (final b in buckets) DuplicateGroup(b)];
    }

    // Optional extra step: split each bucket by real byte equality, so a hash
    // collision never offers a different file for deletion.
    final groups = <DuplicateGroup>[];
    for (var done = 0; done < buckets.length && !_cancelled; done++) {
      var remaining = [...buckets[done]];
      while (remaining.length > 1) {
        final head = remaining.first;
        final same = [head];
        final rest = <DuplicateItem>[];
        for (final other in remaining.skip(1)) {
          _report(ScanPhase.comparing, done, buckets.length, other.path);
          final equal =
              head.size == other.size &&
              await filesHaveSameBytes(
                File(head.path),
                File(other.path),
              ).catchError((_) => false);
          (equal ? same : rest).add(other);
        }
        if (same.length > 1) groups.add(DuplicateGroup(same));
        remaining = rest;
      }
    }
    return groups;
  }

  /// `ProcessSimilarImageFiles` + `GroupFinal`: nine features per image, then
  /// the two matching passes in [groupSimilarImages].
  Future<List<DuplicateGroup>> _bySameAppearance(
    List<DuplicateItem> files,
  ) async {
    final images = files
        .where(
          (f) => AppConstants.decodableImageExtensions.contains(
            p.extension(f.path).replaceFirst('.', '').toLowerCase(),
          ),
        )
        .toList();
    final analysed = <DuplicateItem>[];
    final features = <ImageFeatures>[];
    for (var i = 0; i < images.length && !_cancelled; i++) {
      _report(ScanPhase.analyzing, i, images.length, images[i].path);
      try {
        final f = await ImageFeatures.fromFile(File(images[i].path));
        if (f == null) continue;
        analysed.add(images[i]);
        features.add(f);
      } catch (_) {
        continue;
      }
    }
    if (_cancelled) return const [];
    _report(ScanPhase.comparing, 0, 1, '');
    return [
      for (final g in groupSimilarImages(features))
        DuplicateGroup([for (final i in g) analysed[i]]),
    ];
  }

  void _report(ScanPhase phase, int index, int total, String path) {
    if (onProgress == null || total == 0) return;
    if (index % 5 != 0 && index != total - 1) return;
    onProgress!(ScanProgress(phase, ((index + 1) * 100 ~/ total), path));
  }
}
