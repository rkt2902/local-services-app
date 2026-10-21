import '../../../core/constants/enums.dart';
import '../../help_requests/application/helper_job_state.dart';
import '../../help_requests/data/help_request_model.dart';

/// Cartão "O que falta fazer" do dashboard do jardineiro: agrega, a partir
/// de dados que o dashboard já carrega, o que espera por uma ação dele.
/// Lógica pura (sem Riverpod nem Supabase) para poder ser testada.

/// Trabalho agendado em que o jardineiro é o responsável
/// (`scheduledWorkerProposalsProvider`).
class WorkerTodoScheduledJob {
  const WorkerTodoScheduledJob({
    required this.proposalId,
    required this.jobId,
    required this.status,
    this.confirmedDate,
    this.rescheduleStatus,
    this.rescheduleProposedBy,
  });

  final String proposalId;
  final String jobId;
  final JobStatus status;
  final DateTime? confirmedDate;
  final RescheduleStatus? rescheduleStatus;
  final String? rescheduleProposedBy;
}

/// Trabalho concluído em que o jardineiro foi o responsável
/// (`completedWorkerProposalsProvider(0)`).
class WorkerTodoCompletedJob {
  const WorkerTodoCompletedJob({
    required this.proposalId,
    required this.jobId,
    required this.clientId,
    this.confirmedDate,
  });

  final String proposalId;
  final String jobId;
  final String clientId;
  final DateTime? confirmedDate;
}

enum WorkerTodoKind {
  rescheduleToAnswer,
  workToday,
  toMarkDone,
  ratingsToGive,
  candidatesToDecide,
  pendingApplications,
}

/// Para onde leva uma linha. [push] = ecrã de sub-fluxo por cima do atual;
/// senão `go` para uma rota do shell (ex.: "Os meus trabalhos").
class WorkerTodoTarget {
  const WorkerTodoTarget._(this.location, {required this.push, this.extra});

  const WorkerTodoTarget.push(String location, {Map<String, Object>? extra})
      : this._(location, push: true, extra: extra);

  const WorkerTodoTarget.go(String location, {Map<String, Object>? extra})
      : this._(location, push: false, extra: extra);

  final String location;
  final bool push;
  final Map<String, Object>? extra;
}

class WorkerTodoItem {
  const WorkerTodoItem({
    required this.kind,
    required this.count,
    required this.label,
    required this.target,
  });

  final WorkerTodoKind kind;
  final int count;
  final String label;
  final WorkerTodoTarget target;
}

/// Avaliações pedidas só para trabalhos dos últimos [ratingWindowDays]
/// dias, para não lembrar para sempre um trabalho antigo.
const ratingWindowDays = 30;

/// Máximo de trabalhos agendados cujos candidatos o dashboard consulta
/// (um pedido por trabalho e por pedido de ajuda, por isso limitado).
const todoCandidatesJobCap = 5;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

String _plural(int n, String one, String many) => n == 1 ? '1 $one' : '$n $many';

WorkerTodoTarget _myJob(String proposalId, String jobId) =>
    WorkerTodoTarget.push('/worker/my-job/$proposalId?jobId=$jobId');

WorkerTodoTarget _jobsTab(String tab) =>
    WorkerTodoTarget.go('/worker/jobs', extra: {'initialTab': tab});

WorkerTodoTarget _helperJob(String acceptanceId) =>
    WorkerTodoTarget.push('/worker/help/$acceptanceId');

