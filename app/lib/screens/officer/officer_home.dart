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
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: canGrade ? GovColors.navy : GovColors.border,
        foregroundColor: canGrade ? Colors.white : GovColors.textMuted,
        elevation: canGrade ? 3 : 0,
        onPressed: canGrade ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CaptureScreen())) : null,
        icon: const Icon(Icons.camera_alt),
        label: const Text('Grade a batch', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
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
          const GovPortalFooter(compact: true),
        ],
      ),
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
