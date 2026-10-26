import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/features/agenda/application/agenda_conflicts.dart';
import 'package:servicesapp/features/agenda/data/agenda_entry_model.dart';
import 'package:servicesapp/features/agenda/presentation/agenda_entry_editor_view_data.dart';
import 'package:servicesapp/features/agenda/presentation/agenda_slot_check.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_overlap.dart';
import 'package:servicesapp/features/worker/data/service_type_model.dart';

// Hoje é segunda 26 de outubro de 2026.
final _now = DateTime(2026, 10, 26, 10, 20);
final _fri = DateTime(2026, 10, 30);

int _h(int hour, [int minute = 0]) => hour * 60 + minute;

const _types = [
  ServiceType(id: 'poda', name: 'Poda', slug: 'poda', icon: 'content_cut'),
];

AgendaEntry _entry({
  String id = 'job',
  AgendaEntryKind kind = AgendaEntryKind.appJob,
  int? start,
  int? end,
  String? title,
  bool tentative = false,
  String status = 'confirmed',
}) => AgendaEntry(
  kind: kind,
  sourceId: id,
  date: _fri,
  seriesDate: _fri,
  status: status,
  startMinutes: start,
  endMinutes: end,
  title: title,
  serviceTypeId: 'poda',
  isTentative: tentative,
  locationLabel: 'Rua A 1, Sintra',
);

AgendaSlotCheck _check(int? start, List<AgendaEntry> entries) =>
    checkAgendaSlot(
      slot: AgendaSlot(date: _fri, startMinutes: start, durationMinutes: 120),
      entries: entries,
      serviceTypes: _types,
      now: _now,
      continueLabel: 'Enviar mesmo assim',
      confirmSummary:
          'Se enviares e o cliente aceitar, ficas com dois '
          'trabalhos ao mesmo tempo.',
    );

void main() {
  group('checkAgendaSlot (A10, M1 e M3)', () {
    test('livre: nota verde, sem confirmação', () {
      final c = _check(_h(9), const []);
      expect(c.note.tone, AgendaWarningTone.success);
      expect(c.note.message, 'Estás livre neste horário');
      expect(c.note.actionLabel, 'Ver o dia');
      expect(c.confirm, isNull);
    });

    test('horas cruzam-se com um trabalho: nota âmbar e confirmação', () {
      final c = _check(_h(10), [_entry(start: _h(9), end: _h(12))]);
      expect(c.note.tone, AgendaWarningTone.waiting);
      expect(
        c.note.message,
        'Coincide com Poda, Sintra\n09:00 a 12:00 · já marcado',
      );
      expect(c.isStrong, isTrue);
      expect(c.confirm!.title, 'Já tens um trabalho a esta hora');
      expect(c.confirm!.continueLabel, 'Enviar mesmo assim');
      expect(c.confirm!.summary, startsWith('Se enviares'));
    });

    test('indisponível nesse dia conta como forte', () {
      final c = _check(_h(10), [
        _entry(id: 'b', kind: AgendaEntryKind.block, title: 'Férias'),
      ]);
      expect(c.note.message, startsWith('Estás indisponível neste dia'));
      expect(c.confirm!.title, 'Estás indisponível neste dia');
    });

    test('pouco intervalo: "Fica apertado", sem confirmação', () {
      final c = _check(_h(14), [
        _entry(
          id: 'ext',
          kind: AgendaEntryKind.external,
          title: 'Rega do Sr. Alves',
          start: _h(11, 30),
          end: _h(13, 45),
        ),
      ]);
      expect(c.note.tone, AgendaWarningTone.info);
      expect(
        c.note.message,
        'Fica apertado. Acabas Rega do Sr. Alves, Sintra às 13:45.',
      );
      expect(c.confirm, isNull);
    });

    test(
      'outra proposta à mesma hora: "Também propuseste", sem confirmação',
      () {
        final c = _check(_h(9), [
          _entry(
            id: 'p',
            kind: AgendaEntryKind.proposal,
            start: _h(9),
            end: _h(11),
            tentative: true,
            status: 'pending',
          ),
        ]);
        expect(c.note.tone, AgendaWarningTone.info);
        expect(c.note.message, 'Também propuseste Poda nesta hora');
        expect(c.confirm, isNull);
      },
    );

    test('remarcar não compara com o próprio trabalho', () {
      final c = checkAgendaSlot(
        slot: AgendaSlot(
          date: _fri,
          startMinutes: _h(10),
          ignoreSourceId: 'job',
        ),
        entries: [_entry(start: _h(9), end: _h(12))],
        serviceTypes: _types,
        now: _now,
        continueLabel: 'Pedir mesmo assim',
      );
      expect(c.note.tone, AgendaWarningTone.success);
    });
  });

  group('agendaRequestAvailability (A10, M2)', () {
    test('livre', () {
      final (kind, label) = agendaRequestAvailability(
        slot: AgendaSlot(date: _fri),
        entries: const [],
      );
      expect(kind, AgendaAvailability.free);
      expect(label, 'Estás livre');
    });

    test('conta os trabalhos do dia, não as propostas', () {
      final (kind, label) = agendaRequestAvailability(
        slot: AgendaSlot(date: _fri),
        entries: [
          _entry(id: 'a', start: _h(9), end: _h(11)),
          _entry(id: 'b', kind: AgendaEntryKind.external, start: _h(15)),
          _entry(
            id: 'p',
            kind: AgendaEntryKind.proposal,
            start: _h(12),
            tentative: true,
            status: 'pending',
          ),
        ],
      );
      expect(kind, AgendaAvailability.busyDay);
      expect(label, 'Já tens 2 trabalhos neste dia');
    });

    test('dia indisponível: coincide', () {
      final (kind, label) = agendaRequestAvailability(
        slot: AgendaSlot(date: _fri),
        entries: [_entry(id: 'b', kind: AgendaEntryKind.block)],
      );
      expect(kind, AgendaAvailability.overlap);
      expect(label, 'Estás indisponível neste dia');
    });
  });
}
