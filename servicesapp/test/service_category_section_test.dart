import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:servicesapp/core/widgets/service_category_section.dart';

void main() {
  testWidgets('abre ao tocar e o selecionar todos chama o callback',
      (tester) async {
    var expanded = false;
    bool? selectAll;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ServiceCategorySection(
              icon: Icons.forest_outlined,
              title: 'Floresta',
              summary: '9 serviços',
              expanded: expanded,
              onToggle: () => setState(() => expanded = !expanded),
              onSelectAll: (value) => selectAll = value,
              child: const Text('Abate de árvores'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Floresta'), findsOneWidget);
    expect(find.text('Abate de árvores'), findsNothing);

    await tester.tap(find.text('Floresta'));
    await tester.pumpAndSettle();
    expect(find.text('Abate de árvores'), findsOneWidget);

    await tester.tap(find.text('Selecionar todos'));
    expect(selectAll, isTrue);
  });
}
