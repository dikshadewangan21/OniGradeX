import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'benchmark_screen.dart';

/// Developer/officer diagnostics: what model is actually installed. Shows only values read from the
/// metadata file; if metrics are empty it says so rather than inventing an accuracy.
class ModelStatusScreen extends StatelessWidget {
  const ModelStatusScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final m = context.watch<AppState>().model;
    return Scaffold(
      appBar: AppBar(title: const Text('Model status')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ListTile(
          leading: Icon(m.ready ? Icons.check_circle : Icons.error, color: m.ready ? Colors.green : Colors.red),
          title: Text(m.ready ? 'Installed' : 'Not installed / invalid'),
        ),
        if (!m.ready) ...[
          for (final p in m.problems) ListTile(leading: const Icon(Icons.arrow_right), title: Text(p)),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Real grading stays disabled until a trained model and model_metadata.json are placed in '
                'app/assets/model/ and the app is rebuilt. See ml/README.md.'),
          ),
        ] else ...[
          Text('Name: ${m.metadata!['model_name']}'),
          Text('Version: ${m.version}'),
          Text('Trained on: ${m.metadata!['trained_on']}'),
          Text('Classes: ${m.classes.map((c) => c['name']).join(', ')}'),
          Text('Score threshold: ${m.scoreThreshold}'),
          const SizedBox(height: 8),
          Text((m.metadata!['metrics'] as Map).isEmpty
              ? 'No evaluation metrics were recorded in the metadata.'
              : 'Recorded metrics: ${m.metadata!['metrics']}'),
        ],
        if (kDebugMode) ...[
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.speed, color: Colors.blue),
            title: const Text('Latency benchmark (Debug)'),
            subtitle: const Text('Measure real on-device median inference latency'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BenchmarkScreen())),
          ),
        ],
      ]),
    );
  }
}
