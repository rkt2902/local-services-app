import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/widgets/app_motion.dart';
import 'package:servicesapp/features/agenda/application/agenda_entry_form.dart';
import 'package:servicesapp/features/agenda/data/agenda_entry_model.dart';
import 'package:servicesapp/features/agenda/presentation/agenda_entry_editor_presenter.dart';
import 'package:servicesapp/features/agenda/presentation/agenda_entry_editor_view_data.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_entry_editor_view.dart';
import 'package:servicesapp/features/worker/data/service_type_model.dart';

// Hoje é quarta 28 de outubro de 2026.
final _now = DateTime(2026, 10, 28, 10, 20);

DateTime _d(int day, [int month = 10]) => DateTime(2026, month, day);

int _h(int hour, [int minute = 0]) => hour * 60 + minute;

const _types = [
  ServiceType(
    id: 'relva',
    name: 'Corte de relva',
    slug: 'relva',
    icon: 'grass',
  ),
];

AgendaEntry _e(
  String id, {
  required DateTime date,
  int? start,
  int? end,
  AgendaEntryKind kind = AgendaEntryKind.appJob,
  String? title,
}) => AgendaEntry(
  kind: kind,
  sourceId: id,
  jobId: kind == AgendaEntryKind.block ? null : 'job-$id',
  date: date,
  seriesDate: date,
  status: 'confirmed',
  startMinutes: start,
  endMinutes: end,
  title: title,
  serviceTypeId: kind == AgendaEntryKind.appJob ? 'relva' : null,
  locationLabel: 'Rua A, Cascais',
  personName: 'Maria Santos',
  isTentative: kind == AgendaEntryKind.proposal,
);

final _entries = [
  _e('a', date: _d(28), start: _h(9), end: _h(11)),
  _e(
    'poda',
    date: _d(28),
    start: _h(14),
    end: _h(16, 15),
    kind: AgendaEntryKind.external,
    title: 'Poda',
  ),
  _e('ferias', date: _d(31), kind: AgendaEntryKind.block, title: 'Férias'),
];

AgendaEditorViewData _build(
  AgendaEntryForm form, {
  bool isEdit = false,
  List<AgendaEntry>? entries,
}) => buildAgendaEditor(
  form: form,
  isEdit: isEdit,
  entries: entries ?? _entries,
  serviceTypes: _types,
  now: _now,
);

final _work = AgendaEntryForm.create(_d(28)).copyWith(title: 'Relva');

