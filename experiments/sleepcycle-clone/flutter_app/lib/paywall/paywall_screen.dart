import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
import '../backend/backend.dart';
import '../backend/billing.dart';
import '../device/notifications.dart';
import '../theme.dart';
import '../ui/main_shell.dart';
import '../ui/widgets/common.dart';
import 'paywall_config.dart';

/// Open the paywall for [placement] (the server picks the variant); from
/// onboarding, closing or buying enters the app. [variant] previews one.
Future<void> showPaywall(BuildContext context, String placement, {String? variant}) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => PaywallScreen(placement: placement, variant: variant)));

/// A server-driven paywall: loads the variant for its placement and renders
/// the variant's modules top to bottom (hero, trial journey, selling points,
/// feature list, comparison table, social proof, value presentation,
/// motivational message, discount offer, carousel, gift cards, pricing,
/// legal). Every paywall the original shows is one module list.
class PaywallScreen extends StatefulWidget {
  final String placement;
  final String? variant;
  const PaywallScreen({super.key, required this.placement, this.variant});
  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  PaywallConfig? _cfg;
  bool _loading = true;
  Map<String, StoreOffer> _store = {};
  String? _selected;
  bool _trialOn = true; // the opt-in variant's trial switch
  bool _buying = false;

  bool get _onboarding => widget.placement == Placement.onboarding;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await Paywalls.I.load(widget.placement, variant: widget.variant);
    if (!mounted) return;
    if (c == null) {
      _close();
      return;
    }
    setState(() {
      _cfg = c;
      _selected = c.defaultProduct;
      _loading = false;
    });
    final store = await Billing.I.products({for (final o in c.offers) o['product'] as String});
    if (mounted) setState(() => _store = store);
  }

  void _close() {
    if (_onboarding) {
      AppState.I.finishOnboarding();
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainShell()), (_) => false);
    } else {
      Navigator.pop(context);
    }
  }

  Map<String, dynamic>? _module(String type) {
    for (final m in _cfg!.modules) {
      if (m['type'] == type) return m;
    }
    return null;
  }

  bool get _showTrial {
    final pricing = _module('pricing');
    if (pricing?['showTrial'] == false) return false;
    if (pricing?['optIn'] == true && !_trialOn) return false;
    return _cfg!.trialDaysFor(_selected!) > 0;
  }

  // ── prices ────────────────────────────────────────────────────────────────

  bool _yearly(String id) => (_cfg!.products[id] as Map?)?['period'] == 'P1Y';

  String _money(StoreOffer d, double v) => '${d.currencySymbol}${v.toStringAsFixed(2)}';

  String? _perMonth(String id) {
    final d = _store[id];
    if (d == null) return null;
    return _yearly(id) ? _money(d, d.rawPrice / 12) : d.price;
  }

  int? _savePercent() {
    final y = _store.values.where((d) => _yearly(d.id)).firstOrNull;
    final m = _store.values.where((d) => !_yearly(d.id)).firstOrNull;
    if (y == null || m == null || m.rawPrice == 0) return null;
    return ((1 - y.rawPrice / (m.rawPrice * 12)) * 100).round();
  }

  String _planTitle(String id) => _yearly(id) ? 'Yearly' : 'Monthly';

  String _planPrice(String id) {
    final d = _store[id];
    if (d == null) return _yearly(id) ? 'billed yearly · price set by the store' : 'billed monthly';
    return _yearly(id) ? '${d.price}/year (only ${_perMonth(id)}/month)' : '${d.price}/month';
  }

  String _ctaDescription() {
    final id = _selected!;
    final d = _store[id];
    final price = d == null ? 'the store price' : (_yearly(id) ? '${d.price} per year' : '${d.price} per month');
    return _showTrial ? 'Then $price. Cancel anytime.' : '$price. Cancel anytime.';
  }

  // ── buying ────────────────────────────────────────────────────────────────

  Future<void> _buy() async {
    if (_buying) return;
    setState(() => _buying = true);
    final id = _selected!;
    try {
      // The store through RevenueCat; builds without a RevenueCat key
      // (development) start a local trial instead.
      final paid = Billing.I.available;
      if (paid) {
        final err = await Billing.I.buy(id);
        if (err != null) {
          if (mounted) toast(context, err);
          return;
        }
      } else {
        AppState.I.premium = true;
      }
      if (_showTrial) await _trialStarted(id);
      if (paid && _module('gift_cards') != null && mounted) await _shareGiftCards();
      if (mounted) _close();
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  Future<void> _trialStarted(String id) async {
    await Notifications.I.requestPermission();
    await Notifications.I.scheduleTrialReminder(DateTime.now());
    if (Backend.I.user != null) {
      try {
        await Backend.I.startTrial(id);
      } catch (_) {
        // already used on this account, or offline: the store is the source of truth
      }
    }
  }

  Future<void> _shareGiftCards() async {
    List<String> codes;
    try {
      codes = await Backend.I.issueGiftCards();
    } catch (_) {
      codes = const [];
    }
    if (codes.isEmpty || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Your gift cards'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Each code gives a friend a year of Premium. Valid for new users only.'),
          const SizedBox(height: 12),
          for (final code in codes)
            ListTile(
              title: SelectableText(code, style: const TextStyle(fontFamily: 'monospace', fontSize: 18)),
              trailing: IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () => Clipboard.setData(ClipboardData(text: code)),
              ),
            ),
        ]),
        actions: [
          TextButton(
            onPressed: () => SharePlus.instance.share(ShareParams(
                text: 'You have been given a year of Lullwake Premium. Redeem one of these codes in '
                    'Profile › Benefits:\n\n${codes.join('\n')}')),
            child: const Text('Share'),
          ),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Done')),
        ],
      ),
    );
  }

  // ── legal ─────────────────────────────────────────────────────────────────

  static const _terms = 'The subscription renews automatically at the end of each period unless you cancel at '
      'least 24 hours before it ends. Cancel any time in your app store account settings. During a free trial you '
      'are not charged; if you cancel before it ends, you keep the free version.';
  /// Apple's standard licence agreement (the app has no custom EULA) and
  /// MatchLab's privacy policy.
  static const termsUrl = 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';
  static const privacyUrl = 'https://www.matchlab.sg/privacy.html';

  Future<void> _open(String url) async {
    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication) && mounted) {
      toast(context, 'Couldn\'t open $url');
    }
  }

  Future<void> _restore() async {
    if (_buying) return;
    setState(() => _buying = true);
    final err = await Billing.I.restore();
    if (!mounted) return;
    setState(() => _buying = false);
    if (err == null && AppState.I.premium) {
      toast(context, 'Premium restored');
      _close();
    } else {
      toast(context, err ?? 'No active subscription found.');
    }
  }

  void _sheet(String title, Widget body) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (c) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            body,
          ]),
        ),
      );

  void _legal(String title, String body) =>
      _sheet(title, Text(body, style: TextStyle(color: context.palette.textMuted, height: 1.45)));

  // ── modules ───────────────────────────────────────────────────────────────

  Widget _render(Map<String, dynamic> m) {
    final p = context.palette;
    List<Map<String, dynamic>> items(String k) => [for (final i in (m[k] as List? ?? const [])) (i as Map).cast()];
    switch (m['type']) {
      case 'hero':
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(children: [
            if (m['animation'] == 'stars')
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Icon(Icons.auto_awesome, size: 72, color: p.accent),
              ),
            Text(m['title'] as String? ?? '',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            if (m['subtitle'] != null) ...[
              const SizedBox(height: 8),
              Text(m['subtitle'] as String, textAlign: TextAlign.center, style: TextStyle(color: p.textMuted)),
            ],
          ]),
        );
      case 'trial_journey':
        final steps = items('steps');
        return Column(children: [
          for (var i = 0; i < steps.length; i++)
            _Step(
                icon: paywallIcon(steps[i]['icon']),
                title: steps[i]['title'],
                body: steps[i]['body'],
                last: i == steps.length - 1),
        ]);
      case 'selling_points':
        return Column(children: [
          for (final it in items('items'))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading:
                  CircleAvatar(backgroundColor: p.surfaceHi, child: Icon(paywallIcon(it['icon']), color: p.accent)),
              title: Text(it['heading'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(it['text'] as String, style: TextStyle(color: p.textMuted)),
            ),
          const SizedBox(height: 16),
        ]);
      case 'feature_list':
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(children: [
            for (final it in items('items'))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.check_circle, color: p.positive, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '${it['heading']}  ', style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: it['text'] as String, style: TextStyle(color: p.textMuted)),
                    ])),
                  ),
                ]),
              ),
          ]),
        );
      case 'comparison_table':
        Widget mark(bool on) => Icon(on ? Icons.check : Icons.remove, color: on ? p.positive : p.textFaint, size: 20);
        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(p.radius)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Table(columnWidths: const {
            0: FlexColumnWidth(3),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1)
          }, children: [
            TableRow(children: [
              const SizedBox(),
              Center(child: Text('Free', style: TextStyle(color: p.textMuted))),
              Center(child: Text('Premium', style: TextStyle(color: p.accent, fontWeight: FontWeight.w700))),
            ]),
            for (final r in items('rows'))
              TableRow(children: [
                Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(r['label'] as String)),
                Center(child: mark(r['free'] == true)),
                Center(child: mark(true)),
              ]),
          ]),
        );
      case 'social_proof':
        final reviews = items('reviews');
        if (reviews.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 170,
          child: PageView(controller: PageController(viewportFraction: 0.9), children: [
            for (final r in reviews)
              Card(
                color: p.surface,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [for (var i = 0; i < 5; i++) Icon(Icons.star, size: 16, color: p.warn)]),
                    const SizedBox(height: 6),
                    Text(r['heading'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Expanded(
                        child: Text(r['text'] as String? ?? '',
                            overflow: TextOverflow.fade, style: TextStyle(color: p.textMuted))),
                    if (r['source'] != null) Text(r['source'] as String, style: TextStyle(color: p.textFaint)),
                  ]),
                ),
              ),
          ]),
        );
      case 'value_presentation':
        return Column(children: [
          for (final it in items('items'))
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(p.radius)),
              child: Row(children: [
                Icon(paywallIcon(it['icon']), color: p.accent, size: 36),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(it['header'] as String, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(it['text'] as String, style: TextStyle(color: p.textMuted)),
                  ]),
                ),
              ]),
            ),
          const SizedBox(height: 12),
        ]);
      case 'motivational_message':
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
          child: Text(m['text'] as String? ?? '',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontStyle: FontStyle.italic)),
        );
      case 'discount_offer':
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: p.warn, borderRadius: BorderRadius.circular(20)),
              child: Text('${m['percent']}% OFF',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, letterSpacing: 1)),
            ),
            const SizedBox(height: 8),
            Text(m['text'] as String? ?? '', textAlign: TextAlign.center, style: TextStyle(color: p.textMuted)),
          ]),
        );
      case 'carousel':
        return _Carousel(items: items('items'));
      case 'gift_cards':
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(children: [
            Stack(alignment: Alignment.topRight, children: [
              Container(
                height: 160,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(p.radius),
                  gradient: LinearGradient(colors: p.cta.length > 1 ? p.cta : [p.accent, p.surfaceHi]),
                ),
                child: const Center(child: Icon(Icons.card_giftcard, size: 84, color: Colors.white)),
              ),
              Container(
                margin: const EdgeInsets.all(10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: p.warn, borderRadius: BorderRadius.circular(4)),
                child: Text(m['ribbon'] as String? ?? '',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 20),
            Text(m['header'] as String? ?? '',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(m['description'] as String? ?? '', textAlign: TextAlign.center, style: TextStyle(color: p.textMuted)),
          ]),
        );
      case 'pricing':
        return _pricing(m);
      case 'legal':
        return Column(children: [
          const SizedBox(height: 8),
          Wrap(alignment: WrapAlignment.center, children: [
            TextButton(
                onPressed: () => Platform.isIOS ? _open(termsUrl) : _legal('Terms of use', _terms),
                child: Text('Terms', style: TextStyle(color: p.accent))),
            TextButton(
                onPressed: () => _open(privacyUrl), child: Text('Privacy', style: TextStyle(color: p.accent))),
            TextButton(onPressed: _restore, child: Text('Restore', style: TextStyle(color: p.accent))),
            if (m['whatsInPremium'] == true)
              TextButton(
                  onPressed: () => _sheet(
                      "What's in Premium?",
                      Column(children: [
                        for (final f in const [
                          'Smart alarm and more alarm sounds',
                          'Sleep aid: sounds, music and stories',
                          'Snore and sound detection',
                          'Statistics and weekly summary',
                          'Sleep notes and wake-up mood',
                          'Online backup',
                        ])
                          ListTile(leading: Icon(Icons.check, color: p.positive), title: Text(f)),
                      ])),
                  child: Text("What's in Premium?", style: TextStyle(color: p.accent))),
          ]),
        ]);
      default:
        return const SizedBox.shrink(); // a module this version doesn't know
    }
  }

  Widget _plan(String id, {String? badge}) {
    final p = context.palette;
    final on = _selected == id;
    final trial = _cfg!.trialDaysFor(id);
    return GestureDetector(
      onTap: () => setState(() => _selected = id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? p.accent : p.stroke, width: on ? 2 : 1),
          color: p.surface,
        ),
        child: Row(children: [
          Icon(on ? Icons.radio_button_checked : Icons.radio_button_off, color: on ? p.accent : p.textFaint),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('PREMIUM · ${_planTitle(id).toUpperCase()}',
                  style: const TextStyle(letterSpacing: 1.1, fontSize: 13)),
              const SizedBox(height: 4),
              if (trial > 0 && _showTrial)
                Text('$trial-day free trial', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              Text(_planPrice(id), style: TextStyle(color: p.textMuted)),
            ]),
          ),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(6)),
              child: Text(badge, style: TextStyle(color: p.onCta, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
        ]),
      ),
    );
  }

  Widget _pricing(Map<String, dynamic> m) {
    final p = context.palette;
    final ids = [for (final o in _cfg!.offers) o['product'] as String];
    final layout = m['layout'] as String? ?? 'single';
    final save = _savePercent();
    final plans = switch (layout) {
      'single' => [_plan(_selected!)],
      'two_plan' => [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final id in ids)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _TwoPlanCard(
                    title: _planTitle(id),
                    price:
                        _store[id] == null ? 'Store price' : (_yearly(id) ? '${_perMonth(id)}/mo' : _store[id]!.price),
                    sub: _store[id] == null
                        ? null
                        : (_yearly(id) ? '${_store[id]!.price} billed yearly' : 'billed monthly'),
                    badge: _yearly(id) && save != null ? 'Save $save%' : null,
                    selected: _selected == id,
                    onTap: () => setState(() => _selected = id),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 12),
        ],
      _ => [for (final id in ids) _plan(id, badge: _yearly(id) && save != null ? 'Save $save%' : null)],
    };
    final cta = m['cta'] as String? ?? (_showTrial ? 'Try it free' : 'Subscribe');
    return Column(children: [
      ...plans,
      if (m['optIn'] == true)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable free trial'),
          subtitle: Text(_trialOn ? 'Not charged until the trial ends' : 'Starts immediately, without a trial',
              style: TextStyle(color: p.textMuted)),
          value: _trialOn,
          onChanged: (v) => setState(() => _trialOn = v),
        ),
      const SizedBox(height: 16),
      PillButton(_buying ? 'One moment…' : cta, onPressed: _buy),
      const SizedBox(height: 10),
      Text(_ctaDescription(), textAlign: TextAlign.center, style: TextStyle(color: p.textMuted)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = _cfg;
    return Scaffold(
      body: StarryBackground(
        child: SafeArea(
          child: _loading || c == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: c.skippable
                        ? IconButton(icon: const Icon(Icons.close), onPressed: _close)
                        : const SizedBox(height: 48),
                  ),
                  for (final m in c.modules) _render(m),
                ]),
        ),
      ),
    );
  }
}

