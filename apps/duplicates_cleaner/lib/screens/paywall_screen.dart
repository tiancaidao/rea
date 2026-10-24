import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../core/byte_size.dart';
import '../core/constants.dart';
import '../services/premium_service.dart';
import '../widgets/dialogs.dart';
import '../widgets/themed.dart';
import 'home_screen.dart';

/// Full-screen upgrade offer: what the free version allows next to Prime,
/// the two store products, and the purchase call to action.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, this.reason, this.fromOnboarding = false});

  /// The free-tier limit that sent the user here, shown as a banner.
  final String? reason;

  /// Shown at the end of onboarding: leaving opens the home screen instead
  /// of popping back.
  final bool fromOnboarding;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

/// One row of the Free vs Prime table. A null cell is "not included".
typedef _Row = (IconData icon, String label, String? free, String prime);

const _yes = '✓';

final List<_Row> _rows = [
  (
    Icons.delete_sweep_outlined,
    'Files per clean',
    '${AppConstants.freeDeleteMaxFilesPerOperation}',
    'Unlimited',
  ),
  (
    Icons.data_usage,
    'Size per clean',
    '< ${formatBytes(AppConstants.freeFileSizeLimit)}',
    'Unlimited',
  ),
  (Icons.phone_android, 'Internal storage', _yes, _yes),
  (Icons.sd_card_outlined, 'SD card, USB & parallel apps', null, _yes),
  (Icons.folder_open_outlined, 'Custom folder scan', null, _yes),
  (Icons.auto_awesome_outlined, 'Similar images', null, _yes),
  (Icons.text_fields, 'Match by name, extension or size', null, _yes),
  (Icons.android, 'APK & custom extension scans', null, _yes),
  (Icons.filter_alt_outlined, 'File size exclusion filter', null, _yes),
  (Icons.sort, 'Advanced sort & selection filters', null, _yes),
];

class _PaywallScreenState extends State<PaywallScreen> {
  PremiumPlan _plan = PremiumPlan.lifetime;
  bool _busy = false;

  void _leave() {
    if (widget.fromOnboarding) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _purchase() async {
    final premium = AppScope.of(context).premium;
    setState(() => _busy = true);
    try {
      final ok = await premium.purchase(_plan);
      if (ok && mounted) _welcome();
    } on PremiumException catch (e) {
      if (mounted) await showMessage(context, 'Purchase failed', e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final premium = AppScope.of(context).premium;
    setState(() => _busy = true);
    bool restored;
    try {
      restored = await premium.restore();
    } on PremiumException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await showMessage(context, 'Restore failed', e.message);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (restored) return _welcome();
    await showMessage(
      context,
      'Nothing to restore',
      'We could not find a previous Prime purchase for this account.',
    );
  }

  void _welcome() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Welcome to ${AppConstants.premiumAppName}!'),
      ),
    );
    _leave();
  }

  @override
  Widget build(BuildContext context) {
    final premium = AppScope.of(context).premium;
    return ListenableBuilder(
      listenable: premium,
      builder: (context, _) => _buildPage(premium),
    );
  }

  Widget _buildPage(PremiumService premium) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    SquareIconButton(
                      icon: Icons.close,
                      tooltip: 'Close',
                      onPressed: _leave,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _busy ? null : _restore,
                      child: const Text('Restore'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  children: [
                    const _Rise(order: 0, child: _Header()),
                    if (widget.reason != null)
                      _Rise(order: 1, child: _ReasonBanner(widget.reason!)),
                    const SizedBox(height: 26),
                    for (final plan in PremiumPlan.values)
                      _Rise(
                        order: 2 + plan.index,
                        child: _PlanCard(
                          plan: plan,
                          price: premium.priceOf(plan),
                          selected: plan == _plan,
                          onTap: () => setState(() => _plan = plan),
                        ),
                      ),
                    const SizedBox(height: 14),
                    const _Rise(
                      order: 4,
                      child: Padding(
                        padding: EdgeInsets.only(left: 4, bottom: 10),
                        child: Text(
                          'Free vs Prime',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const _Rise(order: 5, child: _Comparison()),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              _Footer(
                plan: _plan,
                price: premium.priceOf(_plan),
                busy: _busy,
                onPurchase: _purchase,
                onSkip: widget.fromOnboarding ? _leave : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const AppMark(size: 120, icon: Icons.workspace_premium),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.premium.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'PRIME',
          style: TextStyle(
            color: Color(0xFFB87400),
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
          ),
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        'Clean without limits',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Every scan type, every storage location and every filter, '
        'with no cap on what you delete.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textMuted, height: 1.4),
      ),
    ],
  );
}

class _ReasonBanner extends StatelessWidget {
  const _ReasonBanner(this.reason);

  final String reason;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 18),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.premium.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.premium.withValues(alpha: 0.35)),
    ),
    child: Row(
      children: [
        const Icon(Icons.lock_outline, color: Color(0xFFB87400), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            reason,
            style: const TextStyle(fontSize: 13, height: 1.35),
          ),
        ),
      ],
    ),
  );
}

