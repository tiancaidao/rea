import 'dart:io';

import 'package:flutter/material.dart';

import '../app.dart';
import '../core/constants.dart';
import '../models/enums.dart';
import '../services/app_log.dart';
import '../widgets/dialogs.dart';
import '../widgets/panel_scaffold.dart';
import '../widgets/themed.dart';

/// Scan location, scan type, size exclusion, toggles and custom extensions
/// (`SettingsActivity`).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final settings = scope.settings, premium = scope.premium;
    return ListenableBuilder(
      listenable: Listenable.merge([settings, premium]),
      builder: (context, _) {
        final locations = Platform.isIOS
            ? const [StorageSelection.internal, StorageSelection.customFolder]
            : StorageSelection.values;
        return PanelScaffold(
          title: 'Settings',
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              _OptionCard(
                icon: Icons.folder_outlined,
                color: AppColors.badges[0],
                title: 'Scan Location',
                value:
                    settings.storage == StorageSelection.customFolder &&
                        settings.customFolder != null
                    ? 'Custom: ${settings.customFolder}'
                    : settings.storage.label,
                onTap: () async {
                  final s = await chooseOne(
                    context,
                    title: 'Scan Location',
                    options: locations,
                    label: (s) => s.label,
                    selected: settings.storage,
                    locked: (s) => !premium.allowsStorage(s),
                  );
                  if (s == null || !context.mounted) return;
                  if (!premium.allowsStorage(s)) {
                    return showPaywall(context);
                  }
                  if (s == StorageSelection.customFolder) {
                    final folder = await scope.storage.pickFolder();
                    if (folder == null) return;
                    settings.customFolder = folder;
                  }
                  settings.storage = s;
                },
              ),
              _OptionCard(
                icon: Icons.manage_search,
                color: AppColors.badges[3],
                title: 'Scan Type',
                value: settings.algorithm.label,
                onTap: () async {
                  final a = await chooseOne(
                    context,
                    title: 'Scan Type',
                    options: ScanAlgorithm.values,
                    label: (a) => a.label,
                    selected: settings.algorithm,
                    locked: (a) => !premium.allowsAlgorithm(a),
                  );
                  if (a == null || !context.mounted) return;
                  if (!premium.allowsAlgorithm(a)) {
                    return showPaywall(context);
                  }
                  settings.algorithm = a;
                },
              ),
              _OptionCard(
                icon: Icons.filter_alt_outlined,
                color: AppColors.badges[5],
                title: 'File Size Exclusion',
                value: settings.sizeExclusion.label,
                onTap: () async {
                  final e = await chooseOne(
                    context,
                    title: 'File Size Exclusion',
                    options: FileSizeExclusion.values,
                    label: (e) => e.label,
                    selected: settings.sizeExclusion,
                    locked: (e) => !premium.allowsSizeExclusion(e),
                  );
                  if (e == null || !context.mounted) return;
                  if (!premium.allowsSizeExclusion(e)) {
                    return showPaywall(context);
                  }
                  settings.sizeExclusion = e;
                },
              ),
              Card(
                child: SwitchListTile(
                  secondary: IconBadge(
                    icon: Icons.done_all,
                    color: AppColors.badges[4],
                    size: 42,
                  ),
                  title: const Text('Auto Select Duplicates'),
                  value: settings.autoSelectDuplicates,
                  onChanged: (v) => settings.autoSelectDuplicates = v,
                ),
              ),
              Card(
                child: SwitchListTile(
                  secondary: IconBadge(
                    icon: Icons.warning_amber_outlined,
                    color: AppColors.badges[2],
                    size: 42,
                  ),
                  title: const Text('Prompt Before File Deletion'),
                  value: settings.promptBeforeDeletion,
                  onChanged: (v) => settings.promptBeforeDeletion = v,
                ),
              ),
              Card(
                child: SwitchListTile(
                  secondary: IconBadge(
                    icon: Icons.verified_outlined,
                    color: AppColors.badges[1],
                    size: 42,
                  ),
                  title: const Text('Confirm Same Content Byte by Byte'),
                  subtitle: const Text(
                    'Slower, but never groups files that only share sampled bytes',
                  ),
                  value: settings.verifyContent,
                  onChanged: (v) => settings.verifyContent = v,
                ),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                icon: Icons.add,
                label: 'Custom Extensions',
                onPressed: () => premium.allowsCustomExtensions
                    ? showDialog(
                        context: context,
                        builder: (_) => const _ExtensionsDialog(),
                      )
                    : showPaywall(context),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 54,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Export Log'),
                  onPressed: () async {
                    if (!await AppLog.export() && context.mounted) {
                      await showMessage(
                        context,
                        'Export Log',
                        'Nothing has been logged yet.',
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: IconBadge(icon: icon, color: color, size: 42),
      title: Text(title),
      subtitle: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

/// `CustomExtensionDialogFragment`: add comma separated extensions, remove
/// existing ones.
class _ExtensionsDialog extends StatefulWidget {
  const _ExtensionsDialog();

  @override
  State<_ExtensionsDialog> createState() => _ExtensionsDialogState();
}

class _ExtensionsDialogState extends State<_ExtensionsDialog> {
  final _input = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _save() {
    final settings = AppScope.of(context).settings;
    final text = _input.text.replaceAll(' ', '');
    if (!AppConstants.customExtensionsPattern.hasMatch(text)) {
      setState(
        () =>
            _error = 'Use letters and digits separated by commas, e.g. psd,ai',
      );
      return;
    }
    settings.customExtensions = {
      ...settings.customExtensions,
      ...text.split(',').where((e) => e.isNotEmpty).map((e) => e.toLowerCase()),
    };
    _input.clear();
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => AlertDialog(
        title: const Text('Add Custom Extension'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _input,
                decoration: InputDecoration(
                  hintText: 'Enter extensions',
                  errorText: _error,
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in settings.customExtensions)
                    InputChip(
                      label: Text(e),
                      onDeleted: () => settings.customExtensions = {
                        ...settings.customExtensions,
                      }..remove(e),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}
