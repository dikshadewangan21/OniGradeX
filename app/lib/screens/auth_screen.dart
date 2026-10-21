import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/gov_ui.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _name = TextEditingController();
  final _pw = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _obscurePw = true;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final s = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
    });

    final phoneClean = _phone.text.trim();
    final pwClean = _pw.text;

    try {
      if (_register) {
        await s.api.register(phoneClean, _name.text.trim(), pwClean);
        if (mounted) {
          toast(context, 'Farmer account registered successfully. Signing in…');
        }
      }
      await s.login(phoneClean, pwClean);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GovColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const GovPortalHeader(),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GovCard(
                          title: _register ? 'Farmer Registration Portal' : 'Official Portal Sign-In',
                          subtitle: _register
                              ? 'Self-registration for APMC farmers to view digital grading certificates'
                              : 'Authorized access for Mandi Officers, Admins & Registered Farmers',
                          icon: _register ? Icons.person_add_alt_1 : Icons.lock_outline,
                          padding: const EdgeInsets.all(22),
                          child: Form(
                            key: _form,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Official portal badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: GovColors.saffronLight,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0x66FF9933)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.verified_user_outlined, size: 16, color: GovColors.saffronDark),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _register
                                              ? 'Farmer Onboarding • Instant Quality Passbooks'
                                              : 'Secure Mandi Gateway • GIGW Standard Compliant',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: GovColors.saffronDark,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 18),

                                // Phone number field
                                const Text(
                                  'Registered Mobile Number / मोबाइल नंबर',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: GovColors.navy),
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _phone,
                                  keyboardType: TextInputType.phone,
                                  decoration: InputDecoration(
                                    hintText: '10-digit mobile number (e.g. 9876543210)',
                                    prefixIcon: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: const BoxDecoration(
                                        color: GovColors.navySurface,
                                        border: Border(right: BorderSide(color: GovColors.border)),
                                      ),
                                      child: const Text(
                                        '+91',
                                        style: TextStyle(fontWeight: FontWeight.w700, color: GovColors.navy, fontSize: 13),
                                      ),
                                    ),
                                    border: const OutlineInputBorder(),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                  ),
                                  validator: (v) {
                                    final val = v?.trim() ?? '';
                                    if (val.isEmpty) return 'Mobile number is required';
                                    if (!RegExp(r'^\+?[0-9]{10,15}$').hasMatch(val)) {
                                      return 'Enter valid 10-digit mobile number';
                                    }
                                    return null;
                                  },
                                ),

                                if (_register) ...[
                                  const SizedBox(height: 14),
                                  const Text(
                                    'Farmer Full Name / किसान का पूरा नाम',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: GovColors.navy),
                                  ),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller: _name,
                                    decoration: const InputDecoration(
                                      hintText: 'As per Aadhaar or Mandi Passbook',
                                      prefixIcon: Icon(Icons.person_outline, color: GovColors.navy),
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                    ),
                                    validator: (v) {
                                      final val = v?.trim() ?? '';
                                      if (val.length < 2) return 'Enter your official name (min 2 characters)';
                                      return null;
                                    },
                                  ),
                                ],

                                const SizedBox(height: 14),
                                const Text(
                                  'Security Password / पासवर्ड',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: GovColors.navy),
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _pw,
                                  obscureText: _obscurePw,
                                  decoration: InputDecoration(
                                    hintText: 'Enter account password (min. 8 characters)',
                                    prefixIcon: const Icon(Icons.lock_outline, color: GovColors.navy),
                                    suffixIcon: IconButton(
                                      icon: Icon(_obscurePw ? Icons.visibility_off : Icons.visibility, color: GovColors.textMuted, size: 20),
                                      onPressed: () => setState(() => _obscurePw = !_obscurePw),
                                      tooltip: _obscurePw ? 'Show password' : 'Hide password',
                                    ),
                                    border: const OutlineInputBorder(),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                  ),
                                  validator: (v) {
                                    if ((v?.length ?? 0) < 8) return 'Password must be at least 8 characters';
                                    return null;
                                  },
                                ),

                                // Error display box
                                if (_error != null) ...[
                                  const SizedBox(height: 16),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: GovColors.errorLight,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: const Color(0x80B91C1C)),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.error_outline, size: 18, color: GovColors.error),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Authentication Alert',
                                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: GovColors.error),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _error!,
                                                style: const TextStyle(fontSize: 12, color: GovColors.error),
                                              ),
                                              if (_error!.contains('Cannot connect') || _error!.contains('server')) ...[
                                                const SizedBox(height: 6),
                                                InkWell(
                                                  onTap: () => showDialog(
                                                    context: context,
                                                    builder: (_) => const GovServerConfigDialog(),
                                                  ),
                                                  child: const Text(
                                                    'Verify Mandi Gateway Server Settings →',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w700,
                                                      color: GovColors.navy,
                                                      decoration: TextDecoration.underline,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 20),
                                GovButton(
                                  label: _register ? 'Complete Farmer Registration' : 'Sign In to Mandi Portal',
                                  icon: _register ? Icons.how_to_reg : Icons.login,
                                  busy: _busy,
                                  onPressed: _submit,
                                ),

                                const SizedBox(height: 12),
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: GovColors.navy,
                                    side: const BorderSide(color: GovColors.border),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  onPressed: _busy
                                      ? null
                                      : () => setState(() {
                                            _register = !_register;
                                            _phone.clear();
                                            _name.clear();
                                            _pw.clear();
                                            _error = null;
                                          }),
                                  child: Text(
                                    _register ? 'Already registered? Return to Sign-In' : 'New Farmer? Register for Mandi Grading',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Official security notice card
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: GovColors.border),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline, size: 16, color: GovColors.textMuted),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Procurement Officers and Mandi Administrators: Accounts are provisioned centrally by your State Agricultural Board. Self-registration is restricted to Farmers under APMC regulations.',
                                  style: TextStyle(fontSize: 10.5, color: GovColors.textSecondary, height: 1.35),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const GovPortalFooter(),
          ],
        ),
      ),
    );
  }
}
