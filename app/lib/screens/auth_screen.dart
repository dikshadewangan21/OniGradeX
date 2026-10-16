import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/common.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController(), _name = TextEditingController(), _pw = TextEditingController();
  bool _register = false, _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final s = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await s.api.register(_phone.text.trim(), _name.text.trim(), _pw.text);
        if (mounted) toast(context, 'Account created. Signing you in…');
      }
      await s.login(_phone.text.trim(), _pw.text);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, actions: const [LanguageSwitcherAction()]),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Form(
                  key: _form,
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('OniGrader', style: Theme.of(context).textTheme.headlineLarge, textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    Text(_register ? 'Farmer sign-up' : 'Sign in', textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Phone number', border: OutlineInputBorder()),
                      validator: (v) => RegExp(r'^\+?[0-9]{10,15}$').hasMatch(v?.trim() ?? '') ? null : 'Enter 10–15 digits',
                    ),
                    if (_register) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder()),
                        validator: (v) => (v?.trim().length ?? 0) >= 2 ? null : 'Required',
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _pw,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                      validator: (v) => (v?.length ?? 0) >= 8 ? null : 'At least 8 characters',
                    ),
                    if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                    const SizedBox(height: 20),
                    BusyButton(label: _register ? 'Create account' : 'Sign in', busy: _busy, onPressed: _submit),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _register = !_register;
                                _phone.clear();
                                _name.clear();
                                _pw.clear();
                                _error = null;
                              }),
                      child: Text(_register ? 'I already have an account' : 'Farmer? Create an account'),
                    ),
                    const Text('Officer and admin accounts are issued by your administrator.', textAlign: TextAlign.center),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}
