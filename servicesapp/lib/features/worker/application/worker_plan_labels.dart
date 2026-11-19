import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
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
    if (limit == null) return 'Está no plano Grátis.';
    final usage = plan.reachedLimit
        ? 'Já chegou aos $limit trabalhos deste mês. Volta a poder '
            'enviar propostas no início do próximo mês.'
        : 'Este mês já tem ${plan.jobsThisMonth} de $limit trabalhos aceites.';
    // O limite trava propostas novas; as já enviadas ainda podem ser
    // aceites (decidido 2026-11-02).
    return 'No plano Grátis pode enviar propostas até ter $limit '
        'trabalhos aceites no mês. '
        '$usage';
  }
  final verified = plan.verified
      ? ' Os seus documentos foram confirmados pela ProJardim.'
      : '';
  final benefits = plan.tier == WorkerPlanTier.proPlus
      ? ' e acesso aos Benefícios (cartão frota e parceiros)'
      : '';
  return 'Está no plano ${plan.tier.label}: trabalhos sem limite, selo '
      '${plan.tier.label} no perfil e nas propostas, cartão em PDF e painel '
      'de ganhos$benefits.$verified';
}
