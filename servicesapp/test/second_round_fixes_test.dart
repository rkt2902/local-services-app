import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/utils/error_utils.dart';
import 'package:servicesapp/core/widgets/app_bottom_navigation.dart';

Widget _nav(int alerts) => MaterialApp(
  home: Scaffold(
    bottomNavigationBar: AppBottomNavigation(
      selectedIndex: 0,
      onItemSelected: (_) {},
      onCentralActionPressed: () {},
      items: [
        const AppBottomNavigationItem(
          label: 'Início',
          icon: Icons.home,
          selectedIcon: Icons.home,
        ),
        const AppBottomNavigationItem(
          label: 'Pedidos',
          icon: Icons.list,
          selectedIcon: Icons.list,
        ),
        AppBottomNavigationItem(
          label: 'Alertas',
          icon: Icons.notifications,
          selectedIcon: Icons.notifications,
          badgeCount: alerts,
        ),
        const AppBottomNavigationItem(
          label: 'Perfil',
          icon: Icons.person,
          selectedIcon: Icons.person,
        ),
      ],
    ),
  ),
);

void main() {
  group('TM-043: contador de Alertas do cliente', () {
    testWidgets('mostra o número por ler', (tester) async {
      await tester.pumpWidget(_nav(3));
      expect(find.text('3'), findsOneWidget);
      expect(find.bySemanticsLabel('Alertas, 3 por ler'), findsOneWidget);
    });

    testWidgets('mais de 9 fica 9+', (tester) async {
      await tester.pumpWidget(_nav(12));
      expect(find.text('9+'), findsOneWidget);
    });

    testWidgets('sem nada por ler não mostra contador', (tester) async {
      await tester.pumpWidget(_nav(0));
      expect(find.text('0'), findsNothing);
      expect(find.bySemanticsLabel('Alertas'), findsOneWidget);
    });
  });

  group('TM-017: sem rede na web', () {
    test('Failed to fetch é falta de rede', () {
      expect(
        friendlyError(
          Exception('ClientException: Failed to fetch, uri=http://x'),
        ),
        contains('Sem ligação'),
      );
    });
    test('XMLHttpRequest error é falta de rede', () {
      expect(isNetworkError(Exception('XMLHttpRequest error.')), isTrue);
    });
  });
}
