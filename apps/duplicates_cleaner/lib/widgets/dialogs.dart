import 'package:flutter/material.dart';

import '../app.dart';
import '../core/constants.dart';

Future<void> showMessage(BuildContext context, String title, String message) =>
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Ok'))],
      ),
    );

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String yes = 'Yes!',
  String no = 'no',
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(no)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(yes)),
        ],
      ),
    ) ??
    false;

/// Single-choice list (`SelectDialogFragment` / `SelectFilterDialogFragment`).
Future<T?> chooseOne<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required String Function(T) label,
  T? selected,
  bool Function(T)? locked,
}) =>
    showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final o in options)
              ListTile(
                title: Text(label(o)),
                leading: Icon(
                  o == selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: AppColors.accent,
                ),
                trailing: (locked?.call(o) ?? false)
                    ? const Icon(Icons.workspace_premium, color: AppColors.primaryDark)
                    : null,
                onTap: () => Navigator.pop(c, o),
              ),
          ],
        ),
      ),
    );

/// The upgrade dialog with the benefits list (`UpgradeDialogFragment`).
Future<void> showUpgradeDialog(BuildContext context, {String? reason}) {
  final premium = AppScope.of(context).premium;
  return showDialog(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Upgrade Benefits'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reason != null) ...[Text(reason), const SizedBox(height: 12)],
            for (final b in AppConstants.premiumBenefits)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  const Icon(Icons.check_circle, color: AppColors.accent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(b)),
                ]),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('later')),
        FilledButton(
          onPressed: () async {
            Navigator.pop(c);
            if (premium.canPurchase) {
              await premium.unlockForTesting();
            } else {
              if (context.mounted) {
                await showMessage(context, 'Not available',
                    'In-app purchases are not configured in this build yet.');
              }
            }
          },
          child: Text(premium.canPurchase ? 'Unlock (debug)' : 'Upgrade Now!'),
        ),
      ],
    ),
  );
}
