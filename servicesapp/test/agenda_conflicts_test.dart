import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/features/agenda/application/agenda_conflicts.dart';
import 'package:servicesapp/features/agenda/data/agenda_entry_model.dart';

final _day = DateTime(2026, 11, 3);

AgendaEntry _entry({
  AgendaEntryKind kind = AgendaEntryKind.appJob,
  String id = 'a',
  DateTime? date,
  int? start,
  int? end,
  int dayIndex = 1,
  int dayCount = 1,
  String status = 'confirmed',
  bool tentative = false,
}) {
  final d = date ?? _day;
  return AgendaEntry(
    kind: kind,
    sourceId: id,
    date: d,
    seriesDate: d,
    status: status,
    startMinutes: start,
    endMinutes: end,
    dayIndex: dayIndex,
    dayCount: dayCount,
    isTentative: tentative,
  );
}

int _h(int hour, [int minute = 0]) => hour * 60 + minute;

void main() {
  group('AgendaEntry.fromJson', () {
    test('lê a linha da RPC, com horas e vários dias', () {
      final e = AgendaEntry.fromJson({
        'entry_kind': 'helper_job',
        'source_id': 'x',
        'job_id': 'j',
        'occurrence_date': '2026-11-06',
        'series_date': '2026-11-05',
        'start_time': null,
        'end_time': null,
        'day_index': 2,
        'day_count': 3,
        'status': 'confirmed',
        'is_tentative': false,
        'amount_min': 20,
        'amount_max': 40.5,
        'recurrence': 'none',
        'is_exception': false,
      });
      expect(e.kind, AgendaEntryKind.helperJob);
      expect(e.date, DateTime(2026, 11, 6));
      expect(e.seriesDate, DateTime(2026, 11, 5));
      expect(e.isMultiDay, isTrue);
      expect(e.amountMax, 40.5);
    });

    test('converte horas em minutos e volta', () {
      expect(parseTimeMinutes('09:30:00'), 570);
      expect(parseTimeMinutes('23:59'), 1439);
      expect(parseTimeMinutes(null), isNull);
      expect(formatMinutes(570), '09:30');
    });
  });

  group('conflictsForSlot', () {
    test('horas que se cruzam são aviso forte, com o intervalo comum', () {
      final c = conflictsForSlot(
        AgendaSlot(date: _day, startMinutes: _h(9, 30), durationMinutes: 120),
        [_entry(start: _h(9), end: _h(11))],
      );
      expect(c, hasLength(1));
      expect(c.first.level, AgendaConflictLevel.strong);
      expect(c.first.reason, AgendaConflictReason.overlap);
      expect(c.first.overlapStart, _h(9, 30));
      expect(c.first.overlapEnd, _h(11));
    });

    test('encostados não coincidem, mas é pouco intervalo', () {
      final c = conflictsForSlot(
        AgendaSlot(date: _day, startMinutes: _h(11), durationMinutes: 60),
        [_entry(start: _h(9), end: _h(11))],
      );
      expect(c.single.level, AgendaConflictLevel.light);
      expect(c.single.reason, AgendaConflictReason.shortGap);
      expect(c.single.gapMinutes, 0);
    });

    test('30 minutos ou mais de folga: livre', () {
      final c = conflictsForSlot(
        AgendaSlot(date: _day, startMinutes: _h(11, 30), durationMinutes: 60),
        [_entry(start: _h(9), end: _h(11))],
      );
      expect(c, isEmpty);
    });

    test('sem hora de um dos lados: aviso leve de mesmo dia', () {
      final semHora = conflictsForSlot(AgendaSlot(date: _day), [
        _entry(start: _h(9), end: _h(11)),
      ]);
      expect(semHora.single.reason, AgendaConflictReason.sameDayNoTime);
      expect(semHora.single.level, AgendaConflictLevel.light);

      final outroSemHora = conflictsForSlot(
        AgendaSlot(date: _day, startMinutes: _h(15)),
        [_entry()],
      );
      expect(outroSemHora.single.reason, AgendaConflictReason.sameDayNoTime);
    });

    test('indisponível e trabalhos de vários dias ocupam o dia todo', () {
      final ferias = conflictsForSlot(
        AgendaSlot(date: _day, startMinutes: _h(9)),
        [_entry(kind: AgendaEntryKind.block)],
      );
      expect(ferias.single.level, AgendaConflictLevel.strong);
      expect(ferias.single.reason, AgendaConflictReason.wholeDay);

      final variosDias = conflictsForSlot(AgendaSlot(date: _day), [
        _entry(dayIndex: 2, dayCount: 3),
      ]);
      expect(variosDias.single.level, AgendaConflictLevel.strong);
    });

    test('propostas pendentes contam como tentativa', () {
      final c = conflictsForSlot(
        AgendaSlot(date: _day, startMinutes: _h(10), durationMinutes: 60),
        [
          _entry(
            kind: AgendaEntryKind.proposal,
            start: _h(10),
            end: _h(12),
            tentative: true,
          ),
        ],
      );
      expect(c.single.level, AgendaConflictLevel.tentative);
    });

    test('ignora outros dias, entradas fechadas e a própria entrada', () {
      final c = conflictsForSlot(
        AgendaSlot(
          date: _day,
          startMinutes: _h(9),
          durationMinutes: 60,
          ignoreSourceId: 'eu',
        ),
        [
          _entry(id: 'eu', start: _h(9), end: _h(10)),
          _entry(id: 'b', start: _h(9), end: _h(10), status: 'completed'),
          _entry(id: 'c', start: _h(9), end: _h(10), status: 'done'),
          _entry(
            id: 'd',
            start: _h(9),
            end: _h(10),
            date: DateTime(2026, 11, 4),
          ),
        ],
      );
      expect(c, isEmpty);
    });

    test('sem fim: 2 h para a app, 60 min para os de fora', () {
      final app = conflictsForSlot(
        AgendaSlot(date: _day, startMinutes: _h(10, 45), durationMinutes: 30),
        [_entry(start: _h(9))],
      );
      expect(app.single.level, AgendaConflictLevel.strong);

      final fora = conflictsForSlot(
        AgendaSlot(date: _day, startMinutes: _h(10, 45), durationMinutes: 30),
        [_entry(kind: AgendaEntryKind.external, start: _h(9))],
      );
      expect(fora, isEmpty);
    });

    test('ordena do mais grave para o mais leve', () {
      final c = conflictsForSlot(
        AgendaSlot(date: _day, startMinutes: _h(10), durationMinutes: 60),
        [
          _entry(id: 'leve', start: _h(11, 10), end: _h(12)),
          _entry(id: 'forte', start: _h(9), end: _h(10, 30)),
        ],
      );
      expect(c.map((e) => e.other.sourceId), ['forte', 'leve']);
      expect(worstConflict(c)!.level, AgendaConflictLevel.strong);
    });
  });

  group('overlapGroupsForDay', () {
    test('junta os que se cruzam e diz desde quando coincidem', () {
      final groups = overlapGroupsForDay([
        _entry(id: 'a', start: _h(9), end: _h(11)),
        _entry(id: 'b', start: _h(9, 30), end: _h(12)),
        _entry(id: 'c', start: _h(14), end: _h(15)),
      ]);
      expect(groups, hasLength(1));
      expect(groups.single.entries.map((e) => e.sourceId), ['a', 'b']);
      expect(groups.single.start, _h(9, 30));
      expect(groups.single.end, _h(11));
    });

    test('três em cadeia ficam no mesmo grupo', () {
      final groups = overlapGroupsForDay([
        _entry(id: 'a', start: _h(9), end: _h(10)),
        _entry(id: 'b', start: _h(9, 30), end: _h(11)),
        _entry(id: 'c', start: _h(10, 30), end: _h(12)),
      ]);
      expect(groups.single.entries, hasLength(3));
      expect(groups.single.start, _h(9, 30));
      expect(groups.single.end, _h(11));
    });

    test('tentativas e dias todos não entram nos grupos', () {
      final groups = overlapGroupsForDay([
        _entry(id: 'a', start: _h(9), end: _h(11)),
        _entry(
          id: 'p',
          kind: AgendaEntryKind.proposal,
          start: _h(9),
          end: _h(11),
          tentative: true,
        ),
        _entry(id: 'sem', start: null),
      ]);
      expect(groups, isEmpty);
    });
  });

  group('dayHasOverlap e freeMinutesBetween', () {
    test('dia com férias e um trabalho tem sobreposição', () {
      expect(
        dayHasOverlap([
          _entry(kind: AgendaEntryKind.block, id: 'f'),
          _entry(start: _h(9), end: _h(10)),
        ]),
        isTrue,
      );
      expect(dayHasOverlap([_entry(start: _h(9), end: _h(10))]), isFalse);
    });

    test('tempo livre entre dois trabalhos', () {
      expect(
        freeMinutesBetween(
          _entry(start: _h(9), end: _h(11, 30)),
          _entry(start: _h(14), end: _h(15)),
        ),
        150,
      );
      expect(
        freeMinutesBetween(
          _entry(start: _h(9), end: _h(11)),
          _entry(start: _h(10), end: _h(12)),
        ),
        isNull,
      );
    });
  });
}
