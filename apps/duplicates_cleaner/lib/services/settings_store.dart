import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/enums.dart';

/// Persists the options shown on the Settings screen (`CommonPageData` /
/// `SettingsData` in the original).
class SettingsStore extends ChangeNotifier {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<SettingsStore> load() async =>
      SettingsStore(await SharedPreferences.getInstance());

  T _enum<T extends Enum>(String key, List<T> values, T fallback) {
    final i = _prefs.getInt(key);
    return i != null && i >= 0 && i < values.length ? values[i] : fallback;
  }

  Future<void> _setEnum(String key, Enum value) async {
    await _prefs.setInt(key, value.index);
    notifyListeners();
  }

  ScanAlgorithm get algorithm =>
      _enum('ScanAlgorithm', ScanAlgorithm.values, ScanAlgorithm.sameContent);
  set algorithm(ScanAlgorithm v) => _setEnum('ScanAlgorithm', v);

  StorageSelection get storage =>
      _enum('StorageSelection', StorageSelection.values, StorageSelection.internal);
  set storage(StorageSelection v) => _setEnum('StorageSelection', v);

  FileSizeExclusion get sizeExclusion =>
      _enum('ExcludedFileSizes', FileSizeExclusion.values, FileSizeExclusion.none);
  set sizeExclusion(FileSizeExclusion v) => _setEnum('ExcludedFileSizes', v);

  bool get autoSelectDuplicates => _prefs.getBool('DuplicatesAutoSelection') ?? true;
  set autoSelectDuplicates(bool v) {
    _prefs.setBool('DuplicatesAutoSelection', v);
    notifyListeners();
  }

  bool get promptBeforeDeletion => _prefs.getBool('FilesDeletionPrompt') ?? true;
  set promptBeforeDeletion(bool v) {
    _prefs.setBool('FilesDeletionPrompt', v);
    notifyListeners();
  }

  bool get firstLaunch => _prefs.getBool('FirstLaunch') ?? true;
  set firstLaunch(bool v) => _prefs.setBool('FirstLaunch', v);

  bool get similarImageWarningDisabled =>
      _prefs.getBool('SimilarImageWarningDisabled') ?? false;
  set similarImageWarningDisabled(bool v) =>
      _prefs.setBool('SimilarImageWarningDisabled', v);

  String? get customFolder => _prefs.getString('CustomFolder');
  set customFolder(String? v) {
    v == null ? _prefs.remove('CustomFolder') : _prefs.setString('CustomFolder', v);
    notifyListeners();
  }

  /// Stored comma separated, like the original `CustomExtensions` key.
  Set<String> get customExtensions => (_prefs.getString('CustomExtensions') ?? '')
      .split(',')
      .map((e) => e.trim().toLowerCase())
      .where((e) => e.isNotEmpty)
      .toSet();
  set customExtensions(Set<String> v) {
    _prefs.setString('CustomExtensions', v.join(','));
    notifyListeners();
  }

  int get deletionSuccessCount => _prefs.getInt('DeletionSuccessCount') ?? 0;
  set deletionSuccessCount(int v) => _prefs.setInt('DeletionSuccessCount', v);
}
