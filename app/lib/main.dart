import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n/app_localizations.dart';
import 'screens/admin/admin_home.dart';
import 'screens/auth_screen.dart';
import 'screens/farmer/farmer_home.dart';
import 'screens/officer/officer_home.dart';
import 'state/app_state.dart';
import 'widgets/gov_ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ChangeNotifierProvider(create: (_) => AppState()..init(), child: const OniGraderApp()));
}

class OniGraderApp extends StatelessWidget {
  const OniGraderApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    final govTheme = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: GovColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: GovColors.navy,
        primary: GovColors.navy,
        secondary: GovColors.saffronDark,
        surface: Colors.white,
        error: GovColors.error,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: GovColors.navy,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: GovColors.navy,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: GovColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: GovColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: GovColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: GovColors.navy, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: GovColors.error),
        ),
        labelStyle: const TextStyle(color: GovColors.textSecondary, fontSize: 13),
        hintStyle: const TextStyle(color: GovColors.textMuted, fontSize: 13),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: GovColors.navy,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: GovColors.navy,
          side: const BorderSide(color: GovColors.navy),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: GovColors.border,
        thickness: 1,
        space: 1,
      ),
    );

    return MaterialApp(
      title: 'OniGrader — National Mandi Quality Portal',
      debugShowCheckedModeBanner: false,
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
      theme: govTheme,
      home: const Root(),
    );
  }
}

class Root extends StatelessWidget {
  const Root({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (!s.ready) {
      return const Scaffold(
        backgroundColor: GovColors.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GovEmblemPlaceholder(size: 54),
              SizedBox(height: 16),
              CircularProgressIndicator(color: GovColors.navy),
              SizedBox(height: 12),
              Text(
                'Connecting to Mandi Gateway…',
                style: TextStyle(color: GovColors.navy, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
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
