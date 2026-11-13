import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/features/notifications/application/notification_handler.dart';

void main() {
  group('pushTapBaseLocation', () {
    test('no arranque vai primeiro para a home do papel', () {
      expect(
        pushTapBaseLocation(currentPath: '/loading', role: UserRole.worker),
        '/worker/home',
      );
      expect(
        pushTapBaseLocation(currentPath: '/', role: UserRole.client),
        '/client/home',
      );
    });

    test('já dentro da app não muda a base', () {
      expect(
        pushTapBaseLocation(currentPath: '/worker/home', role: UserRole.worker),
        isNull,
      );
      expect(
        pushTapBaseLocation(
          currentPath: '/worker/available-jobs',
          role: UserRole.worker,
        ),
        isNull,
      );
    });

    test('sem papel não faz nada', () {
      expect(pushTapBaseLocation(currentPath: '/loading', role: null), isNull);
    });
  });
}
