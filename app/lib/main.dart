import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'l10n/app_localizations.dart';
import 'screens/admin/admin_home.dart';
import 'screens/auth_screen.dart';
import 'screens/farmer/farmer_home.dart';
import 'screens/officer/officer_home.dart';
import 'state/app_state.dart';

void main() {
  runApp(ChangeNotifierProvider(create: (_) => AppState()..init(), child: const OniGraderApp()));
}

class OniGraderApp extends StatelessWidget {
  const OniGraderApp({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      title: 'OniGrader',
      locale: state.currentLocale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('hi'),
        Locale('mr'),
      ],
      theme: ThemeData(colorSchemeSeed: const Color(0xFF7B1FA2), useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF7B1FA2), useMaterial3: true, brightness: Brightness.dark),
      home: const Root(),
    );
  }
}

class Root extends StatelessWidget {
  const Root({super.key});
  @override
  Widget build(BuildContext context) {
    if (!AppConfig.isConfigured) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('This build has no server address.\nRebuild with --dart-define=API_BASE_URL=https://your-server',
                textAlign: TextAlign.center),
          ),
        ),
      );
    }
    final s = context.watch<AppState>();
    if (!s.ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    switch (s.session?.role) {
      case 'officer':
        return const OfficerHome();
      case 'farmer':
        return const FarmerHome();
      case 'admin':
        return const AdminHome();
      default:
        return const AuthScreen();
    }
  }
}
