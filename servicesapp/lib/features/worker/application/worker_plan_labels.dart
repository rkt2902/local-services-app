import 'package:intl/intl.dart';

import '../data/worker_plan_model.dart';

/// Texto curto na linha "Plano" da conta: "Grátis · 3 de 5 este mês",
/// "Pro · até 22/10/2027" ou só "Pro+" (sem data de fim).
String workerPlanSummaryLabel(WorkerPlan plan) {
  final limit = plan.monthlyJobLimit;
  if (!plan.tier.isPaid) {
    if (limit == null) return plan.tier.label;
    return '${plan.tier.label} · ${plan.jobsThisMonth} de $limit este mês';
  }
  final endsAt = plan.endsAt;
  if (endsAt == null) return plan.tier.label;
  return '${plan.tier.label} · até ${DateFormat('dd/MM/yyyy').format(endsAt)}';
}

/// Explicação na folha do plano. Sem preços nem forma de pagar: o plano é
/// contratado fora da app (regras de faturação das lojas).
String workerPlanExplanation(WorkerPlan plan) {
  final limit = plan.monthlyJobLimit;
  if (!plan.tier.isPaid) {
    if (limit == null) return 'Estás no plano Grátis.';
    final usage = plan.reachedLimit
        ? 'Já chegaste aos $limit trabalhos deste mês. Voltas a poder '
            'enviar propostas no início do próximo mês.'
        : 'Este mês já tens ${plan.jobsThisMonth} de $limit trabalhos aceites.';
    return 'No plano Grátis podes ter até $limit trabalhos aceites por mês. '
        '$usage';
  }
  final verified = plan.verified
      ? ' Os teus documentos foram confirmados pela ProJardim.'
      : '';
  return 'Estás no plano ${plan.tier.label}: trabalhos sem limite e selo '
      '${plan.tier.label} no perfil.$verified';
}
