import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/constants.dart';
import '../models/duplicate_item.dart';
import '../models/enums.dart';
import 'content_fingerprint.dart';
import 'image_hash.dart';

/// Everything a scan needs. Plain data so it can cross an isolate boundary.
class ScanRequest {
  const ScanRequest({
    required this.roots,
    required this.extensions,
    required this.algorithm,
    required this.sizeExclusion,
  });

  final List<String> roots;
  final Set<String> extensions;
  final ScanAlgorithm algorithm;
  final FileSizeExclusion sizeExclusion;
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

/// Pure-Dart port of the original `FilesScanner` pipeline. It walks the roots,
/// filters by extension and size, then groups files by the chosen algorithm.
class ScanEngine {
  ScanEngine(this.request, {this.onProgress, this.isCancelled});

  final ScanRequest request;
  final ProgressCallback? onProgress;
  final bool Function()? isCancelled;

  bool get _cancelled => isCancelled?.call() ?? false;

  Future<List<DuplicateGroup>> run() async {
    final files = await enumerate();
    if (_cancelled) return const [];
    final groups = switch (request.algorithm) {
      ScanAlgorithm.sameContent => await _bySameContent(files),
      ScanAlgorithm.sameName => _groupBy(files, (f) => f.name.toLowerCase()),
      ScanAlgorithm.sameNameAndSize =>
        _groupBy(files, (f) => '${f.name.toLowerCase()}|${f.size}'),
      ScanAlgorithm.sameSize => _groupBy(files, (f) => '${f.size}'),
      ScanAlgorithm.sameAppearance => await _bySameAppearance(files),
    };
    for (final g in groups) {
      g.items.first.isMainFile = true;
    }
    return groups;
  }

  /// Iterative walk, like `FileUtility.FetchStorageFilesIterative`.
  Future<List<DuplicateItem>> enumerate() async {
    final result = <DuplicateItem>[];
    final seen = <String>{};
    final stack = <Directory>[for (final r in request.roots) Directory(r)];
    var visited = 0;
    while (stack.isNotEmpty && !_cancelled) {
      final dir = stack.removeLast();
      List<FileSystemEntity> entries;
      try {
        entries = await dir.list(followLinks: false).toList();
      } on FileSystemException {
        continue;
      }
      for (final e in entries) {
        final name = p.basename(e.path);
        if (name.startsWith('.')) continue;
        if (e is Directory) {
          if (_skippedDirs.any((s) => e.path.endsWith(s))) continue;
          stack.add(e);
        } else if (e is File) {
          final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
          if (!request.extensions.contains(ext)) continue;
          FileStat stat;
          try {
            stat = await e.stat();
          } on FileSystemException {
            continue;
          }
          if (!request.sizeExclusion.allows(stat.size)) continue;
          if (!seen.add(e.absolute.path)) continue;
          result.add(DuplicateItem(
            path: e.path,
            name: name,
            size: stat.size,
            modified: stat.modified,
          ));
        }
      }
      if (++visited % 25 == 0) {
        onProgress?.call(ScanProgress(ScanPhase.enumerating, 0, dir.path));
      }
    }
    return result;
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

  Future<List<DuplicateGroup>> _bySameContent(List<DuplicateItem> files) async {
    // Stage 1: only files sharing a size can be identical.
    final bySize = _groupBy(files, (f) => '${f.size}');
    final candidates = bySize.expand((g) => g.items).toList();
    // Stage 2: the original app's partial XXH32 fingerprint.
    final byPrint = <String, List<DuplicateItem>>{};
    for (var i = 0; i < candidates.length && !_cancelled; i++) {
      final f = candidates[i];
      _report(ScanPhase.analyzing, i, candidates.length, f.path);
      try {
        final key = await partialContentFingerprint(File(f.path));
        byPrint.putIfAbsent(key, () => []).add(f);
      } on FileSystemException {
        continue;
      }
    }
    // Stage 3: confirm byte-for-byte so a fingerprint collision never leads
    // to deleting a file that only looks the same at its edges.
    final groups = <DuplicateGroup>[];
    var done = 0;
    for (final bucket in byPrint.values.where((b) => b.length > 1)) {
      if (_cancelled) break;
      var remaining = [...bucket];
      while (remaining.length > 1) {
        final head = remaining.first;
        final same = [head];
        final rest = <DuplicateItem>[];
        for (final other in remaining.skip(1)) {
          _report(ScanPhase.comparing, done, byPrint.length, other.path);
          final equal =
              await filesHaveSameBytes(File(head.path), File(other.path))
                  .catchError((_) => false);
          (equal ? same : rest).add(other);
        }
        if (same.length > 1) groups.add(DuplicateGroup(same));
        remaining = rest;
      }
      done++;
    }
    return groups;
  }

  Future<List<DuplicateGroup>> _bySameAppearance(List<DuplicateItem> files) async {
    final images = files
        .where((f) => AppConstants.decodableImageExtensions
            .contains(p.extension(f.name).replaceFirst('.', '').toLowerCase()))
        .toList();
    final hashed = <(DuplicateItem, int)>[];
    for (var i = 0; i < images.length && !_cancelled; i++) {
      _report(ScanPhase.analyzing, i, images.length, images[i].path);
      try {
        final h = await perceptualHash(File(images[i].path));
        if (h != null) hashed.add((images[i], h));
      } catch (_) {
        continue;
      }
    }
    // Connected components over "close enough" pairs, as the original does
    // with its breadth-first grouping in `GroupByPhaseOne`.
    final parent = List<int>.generate(hashed.length, (i) => i);
    int find(int i) => parent[i] == i ? i : parent[i] = find(parent[i]);
    for (var i = 0; i < hashed.length && !_cancelled; i++) {
      _report(ScanPhase.comparing, i, hashed.length, hashed[i].$1.path);
      for (var j = i + 1; j < hashed.length; j++) {
        if (hammingDistance(hashed[i].$2, hashed[j].$2) <=
            AppConstants.similarImageMaxHammingDistance) {
          parent[find(j)] = find(i);
        }
      }
    }
    final components = <int, List<DuplicateItem>>{};
    for (var i = 0; i < hashed.length; i++) {
      components.putIfAbsent(find(i), () => []).add(hashed[i].$1);
    }
    return [
      for (final c in components.values)
        if (c.length > 1) DuplicateGroup(c),
    ];
  }

  void _report(ScanPhase phase, int index, int total, String path) {
    if (onProgress == null || total == 0) return;
    if (index % 5 != 0 && index != total - 1) return;
    onProgress!(ScanProgress(phase, ((index + 1) * 100 ~/ total), path));
  }
}
