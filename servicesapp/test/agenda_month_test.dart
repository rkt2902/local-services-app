import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/features/agenda/data/agenda_entry_model.dart';
import 'package:servicesapp/features/agenda/presentation/agenda_month_presenter.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_controls.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_entry_card.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_month_view.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_skeleton.dart';

// Outubro de 2026; hoje é quarta 28.
final _now = DateTime(2026, 10, 28, 10, 20);

DateTime _d(int day) => DateTime(2026, 10, day);

int _h(int hour, [int minute = 0]) => hour * 60 + minute;

AgendaEntry _e(
  String id, {
  required DateTime date,
  AgendaEntryKind kind = AgendaEntryKind.appJob,
  int? start,
  int? end,
  String? title,
}) => AgendaEntry(
  kind: kind,
  sourceId: id,
  jobId: kind == AgendaEntryKind.external || kind == AgendaEntryKind.block
      ? null
      : 'job-$id',
  proposalId: 'prop-$id',
  date: date,
  seriesDate: date,
  status: 'confirmed',
  startMinutes: start,
  endMinutes: end,
  title: title ?? 'Trabalho $id',
  locationLabel: 'Cascais',
  personName: 'Maria Santos',
  isTentative: kind == AgendaEntryKind.proposal,
  amountMin: 60,
  amountMax: 60,
);

List<AgendaEntry> _october() => [
  for (final (i, kind) in const [
    (1, AgendaEntryKind.appJob),
    (2, AgendaEntryKind.helperJob),
    (3, AgendaEntryKind.external),
    (4, AgendaEntryKind.proposal),
  ])
    _e(
      'v$i',
      date: _d(20),
      kind: kind,
      start: _h(8 + i * 2),
      end: _h(9 + i * 2),
    ),
  _e('a', date: _d(22), start: _h(9), end: _h(11)),
  _e('b', date: _d(22), start: _h(10), end: _h(12)),
  _e('ferias', date: _d(13), kind: AgendaEntryKind.block, title: 'Férias'),
  _e(
    'fora',
    date: _d(6),
    kind: AgendaEntryKind.external,
    start: _h(16),
    end: _h(18),
    title: 'Rega',
  ),
  // Novembro: a grelha mostra o 1, mas sem pontos.
  _e('nov', date: DateTime(2026, 11, 1), start: _h(9), end: _h(10)),
];

AgendaMonthContentViewData _build(DateTime selected) => buildAgendaMonth(
  selectedDay: selected,
  entries: _october(),
  now: _now,
  showProposals: true,
  serviceTypes: const [],
);

class _Calls {
  final selected = <DateTime>[];
  final opened = <DateTime>[];
  final entries = <String>[];
  final added = <DateTime>[];
  int today = 0;
  int previous = 0;
  int next = 0;
}

Widget _view(
  _Calls calls,
  DateTime selected, {
  bool loading = false,
  bool withAdd = false,
  bool currentMonth = true,
}) {
  final content = loading ? null : _build(selected);
  return MaterialApp(
    home: Scaffold(
      body: AgendaMonthView(
        monthKey: '${selected.year}-${selected.month}',
        monthLabel: agendaMonthLabel(selected),
        isCurrentMonth: currentMonth,
        showProposals: true,
        cells: (content ?? _build(selected)).cells,
        selectedDay: selected,
        selected: content?.selected,
        loading: loading,
        onPreviousMonth: () => calls.previous++,
        onNextMonth: () => calls.next++,
        onGoToToday: () => calls.today++,
        onOpenCalendar: () {},
        onRangeChanged: (_) {},
        onShowProposalsChanged: (_) {},
        onRefresh: () async {},
        onSelectDay: calls.selected.add,
        onOpenDay: calls.opened.add,
        onOpenEntry: (e) => calls.entries.add(e.sourceId),
        onResolveOverlap: (_) {},
        onAddToAgendaOnDay: withAdd ? calls.added.add : null,
      ),
    ),
  );
}