/// Feature table with a highlighted Prime column.
class _Comparison extends StatelessWidget {
  const _Comparison();

  static const _colWidth = 78.0;
  static const _tint = Color(0x140A7AFF);

  Widget _cell(String? value, {required bool prime}) {
    if (value == _yes) {
      return Icon(
        Icons.check_circle,
        size: 20,
        color: prime ? AppColors.primary : AppColors.textMuted,
      );
    }
    if (value == null) {
      return const Icon(Icons.remove, size: 18, color: AppColors.ring);
    }
    return Text(
      value,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: prime ? FontWeight.w700 : FontWeight.w500,
        color: prime ? AppColors.primary : AppColors.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    TableRow row(_Row r, {required bool last}) {
      final (icon, label, free, prime) = r;
      return TableRow(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label, style: const TextStyle(fontSize: 13.5)),
                ),
              ],
            ),
          ),
          Center(child: _cell(free, prime: false)),
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.fill,
            child: Container(
              decoration: BoxDecoration(
                color: _tint,
                borderRadius: last
                    ? const BorderRadius.vertical(bottom: Radius.circular(14))
                    : null,
              ),
              alignment: Alignment.center,
              child: _cell(prime, prime: true),
            ),
          ),
        ],
      );
    }

    const header = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: AppColors.textMuted,
      letterSpacing: 0.4,
    );
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
      child: Table(
        columnWidths: const {
          1: FixedColumnWidth(_colWidth),
          2: FixedColumnWidth(_colWidth),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('FEATURES', style: header),
              ),
              const Center(child: Text('FREE', style: header)),
              TableCell(
                verticalAlignment: TableCellVerticalAlignment.fill,
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: const BoxDecoration(
                    color: _tint,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(14),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'PRIME',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
          for (var i = 0; i < _rows.length; i++)
            row(_rows[i], last: i == _rows.length - 1),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.price,
    required this.selected,
    required this.onTap,
  });

  final PremiumPlan plan;
  final String price;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: selected
                ? Color.alphaBlend(_Comparison._tint, AppColors.surface)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppColors.primary : Colors.transparent,
              width: 2,
            ),
            boxShadow: softShadow(blur: 16, y: 5),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 18, 16),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: selected ? AppColors.primary : AppColors.textMuted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            plan.caption,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: price,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          TextSpan(
                            text: plan.period,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (plan == PremiumPlan.lifetime)
          Positioned(
            top: -10,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFC83D), AppColors.premium],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'BEST VALUE',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.plan,
    required this.price,
    required this.busy,
    required this.onPurchase,
    this.onSkip,
  });

  final PremiumPlan plan;
  final String price;
  final bool busy;
  final VoidCallback onPurchase;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      boxShadow: softShadow(blur: 24, y: -4),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: PrimaryButton(
            label: plan == PremiumPlan.lifetime
                ? 'Unlock Prime for $price'
                : 'Start Prime for $price${plan.period}',
            icon: Icons.workspace_premium,
            pill: true,
            loading: busy,
            onPressed: onPurchase,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          plan == PremiumPlan.lifetime
              ? 'One-time payment. No subscription.'
              : 'Renews monthly until cancelled. Cancel anytime in your '
                    'store account settings.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Link('Terms of Use', AppConstants.termsOfUseUrl),
            Text('·', style: TextStyle(color: AppColors.textMuted)),
            _Link('Privacy Policy', AppConstants.privacyPolicyUrl),
          ],
        ),
        if (onSkip != null)
          TextButton(
            onPressed: busy ? null : onSkip,
            child: const Text('Continue with the free version'),
          )
        else
          const SizedBox(height: 6),
      ],
    ),
  );
}

class _Link extends StatelessWidget {
  const _Link(this.label, this.url);

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(
      foregroundColor: AppColors.textMuted,
      textStyle: const TextStyle(fontSize: 11.5),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 30),
    ),
    onPressed: () =>
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    child: Text(label),
  );
}

/// Fades and lifts its child in, staggered by [order].
class _Rise extends StatelessWidget {
  const _Rise({required this.order, required this.child});

  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = (order * 0.08).clamp(0.0, 0.6);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
