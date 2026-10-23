import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/gov_ui.dart';
import '../certificate_screen.dart';
import '../model_status_screen.dart';
import 'capture_screen.dart';

class OfficerHome extends StatelessWidget {
  const OfficerHome({super.key});

  @override
  Widget build(BuildContext context) {
    return const _OfficerHomeTabs();
  }
}

class _OfficerHomeTabs extends StatefulWidget {
  const _OfficerHomeTabs();

  @override
  State<_OfficerHomeTabs> createState() => _OfficerHomeTabsState();
}

class _OfficerHomeTabsState extends State<_OfficerHomeTabs> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final canGrade = s.model.ready && s.rule != null;

    return Scaffold(
      backgroundColor: GovColors.background,
      appBar: AppBar(
        title: const Row(
          children: [
            GovEmblemPlaceholder(size: 32),
            SizedBox(width: 10),
            Text('Procurement', style: TextStyle(fontWeight: FontWeight.w700, color: GovColors.navy)),
          ],
        ),
        actions: [
          const LanguageSwitcherAction(),
          IconButton(
            tooltip: 'Model status',
            icon: Icon(s.model.ready ? Icons.memory : Icons.warning_amber, color: s.model.ready ? GovColors.greenDark : GovColors.saffronDark),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ModelStatusScreen())),
          ),
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
              label: 'Produce Register',
            ),
            NavigationDestination(
              icon: Icon(Icons.assignment_late_outlined, color: GovColors.navy),
              label: 'Re-inspections',
            ),
          ],
        ),
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              backgroundColor: canGrade ? GovColors.navy : GovColors.border,
              foregroundColor: canGrade ? Colors.white : GovColors.textMuted,
              elevation: canGrade ? 3 : 0,
              onPressed: canGrade ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CaptureScreen())) : null,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Grade a batch', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
      body: Column(
        children: [
          Expanded(
            child: GovResponsiveContainer(
              maxWidth: 1000,
              child: _tab == 0 ? const _InspectionRegister() : const _AssignedReinspections(),
            ),
          ),
          const GovPortalFooter(compact: true),
        ],
      ),
    );
  }
}

class _InspectionRegister extends StatelessWidget {
  const _InspectionRegister();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();

    return Column(
      children: [
        if (!s.model.ready)
          _Banner(
            'Grading unavailable: the AI model is not installed on this build.\n${s.model.problems.join('\n')}',
            error: true,
          ),
        if (s.rule == null) _Banner(s.ruleNote ?? 'Grading rules not loaded.', error: true),
        if (s.rule != null && s.ruleNote != null) _Banner(s.ruleNote!),
        if (s.pendingCount > 0)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: GovColors.saffronLight,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0x80FF9933)),
            ),
            child: ListTile(
              leading: s.syncing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: GovColors.saffronDark))
                  : const Icon(Icons.cloud_upload_outlined, color: GovColors.saffronDark),
              title: Text(
                '${s.pendingCount} certificate(s) waiting to sync',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: GovColors.navy),
              ),
              subtitle: s.lastSyncError == null
                  ? const Text('Offline records will be uploaded securely to the Mandi Gateway', style: TextStyle(fontSize: 11))
                  : Text(s.lastSyncError!, style: const TextStyle(fontSize: 11, color: GovColors.error)),
              trailing: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: GovColors.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                onPressed: s.syncing ? null : s.syncPending,
                icon: const Icon(Icons.sync, size: 14),
                label: const Text('Sync now'),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.receipt_long, size: 16, color: GovColors.navy),
              const SizedBox(width: 6),
              const Text(
                'Official Produce Inspection Register',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: GovColors.navy),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: GovColors.navySurface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: GovColors.border),
                ),
                child: const Text(
                  'OFFICER TERMINAL',
                  style: TextStyle(fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.w600, color: GovColors.navy),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        const Expanded(child: _LocalHistory()),
      ],
    );
  }
}

class _AssignedReinspections extends StatelessWidget {
  const _AssignedReinspections();

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;
    return Loader<List<dynamic>>(
      load: () => api.assignedDisputes(),
      builder: (c, items, reload) {
        if (items.isEmpty) {
          return const EmptyView('No re-inspection requests assigned to your jurisdiction.\nAny admin escalation will appear here.');
        }

        return RefreshIndicator(
          onRefresh: () async => reload(),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              final d = Map<String, dynamic>.from(items[i] as Map);
              final isDone = d['reinspection_certificate_id'] != null;

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: isDone ? GovColors.green : GovColors.saffron),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isDone ? Icons.check_circle : Icons.warning_amber_rounded,
                            color: isDone ? GovColors.green : GovColors.saffronDark,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isDone ? 'RE-INSPECTION SUBMITTED' : 'ACTION REQUIRED: RE-INSPECTION',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: isDone ? GovColors.greenDark : GovColors.saffronDark,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Cert #${d['certificate_id'].toString().substring(0, 8)}',
                            style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: GovColors.textMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Farmer Dispute Claim:',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: GovColors.navy),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${d['reason']}',
                        style: const TextStyle(fontSize: 12, color: GovColors.textSecondary),
                      ),
                      if (d['resolution_note'] != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${d['resolution_note']}',
                          style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: GovColors.navy),
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (!isDone)
                        Align(
                          alignment: Alignment.centerRight,
                          child: GovButton(
                            label: 'Perform Re-inspection',
                            icon: Icons.camera_alt,
                            onPressed: () => Navigator.push(
                              ctx,
                              MaterialPageRoute(builder: (_) => const CaptureScreen()),
                            ),
                          ),
                        ),
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
}

class _Banner extends StatelessWidget {
  const _Banner(this.text, {this.error = false});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: error ? GovColors.errorLight : GovColors.saffronLight,
          border: Border(bottom: BorderSide(color: error ? GovColors.error : GovColors.saffron, width: 1.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              error ? Icons.warning_amber_rounded : Icons.info_outline,
              color: error ? GovColors.error : GovColors.saffronDark,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: error ? GovColors.error : GovColors.navy,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
}

class _LocalHistory extends StatelessWidget {
  const _LocalHistory();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(s.pendingCount),
      future: s.db.certificates(),
      builder: (c, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: GovColors.navy));
        final items = snap.data!;
        if (items.isEmpty) {
          return const EmptyView('No produce certificates issued from this terminal yet.\nInitiate a batch grading above.');
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (c, i) {
            final b = Map<String, dynamic>.from(items[i]['body'] as Map);
            final synced = items[i]['synced'] as bool;
            final grade = '${b['grade']}';
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: Container(
                    width: 42,
                    height: 42,
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
                          fontSize: 16,
                          color: isGradeA ? GovColors.greenDark : GovColors.saffronDark,
                        ),
                      ),
                    ),
                  ),
                  title: Text(
                    '$grade · ${b['fresh_pct']}% fresh · ${b['onion_count']} onions',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: GovColors.navy),
                  ),
                  subtitle: Text(
                    'Issued: ${b['captured_at']}\nStatus: ${synced ? "Cryptographically Synced & Signed" : (items[i]['last_error'] ?? "Pending Mandi Sync")}',
                    style: TextStyle(
                      fontSize: 11,
                      color: synced ? GovColors.greenDark : GovColors.textMuted,
                      height: 1.3,
                    ),
                  ),
                  isThreeLine: true,
                  trailing: Icon(
                    synced ? Icons.verified : Icons.cloud_off,
                    color: synced ? GovColors.green : GovColors.textMuted,
                    size: 22,
                  ),
                  onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => CertificateScreen(local: items[i]))),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
