import '../application/agenda_conflicts.dart';
import '../data/agenda_entry_model.dart';
import 'agenda_day_view_data.dart';

/// Folha "Ver o dia" (A8F): só para ver. Mostra o dia escolhido num
/// formulário (adicionar, editar, enviar proposta) com o que se está a marcar
/// por cima, a tracejado, sem gravar nada.

/// O que se está a marcar, vindo do formulário. Nunca é gravado.
class AgendaDayPreviewGhost {
  const AgendaDayPreviewGhost({
    required this.date,
    required this.label,
    this.lastDate,
    this.startMinutes,
    this.durationMinutes,
    this.wholeDay = false,
    this.allDay = false,
    this.slotKind = AgendaEntryKind.external,
    this.ignoreSourceId,
  });

  final DateTime date;

  /// Último dia, quando ocupa vários (aparece em todos).
  final DateTime? lastDate;

  /// "O teu trabalho", "A tua proposta", "A nova hora".
  final String label;

  /// Nulo = sem hora (dia todo ou hora a combinar).
  final int? startMinutes;
  final int? durationMinutes;

  /// Ocupa o dia todo (indisponível ou vários dias).
  final bool wholeDay;

  /// Sem hora, mas sem ocupar o dia: "dia todo" em vez de "sem hora".
  final bool allDay;

  /// Escolhe a duração por omissão quando o formulário não a tem.
  final AgendaEntryKind slotKind;

  /// A própria entrada, ao editar: não aparece nem conta.
  final String? ignoreSourceId;

  /// [day] está entre [date] e [lastDate].
  bool covers(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final first = DateTime(date.year, date.month, date.day);
    final last = lastDate == null
        ? first
        : DateTime(lastDate!.year, lastDate!.month, lastDate!.day);
    return !d.isBefore(first) && !d.isAfter(last);
  }

  /// O slot de [day] para comparar com a agenda.
  AgendaSlot slotOn(DateTime day) => AgendaSlot(
    date: day,
    startMinutes: wholeDay ? null : startMinutes,
    durationMinutes: durationMinutes,
    wholeDay: wholeDay,
    ignoreSourceId: ignoreSourceId,
  );
}

/// Faixa por cima da lista. [none] não aparece (dias sem fantasma).
enum AgendaPreviewAssessment {
  none,

  /// Cabe (tom success).
  fits,

  /// Cabe, mas com pouco intervalo ou no mesmo dia sem hora (tom info).
  tight,

  /// Coincide com uma proposta enviada (neutro).
  tentative,

  /// As horas cruzam-se ou o dia está ocupado (tom waiting).
  conflict,
}

sealed class AgendaPreviewItem {
  const AgendaPreviewItem();
}

/// Uma entrada real, só de leitura.
class AgendaPreviewEntryItem extends AgendaPreviewItem {
  const AgendaPreviewEntryItem(this.entry, {this.conflict = false});

  final AgendaDayEntryViewData entry;

  /// Choca com o fantasma fora de um grupo (dia todo): faixa âmbar.
  final bool conflict;
}

/// O que se está a marcar, a tracejado.
class AgendaPreviewGhostItem extends AgendaPreviewItem {
  const AgendaPreviewGhostItem({required this.label, this.conflict = false});

  /// "O teu trabalho, 09:00 a 11:00".
  final String label;
  final bool conflict;
}

/// Entradas (e talvez o fantasma) cujas horas se cruzam, com a faixa âmbar.
class AgendaPreviewGroupItem extends AgendaPreviewItem {
  const AgendaPreviewGroupItem({required this.label, required this.children});

  /// "Choca das 10:00 às 11:00" ou "Coincidem das 09:30 às 11:00".
  final String label;
  final List<AgendaPreviewItem> children;
}

/// "Livre das 12:00 às 15:00", "Livre até às 09:00".
class AgendaPreviewFreeItem extends AgendaPreviewItem {
  const AgendaPreviewFreeItem(this.label, {this.short = false});

  final String label;
  final bool short;
}

/// "Sem hora marcada" / "Por hora".
class AgendaPreviewSectionItem extends AgendaPreviewItem {
  const AgendaPreviewSectionItem(this.label);

  final String label;
}

class AgendaPreviewEmptyViewData {
  const AgendaPreviewEmptyViewData({required this.title, required this.body});

  final String title;
  final String body;
}

class AgendaDayPreviewViewData {
  const AgendaDayPreviewViewData({
    required this.day,
    required this.dayKey,
    required this.dayLabel,
    required this.items,
    this.assessment = AgendaPreviewAssessment.none,
    this.assessmentLabel,
    this.empty,
    this.hasGhost = false,
  });

  final DateTime day;

  /// Muda a cada dia: chave da troca com fade-through.
  final String dayKey;

  /// "Sexta, 30 out".
  final String dayLabel;

  /// Já ordenados: sem hora primeiro, depois por hora.
  final List<AgendaPreviewItem> items;

  final AgendaPreviewAssessment assessment;
  final String? assessmentLabel;

  /// Nada (mais) neste dia, no fim da lista.
  final AgendaPreviewEmptyViewData? empty;

  /// Só o dia do formulário tem o fantasma.
  final bool hasGhost;
}
