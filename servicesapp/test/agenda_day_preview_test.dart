import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/features/agenda/application/agenda_providers.dart';
import 'package:servicesapp/features/agenda/data/agenda_entry_model.dart';
import 'package:servicesapp/features/agenda/presentation/agenda_day_preview.dart';
import 'package:servicesapp/features/agenda/presentation/agenda_day_preview_presenter.dart';
import 'package:servicesapp/features/agenda/presentation/agenda_day_preview_view_data.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_day_preview_sheet.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_entry_card.dart';
import 'package:servicesapp/features/worker/application/worker_providers.dart';
import 'package:servicesapp/features/worker/data/service_type_model.dart';

// Hoje é quarta 28 de outubro de 2026; o formulário está em sexta, 30.
final _now = DateTime(2026, 10, 28, 10, 20);

DateTime _d(int day, [int month = 10]) => DateTime(2026, month, day);

int _h(int hour, [int minute = 0]) => hour * 60 + minute;

const _types = [
  ServiceType(
    id: 'canteiros',
    name: 'Limpeza de canteiros',
    slug: 'canteiros',
    icon: 'grass',
  ),
];

AgendaEntry _job(String id, int start, int end, {DateTime? day}) => AgendaEntry(
  kind: AgendaEntryKind.appJob,
  sourceId: id,
  jobId: id,
  date: day ?? _d(30),
  seriesDate: day ?? _d(30),
  status: 'confirmed',
  startMinutes: start,
  endMinutes: end,
  serviceTypeId: 'canteiros',
  locationLabel: 'Rua A 1, Cascais',
);

AgendaEntry _external(String id, int start, int end, {DateTime? day}) =>
    AgendaEntry(
      kind: AgendaEntryKind.external,
      sourceId: id,
      date: day ?? _d(30),
      seriesDate: day ?? _d(30),
      status: 'scheduled',
      startMinutes: start,
      endMinutes: end,
      title: 'Relva da D. Rosa',
      locationLabel: 'Oeiras',
    );

AgendaEntry _proposal(String id, int start, int end) => AgendaEntry(
  kind: AgendaEntryKind.proposal,
  sourceId: id,
  date: _d(30),
  seriesDate: _d(30),
  status: 'pending',
  isTentative: true,
  startMinutes: start,
  endMinutes: end,
  serviceTypeId: 'canteiros',
  locationLabel: 'Estoril',
);

AgendaDayPreviewGhost _ghost(int start, int duration, {String? ignore}) =>
    AgendaDayPreviewGhost(
      date: _d(30),
      label: 'A tua proposta',
      startMinutes: start,
      durationMinutes: duration,
      slotKind: AgendaEntryKind.proposal,
      ignoreSourceId: ignore,
    );

AgendaDayPreviewViewData _build(
  List<AgendaEntry> entries, {
  DateTime? day,
  AgendaDayPreviewGhost? ghost,
}) => buildAgendaDayPreview(
  day: day ?? _d(30),
  entries: entries,
  ghost: ghost,
  serviceTypes: _types,
  now: _now,
);

List<String> _labels(List<AgendaPreviewItem> items) => [
  for (final item in items)
    switch (item) {
      AgendaPreviewSectionItem(:final label) => 'section:$label',
      AgendaPreviewFreeItem(:final label) => 'free:$label',
      AgendaPreviewGhostItem(:final label, :final conflict) =>
        'ghost:$label${conflict ? ' !' : ''}',
      AgendaPreviewEntryItem(:final entry, :final conflict) =>
        'entry:${entry.title}${conflict ? ' !' : ''}',
      AgendaPreviewGroupItem(:final label, :final children) =>
        'group:$label[${_labels(children).join(', ')}]',
    },
];

