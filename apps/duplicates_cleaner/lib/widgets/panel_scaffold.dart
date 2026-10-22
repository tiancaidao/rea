import 'package:flutter/material.dart';

import '../theme.dart';
import 'themed.dart';

/// Shared screen shape: a title row on the pale blue gradient, with square
/// white toolbar buttons. With a [header], the [body] sits in a white sheet
/// below it, rounded at the top; otherwise it floats on the gradient.
class PanelScaffold extends StatelessWidget {
  const PanelScaffold({
    super.key,
    required this.title,
    required this.body,
    this.showBack = true,
    this.actions = const [],
    this.header,
    this.bottom,
  });

  final String title;
  final Widget body;
  final bool showBack;
  final List<Widget> actions;
  final Widget? header;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final canPop = showBack && Navigator.of(context).canPop();
    final bottomBar = bottom == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: bottom,
          );
    final head = header;
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leadingWidth: 64,
          leading: canPop
              ? SquareIconButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              : null,
          title: Text(title),
          actions: [...actions, const SizedBox(width: 10)],
        ),
        body: head == null
            ? SafeArea(
                top: false,
                child: Column(
                  children: [
                    Expanded(child: body),
                    ?bottomBar,
                  ],
                ),
              )
            : Column(
                children: [
                  head,
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppRadii.sheet),
                        ),
                        boxShadow: softShadow(blur: 30, y: -4),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Column(
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 12),
                              width: 56,
                              height: 4,
                              decoration: BoxDecoration(
                                color: AppColors.text.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            Expanded(child: body),
                            ?bottomBar,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
