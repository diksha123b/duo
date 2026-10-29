/// Build-time configuration, set with `--dart-define`.
///
///   flutter run -d chrome --dart-define=API_URL=http://localhost:3000
///
/// The Android emulator reaches the host machine at 10.0.2.2, not localhost.
class AppConfig {
  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');

  /// OAuth client IDs. Google sign-in is hidden when these are empty.
  /// Web uses the web client ID; Android needs it as the "server" client ID
  /// so the ID token's audience matches what the API verifies.
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// Crash reporting is off unless a DSN is provided.
  static const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  static bool get googleEnabled => googleWebClientId.isNotEmpty;
}
