import 'package:flutter/material.dart';
import '../app_state.dart';
import '../data/api_client.dart';
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
              child: const Icon(Icons.nightlight_round, size: 64, color: Color(0xFF0F2B3A)),
            ),
            const SizedBox(height: 28),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text('Better mornings start with understanding your nights',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 24, height: 1.3)),
            ),
            const Spacer(flex: 2),
            Container(
              color: const Color(0xFF071620),
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
                    onPressed: () => _signedIn(context),
                    icon: const Icon(Icons.account_circle),
                    label: const Text('Continue with Google', style: TextStyle(fontSize: 17)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  TextButton(onPressed: () => _email(context), child: const Text('Sign up with email', style: TextStyle(color: AppTheme.accent, fontSize: 16))),
                  TextButton(onPressed: () => _email(context), child: const Text('Log in', style: TextStyle(color: AppTheme.accent, fontSize: 16))),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _email(BuildContext context) async {
    final ok = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => LoginScreen(api: SleepApi())));
    if (ok == true && context.mounted) _signedIn(context);
  }
}

/// "How your free trial works": a three-step timeline and the plan card.
/// The close button skips straight into the free app.
class TrialScreen extends StatelessWidget {
  const TrialScreen({super.key});

  void _enter(BuildContext context) => Navigator.pushAndRemoveUntil(
      context, MaterialPageRoute(builder: (_) => const MainShell()), (_) => false);

  @override
  Widget build(BuildContext context) {
    Widget step(IconData icon, String title, String body, {bool last = false}) => IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(children: [
              CircleAvatar(radius: 20, backgroundColor: const Color(0xFF2C8FB0), child: Icon(icon, color: Colors.white)),
              if (!last) Expanded(child: Container(width: 10, color: const Color(0xFF2C8FB0))),
            ]),
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(body, style: const TextStyle(color: Colors.white70)),
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
            step(Icons.lock_open, 'Today: full access', 'Every feature unlocked: smart alarm, sleep aid, programs and statistics.'),
            step(Icons.notifications, 'Day 5: reminder', 'We remind you two days before the trial ends.'),
            step(Icons.star, 'Day 7: trial ends', 'Cancel before then and keep using the free version.', last: true),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.accent),
                color: const Color(0x2215A0C0),
              ),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('PREMIUM · YEARLY', style: TextStyle(letterSpacing: 1.1, fontSize: 13)),
                SizedBox(height: 8),
                Text('7-day free trial', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                SizedBox(height: 8),
                Text('then billed yearly · price set by the store', style: TextStyle(color: Colors.white70)),
              ]),
            ),
            const SizedBox(height: 40),
            PillButton('Try it free', onPressed: () {
              // Purchase is mocked: a real build calls Play Billing / StoreKit.
              AppState.I.premium = true;
              _enter(context);
            }),
            const SizedBox(height: 12),
            const Text('Cancel anytime in your app store subscriptions.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
          ]),
        ),
      ),
    );
  }
}
