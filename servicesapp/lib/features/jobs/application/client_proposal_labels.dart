import '../../../core/utils/price_labels.dart';
import '../../proposals/data/proposal_model.dart';
import '../../ratings/data/rating_model.dart';
import '../../worker/application/worker_job_rules.dart';

/// Textos e ordem dos cartões de "Propostas recebidas" (design A3). Funções
/// puras para o ecrã não calcular nada e para se poderem testar sem rede.

/// Total estimado da proposta, com a equipa incluída ([teamHourlyRate],
/// o mesmo cálculo de todos os ecrãs). Os dois lados ficam `null` quando
/// não há preço ou horas.
({double? min, double? max}) proposalEstimate(JobProposal p) {
  if (p.hourlyRate <= 0) return (min: null, max: null);
  final perHour = teamHourlyRate(
    p.hourlyRate,
    peopleNeeded: p.peopleNeeded,
    helpersEquipmentRequired: p.helpersEquipmentRequired,
  );
  final min = p.estimatedHoursMin;
  final max = p.estimatedHoursMax;
  return (
    min: min == null ? null : perHour * min,
    max: max == null ? null : perHour * max,
  );
}

/// "Ordenadas por preço estimado, da mais barata para a mais cara": total
/// mínimo estimado (equipa incluída) a subir. Sem horas ficam no fim,
/// ordenadas pelo preço por hora.
int compareProposalsByEstimate(JobProposal a, JobProposal b) {
  final ea = proposalEstimate(a);
  final eb = proposalEstimate(b);
  final ta = ea.min ?? ea.max;
  final tb = eb.min ?? eb.max;
  if (ta == null && tb == null) return a.hourlyRate.compareTo(b.hourlyRate);
  if (ta == null) return 1;
  if (tb == null) return -1;
  return ta.compareTo(tb);
}

String _euros(double value) => '${value.round()} €';

/// Valor grande do cartão: total estimado ("48 €" ou "48 a 96 €"); sem
/// horas, o preço por hora.
String proposalPriceLabel(JobProposal p) {
  final e = proposalEstimate(p);
  final min = e.min;
  final max = e.max;
  if (min != null && max != null && max.round() > min.round()) {
    return '${min.round()} a ${_euros(max)}';
  }
  final one = min ?? max;
  if (one != null) return _euros(one);
  return hourlyRateLabel(p.hourlyRate);
}

String _hours(double h) =>
    h == h.roundToDouble() ? h.toStringAsFixed(0) : decimalLabel(h, 1);

/// Horas estimadas compactas. Ex.: "2 a 4h", "1,5h". Vazio sem horas.
String proposalHoursLabel(JobProposal p) {
  final min = p.estimatedHoursMin;
  final max = p.estimatedHoursMax;
  if (min != null && max != null && max > min) {
    return '${_hours(min)} a ${_hours(max)}h';
  }
  final one = min ?? max;
  return one == null ? '' : '${_hours(one)}h';
}

/// Linha por baixo do valor: horas e, quando o valor grande é um total, o
/// preço por hora que o jardineiro propôs (é esse o compromisso).
String proposalPriceDetailLabel(JobProposal p) {
  final hours = proposalHoursLabel(p);
  if (hours.isEmpty || p.hourlyRate <= 0) return hours;
  return '$hours · ${hourlyRateLabel(p.hourlyRate)}';
}

/// Data e hora propostas. Ex.: "Qui, 23/10 · 9:00".
String proposalScheduleLabel(JobProposal p, {DateTime? now}) {
  if (p.scheduledDate == null) return 'Data a combinar com o jardineiro';
  return workerScheduleLabel(
    date: p.scheduledDate,
    time: p.scheduledTime,
    flexible: p.scheduledFlexible,
    now: now,
  );
}

/// Ex.: "4,9 · 38 avaliações". `null` sem avaliações (o cartão mostra
/// "Ainda sem avaliações" sem estrela).
String? proposalRatingLabel(RatingSummary? summary) {
  if (summary == null || summary.ratingCount == 0) return null;
  final count = summary.ratingCount;
  return '${decimalLabel(summary.avgRating, 1)} · '
      '$count ${count == 1 ? 'avaliação' : 'avaliações'}';
}

/// "Equipa de 2" quando a proposta inclui ajudantes.
String? proposalTeamLabel(JobProposal p) =>
    p.peopleNeeded > 1 ? 'Equipa de ${p.peopleNeeded}' : null;

/// "Recomendada" é só um destaque da app, não um estado: a melhor média
/// entre jardineiros com pelo menos 3 avaliações (empate fica a primeira
/// da lista, que é a mais barata).
String? recommendedProposalId(
  List<JobProposal> sorted,
  RatingSummary? Function(String workerId) summaryOf,
) {
  String? best;
  double bestRating = 0;
  for (final p in sorted) {
    final s = summaryOf(p.workerId);
    if (s != null && s.ratingCount >= 3 && s.avgRating > bestRating) {
      bestRating = s.avgRating;
      best = p.id;
    }
  }
  return best;
}

/// Ex.: "Corte de relva · 3 propostas".
String proposalsHeaderSubtitle(String? serviceLabel, int count) {
  final total = count == 0
      ? 'Ainda sem propostas'
      : '$count ${count == 1 ? 'proposta' : 'propostas'}';
  if (serviceLabel == null || serviceLabel.isEmpty) return total;
  return '$serviceLabel · $total';
}
