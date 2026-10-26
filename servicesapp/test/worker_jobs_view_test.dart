import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/theme/app_status_color.dart';
import 'package:servicesapp/core/theme/app_status_presentation.dart';
import 'package:servicesapp/features/worker/data/worker_job_board_entry_model.dart';
import 'package:servicesapp/features/worker/presentation/widgets/worker_jobs_view.dart';
import 'package:servicesapp/features/worker/presentation/worker_jobs_screen.dart'
    hide WorkerJobsScreen;

WorkerJobBoardEntry _entry({
  WorkerJobBoardRole role = WorkerJobBoardRole.responsible,
  String status = 'accepted',
  String? jobStatus = 'confirmed',
  DateTime? confirmedDate,
  String? confirmedTime,
  DateTime? markedDoneAt,
  String? cancelReason,
  bool cancelledByClient = false,
  DateTime? jobUpdatedAt,
}) => WorkerJobBoardEntry(
  entryId: 'e1',
  role: role,
  jobId: 'j1',
  serviceTypeName: 'Corte de relva',
  personName: 'João Pires',
  addressText: 'Rua das Flores 12, Cascais',
  locationArea: 'Cascais',
  confirmedDate: confirmedDate,
  confirmedTime: confirmedTime,
  hourlyRate: 20,
  estimatedHoursMin: 3,
  status: status,
  createdAt: DateTime(2026, 10, 17, 10),
  jobStatus: jobStatus,
  markedDoneAt: markedDoneAt,
  cancelReason: cancelReason,
  cancelledByClient: cancelledByClient,
  jobUpdatedAt: jobUpdatedAt,
);

WorkerJobListItemViewData _item(
  String id, {
  String? role,
  bool muted = false,
  String status = 'Agendado',
}) => WorkerJobListItemViewData(
  id: id,
  title: 'Serviço $id',
  serviceIcon: Icons.yard_outlined,
  metaLabel: 'Detalhe $id',
  status: AppStatusPresentation(label: status, color: AppStatusColor.success),
  roleLabel: role,
  muted: muted,
);

Widget _screen({
  WorkerJobsSection section = WorkerJobsSection.proposals,
  WorkerJobsTabViewData pending = const WorkerJobsTabViewData(),
  WorkerJobsTabViewData history = const WorkerJobsTabViewData(),
  VoidCallback? onFind,
  ValueChanged<WorkerJobsSection>? onSection,
}) {
  return MaterialApp(
    home: WorkerJobsScreen(
      selectedSection: section,
      agenda: const Text('corpo da agenda'),
      proposalsCount: 3,
      pending: pending,
      history: history,
      onSectionSelected: onSection ?? (_) {},
      onNotificationsPressed: () {},
      onColorsPressed: () {},
      onJobPressed: (_) {},
      onLoadMore: (_) {},
      onFindJobsPressed: onFind,
    ),
  );
}