void main() {
  group('buildAgendaDayPreview', () {
    test('V1: choca com um trabalho, agrupado com a faixa âmbar', () {
      final data = _build([
        _job('canteiros', _h(10), _h(12)),
        _external('rosa', _h(15), _h(16)),
      ], ghost: _ghost(_h(9), 120));

      expect(data.dayLabel, 'Sexta, 30 out');
      expect(data.hasGhost, isTrue);
      expect(data.assessment, AgendaPreviewAssessment.conflict);
      expect(
        data.assessmentLabel,
        'Choca 1 hora com Limpeza de canteiros (10:00 a 12:00).',
      );
      expect(_labels(data.items), [
        'free:Livre até às 09:00',
        'group:Choca das 10:00 às 11:00['
            'ghost:A tua proposta, 09:00 a 11:00 !, '
            'entry:Limpeza de canteiros]',
        'free:Livre das 12:00 às 15:00',
        'entry:Relva da D. Rosa',
        'free:Livre a partir das 16:00',
      ]);
      expect(data.empty, isNull);
    });

    test('V2: cabe, com 1 hora antes e depois', () {
      final data = _build([
        _external('rosa', _h(7), _h(8)),
        _job('canteiros', _h(12), _h(14)),
        _proposal('estoril', _h(16), _h(17)),
      ], ghost: _ghost(_h(9), 120));

      expect(data.assessment, AgendaPreviewAssessment.fits);
      expect(data.assessmentLabel, 'Cabe. Fica 1 hora livre antes e depois.');
      expect(_labels(data.items), [
        'free:Livre até às 07:00',
        'entry:Relva da D. Rosa',
        'free:Livre das 08:00 às 09:00',
        'ghost:A tua proposta, 09:00 a 11:00',
        'free:Livre das 11:00 às 12:00',
        'entry:Limpeza de canteiros',
        'free:Livre das 14:00 às 16:00',
        'entry:Limpeza de canteiros',
        'free:Livre a partir das 17:00',
      ]);
    });

    test('V3: dia vazio, com livre antes e depois do fantasma', () {
      final data = _build(const [], ghost: _ghost(_h(9), 120));
      expect(data.assessment, AgendaPreviewAssessment.fits);
      expect(data.assessmentLabel, 'Cabe. Não tens mais nada neste dia.');
      expect(_labels(data.items), [
        'free:Livre até às 09:00',
        'ghost:A tua proposta, 09:00 a 11:00',
        'free:Livre a partir das 11:00',
      ]);
      expect(data.empty?.title, 'Nada mais neste dia');
    });

    test('noutro dia não há fantasma nem frase', () {
      final data = _build(
        [_job('canteiros', _h(10), _h(12), day: _d(29))],
        day: _d(29),
        ghost: _ghost(_h(9), 120),
      );
      expect(data.hasGhost, isFalse);
      expect(data.assessment, AgendaPreviewAssessment.none);
      expect(data.dayLabel, 'Amanhã, quinta 29 out');
      expect(_labels(data.items), [
        'free:Livre até às 10:00',
        'entry:Limpeza de canteiros',
        'free:Livre a partir das 12:00',
      ]);

      final empty = _build(const [], day: _d(31), ghost: _ghost(_h(9), 120));
      expect(empty.empty?.title, 'Nada neste dia');
      expect(empty.empty?.body, 'O dia está todo livre.');
    });

    test('a própria entrada, ao editar, não aparece nem conta', () {
      final data = _build([
        _external('rosa', _h(9), _h(10)),
      ], ghost: _ghost(_h(9), 60, ignore: 'rosa'));
      expect(data.assessment, AgendaPreviewAssessment.fits);
      expect(_labels(data.items), [
        'free:Livre até às 09:00',
        'ghost:A tua proposta, 09:00 a 10:00',
        'free:Livre a partir das 10:00',
      ]);
    });

    test('proposta enviada à mesma hora: neutro, sem grupo', () {
      final data = _build([
        _proposal('estoril', _h(10), _h(12)),
      ], ghost: _ghost(_h(9), 120));
      expect(data.assessment, AgendaPreviewAssessment.tentative);
      expect(
        data.assessmentLabel,
        'Coincide com uma proposta enviada: Limpeza de canteiros '
        '(10:00 a 12:00).',
      );
      expect(data.items.whereType<AgendaPreviewGroupItem>(), isEmpty);
    });

    test('pouco intervalo e mesmo dia sem hora: info', () {
      final tight = _build([
        _job('canteiros', _h(11, 15), _h(12)),
      ], ghost: _ghost(_h(9), 120));
      expect(tight.assessment, AgendaPreviewAssessment.tight);
      expect(
        tight.assessmentLabel,
        'Cabe, mas fica só 15 min até Limpeza de canteiros (11:15 a 12:00).',
      );

      final untimed = _build(const [], ghost: _ghost(_h(9), 120));
      expect(untimed.assessment, AgendaPreviewAssessment.fits);

      final noTime = _build([
        AgendaEntry(
          kind: AgendaEntryKind.appJob,
          sourceId: 'x',
          date: _d(30),
          seriesDate: _d(30),
          status: 'confirmed',
          serviceTypeId: 'canteiros',
        ),
      ], ghost: _ghost(_h(9), 120));
      expect(
        noTime.assessmentLabel,
        'Já tens Limpeza de canteiros neste dia, sem hora marcada.',
      );
    });

    test('indisponível no dia todo: choca, com a faixa na entrada', () {
      final data = _build([
        AgendaEntry(
          kind: AgendaEntryKind.block,
          sourceId: 'ferias',
          date: _d(30),
          seriesDate: _d(30),
          status: 'scheduled',
          title: 'Férias',
        ),
      ], ghost: _ghost(_h(9), 120));
      expect(data.assessment, AgendaPreviewAssessment.conflict);
      expect(data.assessmentLabel, 'Choca com uma indisponibilidade: Férias.');
      expect(_labels(data.items), [
        'section:Sem hora marcada',
        'entry:Férias !',
        'section:Por hora',
        'free:Livre até às 09:00',
        'ghost:A tua proposta, 09:00 a 11:00 !',
        'free:Livre a partir das 11:00',
      ]);
    });

    test('vários dias: o fantasma aparece em todos, dia todo', () {
      final ghost = AgendaDayPreviewGhost(
        date: _d(30),
        lastDate: _d(1, 11),
        label: 'O teu trabalho',
        wholeDay: true,
      );
      final data = _build(
        [_external('rosa', _h(15), _h(16), day: _d(31))],
        day: _d(31),
        ghost: ghost,
      );
      expect(data.hasGhost, isTrue);
      expect(
        data.assessmentLabel,
        'Choca com Relva da D. Rosa (15:00 a 16:00).',
      );
      expect(_labels(data.items).take(2), [
        'section:Sem hora marcada',
        'ghost:O teu trabalho, dia todo !',
      ]);
      expect(_build(const [], day: _d(2, 11), ghost: ghost).hasGhost, isFalse);
    });

    test('agendaLongDuration', () {
      expect(agendaLongDuration(60), '1 hora');
      expect(agendaLongDuration(120), '2 horas');
      expect(agendaLongDuration(90), '1 h 30');
      expect(agendaLongDuration(45), '45 min');
    });
  });

  group('AgendaDayPreviewSheet', () {
    Widget host(Widget sheet) => MaterialApp(
      home: Scaffold(
        body: Align(alignment: Alignment.bottomCenter, child: sheet),
      ),
    );

    testWidgets('V1: frase, fantasma, grupo e Fechar; nada se toca', (
      tester,
    ) async {
      final calls = <String>[];
      final data = _build([
        _job('canteiros', _h(10), _h(12)),
        _external('rosa', _h(15), _h(16)),
      ], ghost: _ghost(_h(9), 120));
      await tester.pumpWidget(
        host(
          AgendaDayPreviewSheet(
            dayLabel: data.dayLabel,
            data: data,
            onPreviousDay: () => calls.add('prev'),
            onNextDay: () => calls.add('next'),
            onClose: () => calls.add('close'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sexta, 30 out'), findsOneWidget);
      expect(
        find.text('Choca 1 hora com Limpeza de canteiros (10:00 a 12:00).'),
        findsOneWidget,
      );
      expect(find.text('A tua proposta, 09:00 a 11:00'), findsOneWidget);
      expect(find.text('Choca das 10:00 às 11:00'), findsOneWidget);
      expect(find.text('Relva da D. Rosa'), findsOneWidget);
      expect(find.text('Guardar'), findsNothing);
      expect(find.text('Editar'), findsNothing);
      expect(
        tester
            .widgetList<AgendaWeekEntryRow>(find.byType(AgendaWeekEntryRow))
            .every((row) => row.onTap == null),
        isTrue,
      );

      await tester.tap(find.byTooltip('Dia anterior'));
      await tester.tap(find.byTooltip('Dia seguinte'));
      await tester.fling(
        find.text('A tua proposta, 09:00 a 11:00'),
        const Offset(-300, 0),
        1000,
      );
      await tester.fling(
        find.text('A tua proposta, 09:00 a 11:00'),
        const Offset(300, 0),
        1000,
      );
      await tester.tap(find.text('Fechar'));
      expect(calls, ['prev', 'next', 'next', 'prev', 'close']);
    });

    testWidgets('V3: dia vazio e esqueleto / erro', (tester) async {
      final data = _build(const [], ghost: _ghost(_h(9), 120));
      var retried = false;
      Widget sheet({AgendaDayPreviewViewData? d, String? error}) => host(
        AgendaDayPreviewSheet(
          dayLabel: 'Sexta, 30 out',
          data: d,
          errorMessage: error,
          onRetry: () => retried = true,
          onPreviousDay: () {},
          onNextDay: () {},
          onClose: () {},
        ),
      );

      await tester.pumpWidget(sheet(d: data));
      await tester.pumpAndSettle();
      expect(find.text('Cabe. Não tens mais nada neste dia.'), findsOneWidget);
      expect(find.text('Nada mais neste dia'), findsOneWidget);
      expect(find.text('Livre a partir das 11:00'), findsOneWidget);

      await tester.pumpWidget(sheet());
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.bySemanticsLabel('A carregar'), findsWidgets);

      await tester.pumpWidget(sheet(error: 'Sem rede.'));
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível carregar este dia'), findsOneWidget);
      await tester.tap(find.text('Tentar de novo'));
      expect(retried, isTrue);
    });
  });

  group('showAgendaDayPreview', () {
    testWidgets(
      'mudar de dia não mexe no formulário; o fantasma volta ao dia dele',
      (tester) async {
        final entries = [
          _job('canteiros', _h(10), _h(12)),
          _job('outro', _h(14), _h(15), day: _d(29)),
        ];
        final controller = TextEditingController(text: 'Relva grande');
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              agendaRangeProvider.overrideWith((ref, range) async => entries),
              serviceTypesProvider.overrideWith((ref) async => _types),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => Column(
                    children: [
                      TextField(controller: controller),
                      TextButton(
                        onPressed: () => showAgendaDayPreview(
                          context,
                          day: _d(30),
                          ghost: _ghost(_h(9), 120),
                        ),
                        child: const Text('Ver o dia'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Ver o dia'));
        await tester.pumpAndSettle();
        expect(find.text('A tua proposta, 09:00 a 11:00'), findsOneWidget);

        await tester.tap(find.byTooltip('Dia anterior'));
        await tester.pumpAndSettle();
        expect(find.text('A tua proposta, 09:00 a 11:00'), findsNothing);
        expect(find.text('Livre a partir das 15:00'), findsOneWidget);

        await tester.tap(find.byTooltip('Dia seguinte'));
        await tester.pumpAndSettle();
        expect(find.text('A tua proposta, 09:00 a 11:00'), findsOneWidget);

        // Tocar fora fecha, como o botão.
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();
        expect(find.byType(AgendaDayPreviewSheet), findsNothing);
        expect(controller.text, 'Relva grande');
        expect(find.text('Relva grande'), findsOneWidget);
      },
    );
  });
}
