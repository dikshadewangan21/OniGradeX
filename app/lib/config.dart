import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Build-time and runtime endpoint configuration.
/// Defaults detect platform (Android emulator uses 10.0.2.2, desktop/web uses 127.0.0.1)
/// or can be passed via --dart-define=API_BASE_URL=... or changed in-app.
class AppConfig {
  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get defaultBaseUrl {
    if (_envBaseUrl.isNotEmpty) return _envBaseUrl;
    if (kIsWeb) return 'http://127.0.0.1:8000';
    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    } catch (_) {}
    return 'http://127.0.0.1:8000';
  }

  static String apiBaseUrl = defaultBaseUrl;
  static bool get isConfigured => apiBaseUrl.isNotEmpty;
}
