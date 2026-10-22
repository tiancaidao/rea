import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/enums.dart';

/// The two products the original sells, with their Play Console ids.
enum PremiumPlan {
  lifetime(
    productId: 'dc_prime_one_time_purchase',
    title: 'Lifetime',
    caption: 'Pay once, yours forever',
    fallbackPrice: '\$9.99',
  ),
  monthly(
    productId: 'dc_prime_benefits',
    title: 'Monthly',
    caption: 'Billed monthly, cancel anytime',
    fallbackPrice: '\$1.99',
    period: '/month',
  );

  const PremiumPlan({
    required this.productId,
    required this.title,
    required this.caption,
    required this.fallbackPrice,
    this.period = '',
  });

  final String productId;
  final String title;
  final String caption;

  /// Placeholder until store prices are loaded; replace with the localized
  /// `ProductDetails.price` once billing is wired up.
  final String fallbackPrice;
  final String period;
}

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

  /// Store price for [plan]; the placeholder until billing is wired up.
  String priceOf(PremiumPlan plan) => plan.fallbackPrice;

  /// Starts the store purchase for [plan]. Returns whether premium is now
  /// active. Only debug builds can complete it until billing is wired up.
  Future<bool> purchase(PremiumPlan plan) async {
    if (!canPurchase) return false;
    await unlockForTesting();
    return true;
  }

  /// Restores a previous purchase. Returns whether premium is now active.
  Future<bool> restore() async => isPremium;

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
