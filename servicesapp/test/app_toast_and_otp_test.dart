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

  testWidgets('navegar com o aviso aberto não o faz entrar outra vez',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navKey, home: const Scaffold()),
    );

    // Contexto do Navigator raiz, como em app.dart (avisos de notificações).
    // Regra T4: navegar e logo a seguir o aviso. A transição da rota volta a
    // construir o Overlay; o aviso tem de manter o seu tempo.
    AppToast.of(navKey.currentContext!).show('Guardado.');
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    navKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold()),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Guardado.'), findsNothing);
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

  Future<String?> pumpOtp(WidgetTester tester) async {
    String? completed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppOtpInput(onCompleted: (code) => completed = code),
        ),
      ),
    );
    return completed;
  }

  testWidgets('colar o código inteiro na primeira caixa preenche as 6',
      (tester) async {
    String? completed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppOtpInput(onCompleted: (code) => completed = code),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, '489590');
    await tester.pump();
    expect(completed, '489590');
    final texts = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.controller!.text)
        .join();
    expect(texts, '489590');
  });

  testWidgets('escrever por cima de uma caixa cheia troca o dígito',
      (tester) async {
    await pumpOtp(tester);
    final first = find.byType(TextField).first;
    await tester.enterText(first, '4');
    await tester.pump();
    await tester.showKeyboard(first);
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '47',
      selection: TextSelection.collapsed(offset: 2),
    ));
    await tester.pump();
    final firstField = tester.widget<TextField>(first);
    expect(firstField.controller!.text, '7');
  });
}
