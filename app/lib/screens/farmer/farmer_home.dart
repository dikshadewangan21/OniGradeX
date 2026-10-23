import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api_client.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/gov_ui.dart';

class FarmerHome extends StatefulWidget {
  const FarmerHome({super.key});
  @override
  State<FarmerHome> createState() => _FarmerHomeState();
}

class _FarmerHomeState extends State<FarmerHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();

    return Scaffold(
      backgroundColor: GovColors.background,
      appBar: AppBar(
        title: const Row(
          children: [
            GovEmblemPlaceholder(size: 32),
            SizedBox(width: 10),
            Text('Farmer Quality Passbook', style: TextStyle(fontWeight: FontWeight.w700, color: GovColors.navy)),
          ],
        ),
        actions: [
          const LanguageSwitcherAction(),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout, color: GovColors.error),
            onPressed: s.logout,
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(3),
          child: GovTricolorBar(height: 3),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: GovColors.border)),
        ),
        child: NavigationBar(
          backgroundColor: Colors.white,
          indicatorColor: GovColors.navySurface,
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.receipt_long, color: GovColors.navy),
              label: 'My Certificates',
            ),
            NavigationDestination(
              icon: Icon(Icons.gavel, color: GovColors.navy),
              label: 'Dispute Redressal',
            ),
            NavigationDestination(
              icon: Icon(Icons.notifications_active_outlined, color: GovColors.navy),
              label: 'Notifications',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: GovResponsiveContainer(
              maxWidth: 1000,
              child: Column(
                children: [
                  // Welcome greeting banner
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: Colors.white,
                    child: Row(
                      children: [
                        const Icon(Icons.account_circle, color: GovColors.navy, size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Farmer: ${s.profile?['name'] ?? "Registered Producer"}',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: GovColors.navy),
                              ),
                              Text(
                                'Registered Mobile: ${s.profile?['phone'] ?? ""}',
                                style: const TextStyle(fontSize: 11, color: GovColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: GovColors.greenLight,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: GovColors.green),
                          ),
                          child: const Text('VERIFIED FARMER', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: GovColors.greenDark)),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: switch (_tab) {
                      0 => const _Certificates(),
                      1 => const _Disputes(),
                      _ => const _Notifications(),
                    },
                  ),
                ],
              ),
            ),
          ),
          const GovPortalFooter(compact: true),
        ],
      ),
    );
  }
}

class _Certificates extends StatelessWidget {
  const _Certificates();

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: () => context.read<AppState>().api.listCertificates(),
        builder: (c, data, reload) {
          final items = (data['items'] as List).cast<Map>();
          if (items.isEmpty) {
            return const EmptyView(
              'No quality certificates issued for your phone number yet.\nProvide your mobile number to the Procurement Officer at the mandi.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => reload(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (c, i) {
                final it = items[i];
                final grade = '${it['grade']}';
                final isGradeA = grade.toUpperCase().contains('A');

                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: GovColors.border),
                  ),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isGradeA ? GovColors.greenLight : GovColors.saffronLight,
                        border: Border.all(color: isGradeA ? GovColors.green : GovColors.saffron, width: 1.5),
                      ),
                      child: Center(
                        child: Text(
                          grade.characters.first,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: isGradeA ? GovColors.greenDark : GovColors.saffronDark,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      'Official Grade: $grade · ${it['fresh_pct']}% Fresh',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: GovColors.navy),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Text('Assessment Date: ${it['captured_at']}', style: const TextStyle(fontSize: 11, color: GovColors.textMuted)),
                        if (it['payout_per_kg'] != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Estimated Mandi Payout: ₹${it['payout_per_kg']}/kg (${it['rate_source'] ?? "e-NAM Modal Rate"})',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: GovColors.greenDark),
                          ),
                        ],
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right, color: GovColors.navy),
                    onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => _Detail(cert: Map<String, dynamic>.from(it)))),
                  ),
                ),
              );
              },
            ),
          );
        },
      );
}

class _Detail extends StatefulWidget {
  const _Detail({required this.cert});
  final Map<String, dynamic> cert;
  @override
  State<_Detail> createState() => _DetailState();
}

