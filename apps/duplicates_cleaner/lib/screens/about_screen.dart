import 'package:flutter/material.dart';

import '../app.dart';
import '../widgets/dialogs.dart';
import '../widgets/panel_scaffold.dart';

/// Version, upgrade and help entries (`AboutActivity`). Support and store
/// links from the original are intentionally left out; add your own.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const version = '1.0.0';

  @override
  Widget build(BuildContext context) {
    final premium = AppScope.of(context).premium;
    return ListenableBuilder(
      listenable: premium,
      builder: (context, _) => PanelScaffold(
        title: 'About',
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const SizedBox(height: 16),
            const CircleAvatar(
              radius: 48,
              backgroundColor: AppColors.primary,
              child: Icon(Icons.cleaning_services, size: 48, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text('Duplicates Cleaner${premium.isPremium ? ' Prime' : ''}',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            const Center(child: Text('Version $version')),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: Text(premium.isPremium
                    ? 'Premium version is already purchased'
                    : 'Upgrade - Premium Version'),
                onTap: premium.isPremium ? null : () => showUpgradeDialog(context),
                trailing: premium.isPremium && premium.canPurchase
                    ? TextButton(onPressed: premium.reset, child: const Text('Reset'))
                    : null,
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('User Guide'),
                onTap: () => showMessage(
                  context,
                  'User Guide',
                  '1. Pick a category on the home screen.\n'
                      '2. Wait for the scan to finish.\n'
                      '3. Review the checked files. The first file of each set is kept '
                      'as the original.\n'
                      '4. Tap a thumbnail to open the file, then tap CAN BE DELETED.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
