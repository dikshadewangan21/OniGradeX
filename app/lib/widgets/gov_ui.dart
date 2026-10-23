import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../state/app_state.dart';

/// Professional Indian Government Website UI Palette & Styles
/// Aligned with Guidelines for Indian Government Websites (GIGW).
class GovColors {
  // Official Deep Navy / Government Blue
  static const Color navy = Color(0xFF0B2545);
  static const Color navyDark = Color(0xFF061727);
  static const Color navyLight = Color(0xFF133E87);
  static const Color navySurface = Color(0xFFF0F4F8);

  // Subtle National Saffron & Green accents
  static const Color saffron = Color(0xFFFF9933);
  static const Color saffronDark = Color(0xFFD97706);
  static const Color saffronLight = Color(0xFFFFF7ED);
  static const Color green = Color(0xFF138808);
  static const Color greenDark = Color(0xFF0D5E06);
  static const Color greenLight = Color(0xFFF0FDF4);

  // Clean, high-contrast surfaces & typography
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFCBD5E1);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF334155);
  static const Color textMuted = Color(0xFF64748B);
  static const Color error = Color(0xFFB91C1C);
  static const Color errorLight = Color(0xFFFEF2F2);
}

/// Official Indian Tricolor hairline banner strip (Saffron, White, Green)
class GovTricolorBar extends StatelessWidget {
  const GovTricolorBar({super.key, this.height = 3.0});
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const Row(
        children: [
          Expanded(child: ColoredBox(color: GovColors.saffron)),
          Expanded(child: ColoredBox(color: Colors.white)),
          Expanded(child: ColoredBox(color: GovColors.green)),
        ],
      ),
    );
  }
}

/// Authorized Department Seal / Emblem Placeholder
/// Uses dignified agricultural wheat & gear motif with no fake protected state emblems.
class GovEmblemPlaceholder extends StatelessWidget {
  const GovEmblemPlaceholder({super.key, this.size = 46});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: GovColors.navy, width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Center(
        child: Container(
          width: size - 8,
          height: size - 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: GovColors.saffron, width: 1.2),
            color: GovColors.navySurface,
          ),
          child: Icon(
            Icons.eco_rounded,
            size: size * 0.55,
            color: GovColors.navy,
          ),
        ),
      ),
    );
  }
}

/// Responsive Breakpoint Helper for phone, tablet, and desktop viewports
class GovBreakpoints {
  static bool isMobile(BuildContext context) => MediaQuery.sizeOf(context).width < 600;
  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 600 && MediaQuery.sizeOf(context).width < 960;
  static bool isDesktop(BuildContext context) => MediaQuery.sizeOf(context).width >= 960;
  static double width(BuildContext context) => MediaQuery.sizeOf(context).width;
}

/// Centers content with a responsive maximum width suitable for desktop/tablet
class GovResponsiveContainer extends StatelessWidget {
  const GovResponsiveContainer({
    super.key,
    required this.child,
    this.maxWidth = 1100,
    this.padding,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: padding != null ? Padding(padding: padding!, child: child) : child,
      ),
    );
  }
}

/// Top Utility Bar seen on official Indian government web portals (NIC style)
class GovTopUtilityBar extends StatelessWidget {
  const GovTopUtilityBar({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final isNarrow = MediaQuery.sizeOf(context).width < 520;
    return Container(
      color: GovColors.navyDark,
      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 10 : 16, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: GovColors.saffron, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              isNarrow
                  ? 'भारत सरकार | GOI • Mandi Portal'
                  : 'भारत सरकार | Government of India • National Mandi Assessment Gateway',
              style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Server status pill
          InkWell(
            onTap: () => showDialog(context: context, builder: (_) => const GovServerConfigDialog()),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.dns_outlined, color: Colors.white70, size: 12),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: isNarrow ? 80 : 130),
                    child: Text(
                      AppConfig.apiBaseUrl,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Language selector
          PopupMenuButton<String>(
            tooltip: 'Language / भाषा',
            icon: const Icon(Icons.translate, color: Colors.white70, size: 14),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onSelected: (code) => s.setLocale(Locale(code)),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'en', child: Text('English', style: TextStyle(fontSize: 13))),
              PopupMenuItem(value: 'hi', child: Text('हिंदी (Hindi)', style: TextStyle(fontSize: 13))),
              PopupMenuItem(value: 'mr', child: Text('मराठी (Marathi)', style: TextStyle(fontSize: 13))),
            ],
          ),
        ],
      ),
    );
  }
}

