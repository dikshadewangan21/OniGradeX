import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api_client.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/gov_ui.dart';

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
      backgroundColor: GovColors.background,
      appBar: AppBar(
        title: const Row(
          children: [
            GovEmblemPlaceholder(size: 32),
            SizedBox(width: 10),
            Text('Central Admin Portal', style: TextStyle(fontWeight: FontWeight.w700, color: GovColors.navy)),
          ],
        ),
        actions: [
          const LanguageSwitcherAction(),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout, color: GovColors.error),
            onPressed: context.read<AppState>().logout,
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
            NavigationDestination(icon: Icon(Icons.insights, color: GovColors.navy), label: 'Overview'),
            NavigationDestination(icon: Icon(Icons.gavel, color: GovColors.navy), label: 'Disputes'),
            NavigationDestination(icon: Icon(Icons.rule, color: GovColors.navy), label: 'Rules'),
            NavigationDestination(icon: Icon(Icons.settings, color: GovColors.navy), label: 'Setup'),
          ],
        ),
      ),
      body: Column(
        children: [
          const GovTopUtilityBar(),
          Expanded(child: pages[_tab]),
          const GovPortalFooter(),
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
    final officerIdCtl = TextEditingController(text: d['assigned_officer_id'] as String? ?? '');
    String status = d['status'] == 'reinspection' ? 'reinspection' : 'upheld';
    await showDialog(
      context: context,
      builder: (dc) => StatefulBuilder(
        builder: (dc, set) => AlertDialog(
          title: Text('Dispute for cert ${d['certificate_id']}'.substring(0, 24)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Reason: ${d['reason']}', style: const TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              DropdownButton<String>(
                value: status,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'reinspection', child: Text('Assign re-inspection to officer')),
                  DropdownMenuItem(value: 'upheld', child: Text('Uphold original grade')),
                  DropdownMenuItem(value: 'overturned', child: Text('Overturn grade')),
                ],
                onChanged: (v) => set(() => status = v!),
              ),
              const SizedBox(height: 8),
              if (status == 'reinspection') ...[
                TextField(
                  controller: officerIdCtl,
                  decoration: const InputDecoration(labelText: 'Officer User ID (required for re-inspection)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Resolution note (required)', border: OutlineInputBorder()),
                maxLines: 3,
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dc), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                try {
                  if (status == 'reinspection') {
                    if (officerIdCtl.text.trim().isEmpty) {
                      toast(dc, 'Enter an officer user ID');
                      return;
                    }
                    await api.assignDispute(d['id'] as String, officerIdCtl.text.trim());
                    if (dc.mounted) Navigator.pop(dc);
                    reload();
                    return;
                  }
                  if (note.text.trim().isEmpty) {
                    toast(dc, 'Note is required to resolve');
                    return;
                  }
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

/// Validated form-based grading-rule editor (Phase 5f).
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
          onPressed: () => _openValidatedRuleDialog(context, api, rules.isEmpty ? null : rules.first as Map, reload),
        ),
        const SizedBox(height: 12),
        if (rules.isEmpty) const Text('No rules published yet. Officers cannot grade until you publish one.'),
        for (final r in rules)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text('v${r['version']}${r['is_active'] == true ? '  (active)' : ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(const JsonEncoder.withIndent('  ').convert(r['definition'])),
            ),
          ),
      ]),
    );
  }

  Future<void> _openValidatedRuleDialog(BuildContext context, ApiClient api, Map? current, VoidCallback reload) async {
    await showDialog(
      context: context,
      builder: (dc) => _RuleFormDialog(api: api, currentDefinition: current?['definition'] as Map?, onPublished: reload),
    );
  }
}

class _RuleFormDialog extends StatefulWidget {
  const _RuleFormDialog({required this.api, this.currentDefinition, required this.onPublished});
  final ApiClient api;
  final Map? currentDefinition;
  final VoidCallback onPublished;

  @override
  State<_RuleFormDialog> createState() => _RuleFormDialogState();
}

class _GradeRowData {
  _GradeRowData({required this.grade, required this.maxDefective, this.maxRot, this.minDiameter});
  final TextEditingController grade;
  final TextEditingController maxDefective;
  final TextEditingController? maxRot;
  final TextEditingController? minDiameter;
}

