import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../app_state.dart';
import 'backend.dart';

/// A store product as the paywall shows it.
class StoreOffer {
  final String id; // our product id (premium_yearly / premium_monthly)
  final String price; // localized, e.g. "$39.99"
  final double rawPrice;
  final String currencySymbol;
  final StoreProduct? product; // null for preview prices
  final Package? package; // the offering package it came from, if any
  StoreOffer(this.id, StoreProduct this.product, [this.package])
      : price = product.priceString,
        rawPrice = product.price,
        currencySymbol = product.priceString.replaceAll(RegExp(r'[\d.,\s\u00a0]'), '');

  /// US list price, for builds with no store (store screenshots).
  StoreOffer.preview(this.id, this.rawPrice)
      : product = null,
        package = null,
        currencySymbol = r'$',
        price = '\$${rawPrice.toStringAsFixed(2)}';
}

/// App Store and Google Play subscriptions through RevenueCat, which
/// validates receipts and tells our API about renewals and cancellations
/// (webhook → POST /v1/billing/revenuecat). Premium is the RevenueCat
/// entitlement [entitlement]. The plans come from the current offering's
/// annual and monthly packages, so the store product ids can be anything;
/// purchases belong to the Firebase account
/// (RevenueCat app user id = Firebase uid) once signed in.
///
///   --dart-define=REVENUECAT_IOS_KEY=appl_...  --dart-define=REVENUECAT_ANDROID_KEY=goog_...
///   --dart-define=REVENUECAT_KEY=test_...      # one key for both, e.g. the Test Store
///
/// These are RevenueCat's public SDK keys. Without one (dev builds) the store
/// is unavailable and the paywall falls back to a local trial.
class Billing {
  Billing._();
  static final Billing I = Billing._();

  static const entitlement = 'lulu_wake_pro';
  static const productId = 'premium_yearly';
  static const _iosKey = String.fromEnvironment('REVENUECAT_IOS_KEY');
  static const _androidKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY');
  static const _sharedKey = String.fromEnvironment('REVENUECAT_KEY');

  /// --dart-define=PREVIEW_PRICES=true shows the US list prices on the
  /// paywall when no store is configured (for store screenshots); buying
  /// still needs the store.
  static const _previewPrices = bool.fromEnvironment('PREVIEW_PRICES');
  static const _listPrices = {'premium_yearly': 39.99, 'premium_monthly': 9.99};

  bool _ready = false;
  bool get available => _ready;

  /// Whether the current Premium came from a store subscription (as opposed
  /// to a gift card or a local trial), so a lapsed subscription removes it.
  bool _fromStore = false;

  static String get _key {
    final own = Platform.isIOS
        ? _iosKey
        : Platform.isAndroid
            ? _androidKey
            : '';
    return own.isNotEmpty ? own : _sharedKey;
  }

  Future<void> init() async {
    if (_ready || _key.isEmpty) return;
    try {
      await Purchases.configure(PurchasesConfiguration(_key)..appUserID = Backend.I.user?.uid);
      Purchases.addCustomerInfoUpdateListener(_apply);
      Backend.I.authChanges.listen((u) => unawaited(identify(u?.uid)));
      _ready = true;
      _apply(await Purchases.getCustomerInfo());
    } catch (_) {}
  }

  /// Moves purchases to the signed-in account; null (signed out) goes back
  /// to an anonymous RevenueCat user.
  Future<void> identify(String? uid) async {
    if (!_ready) return;
    try {
      if (uid == null) {
        if (!await Purchases.isAnonymous) _apply(await Purchases.logOut());
      } else if (await Purchases.appUserID != uid) {
        _apply((await Purchases.logIn(uid)).customerInfo);
      }
    } catch (_) {}
  }

  void _apply(CustomerInfo info) {
    final active = info.entitlements.active.containsKey(entitlement);
    if (active) {
      _fromStore = true;
      AppState.I.setPremium(true);
    } else if (_fromStore) {
      _fromStore = false;
      AppState.I.setPremium(false);
    }
  }

  /// The store's localized price for the yearly plan, or null until the
  /// product exists in App Store Connect / Play Console and RevenueCat.
  Future<String?> price() async => (await products({productId}))[productId]?.price;

  /// Store details for [ids]; products not set up in the store are missing.
  Future<Map<String, StoreOffer>> products(Set<String> ids) async {
    if (!_ready) {
      if (!_previewPrices) return {};
      return {
        for (final id in ids)
          if (_listPrices[id] != null) id: StoreOffer.preview(id, _listPrices[id]!),
      };
    }
    try {
      final offering = (await Purchases.getOfferings()).current;
      final packages = {'premium_yearly': offering?.annual, 'premium_monthly': offering?.monthly};
      final found = {
        for (final id in ids)
          if (packages[id] != null) id: StoreOffer(id, packages[id]!.storeProduct, packages[id]),
      };
      if (found.isNotEmpty) return found;
      // No offering: look the products up by id. Play reports subscriptions
      // as "<product>:<base plan>".
      final list = await Purchases.getProducts(ids.toList());
      return {for (final p in list) p.identifier.split(':').first: StoreOffer(p.identifier.split(':').first, p)};
    } catch (_) {
      return {};
    }
  }

  /// Returns null on success, or a message explaining why premium wasn't granted.
  Future<String?> startTrial() => buy(productId);

  /// Buy the subscription [id] (yearly or monthly); null on success.
  Future<String?> buy(String id) async {
    if (!_ready) return 'The store isn\'t available in this build.';
    final offer = (await products({id}))[id];
    if (offer?.product == null) return 'The subscription isn\'t set up in the store yet.';
    try {
      final r = await Purchases.purchase(offer!.package != null
          ? PurchaseParams.package(offer.package!)
          : PurchaseParams.storeProduct(offer.product!));
      _apply(r.customerInfo);
      unawaited(Backend.I.syncPurchases());
      return AppState.I.premium ? null : 'The purchase went through but Premium isn\'t active yet.';
    } on PlatformException catch (e) {
      return _message(e);
    }
  }

  /// Restore purchases (App Review 3.1.1). Null when Premium came back.
  Future<String?> restore() async {
    if (!_ready) return 'The store isn\'t available in this build.';
    try {
      final info = await Purchases.restorePurchases();
      _apply(info);
      unawaited(Backend.I.syncPurchases());
      return info.entitlements.active.containsKey(entitlement)
          ? null
          : 'No active subscription found for this store account.';
    } on PlatformException catch (e) {
      return _message(e);
    }
  }

  static String _message(PlatformException e) => switch (PurchasesErrorHelper.getErrorCode(e)) {
        PurchasesErrorCode.purchaseCancelledError => 'Purchase cancelled.',
        PurchasesErrorCode.paymentPendingError => 'The payment is pending approval.',
        PurchasesErrorCode.networkError => 'No connection to the store. Try again.',
        _ => e.message ?? 'Purchase failed.',
      };
}
