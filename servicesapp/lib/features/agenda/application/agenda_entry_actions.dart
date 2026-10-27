import '../data/agenda_calendar_entry.dart';
import '../data/agenda_repository.dart';
import 'agenda_entry_form.dart';

// Ações sobre um trabalho de fora da app ou uma indisponibilidade
// (`worker_calendar_entries`, 0064), iguais no detalhe e no formulário.
// `occurrence` é o dia da série tocado na Agenda (`series_date`).

/// Estado deste dia: o da exceção, se houver, senão o da série.
String calendarOccurrenceStatus(
  CalendarEntry entry,
  CalendarException? exception,
) => exception?.status ?? entry.status;

/// Hora a que este dia passou a feito ou cancelado.
DateTime? calendarOccurrenceStatusAt(
  CalendarEntry entry,
  CalendarException? exception,
) => exception?.status != null ? exception?.statusAt : entry.statusAt;

/// "Marcar como feito". Numa série é sempre só este dia: marcar dias que
/// ainda não aconteceram como feitos não faz sentido.
Future<void> markCalendarOccurrenceDone(
  AgendaRepository repo, {
  required CalendarEntry entry,
  required DateTime occurrence,
}) => entry.repeats
    ? repo.setOccurrenceStatus(
        entryId: entry.id,
        occurrenceDate: occurrence,
        status: 'done',
      )
    : repo.setEntryStatus(entry.id, 'done');

/// "Afinal não foi feito" e o "Desfazer" do feito.
Future<void> undoCalendarOccurrenceDone(
  AgendaRepository repo, {
  required CalendarEntry entry,
  required CalendarException? exception,
  required DateTime occurrence,
}) => exception?.status == 'done'
    ? repo.setOccurrenceStatus(
        entryId: entry.id,
        occurrenceDate: occurrence,
        status: null,
      )
    : repo.setEntryStatus(entry.id, 'scheduled');

/// "Cancelar este trabalho": fica na agenda, riscado. Devolve a série que
/// ficou cancelada (a nova, em "Este e os seguintes" a meio da série).
Future<String> cancelCalendarOccurrences(
  AgendaRepository repo, {
  required CalendarEntry entry,
  required DateTime occurrence,
  AgendaSeriesScope? scope,
}) async {
  if (!entry.repeats) {
    await repo.setEntryStatus(entry.id, 'cancelled');
    return entry.id;
  }
  switch (scope ?? AgendaSeriesScope.thisDay) {
    case AgendaSeriesScope.thisDay:
      await repo.setOccurrenceStatus(
        entryId: entry.id,
        occurrenceDate: occurrence,
        status: 'cancelled',
      );
      return entry.id;
    case AgendaSeriesScope.following when occurrence.isAfter(entry.startsOn):
      final id = await repo.splitSeries(
        entryId: entry.id,
        fromDate: occurrence,
      );
      await repo.setEntryStatus(id, 'cancelled');
      return id;
    case AgendaSeriesScope.following || AgendaSeriesScope.all:
      await repo.setEntryStatus(entry.id, 'cancelled');
      return entry.id;
  }
}

/// Volta a marcado um cancelado: só este dia, se foi cancelado só nele;
/// senão a série (ou a parte dela) que foi cancelada.
Future<void> restoreCalendarOccurrence(
  AgendaRepository repo, {
  required CalendarEntry entry,
  required CalendarException? exception,
  required DateTime occurrence,
}) => exception?.status == 'cancelled'
    ? repo.setOccurrenceStatus(
        entryId: entry.id,
        occurrenceDate: occurrence,
        status: null,
      )
    : repo.setEntryStatus(entry.id, 'scheduled');

/// Apagar: tira da agenda (ao contrário de cancelar). Numa série, [scope]
/// diz que dias; "Este e os seguintes" a partir do primeiro dia é a série
/// toda.
Future<void> deleteCalendarOccurrences(
  AgendaRepository repo, {
  required CalendarEntry entry,
  required DateTime occurrence,
  AgendaSeriesScope? scope,
}) async {
  if (!entry.repeats) {
    await repo.deleteCalendarEntry(entry.id);
    return;
  }
  switch (scope ?? AgendaSeriesScope.all) {
    case AgendaSeriesScope.thisDay:
      await repo.saveException(
        entryId: entry.id,
        occurrenceDate: occurrence,
        values: AgendaEntryForm.skippedExceptionRow(),
      );
    case AgendaSeriesScope.following when occurrence.isAfter(entry.startsOn):
      final last = occurrence.subtract(const Duration(days: 1));
      await repo.updateCalendarEntry(entry.id, {
        'recurrence_until':
            '${last.year.toString().padLeft(4, '0')}-'
            '${last.month.toString().padLeft(2, '0')}-'
            '${last.day.toString().padLeft(2, '0')}',
      });
    case AgendaSeriesScope.following || AgendaSeriesScope.all:
      await repo.deleteCalendarEntry(entry.id);
  }
}
