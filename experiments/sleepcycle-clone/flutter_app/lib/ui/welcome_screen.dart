import 'dart:async';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../backend/backend.dart';
import '../backend/billing.dart';
import '../device/notifications.dart';
import '../theme.dart';
import 'login_screen.dart';
import 'main_shell.dart';
import 'widgets/common.dart';

/// After onboarding: account choice (continue with a provider, sign up, or
/// log in), then the free-trial explainer, then the app. Mirrors the
/// original's post-onboarding journey with our own copy; sign-in providers
/// and purchases are mocked.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  Future<void> _signedIn(BuildContext context) async {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TrialScreen()));
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

/// "How your free trial works": a three-step timeline and the plan card with
/// the store's price, Terms and Privacy. The close button skips straight into
/// the free app.
class TrialScreen extends StatefulWidget {
  const TrialScreen({super.key});
  @override
  State<TrialScreen> createState() => _TrialScreenState();
}

class _TrialScreenState extends State<TrialScreen> {
  String? _price;

  @override
  void initState() {
    super.initState();
    Billing.I.price().then((p) {
      if (mounted && p != null) setState(() => _price = p);
    });
  }

  Future<void> _trialStarted() async {
    final now = DateTime.now();
    await Notifications.I.requestPermission();
    await Notifications.I.scheduleTrialReminder(now);
    if (Backend.I.user != null) {
      try {
        await Backend.I.startTrial(Billing.productId);
      } catch (_) {
        // already used on this account, or offline: the store is the source of truth
      }
    }
  }

  static const _terms = 'The subscription renews automatically each year unless you cancel at least 24 hours '
      'before the end of the current period. Cancel any time in your app store account settings. During the free '
      'trial you are not charged; if you cancel before it ends, you keep the free version.';
  static const _privacy = 'Your nights are analysed on your phone. With Online backup on, nights and settings are '
      'stored in your account so you can restore them. Sound clips stay on your phone unless you agree to share '
      'them in Consent and privacy. You can erase your data or your account at any time in Profile › More › Account.';

  void _legal(BuildContext context, String title, String body) => showModalBottomSheet(
        context: context,
        builder: (c) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text(body, style: TextStyle(color: c.palette.textMuted, height: 1.45)),
          ]),
        ),
      );

  void _enter(BuildContext context) {
    AppState.I.finishOnboarding();
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainShell()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    Widget step(IconData icon, String title, String body, {bool last = false}) => IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(children: [
              CircleAvatar(radius: 20, backgroundColor: context.palette.light, child: Icon(icon, color: Colors.white)),
              if (!last) Expanded(child: Container(width: 10, color: context.palette.light)),
            ]),
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(body, style: TextStyle(color: context.palette.textMuted)),
                ]),
              ),
            ),
          ]),
        );
    return Scaffold(
      body: StarryBackground(
        child: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(icon: const Icon(Icons.close), onPressed: () => _enter(context)),
            ),
            const Text('How your free trial works',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 28),
            step(Icons.lock_open, 'Today: full access',
                'Every feature unlocked: smart alarm, sleep aid, programs and statistics.'),
            step(Icons.notifications, 'Day 5: reminder', 'We remind you two days before the trial ends.'),
            step(Icons.star, 'Day 7: trial ends', 'Cancel before then and keep using the free version.', last: true),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.palette.accent),
                color: context.palette.surface,
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('PREMIUM · YEARLY', style: const TextStyle(letterSpacing: 1.1, fontSize: 13)),
                const SizedBox(height: 8),
                const Text('7-day free trial', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(_price == null ? 'then billed yearly · price set by the store' : 'then $_price per year',
                    style: TextStyle(color: context.palette.textMuted)),
              ]),
            ),
            const SizedBox(height: 40),
            PillButton('Try it free', onPressed: () async {
              // Real Play Billing + server verification when the backend is on;
              // until the subscription exists in Play Console, a local trial.
              if (Backend.I.user != null) {
                final err = await Billing.I.startTrial();
                if (err == null) {
                  await _trialStarted();
                  if (context.mounted) _enter(context);
                  return;
                }
                if (context.mounted) toast(context, '$err Starting a local trial.');
              }
              AppState.I.premium = true;
              await _trialStarted();
              if (context.mounted) _enter(context);
            }),
            const SizedBox(height: 12),
            Text('Cancel anytime in your app store subscriptions.',
                textAlign: TextAlign.center, style: TextStyle(color: context.palette.textMuted)),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              TextButton(
                  onPressed: () => _legal(context, 'Terms of use', _terms),
                  child: Text('Terms', style: TextStyle(color: context.palette.accent))),
              Text('·', style: TextStyle(color: context.palette.textMuted)),
              TextButton(
                  onPressed: () => _legal(context, 'Privacy policy', _privacy),
                  child: Text('Privacy', style: TextStyle(color: context.palette.accent))),
              Text('·', style: TextStyle(color: context.palette.textMuted)),
              TextButton(
                  onPressed: () => toast(context, 'Restoring purchases happens automatically when you sign in.'),
                  child: Text('Restore', style: TextStyle(color: context.palette.accent))),
            ]),
          ]),
        ),
      ),
    );
  }
}
