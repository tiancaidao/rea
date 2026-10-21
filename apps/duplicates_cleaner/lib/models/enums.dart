import '../core/constants.dart';

/// Home screen scan categories (`CommonPageData.ScanType`).
enum ScanType {
  image('Scan Images'),
  audio('Scan Audio'),
  video('Scan Videos'),
  doc('Scan Docs'),
  apk('Scan APK'),
  custom('Scan Custom Files');

  const ScanType(this.label);
  final String label;

  Set<String> extensions(Set<String> customExtensions) => switch (this) {
        ScanType.image => AppConstants.imageExtensions,
        ScanType.audio => AppConstants.audioExtensions,
        ScanType.video => AppConstants.videoExtensions,
        ScanType.doc => AppConstants.documentExtensions,
        ScanType.apk => AppConstants.apkExtensions,
        ScanType.custom => customExtensions,
      };
}

/// `CommonPageData.ScanAlgorithmType`.
enum ScanAlgorithm {
  sameContent('Scan For Same Content'),
  sameName('Scan For Same Name'),
  sameNameAndSize('Scan For Same Name and Size'),
  sameSize('Scan For Same Size'),
  sameAppearance('Scan For Same Appearance - Images');

  const ScanAlgorithm(this.label);
  final String label;
}

/// `CommonPageData.StorageSelection`.
enum StorageSelection {
  internal('Scan Internal Storage'),
  sdCard('Scan SD Card'),
  customFolder('Scan Custom Folder'),
  parallel('Scan Parallel Storage'),
  internalPlusSdCard('Scan Internal + SD Card'),
  usb('Scan USB Device');

  const StorageSelection(this.label);
  final String label;
}

/// `CommonPageData.FileSizeExclusionType`, with the byte ranges recovered from
/// `FilesScanner.FileCanBeProcessed`.
enum FileSizeExclusion {
  none('Exclude None'),
  tiny('Exclude Tiny Files (0 - 1MB)'),
  small('Exclude Small Files (1MB - 50MB)'),
  medium('Exclude Medium Files (50MB - 250MB)'),
  large('Exclude Large Files (250MB and above)');

  const FileSizeExclusion(this.label);
  final String label;

  static const _mb = 1048576;

  /// The 8 KB floor applies only to [none], exactly as in the original.
  bool allows(int size) => switch (this) {
        FileSizeExclusion.none => size >= AppConstants.minScannableFileSize,
        FileSizeExclusion.tiny => size > _mb,
        FileSizeExclusion.small => size < _mb || size > 50 * _mb,
        FileSizeExclusion.medium => size < 50 * _mb || size > 250 * _mb,
        FileSizeExclusion.large => size < 250 * _mb,
      };
}

/// `SortFieldType`.
enum SortField {
  size('Size'),
  nameLength('Name Length'),
  nameAlphabetical('Name alphabetical'),
  path('Path'),
  dateCreated('Date created');

  const SortField(this.label);
  final String label;
}

/// Selection filter options (`selectFiltersArray`).
enum SelectFilter {
  selectAll('Select all'),
  unselectAll('Unselect all'),
  selectDuplicates('Select duplicates');

  const SelectFilter(this.label);
  final String label;
}
