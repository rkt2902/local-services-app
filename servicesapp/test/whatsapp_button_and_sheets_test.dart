import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/widgets/app_about_dialog.dart';
import 'package:servicesapp/core/widgets/app_whatsapp_button.dart';
import 'package:servicesapp/features/ratings/presentation/submit_rating_sheet.dart';

void main() {
  testWidgets('WhatsApp compacto fica numa linha ao lado de um nome',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              const Expanded(child: Text('Henrique')),
              AppWhatsAppButton(onPressed: () {}, compact: true),
            ],
          ),
        ),
      ),
    );
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.byIcon(appWhatsAppIcon), findsOneWidget);
    final label = tester.getSize(find.text('WhatsApp'));
    final button = tester.getSize(find.byType(AppWhatsAppButton));
    expect(label.height, lessThan(button.height));
    expect(tester.takeException(), isNull);
  });

  testWidgets('folha de avaliação: enviar só com estrelas', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) {
          ctx = context;
          return const Scaffold();
        }),
      ),
    );
    int? sent;
    showSubmitRatingSheet(
      context: ctx,
      title: 'Avaliar o trabalho',
      successMessage: 'Obrigado!',
      onSubmit: (stars, _) async => sent = stars,
    );
    await tester.pumpAndSettle();
    expect(find.text('Avaliar o trabalho'), findsOneWidget);
    expect(find.text('Toca nas estrelas para dar a nota'), findsOneWidget);

    await tester.tap(find.text('Enviar avaliação'));
    await tester.pumpAndSettle();
    expect(sent, isNull);

    await tester.tap(find.byIcon(Icons.star_border_rounded).last);
    await tester.pumpAndSettle();
    expect(find.text('Excelente'), findsOneWidget);
    await tester.tap(find.text('Enviar avaliação'));
    await tester.pumpAndSettle();
    expect(sent, 5);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('Sobre a ProJardim em português, com logo e links',
      (tester) async {
    var licenses = 0;
    var closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppAboutDialog(
            onClose: () => closed++,
            onTerms: () {},
            onPrivacy: () {},
            onLicenses: () => licenses++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Versão $appVersionLabel'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('View licenses'), findsNothing);
    await tester.tap(find.text('Licenças de software'));
    await tester.tap(find.text('Fechar'));
    expect(licenses, 1);
    expect(closed, 1);
  });
}