void main() {
  group('presenter', () {
    test('F1: vazio, data já escolhida, botão cinzento com o motivo', () {
      final data = _build(AgendaEntryForm.create(_d(28)));
      expect(data.title, 'Adicionar à agenda');
      expect(data.showTypeSelector, isTrue);
      expect(data.canSave, isFalse);
      expect(data.saveHelper, 'Escreve um título para poder guardar.');
      expect(data.saveLabel, 'Guardar na agenda');
      expect(data.work.dateLabel, 'Hoje, quarta 28 out');
      expect(data.work.serviceLabel, isNull);
      expect(
        [for (final c in data.work.durationChoices) c.label],
        ['1 h', '2 h', '4 h', 'Dia todo', 'Vários dias', 'Outra'],
      );
      expect(data.work.timeSummary, 'Das 09:00 às 10:00');
    });

    test('F2: aviso leve quando há pouco intervalo', () {
      final form = _work.copyWith(
        startMinutes: _h(16, 30),
        serviceTypeId: 'relva',
      );
      final data = _build(form);
      expect(data.canSave, isTrue);
      expect(data.work.serviceLabel, 'Corte de relva');
      expect(data.work.warning!.tone, AgendaWarningTone.info);
      expect(data.work.warning!.message, 'Só 15 min depois de Poda, Cascais.');
      expect(data.work.warning!.actionLabel, 'Ver o dia');
    });

    test('F3: aviso forte e confirmação ao guardar', () {
      final form = _work.copyWith(
        startMinutes: _h(9, 30),
        durationMinutes: 120,
      );
      final data = _build(form);
      expect(data.work.warning!.tone, AgendaWarningTone.waiting);
      expect(
        data.work.warning!.message,
        'Coincide com Corte de relva, Cascais, 09:00 a 11:00.',
      );
      final dialog = agendaStrongConflict(
        form: form,
        entries: _entries,
        serviceTypes: _types,
        now: _now,
      )!;
      expect(dialog.title, 'Já tens um trabalho a esta hora');
      expect(dialog.entryStart, '09:00');
      expect(dialog.entryMeta, 'Cascais · Maria Santos');
      expect(
        dialog.summary,
        'O novo fica das 09:30 às 11:30. Cruzam-se 1 h 30.',
      );
      // Ao editar a própria entrada, não conta.
      expect(
        agendaStrongConflict(
          form: form,
          entries: _entries,
          serviceTypes: _types,
          now: _now,
          ignoreSourceId: 'a',
        ),
        isNull,
      );
    });

    test('dia indisponível e duração "Outra"', () {
      final form = _work.withDate(_d(31)).copyWith(durationMinutes: 90);
      final data = _build(form);
      expect(
        data.work.warning!.message,
        'Estás indisponível neste dia (Férias).',
      );
      final custom = data.work.durationChoices.last;
      expect(custom.label, '1 h 30');
      expect(custom.selected, isTrue);
    });

    test('F5: repetição semanal com resumo e "Sem fim"', () {
      final form = _work
          .withDate(_d(3, 11))
          .copyWith(
            startMinutes: _h(16, 30),
            recurrence: AgendaRecurrence.weekly,
          );
      var data = _build(form);
      expect(data.work.recurrence.showUntil, isTrue);
      expect(data.work.recurrence.noEnd, isTrue);
      expect(data.work.recurrence.summary, 'Todas as terças às 16:30, sem fim');
      data = _build(form.copyWith(recurrenceUntil: DateTime(2027, 3, 30)));
      expect(
        data.work.recurrence.summary,
        'Todas as terças às 16:30, até 30 mar 2027',
      );
    });

    test('F6: indisponível avisa dos trabalhos que ficam', () {
      final form = AgendaEntryForm.create(
        _d(28),
        type: AgendaFormType.unavailable,
      ).copyWith(reason: AgendaBlockReason.vacation);
      final data = _build(form);
      expect(data.saveLabel, 'Guardar');
      expect(
        [for (final r in data.unavailable.reasons) r.label],
        ['Férias', 'Folga', 'Consulta', 'Outro'],
      );
      expect(data.unavailable.reasons.first.selected, isTrue);
      expect(
        data.unavailable.warning!.message,
        'Já tens 2 trabalhos neste dia. Ficam na agenda; tu decides o que '
        'mudar.',
      );
    });

    test('F7: editar esconde o tipo e mostra Apagar', () {
      final data = _build(_work, isEdit: true);
      expect(data.title, 'Editar');
      expect(data.showTypeSelector, isFalse);
      expect(data.showDelete, isTrue);
      expect(data.saveLabel, 'Guardar alterações');
    });

    test('folha da série: "Só este dia" por omissão', () {
      final scope = buildAgendaScope(
        entryTitle: 'Rega da D. Rosa',
        recurrence: AgendaRecurrence.weekly,
        seriesStart: _d(6),
        occurrenceDate: _d(10, 11),
        recurrenceUntil: DateTime(2027, 3, 30),
        now: _now,
        forDelete: false,
      );
      expect(scope.title, 'Guardar a mudança em…');
      expect(scope.summary, 'Rega da D. Rosa repete todas as terças.');
      expect(
        [for (final o in scope.options) o.label],
        ['Só este dia', 'Este e os seguintes', 'Todos'],
      );
      expect(scope.options[0].selected, isTrue);
      expect(scope.options[0].subtitle, 'Terça, 10 nov');
      expect(scope.options[1].subtitle, 'De 10 nov até 30 mar 2027');
      expect(scope.options[2].subtitle, 'Todas as terças da série');

      final first = buildAgendaScope(
        entryTitle: 'Rega',
        recurrence: AgendaRecurrence.weekly,
        seriesStart: _d(6),
        occurrenceDate: _d(6),
        now: _now,
        forDelete: false,
        thisDayAllowed: false,
      );
      // No primeiro dia não há "seguintes"; sem "Só este dia", fica Todos.
      expect(first.options, hasLength(2));
      expect(first.options[0].enabled, isFalse);
      expect(first.options[1].selected, isTrue);
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

    Widget host(
      AgendaEditorViewData data, {
      AgendaEditorControllers? controllers,
      List<String>? calls,
      String? success,
    }) {
      final log = calls ?? <String>[];
      return MaterialApp(
        home: Scaffold(
          body: AgendaEntryEditorView(
            data: data,
            controllers: controllers ?? AgendaEditorControllers(),
            successMessage: success,
            onBack: () => log.add('back'),
            onTypeChanged: (t) => log.add('type:${t.name}'),
            onPickService: () => log.add('service'),
            onAddressSelected: (_) => log.add('address'),
            onPickDate: () => log.add('date'),
            onPickStartTime: () => log.add('start'),
            onAllDayChanged: (v) => log.add('allDay:$v'),
            onDurationSelected: (d) => log.add('duration:${d.option.name}'),
            onPickEndDate: () => log.add('end'),
            onOpenDayPreview: () => log.add('preview'),
            onRecurrenceSelected: (r) => log.add('repeat:$r'),
            onPickRecurrenceUntil: () => log.add('until'),
            onRecurrenceNoEnd: () => log.add('noEnd'),
            onReasonSelected: (r) => log.add('reason:${r.name}'),
            onPickEndTime: () => log.add('endTime'),
            onSave: () => log.add('save'),
            onDelete: () => log.add('delete'),
          ),
        ),
      );
    }

    testWidgets('F1: guardar desligado sem título; trocar de tipo', (
      tester,
    ) async {
      final calls = <String>[];
      await tester.pumpWidget(
        host(_build(AgendaEntryForm.create(_d(28))), calls: calls),
      );
      await tester.pumpAndSettle();

      expect(find.text('Adicionar à agenda'), findsOneWidget);
      expect(
        find.text('Escreve um título para poder guardar.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Guardar na agenda'));
      expect(calls, isNot(contains('save')));

      await tester.tap(find.text('Indisponível'));
      expect(calls, contains('type:unavailable'));
      expect(find.text('Apagar'), findsNothing);
    });

    testWidgets('F2/F3: teclados, nota com "Ver o dia" e guardar', (
      tester,
    ) async {
      final calls = <String>[];
      await tester.pumpWidget(
        host(_build(_work.copyWith(startMinutes: _h(9, 30))), calls: calls),
      );
      await tester.pumpAndSettle();

      TextField field(String label) => tester.widget<TextField>(
        find.descendant(
          of: find.ancestor(
            of: find.text(label),
            matching: find.byType(TextFormField),
          ),
          matching: find.byType(TextField),
        ),
      );
      expect(field('Telefone').keyboardType, TextInputType.phone);
      expect(
        field('Valor combinado').keyboardType,
        const TextInputType.numberWithOptions(decimal: true),
      );
      expect(field('Notas').keyboardType, TextInputType.multiline);
      expect(find.text('Ligar'), findsNothing);

      await tester.ensureVisible(find.text('Ver o dia'));
      await tester.tap(find.text('Ver o dia'));
      expect(calls, contains('preview'));

      await tester.ensureVisible(find.text('4 h'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4 h'));
      expect(calls, contains('duration:preset'));

      await tester.tap(find.text('Guardar na agenda'));
      expect(calls, contains('save'));
    });

    testWidgets('F5: repetir mostra "Até" e "Sem fim"', (tester) async {
      final calls = <String>[];
      final form = _work.copyWith(recurrence: AgendaRecurrence.weekly);
      await tester.pumpWidget(host(_build(form), calls: calls));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sem fim').last);
      await tester.tap(find.widgetWithText(InkWell, 'Sem fim').last);
      expect(calls, contains('noEnd'));
      expect(find.text('Todas as quartas às 09:00, sem fim'), findsOneWidget);
    });

    testWidgets('F6: motivos e horas quando não é o dia todo', (tester) async {
      final calls = <String>[];
      final form = AgendaEntryForm.create(
        _d(28),
        type: AgendaFormType.unavailable,
      );
      await tester.pumpWidget(host(_build(form), calls: calls));
      await tester.pumpAndSettle();
      expect(find.text('Hora de fim'), findsNothing);
      await tester.tap(find.text('Folga'));
      expect(calls, contains('reason:dayOff'));

      await tester.pumpWidget(
        host(_build(form.copyWith(allDay: false)), calls: calls),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hora de fim'), findsOneWidget);
      await tester.ensureVisible(find.text('13:00'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('13:00'));
      expect(calls, contains('endTime'));
    });

    testWidgets('F7: editar sem tipo, com Apagar', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(host(_build(_work, isEdit: true), calls: calls));
      await tester.pumpAndSettle();
      expect(find.text('Trabalho'), findsNothing);
      await tester.tap(find.text('Apagar'));
      expect(calls, contains('delete'));
    });

    testWidgets('F8A: visto verde por cima', (tester) async {
      await tester.pumpWidget(
        host(_build(_work), success: 'Guardado na agenda'),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(AppSuccessFeedback), findsOneWidget);
      expect(find.text('Guardado na agenda'), findsOneWidget);
    });

    testWidgets('F4: "Mudar a hora" devolve falso, guardar devolve verdade', (
      tester,
    ) async {
      final dialog = agendaStrongConflict(
        form: _work.copyWith(startMinutes: _h(9, 30)),
        entries: _entries,
        serviceTypes: _types,
        now: _now,
      )!;
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await AgendaConflictDialog.show(context, dialog),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Corte de relva'), findsOneWidget);
      await tester.tap(find.text('Mudar a hora'));
      await tester.pumpAndSettle();
      expect(result, isFalse);

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar mesmo assim'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('folha da série devolve a escolha', (tester) async {
      AgendaSeriesScope? chosen;
      final data = buildAgendaScope(
        entryTitle: 'Rega',
        recurrence: AgendaRecurrence.weekly,
        seriesStart: _d(6),
        occurrenceDate: _d(10, 11),
        now: _now,
        forDelete: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgendaScopeSheet(data: data, onConfirm: (s) => chosen = s),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Este e os seguintes'));
      await tester.pump();
      await tester.tap(find.text('Guardar'));
      expect(chosen, AgendaSeriesScope.following);
    });
  });
}
