import 'package:flutter/material.dart';
import '../app_state.dart';
import '../backend/backend.dart';
import '../theme.dart';
import 'widgets/common.dart';

/// Email sign-up / log-in. With the backend on this is Firebase Auth and the
/// account's data is pulled from Firestore afterwards; with it off (local-only
/// builds) the email is just remembered on the device.
class LoginScreen extends StatefulWidget {
  final bool signUp;
  const LoginScreen({super.key, this.signUp = false});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    final email = _email.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (Backend.I.enabled) {
        widget.signUp
            ? await Backend.I.signUp(email, _password.text)
            : await Backend.I.signIn(email, _password.text);
        await AppState.I.syncFromCloud();
      } else {
        AppState.I.email = email;
      }
      if (mounted) Navigator.pop(context, true);
    } on BackendException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.signUp ? 'Create account' : 'Log in';
    return SettingsPage(title: title, children: [
      Padding(
        padding: const EdgeInsets.all(24),
        child: AutofillGroup(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
              autofillHints: [widget.signUp ? AutofillHints.newPassword : AutofillHints.password],
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 20),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: TextStyle(color: context.palette.awake)),
              ),
            if (!Backend.I.enabled)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('Offline build: your nights stay on this device.',
                    style: TextStyle(color: context.palette.textMuted)),
              ),
            _busy
                ? Center(child: CircularProgressIndicator(color: context.palette.accent))
                : PillButton(title, onPressed: _submit),
          ]),
        ),
      ),
    ]);
  }
}
