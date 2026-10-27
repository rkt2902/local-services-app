import '../../../core/constants/enums.dart';
import '../../worker/application/worker_job_rules.dart';
import '../data/job_model.dart';
import 'direct_request_labels.dart';

// Próximo passo de um pedido, do ponto de vista do cliente. Partilhado pelo
// Início (client_home_screen.dart) e pela aba Pedidos (client_jobs_screen.dart)
// para os dois dizerem o mesmo.

/// Pedidos que aparecem no Início: tudo o que ainda está em curso, numa só
/// lista, com o que precisa do cliente primeiro.
List<JobRequest> clientHomeActiveJobs(List<JobRequest> jobs) {
  final active = jobs
      .where((j) =>
          j.status == JobStatus.open ||
          j.status == JobStatus.confirmed ||
          j.status == JobStatus.awaitingConfirmation)
      .toList();
  int rank(JobRequest j) {
    if (j.status == JobStatus.awaitingConfirmation) return 0;
    if (_rescheduleAwaitsClient(j)) return 1;
    if (j.status == JobStatus.open && j.proposalCount > 0) return 2;
    if (j.status == JobStatus.confirmed) return 3;
    return 4;
  }

  active.sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    return b.createdAt.compareTo(a.createdAt);
  });
  return active;
}

/// Nova data proposta pelo jardineiro, à espera da resposta do cliente.
bool _rescheduleAwaitsClient(JobRequest job) =>
    job.rescheduleStatus == RescheduleStatus.pending &&
    job.rescheduleProposedBy != null &&
    job.rescheduleProposedBy != job.clientId;

/// `true` quando o pedido está à espera de uma ação do cliente.
bool clientJobNeedsAction(JobRequest job) =>
    job.status == JobStatus.awaitingConfirmation ||
    _rescheduleAwaitsClient(job) ||
    (job.status == JobStatus.open && job.proposalCount > 0);

/// Uma linha a dizer o que acontece a seguir com o pedido. Com [now], o
/// pedido à espera de confirmação diz quanto tempo falta para ficar
/// confirmado sozinho (48h depois de o jardineiro o dar por concluído).
String clientJobNextStepLabel(JobRequest job, {DateTime? now}) {
  if (job.status == JobStatus.awaitingConfirmation) {
    const base = 'O jardineiro deu o trabalho por concluído.';
    final doneAt = job.markedDoneAt;
    if (now != null && doneAt != null) {
      final left = doneAt
          .add(const Duration(hours: WorkerJobDayRules.autoConfirmHours))
          .difference(now);
      if (left.inMinutes > 0) {
        final hours = (left.inMinutes / 60).ceil();
        return '$base Confirma em ${hours}h.';
      }
    }
    return '$base Confirma.';
  }
  if (_rescheduleAwaitsClient(job)) {
    return 'O jardineiro propôs uma nova data. Responde.';
  }
  if (job.rescheduleStatus == RescheduleStatus.pending) {
    return 'Propuseste uma nova data. À espera do jardineiro.';
  }
  if (job.status == JobStatus.open) {
    final n = job.proposalCount;
    final directUntil = job.directUntil;
    if (n <= 0 && job.isDirectWaiting && directUntil != null) {
      return 'Só o teu jardineiro vê o pedido até '
          '${directDeadlineLabel(directUntil)}.';
    }
    // Interruptor desligado (0059): o pedido parou e espera pelo cliente.
    if (n <= 0 && job.isDirectOnHold) {
      return 'O pedido está parado. Decide se o mostras a outros jardineiros.';
    }
    if (n <= 0) return 'À espera de propostas dos jardineiros.';
    return n == 1 ? 'Tens 1 proposta para ver.' : 'Tens $n propostas para ver.';
  }
  if (job.isInProgress) return 'O jardineiro já começou o trabalho.';
  return 'Trabalho marcado. Fala com o jardineiro por WhatsApp.';
}


/// O que o pedido espera do cliente, para "Precisa de ti" no Início (A11).
enum ClientJobAttention { confirmDone, answerReschedule, seeProposals }

/// `null` quando o pedido não espera nada do cliente (o mesmo critério de
/// [clientJobNeedsAction]).
ClientJobAttention? clientJobAttention(JobRequest job) {
  if (job.status == JobStatus.awaitingConfirmation) {
    return ClientJobAttention.confirmDone;
  }
  if (_rescheduleAwaitsClient(job)) return ClientJobAttention.answerReschedule;
  if (job.status == JobStatus.open && job.proposalCount > 0) {
    return ClientJobAttention.seeProposals;
  }
  return null;
}

/// Título curto da linha de "Precisa de ti" ("3 propostas para ver").
String clientJobAttentionTitle(ClientJobAttention kind, JobRequest job) =>
    switch (kind) {
      ClientJobAttention.confirmDone => 'Confirma o trabalho feito',
      ClientJobAttention.answerReschedule => 'Nova data proposta',
      ClientJobAttention.seeProposals => job.proposalCount == 1
          ? '1 proposta para ver'
          : '${job.proposalCount} propostas para ver',
    };
