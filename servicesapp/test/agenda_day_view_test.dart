import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/features/agenda/data/agenda_entry_model.dart';
import 'package:servicesapp/features/agenda/presentation/agenda_day_presenter.dart';
import 'package:servicesapp/features/agenda/presentation/agenda_day_view_data.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_controls.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_day_view.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_skeleton.dart';

final _day = DateTime(2026, 10, 28);
final _now = DateTime(2026, 10, 28, 10, 20);

int _h(int hour, [int minute = 0]) => hour * 60 + minute;

AgendaEntry _e(
  String id, {
  AgendaEntryKind kind = AgendaEntryKind.appJob,
  int? start,
  int? end,
  int dayCount = 1,
  String? title,
}) => AgendaEntry(
  kind: kind,
  sourceId: id,
  jobId: kind == AgendaEntryKind.block ? null : 'job-$id',
  proposalId: 'prop-$id',
  date: _day,
  seriesDate: _day,
  status: 'confirmed',
  startMinutes: start,
  endMinutes: end,
  dayCount: dayCount,
  title: title,
  locationLabel: 'Cascais',
  personName: 'Maria Santos',
  personPhone: kind == AgendaEntryKind.block ? null : '912345678',
  amountMin: kind == AgendaEntryKind.block ? null : 60,
  amountMax: kind == AgendaEntryKind.block ? null : 60,
);

AgendaDayContentViewData _content(List<AgendaEntry> entries) => buildAgendaDay(
  day: _day,
  entries: entries,
  now: _now,
  showProposals: true,
  serviceTypes: const [],
);

class _Calls {
  final opened = <String>[];
  final started = <String>[];
  final available = <String>[];
  List<AgendaEntry>? resolved;
  int next = 0;
  int previous = 0;
  int search = 0;
  int add = 0;
  int retry = 0;
}

Widget _view(
  _Calls calls, {
  AgendaDayContentViewData? content,
  bool loading = false,
  bool isToday = true,
  String? offline,
  bool withAdd = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: AgendaDayView(
        dayKey: '2026-10-28',
        dayLabel: 'Hoje, quarta 28 out',
        range: AgendaRange.day,
        isToday: isToday,
        showProposals: true,
        content: content,
        loading: loading,
        offlineLabel: offline,
        onRetry: () => calls.retry++,
        onPreviousDay: () => calls.previous++,
        onNextDay: () => calls.next++,
        onGoToToday: () {},
        onOpenCalendar: () {},
        onRangeChanged: (_) {},
        onShowProposalsChanged: (_) {},
        onRefresh: () async {},
        onOpenEntry: (e) => calls.opened.add(e.sourceId),
        onStartJob: (e) => calls.started.add(e.sourceId),
        onChooseTime: (e) => calls.opened.add(e.sourceId),
        onWhatsApp: (_) {},
        onMap: (_) {},
        onResolveOverlap: (list) => calls.resolved = list,
        onSearchWork: () => calls.search++,
        onAddToAgenda: withAdd ? () => calls.add++ : null,
        onMarkAvailable: (e) => calls.available.add(e.sourceId),
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
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('H1: resumo, agora, livre e Iniciar sem abrir o cartão', (
    tester,
  ) async {
    final calls = _Calls();
    await tester.pumpWidget(
      _view(
        calls,
        content: _content([
          _e('a', start: _h(9), end: _h(11)),
          _e('b', start: _h(14), end: _h(16)),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hoje, quarta 28 out'), findsOneWidget);
    expect(find.textContaining('2 trabalhos'), findsOneWidget);
    expect(find.text('10:20'), findsOneWidget);
    expect(find.text('Livre das 11:00 às 14:00'), findsOneWidget);
    // Hoje: sem botão "Hoje" ao lado do seletor.
    expect(find.byType(AgendaTodayButton), findsNothing);

    await tester.tap(find.text('Iniciar'));
    expect(calls.started, ['a']);
    expect(calls.opened, isEmpty);

    await tester.tap(find.text('09:00'));
    expect(calls.opened, ['a']);
  });

  testWidgets('deslizar muda de dia', (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(
      _view(calls, content: _content([_e('a', start: _h(14), end: _h(15))])),
    );
    await tester.pumpAndSettle();
    await tester.fling(find.text('14:00'), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(calls.next, 1);
    await tester.fling(find.text('14:00'), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(calls.previous, 1);
  });

  testWidgets('H2: aviso no topo e grupo que coincide', (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(
      _view(
        calls,
        content: _content([
          _e('a', start: _h(14), end: _h(16)),
          _e('b', start: _h(14, 30), end: _h(15, 30)),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 trabalhos ao mesmo tempo às 14:30'), findsOneWidget);
    await tester.tap(find.text('Ver'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coincidem das 14:30 às 15:30'));
    expect(calls.resolved?.map((e) => e.sourceId), ['a', 'b']);
  });

  testWidgets('H3: outro dia mostra o botão Hoje', (tester) async {
    await tester.pumpWidget(
      _view(_Calls(), content: _content(const []), isToday: false),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AgendaTodayButton), findsOneWidget);
    expect(find.text('Nada marcado neste dia'), findsOneWidget);
  });

  testWidgets('H4: indisponível com trabalho por baixo e Já estou livre', (
    tester,
  ) async {
    final calls = _Calls();
    await tester.pumpWidget(
      _view(
        calls,
        content: _content([
          _e('f', kind: AgendaEntryKind.block, title: 'Férias', dayCount: 1),
          _e('a', start: _h(9), end: _h(11)),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Férias'), findsOneWidget);
    expect(find.text('Marcaste este dia como indisponível.'), findsOneWidget);
    expect(find.text('Tens trabalhos marcados neste dia.', findRichText: true),
        findsNothing);
    expect(find.textContaining('Tens trabalhos marcados', findRichText: true),
        findsOneWidget);
    // Sem formulário ainda: sem "Mudar datas".
    expect(find.text('Mudar datas'), findsNothing);
    await tester.tap(find.text('Já estou livre'));
    expect(calls.available, ['f']);
  });

  testWidgets('H5: dia livre com Procurar trabalho e Adicionar à agenda', (
    tester,
  ) async {
    final calls = _Calls();
    await tester.pumpWidget(_view(calls, content: _content(const [])));
    await tester.pumpAndSettle();
    expect(find.text('Nada marcado para hoje'), findsOneWidget);
    expect(find.text('Adicionar à agenda'), findsNothing);
    await tester.tap(find.text('Procurar trabalho'));
    expect(calls.search, 1);

    await tester.pumpWidget(
      _view(calls, content: _content(const []), withAdd: true),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar à agenda'));
    expect(calls.add, 1);
  });

  testWidgets('H6: a carregar, esqueleto e controlos ativos, sem spinner', (
    tester,
  ) async {
    await tester.pumpWidget(_view(_Calls(), loading: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AgendaEntrySkeleton), findsNWidgets(2));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Mostrar propostas'), findsOneWidget);
    expect(find.text('Semana'), findsOneWidget);
  });

  testWidgets('H7: erro sem dados e erro com dados guardados', (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(_view(calls));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível carregar a agenda'), findsOneWidget);
    await tester.tap(find.text('Tentar de novo'));
    expect(calls.retry, 1);

    await tester.pumpWidget(
      _view(
        calls,
        content: _content([_e('a', start: _h(14), end: _h(15))]),
        offline: 'Sem rede · dados das 08:12',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sem rede · dados das 08:12'), findsOneWidget);
    expect(find.text('14:00'), findsOneWidget);
  });
}
