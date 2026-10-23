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

  String _normalizePhone(String raw) {
    var p = raw.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (p.startsWith('+91')) {
      p = p.substring(3);
    } else if (p.startsWith('91') && p.length == 12) {
      p = p.substring(2);
    } else if (p.startsWith('0') && p.length == 11) {
      p = p.substring(1);
    }
    return p;
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final s = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
    });

    final phoneClean = _normalizePhone(_phone.text.trim());
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

  Widget _roleChip({
    required String label,
    required String phone,
    required String password,
    required Color color,
  }) {
    return InkWell(
      onTap: () {
        setState(() {
          _register = false;
          _phone.text = phone;
          _pw.text = password;
          _error = null;
        });
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Mobile: $phone',
              style: const TextStyle(fontSize: 10, color: GovColors.textSecondary, fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = GovBreakpoints.isDesktop(context);
    final cardWidget = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
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
                                    final val = _normalizePhone(v?.trim() ?? '');
                                    if (val.isEmpty) return 'Mobile number is required';
                                    if (!RegExp(r'^[0-9]{10}$').hasMatch(val)) {
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
                        const SizedBox(height: 12),

                        // Authorized Portal Accounts Quick-Fill card
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: GovColors.navySurface,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: GovColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.badge_outlined, size: 16, color: GovColors.navy),
                                  SizedBox(width: 6),
                                  Text(
                                    'Authorized Portal Accounts (Quick Fill)',
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: GovColors.navy),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Tap a role below to automatically fill credentials for instant testing:',
                                style: TextStyle(fontSize: 10.5, color: GovColors.textSecondary),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _roleChip(
                                    label: 'Central Admin',
                                    phone: '9000000001',
                                    password: 'adminpassword123',
                                    color: GovColors.navy,
                                  ),
                                  _roleChip(
                                    label: 'Mandi Officer',
                                    phone: '9000000003',
                                    password: 'officerpassword123',
                                    color: GovColors.saffronDark,
                                  ),
                                  _roleChip(
                                    label: 'Registered Farmer',
                                    phone: '9000000002',
                                    password: 'farmerpassword123',
                                    color: GovColors.greenDark,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

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
                  );

    return Scaffold(
      backgroundColor: GovColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const GovPortalHeader(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isDesktop ? 36 : 16,
                        vertical: isDesktop ? 36 : 20,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: isDesktop ? 1040 : 460),
                          child: isDesktop
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Expanded(child: _GovPortalHero()),
                                    SizedBox(width: 440, child: cardWidget),
                                  ],
                                )
                              : cardWidget,
                        ),
                      ),
                    ),
                    const GovPortalFooter(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GovPortalHero extends StatelessWidget {
  const _GovPortalHero();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 36, top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: GovColors.saffronLight,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0x80FF9933)),
            ),
            child: const Text(
              'DEPARTMENT OF AGRICULTURE & FARMERS WELFARE',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: GovColors.saffronDark, letterSpacing: 0.5),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'National AI Mandi Quality\nAssessment Portal',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: GovColors.navy,
              height: 1.25,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Standardized produce grading under NAFED specifications and e-NAM national market integration (SIH26031).',
            style: TextStyle(fontSize: 13.5, color: GovColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 28),
          const _HeroFeature(
            icon: Icons.offline_bolt_outlined,
            title: 'On-Device Edge AI',
            desc: 'Real-time TFLite computer vision without network dependency at APMC mandis.',
          ),
          const SizedBox(height: 16),
          const _HeroFeature(
            icon: Icons.verified_user_outlined,
            title: 'Tamper-Evident SHA-256',
            desc: 'Cryptographically hashed produce batches with central server digital signatures.',
          ),
          const SizedBox(height: 16),
          const _HeroFeature(
            icon: Icons.currency_rupee,
            title: 'Fair e-NAM Mandi Payouts',
            desc: 'Real-time Agmarknet modal rate calculation based on certified fresh percentage.',
          ),
        ],
      ),
    );
  }
}

class _HeroFeature extends StatelessWidget {
  const _HeroFeature({required this.icon, required this.title, required this.desc});
  final IconData icon;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: GovColors.navySurface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: GovColors.border),
          ),
          child: Icon(icon, color: GovColors.navy, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: GovColors.navy)),
              const SizedBox(height: 2),
              Text(desc, style: const TextStyle(fontSize: 11.5, color: GovColors.textMuted, height: 1.35)),
            ],
          ),
        ),
      ],
    );
  }
}
