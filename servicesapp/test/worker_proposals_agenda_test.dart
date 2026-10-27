import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/features/agenda/data/agenda_entry_model.dart';
import 'package:servicesapp/features/worker/data/service_type_model.dart';
import 'package:servicesapp/features/worker/data/worker_job_board_entry_model.dart';
import 'package:servicesapp/features/worker/presentation/worker_proposals_agenda.dart';

// Hoje é segunda 26 de outubro de 2026.
final _now = DateTime(2026, 10, 26, 10, 20);

DateTime _d(int day, [int month = 10]) => DateTime(2026, month, day);

int _h(int hour, [int minute = 0]) => hour * 60 + minute;

const _types = [
  ServiceType(id: 'poda', name: 'Poda', slug: 'poda', icon: 'content_cut'),
];

WorkerJobBoardEntry _board(
  String id, {
  WorkerJobBoardRole role = WorkerJobBoardRole.responsible,
  DateTime? confirmedDate,
  String? confirmedTime,
}) => WorkerJobBoardEntry(
  entryId: id,
  role: role,
  jobId: 'job-$id',
  serviceTypeName: 'Corte de relva',
  personName: 'Rui Costa',
  addressText: 'Cascais',
  status: 'pending',
  createdAt: DateTime(2026, 10, 20),
  confirmedDate: confirmedDate,
  confirmedTime: confirmedTime,
);

AgendaEntry _proposalRow(String id, DateTime day, int start, int end) =>
    AgendaEntry(
      kind: AgendaEntryKind.proposal,
      sourceId: id,
      proposalId: id,
      date: day,
      seriesDate: day,
      status: 'pending',
      isTentative: true,
      startMinutes: start,
      endMinutes: end,
      serviceTypeId: 'poda',
    );

final _poda = AgendaEntry(
  kind: AgendaEntryKind.appJob,
  sourceId: 'job',
  jobId: 'job',
  date: _d(30),
  seriesDate: _d(30),
  status: 'confirmed',
  startMinutes: _h(9),
  endMinutes: _h(12),
  serviceTypeId: 'poda',
  locationLabel: 'Rua A 1, Sintra',
);

void main() {
  test('proposta que choca com um trabalho: data e aviso', () {
    final agenda = [_proposalRow('p1', _d(30), _h(9), _h(11)), _poda];
    final s = workerProposalSchedule(
      _board('p1'),
      agenda: agenda,
      serviceTypes: _types,
      now: _now,
    )!;
    expect(s.label, 'Sex 30 out · 09:00');
    expect(s.durationMinutes, 120);
    expect(s.warning, 'Coincide com Poda, Sintra, 09:00 a 12:00');
  });

  test('outra proposta à mesma hora não faz aviso', () {
    final agenda = [
      _proposalRow('p1', _d(30), _h(9), _h(11)),
      _proposalRow('p2', _d(30), _h(9), _h(11)),
    ];
    final s = workerProposalSchedule(
      _board('p1'),
      agenda: agenda,
      serviceTypes: _types,
      now: _now,
    )!;
    expect(s.warning, isNull);
  });

  test('sem linha na Agenda não há data', () {
    expect(
      workerProposalSchedule(
        _board('p9'),
        agenda: [_poda],
        serviceTypes: _types,
        now: _now,
      ),
      isNull,
    );
  });

  test('candidatura usa a data marcada do trabalho', () {
    final s = workerProposalSchedule(
      _board(
        'h1',
        role: WorkerJobBoardRole.helper,
        confirmedDate: _d(4, 11),
        confirmedTime: '08:30:00',
      ),
      agenda: const [],
      serviceTypes: _types,
      now: _now,
    )!;
    expect(s.label, 'Qua 4 nov · 08:30');
    expect(s.warning, isNull);
  });

  test('indisponível no dia todo', () {
    final s = workerProposalSchedule(
      _board('p1'),
      agenda: [
        _proposalRow('p1', _d(30), _h(9), _h(11)),
        AgendaEntry(
          kind: AgendaEntryKind.block,
          sourceId: 'ferias',
          date: _d(30),
          seriesDate: _d(30),
          status: 'scheduled',
          title: 'Férias',
        ),
      ],
      serviceTypes: _types,
      now: _now,
    )!;
    expect(s.warning, 'Estás indisponível neste dia: Férias');
  });

  test('ordem: com aviso primeiro, depois a data mais próxima', () {
    final schedules = {
      'a': WorkerProposalSchedule(date: _d(6, 11), label: ''),
      'b': WorkerProposalSchedule(date: _d(2, 11), label: ''),
      'c': WorkerProposalSchedule(date: _d(30), label: '', warning: 'x'),
    };
    expect(sortWorkerProposals(['sem', 'a', 'b', 'c'], (id) => schedules[id]), [
      'c',
      'b',
      'a',
      'sem',
    ]);
  });
}
