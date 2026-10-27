import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/features/agenda/data/agenda_entry_model.dart';
import 'package:servicesapp/features/agenda/presentation/agenda_week_presenter.dart';
import 'package:servicesapp/features/agenda/presentation/agenda_week_view_data.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_controls.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_skeleton.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_week_view.dart';

// Semana de 26 out a 1 nov de 2026; hoje é quarta 28.
final _monday = DateTime(2026, 10, 26);
final _now = DateTime(2026, 10, 28, 10, 20);

DateTime _d(int day) => DateTime(2026, 10, 26 + day);

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
  amountMin: 60,
  amountMax: 60,
);

AgendaWeekContentViewData _content(
  List<AgendaEntry> entries, {
  DateTime? weekStart,
}) => buildAgendaWeek(
  weekStart: weekStart ?? _monday,
  entries: entries,
  now: _now,
  showProposals: true,
  serviceTypes: const [],
);

class _Calls {
  final opened = <String>[];
  final openedDays = <DateTime>[];
  final conflictDays = <DateTime>[];
  final addedOn = <DateTime>[];
  final selected = <DateTime>[];
  int next = 0;
  int previous = 0;
  int current = 0;
  int search = 0;
  int retry = 0;
}

/// Uma semana cheia: dois trabalhos por dia, para a lista ter scroll.
List<AgendaEntry> _busyWeek() => [
  for (var day = 0; day < 6; day++) ...[
    _e('m$day', date: _d(day), start: _h(9), end: _h(11)),
    _e('t$day', date: _d(day), start: _h(14), end: _h(16)),
  ],
  _e(
    'fora',
    date: _d(2),
    kind: AgendaEntryKind.external,
    start: _h(18),
    end: _h(19),
    title: 'Rega',
  ),
];

Widget _view(
  _Calls calls, {
  AgendaWeekContentViewData? content,
  DateTime? weekStart,
  bool loading = false,
  bool isCurrentWeek = true,
  DateTime? initialDay,
  bool withAdd = false,
}) {
  final start = weekStart ?? _monday;
  return MaterialApp(
    home: Scaffold(
      body: AgendaWeekView(
        weekKey: '${start.month}-${start.day}',
        rangeLabel: agendaWeekRangeLabel(start, _now),
        isCurrentWeek: isCurrentWeek,
        showProposals: true,
        days: (content ?? _content(const [], weekStart: start)).days,
        content: content,
        initialDay: initialDay,
        loading: loading,
        onPreviousWeek: () => calls.previous++,
        onNextWeek: () => calls.next++,
        onGoToCurrentWeek: () => calls.current++,
        onOpenCalendar: () {},
        onRangeChanged: (_) {},
        onShowProposalsChanged: (_) {},
        onRefresh: () async {},
        onRetry: () => calls.retry++,
        onOpenEntry: (e) => calls.opened.add(e.sourceId),
        onOpenDay: calls.openedDays.add,
        onOpenDayAtConflict: calls.conflictDays.add,
        onResolveOverlap: (_) {},
        onSelectedDayChanged: calls.selected.add,
        onSearchWork: () => calls.search++,
        onAddToAgenda: withAdd ? () {} : null,
        onAddToAgendaOnDay: withAdd ? calls.addedOn.add : null,
      ),
    ),
  );
}