/// Linhas do cartão, pela ordem em que aparecem. Vazia = cartão escondido.
///
/// [completedJobs] e [ratingsGiven] a `null` (ainda a carregar ou com
/// erro) escondem a linha das avaliações em vez de inventar um número.
/// [pendingCandidatesByJob]: candidatos por decidir por `job_id`.
List<WorkerTodoItem> buildWorkerTodo({
  required String myUserId,
  required DateTime today,
  required List<WorkerTodoScheduledJob> scheduledJobs,
  required List<HelpAcceptanceSummary> helpAcceptances,
  List<WorkerTodoCompletedJob>? completedJobs,
  Set<(String, String)>? ratingsGiven,
  Map<String, int> pendingCandidatesByJob = const {},
}) {
  final day = _day(today);
  final items = <WorkerTodoItem>[];

  // Remarcações propostas pelo cliente, à espera da resposta do jardineiro.
  final reschedules = scheduledJobs
      .where((j) =>
          j.status == JobStatus.confirmed &&
          j.rescheduleStatus == RescheduleStatus.pending &&
          j.rescheduleProposedBy != null &&
          j.rescheduleProposedBy != myUserId)
      .toList();
  if (reschedules.isNotEmpty) {
    items.add(WorkerTodoItem(
      kind: WorkerTodoKind.rescheduleToAnswer,
      count: reschedules.length,
      label: _plural(reschedules.length, 'remarcação por responder',
          'remarcações por responder'),
      target: reschedules.length == 1
          ? _myJob(reschedules.first.proposalId, reschedules.first.jobId)
          : _jobsTab('scheduled'),
    ));
  }

  // Trabalho hoje: como responsável ou como ajudante aceite.
  final todayAsPrincipal = scheduledJobs
      .where((j) =>
          j.status == JobStatus.confirmed &&
          j.confirmedDate != null &&
          _day(j.confirmedDate!) == day)
      .toList();
  final todayAsHelper = helpAcceptances
      .where((a) =>
          helperJobStage(a.status, a.jobStatus) == HelperJobStage.accepted &&
          a.confirmedDate != null &&
          _day(a.confirmedDate!) == day)
      .toList();
  final todayCount = todayAsPrincipal.length + todayAsHelper.length;
  if (todayCount > 0) {
    final WorkerTodoTarget target;
    if (todayCount > 1) {
      target = _jobsTab('scheduled');
    } else if (todayAsPrincipal.isNotEmpty) {
      target = _myJob(todayAsPrincipal.first.proposalId, todayAsPrincipal.first.jobId);
    } else {
      target = _helperJob(todayAsHelper.first.id);
    }
    items.add(WorkerTodoItem(
      kind: WorkerTodoKind.workToday,
      count: todayCount,
      label: _plural(todayCount, 'trabalho hoje', 'trabalhos hoje'),
      target: target,
    ));
  }

  // Por marcar como concluído: a data já passou e o trabalho continua
  // confirmado (o de hoje já aparece em "Trabalho hoje").
  final overdue = scheduledJobs
      .where((j) =>
          j.status == JobStatus.confirmed &&
          j.confirmedDate != null &&
          _day(j.confirmedDate!).isBefore(day))
      .toList();
  if (overdue.isNotEmpty) {
    items.add(WorkerTodoItem(
      kind: WorkerTodoKind.toMarkDone,
      count: overdue.length,
      label: _plural(overdue.length, 'trabalho por marcar como concluído',
          'trabalhos por marcar como concluídos'),
      target: overdue.length == 1
          ? _myJob(overdue.first.proposalId, overdue.first.jobId)
          : _jobsTab('scheduled'),
    ));
  }

  // Avaliações por fazer: o cliente (como responsável) e o responsável
  // (como ajudante). As dos ajudantes da minha equipa ficam de fora (exigia
  // um pedido por trabalho).
  if (completedJobs != null && ratingsGiven != null) {
    final windowStart = day.subtract(const Duration(days: ratingWindowDays));
    bool recent(DateTime? date) =>
        date == null || !_day(date).isBefore(windowStart);

    final clientsToRate = completedJobs
        .where((j) =>
            j.clientId.isNotEmpty &&
            recent(j.confirmedDate) &&
            !ratingsGiven.contains((j.jobId, j.clientId)))
        .toList();
    final principalsToRate = helpAcceptances
        .where((a) =>
            helperJobStage(a.status, a.jobStatus) == HelperJobStage.completed &&
            a.jobId.isNotEmpty &&
            a.principalWorkerId.isNotEmpty &&
            recent(a.confirmedDate) &&
            !ratingsGiven.contains((a.jobId, a.principalWorkerId)))
        .toList();
    final count = clientsToRate.length + principalsToRate.length;
    if (count > 0) {
      final WorkerTodoTarget target;
      if (count > 1) {
        target = _jobsTab('completed');
      } else if (clientsToRate.isNotEmpty) {
        target = _myJob(clientsToRate.first.proposalId, clientsToRate.first.jobId);
      } else {
        target = _helperJob(principalsToRate.first.id);
      }
      items.add(WorkerTodoItem(
        kind: WorkerTodoKind.ratingsToGive,
        count: count,
        label: _plural(count, 'avaliação por fazer', 'avaliações por fazer'),
        target: target,
      ));
    }
  }

  // Candidatos à espera de decisão nas minhas equipas.
  final jobsWithCandidates = pendingCandidatesByJob.entries
      .where((e) => e.value > 0)
      .toList();
  final candidates =
      jobsWithCandidates.fold<int>(0, (sum, e) => sum + e.value);
  if (candidates > 0) {
    items.add(WorkerTodoItem(
      kind: WorkerTodoKind.candidatesToDecide,
      count: candidates,
      label: _plural(candidates, 'candidato por decidir', 'candidatos por decidir'),
      target: jobsWithCandidates.length == 1
          ? WorkerTodoTarget.push(
              '/worker/job/${jobsWithCandidates.first.key}/help-requests')
          : _jobsTab('scheduled'),
    ));
  }

  // As minhas candidaturas a pedidos de ajuda, à espera de resposta.
  final pending = helpAcceptances
      .where((a) => helperJobStage(a.status, a.jobStatus) == HelperJobStage.pending)
      .toList();
  if (pending.isNotEmpty) {
    items.add(WorkerTodoItem(
      kind: WorkerTodoKind.pendingApplications,
      count: pending.length,
      label: _plural(pending.length, 'candidatura à espera de resposta',
          'candidaturas à espera de resposta'),
      target: pending.length == 1
          ? _helperJob(pending.first.id)
          : const WorkerTodoTarget.push(
              '/worker/help-requests',
              extra: {'initialTabIndex': 1},
            ),
    ));
  }

  return items;
}
