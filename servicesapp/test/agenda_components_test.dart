import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_controls.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_entry_card.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_legend.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_list_rows.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_overlap.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_skeleton.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SizedBox(width: 358, child: child),
    ),
  ),
);

void main() {
  testWidgets('cartão completo mostra hora, título, etiqueta e ações', (
    tester,
  ) async {
    var started = 0;
    var opened = 0;
    await tester.pumpWidget(
      _wrap(
        AgendaEntryCard(
          data: AgendaEntryCardData(
            kind: AgendaCardKind.app,
            title: 'Corte de relva',
            serviceIcon: Icons.grass_outlined,
            startLabel: '09:00',
            endLabel: '11:00',
            subtitle: 'Cascais · Maria Santos',
            amountLabel: '≈ 60 €',
            pill: AgendaCardPill.scheduled,
            onTap: () => opened++,
            actions: [
              AgendaCardAction(
                label: 'Iniciar',
                icon: Icons.play_arrow_rounded,
                primary: true,
                onPressed: () => started++,
              ),
              AgendaCardAction(
                label: 'WhatsApp',
                icon: Icons.chat_outlined,
                onPressed: () {},
              ),
              AgendaCardAction(
                label: 'Mapa',
                icon: Icons.map_outlined,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('09:00'), findsOneWidget);
    expect(find.text('11:00'), findsOneWidget);
    expect(find.text('Marcado'), findsOneWidget);
    expect(find.text('≈ 60 €'), findsOneWidget);
    await tester.tap(find.text('Iniciar'));
    await tester.tap(find.text('Corte de relva'));
    expect(started, 1);
    expect(opened, 1);
  });

  testWidgets('concluído fica atenuado e sem botões', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AgendaEntryCard(
          data: AgendaEntryCardData(
            kind: AgendaCardKind.app,
            title: 'Corte de relva',
            serviceIcon: Icons.grass_outlined,
            startLabel: '09:00',
            pill: AgendaCardPill.done,
            done: true,
            actions: [
              AgendaCardAction(
                label: 'Mapa',
                icon: Icons.map_outlined,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Mapa'), findsNothing);
    expect(find.byType(Opacity), findsWidgets);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });

  testWidgets('variantes: vários dias, hora a combinar, dia todo, mudado', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const Column(
          children: [
            AgendaEntryCard(
              data: AgendaEntryCardData(
                kind: AgendaCardKind.app,
                title: 'Limpeza de terreno',
                serviceIcon: Icons.landscape_outlined,
                dayIndex: 2,
                dayCount: 3,
                pill: AgendaCardPill.inProgress,
                detailLabel: '27 a 29 out · 08:00 a 17:00',
              ),
            ),
            AgendaEntryCard(
              data: AgendaEntryCardData(
                kind: AgendaCardKind.app,
                title: 'Manutenção de jardim',
                serviceIcon: Icons.yard_outlined,
                timeToArrange: true,
              ),
            ),
            AgendaEntryCard(
              data: AgendaEntryCardData(
                kind: AgendaCardKind.block,
                title: 'Folga',
                serviceIcon: Icons.event_busy_outlined,
                pill: AgendaCardPill.block,
              ),
            ),
            AgendaEntryCard(
              data: AgendaEntryCardData(
                kind: AgendaCardKind.external,
                title: 'Rega',
                serviceIcon: Icons.water_drop_outlined,
                startLabel: '10:00',
                repeats: true,
                changedLabel: 'Mudado só este dia · era às 08:00',
              ),
            ),
          ],
        ),
      ),
    );

    expect(find.text('Dia 2'), findsOneWidget);
    expect(find.text('de 3'), findsOneWidget);
    expect(find.byType(AgendaDayProgress), findsOneWidget);
    expect(find.text('Hora a\ncombinar'), findsOneWidget);
    expect(find.text('Dia todo'), findsOneWidget);
    expect(find.text('Indisponível'), findsOneWidget);
    expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
    expect(find.text('Mudado só este dia · era às 08:00'), findsOneWidget);
  });

  testWidgets('linha compacta corta o texto e mostra um marcador', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const Column(
          children: [
            AgendaEntryCompactRow(
              kind: AgendaCardKind.proposal,
              title: 'Limpeza de terreno com um nome muito comprido',
              startLabel: '15:00',
              zone: 'Mafra',
              marker: AgendaCompactMarker.proposal,
            ),
            AgendaEntryCompactRow(
              kind: AgendaCardKind.external,
              title: 'Rega',
              startLabel: '08:00',
              zone: 'Oeiras',
              marker: AgendaCompactMarker.external,
            ),
          ],
        ),
      ),
    );
    expect(find.text('15:00'), findsOneWidget);
    expect(find.text('Fora'), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nota de sobreposição e chip abrem o dia', (tester) async {
    var viewed = 0;
    await tester.pumpWidget(
      _wrap(
        Column(
          children: [
            AgendaOverlapNote(
              level: AgendaNoteLevel.strong,
              highlight: 'Coincide com Corte de relva',
              message: ', Cascais, 09:00 a 11:00',
              onViewDay: () => viewed++,
            ),
            AgendaAvailabilityChip(
              availability: AgendaAvailability.free,
              label: 'Estás livre',
              onPressed: () => viewed++,
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Ver o dia'));
    await tester.tap(find.text('Estás livre'));
    expect(viewed, 2);
  });

  testWidgets('grupo de sobreposição, linhas da lista e legenda', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const Column(
          children: [
            AgendaOverlapStack(
              label: 'Coincidem das 09:30 às 11:00',
              children: [SizedBox(height: 40), SizedBox(height: 40)],
            ),
            AgendaFreeTimeRow(label: 'Livre das 11:30 às 14:00'),
            AgendaFreeTimeRow(label: 'Só 15 min até ao próximo', short: true),
            AgendaNowLine(timeLabel: '11:42'),
            AgendaDayHeader(
              dayLabel: 'Segunda, 27 out',
              isToday: true,
              countLabel: '2 trabalhos',
            ),
            AgendaDayHeader(
              dayLabel: 'Terça, 28 out',
              countLabel: '3 trabalhos',
              hasOverlap: true,
            ),
            AgendaDayHeader(dayLabel: 'Quarta, 29 out'),
            AgendaDayHeader(dayLabel: 'Quinta, 30 out', blockLabel: 'Folga'),
            AgendaLegendSheet(),
            AgendaLegendInline(),
            AgendaEntrySkeleton(),
            AgendaEntrySkeleton(compact: true),
          ],
        ),
      ),
    );
    expect(find.text('Coincidem das 09:30 às 11:00'), findsOneWidget);
    expect(find.text('HOJE'), findsOneWidget);
    expect(find.text('Livre'), findsOneWidget);
    expect(find.text('O que significam as cores?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tabs, seletor, botão Hoje e interruptor', (tester) async {
    var tab = -1;
    AgendaRange? range;
    bool? show;
    var today = 0;
    await tester.pumpWidget(
      _wrap(
        Column(
          children: [
            AgendaTabs(
              items: const [
                AgendaTabItem(label: 'Agenda'),
                AgendaTabItem(label: 'Propostas', count: 4),
                AgendaTabItem(label: 'Histórico'),
              ],
              selectedIndex: 0,
              onSelected: (i) => tab = i,
            ),
            AgendaRangeSelector(
              selected: AgendaRange.day,
              onSelected: (r) => range = r,
            ),
            AgendaTodayButton(onPressed: () => today++),
            const AgendaTodayButton(onPressed: null),
            AgendaPeriodNav(
              label: 'Segunda, 27 out',
              onPrevious: () {},
              onNext: () {},
            ),
            AgendaProposalsToggle(value: true, onChanged: (v) => show = v),
          ],
        ),
      ),
    );

    expect(find.text('4'), findsOneWidget);
    await tester.tap(find.text('Propostas'));
    await tester.tap(find.text('Semana'));
    await tester.tap(find.text('Mostrar propostas'));
    await tester.tap(find.byType(AgendaTodayButton).first);
    expect(tab, 1);
    expect(range, AgendaRange.week);
    expect(show, isFalse);
    expect(today, 1);
  });
}
