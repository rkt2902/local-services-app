import 'package:flutter_test/flutter_test.dart';

import 'package:servicesapp/core/constants/password_policy.dart';
import 'package:servicesapp/core/utils/error_utils.dart';

// O smoke test antigo fazia pumpWidget(App()) sem inicializar o Supabase e
// falhava sempre. Estes testes cobrem lógica pura que não precisa de rede.
void main() {
  group('passwordPolicyValidator', () {
    test('aceita password com 8+, maiúscula e número', () {
      expect(passwordPolicyValidator('Jardim2026'), isNull);
    });

    test('recusa password sem maiúscula', () {
      expect(passwordPolicyValidator('jardim2026'), weakPasswordMessage);
    });

    test('recusa password vazia', () {
      expect(passwordPolicyValidator(''), isNotNull);
    });
  });

  group('friendlyError', () {
    test('erro de rede', () {
      expect(
        friendlyError(Exception('SocketException: Failed host lookup')),
        contains('internet'),
      );
    });

    test('limite de pedidos da policy de job_requests', () {
      expect(
        friendlyError(Exception(
          'new row violates row-level security policy for table "job_requests"',
        )),
        contains('vários pedidos'),
      );
    });

    test('RLS noutra tabela continua a ser falta de permissão', () {
      expect(
        friendlyError(Exception(
          'new row violates row-level security policy for table "ratings"',
        )),
        'Não tens permissão para esta ação.',
      );
    });
  });
}
