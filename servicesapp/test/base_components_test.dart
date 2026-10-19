import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/theme/app_status_color.dart';
import 'package:servicesapp/core/theme/app_status_presentation.dart';
import 'package:servicesapp/core/widgets/app_confirm_dialog.dart';
import 'package:servicesapp/core/widgets/app_empty_state.dart';
import 'package:servicesapp/core/widgets/next_step_row.dart';
import 'package:servicesapp/core/widgets/todo_row.dart';
import 'package:servicesapp/features/worker/presentation/widgets/worker_quick_actions_sheet.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('AppConfirmDialog.show', () {
    Future<bool?> open(WidgetTester tester, {required String tap}) async {
      bool? result;
      await tester.pumpWidget(_app(Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await AppConfirmDialog.show(
              context,
              icon: Icons.person_remove_outlined,
              title: 'Retirar Rui da equipa?',
              message: 'O Rui é avisado e a vaga volta a ficar aberta.',
              confirmLabel: 'Retirar',
              destructive: true,
            );
          },
          child: const Text('abrir'),
        ),
      )));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Retirar Rui da equipa?'), findsOneWidget);
      await tester.tap(find.text(tap));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('confirmar devolve true', (tester) async {
      expect(await open(tester, tap: 'Retirar'), isTrue);
    });

    testWidgets('Voltar devolve false', (tester) async {
      expect(await open(tester, tap: 'Voltar'), isFalse);
    });
  });

  testWidgets('a submeter, os botões ficam bloqueados e o erro aparece',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(AppConfirmDialog(
      icon: Icons.delete_forever_outlined,
      title: 'Tens a certeza?',
      message: 'Texto',
      confirmLabel: 'Eliminar conta',
      destructive: true,
      isSubmitting: true,
      errorText: 'Erro do servidor',
      onConfirm: () => taps++,
      onCancel: () => taps++,
    )));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Voltar'));
    expect(taps, 0);
    expect(find.text('Erro do servidor'), findsOneWidget);
  });

  testWidgets('AppEmptyState só mostra o botão quando há ação', (tester) async {
    var pressed = false;
    await tester.pumpWidget(_app(AppEmptyState(
      icon: Icons.inbox_outlined,
      title: 'Ainda sem candidaturas',
      message: 'Candidata-te a um pedido de ajuda.',
      actionLabel: 'Descobrir pedidos',
      onAction: () => pressed = true,
    )));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Descobrir pedidos'));
    expect(pressed, isTrue);

    await tester.pumpWidget(_app(const AppEmptyState(
      icon: Icons.history_rounded,
      title: 'Sem histórico',
      message: 'Nada aqui.',
      tone: AppStatusColor.neutral,
    )));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('NextStepRow usa o estado curto e o toque chega a quem o usa',
      (tester) async {
    var pressed = false;
    await tester.pumpWidget(_app(NextStepRow(
      icon: Icons.grass,
      title: 'Corte de relva',
      status: const AppStatusPresentation(
        label: 'À espera de proposta',
        color: AppStatusColor.waiting,
      ),
      subtitle: 'Tens 2 propostas para ver.',
      needsAction: true,
      onPressed: () => pressed = true,
    )));
    expect(find.text('Em aberto'), findsOneWidget);
    await tester.tap(find.text('Corte de relva'));
    expect(pressed, isTrue);
  });

  testWidgets('TodoRow mostra o texto e responde ao toque', (tester) async {
    var pressed = false;
    await tester.pumpWidget(_app(TodoRow(
      icon: Icons.task_alt_rounded,
      tone: AppStatusColor.cancelled,
      title: '2 trabalhos por concluir',
      onPressed: () => pressed = true,
    )));
    await tester.tap(find.text('2 trabalhos por concluir'));
    expect(pressed, isTrue);
  });

  testWidgets('folha do "+" só mostra o Cartão frota quando está ativo',
      (tester) async {
    Widget sheet({required bool fleet}) => _app(WorkerQuickActionsSheet(
          showFleetCard: fleet,
          onFindWork: () {},
          onOpenHelpRequests: () {},
          onOpenFleetCard: () {},
        ));
    await tester.pumpWidget(sheet(fleet: false));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Encontrar trabalho'), findsOneWidget);
    expect(find.text('Pedidos de ajuda'), findsOneWidget);
    expect(find.text('Cartão frota'), findsNothing);

    await tester.pumpWidget(sheet(fleet: true));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Cartão frota'), findsOneWidget);
  });
}
