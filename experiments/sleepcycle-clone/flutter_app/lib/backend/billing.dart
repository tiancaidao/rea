import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../app_state.dart';
import 'backend.dart';

/// Google Play subscriptions via in_app_purchase, verified server-side
/// (POST /v1/billing/verify) before premium is granted.
///
/// Until the app and its `premium_yearly` subscription exist in Play Console,
/// the product lookup comes back empty and [startTrial] reports that instead
/// of charging anything; the caller then falls back to the local trial.
class Billing {
  Billing._();
  static final Billing I = Billing._();

  static const productId = 'premium_yearly';
  StreamSubscription<List<PurchaseDetails>>? _sub;
  Completer<String?>? _pending;

  void _listen() {
    _sub ??= InAppPurchase.instance.purchaseStream.listen(_onPurchases, onError: (Object e) {
      _pending?.complete('Purchase failed: $e');
      _pending = null;
    });
  }

  /// The store's localized price for the yearly plan (e.g. "€29.99"), or
  /// null until the product exists in Play Console / App Store Connect.
  Future<String?> price() async => (await products({productId}))[productId]?.price;

  /// Store details for [ids]; products not set up in the store are missing.
  Future<Map<String, ProductDetails>> products(Set<String> ids) async {
    try {
      final iap = InAppPurchase.instance;
      if (!await iap.isAvailable()) return {};
      final r = await iap.queryProductDetails(ids);
      return {for (final d in r.productDetails) d.id: d};
    } catch (_) {
      return {};
    }
  }

  /// Returns null on success, or a message explaining why premium wasn't granted.
  Future<String?> startTrial() => buy(productId);

  /// Buy the subscription [id] (yearly or monthly); null on success.
  Future<String?> buy(String id) async {
    final iap = InAppPurchase.instance;
    if (!await iap.isAvailable()) return 'Google Play billing isn\'t available on this device.';
    final r = await iap.queryProductDetails({id});
    if (r.productDetails.isEmpty) {
      return 'The subscription isn\'t set up in Play Console yet.';
    }
    _listen();
    _pending = Completer<String?>();
    await iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: r.productDetails.first));
    return _pending!.future;
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      if (p.status == PurchaseStatus.pending) continue;
      String? result;
      if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
        try {
          final v = await Backend.I.verifyPurchase(p.productID, p.verificationData.serverVerificationData);
          AppState.I.premium = v?['active'] == true;
          result = AppState.I.premium ? null : 'Purchase could not be verified.';
        } catch (e) {
          result = 'Verification failed: $e';
        }
      } else if (p.status == PurchaseStatus.canceled) {
        result = 'Purchase cancelled.';
      } else if (p.status == PurchaseStatus.error) {
        result = p.error?.message ?? 'Purchase failed.';
      }
      if (p.pendingCompletePurchase) await InAppPurchase.instance.completePurchase(p);
      _pending?.complete(result);
      _pending = null;
    }
  }
}
