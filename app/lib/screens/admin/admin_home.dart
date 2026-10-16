import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api_client.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) {
    const pages = [_Overview(), _DisputeQueue(), _Rules(), _Setup()];
    return Scaffold(
      appBar: AppBar(title: const Text('Central admin'), actions: [
        IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: context.read<AppState>().logout),
      ]),
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.insights), label: 'Overview'),
          NavigationDestination(icon: Icon(Icons.gavel), label: 'Disputes'),
          NavigationDestination(icon: Icon(Icons.rule), label: 'Rules'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Setup'),
        ],
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview();
  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;
    return Loader<List<dynamic>>(
      load: () async => [await api.summary(), await api.flags(), await api.stockHealth(), await api.trends()],
      builder: (c, d, reload) {
        final sum = d[0] as Map, flags = d[1] as Map, stock = d[2] as Map, trends = d[3] as List;
        if ((sum['total_certificates'] as int) == 0) return const EmptyView('No certificates have been synced yet.');
        return RefreshIndicator(
          onRefresh: () async => reload(),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text('${sum['total_certificates']} certificates · avg ${sum['avg_fresh_pct']}% fresh'),
            Text('Open disputes: ${sum['open_disputes']} · Weight mismatches: ${sum['weight_mismatches']}'),
            const SizedBox(height: 12),
            Text('By grade', style: Theme.of(context).textTheme.titleMedium),
            for (final e in (sum['by_grade'] as Map).entries) Text('${e.key}: ${e.value}'),
            const SizedBox(height: 12),
            Text('By mandi', style: Theme.of(context).textTheme.titleMedium),
            for (final m in (sum['by_mandi'] as List)) Text('${m['mandi'] ?? 'Unassigned'}: ${m['certificates']} · ${m['avg_fresh_pct']}% fresh'),
            const SizedBox(height: 12),
            Text('Officer alerts', style: Theme.of(context).textTheme.titleMedium),
            if ((flags['flags'] as List).isEmpty) Text(flags['note'] ?? 'No officers currently flagged.'),
            for (final f in (flags['flags'] as List)) ListTile(leading: const Icon(Icons.flag), title: Text('${f['officer']} (${f['certificates']} certs)'), subtitle: Text((f['reasons'] as List).join('\n'))),
            const SizedBox(height: 12),
            Text('Stock health (shortest shelf-life first)', style: Theme.of(context).textTheme.titleMedium),
            if ((stock['items'] as List).isEmpty) Text(stock['note'] ?? 'None'),
            for (final s in (stock['items'] as List).take(10)) Text('${s['shelf_life_days']} days · grade ${s['grade']} · ${s['certificate_id']}'),
            const SizedBox(height: 12),
            Text('Last 30 days', style: Theme.of(context).textTheme.titleMedium),
            for (final t in trends) Text('${t['date']}: ${t['count']} batches, ${t['avg_fresh_pct']}% fresh'),
          ]),
        );
      },
    );
  }
}

