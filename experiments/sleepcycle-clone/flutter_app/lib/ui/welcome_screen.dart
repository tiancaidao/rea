import 'dart:async';
import 'package:flutter/material.dart';
import '../backend/backend.dart';
import '../theme.dart';
import 'login_screen.dart';
import '../paywall/paywall_config.dart';
import '../paywall/paywall_screen.dart';
import 'widgets/common.dart';

/// After onboarding: account choice (continue with a provider, sign up, or
/// log in), then the free-trial explainer, then the app. Mirrors the
/// original's post-onboarding journey with our own copy; sign-in providers
/// and purchases are mocked.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  Future<void> _signedIn(BuildContext context) async {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TrialScreen(placement: Placement.onboarding)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StarryBackground(
        child: SafeArea(
          child: Column(children: [
            const Spacer(flex: 2),
            Container(
              width: 130,
              height: 130,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Icon(Icons.nightlight_round, size: 64, color: context.palette.deep),
            ),
            const SizedBox(height: 28),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text('Better mornings start with understanding your nights',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 24, height: 1.3)),
            ),
            const Spacer(),
            const _SocialProof(),
            const Spacer(),
            Container(
              color: context.palette.sheet,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(children: [
                const Text('Create an account to keep your nights safe and synced.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.white, foregroundColor: Colors.black, shape: const StadiumBorder()),
                    onPressed: () {
                      if (Backend.I.enabled) {
                        // Google sign-in needs the app's SHA-1 registered in Firebase
                        // (see backend/README.md); use email until then.
                        toast(context, 'Google sign-in isn\'t set up for this build yet — use email.');
                        _email(context, signUp: true);
                      } else {
                        _signedIn(context);
                      }
                    },
                    icon: const Icon(Icons.account_circle),
                    label: const Text('Continue with Google', style: TextStyle(fontSize: 17)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  TextButton(
                      onPressed: () => _email(context, signUp: true),
                      child: Text('Sign up with email', style: TextStyle(color: context.palette.accent, fontSize: 16))),
                  TextButton(
                      onPressed: () => _email(context),
                      child: Text('Log in', style: TextStyle(color: context.palette.accent, fontSize: 16))),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _email(BuildContext context, {bool signUp = false}) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => LoginScreen(signUp: signUp)));
    if (ok == true && context.mounted) _signedIn(context);
  }
}

/// Auto-advancing carousel of what people get out of tracking (our own
/// copy), under the headline as on the original's sign-up wall.
class _SocialProof extends StatefulWidget {
  const _SocialProof();
  @override
  State<_SocialProof> createState() => _SocialProofState();
}

class _SocialProofState extends State<_SocialProof> {
  static const quotes = [
    ('"I finally wake up before the alarm feels like a shock."', 'Smart alarm'),
    ('"Seeing my bedtime drift every weekend made me fix it."', 'Statistics'),
    ('"The rain sound has me asleep in ten minutes."', 'Sleep aid'),
  ];
  final _pager = PageController();
  Timer? _t;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_pager.hasClients) return;
      _i = (_i + 1) % quotes.length;
      _pager.animateToPage(_i, duration: const Duration(milliseconds: 500), curve: Curves.easeOut);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        SizedBox(
          height: 96,
          child: PageView(
            controller: _pager,
            onPageChanged: (i) => setState(() => _i = i),
            children: [
              for (final q in quotes)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      for (var k = 0; k < 5; k++) Icon(Icons.star, size: 16, color: context.palette.warn),
                    ]),
                    const SizedBox(height: 8),
                    Text(q.$1, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.35)),
                    const SizedBox(height: 4),
                    Text(q.$2, style: TextStyle(color: context.palette.textMuted, fontSize: 13)),
                  ]),
                ),
            ],
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var k = 0; k < quotes.length; k++)
            Container(
              margin: const EdgeInsets.all(3),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: k == _i ? context.palette.accent : context.palette.textFaint),
            ),
        ]),
      ]);
}

/// The paywall: which variant shows is decided by the server per placement
/// (see lib/paywall). From onboarding, closing or buying enters the app.
class TrialScreen extends StatelessWidget {
  final String placement;
  const TrialScreen({super.key, this.placement = Placement.inApp});
  @override
  Widget build(BuildContext context) => PaywallScreen(placement: placement);
}
