import '../../../core/utils/price_labels.dart';
import '../../proposals/data/proposal_model.dart';
import '../../ratings/data/rating_model.dart';
import '../../worker/application/worker_job_rules.dart';

/// Textos e ordem dos cartões de "Propostas recebidas" (designs A3 e
/// A6). Funções puras para o ecrã não calcular nada e para se poderem
/// testar sem rede. Os preços vêm de `proposal_price_labels.dart`.

/// Ordem da lista (A6): a recomendada primeiro, depois as de melhor média
/// e, por fim, por ordem de chegada. Nunca pelo preço: 25 €/h e 450 € não
/// medem a mesma coisa. As expiradas vão para o fim.
List<JobProposal> orderProposals(
  List<JobProposal> proposals,
  RatingSummary? Function(String workerId) summaryOf,
) {
  final recommendedId = recommendedProposalId(proposals, summaryOf);
  double rating(JobProposal p) {
    final s = summaryOf(p.workerId);
    return s == null || s.ratingCount == 0 ? 0 : s.avgRating;
  }

  final indexed = [for (var i = 0; i < proposals.length; i++) (i, proposals[i])];
  indexed.sort((a, b) {
    if (a.$2.isExpired != b.$2.isExpired) return a.$2.isExpired ? 1 : -1;
    if (a.$2.id == recommendedId) return -1;
    if (b.$2.id == recommendedId) return 1;
    final byRating = rating(b.$2).compareTo(rating(a.$2));
    if (byRating != 0) return byRating;
    return a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
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
/// a chegar). Propostas expiradas não contam.
String? recommendedProposalId(
  List<JobProposal> sorted,
  RatingSummary? Function(String workerId) summaryOf,
) {
  String? best;
  double bestRating = 0;
  for (final p in sorted) {
    if (p.isExpired) continue;
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
