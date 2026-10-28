import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../../../core/models/job_flow_stage.dart';
import '../../../core/utils/date_labels.dart';
import '../../help_requests/data/help_request_model.dart';
import '../data/job_model.dart';
import 'direct_request_labels.dart';

/// A equipa de um trabalho vista pela cliente (design A12, C4 a C7): quantos
/// ajudantes o responsável procura, quem já vem e se há um pedido de
/// ajudantes à espera da aprovação dela.
class ClientJobTeam {
  const ClientJobTeam({
    required this.helpersNeeded,
    required this.helperNames,
    this.pendingApprovalSlots = 0,
  });

  /// Vagas de ajudante deste trabalho (0 sem ajudantes).
  final int helpersNeeded;

  /// Nomes dos ajudantes aceites, pela ordem do servidor.
  final List<String> helperNames;

  /// Vagas de um pedido de ajudantes que ainda espera pela cliente
  /// (`pending_approval`); 0 quando não há.
  final int pendingApprovalSlots;

  int get joined => helperNames.length;

  /// Com ajudantes previstos ou já na equipa. Sem isto, o detalhe não fala
  /// de equipa (pedido do Henrique, 27/10).
  bool get hasHelpers => helpersNeeded > 0 || joined > 0;

  /// Todas as vagas preenchidas e nada por aprovar.
  bool get isComplete => joined >= helpersNeeded && pendingApprovalSlots == 0;

  /// "1/2" no separador Equipa; `null` sem ajudantes.
  String? get countLabel {
    if (!hasHelpers) return null;
    final total = helpersNeeded > joined ? helpersNeeded : joined;
    return '$joined/$total';
  }
}

/// Junta a proposta aceite, os pedidos de ajudantes e os ajudantes aceites.
///
/// - Sem pedido de ajudantes: as vagas são as que a proposta previa
///   (`people_needed` conta o responsável).
/// - Com pedidos abertos ou por aprovar: as vagas desses pedidos.
/// - Pedidos todos fechados ou cancelados: fica quem já está na equipa.
ClientJobTeam clientJobTeam({
  required int? proposalPeopleNeeded,
  required List<HelpRequest> helpRequests,
  required List<String> helperNames,
}) {
  final active = helpRequests
      .where(
        (hr) =>
            hr.status == HelpRequestStatus.open ||
            hr.status == HelpRequestStatus.pendingApproval,
      )
      .toList();
  final pending = active
      .where((hr) => hr.status == HelpRequestStatus.pendingApproval)
      .fold<int>(0, (sum, hr) => sum + hr.slotsNeeded);

  int needed;
  if (helpRequests.isEmpty) {
    final planned = (proposalPeopleNeeded ?? 1) - 1;
    needed = planned < 0 ? 0 : planned;
  } else if (active.isEmpty) {
    needed = helperNames.length;
  } else {
    needed = active.fold<int>(0, (sum, hr) => sum + hr.slotsNeeded);
  }
  if (needed < helperNames.length) needed = helperNames.length;

  return ClientJobTeam(
    helpersNeeded: needed,
    helperNames: helperNames,
    pendingApprovalSlots: pending,
  );
}

/// Fase do stepper para a cliente. Vem do estado do pedido e da equipa,
/// nunca da data: um trabalho marcado sem ajudantes por juntar já está
/// "No dia" (à espera do dia), um com a equipa por fechar está em "Equipa".
JobFlowStage clientJobFlowStage(JobRequest job, ClientJobTeam team) {
  switch (job.status) {
    case JobStatus.open:
    case JobStatus.noResponse:
    case JobStatus.cancelled:
      return job.proposalCount > 0
          ? JobFlowStage.proposal
          : JobFlowStage.request;
    case JobStatus.confirmed:
      if (job.startedAt != null || team.isComplete) {
        return JobFlowStage.onTheDay;
      }
      return JobFlowStage.team;
    case JobStatus.awaitingConfirmation:
    case JobStatus.completed:
      return JobFlowStage.completed;
  }
}

enum ClientJobFlowBannerKind { started, approveTeam, formingTeam, teamReady }

/// Aviso do topo do detalhe e do separador Equipa.
class ClientJobFlowBanner {
  const ClientJobFlowBanner({
    required this.kind,
    required this.title,
    this.body,
  });

