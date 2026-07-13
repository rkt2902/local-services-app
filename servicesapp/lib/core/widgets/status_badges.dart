import 'package:flutter/material.dart';

import '../constants/enums.dart';
import '../theme/app_status_color.dart';
import 'app_status_badge.dart';

/// Mapeamento único de JobStatus/ProposalStatus → (label, cor).
///
/// Substitui as implementações duplicadas e inconsistentes que existiam em
/// client_home_screen, client_jobs_screen, client_job_detail_screen,
/// worker_jobs_screen, worker_my_job_detail_screen e
/// worker_help_requests_screen (ver docs/improvements.md, item P1/A1).
///
/// `color == null` significa estado neutro (renderiza via
/// [AppStatusBadge.neutral]).

Widget jobStatusBadge(JobStatus status, {int proposalCount = 0}) {
  final (label, color) = jobStatusInfo(status, proposalCount);
  return color == null
      ? AppStatusBadge.neutral(label: label)
      : AppStatusBadge(label: label, statusColor: color);
}

Widget proposalStatusBadge(ProposalStatus status) {
  final (label, color) = proposalStatusInfo(status);
  return color == null
      ? AppStatusBadge.neutral(label: label)
      : AppStatusBadge(label: label, statusColor: color);
}

/// Tupla (label, cor) crua — para ecrãs que precisam de inspecionar o valor
/// antes de renderizar (ex.: worker_dashboard_screen.dart). A maioria dos
/// callers deve preferir [jobStatusBadge], que já devolve o widget pronto.
(String, AppStatusColor?) jobStatusInfo(JobStatus status, int proposalCount) =>
    switch (status) {
      JobStatus.open when proposalCount > 0 => (
          '$proposalCount proposta${proposalCount > 1 ? 's' : ''}',
          AppStatusColor.waiting,
        ),
      JobStatus.open => ('À espera de proposta', AppStatusColor.waiting),
      JobStatus.confirmed => ('Confirmado', AppStatusColor.success),
      JobStatus.awaitingConfirmation => (
          'A aguardar confirmação',
          AppStatusColor.waiting,
        ),
      JobStatus.completed => ('Concluído', AppStatusColor.success),
      // Expirou sem ninguém ter cancelado nada — estado neutro, não
      // "cancelled" (decisão explícita, 2026-07-13).
      JobStatus.noResponse => ('Sem resposta', null),
      JobStatus.cancelled => ('Cancelado', AppStatusColor.cancelled),
    };

(String, AppStatusColor?) proposalStatusInfo(ProposalStatus status) =>
    switch (status) {
      ProposalStatus.pending => ('Aguarda resposta', AppStatusColor.waiting),
      ProposalStatus.accepted => ('Aceite', AppStatusColor.success),
      // Nem "não selecionada" nem "substituída" são um cancelamento do job —
      // ambos neutros (decisão explícita, 2026-07-13).
      ProposalStatus.rejected => ('Não selecionada', null),
      ProposalStatus.superseded => ('Substituída', null),
    };
