import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/widgets/app_adaptive_shell.dart';
import 'package:servicesapp/core/widgets/app_bottom_navigation.dart';

Widget _shell(
  Size size,
  ValueChanged<int> onSelected, {
  Widget child = const Text('conteúdo'),
  VoidCallback? onCentral,
}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      home: AppAdaptiveShell(
        selectedIndex: 0,
        onItemSelected: onSelected,
        onCentralActionPressed: onCentral ?? () {},
        centralActionTooltip: 'Criar pedido',
        items: const [
          AppBottomNavigationItem(
            label: 'A',
            icon: Icons.home,
            selectedIcon: Icons.home,
          ),
          AppBottomNavigationItem(
            label: 'B',
            icon: Icons.list,
            selectedIcon: Icons.list,
          ),
          AppBottomNavigationItem(
            label: 'C',
            icon: Icons.event,
            selectedIcon: Icons.event,
          ),
          AppBottomNavigationItem(
            label: 'D',
            icon: Icons.person,
            selectedIcon: Icons.person,
          ),
        ],
        child: child,
      ),
    ),
  );
}

void main() {
  testWidgets('telemóvel mostra a bottom nav', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_shell(const Size(390, 844), (_) {}));
    expect(find.byType(AppBottomNavigation), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('PC mostra a navegação lateral com os mesmos destinos', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    int? selected;
    await tester.pumpWidget(_shell(const Size(1440, 900), (i) => selected = i));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(AppBottomNavigation), findsNothing);
    await tester.tap(find.text('C'));
    expect(selected, 2);
    expect(tester.getSize(find.text('conteúdo')).width, lessThanOrEqualTo(720));
  });

  testWidgets('telemóvel deitado continua com a bottom nav', (tester) async {
    tester.view.physicalSize = const Size(932, 430);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_shell(const Size(932, 430), (_) {}));
    expect(find.byType(AppBottomNavigation), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('trocar de bottom nav para lateral mantém o estado do ecrã', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const field = TextField();
    await tester.pumpWidget(
      _shell(const Size(700, 1000), (_) {}, child: field),
    );
    await tester.enterText(find.byType(TextField), 'texto');
    tester.view.physicalSize = const Size(1200, 1000);
    await tester.pumpWidget(
      _shell(const Size(1200, 1000), (_) {}, child: field),
    );
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('texto'), findsOneWidget);
  });

  testWidgets('tablet ao alto (800) fica com a bottom nav', (tester) async {
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_shell(const Size(800, 1280), (_) {}));
    expect(find.byType(AppBottomNavigation), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('exatamente 840 já usa a lateral, com o "+" no topo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(840, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var central = 0;
    await tester.pumpWidget(
      _shell(const Size(840, 900), (_) {}, onCentral: () => central++),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.tap(find.byTooltip('Criar pedido'));
    expect(central, 1);
  });
}
