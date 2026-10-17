import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/widgets/app_adaptive_shell.dart';
import 'package:servicesapp/core/widgets/app_bottom_navigation.dart';

Widget _shell(Size size, ValueChanged<int> onSelected) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      home: AppAdaptiveShell(
        selectedIndex: 0,
        onItemSelected: onSelected,
        onCentralActionPressed: () {},
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
        child: const Text('conteúdo'),
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
    expect(tester.getSize(find.text('conteúdo')).width, lessThanOrEqualTo(640));
  });
}
