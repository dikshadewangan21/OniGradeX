import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../widgets/common.dart';
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
      appBar: AppBar(title: const Text('Procurement'), actions: [
        IconButton(
          tooltip: 'Model status',
          icon: Icon(s.model.ready ? Icons.memory : Icons.warning_amber),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ModelStatusScreen())),
        ),
        IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: s.logout),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: canGrade ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CaptureScreen())) : null,
        icon: const Icon(Icons.camera_alt),
        label: const Text('Grade a batch'),
      ),
      body: Column(children: [
        if (!s.model.ready)
          _Banner(
              'Grading unavailable: the AI model is not installed on this build.\n${s.model.problems.join('\n')}',
              error: true),
        if (s.rule == null) _Banner(s.ruleNote ?? 'Grading rules not loaded.', error: true),
        if (s.rule != null && s.ruleNote != null) _Banner(s.ruleNote!),
        if (s.pendingCount > 0)
          ListTile(
            leading: s.syncing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
            title: Text('${s.pendingCount} certificate(s) waiting to sync'),
            subtitle: s.lastSyncError == null ? null : Text(s.lastSyncError!),
            trailing: TextButton(onPressed: s.syncing ? null : s.syncPending, child: const Text('Sync now')),
          ),
        const Divider(height: 1),
        const Expanded(child: _LocalHistory()),
      ]),
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
        color: error ? Theme.of(context).colorScheme.errorContainer : Theme.of(context).colorScheme.secondaryContainer,
        padding: const EdgeInsets.all(12),
        child: Text(text),
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
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = snap.data!;
        if (items.isEmpty) return const EmptyView('No certificates issued from this device yet.');
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (c, i) {
            final b = Map<String, dynamic>.from(items[i]['body'] as Map);
            final synced = items[i]['synced'] as bool;
            return ListTile(
              leading: CircleAvatar(child: Text('${b['grade']}'.characters.first)),
              title: Text('${b['grade']} · ${b['fresh_pct']}% fresh · ${b['onion_count']} onions'),
              subtitle: Text('${b['captured_at']}\n${synced ? 'Synced' : (items[i]['last_error'] ?? 'Not synced yet')}'),
              isThreeLine: true,
              trailing: Icon(synced ? Icons.cloud_done : Icons.cloud_off),
              onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => CertificateScreen(local: items[i]))),
            );
          },
        );
      },
    );
  }
}
