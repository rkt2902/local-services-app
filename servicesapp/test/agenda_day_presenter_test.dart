import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/features/agenda/data/agenda_entry_model.dart';
import 'package:servicesapp/features/agenda/presentation/agenda_day_presenter.dart';
import 'package:servicesapp/features/agenda/presentation/agenda_day_view_data.dart';
import 'package:servicesapp/features/agenda/presentation/agenda_month_sheet.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_entry_card.dart';
import 'package:servicesapp/features/worker/data/service_type_model.dart';

final _day = DateTime(2026, 10, 28);

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
  ServiceType(
    id: 'poda',
    name: 'Poda',
    slug: 'poda',
    icon: 'content_cut',
    sortOrder: 2,
    categoryName: 'Jardim',
    categorySortOrder: 1,
  ),
];

AgendaEntry _e(
  String id, {
  AgendaEntryKind kind = AgendaEntryKind.appJob,
  DateTime? date,
  int? start,
  int? end,
  String status = 'confirmed',
  String service = 'relva',
  int dayIndex = 1,
  int dayCount = 1,
  String? title,
  String? phone = '+351 912 345 678',
  double? amount = 60,
}) {
  final d = date ?? _day;
  final tentative =
      kind == AgendaEntryKind.proposal || kind == AgendaEntryKind.reschedule;
  return AgendaEntry(
    kind: kind,
    sourceId: id,
    jobId: kind == AgendaEntryKind.external || kind == AgendaEntryKind.block
        ? null
        : 'job-$id',
    proposalId: 'prop-$id',
    date: d,
    seriesDate: d.subtract(Duration(days: dayIndex - 1)),
    status: status,
    startMinutes: start,
    endMinutes: end,
    dayIndex: dayIndex,
    dayCount: dayCount,
    title: title,
    serviceTypeId: kind == AgendaEntryKind.block ? null : service,
    locationLabel: 'Rua A 1, Cascais',
    personName: 'Maria Santos',
    personPhone: phone,
    isTentative: tentative,
    amountMin: amount,
    amountMax: amount,
  );
}

AgendaDayContentViewData _build(
  List<AgendaEntry> entries, {
  DateTime? now,
  bool showProposals = true,
}) => buildAgendaDay(
  day: _day,
  entries: entries,
  now: now ?? DateTime(2026, 10, 28, 10, 20),
  showProposals: showProposals,
  serviceTypes: _types,
);

List<AgendaDayItemKind> _kinds(AgendaDayContentViewData c) => [
  for (final i in c.items) i.kind,
];