void main() {
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

  testWidgets('S1: abre em hoje, com os dias antes por cima', (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(
      _view(calls, content: _content(_busyWeek()), initialDay: _d(2)),
    );
    await tester.pumpAndSettle();

    expect(find.text('26 out a 1 nov'), findsOneWidget);
    expect(find.textContaining('13 trabalhos'), findsOneWidget);
    // Semana atual: sem botão "Hoje".
    expect(find.byType(AgendaTodayButton), findsNothing);
    expect(
      find.textContaining('Quarta, 28 out', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Segunda, 26 out', findRichText: true).hitTestable(),
      findsNothing,
    );
    // Domingo sem nada: linha "Livre" sem "+" enquanto não há formulário.
    await tester.scrollUntilVisible(
      find.textContaining('Domingo, 1 nov', findRichText: true),
      200,
    );
    expect(find.byIcon(Icons.add_circle_outline_rounded), findsNothing);
  });

  testWidgets('tocar num dia da faixa leva a lista até ele', (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(
      _view(calls, content: _content(_busyWeek()), initialDay: _d(0)),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Sábado, 31 out', findRichText: true).hitTestable(),
      findsNothing,
    );

    await tester.tap(find.text('31'));
    await tester.pumpAndSettle();
    expect(calls.selected.last, _d(5));
    expect(
      find.textContaining('Sábado, 31 out', findRichText: true).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('scroll à mão muda o dia preenchido', (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(
      _view(calls, content: _content(_busyWeek()), initialDay: _d(0)),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(calls.selected, isNotEmpty);
    expect(calls.selected.last.isAfter(_d(0)), isTrue);
  });

  testWidgets('cartões: fora da app abre o formulário; o dia abre o Hoje', (
    tester,
  ) async {
    final calls = _Calls();
    await tester.pumpWidget(
      _view(calls, content: _content(_busyWeek()), initialDay: _d(2)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rega'));
    expect(calls.opened, hasLength(1));
    expect(calls.openedDays, isEmpty);
    await tester.tap(find.textContaining('Quarta, 28 out', findRichText: true));
    expect(calls.openedDays, [_d(2)]);
  });

  testWidgets('deslizar a faixa muda de semana', (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(
      _view(calls, content: _content(_busyWeek()), initialDay: _d(2)),
    );
    await tester.pumpAndSettle();
    await tester.fling(find.text('29'), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(calls.next, 1);
    await tester.fling(find.text('29'), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(calls.previous, 1);
  });

  testWidgets('S2: aviso de sobreposição abre o dia no conflito', (
    tester,
  ) async {
    final calls = _Calls();
    await tester.pumpWidget(
      _view(
        calls,
        content: _content([
          _e('a', date: _d(3), start: _h(14), end: _h(15)),
          _e('b', date: _d(3), start: _h(14), end: _h(16)),
          _e('folga', date: _d(6), kind: AgendaEntryKind.block, title: 'Folga'),
        ]),
        initialDay: _d(2),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Quinta: 2 trabalhos ao mesmo tempo às 14:00'),
      findsOneWidget,
    );
    expect(find.text('Coincidem das 14:00 às 15:00'), findsOneWidget);
    await tester.tap(find.text('Ver o dia'));
    expect(calls.conflictDays, [_d(3)]);
  });

  testWidgets('S3: semana livre noutra semana', (tester) async {
    final calls = _Calls();
    final next = DateTime(2026, 11, 2);
    await tester.pumpWidget(
      _view(
        calls,
        content: _content(const [], weekStart: next),
        weekStart: next,
        isCurrentWeek: false,
        withAdd: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Semana livre'), findsOneWidget);
    expect(find.text('Ainda não tens nada de 2 a 8 nov.'), findsOneWidget);
    expect(find.byType(AgendaTodayButton), findsOneWidget);

    await tester.tap(find.byType(AgendaTodayButton));
    expect(calls.current, 1);
    await tester.tap(find.text('Procurar trabalho'));
    expect(calls.search, 1);
    expect(find.text('Adicionar à agenda'), findsOneWidget);
    // Tocar num dia da faixa: marcar alguma coisa nesse dia.
    await tester.tap(find.text('5'));
    expect(calls.addedOn, [DateTime(2026, 11, 5)]);
  });

  testWidgets('a carregar: faixa e esqueleto, sem spinner', (tester) async {
    await tester.pumpWidget(_view(_Calls(), loading: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AgendaEntrySkeleton), findsNWidgets(4));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('28'), findsOneWidget);
    expect(find.text('Mostrar propostas'), findsOneWidget);
  });

  testWidgets('erro sem dados', (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(_view(calls));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível carregar a agenda'), findsOneWidget);
    await tester.tap(find.text('Tentar de novo'));
    expect(calls.retry, 1);
  });
}