class _DetailState extends State<_Detail> {
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _dispute() async {
    if (_reason.text.trim().length < 10) {
      toast(context, 'Please describe your dispute reason in detail (at least 10 characters).');
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AppState>().api.raiseDispute(widget.cert['id'] as String, _reason.text.trim());
      if (!mounted) return;
      toast(context, 'Dispute raised. An official re-inspection will be assigned.');
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cert;
    final grade = '${c['grade']}';
    final isGradeA = grade.toUpperCase().contains('A');

    return Scaffold(
      backgroundColor: GovColors.background,
      appBar: AppBar(
        title: const Text('Produce Grading Certificate', style: TextStyle(fontWeight: FontWeight.w700, color: GovColors.navy)),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(3),
          child: GovTricolorBar(height: 3),
        ),
      ),
      body: Column(
        children: [
          const GovTopUtilityBar(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GovCard(
                        title: 'Produce Quality Summary',
                        subtitle: 'Official AI grading results under NAFED standards',
                        icon: Icons.verified_outlined,
                        badge: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isGradeA ? GovColors.greenLight : GovColors.saffronLight,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: isGradeA ? GovColors.green : GovColors.saffron),
                          ),
                          child: Text(
                            'GRADE $grade',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: isGradeA ? GovColors.greenDark : GovColors.saffronDark,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Grade $grade',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: isGradeA ? GovColors.greenDark : GovColors.navy,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${c['onion_count']} sample onions evaluated · ${c['fresh_pct']}% fresh · ${c['defective_pct']}% defective',
                              style: const TextStyle(fontSize: 13, color: GovColors.textSecondary),
                            ),
                            const Divider(height: 20),
                            if (c['details'] is Map) ...[
                              const Text('Defect Breakdown:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: GovColors.navy)),
                              const SizedBox(height: 6),
                              for (final e in (c['details'] as Map).entries)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('${e.key}:', style: const TextStyle(fontSize: 12, color: GovColors.textSecondary)),
                                      Text('${e.value}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: GovColors.navy)),
                                    ],
                                  ),
                                ),
                              const Divider(height: 20),
                            ],
                            if (c['payout_per_kg'] != null) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Estimated Rate:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: GovColors.textMuted)),
                                  Text('₹${c['payout_per_kg']}/kg (${c['rate_source'] ?? "e-NAM"})',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: GovColors.greenDark)),
                                ],
                              ),
                              const SizedBox(height: 6),
                            ],
                            SelectableText('Certificate UUID: ${c['id']}',
                                style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: GovColors.textMuted)),
                          ],
                        ),
                      ),
                      GovCard(
                        title: 'Dispute Redressal / Re-Inspection Request',
                        subtitle: 'File an official dispute if you contest this grading evaluation',
                        icon: Icons.gavel,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Under Mandi Grading Guidelines, you have the right to request a second manual re-inspection by an independent procurement officer.',
                              style: TextStyle(fontSize: 11.5, color: GovColors.textSecondary, height: 1.35),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _reason,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Reason for Disputing Grade / आपत्ति का कारण',
                                hintText: 'Specify defect percentages or scale weight discrepancy observed…',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 14),
                            GovButton(
                              label: 'Submit Formal Dispute Request',
                              icon: Icons.send_outlined,
                              isAccent: true,
                              busy: _busy,
                              onPressed: _dispute,
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
    );
  }
}

class _Disputes extends StatelessWidget {
  const _Disputes();

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: () => context.read<AppState>().api.listDisputes(),
        builder: (c, data, reload) {
          final items = (data['items'] as List).cast<Map>();
          if (items.isEmpty) {
            return const EmptyView('You have not submitted any grading disputes.');
          }
          return RefreshIndicator(
            onRefresh: () async => reload(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (c, i) {
                final it = items[i];
                final status = '${it['status']}'.toUpperCase();
                final isResolved = status == 'UPHELD' || status == 'OVERTURNED';

                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: GovColors.border),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(14),
                    leading: Icon(
                      isResolved ? Icons.check_circle : Icons.pending_actions,
                      color: isResolved ? GovColors.green : GovColors.saffronDark,
                      size: 28,
                    ),
                    title: Row(
                      children: [
                        const Text(
                          'Dispute Status: ',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: GovColors.textMuted),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isResolved ? GovColors.greenLight : GovColors.saffronLight,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: isResolved ? GovColors.green : GovColors.saffron),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: isResolved ? GovColors.greenDark : GovColors.saffronDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 6),
                        Text('Reason: ${it['reason']}', style: const TextStyle(fontSize: 12, color: GovColors.navy)),
                        if (it['resolution_note'] != null) ...[
                          const SizedBox(height: 4),
                          Text('Mandi Admin Note: ${it['resolution_note']}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: GovColors.greenDark)),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      );
}

class _Notifications extends StatelessWidget {
  const _Notifications();

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;

    return Loader<List<dynamic>>(
      load: () => api.notifications(),
      builder: (c, items, reload) {
        if (items.isEmpty) {
          return const EmptyView('No updates or administrative notices at this time.\nNotifications on dispute re-inspections will appear here.');
        }

        return RefreshIndicator(
          onRefresh: () async => reload(),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final n = Map<String, dynamic>.from(items[i] as Map);
              final isRead = n['is_read'] == true;

              return Container(
                decoration: BoxDecoration(
                  color: isRead ? Colors.white : GovColors.navySurface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: isRead ? GovColors.border : GovColors.navy),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  leading: Icon(
                    isRead ? Icons.mark_email_read_outlined : Icons.mark_email_unread,
                    color: isRead ? GovColors.textMuted : GovColors.navy,
                    size: 26,
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${n['title']}',
                          style: TextStyle(
                            fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                            fontSize: 13,
                            color: GovColors.navy,
                          ),
                        ),
                      ),
                      if (!isRead)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: GovColors.saffronLight,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: GovColors.saffron),
                          ),
                          child: const Text('NEW', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: GovColors.saffronDark)),
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        '${n['message']}',
                        style: const TextStyle(fontSize: 11.5, color: GovColors.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${n['created_at']}',
                        style: const TextStyle(fontSize: 10, color: GovColors.textMuted),
                      ),
                    ],
                  ),
                  onTap: isRead
                      ? null
                      : () async {
                          try {
                            await api.markNotificationRead(n['id'] as String);
                            reload();
                          } catch (_) {}
                        },
                ),
              );
            },
          ),
        );
      },
    );
  }
}
