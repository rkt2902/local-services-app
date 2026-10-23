import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/price_labels.dart';
import '../data/proposal_model.dart';

/// Textos do preço, da duração, do "inclui" e da validade de uma proposta
/// (design A6). Funções puras: os ecrãs recebem tudo pronto e os dois
/// formatos (por hora e valor total) nunca se comparam pelo número.

/// Euros sem casas decimais quando é um número redondo. Ex.: "450 €",
/// "12,50 €".
String compactMoneyLabel(double value) => value == value.roundToDouble()
    ? '${value.round()} €'
    : moneyLabel(value);

/// Valor grande do cartão. Ex.: "450 €" (valor fechado) ou "25 €/h".
String proposalValueLabel(JobProposal p) {
  if (p.isFixedTotal) return compactMoneyLabel(p.totalPrice!);
  if (p.hourlyRate <= 0) return 'Preço a definir';
  return '${compactMoneyLabel(p.hourlyRate).replaceAll(' €', '')} €/h';
}

/// Ao lado do valor grande: "valor fechado" ou "preço por hora".
String proposalPriceKindLabel(JobProposal p) =>
    p.isFixedTotal ? 'valor fechado' : 'preço por hora';

/// Linha "Total": o valor fechado, ou o total estimado pelas horas com a
/// equipa incluída ("cerca de 100 a 150 €"). `null` por hora sem horas.
String? proposalTotalLabel(JobProposal p) {
  if (p.isFixedTotal) return compactMoneyLabel(p.totalPrice!);
  final estimate = estimatedTotalLabel(
    p.hourlyRate,
    p.estimatedHoursMin,
    p.estimatedHoursMax,
    peopleNeeded: p.peopleNeeded,
    helpersEquipmentRequired: p.helpersEquipmentRequired,
  );
  if (estimate.isEmpty) return null;
  return estimate.replaceFirst('≈ ', 'cerca de ');
}

/// Por baixo do total, o tipo escrito por extenso.
String proposalTotalNoteLabel(JobProposal p) => p.isFixedTotal
    ? 'Fechado. Não muda com as horas.'
    : 'Estimado. Depende das horas feitas.';

/// Explicação grande no detalhe da proposta.
String proposalPriceExplanationLabel(JobProposal p) => p.isFixedTotal
    ? 'É o que pagas no fim, mesmo que o trabalho demore mais.'
    : 'Pagas as horas feitas. O total é uma estimativa.';

String _number(double v) =>
    v == v.roundToDouble() ? v.round().toString() : decimalLabel(v, 1);

/// Duração estimada. Ex.: "2 a 3 dias", "1 dia", "4 a 6 h", "6 h ou
/// mais". Vazio sem duração.
String proposalDurationLabel(JobProposal p) {
  final dMin = p.estimatedDaysMin;
  final dMax = p.estimatedDaysMax;
  if (dMin != null || dMax != null) {
    return workDaysRangeLabel(dMin, dMax);
  }
  final hMin = p.estimatedHoursMin;
  final hMax = p.estimatedHoursMax;
  if (hMin != null && hMax != null && hMax > hMin) {
    return '${_number(hMin)} a ${_number(hMax)} h';
  }
  if (hMin != null && hMax == null) return '${_number(hMin)} h ou mais';
  final one = hMin ?? hMax;
  return one == null ? '' : '${_number(one)} h';
}

/// "1 dia", "2 a 3 dias", "mais de 7 dias".
String workDaysRangeLabel(int? min, int? max) {
  String days(int n) => n == 1 ? '1 dia' : '$n dias';
  if (min != null && max == null) return 'mais de ${days(min - 1)}';
  if (min != null && max != null && max > min) return '$min a ${days(max)}';
  final one = min ?? max;
  return one == null ? '' : days(one);
}

/// Etiquetas do "inclui", pela ordem das opções. Opções que já não
/// existem ficam de fora.
List<String> proposalIncludeLabels(
  JobProposal p,
  List<ProposalIncludeOption> options,
) =>
    [
      for (final o in options)
        if (p.includes.contains(o.slug)) o.label,
    ];

