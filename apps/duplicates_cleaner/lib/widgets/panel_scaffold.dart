import 'package:flutter/material.dart';

import '../app.dart';

/// The original screens share one shape: a title row on the cream background
/// and a rounded panel holding the content.
class PanelScaffold extends StatelessWidget {
  const PanelScaffold({
    super.key,
    required this.title,
    required this.body,
    this.showBack = true,
    this.actions = const [],
    this.bottom,
  });

  final String title;
  final Widget body;
  final bool showBack;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: showBack,
        title: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
        actions: actions,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(25),
                ),
                clipBehavior: Clip.antiAlias,
                child: body,
              ),
            ),
            ?bottom,
          ],
        ),
      ),
    );
  }
}
