import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/enums.dart';

/// The two Prime products, with their App Store and Play product ids.
enum PremiumPlan {
  lifetime(
    productId: 'prime_lifetime',
    title: 'Lifetime',
    caption: 'Pay once, yours forever',
    fallbackPrice: '\$9.99',
  ),
  monthly(
    productId: 'prime_monthly',
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

  /// Shown until the store's localized price has loaded.
  final String fallbackPrice;
  final String period;
}

/// Prime purchases through RevenueCat, which wraps StoreKit and Play Billing.
///
/// Prime is the RevenueCat entitlement [entitlementId]; the current offering
/// holds one package per [PremiumPlan] (store_products/subscriptions.json
/// sets them up). The public SDK keys come from
/// `--dart-define=REVENUECAT_IOS_KEY=...` and `REVENUECAT_ANDROID_KEY`. A
/// build without a key (tests, screenshots) can't sell, but debug builds can
/// still unlock Prime locally so every feature can be exercised.
class PremiumService extends ChangeNotifier {
  PremiumService(this._prefs);

  static const entitlementId = 'prime';
  static const _iosKey = String.fromEnvironment('REVENUECAT_IOS_KEY');
  static const _androidKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY');
  static const _cacheKey = 'Subscribed';

  final SharedPreferences _prefs;
  bool _configured = false;
  final Map<PremiumPlan, Package> _packages = {};

  static Future<PremiumService> load() async {
    final service = PremiumService(await SharedPreferences.getInstance());
    await service._configure();
    return service;
  }

  static String get _apiKey {
    if (kIsWeb) return '';
    if (Platform.isIOS) return _iosKey;
    if (Platform.isAndroid) return _androidKey;
    return '';
  }

  Future<void> _configure() async {
    final key = _apiKey;
    if (key.isEmpty) return;
    try {
      await Purchases.configure(PurchasesConfiguration(key));
      _configured = true;
      Purchases.addCustomerInfoUpdateListener(_apply);
      // The cached flag keeps the app usable offline; the store has the
      // final say once these return.
      unawaited(Purchases.getCustomerInfo().then(_apply).catchError((_) {}));
      unawaited(_loadPackages());
    } on PlatformException catch (e) {
      debugPrint('RevenueCat setup failed: ${e.message}');
    }
  }

  Future<void> _loadPackages() async {
    try {
      final offering = (await Purchases.getOfferings()).current;
      if (offering == null) return;
      for (final pkg in offering.availablePackages) {
        for (final plan in PremiumPlan.values) {
          // Play ids carry the base plan ("prime_monthly:monthly").
          if (pkg.storeProduct.identifier.split(':').first == plan.productId) {
            _packages[plan] = pkg;
          }
        }
      }
      notifyListeners();
    } on PlatformException catch (e) {
      debugPrint('RevenueCat offerings failed: ${e.message}');
    }
  }

  void _apply(CustomerInfo info) {
    final active = info.entitlements.active.containsKey(entitlementId);
    if (active == isPremium) return;
    _prefs.setBool(_cacheKey, active);
    notifyListeners();
  }

  bool get isPremium => _prefs.getBool(_cacheKey) ?? false;

  /// Debug builds can reset Prime to test the free tier again.
  bool get canReset => kDebugMode;

  Future<void> unlockForTesting() async {
    await _prefs.setBool(_cacheKey, true);
    notifyListeners();
  }

  /// The store's localized price for [plan], or its fallback until loaded.
  String priceOf(PremiumPlan plan) =>
      _packages[plan]?.storeProduct.priceString ?? plan.fallbackPrice;

  /// Starts the store purchase for [plan]. Returns whether Prime is now
  /// active; false when the user cancels. Throws [PremiumException] when the
  /// store can't sell it.
  Future<bool> purchase(PremiumPlan plan) async {
    if (!_configured) {
      if (!kDebugMode) throw const PremiumException(_unavailable);
      await unlockForTesting();
      return true;
    }
    if (_packages[plan] == null) await _loadPackages();
    final pkg = _packages[plan];
    if (pkg == null) throw const PremiumException(_unavailable);
    try {
      final result = await Purchases.purchase(PurchaseParams.package(pkg));
      _apply(result.customerInfo);
      return isPremium;
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) return false;
      if (code == PurchasesErrorCode.productAlreadyPurchasedError) {
        return restore();
      }
      throw PremiumException(e.message ?? _unavailable);
    }
  }

  /// Restores a previous purchase. Returns whether Prime is now active.
  Future<bool> restore() async {
    if (!_configured) return isPremium;
    try {
      _apply(await Purchases.restorePurchases());
    } on PlatformException catch (e) {
      throw PremiumException(e.message ?? _unavailable);
    }
    return isPremium;
  }

  /// Debug only: forgets the local unlock (the store purchase stays).
  Future<void> reset() async {
    await _prefs.setBool(_cacheKey, false);
    notifyListeners();
  }

  static const _unavailable =
      'Purchases are not available right now. Please try again later.';

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

/// A purchase or restore the store couldn't complete; [message] is shown to
/// the user.
class PremiumException implements Exception {
  const PremiumException(this.message);

  final String message;

  @override
  String toString() => message;
}
