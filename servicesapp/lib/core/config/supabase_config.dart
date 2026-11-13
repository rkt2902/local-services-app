class SupabaseConfig {
  SupabaseConfig._();

  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Nomes dos `--dart-define` obrigatórios que faltam neste build.
  static List<String> get missingKeys => missingKeysFor(url, anonKey);

  static List<String> missingKeysFor(String url, String anonKey) => [
        if (url.trim().isEmpty) 'SUPABASE_URL',
        if (anonKey.trim().isEmpty) 'SUPABASE_ANON_KEY',
      ];

  static bool get isConfigured => missingKeys.isEmpty;
}
