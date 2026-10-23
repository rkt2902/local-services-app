import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_status_color.dart';

/// "83%" (arredondado) ou "—" sem base.
String adminPercentLabel(int part, int total) {
  if (total <= 0) return '—';
  return '${(part * 100 / total).round()}%';
}

/// "3,5 h" ou "—".
String adminHoursLabel(double? hours) {
  if (hours == null) return '—';
  return '${NumberFormat('0.#', 'pt_PT').format(hours)} h';
}

/// "1 250 €".
String adminEuroLabel(double value) =>
    '${NumberFormat.decimalPattern('pt_PT').format(value.round())} €';

/// "4,8" ou "—".
String adminRatingLabel(double? rating) {
  if (rating == null) return '—';
  return NumberFormat('0.0', 'pt_PT').format(rating);
}

/// "hoje", "ontem", "há 5 dias", "há 3 meses" ou "nunca".
String adminRelativeDateLabel(DateTime? date, {DateTime? now}) {
  if (date == null) return 'nunca';
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final local = date.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return 'hoje';
  if (days == 1) return 'ontem';
  if (days < 60) return 'há $days dias';
  return 'há ${(days / 30).floor()} meses';
}

/// "22/10/2026" ou "—".
String adminDateLabel(DateTime? date) =>
    date == null ? '—' : DateFormat('dd/MM/yyyy').format(date);

const _monthShortNames = [
  'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
  'jul', 'ago', 'set', 'out', 'nov', 'dez',
];

/// `2026-10` → "out".
String adminMonthShortLabel(String yearMonth) {
  final parts = yearMonth.split('-');
  final month = parts.length == 2 ? int.tryParse(parts[1]) : null;
  if (month == null || month < 1 || month > 12) return yearMonth;
  return _monthShortNames[month - 1];
}

/// Tom do selo do plano no painel.
AppStatusColor adminTierStatusColor(WorkerPlanTier tier) => switch (tier) {
      WorkerPlanTier.free => AppStatusColor.neutral,
      WorkerPlanTier.pro => AppStatusColor.success,
      WorkerPlanTier.proPlus => AppStatusColor.info,
    };
