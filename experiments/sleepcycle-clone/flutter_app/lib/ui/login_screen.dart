import 'package:flutter/material.dart';
import '../app_state.dart';
import '../data/api_client.dart';

/// Email/password sign-in against the mock identity endpoint. The real backend
/// would be Ory Kratos (self-service login) returning a session token.
class LoginScreen extends StatefulWidget {
  final SleepApi api;
  const LoginScreen({super.key, required this.api});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController(text: 'demo@example.com');
  final _password = TextEditingController(text: 'password');
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      await widget.api.login(_email.text.trim(), _password.text);
      AppState.I.email = _email.text.trim();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // Prototype: the mock backend (../mock-api) is optional. If it isn't
      // running, continue signed in locally so the journey can be explored.
      AppState.I.email = _email.text.trim();
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}
