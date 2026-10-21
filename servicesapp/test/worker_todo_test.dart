import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/features/help_requests/data/help_request_model.dart';
import 'package:servicesapp/features/worker/application/worker_todo.dart';

final _today = DateTime(2026, 10, 18, 9);

WorkerTodoScheduledJob _job(
  String id, {
  JobStatus status = JobStatus.confirmed,
  DateTime? date,
  RescheduleStatus? reschedule,
  String? proposedBy,
  String? time,
  DateTime? startedAt,
}) =>
    WorkerTodoScheduledJob(
      proposalId: 'p$id',
      jobId: 'j$id',
      status: status,
      confirmedDate: date,
      confirmedTime: time,
      startedAt: startedAt,
      rescheduleStatus: reschedule,
      rescheduleProposedBy: proposedBy,
    );

HelpAcceptanceSummary _help(
  String id, {
  HelpAcceptanceStatus status = HelpAcceptanceStatus.accepted,
  String jobStatus = 'confirmed',
  DateTime? date,
}) =>
    HelpAcceptanceSummary(
      id: id,
      helpRequestId: 'h$id',
      status: status,
      agreedRate: 10,
      broughtEquipment: false,
      createdAt: DateTime(2026, 10, 1),
      serviceTypeName: 'Poda',
      principalName: 'Rui',
      jobStatus: jobStatus,
      jobId: 'hj$id',
      principalWorkerId: 'principal',
      confirmedDate: date,
    );

List<WorkerTodoItem> _build({
  List<WorkerTodoScheduledJob> scheduled = const [],
  List<HelpAcceptanceSummary> help = const [],
  List<WorkerTodoCompletedJob>? completed,
  Set<(String, String)>? given,
  Map<String, int> candidates = const {},
}) =>
    buildWorkerTodo(
      myUserId: 'me',
      today: _today,
      scheduledJobs: scheduled,
      helpAcceptances: help,
      completedJobs: completed,
      ratingsGiven: given,
      pendingCandidatesByJob: candidates,
    );

WorkerTodoItem? _find(List<WorkerTodoItem> items, WorkerTodoKind kind) =>
    items.where((i) => i.kind == kind).firstOrNull;

void main() {
  test('sem nada para fazer o cartão fica vazio', () {
    expect(_build(scheduled: [_job('1', date: DateTime(2026, 10, 25))]), isEmpty);
  });

  test('remarcação só conta quando foi o cliente a propor', () {
    final items = _build(scheduled: [
      _job('1', reschedule: RescheduleStatus.pending, proposedBy: 'client'),
      _job('2', reschedule: RescheduleStatus.pending, proposedBy: 'me'),
      _job('3', reschedule: RescheduleStatus.rejected, proposedBy: 'client'),
    ]);
    final item = _find(items, WorkerTodoKind.rescheduleToAnswer)!;
    expect(item.count, 1);
    expect(item.label, '1 remarcação por responder');
    expect(item.target.location, '/worker/my-job/p1?jobId=j1');
    expect(item.target.push, isTrue);
  });

  test('trabalho hoje junta responsável e ajudante, e vai para a lista', () {
    final items = _build(
      scheduled: [_job('1', date: DateTime(2026, 10, 18))],
      help: [_help('a', date: DateTime(2026, 10, 18))],
    );
    final item = _find(items, WorkerTodoKind.workToday)!;
    expect(item.count, 2);
    expect(item.label, '2 trabalhos hoje');
    expect(item.target.location, '/worker/jobs');
    expect(item.target.push, isFalse);
    expect(item.target.extra, {'initialTab': 'scheduled'});
  });

  test('um só trabalho hoje com hora diz a hora e quando pode iniciar', () {
    final items = _build(
      scheduled: [_job('1', date: DateTime(2026, 10, 18), time: '09:00:00')],
    );
    final item = _find(items, WorkerTodoKind.workToday)!;
    expect(item.label, 'Trabalho hoje às 9:00');
    expect(item.subtitle, 'Iniciar disponível a partir das 8:00');
  });

  test('trabalho de hoje já iniciado diz "Em curso"', () {
    final items = _build(scheduled: [
      _job(
        '1',
        date: DateTime(2026, 10, 18),
        time: '14:30',
        startedAt: DateTime(2026, 10, 18, 14, 35),
      ),
    ]);
    final item = _find(items, WorkerTodoKind.workToday)!;
    expect(item.label, 'Trabalho hoje às 14:30');
    expect(item.subtitle, 'Em curso');
  });

  test('um só trabalho hoje como ajudante abre o ecrã do ajudante', () {
    final items = _build(help: [_help('a', date: DateTime(2026, 10, 18))]);
    expect(_find(items, WorkerTodoKind.workToday)!.target.location, '/worker/help/a');
  });

  test('por marcar como concluído: data passada e ainda confirmado', () {
    final items = _build(scheduled: [
      _job('1', date: DateTime(2026, 10, 16)),
      _job('2', date: DateTime(2026, 10, 15), status: JobStatus.awaitingConfirmation),
      _job('3', date: DateTime(2026, 10, 18)),
    ]);
    final item = _find(items, WorkerTodoKind.toMarkDone)!;
    expect(item.count, 1);
    expect(item.label, '1 trabalho por concluir');
  });

  test('avaliações: escondidas enquanto os dados não chegam', () {
    final items = _build(
      help: [_help('a', jobStatus: 'completed', date: DateTime(2026, 10, 10))],
    );
    expect(_find(items, WorkerTodoKind.ratingsToGive), isNull);
  });

  test('avaliações por fazer: cliente e responsável, sem as já feitas nem antigas', () {
    final items = _build(
      completed: [
        WorkerTodoCompletedJob(
          proposalId: 'p1',
          jobId: 'j1',
          clientId: 'c1',
          confirmedDate: DateTime(2026, 10, 12),
        ),
        WorkerTodoCompletedJob(
          proposalId: 'p2',
          jobId: 'j2',
          clientId: 'c2',
          confirmedDate: DateTime(2026, 10, 12),
        ),
        WorkerTodoCompletedJob(
          proposalId: 'p3',
          jobId: 'j3',
          clientId: 'c3',
          confirmedDate: DateTime(2026, 8, 1),
        ),
      ],
      given: {('j2', 'c2')},
      help: [_help('a', jobStatus: 'completed', date: DateTime(2026, 10, 10))],
    );
    final item = _find(items, WorkerTodoKind.ratingsToGive)!;
    expect(item.count, 2);
    expect(item.label, '2 avaliações por fazer');
    expect(item.target.extra, {'initialTab': 'completed'});
  });

  test('candidatos por decidir num só trabalho abrem a equipa', () {
    final items = _build(candidates: {'j1': 2, 'j2': 0});
    final item = _find(items, WorkerTodoKind.candidatesToDecide)!;
    expect(item.count, 2);
    expect(item.label, '2 candidatos por decidir');
    expect(item.target.location, '/worker/job/j1/help-requests');
  });

  test('candidaturas pendentes, sem as de pedidos cancelados', () {
    final items = _build(help: [
      _help('a', status: HelpAcceptanceStatus.pending),
      _help('b', status: HelpAcceptanceStatus.pending),
      _help('c', status: HelpAcceptanceStatus.pending, jobStatus: 'cancelled'),
    ]);
    final item = _find(items, WorkerTodoKind.pendingApplications)!;
    expect(item.count, 2);
    expect(item.target.location, '/worker/help-requests');
    expect(item.target.extra, {'initialTabIndex': 1});
  });
}
