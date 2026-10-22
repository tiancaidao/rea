import 'package:flutter/material.dart';

import '../app.dart';
import '../core/byte_size.dart';
import '../core/constants.dart';
import '../models/enums.dart';
import '../widgets/dialogs.dart';
import '../widgets/themed.dart';
import 'about_screen.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';

/// Grid of scan categories plus Settings and About (`HomeScreenActivity`).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.showFreeLimits = false});

  final bool showFreeLimits;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _icons = {
    ScanType.image: Icons.image_outlined,
    ScanType.audio: Icons.audiotrack_outlined,
    ScanType.video: Icons.movie_outlined,
    ScanType.doc: Icons.description_outlined,
    ScanType.apk: Icons.android,
    ScanType.custom: Icons.extension_outlined,
  };

  @override
  void initState() {
    super.initState();
    if (widget.showFreeLimits) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showFreeLimits());
    }
  }

  Future<void> _showFreeLimits() async {
    if (AppScope.of(context).premium.isPremium) return;
    final upgrade = await confirm(
      context,
      title: 'Free Version Limits',
      message:
          "You're using the free version.\n\n"
          'Delete up to ${AppConstants.freeDeleteMaxFilesPerOperation} files per operation '
          'and up to ${formatBytes(AppConstants.freeFileSizeLimit)} at a time.\n\n'
          'Continue free or upgrade now for unlimited cleanup.',
      yes: 'Upgrade Now!',
      no: 'Continue Free',
    );
    if (upgrade && mounted) await showUpgradeDialog(context);
  }

  Future<void> _open(ScanType type) async {
    final scope = AppScope.of(context);
    if (type == ScanType.apk && !scope.premium.allowsApkScan) {
      return showUpgradeDialog(
        context,
        reason: 'This feature is available in our prime version.',
      );
    }
    if (type == ScanType.custom) {
      if (!scope.premium.allowsCustomExtensions) {
        return showUpgradeDialog(
          context,
          reason: 'This feature is available in our prime version.',
        );
      }
      if (scope.settings.customExtensions.isEmpty) {
        return showMessage(
          context,
          'Custom Extensions',
          'Add custom extensions in Settings before running this scan.',
        );
      }
    }
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ScannerScreen(scanType: type)));
    // Refresh the cleaned-files counter in the hero.
    if (mounted) setState(() {});
  }

  void _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final premium = scope.premium;
    final cleaned = scope.settings.deletionSuccessCount;
    return ListenableBuilder(
      listenable: premium,
      builder: (context, _) => GradientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _Hero(
                  title: premium.isPremium
                      ? AppConstants.premiumAppName
                      : AppConstants.freeAppName,
                  cleaned: cleaned,
                  onSettings: () => _push(const SettingsScreen()),
                  onAbout: () => _push(const AboutScreen()),
                  onScan: () => _open(ScanType.image),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                sliver: SliverGrid.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 1.05,
                  children: [
                    for (final t in ScanType.values)
                      _HomeTile(
                        icon: _icons[t]!,
                        color: AppColors.badges[t.index],
                        label: t.label.replaceFirst('Scan ', ''),
                        subtitle: _subtitle(t, scope),
                        locked: switch (t) {
                          ScanType.apk => !premium.allowsApkScan,
                          ScanType.custom => !premium.allowsCustomExtensions,
                          _ => false,
                        },
                        onTap: () => _open(t),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _subtitle(ScanType t, AppScope scope) {
    final ext = t.extensions(scope.settings.customExtensions).toList();
    if (ext.isEmpty) return 'Add extensions in Settings';
    final shown = ext.take(3).join(', ');
    return ext.length > 3 ? '$shown...' : shown;
  }
}

/// White top panel with the toolbar, the big ring and the pill action that
/// overlaps its bottom edge.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.title,
    required this.cleaned,
    required this.onSettings,
    required this.onAbout,
    required this.onScan,
  });

  final String title;
  final int cleaned;
  final VoidCallback onSettings;
  final VoidCallback onAbout;
  final VoidCallback onScan;

  static const _buttonHeight = 52.0;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Container(
        margin: const EdgeInsets.only(bottom: _buttonHeight / 2),
        padding: EdgeInsets.fromLTRB(
          10,
          MediaQuery.paddingOf(context).top + 6,
          10,
          _buttonHeight / 2 + 28,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(AppRadii.sheet),
          ),
          boxShadow: softShadow(blur: 30, y: 10),
        ),
        child: Column(
          children: [
            Row(
              children: [
                SquareIconButton(
                  icon: Icons.tune,
                  tooltip: 'Settings',
                  color: AppColors.background,
                  onPressed: onSettings,
                ),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SquareIconButton(
                  icon: Icons.info_outline,
                  tooltip: 'About',
                  color: AppColors.background,
                  onPressed: onAbout,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ProgressRing(
              value: 0.78,
              size: 230,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$cleaned',
                    style: const TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'duplicate files\ncleaned so far',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Center(
          child: PrimaryButton(
            pill: true,
            height: _buttonHeight,
            icon: Icons.auto_awesome,
            label: 'Smart Scan',
            onPressed: onScan,
          ),
        ),
      ),
    ],
  );
}

class _HomeTile extends StatelessWidget {
  const _HomeTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.subtitle,
    required this.locked,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SoftCard(
    onTap: onTap,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(icon: icon, color: color, size: 46),
            const Spacer(),
            if (locked)
              const Icon(
                Icons.workspace_premium,
                size: 20,
                color: AppColors.premium,
              ),
          ],
        ),
        const Spacer(),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    ),
  );
}
