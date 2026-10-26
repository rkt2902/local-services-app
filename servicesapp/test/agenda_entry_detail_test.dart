import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/features/agenda/application/agenda_entry_form.dart';
import 'package:servicesapp/features/agenda/data/agenda_calendar_entry.dart';
import 'package:servicesapp/features/agenda/data/agenda_entry_model.dart';
import 'package:servicesapp/features/agenda/presentation/agenda_day_presenter.dart';
import 'package:servicesapp/features/agenda/presentation/agenda_entry_detail_presenter.dart';
import 'package:servicesapp/features/agenda/presentation/agenda_entry_detail_view_data.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_entry_detail_view.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_entry_card.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_entry_editor_view.dart';
import 'package:servicesapp/features/worker/data/service_type_model.dart';

// Hoje é quarta 28 de outubro de 2026.
final _now = DateTime(2026, 10, 28, 10, 20);

DateTime _d(int day, [int month = 10, int year = 2026]) =>
    DateTime(year, month, day);

int _h(int hour, [int minute = 0]) => hour * 60 + minute;

const _types = [
  ServiceType(
    id: 'poda',
    name: 'Poda de sebes',
    slug: 'poda',
    icon: 'content_cut',
  ),
];

/// D1: "Relva da D. Rosa", todas as quartas até 31 mar, 16:30 a 17:30.
final _rosa = CalendarEntry(
  id: 'rosa',
  kind: CalendarEntryKind.job,
  title: 'Relva da D. Rosa',
  startsOn: _d(7),
  startMinutes: _h(16, 30),
  durationMinutes: 60,
  recurrence: AgendaRecurrence.weekly,
  recurrenceUntil: _d(31, 3, 2027),
  personName: 'Rosa Ferreira',
  personPhone: '+351912345678',
  locationLabel: 'Rua das Flores 12, Oeiras',
  amount: 25,
  notes: 'Portão do lado. Levar o saco dos restos.',
);

final _ferias = CalendarEntry(
  id: 'ferias',
  kind: CalendarEntryKind.block,
  title: 'Férias',
  startsOn: _d(10, 11),
  endsOn: _d(14, 11),
);

/// Poda da app às 17:00, a cruzar com a Rosa.
final _agenda = [
  AgendaEntry(
    kind: AgendaEntryKind.appJob,
    sourceId: 'job',
    jobId: 'job',
    date: _d(28),
    seriesDate: _d(28),
    status: 'confirmed',
    startMinutes: _h(17),
    endMinutes: _h(18),
    serviceTypeId: 'poda',
  ),
];

AgendaDetailViewData _build(
  CalendarEntry entry, {
  CalendarException? exception,
  DateTime? occurrence,
  List<AgendaEntry>? entries,
}) => buildAgendaEntryDetail(
  entry: entry,
  exception: exception,
  occurrence: occurrence ?? _d(28),
  entries: entries,
  serviceTypes: _types,
  now: _now,
);

