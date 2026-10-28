import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/price_labels.dart';
import '../data/worker_earnings_model.dart';

/// Contas do painel de ganhos, sem Riverpod nem Supabase (testável).
///
/// A app não trata de pagamentos, por isso isto é o que o jardineiro
/// combinou receber, calculado como nos outros ecrãs:
///   responsável, por hora: preço por hora × horas registadas;
///   responsável, valor fechado: valor total − o que vai para os ajudantes;
///   ajudante: valor acordado × horas registadas.
/// Sem horas registadas (trabalho sem "Iniciar"), usa a média da estimativa
/// da proposta e marca o valor como estimado.

/// Horas de um trabalho e se vêm da estimativa.
({double hours, bool estimated}) earningHours(WorkerEarningEntry e) {
  final minutes = e.workedMinutes;
  if (minutes != null && minutes > 0) {
    return (hours: minutes / 60, estimated: false);
  }
  final min = e.estimatedHoursMin;
  final max = e.estimatedHoursMax;
  if (min != null && max != null) return (hours: (min + max) / 2, estimated: true);
  return (hours: min ?? max ?? 0, estimated: true);
}

/// Valor de um trabalho para o próprio, e se é estimado.
({double amount, bool estimated}) earningAmount(WorkerEarningEntry e) {
  if (!e.asHelper && e.pricingMode == ProposalPricingMode.fixedTotal) {
    final total = e.totalPrice ?? 0;
    final helpers = e.helpersCost ?? 0;
    final amount = total - helpers;
    return (amount: amount < 0 ? 0 : amount, estimated: false);
  }
  final h = earningHours(e);
  return (amount: e.rate * h.hours, estimated: h.estimated);
}

/// Resumo de um mês.
class WorkerEarningsMonth {
  const WorkerEarningsMonth({
    required this.month,
    required this.entries,
    required this.total,
    required this.awaitingTotal,
    required this.registeredHours,
    required this.hasEstimates,
  });

  /// Primeiro dia do mês.
  final DateTime month;

  /// Trabalhos do mês, do mais recente para o mais antigo.
  final List<WorkerEarningEntry> entries;

  /// Tudo, incluindo o que ainda espera a confirmação do cliente.
  final double total;

  /// A parte de [total] que ainda espera a confirmação do cliente.
  final double awaitingTotal;

  /// Só horas registadas (sem estimativas).
  final double registeredHours;

  /// Algum valor do mês veio da estimativa da proposta.
  final bool hasEstimates;

  int get jobCount => entries.length;
}

DateTime monthStart(DateTime d) => DateTime(d.year, d.month);

/// Agrupa por mês os [months] meses que acabam em [lastMonth] (inclusive),
/// do mais antigo para o mais recente. Meses sem trabalhos vêm a zero.
List<WorkerEarningsMonth> groupEarningsByMonth(
  List<WorkerEarningEntry> entries, {
  required DateTime lastMonth,
  int months = 6,
}) {
  final last = monthStart(lastMonth);
  final result = <WorkerEarningsMonth>[];
  for (var i = months - 1; i >= 0; i--) {
    final month = DateTime(last.year, last.month - i);
    final inMonth = entries
        .where((e) => e.doneOn.year == month.year && e.doneOn.month == month.month)
        .toList()
      ..sort((a, b) => b.doneOn.compareTo(a.doneOn));
    var total = 0.0;
    var awaiting = 0.0;
    var hours = 0.0;
    var estimates = false;
    for (final e in inMonth) {
      final a = earningAmount(e);
      total += a.amount;
      if (e.awaitingConfirmation) awaiting += a.amount;
      if (a.estimated) estimates = true;
      final h = earningHours(e);
      if (!h.estimated) hours += h.hours;
    }
    result.add(WorkerEarningsMonth(
      month: month,
      entries: inMonth,
      total: total,
      awaitingTotal: awaiting,
      registeredHours: hours,
      hasEstimates: estimates,
    ));
  }
  return result;
}

const _monthNames = [
  'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho',
  'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
];

/// "Outubro 2026" (mesmo formato da Agenda).
String earningsMonthLabel(DateTime month) =>
    '${_monthNames[month.month - 1]} ${month.year}';

/// "Out", para as barras.
String earningsMonthShortLabel(DateTime month) =>
    _monthNames[month.month - 1].substring(0, 3);

/// "12 h 30" ou "45 min"; "—" sem horas.
String earningsHoursLabel(double hours) {
  if (hours <= 0) return '—';
  final totalMinutes = (hours * 60).round();
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

/// Valor de uma linha: "45,00 €" ou "≈ 45,00 €" quando é estimado.
String earningAmountLabel(WorkerEarningEntry e) {
  final a = earningAmount(e);
  final money = moneyLabel(a.amount);
  return a.estimated ? '≈ $money' : money;
}

/// Linha por baixo do serviço: "28/10 · Responsável · 2 h" ou
/// "28/10 · Ajudante · por confirmar".
String earningEntrySubtitle(WorkerEarningEntry e) {
  final parts = <String>[
    DateFormat('dd/MM').format(e.doneOn),
    e.asHelper ? 'Ajudante' : 'Responsável',
    if (!e.asHelper && e.pricingMode == ProposalPricingMode.fixedTotal)
      'Valor fechado'
    else
      () {
        final h = earningHours(e);
        return h.estimated
            ? 'estimado'
            : earningsHoursLabel(h.hours);
      }(),
    if (e.awaitingConfirmation) 'por confirmar',
  ];
  return parts.join(' · ');
}
