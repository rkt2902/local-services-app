import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/config/supabase_config.dart';

void main() {
  group('SupabaseConfig.missingKeysFor (AUD-04)', () {
    test('com as duas chaves não falta nada', () {
      expect(
        SupabaseConfig.missingKeysFor('https://x.supabase.co', 'k'),
        isEmpty,
      );
    });

    test('lista as que faltam, mesmo só com espaços', () {
      expect(SupabaseConfig.missingKeysFor('', '  '), [
        'SUPABASE_URL',
        'SUPABASE_ANON_KEY',
      ]);
      expect(SupabaseConfig.missingKeysFor('https://x', ''), [
        'SUPABASE_ANON_KEY',
      ]);
    });

    test('nos testes (sem --dart-define) a app não está configurada', () {
      expect(SupabaseConfig.isConfigured, isFalse);
    });
  });
}
