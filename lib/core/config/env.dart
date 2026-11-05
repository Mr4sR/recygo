class Env {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );
  static const bool demoMode = bool.fromEnvironment('DEMO_MODE');
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
  );

  static bool get useBackend => backendBaseUrl.isNotEmpty && !demoMode;
  static bool get isConfigured =>
      demoMode ||
      useBackend ||
      (supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty);
}
