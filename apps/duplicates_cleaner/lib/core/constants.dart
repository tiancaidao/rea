/// Values recovered from the original app (`Constants`, `StaticDataStore`,
/// `FilesScanner.FileCanBeProcessed`). See analysis/ANALYSIS.md.
class AppConstants {
  static const freeAppName = 'Duplicates Cleaner';
  static const premiumAppName = 'Duplicates Cleaner Prime';

  /// Free users cannot delete a selection totalling this size or more (500 MB).
  static const freeFileSizeLimit = 524288000;

  /// Free users can delete at most this many files per delete operation.
  static const freeDeleteMaxFilesPerOperation = 100;

  /// Files below this size are skipped when no size exclusion is chosen.
  static const minScannableFileSize = 8192;

  /// Hamming distance threshold used for perceptual-hash image grouping.
  static const similarImageMaxHammingDistance = 12;

  /// Thumbnail edge in the results list (`IMAGE_DIMENSION`).
  static const thumbnailSize = 60.0;

  /// Validation pattern for the custom extensions input (comma separated).
  static final customExtensionsPattern = RegExp(
    r'^,?[A-Za-z0-9]+(,[A-Za-z0-9]+)*$',
  );

  static const imageExtensions = {
    'jpg', 'jpeg', 'png', 'gif', 'tiff', 'tif', 'bmp', 'heif', 'eps', 'raw', //
  };
  static const audioExtensions = {
    'mp3',
    'wav',
    'wma',
    'm4a',
    'flac',
    'aac',
    'amr',
    'opus',
    'asf',
    'asx',
    'midi', //
  };
  static const videoExtensions = {
    'mp4', 'avi', 'vob', 'mkv', 'flv', '3gp', 'mov', 'wmv', 'webm', //
  };
  static const documentExtensions = {
    'pdf',
    'doc',
    'docx',
    'rtf',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'mobi',
    'epub', //
    'rar', 'zip', 'txt', 'cbr', 'cbz', 'fb2', 'ttf',
  };
  static const apkExtensions = {'apk'};

  /// Image formats the pure-Dart decoder can read for similar-image scans.
  static const decodableImageExtensions = {
    'jpg', 'jpeg', 'png', 'gif', 'tiff', 'tif', 'bmp', //
  };

  static const premiumBenefits = [
    'Delete files without any limit',
    'Scan SD Card storage',
    'Scan Similar-Images',
    'Scan USB storage (Requires Android > 10)',
    'Scan Parallel storage',
    'Scan Custom folder',
    'File size exclusion filter',
    'Scan duplicates with same name/extension/size',
    'Scan duplicates with custom extensions',
    'Advanced sort filters',
    'Selection filters',
  ];
}