void main() {
  group('presenter', () {
    test('D1: marcado, repete, coincide', () {
      final data = _build(
        _rosa,
        entries: _agenda,
        exception: CalendarException(
          occurrenceDate: _d(28),
          action: 'changed',
          newTitle: 'Relva da D. Rosa',
        ),
      );
      expect(data.state, AgendaDetailState.scheduled);
      expect(data.status.label, 'Marcado');
      expect(data.showSourceBadge, isTrue);
      expect(data.when.primary, 'Quarta, 28 out · 16:30 a 17:30');
      expect(data.when.secondary, 'Repete todas as quartas, até 31 mar 2027');
      expect(data.when.exceptionLabel, 'Mudado só este dia');
      expect(data.overlap?.title, 'Coincide com outro trabalho.');
      expect(data.overlap?.detail, 'Poda de sebes, 17:00 a 18:00 (app)');
      expect(data.person?.name, 'Rosa Ferreira');
      expect(data.person?.hasWhatsApp, isTrue);
      expect(data.place?.address, 'Rua das Flores 12, Oeiras');
      expect(data.valueNotes?.sectionTitle, 'Valor e notas');
      expect(data.valueNotes?.value, '25 € combinado');
      expect(data.primary?.kind, AgendaDetailPrimary.markDone);
      expect(data.showCancel, isTrue);
    });

    test('D4: feito mostra a hora, o próximo e "Afinal não foi feito"', () {
      final data = _build(
        _rosa,
        entries: _agenda,
        exception: CalendarException(
          occurrenceDate: _d(28),
          action: 'status',
          status: 'done',
          statusAt: DateTime(2026, 10, 28, 17, 40),
        ),
      );
      expect(data.state, AgendaDetailState.done);
      expect(data.status.label, 'Feito');
      expect(data.metaLabel, 'Marcado como feito a 28 out, às 17:40');
      expect(data.when.secondary, 'Próximo: quarta 4 nov');
      expect(data.when.exceptionLabel, isNull);
      expect(data.overlap, isNull);
      expect(data.primary?.kind, AgendaDetailPrimary.undoDone);
      expect(data.showCancel, isFalse);
    });

    test('cancelado: pode ser reposto', () {
      final data = _build(
        CalendarEntry(
          id: 'x',
          kind: CalendarEntryKind.job,
          title: 'Rega',
          startsOn: _d(28),
          status: 'cancelled',
        ),
      );
      expect(data.status.label, 'Cancelado');
      expect(data.primary?.kind, AgendaDetailPrimary.restore);
      expect(data.when.primary, 'Quarta, 28 out · dia inteiro');
      expect(data.person, isNull);
      expect(data.place, isNull);
      expect(data.valueNotes, isNull);
    });

    test('sem telefone: só o nome, sem WhatsApp', () {
      final data = _build(
        CalendarEntry(
          id: 'x',
          kind: CalendarEntryKind.job,
          title: 'Rega',
          startsOn: _d(28),
          personName: 'Sr. Luís',
        ),
      );
      expect(data.person?.name, 'Sr. Luís');
      expect(data.person?.hasWhatsApp, isFalse);
    });

    test('D5: indisponibilidade com período e aviso, sem feito', () {
      final data = _build(_ferias, occurrence: _d(10, 11));
      expect(data.state, AgendaDetailState.unavailable);
      expect(data.status.label, 'Indisponível');
      expect(data.title, 'Férias');
      expect(data.heroIcon, Icons.beach_access_outlined);
      expect(data.when.primary, '10 a 14 nov · dia inteiro');
      expect(data.when.secondary, 'Terça a sábado · 5 dias');
      expect(data.unavailableInfo, isNotNull);
      expect(data.primary, isNull);
      expect(data.showSourceBadge, isFalse);
    });

    test('próximo dia: semanal, mensal no fim do mês e fim da série', () {
      expect(nextCalendarOccurrence(_rosa, _d(28)), _d(4, 11));
      final monthly = CalendarEntry(
        id: 'm',
        kind: CalendarEntryKind.job,
        title: 'Sebes',
        startsOn: _d(31, 1),
        recurrence: AgendaRecurrence.monthly,
        recurrenceUntil: _d(31, 3),
      );
      expect(nextCalendarOccurrence(monthly, _d(31, 1)), _d(28, 2));
      expect(nextCalendarOccurrence(monthly, _d(31, 3)), isNull);
    });

    test('D3: a pergunta muda com a ação; "seguintes" só depois do início', () {
      final scope = buildAgendaDetailScope(
        entry: _rosa,
        occurrence: _d(28),
        action: AgendaDetailScopeAction.cancel,
        now: _now,
      );
      expect(scope.title, 'Este trabalho repete-se');
      expect(scope.summary, 'Cancelar em que dias?');
      expect(scope.options.map((o) => o.label), [
        'Só este dia',
        'Este e os seguintes',
        'Todos',
      ]);
      expect(
        scope.options[1].subtitle,
        'De 28 out até 31 mar 2027. Os anteriores ficam.',
      );
      final first = buildAgendaDetailScope(
        entry: _rosa,
        occurrence: _d(7),
        action: AgendaDetailScopeAction.delete,
        now: _now,
      );
      expect(first.summary, 'Apagar em que dias?');
      expect(first.options, hasLength(2));
    });

    test('D6: o texto de apagar diz que dias e que ninguém é avisado', () {
      final one = agendaDeleteConfirm(
        entry: _rosa,
        exception: null,
        occurrence: _d(28),
        scope: AgendaSeriesScope.thisDay,
        now: _now,
      );
      expect(one.title, 'Apagar da agenda?');
      expect(
        one.message,
        '"Relva da D. Rosa", quarta 28 out, sai da agenda. '
        'Rosa Ferreira não recebe nenhum aviso.',
      );
      final following = agendaCancelConfirm(
        entry: _rosa,
        exception: null,
        occurrence: _d(28),
        scope: AgendaSeriesScope.following,
        now: _now,
      );
      expect(following.message, contains('de 28 out em diante'));
      expect(following.message, contains('riscado'));
    });
  });

  test('na Agenda, um cancelado fica riscado com "Cancelado"', () {
    final card = agendaEntryViewData(
      AgendaEntry(
        kind: AgendaEntryKind.external,
        sourceId: 'rosa',
        date: _d(28),
        seriesDate: _d(28),
        status: 'cancelled',
        startMinutes: _h(16, 30),
        title: 'Relva da D. Rosa',
      ),
      now: _now,
      isToday: true,
      current: false,
      serviceTypes: _types,
    );
    expect(card.pill, AgendaCardPill.cancelled);
    expect(card.done, isTrue);
    expect(card.canOpen, isTrue);
  });

  group('vista', () {
    Widget host(
      AgendaDetailViewData data, {
      List<String>? calls,
      String? banner,
    }) {
      final log = calls ?? <String>[];
      return MaterialApp(
        home: Scaffold(
          body: AgendaEntryDetailView(
            data: data,
            bannerMessage: banner,
            onUndoBanner: () => log.add('undo'),
            onBack: () => log.add('back'),
            onEdit: () => log.add('edit'),
            onDelete: () => log.add('delete'),
            onPrimary: (k) => log.add('primary:${k.name}'),
            onCancel: () => log.add('cancel'),
            onWhatsApp: () => log.add('whatsapp'),
            onOpenMap: () => log.add('map'),
            onViewDay: () => log.add('day'),
          ),
        ),
      );
    }

    testWidgets('D1/D2: secções, ações e menu com Apagar por último', (
      tester,
    ) async {
      final calls = <String>[];
      await tester.pumpWidget(
        host(_build(_rosa, entries: _agenda), calls: calls),
      );
      await tester.pumpAndSettle();

      expect(find.text('Relva da D. Rosa'), findsOneWidget);
      expect(find.text('Fora da app'), findsOneWidget);
      expect(find.text('Marcado'), findsOneWidget);
      expect(find.text('QUANDO'), findsOneWidget);
      expect(find.textContaining('Ligar'), findsNothing);

      await tester.tap(find.text('Ver o dia'));
      await tester.tap(find.text('Marcar como feito'));
      await tester.tap(find.text('Cancelar este trabalho'));
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('WhatsApp'),
        200,
        scrollable: list,
      );
      await tester.ensureVisible(find.text('WhatsApp'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('WhatsApp'));
      await tester.scrollUntilVisible(
        find.text('Abrir no mapa'),
        200,
        scrollable: list,
      );
      await tester.ensureVisible(find.text('Abrir no mapa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir no mapa'));
      await tester.scrollUntilVisible(
        find.text('25 € combinado'),
        200,
        scrollable: list,
      );
      expect(calls, ['day', 'primary:markDone', 'cancel', 'whatsapp', 'map']);
      await tester.scrollUntilVisible(
        find.text('Relva da D. Rosa'),
        -200,
        scrollable: list,
      );

      await tester.tap(find.byTooltip('Mais opções'));
      await tester.pumpAndSettle();
      final edit = tester.getTopLeft(find.text('Editar'));
      final delete = tester.getTopLeft(find.text('Apagar'));
      expect(delete.dy, greaterThan(edit.dy));
      await tester.tap(find.text('Apagar'));
      await tester.pumpAndSettle();
      expect(calls.last, 'delete');
    });

    testWidgets('D4: feito com a faixa "Desfazer"', (tester) async {
      final calls = <String>[];
      final data = _build(
        _rosa,
        exception: CalendarException(
          occurrenceDate: _d(28),
          action: 'status',
          status: 'done',
          statusAt: DateTime(2026, 10, 28, 17, 40),
        ),
      );
      await tester.pumpWidget(
        host(data, calls: calls, banner: 'Marcado como feito'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Feito'), findsOneWidget);
      expect(find.text('Cancelar este trabalho'), findsNothing);
      await tester.tap(find.text('Desfazer'));
      await tester.tap(find.text('Afinal não foi feito'));
      expect(calls, ['undo', 'primary:undoDone']);
    });

    testWidgets('D5: indisponibilidade com Apagar e Editar, sem menu', (
      tester,
    ) async {
      final calls = <String>[];
      await tester.pumpWidget(
        host(_build(_ferias, occurrence: _d(10, 11)), calls: calls),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Mais opções'), findsNothing);
      expect(find.text('Marcar como feito'), findsNothing);
      await tester.tap(find.text('Apagar'));
      await tester.tap(find.text('Editar'));
      expect(calls, ['delete', 'edit']);
    });

    testWidgets('D3: um toque numa opção escolhe logo', (tester) async {
      AgendaSeriesScope? chosen;
      var cancelled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgendaScopeSheet(
              data: buildAgendaDetailScope(
                entry: _rosa,
                occurrence: _d(28),
                action: AgendaDetailScopeAction.delete,
                now: _now,
              ),
              onConfirm: (s) => chosen = s,
              onCancel: () => cancelled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Este e os seguintes'));
      expect(chosen, AgendaSeriesScope.following);
      await tester.tap(find.text('Cancelar'));
      expect(cancelled, isTrue);
    });
  });
}