/// Material icon for an icon name in a paywall definition.
IconData paywallIcon(Object? name) => switch (name) {
      'lock_open' => Icons.lock_open,
      'notifications' => Icons.notifications,
      'star' => Icons.star,
      'check' => Icons.check,
      'nightlight' => Icons.nightlight_round,
      'alarm' => Icons.alarm,
      'headphones' => Icons.headphones,
      'graphic_eq' => Icons.graphic_eq,
      'bar_chart' => Icons.bar_chart,
      'insights' => Icons.insights,
      'edit_note' => Icons.edit_note,
      'cloud_done' => Icons.cloud_done,
      'music_note' => Icons.music_note,
      'mood' => Icons.mood,
      'record_voice_over' => Icons.record_voice_over,
      'light_mode' => Icons.light_mode,
      'air' => Icons.air,
      'school' => Icons.school,
      'volume_up' => Icons.volume_up,
      _ => Icons.auto_awesome,
    };

class _Step extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool last;
  const _Step({required this.icon, required this.title, required this.body, this.last = false});
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(children: [
            CircleAvatar(radius: 20, backgroundColor: context.palette.light, child: Icon(icon, color: Colors.white)),
            if (!last) Expanded(child: Container(width: 10, color: context.palette.light)),
          ]),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 28 : 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(body, style: TextStyle(color: context.palette.textMuted)),
              ]),
            ),
          ),
        ]),
      );
}

