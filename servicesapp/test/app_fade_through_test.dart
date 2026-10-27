import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/theme/app_motion_tokens.dart';
import 'package:servicesapp/core/widgets/app_motion.dart';

double _opacity(WidgetTester tester, String text) => tester
    .widget<FadeTransition>(
      find
          .ancestor(of: find.text(text), matching: find.byType(FadeTransition))
          .first,
    )
    .opacity
    .value;

void main() {
  testWidgets('fade-through: o que sai e o que entra nunca se veem juntos', (
    tester,
  ) async {
    Widget app(String key) => MaterialApp(
      home: AppFadeThroughSwitcher(switchKey: key, child: Text(key)),
    );
    await tester.pumpWidget(app('Semana'));
    await tester.pumpWidget(app('Mês'));

    final step = AppMotionDuration.screen ~/ 10;
    for (var i = 0; i < 9; i++) {
      await tester.pump(step);
      final out = _opacity(tester, 'Semana');
      final into = _opacity(tester, 'Mês');
      expect(out == 0 || into == 0, isTrue, reason: 'passo $i: $out e $into');
    }
    await tester.pumpAndSettle();
    expect(find.text('Semana'), findsNothing);
    expect(find.text('Mês'), findsOneWidget);
  });
}