/// "Material, remoção de resíduos". `null` sem nada incluído.
String? proposalIncludesSummaryLabel(
  JobProposal p,
  List<ProposalIncludeOption> options,
) {
  final labels = proposalIncludeLabels(p, options);
  if (labels.isEmpty) return null;
  return [
    labels.first,
    for (final l in labels.skip(1)) l.isEmpty ? l : l[0].toLowerCase() + l.substring(1),
  ].join(', ');
}

/// "Válido até 06/11". `null` sem validade.
String? proposalValidUntilLabel(JobProposal p) {
  final d = p.validUntil;
  if (d == null) return null;
  return 'Válido até ${DateFormat('dd/MM').format(d)}';
}

/// Aviso quando a validade acaba hoje ou amanhã (menos de 48 h): "hoje,
/// 23:59" ou "amanhã, 23:59". `null` fora disso ou já expirada.
String? proposalExpiringSoonLabel(JobProposal p, {required DateTime now}) {
  final d = p.validUntil;
  if (d == null || p.isExpired) return null;
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'hoje, 23:59';
  if (diff == 1) return 'amanhã, 23:59';
  return null;
}

/// "Este orçamento expirou a 06/11".
String proposalExpiredLabel(JobProposal p) {
  final d = p.validUntil;
  if (d == null) return 'Este orçamento expirou';
  return 'Este orçamento expirou a ${DateFormat('dd/MM').format(d)}';
}

/// Valor combinado de uma proposta aceite, nos ecrãs de trabalho.
/// Ex.: "450 € · valor fechado" ou "25,00 €/h · ≈ 100 a 150 €".
String acceptedProposalPriceLabel(JobProposal p) {
  if (p.isFixedTotal) return '${compactMoneyLabel(p.totalPrice!)} · valor fechado';
  return agreedPriceLabel(
    p.hourlyRate,
    p.estimatedHoursMin,
    p.estimatedHoursMax,
    peopleNeeded: p.peopleNeeded,
    helpersEquipmentRequired: p.helpersEquipmentRequired,
  );
}

/// Preço de um cartão do quadro "Os meus trabalhos" (A2): "450 €" no
/// valor fechado; `null` deixa o cartão usar o cálculo por hora.
String? boardFixedPriceLabel(ProposalPricingMode mode, double? totalPrice) =>
    mode == ProposalPricingMode.fixedTotal && (totalPrice ?? 0) > 0
        ? compactMoneyLabel(totalPrice!)
        : null;

/// Dias previstos para "Dia 1 de 3": o máximo da duração em dias. `null`
/// quando a proposta não é em dias ou não tem limite ("mais de 7 dias").
int? plannedWorkDays(JobProposal p) => p.estimatedDaysMax;

/// O trabalho segue dia a dia ("Terminar o dia 1")? Só quando a duração é
/// em dias e pode passar de um dia, ou quando já vai no segundo dia.
bool isMultiDayWork(JobProposal p, {int dayCount = 1}) {
  if (dayCount > 1) return true;
  final min = p.estimatedDaysMin;
  final max = p.estimatedDaysMax;
  if (max != null) return max > 1;
  return min != null;
}

/// "Dia 1 de 3"; passou dos previstos: "Dia 4 · além dos 3 previstos";
/// sem previsão: "Dia 2".
String workDayHeaderLabel(int day, int? planned) {
  if (planned == null) return 'Dia $day';
  if (day > planned) return 'Dia $day · além dos $planned previstos';
  return 'Dia $day de $planned';
}

/// Tempo registado: a soma dos dias (o dia aberto conta até [now]).
Duration workedDuration(List<JobWorkDay> days, {required DateTime now}) {
  var total = Duration.zero;
  for (final d in days) {
    final end = d.endedAt ?? now;
    final part = end.difference(d.startedAt);
    if (!part.isNegative) total += part;
  }
  return total;
}

/// "17 h 40 min", "45 min", "3 h".
String workedTimeLabel(Duration d) {
  final minutes = d.inMinutes < 0 ? 0 : d.inMinutes;
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m min';
  if (m == 0) return '$h h';
  return '$h h $m min';
}