void main() {
  group('rótulos', () {
    test('dia: hoje, amanhã, ontem e outro', () {
      final now = DateTime(2026, 10, 28, 9);
      expect(agendaDayLabel(_day, now), 'Hoje, quarta 28 out');
      expect(agendaDayLabel(DateTime(2026, 10, 29), now), 'Amanhã, quinta 29 out');
      expect(agendaDayLabel(DateTime(2026, 10, 27), now), 'Ontem, terça 27 out');
      expect(agendaDayLabel(DateTime(2026, 10, 31), now), 'Sábado, 31 out');
      expect(agendaDayLabel(DateTime(2027, 1, 4), now), 'Segunda, 4 jan 2027');
    });

    test('valor fechado sem ≈, estimado com intervalo', () {
      expect(agendaAmountLabel(60, 60), '60 €');
      expect(agendaAmountLabel(45, 60), '≈ 45 a 60 €');
      expect(agendaAmountLabel(null, null), isNull);
      expect(agendaAmountLabel(0, 0), isNull);
    });

    test('chave do dia', () {
      expect(agendaDayKey(DateTime(2026, 3, 5, 14)), '2026-03-05');
    });
  });

  group('H1 dia normal', () {
    final entries = [
      _e('a', start: _h(9), end: _h(11)),
      _e('b', kind: AgendaEntryKind.helperJob, service: 'poda', start: _h(14), end: _h(16, 15), amount: 70),
      _e('c', kind: AgendaEntryKind.external, title: 'Rega', start: _h(16, 30), end: _h(17, 30), amount: 50),
      // Outro dia: ignorado.
      _e('x', date: DateTime(2026, 10, 29), start: _h(9)),
    ];

    test('ordem: cartão atual, agora, livre, cartão, curto, cartão', () {
      final c = _build(entries);
      expect(_kinds(c), [
        AgendaDayItemKind.entry,
        AgendaDayItemKind.now,
        AgendaDayItemKind.free,
        AgendaDayItemKind.entry,
        AgendaDayItemKind.free,
        AgendaDayItemKind.entry,
      ]);
      expect(c.items[1].label, '10:20');
      expect(c.items[2].label, 'Livre das 11:00 às 14:00');
      expect(c.items[4].label, 'Só 15 min até ao próximo');
      expect(c.items[4].short, isTrue);
    });

    test('o trabalho a decorrer tem contorno e Iniciar; os outros não', () {
      final c = _build(entries);
      final first = c.items[0].entry!;
      expect(first.current, isTrue);
      expect(first.showStart, isTrue);
      expect(first.title, 'Corte de relva');
      expect(first.subtitle, 'Cascais · Maria Santos');
      expect(first.pill, AgendaCardPill.scheduled);
      expect(first.showWhatsApp, isTrue);
      expect(first.showMap, isTrue);

      final helper = c.items[3].entry!;
      expect(helper.kind, AgendaCardKind.helper);
      expect(helper.subtitle, 'Cascais · com Maria Santos');
      expect(helper.showStart, isFalse);
      expect(helper.current, isFalse);

      final external = c.items[5].entry!;
      expect(external.kind, AgendaCardKind.external);
      expect(external.title, 'Rega');
      // Abre o formulário de editar.
      expect(external.canOpen, isTrue);
    });

    test('resumo: trabalhos, horas e valor', () {
      expect(
        _build(entries).summaryLabel,
        '3 trabalhos · das 09:00 às 17:30 · 180 €',
      );
    });

    test('Iniciar só a partir de 1 h antes e só no próprio dia', () {
      final job = [_e('a', start: _h(11), end: _h(13))];
      expect(
        _build(job, now: DateTime(2026, 10, 28, 9, 59)).items
            .firstWhere((i) => i.kind == AgendaDayItemKind.entry)
            .entry!
            .showStart,
        isFalse,
      );
      expect(
        _build(job, now: DateTime(2026, 10, 28, 10)).items
            .firstWhere((i) => i.kind == AgendaDayItemKind.entry)
            .entry!
            .showStart,
        isTrue,
      );
      // Outro dia: nunca, e sem linha de agora.
      final tomorrow = _build(job, now: DateTime(2026, 10, 27, 23));
      expect(tomorrow.items.single.entry!.showStart, isFalse);
      expect(_kinds(tomorrow), [AgendaDayItemKind.entry]);
    });

    test('antes de tudo: agora e "Livre até às"', () {
      final c = _build([
        _e('a', start: _h(14), end: _h(16)),
      ], now: DateTime(2026, 10, 28, 8));
      expect(_kinds(c), [
        AgendaDayItemKind.now,
        AgendaDayItemKind.free,
        AgendaDayItemKind.entry,
      ]);
      expect(c.items[1].label, 'Livre até às 14:00');
    });
  });

  group('H2 sobreposição', () {
    final entries = [
      _e('a', service: 'poda', start: _h(14), end: _h(16, 15)),
      _e('b', start: _h(14), end: _h(15, 30)),
    ];

    test('aviso no topo e um grupo com o intervalo comum', () {
      final c = _build(entries);
      expect(c.items.first.kind, AgendaDayItemKind.overlapAlert);
      expect(c.items.first.label, '2 trabalhos ao mesmo tempo às 14:00');
      final group = c.items
          .firstWhere((i) => i.kind == AgendaDayItemKind.overlapGroup)
          .group!;
      expect(group.label, 'Coincidem das 14:00 às 15:30');
      expect(group.entries, hasLength(2));
      expect(c.items[1].kind, AgendaDayItemKind.now);
      expect(c.items[2].label, 'Livre até às 14:00');
    });
  });

  group('H3 propostas', () {
    final entries = [
      _e('a', start: null, end: null),
      _e(
        'p',
        kind: AgendaEntryKind.proposal,
        start: _h(9),
        end: _h(12),
        phone: null,
        amount: 120,
      ),
    ];
    final now = DateTime(2026, 10, 27, 10, 20);

    test('"Sem hora marcada" primeiro, depois "Por hora"', () {
      final c = _build(entries, now: now);
      expect(c.items[0].label, 'Sem hora marcada');
      final untimed = c.items[1].entry!;
      expect(untimed.timeToArrange, isTrue);
      expect(untimed.showChooseTime, isTrue);
      expect(c.items[2].label, 'Por hora');
      final proposal = c.items[3].entry!;
      expect(proposal.kind, AgendaCardKind.proposal);
      expect(proposal.pill, AgendaCardPill.proposal);
      expect(proposal.showOpenProposal, isTrue);
      expect(proposal.showWhatsApp, isFalse);
      expect(proposal.subtitle, 'Cascais');
      expect(c.summaryLabel, '1 trabalho · 1 proposta · 60 €');
    });

    test('desligar as propostas tira o cartão e a contagem', () {
      final c = _build(entries, now: now, showProposals: false);
      expect(
        c.items.where((i) => i.entry?.kind == AgendaCardKind.proposal),
        isEmpty,
      );
      expect(c.summaryLabel, '1 trabalho · 60 €');
    });

    test('propostas não entram nos grupos de sobreposição', () {
      final c = _build([
        _e('a', start: _h(9), end: _h(11)),
        _e('p', kind: AgendaEntryKind.proposal, start: _h(9), end: _h(10)),
      ], now: now);
      expect(
        c.items.where((i) => i.kind == AgendaDayItemKind.overlapGroup),
        isEmpty,
      );
    });
  });

  group('H4 indisponível', () {
    final block = _e(
      'f',
      kind: AgendaEntryKind.block,
      title: 'Férias',
      date: _day,
      dayIndex: 1,
      dayCount: 5,
      phone: null,
      amount: null,
    );

    test('só o bloco quando não há trabalhos', () {
      final c = _build([block]);
      final u = c.unavailability!;
      expect(u.title, 'Férias');
      expect(u.subtitle, 'Dia todo · Dia 1 de 5');
      expect(u.description, startsWith('28 out a 1 nov.'));
      expect(c.items, isEmpty);
      expect(c.summaryLabel, 'Indisponível · dia todo');
      expect(c.isEmpty, isFalse);
    });

    test('com trabalhos marcados, ficam por baixo', () {
      final c = _build([block, _e('a', start: _h(9), end: _h(11))]);
      expect(c.unavailability, isNotNull);
      expect(c.items.where((i) => i.kind == AgendaDayItemKind.entry), hasLength(1));
      expect(c.summaryLabel, startsWith('Indisponível · dia todo · 1 trabalho'));
    });
  });

  group('H5 vazio', () {
    test('sem resumo nem itens', () {
      final c = _build(const []);
      expect(c.isEmpty, isTrue);
      expect(c.summaryLabel, isEmpty);
    });
  });

  group('outros casos', () {
    test('trabalho de vários dias fica em "Sem hora marcada"', () {
      final c = _build([
        _e('m', start: null, dayIndex: 2, dayCount: 3),
      ]);
      final e = c.items[1].entry!;
      expect(e.dayIndex, 2);
      expect(e.dayCount, 3);
      expect(e.timeToArrange, isFalse);
      expect(e.showStart, isFalse);
    });

    test('concluído: atenuado e sem botões', () {
      final c = _build([
        _e('a', start: _h(9), end: _h(10), status: 'completed'),
      ]);
      final e = c.items.firstWhere((i) => i.entry != null).entry!;
      expect(e.done, isTrue);
      expect(e.pill, AgendaCardPill.done);
      expect(e.showWhatsApp, isFalse);
      expect(e.showMap, isFalse);
    });

    test('pontos do calendário por dia, sem repetir nem fechados', () {
      final dots = agendaDotsByDay([
        _e('a', start: _h(9)),
        _e('b', start: _h(11)),
        _e('c', kind: AgendaEntryKind.external, start: _h(14)),
        _e('d', date: DateTime(2026, 10, 30), status: 'completed'),
      ]);
      expect(dots[28], [AgendaCardKind.app, AgendaCardKind.external]);
      expect(dots.containsKey(30), isFalse);
    });
  });
}
