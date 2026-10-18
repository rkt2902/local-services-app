import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/core/utils/app_status_presenters.dart';
import 'package:servicesapp/features/help_requests/presentation/widgets/worker_help_requests_lobby_view.dart';

Widget _lobby({required bool canManage, List<String>? calls}) {
  return MaterialApp(
    home: WorkerHelpRequestsLobbyView(
      dataAsync: AsyncValue.data(WorkerHelpLobbyViewData(
        jobReferenceLabel: 'Poda · Braga',
        responsibleName: 'Rui',
        sections: [
          HelpRequestSectionViewData(
            helpRequestId: 'h1',
            displayMode: WorkerHelpSectionDisplayMode.active,
            statusPresentation: HelpRequestStatus.open.presentation,
            filledPlacesLabel: '1 de 2 vagas preenchidas',
            filledProgress: 0.5,
            slotsNeeded: 2,
            canManage: canManage,
            acceptedHelpers: [
              WorkerAcceptedHelperViewData(
                applicationId: 'acc1',
                workerId: 'w1',
                name: 'Ana',
                equipmentLabel: 'Traz equipamento',
                statusPresentation: HelpAcceptanceStatus.accepted.presentation,
              ),
            ],
            pendingCandidates: const [],
          ),
        ],
      )),
      onBack: () {},
      onRequestHelpers: () {},
      onAcceptCandidate: (_, _) async => true,
      onRejectCandidate: (_) async => true,
      onViewRatings: (_, _) {},
      onChangeSlots: (id, slots) async {
        calls?.add('slots:$id:$slots');
        return true;
      },
      onCloseHelpRequest: (id) async {
        calls?.add('close:$id');
        return true;
      },
      onRemoveHelper: (id) async {
        calls?.add('remove:$id');
        return true;
      },
    ),
  );
}

void main() {
  testWidgets('sem gestão não mostra as ações de equipa', (tester) async {
    await tester.pumpWidget(_lobby(canManage: false));
    await tester.pumpAndSettle();
    expect(find.text('Alterar vagas'), findsNothing);
    expect(find.text('Retirar da equipa'), findsNothing);
  });

  testWidgets('retirar da equipa pede confirmação e chama a ação', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(_lobby(canManage: true, calls: calls));
    await tester.pumpAndSettle();
    expect(find.text('Alterar vagas'), findsOneWidget);
    expect(find.text('Fechar pedido de ajuda'), findsOneWidget);

    await tester.tap(find.text('Retirar da equipa'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Retirar'));
    await tester.pumpAndSettle();
    expect(calls, ['remove:acc1']);
  });

  testWidgets('alterar vagas não desce abaixo dos aceites', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(_lobby(canManage: true, calls: calls));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alterar vagas'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Menos uma vaga'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    // Já no mínimo (1 aceite): o botão fica desligado.
    final minus = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.remove_rounded),
    );
    expect(minus.onPressed, isNull);

    await tester.tap(find.byTooltip('Mais uma vaga'));
    await tester.tap(find.byTooltip('Mais uma vaga'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(calls, ['slots:h1:3']);
  });

  test('mínimo de vagas', () {
    expect(lobbySlotsMinimum(0), 1);
    expect(lobbySlotsMinimum(3), 3);
    expect(lobbySlotsMinimum(12), lobbyMaxSlots);
  });
}