class _TwoPlanCard extends StatelessWidget {
  final String title;
  final String price;
  final String? sub;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;
  const _TwoPlanCard(
      {required this.title, required this.price, this.sub, this.badge, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 150,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? p.accent : p.stroke, width: selected ? 2 : 1),
          color: selected ? p.surfaceHi : p.surface,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(6)),
              child: Text(badge!, style: TextStyle(color: p.onCta, fontSize: 12, fontWeight: FontWeight.w700)),
            )
          else
            const SizedBox(height: 22),
          const Spacer(),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Text(price, style: const TextStyle(fontSize: 16)),
          if (sub != null) Text(sub!, style: TextStyle(color: p.textMuted, fontSize: 12)),
        ]),
      ),
    );
  }
}

class _Carousel extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  const _Carousel({required this.items});
  @override
  State<_Carousel> createState() => _CarouselState();
}

class _CarouselState extends State<_Carousel> {
  int _page = 0;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(children: [
        SizedBox(
          height: 230,
          child: PageView(
            onPageChanged: (i) => setState(() => _page = i),
            children: [
              for (final it in widget.items)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(p.radius)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(paywallIcon(it['icon']), size: 52, color: p.accent),
                    const SizedBox(height: 12),
                    Text(it['header'] as String, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Flexible(
                      child: Text(it['text'] as String,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.fade,
                          style: TextStyle(color: p.textMuted)),
                    ),
                  ]),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < widget.items.length; i++)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(shape: BoxShape.circle, color: i == _page ? p.accent : p.textFaint),
            ),
        ]),
      ]),
    );
  }
}
