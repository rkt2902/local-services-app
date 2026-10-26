import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/features/agenda/data/agenda_entry_model.dart';
import 'package:servicesapp/features/agenda/presentation/agenda_week_presenter.dart';
import 'package:servicesapp/features/agenda/presentation/agenda_week_view_data.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_entry_card.dart';
import 'package:servicesapp/features/worker/data/service_type_model.dart';

// Semana de segunda 26 out a domingo 1 nov de 2026; hoje é quarta 28.
final _monday = DateTime(2026, 10, 26);
final _now = DateTime(2026, 10, 28, 10, 20);

DateTime _d(int day) => DateTime(2026, 10, 26 + day);

int _h(int hour, [int minute = 0]) => hour * 60 + minute;

const _types = [
  ServiceType(
    id: 'relva',
    name: 'Corte de relva',
    slug: 'relva',
    icon: 'grass',
    sortOrder: 1,
    categoryName: 'Jardim',
    categorySortOrder: 1,
  ),
];

AgendaEntry _e(
  String id, {
  required DateTime date,
  AgendaEntryKind kind = AgendaEntryKind.appJob,
  int? start,
  int? end,
  String status = 'confirmed',
  int dayIndex = 1,
  int dayCount = 1,
  String? title,
  String? location = 'Rua A 1, Cascais',
  double? amount = 60,
  AgendaRecurrence recurrence = AgendaRecurrence.none,
}) {
  final tentative =
      kind == AgendaEntryKind.proposal || kind == AgendaEntryKind.reschedule;
  return AgendaEntry(
    kind: kind,
    sourceId: id,
    jobId: kind == AgendaEntryKind.external || kind == AgendaEntryKind.block
        ? null
        : 'job-$id',
    proposalId: 'prop-$id',
    date: date,
    seriesDate: date.subtract(Duration(days: dayIndex - 1)),
    status: status,
    startMinutes: start,
    endMinutes: end,
    dayIndex: dayIndex,
    dayCount: dayCount,
    title: title,
    serviceTypeId: kind == AgendaEntryKind.block ? null : 'relva',
    locationLabel: location,
    personName: kind == AgendaEntryKind.block ? null : 'Maria Santos',
    isTentative: tentative,
    amountMin: kind == AgendaEntryKind.block ? null : amount,
    amountMax: kind == AgendaEntryKind.block ? null : amount,
    recurrence: recurrence,
  );
}

AgendaWeekContentViewData _build(
  List<AgendaEntry> entries, {
  bool showProposals = true,
}) => buildAgendaWeek(
  weekStart: _monday,
  entries: entries,
  now: _now,
  showProposals: showProposals,
  serviceTypes: _types,
);

/// Semana como a S1 do design, nos dias de 2026.
List<AgendaEntry> _normalWeek() => [
  _e('done', date: _d(0), start: _h(10), end: _h(12), status: 'completed'),
  _e(
    'consulta',
    date: _d(0),
    kind: AgendaEntryKind.block,
    start: _h(15),
    end: _h(16, 30),
    title: 'Consulta',
    location: 'Médico',
  ),
  _e('a', date: _d(2), start: _h(9), end: _h(11)),
  _e(
    'h',
    date: _d(2),
    kind: AgendaEntryKind.helperJob,
    start: _h(14),
    end: _h(16, 15),
  ),
  _e(
    'x',
    date: _d(2),
    kind: AgendaEntryKind.external,
    start: _h(16, 30),
    end: _h(18),
    title: 'Rega',
    recurrence: AgendaRecurrence.weekly,
  ),
  _e(
    'p',
    date: _d(3),
    kind: AgendaEntryKind.proposal,
    start: _h(9),
    end: _h(12),
    status: 'pending',
  ),
  for (var i = 1; i <= 3; i++)
    _e(
      'multi',
      date: _d(3 + i),
      start: _h(8),
      end: _h(17),
      dayIndex: i,
      dayCount: 3,
      amount: 300,
    ),
];

