import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onigrader/data/local_db.dart';
import 'package:onigrader/ml/model_loader.dart';
import 'package:onigrader/screens/benchmark_screen.dart';
import 'package:onigrader/state/app_state.dart';
import 'package:provider/provider.dart';

class FakeLocalDb implements LocalDb {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestAppState extends ChangeNotifier implements AppState {
  @override
  final LocalDb db = FakeLocalDb();

  @override
  ModelStatus model = ModelStatus.unavailable(['Model file not installed (assets/model/onion_model.tflite)']);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('BenchmarkScreen shows blocked state when model is not installed', (tester) async {
    final state = TestAppState();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(
          home: BenchmarkScreen(),
        ),
      ),
    );

    // Verify UI components
    expect(find.text('On-Device Benchmark (Debug)'), findsOneWidget);
    expect(find.text('Model Not Installed'), findsOneWidget);
    expect(find.textContaining('BLOCKED until manual step M6'), findsOneWidget);
    expect(find.textContaining('Model file not installed'), findsOneWidget);

    // Verify Run Benchmark button is disabled
    final buttonFinder = find.widgetWithText(FilledButton, 'Run Benchmark');
    expect(buttonFinder, findsOneWidget);
    final button = tester.widget<FilledButton>(buttonFinder);
    expect(button.onPressed, isNull);
  });
}