void main() {
  group('presenter', () {
    test('grelha de segunda a domingo com os dias ao lado', () {
      final month = _build(_d(28));
      expect(agendaMonthLabel(_d(1)), 'Outubro 2026');
      // 1 de outubro de 2026 é quinta: começa na segunda 28 de setembro.
      expect(month.cells.first.day.date, DateTime(2026, 9, 28));
      expect(month.cells.first.inMonth, isFalse);
      expect(month.cells.last.day.date, DateTime(2026, 11, 1));
      expect(month.cells, hasLength(35));
      // Linhas de outro mês não aparecem.
      expect(month.cells.last.day.dots, isEmpty);
    });

    test('pontos, indisponível, sobreposição e dia escolhido', () {
      final month = _build(_d(22));
      AgendaMonthCellViewData cell(int day) =>
          month.cells.firstWhere((c) => c.inMonth && c.day.date == _d(day));

      expect(cell(20).day.dots, [
        AgendaCardKind.app,
        AgendaCardKind.helper,
        AgendaCardKind.external,
        AgendaCardKind.proposal,
      ]);
      expect(cell(13).day.unavailable, isTrue);
      expect(cell(22).day.hasOverlap, isTrue);
      expect(cell(28).day.isToday, isTrue);

      expect(month.selected.label, 'Quinta, 22 out');
      expect(month.selected.countLabel, '2 trabalhos');
      expect(
        month.selected.items.single.group?.label,
        'Coincidem das 10:00 às 11:00',
      );
    });

    test('mês com 6 semanas', () {
      // Agosto de 2026 começa num sábado.
      final month = buildAgendaMonth(
        selectedDay: DateTime(2026, 8, 15),
        entries: const [],
        now: _now,
        showProposals: true,
        serviceTypes: const [],
      );
      expect(month.cells, hasLength(42));
      expect(month.selected.isFree, isTrue);
    });
  });

  group('vista', () {
    setUp(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.views.first.physicalSize = const Size(
        1170,
        2532,
      );
      binding.platformDispatcher.views.first.devicePixelRatio = 3;
    });

    tearDown(() {
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    testWidgets('M1: dia escolhido, Ver dia, +1 e toques', (tester) async {
      final calls = _Calls();
      await tester.pumpWidget(_view(calls, _d(22)));
      await tester.pumpAndSettle();

      expect(find.text('Outubro 2026'), findsOneWidget);
      expect(find.byType(AgendaTodayButton), findsNothing);
      expect(find.text('+1'), findsOneWidget);
      expect(find.text('Coincidem das 10:00 às 11:00'), findsOneWidget);

      await tester.tap(find.text('Ver dia'));
      expect(calls.opened, [_d(22)]);

      await tester.tap(find.text('6'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(calls.selected, [_d(6)]);

      // Dia de novembro na grelha: a integração muda de mês.
      await tester.tap(find.text('1').last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(calls.selected.last, DateTime(2026, 11, 1));

      // Duplo toque abre o Hoje.
      await tester.tap(find.text('6'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('6'));
      await tester.pumpAndSettle();
      expect(calls.opened.last, _d(6));
    });

    testWidgets('entrada fora da app abre o formulário', (tester) async {
      final calls = _Calls();
      await tester.pumpWidget(_view(calls, _d(6)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rega'));
      expect(calls.entries, ['fora']);
      expect(calls.opened, isEmpty);
    });

    testWidgets('M3: dia livre, com e sem formulário', (tester) async {
      final calls = _Calls();
      await tester.pumpWidget(_view(calls, _d(31)));
      await tester.pumpAndSettle();
      expect(find.text('Nada marcado neste dia.'), findsOneWidget);
      expect(find.text('Adicionar neste dia'), findsNothing);

      await tester.pumpWidget(_view(calls, _d(31), withAdd: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adicionar neste dia'));
      expect(calls.added, [_d(31)]);
    });

    testWidgets('outro mês mostra Hoje; deslizar muda de mês', (tester) async {
      final calls = _Calls();
      await tester.pumpWidget(_view(calls, _d(22), currentMonth: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AgendaTodayButton));
      expect(calls.today, 1);
      await tester.fling(find.text('15'), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(calls.next, 1);
      await tester.fling(find.text('15'), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(calls.previous, 1);
    });

    testWidgets('a carregar: grelha e esqueleto, sem spinner', (tester) async {
      await tester.pumpWidget(_view(_Calls(), _d(22), loading: true));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AgendaEntrySkeleton), findsNWidgets(2));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('22'), findsOneWidget);
    });
  });
}
