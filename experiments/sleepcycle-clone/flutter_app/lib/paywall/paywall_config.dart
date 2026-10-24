import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../backend/backend.dart';

/// Where a paywall opens from; each placement runs its own experiment.
abstract final class Placement {
  static const onboarding = 'onboarding';
  static const inApp = 'in_app';
  static const lockedFeature = 'locked_feature';
  static const giftCards = 'gift_cards';
  static const campaign = 'campaign';
  static const appOpen = 'app_open';
}

/// One server-driven paywall: the variant chosen for this user and the
/// modules to render, in order (see backend/api/src/paywalls.json).
class PaywallConfig {
  final String placement;
  final String variant;
  final String name;
  final bool skippable;
  final String displayInterval;
  final List<Map<String, dynamic>> offers;
  final List<Map<String, dynamic>> modules;
  final Map<String, dynamic> products;

  PaywallConfig({
    required this.placement,
    required this.variant,
    required this.name,
    required this.skippable,
    required this.displayInterval,
    required this.offers,
    required this.modules,
    required this.products,
  });

  factory PaywallConfig.fromJson(Map<String, dynamic> j) {
    final c = (j['config'] as Map).cast<String, dynamic>();
    List<Map<String, dynamic>> maps(Object? l) =>
        [for (final m in (l as List? ?? const [])) (m as Map).cast<String, dynamic>()];
    return PaywallConfig(
      placement: j['placement'] as String,
      variant: j['variant'] as String,
      name: c['name'] as String? ?? j['variant'] as String,
      skippable: c['skippable'] as bool? ?? true,
      displayInterval: c['displayInterval'] as String? ?? 'never',
      offers: maps(c['offers']),
      modules: maps(c['modules']),
      products: (j['products'] as Map? ?? const {}).cast<String, dynamic>(),
    );
  }

  /// The offer preselected in the plan list.
  String get defaultProduct =>
      (offers.firstWhere((o) => o['default'] == true, orElse: () => offers.isEmpty ? const {} : offers.first)['product']
          as String?) ??
      'premium_yearly';

  int trialDaysFor(String product) => ((products[product] as Map?)?['trialDays'] as num?)?.toInt() ?? 0;

  /// How long to wait before showing this paywall again on app open.
  Duration? get reshowAfter => switch (displayInterval) {
        'everyAppOpening' => Duration.zero,
        'everyDay' => const Duration(days: 1),
        'everySecondDay' => const Duration(days: 2),
        'everyThirdDay' => const Duration(days: 3),
        'everyWeek' => const Duration(days: 7),
        _ => null,
      };
}

/// Fetches paywalls from the backend, falling back to the bundled copy of
/// the same definitions (assets/paywalls.json) offline or without a backend.
class Paywalls {
  Paywalls._();
  static final Paywalls I = Paywalls._();

  Map<String, dynamic>? _bundled;
  String? _installId;

  Future<String> installId() async {
    if (_installId != null) return _installId!;
    final p = await SharedPreferences.getInstance();
    var id = p.getString('install_id');
    if (id == null) {
      final r = math.Random.secure();
      id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await p.setString('install_id', id);
    }
    return _installId = id;
  }

  Future<Map<String, dynamic>> bundled() async =>
      _bundled ??= jsonDecode(await rootBundle.loadString('assets/paywalls.json')) as Map<String, dynamic>;

  /// Every variant id with its display name, for the preview list.
  Future<List<(String, String)>> variants() async {
    final v = (await bundled())['variants'] as Map<String, dynamic>;
    return [for (final e in v.entries) (e.key, (e.value as Map)['name'] as String? ?? e.key)];
  }

  /// The paywall for [placement]; null when the placement shows none.
  /// [variant] forces one variant (previews).
  Future<PaywallConfig?> load(String placement, {String? variant}) async {
    final id = await installId();
    try {
      final j = await Backend.I.paywall(placement, id, variant: variant);
      if (j != null) return j['variant'] == null ? null : PaywallConfig.fromJson(j);
    } catch (_) {
      // offline or no backend: choose locally from the bundled definitions
    }
    final j = choose(await bundled(), placement, id, variant);
    return j == null ? null : PaywallConfig.fromJson(j);
  }

  /// The same weighted, sticky choice the backend makes (with a local hash,
  /// so a device may land in another bucket offline than online).
  static Map<String, dynamic>? choose(Map<String, dynamic> cfg, String placement, String subject, String? forced) {
    final variants = (cfg['variants'] as Map).cast<String, dynamic>();
    final p = (cfg['placements'] as Map)[placement] as Map?;
    if (p == null) return null;
    String? id = forced != null && variants.containsKey(forced) ? forced : null;
    if (id == null) {
      final list = [
        for (final v in (p['variants'] as List? ?? const []))
          if (variants.containsKey(v['id']) && (v['weight'] as num) > 0) v as Map
      ];
      final total = list.fold<num>(0, (s, v) => s + (v['weight'] as num));
      if (total == 0) return null;
      var at = bucket('${p['experiment'] ?? placement}:$subject') / 100 * total;
      for (final v in list) {
        if (at < (v['weight'] as num)) {
          id = v['id'] as String;
          break;
        }
        at -= v['weight'] as num;
      }
      id ??= list.last['id'] as String;
    }
    final variant = (variants[id] as Map).cast<String, dynamic>();
    final products = (cfg['products'] as Map).cast<String, dynamic>();
    return {
      'placement': placement,
      'variant': id,
      'config': variant,
      'products': {
        for (final o in (variant['offers'] as List? ?? const []))
          if (products.containsKey(o['product'])) o['product']: products[o['product']],
      },
    };
  }

  /// FNV-1a, 0..99.
  static int bucket(String s) {
    var h = 0x811c9dc5;
    for (final c in utf8.encode(s)) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h % 100;
  }

  /// On app open: the paywall to show now, if its re-show interval passed.
  Future<PaywallConfig?> dueOnAppOpen() async {
    final c = await load(Placement.appOpen);
    final wait = c?.reshowAfter;
    if (c == null || wait == null) return null;
    final p = await SharedPreferences.getInstance();
    final last = p.getInt('paywall_shown_${c.variant}');
    final now = DateTime.now().millisecondsSinceEpoch;
    if (last != null && now - last < wait.inMilliseconds) return null;
    await p.setInt('paywall_shown_${c.variant}', now);
    return c;
  }
}
