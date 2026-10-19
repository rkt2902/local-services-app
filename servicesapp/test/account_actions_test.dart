import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/widgets/app_account_menu_group.dart';
import 'package:servicesapp/core/widgets/app_confirm_dialog.dart';
import 'package:servicesapp/core/widgets/app_support_sheet.dart';

/// Conta (design U7): ações perigosas, diálogos em dois passos e suporte.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('ações perigosas não têm seta', (tester) async {
    await tester.pumpWidget(wrap(AppAccountMenuGroup(
      items: const [
        AppAccountMenuItem(id: 'about', label: 'Sobre', icon: Icons.info),
        AppAccountMenuItem(
          id: 'delete',
          label: 'Eliminar conta',
          icon: Icons.delete_outline_rounded,
          destructive: true,
        ),
      ],
      onItemPressed: (_) {},
    )));
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
  });

  testWidgets('diálogo com passo e sem ícone', (tester) async {
    await tester.pumpWidget(wrap(AppConfirmDialog(
      icon: null,
      title: 'Eliminar conta?',
      stepLabel: '1/2',
      confirmLabel: 'Continuar',
      destructive: true,
      outlinedConfirm: true,
      onConfirm: () {},
      onCancel: () {},
    )));
    await tester.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Continuar'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  test('mailto do suporte com assunto', () {
    final uri = supportMailtoUri('suporte@projardim.pt');
    expect(uri.scheme, 'mailto');
    expect(uri.path, 'suporte@projardim.pt');
    expect(uri.toString(), contains('subject=Ajuda%20ProJardim'));
  });

  testWidgets('folha de suporte com email e as duas ações', (tester) async {
    var copied = 0;
    var composed = 0;
    await tester.pumpWidget(wrap(AppSupportSheet(
      email: 'suporte@projardim.pt',
      responseTimeLabel: 'Respondemos em 1 dia útil',
      onClose: () {},
      onCopyEmail: () => copied++,
      onComposeEmail: () => composed++,
    )));
    await tester.pumpAndSettle();
    expect(find.text('suporte@projardim.pt'), findsOneWidget);
    await tester.tap(find.text('Copiar email'));
    await tester.tap(find.text('Escrever'));
    expect(copied, 1);
    expect(composed, 1);
  });
}
