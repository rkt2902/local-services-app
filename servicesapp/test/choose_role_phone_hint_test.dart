import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/features/auth/presentation/choose_role_screen.dart';

void main() {
  group('phoneUsageHint', () {
    test('cliente: quem contacta é o jardineiro', () {
      expect(phoneUsageHint(UserRole.client), contains('jardineiro'));
    });

    test('jardineiro: quem contacta é o cliente', () {
      expect(phoneUsageHint(UserRole.worker), contains('cliente'));
    });

    test('sem papel escolhido: texto neutro sobre WhatsApp', () {
      final hint = phoneUsageHint(null);
      expect(hint, contains('WhatsApp'));
      expect(hint, isNot(contains('jardineiro')));
    });
  });
}
