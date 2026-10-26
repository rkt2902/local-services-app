import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/features/agenda/application/agenda_conflicts.dart';
import 'package:servicesapp/features/agenda/application/agenda_entry_form.dart';
import 'package:servicesapp/features/agenda/data/agenda_calendar_entry.dart';
import 'package:servicesapp/features/agenda/data/agenda_entry_model.dart';

DateTime _d(int day, [int month = 10]) => DateTime(2026, month, day);

int _h(int hour, [int minute = 0]) => hour * 60 + minute;

AgendaEntry _job(
  String id, {
  required DateTime date,
  int? start,
  int? end,
  AgendaEntryKind kind = AgendaEntryKind.appJob,
}) => AgendaEntry(
  kind: kind,
  sourceId: id,
  jobId: 'job-$id',
  date: date,
  seriesDate: date,
  status: 'confirmed',
  startMinutes: start,
  endMinutes: end,
  isTentative: kind == AgendaEntryKind.proposal,
);

void main() {
  group('validação', () {
    test('trabalho: só o título é obrigatório', () {
      final form = AgendaEntryForm.create(_d(28));
      expect(form.canSave, isFalse);
      expect(form.blocker, 'Escreve um título para poder guardar.');
      expect(form.copyWith(title: 'Relva da D. Rosa').canSave, isTrue);
    });

    test('indisponível: precisa do motivo e de fim depois do início', () {
      final form = AgendaEntryForm.create(
        _d(28),
        type: AgendaFormType.unavailable,
      );
      expect(form.allDay, isTrue);
      expect(form.blocker, 'Escolhe o motivo para poder guardar.');
      final ok = form.copyWith(reason: AgendaBlockReason.vacation);
      expect(ok.canSave, isTrue);
      expect(
        ok
            .copyWith(allDay: false, startMinutes: _h(14), endMinutes: _h(13))
            .blocker,
        'A hora de fim tem de ser depois da de início.',
      );
    });

    test('telefone, valor e repetição de vários dias', () {
      final form = AgendaEntryForm.create(_d(28)).copyWith(title: 'Rega');
      expect(form.copyWith(phone: '12').canSave, isFalse);
      expect(form.copyWith(phone: '912 345 678').canSave, isTrue);
      expect(form.copyWith(amount: 'abc').canSave, isFalse);
      expect(form.copyWith(amount: '25,50').amountValue, 25.5);
      final long = form.copyWith(
        multiDay: true,
        endDate: _d(5, 11),
        recurrence: AgendaRecurrence.weekly,
      );
      expect(
        long.blocker,
        'Só dá para repetir o que dura até 7 dias seguidos.',
      );
    });
  });

  group('linhas para a base de dados', () {
    test('trabalho com hora, telefone em formato internacional', () {
      final row = AgendaEntryForm.create(_d(28))
          .copyWith(
            title: '  Relva da D. Rosa ',
            personName: 'Rosa Ferreira',
            phone: '912 345 678',
            location: 'Rua das Flores 12, Oeiras',
            locationLat: 38.7,
            locationLng: -9.3,
            startMinutes: _h(16, 30),
            durationMinutes: 60,
            amount: '25',
            notes: 'Levar sacos',
          )
          .toRow();
      expect(row['kind'], 'job');
      expect(row['title'], 'Relva da D. Rosa');
      expect(row['person_phone'], '+351912345678');
      expect(row['starts_on'], '2026-10-28');
      expect(row['start_time'], '16:30:00');
      expect(row['duration_minutes'], 60);
      expect(row['ends_on'], isNull);
      expect(row['amount'], 25);
      expect(row['location_lat'], 38.7);
      expect(row.containsKey('worker_id'), isFalse);
    });

    test('vários dias: sem duração e com o último dia', () {
      final row = AgendaEntryForm.create(
        _d(28),
      ).copyWith(title: 'Poda', multiDay: true, endDate: _d(30)).toRow();
      expect(row['ends_on'], '2026-10-30');
      expect(row['duration_minutes'], isNull);
      expect(row['start_time'], '09:00:00');
    });

    test('indisponível: motivo no título, sem cliente nem valor', () {
      final row =
          AgendaEntryForm.create(_d(28), type: AgendaFormType.unavailable)
              .copyWith(
                reason: AgendaBlockReason.vacation,
                endDate: _d(1, 11),
                blockNote: 'Algarve',
                phone: '912345678',
                amount: '30',
              )
              .toRow();
      expect(row['kind'], 'block');
      expect(row['title'], 'Férias');
      expect(row['notes'], 'Algarve');
      expect(row['ends_on'], '2026-11-01');
      expect(row['start_time'], isNull);
      expect(row['person_phone'], isNull);
      expect(row['amount'], isNull);
    });

    test('"Todos" a partir de outra ocorrência anda com a série', () {
      final form = AgendaEntryForm.create(
        _d(28),
      ).copyWith(title: 'Rega', recurrence: AgendaRecurrence.weekly);
      expect(form.toRow(startsOn: _d(7))['starts_on'], '2026-10-07');
    });

    test('"Só este dia": changed no mesmo dia, moved noutro', () {
      final form = AgendaEntryForm.create(
        _d(10, 11),
      ).copyWith(title: 'Rega', startMinutes: _h(17));
      final same = form.toExceptionRow(_d(10, 11));
      expect(same['action'], 'changed');
      expect(same['new_time'], '17:00:00');
      final moved = form.toExceptionRow(_d(3, 11));
      expect(moved['action'], 'moved');
      expect(moved['new_date'], '2026-11-10');
    });
  });

  group('editar', () {
    final entry = CalendarEntry(
      id: 's1',
      kind: CalendarEntryKind.job,
      title: 'Rega da D. Rosa',
      startsOn: DateTime(2026, 10, 6),
      startMinutes: 16 * 60 + 30,
      durationMinutes: 60,
      recurrence: AgendaRecurrence.weekly,
      personPhone: '+351912345678',
      amount: 25.5,
    );

    test('abre na ocorrência tocada, com a exceção por cima', () {
      final form = AgendaEntryForm.fromEntry(
        entry,
        occurrenceDate: _d(10, 11),
        exception: CalendarException(
          occurrenceDate: _d(10, 11),
          action: 'changed',
          newStartMinutes: _h(17),
          newTitle: 'Rega (mais cedo)',
        ),
      );
      expect(form.date, _d(10, 11));
      expect(form.startMinutes, _h(17));
      expect(form.title, 'Rega (mais cedo)');
      expect(form.amount, '25,50');
      expect(form.recurrence, AgendaRecurrence.weekly);
    });

    test('"Só este dia" só serve para data, horas, título e notas', () {
      final original = AgendaEntryForm.fromEntry(
        entry,
        occurrenceDate: _d(10, 11),
      );
      expect(
        original
            .copyWith(startMinutes: _h(17), title: 'Outra')
            .onlyOccurrenceFieldsChanged(original),
        isTrue,
      );
      expect(
        original.copyWith(amount: '40').onlyOccurrenceFieldsChanged(original),
        isFalse,
      );
    });

    test('indisponível: o título volta a ser o motivo', () {
      final block = AgendaEntryForm.fromEntry(
        CalendarEntry(
          id: 'b1',
          kind: CalendarEntryKind.block,
          title: 'Folga',
          startsOn: _d(31),
          endsOn: _d(2, 11),
        ),
      );
      expect(block.type, AgendaFormType.unavailable);
      expect(block.reason, AgendaBlockReason.dayOff);
      expect(block.allDay, isTrue);
      expect(block.lastDay, _d(2, 11));
    });
  });

  test('trocar de tipo guarda a data e as horas', () {
    final work = AgendaEntryForm.create(
      _d(28),
    ).copyWith(startMinutes: _h(9), durationMinutes: 120);
    final block = work.switchType(AgendaFormType.unavailable);
    expect(block.date, _d(28));
    expect(block.endMinutes, _h(11));
    expect(block.switchType(AgendaFormType.work).durationMinutes, 120);
  });

  test('mudar a data arrasta o último dia', () {
    final form = AgendaEntryForm.create(
      _d(28),
    ).copyWith(multiDay: true, endDate: _d(30)).withDate(_d(2, 11));
    expect(form.lastDay, _d(4, 11));
  });

  group('sobreposições', () {
    final entries = [
      _job('a', date: _d(28), start: _h(9), end: _h(11)),
      _job('b', date: _d(28), start: _h(16), end: _h(17)),
      _job(
        'p',
        date: _d(29),
        start: _h(9),
        end: _h(10),
        kind: AgendaEntryKind.proposal,
      ),
    ];
    final base = AgendaEntryForm.create(_d(28)).copyWith(title: 'Novo');

    test('forte quando as horas se cruzam; ignora a própria entrada', () {
      final form = base.copyWith(startMinutes: _h(9, 30), durationMinutes: 120);
      final found = form.conflicts(entries);
      expect(found.first.level, AgendaConflictLevel.strong);
      expect(found.first.other.sourceId, 'a');
      expect(form.conflicts(entries, ignoreSourceId: 'a'), isEmpty);
    });

    test('pouco intervalo é leve; proposta é tentativa', () {
      final gap = base.copyWith(startMinutes: _h(17, 15), durationMinutes: 60);
      expect(gap.conflicts(entries).single.level, AgendaConflictLevel.light);
      final tentative = base
          .withDate(_d(29))
          .copyWith(startMinutes: _h(9), durationMinutes: 60);
      expect(
        tentative.conflicts(entries).single.level,
        AgendaConflictLevel.tentative,
      );
    });

    test('vários dias contam como dia todo em cada dia', () {
      final form = base.copyWith(multiDay: true, endDate: _d(29));
      expect(form.conflicts(entries), hasLength(3));
    });

    test('indisponível: trabalhos nos dias escolhidos', () {
      final block = AgendaEntryForm.create(
        _d(28),
        type: AgendaFormType.unavailable,
      ).copyWith(endDate: _d(29));
      expect(block.entriesInRange(entries), hasLength(3));
      expect(block.conflicts(entries), isEmpty);
    });
  });
}
