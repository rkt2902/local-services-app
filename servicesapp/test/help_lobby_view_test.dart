import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/core/utils/app_status_presenters.dart';
import 'package:servicesapp/features/help_requests/presentation/widgets/worker_help_requests_lobby_view.dart';

WorkerHelpCandidateViewData _candidate(String id, {String? message, bool blocked = false}) =>
    WorkerHelpCandidateViewData(
      applicationId: id,
      workerId: 'w-$id',
      name: 'Candidato $id',
      equipmentLabel: 'Traz equipamento',
      statusPresentation: HelpAcceptanceStatus.pending.presentation,
      actionsBlocked: blocked,
      blockedReasonLabel: blocked ? 'Vagas já preenchidas.' : null,
      message: message,
      acceptance: const AcceptHelperViewData(
        initialRateInput: '12.00',
        suggestedRateLabel: 'Sugerido: €12.00/hora',
      ),
    );

Widget _lobby(List<WorkerHelpCandidateViewData> candidates) {
  return MaterialApp(
    home: WorkerHelpRequestsLobbyView(
      dataAsync: AsyncValue.data(WorkerHelpLobbyViewData(
        jobReferenceLabel: 'Job #abc',
        responsibleName: 'Rui',
        sections: [
          HelpRequestSectionViewData(
            helpRequestId: 'h1',
            displayMode: WorkerHelpSectionDisplayMode.active,
            statusPresentation: HelpRequestStatus.open.presentation,
            filledPlacesLabel: '0 de 1 vaga preenchida',
            filledProgress: 0,
            acceptedHelpers: const [],
            pendingCandidates: candidates,
          ),
        ],
      )),
      onBack: () {},
      onRequestHelpers: () {},
      onAcceptCandidate: (_, _) async => true,
      onRejectCandidate: (_) async => true,
      onViewRatings: (_, _) {},
    ),
  );
}

void main() {
  testWidgets('mostra a mensagem só de quem a escreveu', (tester) async {
    await tester.pumpWidget(_lobby([
      _candidate('1', message: 'Tenho corta-relva e carrinha.'),
      _candidate('2'),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('Candidato 1'), findsOneWidget);
    expect(find.text('Candidato 2'), findsOneWidget);
    expect(find.text('Tenho corta-relva e carrinha.'), findsOneWidget);
    expect(find.text('Mensagem'), findsOneWidget);
  });

  testWidgets('candidato bloqueado mostra a razão', (tester) async {
    await tester.pumpWidget(_lobby([_candidate('1', blocked: true)]));
    await tester.pumpAndSettle();

    expect(find.text('Vagas já preenchidas.'), findsOneWidget);
  });
}
