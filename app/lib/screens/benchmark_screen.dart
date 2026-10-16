import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../ml/model_loader.dart';
import '../state/app_state.dart';

class BenchmarkResult {
  BenchmarkResult({
    required this.runs,
    required this.warmupMs,
    required this.minMs,
    required this.maxMs,
    required this.meanMs,
    required this.medianMs,
    required this.p90Ms,
    required this.fps,
  });

  final List<double> runs;
  final double warmupMs;
  final double minMs;
  final double maxMs;
  final double meanMs;
  final double medianMs;
  final double p90Ms;
  final double fps;
}

class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({super.key});

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends State<BenchmarkScreen> {
  int _numRuns = 10;
  bool _running = false;
  BenchmarkResult? _result;
  String? _error;

  Future<void> _runBenchmark(ModelStatus modelStatus) async {
    if (!modelStatus.ready) return;
    setState(() {
      _running = true;
      _error = null;
      _result = null;
    });

    try {
      final meta = modelStatus.metadata!;
      final input = meta['input'] as Map;
      final w = input['width'] as int;
      final h = input['height'] as int;
      final asFloat = input['dtype'] == 'float32';

      final interp = await Interpreter.fromAsset(modelAsset);
      try {
        final tensor = asFloat ? Float32List(w * h * 3) : Uint8List(w * h * 3);
        final inputObj = (tensor as dynamic).reshape([1, h, w, 3]);

        final outTensors = interp.getOutputTensors();
        final buffers = <int, Object>{
          for (var k = 0; k < outTensors.length; k++) k: _alloc(outTensors[k].shape),
        };

        // 1. Warm-up run (discarded)
        final warmupSw = Stopwatch()..start();
        interp.runForMultipleInputs([inputObj], buffers);
        warmupSw.stop();
        final warmupMs = warmupSw.elapsedMicroseconds / 1000.0;

        // 2. N timed runs
        final latencies = <double>[];
        for (var i = 0; i < _numRuns; i++) {
          final sw = Stopwatch()..start();
          interp.runForMultipleInputs([inputObj], buffers);
          sw.stop();
          latencies.add(sw.elapsedMicroseconds / 1000.0);
        }

        final sorted = List<double>.from(latencies)..sort();
        final minMs = sorted.first;
        final maxMs = sorted.last;
        final meanMs = sorted.reduce((a, b) => a + b) / sorted.length;
        final medianMs = sorted.length.isOdd
            ? sorted[sorted.length ~/ 2]
            : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2.0;
        final p90Idx = (sorted.length * 0.9).floor().clamp(0, sorted.length - 1);
        final p90Ms = sorted[p90Idx];
        final fps = medianMs > 0 ? (1000.0 / medianMs) : 0.0;

        setState(() {
          _result = BenchmarkResult(
            runs: latencies,
            warmupMs: warmupMs,
            minMs: minMs,
            maxMs: maxMs,
            meanMs: meanMs,
            medianMs: medianMs,
            p90Ms: p90Ms,
            fps: fps,
          );
        });
      } finally {
        interp.close();
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _running = false;
      });
    }
  }

  static Object _alloc(List<int> shape) {
    if (shape.length == 1) return List<double>.filled(shape[0], 0);
    return List.generate(shape[0], (_) => _alloc(shape.sublist(1)));
  }

  @override
  Widget build(BuildContext context) {
    final modelStatus = context.watch<AppState>().model;

    return Scaffold(
      appBar: AppBar(
        title: const Text('On-Device Benchmark (Debug)'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: modelStatus.ready ? Colors.green.shade50 : Colors.amber.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        modelStatus.ready ? Icons.check_circle : Icons.warning_amber,
                        color: modelStatus.ready ? Colors.green.shade700 : Colors.amber.shade900,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        modelStatus.ready ? 'Model Ready for Benchmarking' : 'Model Not Installed',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (!modelStatus.ready) ...[
                    const Text(
                      'Latency benchmark is BLOCKED until manual step M6 is complete.\n'
                      'Export your trained TFLite model and place model_metadata.json into assets/model/.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    for (final p in modelStatus.problems)
                      Text('• $p', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                  ] else ...[
                    Text('Model: ${modelStatus.metadata!['model_name']} v${modelStatus.version}'),
                    Text('Input: ${modelStatus.metadata!['input']['width']}x${modelStatus.metadata!['input']['height']} (${modelStatus.metadata!['input']['dtype']})'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Iterations (N):', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 16),
              DropdownButton<int>(
                value: _numRuns,
                items: const [
                  DropdownMenuItem(value: 5, child: Text('5 runs')),
                  DropdownMenuItem(value: 10, child: Text('10 runs')),
                  DropdownMenuItem(value: 20, child: Text('20 runs')),
                  DropdownMenuItem(value: 50, child: Text('50 runs')),
                ],
                onChanged: _running
                    ? null
                    : (v) {
                        if (v != null) setState(() => _numRuns = v);
                      },
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: (!modelStatus.ready || _running) ? null : () => _runBenchmark(modelStatus),
                icon: _running
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.speed),
                label: Text(_running ? 'Running...' : 'Run Benchmark'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('Benchmark Error: $_error', style: TextStyle(color: Colors.red.shade900)),
              ),
            ),
          if (_result != null) ...[
            const Divider(),
            Text('Measured Latency (over $_numRuns runs):', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _metricRow('Median Latency', '${_result!.medianMs.toStringAsFixed(1)} ms', isBold: true),
            _metricRow('Mean Latency', '${_result!.meanMs.toStringAsFixed(1)} ms'),
            _metricRow('Min Latency', '${_result!.minMs.toStringAsFixed(1)} ms'),
            _metricRow('Max Latency', '${_result!.maxMs.toStringAsFixed(1)} ms'),
            _metricRow('90th Percentile (P90)', '${_result!.p90Ms.toStringAsFixed(1)} ms'),
            _metricRow('Warm-up Latency', '${_result!.warmupMs.toStringAsFixed(1)} ms'),
            _metricRow('Equivalent Throughput', '${_result!.fps.toStringAsFixed(1)} FPS'),
            const SizedBox(height: 16),
            const Text('Run breakdown (ms):', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (var i = 0; i < _result!.runs.length; i++)
                  Chip(
                    label: Text('#${i + 1}: ${_result!.runs[i].toStringAsFixed(1)} ms', style: const TextStyle(fontSize: 12)),
                    backgroundColor: Colors.grey.shade100,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: isBold ? Colors.green.shade800 : null)),
        ],
      ),
    );
  }
}
