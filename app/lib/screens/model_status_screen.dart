import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/gov_ui.dart';
import 'benchmark_screen.dart';

/// Developer/officer diagnostics: what model is actually installed. Shows only values read from the
/// metadata file; if metrics are empty it says so rather than inventing an accuracy.
class ModelStatusScreen extends StatelessWidget {
  const ModelStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final m = context.watch<AppState>().model;

    return Scaffold(
      backgroundColor: GovColors.background,
      appBar: AppBar(
        title: const Text('Model status', style: TextStyle(fontWeight: FontWeight.w700, color: GovColors.navy)),
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
              child: Column(
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      GovCard(
                        title: 'AI Inference Engine Diagnostic',
                        subtitle: 'On-device TFLite model verification & compliance check',
                        icon: Icons.memory,
                        badge: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: m.ready ? GovColors.greenLight : GovColors.errorLight,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: m.ready ? GovColors.green : GovColors.error),
                          ),
                          child: Text(
                            m.ready ? 'OPERATIONAL' : 'OFFLINE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: m.ready ? GovColors.greenDark : GovColors.error,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                m.ready ? Icons.check_circle : Icons.error,
                                color: m.ready ? GovColors.green : GovColors.error,
                                size: 28,
                              ),
                              title: Text(
                                m.ready ? 'Installed' : 'Not installed / invalid',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: GovColors.navy),
                              ),
                              subtitle: Text(
                                m.ready
                                    ? 'Valid TFLite model file and metadata contract detected.'
                                    : 'Model weights or metadata are missing from application package.',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            if (!m.ready) ...[
                              const Divider(height: 16),
                              const Text('Identified Diagnostics Issues:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: GovColors.navy)),
                              const SizedBox(height: 6),
                              for (final p in m.problems)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.arrow_right, size: 18, color: GovColors.error),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          p,
                                          style: const TextStyle(fontSize: 12, color: GovColors.error, fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: GovColors.navySurface,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: GovColors.border),
                                ),
                                child: const Text(
                                  'Real grading stays disabled until a trained model and model_metadata.json are placed in app/assets/model/ and the app is rebuilt. See ml/README.md.',
                                  style: TextStyle(fontSize: 11.5, color: GovColors.navy, height: 1.4),
                                ),
                              ),
                            ] else ...[
                              const Divider(height: 20),
                              _InfoRow(label: 'Model Name', value: '${m.metadata!['model_name']}'),
                              _InfoRow(label: 'Model Version', value: '${m.version}'),
                              _InfoRow(label: 'Trained on Date', value: '${m.metadata!['trained_on']}'),
                              _InfoRow(label: 'Configured Classes', value: m.classes.map((c) => c['name']).join(', ')),
                              _InfoRow(label: 'Score Threshold', value: '${m.scoreThreshold}'),
                              const SizedBox(height: 8),
                              Text(
                                (m.metadata!['metrics'] as Map).isEmpty
                                    ? 'No evaluation metrics were recorded in the metadata.'
                                    : 'Recorded metrics: ${m.metadata!['metrics']}',
                                style: const TextStyle(fontSize: 12, color: GovColors.textSecondary),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (kDebugMode) ...[
                        GovCard(
                          title: 'Performance Benchmarking',
                          subtitle: 'Diagnostic latency analysis for procurement hardware',
                          icon: Icons.speed,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.speed, color: GovColors.navy),
                            title: const Text('Latency benchmark (Debug)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: GovColors.navy)),
                            subtitle: const Text('Measure real on-device median inference latency over test runs', style: TextStyle(fontSize: 11)),
                            trailing: const Icon(Icons.chevron_right, color: GovColors.navy),
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BenchmarkScreen())),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
                  const SizedBox(height: 24),
                  const GovPortalFooter(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: GovColors.textMuted))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: GovColors.navy))),
        ],
      ),
    );
  }
}