  final ClientJobFlowBannerKind kind;
  final String title;
  final String? body;
}

/// O aviso muda com e sem ajudantes: sem ajudantes só aparece com o
/// trabalho em curso, e sem falar de equipa. Os nomes vão sem artigo
/// ("Pedro e Tiago"): não sabemos o género de ninguém.
ClientJobFlowBanner? clientJobFlowBanner({
  required JobRequest job,
  required ClientJobTeam team,
  required String workerName,
}) {
  if (job.status != JobStatus.confirmed) return null;
  final who = firstNameOr(workerName, 'O jardineiro');

  final startedAt = job.startedAt;
  if (startedAt != null) {
    final time = DateFormat('HH:mm').format(startedAt.toLocal());
    return ClientJobFlowBanner(
      kind: ClientJobFlowBannerKind.started,
      title: '$who começou às $time.',
      body: team.joined > 0
          ? 'Está com ${_namesLabel(team.helperNames)}.'
          : null,
    );
  }

  if (team.pendingApprovalSlots > 0) {
    final n = team.pendingApprovalSlots;
    return ClientJobFlowBanner(
      kind: ClientJobFlowBannerKind.approveTeam,
      title: '$who quer levar $n ${n == 1 ? 'ajudante' : 'ajudantes'}.',
      body:
          'O preço não muda. Sem resposta, fica aprovado 24 horas '
          'depois do pedido.',
    );
  }

  if (!team.hasHelpers) return null;

  if (!team.isComplete) {
    final missing = team.helpersNeeded;
    return ClientJobFlowBanner(
      kind: ClientJobFlowBannerKind.formingTeam,
      title: '$who está a juntar a equipa.',
      body: team.joined == 0
          ? 'Procura $missing ${missing == 1 ? 'ajudante' : 'ajudantes'}. '
                'O preço não muda.'
          : 'Já tem ${team.joined} de $missing ajudantes. O preço não muda.',
    );
  }

  return ClientJobFlowBanner(
    kind: ClientJobFlowBannerKind.teamReady,
    title: 'Equipa completa.',
    body: '$who vem com ${_namesLabel(team.helperNames)}.',
  );
}

/// "Pedro", "Pedro e Tiago", "Pedro, Tiago e Rui" (primeiros nomes).
String _namesLabel(List<String> names) {
  final first = [for (final n in names) firstNameOr(n, 'um ajudante')];
  if (first.length <= 1) return first.join();
  return '${first.sublist(0, first.length - 1).join(', ')} e ${first.last}';
}

/// "João Silva · Sáb, 31/10 · 08:30" por baixo do título do detalhe.
String clientJobFlowSubtitle({
  required JobRequest job,
  required String workerName,
  DateTime? now,
}) {
  final parts = <String>[];
  if (workerName.trim().isNotEmpty) parts.add(workerName.trim());
  final date = job.confirmedDate;
  if (date != null) {
    parts.add(shortWeekdayDateLabel(date, now: now));
    final time = job.confirmedTime;
    if (!job.confirmedFlexible && time != null && time.length >= 5) {
      parts.add(time.substring(0, 5));
    }
  }
  return parts.join(' · ');
}

/// "Ajudantes · 1 de 2" (ou "Ajudantes · 2" com a equipa completa).
String clientTeamHelpersHeading(ClientJobTeam team) {
  if (team.joined >= team.helpersNeeded) return 'Ajudantes · ${team.joined}';
  return 'Ajudantes · ${team.joined} de ${team.helpersNeeded}';
}

/// "À procura de 2 ajudantes" nas vagas por preencher.
String clientTeamSearchingLabel(ClientJobTeam team) {
  final missing = team.helpersNeeded - team.joined;
  return 'À procura de $missing ${missing == 1 ? 'ajudante' : 'ajudantes'}';
}

/// "João + 2 ajudantes" na linha Equipa do resumo.
String clientTeamSummaryLabel(ClientJobTeam team, String workerName) {
  final who = firstNameOr(workerName, 'Responsável');
  final n = team.helpersNeeded > team.joined ? team.helpersNeeded : team.joined;
  return '$who + $n ${n == 1 ? 'ajudante' : 'ajudantes'}';
}
