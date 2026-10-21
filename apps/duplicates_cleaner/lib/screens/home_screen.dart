import 'package:flutter/material.dart';

import '../app.dart';
import '../core/byte_size.dart';
import '../core/constants.dart';
import '../models/enums.dart';
import '../widgets/dialogs.dart';
import '../widgets/panel_scaffold.dart';
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
      message: "You're using the free version.\n\n"
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
    if (type == ScanType.custom) {
      if (!scope.premium.allowsCustomExtensions) {
        return showUpgradeDialog(context,
            reason: 'This feature is available in our prime version.');
      }
      if (scope.settings.customExtensions.isEmpty) {
        return showMessage(context, 'Custom Extensions',
            'Add custom extensions in Settings before running this scan.');
      }
    }
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ScannerScreen(scanType: type)));
  }

  @override
  Widget build(BuildContext context) {
    final premium = AppScope.of(context).premium;
    return ListenableBuilder(
      listenable: premium,
      builder: (context, _) => PanelScaffold(
        showBack: false,
        title: premium.isPremium ? AppConstants.premiumAppName : AppConstants.freeAppName,
        body: GridView.count(
          padding: const EdgeInsets.all(16),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            for (final t in ScanType.values)
              _HomeTile(icon: _icons[t]!, label: t.label, onTap: () => _open(t)),
            _HomeTile(
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
            _HomeTile(
              icon: Icons.info_outline,
              label: 'About',
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const AboutScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeTile extends StatelessWidget {
  const _HomeTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.primary,
                child: Icon(icon, size: 30, color: Colors.black87),
              ),
              const SizedBox(height: 12),
              Text(label, style: const TextStyle(fontSize: 15), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}