void main() {
  test('início e texto da semana', () {
    expect(agendaWeekStart(DateTime(2026, 10, 28, 15)), _monday);
    expect(agendaWeekStart(DateTime(2026, 11, 1)), _monday);
    expect(agendaWeekRangeLabel(_monday, _now), '26 out a 1 nov');
    expect(agendaWeekRangeLabel(DateTime(2026, 11, 2), _now), '2 a 8 nov');
    expect(
      agendaWeekRangeLabel(DateTime(2026, 12, 28), _now),
      '28 dez a 3 jan 2027',
    );
  });

  test('S1: resumo, faixa e lista com todos os dias', () {
    final week = _build(_normalWeek());

    // 1 concluído + 3 na quarta + 3 dias do trabalho longo; a proposta à
    // parte. O trabalho de 3 dias conta uma vez no valor.
    expect(week.summaryLabel, '7 trabalhos · 1 proposta · 540 €');
    expect(week.isEmpty, isFalse);
    expect(week.days.map((d) => d.weekdayLetter).join(), 'STQQSSD');
    expect(week.days.map((d) => d.dayNumber), [
      '26', '27', '28', '29', '30', '31', '1', //
    ]);
    expect(week.days.where((d) => d.isToday).single.date, _d(2));

    // Pontos pela ordem da hora.
    expect(week.days[2].dots, [
      AgendaCardKind.app,
      AgendaCardKind.helper,
      AgendaCardKind.external,
    ]);
    expect(week.days[0].dots, [AgendaCardKind.app, AgendaCardKind.block]);
    expect(week.days[3].dots, [AgendaCardKind.proposal]);

    final sections = week.sections;
    expect(sections.map((s) => s.label).first, 'Segunda, 26 out');
    expect(sections[0].countLabel, '1 trabalho');
    expect(sections[2].countLabel, '3 trabalhos');
    expect(sections[2].isToday, isTrue);
    expect(sections[3].countLabel, '1 proposta');
    expect(sections[1].isFree, isTrue);
    expect(sections[1].countLabel, isNull);

    final done = sections[0].items.first.entry!;
    expect(done.done, isTrue);
    final consulta = sections[0].items.last.entry!;
    expect(consulta.title, 'Consulta');
    expect(consulta.subtitle, 'Médico');
    expect(consulta.canOpen, isFalse);

    final rega = sections[2].items.last.entry!;
    expect(rega.repeats, isTrue);
    expect(rega.kind, AgendaCardKind.external);

    final multi = [for (final s in sections.skip(4)) s.items.single.entry!];
    expect(multi.map((e) => '${e.dayIndex}/${e.dayCount}'), [
      '1/3',
      '2/3',
      '3/3',
    ]);
    expect(week.overlap, isNull);
  });

  test('S2: sobreposição e domingo indisponível', () {
    final week = _build([
      _e('a', date: _d(3), start: _h(14), end: _h(15)),
      _e('b', date: _d(3), start: _h(14, 30), end: _h(16)),
      _e(
        'folga',
        date: _d(6),
        kind: AgendaEntryKind.block,
        title: 'Folga',
        location: null,
      ),
    ]);

    expect(week.overlap?.label, 'Quinta: 2 trabalhos ao mesmo tempo às 14:30');
    expect(week.overlap?.day, _d(3));
    expect(week.days[3].hasOverlap, isTrue);
    expect(week.sections[3].hasOverlap, isTrue);
    final group = week.sections[3].items.single.group!;
    expect(group.label, 'Coincidem das 14:30 às 15:00');
    expect(group.entries, hasLength(2));

    expect(week.days[6].unavailable, isTrue);
    expect(week.days[6].dots, [AgendaCardKind.block]);
    expect(week.sections[6].countLabel, 'indisponível');
    final folga = week.sections[6].items.single.entry!;
    expect(folga.subtitle, 'Marcado por ti');
    expect(folga.startLabel, isNull);
  });

  test('sem propostas: saem da lista, dos pontos e do resumo', () {
    final week = _build(_normalWeek(), showProposals: false);
    expect(week.summaryLabel, '7 trabalhos · 540 €');
    expect(week.days[3].dots, isEmpty);
    expect(week.sections[3].isFree, isTrue);
  });

  test('S3: semana livre', () {
    final week = _build(const []);
    expect(week.isEmpty, isTrue);
    expect(week.summaryLabel, isEmpty);
    expect(week.days, hasLength(7));
    expect(week.sections.every((s) => s.isFree), isTrue);
  });
}
