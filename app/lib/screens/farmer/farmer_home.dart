import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api_client.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

class FarmerHome extends StatefulWidget {
  const FarmerHome({super.key});
  @override
  State<FarmerHome> createState() => _FarmerHomeState();
}

class _FarmerHomeState extends State<FarmerHome> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('My onions'), actions: [
          IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: context.read<AppState>().logout),
        ]),
        body: _tab == 0 ? const _Certificates() : const _Disputes(),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Certificates'),
            NavigationDestination(icon: Icon(Icons.gavel), label: 'Disputes'),
          ],
        ),
      );
}

class _Certificates extends StatelessWidget {
  const _Certificates();
  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: () => context.read<AppState>().api.listCertificates(),
        builder: (c, data, reload) {
          final items = (data['items'] as List).cast<Map>();
          if (items.isEmpty) {
            return const EmptyView('No certificates yet. Ask the officer to enter your phone number when grading.');
          }
          return RefreshIndicator(
            onRefresh: () async => reload(),
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (c, i) {
                final it = items[i];
                return ListTile(
                  leading: CircleAvatar(child: Text('${it['grade']}'.characters.first)),
                  title: Text('${it['grade']} · ${it['fresh_pct']}% fresh'),
                  subtitle: Text('${it['captured_at']}${it['payout_per_kg'] != null ? '\nPayout ₹${it['payout_per_kg']}/kg' : ''}'),
                  isThreeLine: it['payout_per_kg'] != null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => _Detail(cert: Map<String, dynamic>.from(it)))),
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

  Future<void> _dispute() async {
    if (_reason.text.trim().length < 10) {
      toast(context, 'Please describe the problem (at least 10 characters).');
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AppState>().api.raiseDispute(widget.cert['id'] as String, _reason.text.trim());
      if (!mounted) return;
      toast(context, 'Dispute raised. An admin will arrange re-inspection.');
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
    return Scaffold(
      appBar: AppBar(title: const Text('Certificate')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Grade ${c['grade']}', style: Theme.of(context).textTheme.headlineMedium),
        Text('${c['onion_count']} onions · ${c['fresh_pct']}% fresh · ${c['defective_pct']}% defective'),
        for (final e in (c['details'] as Map).entries) Text('${e.key}: ${e.value}%'),
        if (c['payout_per_kg'] != null) Text('Payout: ₹${c['payout_per_kg']}/kg (${c['rate_source']})'),
        Text('ID: ${c['id']}', style: const TextStyle(fontSize: 12)),
        const Divider(height: 32),
        Text('Disagree with this grade?', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _reason,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'What is wrong?', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        BusyButton(label: 'Raise dispute', busy: _busy, onPressed: _dispute),
      ]),
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
          if (items.isEmpty) return const EmptyView('You have not raised any disputes.');
          return RefreshIndicator(
            onRefresh: () async => reload(),
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (c, i) => ListTile(
                title: Text('${items[i]['status']}'.toUpperCase()),
                subtitle: Text('${items[i]['reason']}${items[i]['resolution_note'] != null ? '\nAdmin: ${items[i]['resolution_note']}' : ''}'),
                isThreeLine: true,
              ),
            ),
          );
        },
      );
}