class _RuleFormDialogState extends State<_RuleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _minConfCtl;
  late final TextEditingController _rejectGradeCtl;
  late final TextEditingController _refSizeCtl;
  late final TextEditingController _densityCtl;
  final List<_GradeRowData> _rows = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final d = widget.currentDefinition;
    _minConfCtl = TextEditingController(text: (d?['min_confidence'] ?? 0.6).toString());
    _rejectGradeCtl = TextEditingController(text: (d?['reject_grade'] ?? 'Rejected').toString());
    _refSizeCtl = TextEditingController(text: (d?['reference_object_size_mm'] ?? 25.0).toString());
    _densityCtl = TextEditingController(text: (d?['density_constant_g_cm3'] ?? 0.96).toString());

    final gradesList = d?['grades'] as List?;
    if (gradesList != null && gradesList.isNotEmpty) {
      for (final g in gradesList) {
        final gm = g as Map;
        _rows.add(_GradeRowData(
          grade: TextEditingController(text: gm['grade']?.toString() ?? ''),
          maxDefective: TextEditingController(text: gm['max_defective_pct']?.toString() ?? '10.0'),
          maxRot: TextEditingController(text: gm['max_rot_pct']?.toString() ?? ''),
          minDiameter: TextEditingController(text: gm['min_diameter_mm']?.toString() ?? ''),
        ));
      }
    } else {
      // Standard default grades
      _rows.add(_GradeRowData(
        grade: TextEditingController(text: 'A'),
        maxDefective: TextEditingController(text: '10.0'),
        maxRot: TextEditingController(text: '5.0'),
        minDiameter: TextEditingController(text: '45.0'),
      ));
      _rows.add(_GradeRowData(
        grade: TextEditingController(text: 'B'),
        maxDefective: TextEditingController(text: '20.0'),
        maxRot: TextEditingController(text: '10.0'),
        minDiameter: TextEditingController(text: '35.0'),
      ));
      _rows.add(_GradeRowData(
        grade: TextEditingController(text: 'C'),
        maxDefective: TextEditingController(text: '35.0'),
        maxRot: TextEditingController(text: '15.0'),
        minDiameter: TextEditingController(text: '25.0'),
      ));
    }
  }

  void _addRow() {
    setState(() {
      _rows.add(_GradeRowData(
        grade: TextEditingController(text: String.fromCharCode(65 + _rows.length)),
        maxDefective: TextEditingController(text: '${(_rows.length + 1) * 15}.0'),
        maxRot: TextEditingController(),
        minDiameter: TextEditingController(),
      ));
    });
  }

  void _removeRow(int idx) {
    if (_rows.length <= 1) {
      toast(context, 'Rule must have at least one grade row');
      return;
    }
    setState(() => _rows.removeAt(idx));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final minConf = double.tryParse(_minConfCtl.text.trim());
    if (minConf == null || minConf < 0.0 || minConf > 1.0) {
      toast(context, 'Min confidence must be between 0.0 and 1.0');
      return;
    }

    final grades = <Map<String, dynamic>>[];
    for (final r in _rows) {
      final gName = r.grade.text.trim();
      final maxDef = double.tryParse(r.maxDefective.text.trim());
      if (gName.isEmpty || maxDef == null || maxDef < 0 || maxDef > 100) {
        toast(context, 'Check grade names and defect percentages');
        return;
      }
      final rowMap = <String, dynamic>{
        'grade': gName,
        'max_defective_pct': maxDef,
      };
      final maxRot = double.tryParse(r.maxRot?.text.trim() ?? '');
      if (maxRot != null) rowMap['max_rot_pct'] = maxRot;
      final minDiam = double.tryParse(r.minDiameter?.text.trim() ?? '');
      if (minDiam != null) rowMap['min_diameter_mm'] = minDiam;
      grades.add(rowMap);
    }

    final definition = <String, dynamic>{
      'min_confidence': minConf,
      'reject_grade': _rejectGradeCtl.text.trim(),
      'grades': grades,
    };

    final refSize = double.tryParse(_refSizeCtl.text.trim());
    if (refSize != null) definition['reference_object_size_mm'] = refSize;
    final density = double.tryParse(_densityCtl.text.trim());
    if (density != null) definition['density_constant_g_cm3'] = density;

    setState(() => _submitting = true);
    try {
      await widget.api.publishRule(definition);
      if (mounted) Navigator.pop(context);
      widget.onPublished();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Publish Grading Rule (Form)'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _minConfCtl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Min Confidence (0.0 - 1.0)', border: OutlineInputBorder()),
                        validator: (v) => (double.tryParse(v ?? '') == null) ? 'Enter number' : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _rejectGradeCtl,
                        decoration: const InputDecoration(labelText: 'Reject Grade Name', border: OutlineInputBorder()),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _refSizeCtl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Ref object size mm (₹5 coin=25)', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _densityCtl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Onion density g/cm³ (0.96)', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Grade Thresholds (Evaluated in Order):', style: TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.add_circle, color: Colors.blue), onPressed: _addRow, tooltip: 'Add Grade'),
                  ],
                ),
                for (var i = 0; i < _rows.length; i++) ...[
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: 80,
                                child: TextFormField(
                                  controller: _rows[i].grade,
                                  decoration: InputDecoration(labelText: 'Grade #${i + 1}'),
                                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: _rows[i].maxDefective,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(labelText: 'Max Defect %'),
                                  validator: (v) => (double.tryParse(v ?? '') == null) ? 'Required' : null,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _removeRow(i),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _rows[i].maxRot,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(labelText: 'Max Rot % (opt)'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: _rows[i].minDiameter,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(labelText: 'Min Diam mm (opt)'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Publishing...' : 'Publish Rule'),
        ),
      ],
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
