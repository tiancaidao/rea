import 'package:flutter/material.dart';

import '../app.dart';
import '../screens/paywall_screen.dart';

Future<void> showMessage(BuildContext context, String title, String message) =>
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Ok'),
          ),
        ],
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
        content: message.isEmpty ? null : Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(no)),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(yes),
          ),
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
}) => showModalBottomSheet<T>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (c) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(c).height * 0.75,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Center(child: Text(title, style: Theme.of(c).textTheme.titleMedium)),
          const SizedBox(height: 8),
          for (final o in options)
            ListTile(
              title: Text(label(o)),
              leading: Icon(
                o == selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: AppColors.primary,
              ),
              trailing: (locked?.call(o) ?? false)
                  ? const Icon(
                      Icons.workspace_premium,
                      color: AppColors.premium,
                    )
                  : null,
              onTap: () => Navigator.pop(c, o),
            ),
        ],
      ),
    ),
  ),
);

/// Opens the full-screen paywall (`UpgradeDialogFragment` in the original).
/// [reason] explains which free-tier limit the user just ran into.
Future<void> showPaywall(BuildContext context, {String? reason}) =>
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PaywallScreen(reason: reason),
      ),
    );
