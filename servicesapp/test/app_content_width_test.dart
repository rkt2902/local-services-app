import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/widgets/app_content_width.dart';

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
}

void main() {
  testWidgets('telemóvel: o ecrã ocupa exatamente o ecrã todo', (tester) async {
    _setSize(tester, const Size(390, 844));
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: AppContentWidth(child: Scaffold(key: key)),
      ),
    );
    expect(tester.getSize(find.byKey(key)), const Size(390, 844));
  });

  testWidgets('PC: o ecrã fica com 720 de largura e a altura toda', (
    tester,
  ) async {
    _setSize(tester, const Size(1440, 900));
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: AppContentWidth(child: Scaffold(key: key)),
      ),
    );
    expect(tester.getSize(find.byKey(key)).height, 900);
    expect(tester.getSize(find.byKey(key)).width, lessThanOrEqualTo(720));
  });

  testWidgets('rodar o telemóvel não apaga o que foi escrito', (tester) async {
    _setSize(tester, const Size(390, 844));
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: AppContentWidth(child: Scaffold(body: TextField())),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Rua das Flores');
    _setSize(tester, const Size(844, 390));
    await tester.pump();
    expect(find.text('Rua das Flores'), findsOneWidget);
  });
}
