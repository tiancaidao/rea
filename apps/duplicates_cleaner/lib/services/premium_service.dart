import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/enums.dart';

/// Stand-in for the original Google Play Billing + sideload licence checks.
///
/// The original sells `dc_prime_benefits` (monthly) and
/// `dc_prime_one_time_purchase`. Wire this to `in_app_purchase` with your own
/// store products before release; until then, debug builds can unlock premium
/// from the upgrade dialog so every feature can be exercised.
class PremiumService extends ChangeNotifier {
  PremiumService(this._prefs);

  final SharedPreferences _prefs;

  static Future<PremiumService> load() async =>
      PremiumService(await SharedPreferences.getInstance());

  bool get isPremium => _prefs.getBool('Subscribed') ?? false;

  bool get canPurchase => kDebugMode;

  Future<void> unlockForTesting() async {
    await _prefs.setBool('Subscribed', true);
    notifyListeners();
  }

  Future<void> reset() async {
    await _prefs.setBool('Subscribed', false);
    notifyListeners();
  }

  /// Features gated behind premium in the original app.
  bool allowsAlgorithm(ScanAlgorithm a) =>
      isPremium || a == ScanAlgorithm.sameContent;
  bool allowsStorage(StorageSelection s) =>
      isPremium || s == StorageSelection.internal;
  bool allowsSizeExclusion(FileSizeExclusion e) =>
      isPremium || e == FileSizeExclusion.none;
  bool get allowsCustomExtensions => isPremium;
  bool get allowsApkScan => isPremium;
  bool get allowsSortAndSelectFilters => isPremium;
}
