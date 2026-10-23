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
          Expanded(child: pages[_tab]),
          const GovPortalFooter(compact: true),
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

        final totalCerts = sum['total_certificates'] as int;
        final avgFresh = sum['avg_fresh_pct'];
        final openDisputes = sum['open_disputes'];
        final weightMismatches = sum['weight_mismatches'];
        final byGrade = Map<String, dynamic>.from(sum['by_grade'] as Map);
        final byMandi = (sum['by_mandi'] as List).cast<Map>();
        final officerFlags = (flags['flags'] as List).cast<Map>();
        final stockItems = (stock['items'] as List).cast<Map>();

        return RefreshIndicator(
          onRefresh: () async => reload(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: GovResponsiveContainer(
              maxWidth: 1100,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // KPI Grid
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final cols = width >= 800 ? 4 : (width >= 480 ? 2 : 1);
                      final kpis = [
                        _KpiCard(
                          title: 'Total Certifications',
                          value: '$totalCerts',
                          subtitle: 'Tamper-evident batches',
                          icon: Icons.verified,
                          color: GovColors.navy,
                        ),
                        _KpiCard(
                          title: 'Average Freshness',
                          value: '$avgFresh%',
                          subtitle: 'NAFED baseline target',
                          icon: Icons.eco,
                          color: GovColors.greenDark,
                        ),
                        _KpiCard(
                          title: 'Open Disputes',
                          value: '$openDisputes',
                          subtitle: 'Pending redressal',
                          icon: Icons.gavel,
                          color: (openDisputes as num) > 0 ? GovColors.error : GovColors.navy,
                        ),
                        _KpiCard(
                          title: 'Scale Mismatches',
                          value: '$weightMismatches',
                          subtitle: 'Flagged weight discrepancies',
                          icon: Icons.scale,
                          color: (weightMismatches as num) > 0 ? GovColors.saffronDark : GovColors.navy,
                        ),
                      ];

                      if (cols == 4) {
                        return Row(
                          children: [
                            for (var i = 0; i < kpis.length; i++) ...[
                              if (i > 0) const SizedBox(width: 12),
                              Expanded(child: kpis[i]),
                            ],
                          ],
                        );
                      } else if (cols == 2) {
                        return Column(
                          children: [
                            Row(children: [Expanded(child: kpis[0]), const SizedBox(width: 12), Expanded(child: kpis[1])]),
                            const SizedBox(height: 12),
                            Row(children: [Expanded(child: kpis[2]), const SizedBox(width: 12), Expanded(child: kpis[3])]),
                          ],
                        );
                      } else {
                        return Column(
                          children: [
                            for (var i = 0; i < kpis.length; i++) ...[
                              if (i > 0) const SizedBox(height: 10),
                              kpis[i],
                            ],
                          ],
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // Responsive 2-column or stacked layout
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 768;

                      final gradeAndMandi = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          GovCard(
                            title: 'Grade Distribution',
                            subtitle: 'NAFED categorization breakdown',
                            icon: Icons.pie_chart_outline,
                            child: Column(
                              children: [
                                for (final e in byGrade.entries)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: e.key.toUpperCase().contains('A') ? GovColors.greenLight : GovColors.navySurface,
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: GovColors.border),
                                          ),
                                          child: Text('Grade ${e.key}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: GovColors.navy)),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: LinearProgressIndicator(
                                              value: totalCerts > 0 ? (e.value as num) / totalCerts : 0,
                                              backgroundColor: GovColors.navySurface,
                                              color: e.key.toUpperCase().contains('A') ? GovColors.green : GovColors.navy,
                                              minHeight: 8,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: GovColors.navy)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          GovCard(
                            title: 'Mandi Performance',
                            subtitle: 'Produce inspected by procurement center',
                            icon: Icons.storefront,
                            child: Column(
                              children: [
                                if (byMandi.isEmpty) const Text('No mandi activity recorded.', style: TextStyle(color: GovColors.textMuted, fontSize: 12)),
                                for (final m in byMandi)
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.location_on, color: GovColors.navy, size: 20),
                                    title: Text('${m['mandi'] ?? 'Unassigned Center'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                                    subtitle: Text('${m['certificates']} certificates issued', style: const TextStyle(fontSize: 11)),
                                    trailing: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: GovColors.greenLight, borderRadius: BorderRadius.circular(4)),
                                      child: Text('${m['avg_fresh_pct']}% Fresh', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: GovColors.greenDark)),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      );

                      final alertsAndStock = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          GovCard(
                            title: 'Officer Audit Alerts',
                            subtitle: 'Anomalies & high reject rate flags',
                            icon: Icons.warning_amber,
                            child: Column(
                              children: [
                                if (officerFlags.isEmpty)
                                  Text(flags['note'] ?? 'All procurement officers operating within nominal parameters.',
                                      style: const TextStyle(color: GovColors.textMuted, fontSize: 12)),
                                for (final f in officerFlags)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: GovColors.errorLight,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: GovColors.error),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.flag, color: GovColors.error, size: 18),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('${f['officer']} (${f['certificates']} certs)', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: GovColors.error)),
                                              Text((f['reasons'] as List).join('\n'), style: const TextStyle(fontSize: 11, color: GovColors.navy)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          GovCard(
                            title: 'Stock Health Alert',
                            subtitle: 'Shortest estimated shelf-life batches',
                            icon: Icons.inventory_2_outlined,
                            child: Column(
                              children: [
                                if (stockItems.isEmpty)
                                  Text(stock['note'] ?? 'No active stock alerts.', style: const TextStyle(color: GovColors.textMuted, fontSize: 12)),
                                for (final s in stockItems.take(5))
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(color: GovColors.saffronLight, borderRadius: BorderRadius.circular(4)),
                                      child: const Icon(Icons.timer, size: 16, color: GovColors.saffronDark),
                                    ),
                                    title: Text('${s['shelf_life_days']} days remaining', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                                    subtitle: Text('Grade ${s['grade']} • ${s['certificate_id']}'.substring(0, 24), style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace')),
                                  ),
                              ],
                            ),
                          ),
                          if (trends.isNotEmpty)
                            GovCard(
                              title: 'Inspection Trends',
                              subtitle: 'Batches certified in recent days',
                              icon: Icons.trending_up,
                              child: Column(
                                children: [
                                  for (final t in trends.take(5))
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 3),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('${t['date']}', style: const TextStyle(fontSize: 11.5, color: GovColors.textSecondary)),
                                          Text('${t['count']} batches (${t['avg_fresh_pct']}% fresh)', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: GovColors.navy)),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      );

                      if (isWide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: gradeAndMandi),
                            const SizedBox(width: 16),
                            Expanded(child: alertsAndStock),
                          ],
                        );
                      } else {
                        return Column(
                          children: [
                            gradeAndMandi,
                            alertsAndStock,
                          ],
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: GovColors.border),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: GovColors.textMuted)),
              Icon(icon, size: 18, color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 10, color: GovColors.textSecondary)),
        ],
      ),
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
    final isDesktop = GovBreakpoints.isTablet(context) || GovBreakpoints.isDesktop(context);

    final mandiCard = GovCard(
      title: 'Mandi Registry',
      subtitle: 'Register new APMC market centers in the central directory',
      icon: Icons.storefront,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(controller: _mName, decoration: const InputDecoration(labelText: 'Mandi Center Name', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _mState, decoration: const InputDecoration(labelText: 'State (e.g. Maharashtra)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _mDist, decoration: const InputDecoration(labelText: 'District (e.g. Nashik)', border: OutlineInputBorder())),
          const SizedBox(height: 14),
          GovButton(
            label: 'Register Mandi',
            icon: Icons.add_business,
            onPressed: () => _run(() async {
              await api.createMandi(_mName.text.trim(), _mState.text.trim(), _mDist.text.trim());
              _mName.clear();
              _mState.clear();
              _mDist.clear();
              await _loadMandis();
            }, 'Mandi added to directory'),
          ),
          if (_mandis.isNotEmpty) ...[
            const Divider(height: 24),
            const Text('Registered Mandis Directory:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: GovColors.navy)),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _mandis.length,
                itemBuilder: (c, i) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.location_city, size: 18, color: GovColors.navy),
                  title: Text('${_mandis[i]['name']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  subtitle: Text('${_mandis[i]['district']}, ${_mandis[i]['state']}', style: const TextStyle(fontSize: 10.5)),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    final userCard = GovCard(
      title: 'Authorized Account Provisioning',
      subtitle: 'Issue officer or admin credentials with assigned jurisdiction',
      icon: Icons.person_add_alt_1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(controller: _uPhone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile Number (+91)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _uName, decoration: const InputDecoration(labelText: 'Full Name / Official Designation', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _uPw, obscureText: true, decoration: const InputDecoration(labelText: 'Initial Password (8+ chars)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: 'Assigned Role', border: OutlineInputBorder()),
            items: const [DropdownMenuItem(value: 'officer', child: Text('Procurement Officer')), DropdownMenuItem(value: 'admin', child: Text('Central Administrator'))],
            onChanged: (v) => setState(() => _role = v!),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            initialValue: _mandiId,
            decoration: const InputDecoration(labelText: 'Jurisdiction Mandi', border: OutlineInputBorder()),
            hint: const Text('Select Mandi (for officers)'),
            items: [for (final m in _mandis) DropdownMenuItem(value: m['id'] as String, child: Text('${m['name']} (${m['district']})'))],
            onChanged: (v) => setState(() => _mandiId = v),
          ),
          const SizedBox(height: 14),
          GovButton(
            label: 'Provision Official Account',
            icon: Icons.how_to_reg,
            onPressed: () => _run(
              () => api.adminCreateUser({'phone': _uPhone.text.trim(), 'name': _uName.text.trim(), 'password': _uPw.text, 'role': _role, 'mandi_id': _mandiId}),
              'Account successfully provisioned',
            ),
          ),
        ],
      ),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: GovResponsiveContainer(
        maxWidth: 1100,
        child: isDesktop
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: mandiCard),
                  const SizedBox(width: 16),
                  Expanded(child: userCard),
                ],
              )
            : Column(
                children: [
                  mandiCard,
                  userCard,
                ],
              ),
      ),
    );
  }
}