void main() {
  final now = DateTime(2026, 10, 19, 10);

  group('texto dos cartões (design A2)', () {
    test('agendado como responsável: dia, hora, zona e valor', () {
      final t = workerJobCardText(
        _entry(
          confirmedDate: DateTime(2026, 10, 19),
          confirmedTime: '09:00:00',
        ),
        WorkerJobsTab.scheduled,
        now,
      );
      expect(t.meta, 'Hoje · 9:00 · Cascais');
      expect(t.amount, '≈ 60 €');
    });

    test('agendado como ajudante: com quem e sem valor', () {
      final t = workerJobCardText(
        _entry(
          role: WorkerJobBoardRole.helper,
          confirmedDate: DateTime(2026, 10, 23),
          confirmedTime: '08:30:00',
        ),
        WorkerJobsTab.scheduled,
        now,
      );
      expect(t.meta, 'Sex, 23/10 · 8:30 · com João Pires');
      expect(t.amount, isNull);
    });

    test('à espera do cliente: feito a e horas até confirmar sozinho', () {
      final t = workerJobCardText(
        _entry(
          jobStatus: 'awaiting_confirmation',
          markedDoneAt: DateTime(2026, 10, 18, 17),
        ),
        WorkerJobsTab.scheduled,
        now,
      );
      expect(t.meta, 'Feito a 18/10 · confirma automaticamente em 31h');
    });

    test('histórico: concluído, cancelado, não selecionada e expirado', () {
      final updated = DateTime(2026, 10, 16, 12);
      String meta(WorkerJobBoardEntry e) =>
          workerJobCardText(e, WorkerJobsTab.history, now).meta;

      expect(
        meta(_entry(jobStatus: 'completed', jobUpdatedAt: updated)),
        '16/10 · Cascais · ≈ 60 €',
      );
      expect(
        meta(
          _entry(
            jobStatus: 'cancelled',
            cancelledByClient: true,
            jobUpdatedAt: updated,
          ),
        ),
        '16/10 · cancelado pelo cliente',
      );
      expect(
        meta(
          _entry(
            status: 'rejected',
            jobStatus: 'confirmed',
            jobUpdatedAt: updated,
          ),
        ),
        '16/10 · o cliente escolheu outra proposta',
      );
      expect(
        meta(
          _entry(
            status: 'pending',
            jobStatus: 'no_response',
            jobUpdatedAt: updated,
          ),
        ),
        '16/10 · expirou sem resposta',
      );
    });

    test('mês do histórico, com o ano só quando não é o atual', () {
      expect(workerHistoryMonthLabel(DateTime(2026, 10, 2), now), 'Outubro');
      expect(
        workerHistoryMonthLabel(DateTime(2025, 12, 2), now),
        'Dezembro de 2025',
      );
    });
  });

  testWidgets('tabs Agenda, Propostas com contagem e Histórico', (
    tester,
  ) async {
    WorkerJobsSection? selected;
    await tester.pumpWidget(
      _screen(
        pending: WorkerJobsTabViewData(
          sections: [
            WorkerJobsSectionViewData(
              items: [
                _item('1', status: 'Pendente'),
                _item('2', role: 'Ajudante', status: 'Pendente'),
              ],
            ),
          ],
        ),
        onSection: (s) => selected = s,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Trabalhos'), findsOneWidget);
    expect(find.text('Agenda'), findsOneWidget);
    expect(find.text('Propostas'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Serviço 1'), findsOneWidget);
    expect(find.text('Ajudante'), findsOneWidget);
    // "Cores" só na Agenda.
    expect(find.text('Cores'), findsNothing);

    await tester.tap(find.text('Agenda'));
    expect(selected, WorkerJobsSection.agenda);
  });

  testWidgets('a Agenda mostra o corpo que recebe e o botão Cores', (
    tester,
  ) async {
    await tester.pumpWidget(_screen(section: WorkerJobsSection.agenda));
    await tester.pumpAndSettle();
    expect(find.text('corpo da agenda'), findsOneWidget);
    expect(find.text('Cores'), findsOneWidget);
  });

  testWidgets('histórico agrupado por mês', (tester) async {
    await tester.pumpWidget(
      _screen(
        section: WorkerJobsSection.history,
        history: WorkerJobsTabViewData(
          sections: [
            WorkerJobsSectionViewData(
              label: 'Outubro',
              items: [
                _item('1', status: 'Concluído'),
                _item('2', muted: true, status: 'Cancelado'),
              ],
            ),
            WorkerJobsSectionViewData(
              label: 'Setembro',
              items: [_item('3', muted: true, status: 'Não selecionada')],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('OUTUBRO'), findsOneWidget);
    expect(find.text('SETEMBRO'), findsOneWidget);
    expect(find.text('Não selecionada'), findsOneWidget);
  });

  testWidgets('vazios por tab: só Propostas tem botão', (tester) async {
    var found = 0;
    await tester.pumpWidget(_screen(onFind: () => found++));
    await tester.pumpAndSettle();
    expect(find.text('Sem propostas à espera'), findsOneWidget);
    await tester.tap(find.text('Procurar trabalho'));
    expect(found, 1);

    await tester.pumpWidget(_screen(section: WorkerJobsSection.history));
    await tester.pumpAndSettle();
    expect(find.text('Histórico vazio'), findsOneWidget);
    expect(find.text('Procurar trabalho'), findsNothing);
  });

  testWidgets('R1: aviso abre "Ver o dia" sem abrir o cartão; Retirar', (
    tester,
  ) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: WorkerJobsScreen(
          selectedSection: WorkerJobsSection.proposals,
          agenda: const SizedBox(),
          pending: const WorkerJobsTabViewData(
            sections: [
              WorkerJobsSectionViewData(
                items: [
                  WorkerJobListItemViewData(
                    id: 'p1',
                    title: 'Corte de relva',
                    serviceIcon: Icons.grass,
                    metaLabel: 'Sex 30 out · 09:00 · Cascais',
                    status: AppStatusPresentation(
                      label: 'À espera do cliente',
                      color: AppStatusColor.waiting,
                    ),
                    warningLabel: 'Coincide com Poda, Sintra, 09:00 a 12:00',
                    withdrawLabel: 'Retirar proposta',
                  ),
                  WorkerJobListItemViewData(
                    id: 'h1',
                    title: 'Poda de árvores',
                    serviceIcon: Icons.group,
                    metaLabel: 'Qua 4 nov · 08:30 · com Rui Costa',
                    roleLabel: 'Ajudante',
                    status: AppStatusPresentation(
                      label: 'Candidatura enviada',
                      color: AppStatusColor.info,
                    ),
                  ),
                ],
              ),
            ],
          ),
          history: const WorkerJobsTabViewData(),
          onSectionSelected: (_) {},
          onNotificationsPressed: () {},
          onColorsPressed: () {},
          onJobPressed: (id) => calls.add('open $id'),
          onLoadMore: (_) {},
          onOpenDayPreview: (id) => calls.add('day $id'),
          onWithdraw: (id) => calls.add('withdraw $id'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Coincide com Poda, Sintra, 09:00 a 12:00'),
      findsOneWidget,
    );
    // Só a proposta tem "Retirar".
    expect(find.text('Retirar proposta'), findsOneWidget);

    await tester.tap(find.text('Coincide com Poda, Sintra, 09:00 a 12:00'));
    await tester.tap(find.text('Retirar proposta'));
    await tester.tap(find.text('Poda de árvores'));
    expect(calls, ['day p1', 'withdraw p1', 'open h1']);
  });
}
