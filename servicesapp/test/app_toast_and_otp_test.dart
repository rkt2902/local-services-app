import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/widgets/app_otp_input.dart';
import 'package:servicesapp/core/widgets/app_toast.dart';

void main() {
  testWidgets('AppToast aparece no topo e some sozinho', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => AppToast.of(context).show('Pedido cancelado.'),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    final toast = find.text('Pedido cancelado.');
    expect(toast, findsOneWidget);
    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getCenter(toast).dy, lessThan(screenHeight / 4));

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(toast, findsNothing);
  });

  testWidgets('um aviso novo substitui o anterior', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) {
          ctx = context;
          return const Scaffold();
        }),
      ),
    );

    AppToast.of(ctx).show('Primeiro');
    await tester.pump();
    AppToast.of(ctx).error('Segundo');
    await tester.pumpAndSettle();
    expect(find.text('Primeiro'), findsNothing);
    expect(find.text('Segundo'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('AppOtpInput cabe num ecrã estreito sem overflow', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              child: AppOtpInput(onCompleted: (_) {}),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsNWidgets(6));
  });
}