/// Official Department Header Bar
class GovPortalHeader extends StatelessWidget {
  const GovPortalHeader({super.key, this.showBack = false, this.actions});
  final bool showBack;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final isMobile = GovBreakpoints.isMobile(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const GovTopUtilityBar(),
        const GovTricolorBar(height: 3),
        Container(
          color: Colors.white,
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: isMobile ? 10 : 14),
          child: Row(
            children: [
              if (showBack && Navigator.of(context).canPop()) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: GovColors.navy),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Go back',
                ),
                const SizedBox(width: 4),
              ],
              GovEmblemPlaceholder(size: isMobile ? 38 : 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'कृषि एवं किसान कल्याण विभाग | Department of Agriculture & Farmers Welfare',
                      style: TextStyle(
                        fontSize: isMobile ? 9 : 10.5,
                        fontWeight: FontWeight.w600,
                        color: GovColors.textMuted,
                        letterSpacing: 0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'OniGrader — National Mandi Quality Portal',
                      style: TextStyle(
                        fontSize: isMobile ? 14 : 17,
                        fontWeight: FontWeight.w800,
                        color: GovColors.navy,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'NAFED Grading & e-NAM Quality Standard Compliance (SIH26031)',
                      style: TextStyle(
                        fontSize: isMobile ? 9.5 : 11,
                        color: GovColors.saffronDark,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (s.session != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: GovColors.navySurface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: GovColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        s.role == 'admin'
                            ? Icons.admin_panel_settings
                            : s.role == 'officer'
                                ? Icons.badge
                                : Icons.agriculture,
                        size: 14,
                        color: GovColors.navy,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        s.role.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: GovColors.navy,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.logout, color: GovColors.error, size: 20),
                  tooltip: 'Sign out',
                  onPressed: () => s.logout(),
                ),
              ],
              if (actions != null) ...actions!,
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: GovColors.border),
      ],
    );
  }
}

/// Official Government Portal Footer
class GovPortalFooter extends StatelessWidget {
  const GovPortalFooter({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Container(
        color: GovColors.navy,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GovTricolorBar(height: 2),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.verified_user_outlined, size: 14, color: GovColors.saffron),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'OniGrader Portal • NAFED / e-NAM Standard Compliant',
                      style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    'SIH26031',
                    style: TextStyle(color: GovColors.saffronLight, fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const GovTricolorBar(height: 3),
        Container(
          color: GovColors.navy,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 24,
                runSpacing: 16,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'OniGrader — National Mandi Quality Portal',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'An offline-first, on-device AI quality assessment platform designed for APMC mandis, procurement officers, and farmers under NAFED grading specifications.',
                          style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Compliance & Governance', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                        SizedBox(height: 6),
                        Text('• Tamper-Evident SHA-256 Certificates\n• Server-Signed Verification\n• GIGW Accessibility Compliant\n• e-NAM Interoperable Schema',
                            style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4)),
                      ],
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Technical Helpdesk', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                        SizedBox(height: 6),
                        Text('Toll-Free: 1800-XXX-XXXX (Toll Free)\nMandi Cell: helpdesk-onigrader@gov.in\nVersion 1.0.0 (Production Build)',
                            style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(color: Colors.white24, height: 1),
              const SizedBox(height: 12),
              const Text(
                '© 2026 Mandi Produce Quality Assessment System. Developed for SIH26031. All official guidelines and trademarks belong to their respective authorities.',
                style: TextStyle(color: Colors.white54, fontSize: 10, height: 1.3),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Official Structured Government Card
class GovCard extends StatelessWidget {
  const GovCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.icon,
    this.badge,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final Widget? badge;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: GovColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: GovColors.navySurface,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(5), topRight: Radius.circular(5)),
                  border: Border(bottom: BorderSide(color: GovColors.border)),
                ),
                child: Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 18, color: GovColors.navy),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title!,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: GovColors.navy,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              style: const TextStyle(fontSize: 11, color: GovColors.textMuted),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (badge != null) badge!,
                  ],
                ),
              ),
            ],
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

