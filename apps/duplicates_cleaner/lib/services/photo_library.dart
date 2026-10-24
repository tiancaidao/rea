import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/duplicate_item.dart';
import '../models/enums.dart';
import 'scan_engine.dart';

/// The iPhone's internal storage for photos and videos.
///
/// iOS keeps the camera roll in the Photos library, not in files the app can
/// walk, so a scan of internal storage reads it through PhotoKit. Each asset
/// that could have a duplicate is exported to the cache and handed to
/// [ScanEngine] as a plain file, and deletion goes back through PhotoKit so
/// the asset moves to Recently Deleted.
class PhotoLibraryService {
  final _thumbnails = <String, Future<Uint8List?>>{};

  /// Photos and Videos are the only scan types the library holds.
  static bool covers(ScanType type) =>
      Platform.isIOS && (type == ScanType.image || type == ScanType.video);

  /// True with full or limited access.
  Future<bool> ensureAccess() async =>
      (await PhotoManager.requestPermissionExtend()).hasAccess;

  Future<void> openAccessSettings() => PhotoManager.openSetting();

  /// Exports the assets [algorithm] could match and returns them as items
  /// whose [DuplicateItem.assetId] points back at the asset.
  ///
  /// Byte-identical copies always share pixel size (and duration), so only
  /// assets that share it with another asset are exported, which keeps a
  /// large library from being copied in full. The appearance scan compares
  /// every image, so it exports small thumbnails instead of originals.
  Future<List<DuplicateItem>> collect(
    ScanType type,
    ScanAlgorithm algorithm,
    FileSizeExclusion sizeExclusion, {
    ProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    final appearance = algorithm == ScanAlgorithm.sameAppearance;
    final assets = await _assets(
      type == ScanType.video ? RequestType.video : RequestType.image,
    );
    await PhotoManager.clearFileCache();

    final candidates = appearance
        ? assets
        : [
            for (final g in _groupByShape(assets).values)
              if (g.length > 1) ...g,
          ];
    final thumbDir = appearance ? await _thumbnailDir() : null;

    final items = <DuplicateItem>[];
    for (var i = 0; i < candidates.length; i++) {
      if (isCancelled?.call() ?? false) break;
      final asset = candidates[i];
      if (i % 5 == 0 || i == candidates.length - 1) {
        onProgress?.call(
          ScanProgress(
            ScanPhase.analyzing,
            (i + 1) * 100 ~/ candidates.length,
            'Photos library: ${i + 1} of ${candidates.length}',
          ),
        );
      }
      try {
        final item = thumbDir != null
            ? await _thumbnailItem(asset, thumbDir)
            : await _originalItem(asset, sizeExclusion);
        if (item != null) items.add(item);
      } catch (_) {
        // An asset that can't be exported (e.g. offline iCloud) is skipped.
        continue;
      }
    }
    return items;
  }

  /// The appearance scan sees thumbnails, so its items carry the thumbnail's
  /// size; this replaces it with the original's for the matched items only.
  ///
  /// Reading an original can be slow (it may come from iCloud), so a few are
  /// read at a time and [onProgress] reports how many are done.
  Future<List<DuplicateGroup>> withOriginalSizes(
    List<DuplicateGroup> groups, {
    ProgressCallback? onProgress,
  }) async {
    final items = [for (final g in groups) ...g.items];
    final sizes = <DuplicateItem, int>{};
    var next = 0, done = 0;
    Future<void> worker() async {
      while (next < items.length) {
        final i = items[next++];
        try {
          final asset = i.assetId == null
              ? null
              : await AssetEntity.fromId(i.assetId!);
          final file = await asset?.originFile;
          if (file != null) sizes[i] = await file.length();
        } catch (_) {
          // Keep the thumbnail's size if the original can't be read.
        }
        done++;
        onProgress?.call(
          ScanProgress(
            ScanPhase.comparing,
            done * 100 ~/ items.length,
            'Reading photo sizes: $done of ${items.length}',
          ),
        );
      }
    }

    await Future.wait([for (var w = 0; w < 6; w++) worker()]);
    return [
      for (final g in groups)
        DuplicateGroup([
          for (final i in g.items)
            sizes[i] == null
                ? i
                : DuplicateItem(
                    path: i.path,
                    name: i.name,
                    size: sizes[i]!,
                    modified: i.modified,
                    assetId: i.assetId,
                    isMainFile: i.isMainFile,
                    checked: i.checked,
                  ),
        ]),
    ];
  }

  /// Moves the assets to Recently Deleted. iOS asks the user to confirm once
  /// for the whole batch; returns the ids that were deleted.
  Future<List<String>> delete(List<String> ids) =>
      PhotoManager.editor.deleteWithIds(ids);

  /// The full-size original of an asset, for viewing. The appearance scan
  /// only exports thumbnails, so its items' paths are not the photo itself.
  Future<File?> original(String assetId) async =>
      (await AssetEntity.fromId(assetId))?.originFile;

  Future<Uint8List?> thumbnail(String assetId) =>
      _thumbnails.putIfAbsent(assetId, () async {
        final asset = await AssetEntity.fromId(assetId);
        return asset?.thumbnailDataWithSize(const ThumbnailSize.square(120));
      });

  Future<List<AssetEntity>> _assets(RequestType type) async {
    final paths = await PhotoManager.getAssetPathList(
      type: type,
      onlyAll: true,
    );
    if (paths.isEmpty) return const [];
    final all = paths.first;
    final count = await all.assetCountAsync;
    final assets = <AssetEntity>[];
    const page = 500;
    for (var start = 0; start < count; start += page) {
      assets.addAll(
        await all.getAssetListRange(
          start: start,
          end: start + page > count ? count : start + page,
        ),
      );
    }
    return assets;
  }

  Map<String, List<AssetEntity>> _groupByShape(List<AssetEntity> assets) {
    final map = <String, List<AssetEntity>>{};
    for (final a in assets) {
      map
          .putIfAbsent(
            '${a.type.index}:${a.width}x${a.height}:${a.duration}',
            () => [],
          )
          .add(a);
    }
    return map;
  }

  Future<DuplicateItem?> _originalItem(
    AssetEntity asset,
    FileSizeExclusion sizeExclusion,
  ) async {
    final file = await asset.originFile;
    if (file == null) return null;
    final size = await file.length();
    if (!sizeExclusion.allows(size)) return null;
    return DuplicateItem(
      path: file.path,
      name: await _name(asset, file.path),
      size: size,
      modified: asset.modifiedDateTime,
      assetId: asset.id,
    );
  }

  Future<DuplicateItem?> _thumbnailItem(
    AssetEntity asset,
    Directory dir,
  ) async {
    final bytes = await asset.thumbnailDataWithSize(
      const ThumbnailSize.square(256),
      quality: 90,
    );
    if (bytes == null) return null;
    final file = File(p.join(dir.path, '${asset.id.replaceAll('/', '_')}.jpg'));
    await file.writeAsBytes(bytes);
    return DuplicateItem(
      path: file.path,
      name: await _name(asset, file.path),
      size: bytes.length,
      modified: asset.modifiedDateTime,
      assetId: asset.id,
    );
  }

  Future<String> _name(AssetEntity asset, String fallback) async {
    final title = await asset.titleAsync;
    return title.isEmpty ? p.basename(fallback) : title;
  }

  Future<Directory> _thumbnailDir() async {
    final dir = Directory(
      p.join((await getTemporaryDirectory()).path, 'photo_thumbnails'),
    );
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    return dir..createSync(recursive: true);
  }
}
