/// Build-time configuration. No server address is baked into source.
/// flutter run --dart-define=API_BASE_URL=https://api.example.org
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static bool get isConfigured => apiBaseUrl.isNotEmpty;
}
