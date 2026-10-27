import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/features/agenda/application/agenda_entry_actions.dart';
import 'package:servicesapp/features/agenda/application/agenda_entry_form.dart';
import 'package:servicesapp/features/agenda/data/agenda_calendar_entry.dart';
import 'package:servicesapp/features/agenda/data/agenda_entry_model.dart';
import 'package:servicesapp/features/agenda/data/agenda_repository.dart';

/// Regista as escritas em vez de ir ao Supabase.
class _FakeRepo implements AgendaRepository {
  final calls = <String>[];

  String _d(DateTime d) => '${d.month}-${d.day}';

  @override
  Future<void> setEntryStatus(String id, String status) async =>
      calls.add('entry $id $status');

  @override
  Future<void> setOccurrenceStatus({
    required String entryId,
    required DateTime occurrenceDate,
    required String? status,
  }) async => calls.add('day $entryId ${_d(occurrenceDate)} $status');

  @override
  Future<String> splitSeries({
    required String entryId,
    required DateTime fromDate,
  }) async {
    calls.add('split $entryId ${_d(fromDate)}');
    return 'new';
  }

  @override
  Future<void> deleteCalendarEntry(String id) async => calls.add('delete $id');

  @override
  Future<void> updateCalendarEntry(
    String id,
    Map<String, dynamic> values,
  ) async => calls.add('update $id $values');

  @override
  Future<void> saveException({
    required String entryId,
    required DateTime occurrenceDate,
    required Map<String, dynamic> values,
  }) async =>
      calls.add('exception $entryId ${_d(occurrenceDate)} ${values['action']}');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _single = CalendarEntry(
  id: 's',
  kind: CalendarEntryKind.job,
  title: 'Relva',
  startsOn: DateTime(2026, 10, 28),
);

final _series = CalendarEntry(
  id: 'r',
  kind: CalendarEntryKind.job,
  title: 'Rega',
  startsOn: DateTime(2026, 10, 7),
  recurrence: AgendaRecurrence.weekly,
);

void main() {
  late _FakeRepo repo;
  setUp(() => repo = _FakeRepo());

  test('feito: a entrada toda, ou só o dia numa série', () async {
    await markCalendarOccurrenceDone(
      repo,
      entry: _single,
      occurrence: DateTime(2026, 10, 28),
    );
    await markCalendarOccurrenceDone(
      repo,
      entry: _series,
      occurrence: DateTime(2026, 10, 28),
    );
    expect(repo.calls, ['entry s done', 'day r 10-28 done']);
  });

  test('desfazer o feito volta ao estado de onde veio', () async {
    final day = DateTime(2026, 10, 28);
    await undoCalendarOccurrenceDone(
      repo,
      entry: _series,
      exception: CalendarException(
        occurrenceDate: day,
        action: 'status',
        status: 'done',
      ),
      occurrence: day,
    );
    await undoCalendarOccurrenceDone(
      repo,
      entry: _single,
      exception: null,
      occurrence: day,
    );
    expect(repo.calls, ['day r 10-28 null', 'entry s scheduled']);
  });

  test('cancelar numa série segue os dias escolhidos', () async {
    final day = DateTime(2026, 10, 28);
    expect(
      await cancelCalendarOccurrences(
        repo,
        entry: _series,
        occurrence: day,
        scope: AgendaSeriesScope.thisDay,
      ),
      'r',
    );
    expect(
      await cancelCalendarOccurrences(
        repo,
        entry: _series,
        occurrence: day,
        scope: AgendaSeriesScope.following,
      ),
      'new',
    );
    await cancelCalendarOccurrences(
      repo,
      entry: _series,
      occurrence: DateTime(2026, 10, 7),
      scope: AgendaSeriesScope.following,
    );
    expect(repo.calls, [
      'day r 10-28 cancelled',
      'split r 10-28',
      'entry new cancelled',
      'entry r cancelled',
    ]);
  });

  test('repor: só o dia, se foi cancelado só nele', () async {
    final day = DateTime(2026, 10, 28);
    await restoreCalendarOccurrence(
      repo,
      entry: _series,
      exception: CalendarException(
        occurrenceDate: day,
        action: 'changed',
        status: 'cancelled',
      ),
      occurrence: day,
    );
    await restoreCalendarOccurrence(
      repo,
      entry: _series,
      exception: null,
      occurrence: day,
    );
    expect(repo.calls, ['day r 10-28 null', 'entry r scheduled']);
  });

  test('apagar: só o dia sai da agenda; seguintes encurta a série', () async {
    final day = DateTime(2026, 10, 28);
    await deleteCalendarOccurrences(
      repo,
      entry: _series,
      occurrence: day,
      scope: AgendaSeriesScope.thisDay,
    );
    await deleteCalendarOccurrences(
      repo,
      entry: _series,
      occurrence: day,
      scope: AgendaSeriesScope.following,
    );
    await deleteCalendarOccurrences(repo, entry: _single, occurrence: day);
    expect(repo.calls, [
      'exception r 10-28 skipped',
      'update r {recurrence_until: 2026-10-27}',
      'delete s',
    ]);
  });

  test('estado e hora do dia: a exceção manda sobre a série', () {
    final at = DateTime(2026, 10, 28, 17, 40);
    final done = CalendarException(
      occurrenceDate: DateTime(2026, 10, 28),
      action: 'status',
      status: 'done',
      statusAt: at,
    );
    expect(calendarOccurrenceStatus(_series, done), 'done');
    expect(calendarOccurrenceStatusAt(_series, done), at);
    expect(calendarOccurrenceStatus(_series, null), 'scheduled');
  });
}