class _DisputeQueue extends StatelessWidget {
  const _DisputeQueue();
  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;
    return Loader<Map<String, dynamic>>(
      load: () => api.listDisputes(),
      builder: (c, data, reload) {
        final items = (data['items'] as List).cast<Map>();
        if (items.isEmpty) return const EmptyView('No disputes.');
        return RefreshIndicator(
          onRefresh: () async => reload(),
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (c, i) {
              final d = items[i];
              final open = d['status'] == 'open' || d['status'] == 'reinspection';
              return ListTile(
                title: Text('${d['status']}'.toUpperCase() + ' · cert ${d['certificate_id']}'.substring(0, 20)),
                subtitle: Text('${d['reason']}${d['resolution_note'] != null ? '\nResolution: ${d['resolution_note']}' : ''}'),
                isThreeLine: true,
                trailing: open ? const Icon(Icons.edit_note) : null,
                onTap: open ? () => _resolve(c, api, d, reload) : null,
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _resolve(BuildContext context, ApiClient api, Map d, VoidCallback reload) async {
    final note = TextEditingController();
    String status = 'upheld';
    await showDialog(
      context: context,
      builder: (dc) => StatefulBuilder(
        builder: (dc, set) => AlertDialog(
          title: const Text('Resolve dispute'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButton<String>(
              value: status,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'reinspection', child: Text('Send for re-inspection')),
                DropdownMenuItem(value: 'upheld', child: Text('Uphold original grade')),
                DropdownMenuItem(value: 'overturned', child: Text('Overturn grade')),
              ],
              onChanged: (v) => set(() => status = v!),
            ),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (required)'), maxLines: 3),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dc), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                try {
                  await api.resolveDispute(d['id'] as String, status, note.text.trim());
                  if (dc.mounted) Navigator.pop(dc);
                  reload();
                } on ApiException catch (e) {
                  if (dc.mounted) toast(dc, e.message);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Edits the active grading rule as JSON; the server validates it (RuleDefinition schema).
class _Rules extends StatelessWidget {
  const _Rules();
  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;
    return Loader<List<dynamic>>(
      load: () => api.listRules(),
      builder: (c, rules, reload) => ListView(padding: const EdgeInsets.all(16), children: [
        FilledButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Publish new rule version'),
          onPressed: () => _edit(context, api, rules.isEmpty ? null : rules.first as Map, reload),
        ),
        const SizedBox(height: 12),
        if (rules.isEmpty) const Text('No rules published yet. Officers cannot grade until you publish one.'),
        for (final r in rules)
          ListTile(
            title: Text('v${r['version']}${r['is_active'] == true ? '  (active)' : ''}'),
            subtitle: Text(const JsonEncoder.withIndent(' ').convert(r['definition'])),
          ),
      ]),
    );
  }

  Future<void> _edit(BuildContext context, ApiClient api, Map? current, VoidCallback reload) async {
    final tmpl = current?['definition'] ??
        {
          'min_confidence': 0.0,
          'reject_grade': 'Rejected',
          'grades': [
            {'grade': 'TOP_GRADE_NAME', 'max_defective_pct': 0.0}
          ]
        };
    final ctl = TextEditingController(text: const JsonEncoder.withIndent('  ').convert(tmpl));
    await showDialog(
      context: context,
      builder: (dc) => AlertDialog(
        title: const Text('New rule version'),
        content: SizedBox(width: 400, child: TextField(controller: ctl, maxLines: 14, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dc), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              try {
                await api.publishRule(Map<String, dynamic>.from(jsonDecode(ctl.text) as Map));
                if (dc.mounted) Navigator.pop(dc);
                reload();
              } on FormatException {
                if (dc.mounted) toast(dc, 'Not valid JSON');
              } on ApiException catch (e) {
                if (dc.mounted) toast(dc, e.message);
              }
            },
            child: const Text('Publish'),
          ),
        ],
      ),
    );
  }
}

class _Setup extends StatefulWidget {
  const _Setup();
  @override
  State<_Setup> createState() => _SetupState();
}

class _SetupState extends State<_Setup> {
  final _mName = TextEditingController(), _mState = TextEditingController(), _mDist = TextEditingController();
  final _uPhone = TextEditingController(), _uName = TextEditingController(), _uPw = TextEditingController();
  String _role = 'officer';
  String? _mandiId;
  List<dynamic> _mandis = [];

  @override
  void initState() {
    super.initState();
    _loadMandis();
  }

  Future<void> _loadMandis() async {
    try {
      final m = await context.read<AppState>().api.mandis();
      if (mounted) setState(() => _mandis = m);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _run(Future<void> Function() f, String ok) async {
    try {
      await f();
      if (mounted) toast(context, ok);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Add mandi', style: Theme.of(context).textTheme.titleMedium),
      TextField(controller: _mName, decoration: const InputDecoration(labelText: 'Name')),
      TextField(controller: _mState, decoration: const InputDecoration(labelText: 'State')),
      TextField(controller: _mDist, decoration: const InputDecoration(labelText: 'District')),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: () => _run(() async {
          await api.createMandi(_mName.text.trim(), _mState.text.trim(), _mDist.text.trim());
          await _loadMandis();
        }, 'Mandi added'),
        child: const Text('Add mandi'),
      ),
      const Divider(height: 32),
      Text('Create officer / admin account', style: Theme.of(context).textTheme.titleMedium),
      TextField(controller: _uPhone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
      TextField(controller: _uName, decoration: const InputDecoration(labelText: 'Name')),
      TextField(controller: _uPw, obscureText: true, decoration: const InputDecoration(labelText: 'Initial password (8+ chars)')),
      DropdownButton<String>(
        value: _role,
        isExpanded: true,
        items: const [DropdownMenuItem(value: 'officer', child: Text('Officer')), DropdownMenuItem(value: 'admin', child: Text('Admin'))],
        onChanged: (v) => setState(() => _role = v!),
      ),
      DropdownButton<String?>(
        value: _mandiId,
        isExpanded: true,
        hint: const Text('Mandi (for officers)'),
        items: [for (final m in _mandis) DropdownMenuItem(value: m['id'] as String, child: Text('${m['name']}'))],
        onChanged: (v) => setState(() => _mandiId = v),
      ),
      FilledButton(
        onPressed: () => _run(
            () => api.adminCreateUser({'phone': _uPhone.text.trim(), 'name': _uName.text.trim(), 'password': _uPw.text, 'role': _role, 'mandi_id': _mandiId}),
            'Account created'),
        child: const Text('Create account'),
      ),
    ]);
  }
}