/// Official High-Contrast Action Button
class GovButton extends StatelessWidget {
  const GovButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.isSecondary = false,
    this.isAccent = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final bool isSecondary;
  final bool isAccent;

  @override
  Widget build(BuildContext context) {
    final bgColor = isSecondary
        ? Colors.white
        : isAccent
            ? GovColors.saffronDark
            : GovColors.navy;
    final fgColor = isSecondary ? GovColors.navy : Colors.white;
    final borderSide = isSecondary
        ? const BorderSide(color: GovColors.navy, width: 1.5)
        : BorderSide.none;

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: bgColor,
        foregroundColor: fgColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: borderSide,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
      onPressed: busy ? null : onPressed,
      child: busy
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(fgColor),
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: fgColor),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: fgColor,
                  ),
                ),
              ],
            ),
    );
  }
}

/// Official Endpoint Configuration Dialog
class GovServerConfigDialog extends StatefulWidget {
  const GovServerConfigDialog({super.key});

  @override
  State<GovServerConfigDialog> createState() => _GovServerConfigDialogState();
}

class _GovServerConfigDialogState extends State<GovServerConfigDialog> {
  late final TextEditingController _ctrl;
  bool _testing = false;
  String? _status;
  bool? _success;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: AppConfig.apiBaseUrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _status = 'Connecting to ${_ctrl.text.trim()}…';
      _success = null;
    });
    final s = context.read<AppState>();
    try {
      final healthy = await s.api.checkHealth();
      setState(() {
        _testing = false;
        _success = healthy;
        _status = healthy ? 'Gateway online and reachable (HTTP 200).' : 'Server responded with non-200 status.';
      });
    } catch (e) {
      setState(() {
        _testing = false;
        _success = false;
        _status = 'Connection failed: ${e.toString()}';
      });
    }
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    await s.setServerUrl(_ctrl.text.trim());
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      title: const Row(
        children: [
          Icon(Icons.dns, color: GovColors.navy, size: 22),
          SizedBox(width: 8),
          Text('Mandi Gateway Configuration', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: GovColors.navy)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Specify the backend endpoint for the Mandi authentication and certificate verification gateway.',
              style: TextStyle(fontSize: 12, color: GovColors.textSecondary),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _ctrl,
              decoration: const InputDecoration(
                labelText: 'Server Gateway URL',
                hintText: 'http://127.0.0.1:8000',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [
                ActionChip(
                  label: const Text('Local (127.0.0.1)', style: TextStyle(fontSize: 11)),
                  onPressed: () => _ctrl.text = 'http://127.0.0.1:8000',
                ),
                ActionChip(
                  label: const Text('Emulator (10.0.2.2)', style: TextStyle(fontSize: 11)),
                  onPressed: () => _ctrl.text = 'http://10.0.2.2:8000',
                ),
              ],
            ),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _success == true ? GovColors.greenLight : GovColors.errorLight,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _success == true ? GovColors.green : GovColors.error),
                ),
                child: Row(
                  children: [
                    Icon(
                      _success == true ? Icons.check_circle : Icons.error_outline,
                      size: 16,
                      color: _success == true ? GovColors.green : GovColors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _status!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _success == true ? GovColors.greenDark : GovColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _testing ? null : _testConnection,
          child: _testing ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Test Connection'),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: GovColors.navy, foregroundColor: Colors.white),
          onPressed: _save,
          child: const Text('Save & Apply'),
        ),
      ],
    );
  }
}
