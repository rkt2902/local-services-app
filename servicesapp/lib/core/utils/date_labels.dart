import 'package:intl/intl.dart';

import '../constants/enums.dart';

/// "Hoje"/"Amanhã"/data formatada quando `dateMode == fixed`, ou
/// "Flexível"/"Ver disponibilidade" para os outros modos.
///
/// Extraído de `worker_job_detail_screen.dart` (`_deadlineLabel`) para
/// `core/utils/` quando passou a ser usado também em
/// `client_jobs_screen.dart` — 2+ features, por isso deixa de ser privado
/// de um ecrã (ver architecture.md: "core/ só para o que é partilhado por
/// 2+ features"). Recebe os dois campos em bruto (não um `JobRequest`)
/// para não obrigar `core/` a depender do model da feature `jobs`.
String jobDeadlineLabel(DateMode dateMode, DateTime? preferredDate) {
  switch (dateMode) {
    case DateMode.fixed:
      final date = preferredDate;
      if (date == null) return 'Data a combinar';
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final target = DateTime(date.year, date.month, date.day);
      if (target == today) return 'Hoje';
      if (target == tomorrow) return 'Amanhã';
      return DateFormat('dd/MM/yyyy').format(date);
    case DateMode.flexible:
      return 'Flexível';
    case DateMode.availability:
      return 'Ver disponibilidade';
  }
}
