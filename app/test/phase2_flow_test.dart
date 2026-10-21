import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onigrader/data/api_client.dart';
import 'package:onigrader/data/local_db.dart';
import 'package:onigrader/ml/model_loader.dart';
import 'package:onigrader/screens/model_status_screen.dart';
import 'package:onigrader/screens/officer/officer_home.dart';
import 'package:onigrader/state/app_state.dart';
import 'package:provider/provider.dart';

class FakeLocalDb implements LocalDb {
  @override
  Future<List<Map<String, dynamic>>> certificates() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestAppState extends ChangeNotifier implements AppState {
  @override
  final LocalDb db = FakeLocalDb();

  @override
  ModelStatus model = ModelStatus.unavailable(['Model file not installed (assets/model/onion_model.tflite)']);

  @override
  Map<String, dynamic>? rule = {
    'version': 1,
    'definition': {
      'reject_grade': 'Rejected',
      'grades': [{'grade': 'A', 'max_defective_pct': 10}],
    }
  };

  @override
  String? ruleNote;

  @override
  int pendingCount = 0;

  @override
  bool syncing = false;

  @override
  String? lastSyncError;

  @override
  bool ready = true;

  @override
  String get role => 'officer';

  @override
  Session? session;

  @override
  Map<String, dynamic>? profile;

  @override
  Locale currentLocale = const Locale('en');

  @override
  void setLocale(Locale loc) {
    currentLocale = loc;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Phase 2 flows: Officer and Model Status validation', () {
    testWidgets('Officer screen displays AI model not installed banner and disables Grade button', (tester) async {
      final appState = TestAppState();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(home: OfficerHome()),
        ),
      );
      await tester.pumpAndSettle();

      // Verify "Procurement" title
      expect(find.text('Procurement'), findsOneWidget);

      // Verify the warning banner is displayed
      expect(find.textContaining('Grading unavailable: the AI model is not installed on this build.'), findsOneWidget);
      expect(find.textContaining('assets/model/onion_model.tflite'), findsOneWidget);

      // Verify warning icon in AppBar
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);

      // Verify Grade a batch FAB is present but disabled (onPressed is null)
      final fabFinder = find.byType(FloatingActionButton);
      expect(fabFinder, findsOneWidget);
      final fab = tester.widget<FloatingActionButton>(fabFinder);
      expect(fab.onPressed, isNull);
    });

    testWidgets('ModelStatusScreen displays not installed / invalid status and exact missing problem', (tester) async {
      final appState = TestAppState();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(home: ModelStatusScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Model status'), findsOneWidget);
      expect(find.text('Not installed / invalid'), findsOneWidget);
      expect(find.text('Model file not installed (assets/model/onion_model.tflite)'), findsOneWidget);
      expect(find.textContaining('Real grading stays disabled until a trained model'), findsOneWidget);
    });

    testWidgets('Officer screen enables Grade button when model and rule are both ready', (tester) async {
      final appState = TestAppState();
      appState.model = ModelStatus.ready({
        'model_name': 'test_model',
        'version': 'v1',
        'trained_on': '2026-10-15',
        'classes': [{'id': 0, 'name': 'onion'}],
        'postprocess': {'score_threshold': 0.5},
        'metrics': {},
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(home: OfficerHome()),
        ),
      );
      await tester.pumpAndSettle();

      // Banner should NOT be displayed
      expect(find.textContaining('Grading unavailable'), findsNothing);

      // Warning icon replaced by memory icon
      expect(find.byIcon(Icons.warning_amber), findsNothing);
      expect(find.byIcon(Icons.memory), findsOneWidget);

      // FAB is enabled
      final fab = tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));
      expect(fab.onPressed, isNotNull);
    });
  });
}
