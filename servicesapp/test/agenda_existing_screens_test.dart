import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/widgets/app_bottom_navigation.dart';
import 'package:servicesapp/features/agenda/presentation/agenda_entry_editor_view_data.dart';
import 'package:servicesapp/features/agenda/presentation/agenda_legend_sheet.dart';
import 'package:servicesapp/features/agenda/presentation/agenda_slot_check.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_entry_editor_view.dart';
import 'package:servicesapp/features/agenda/presentation/widgets/agenda_intro_card.dart';
import 'package:servicesapp/features/jobs/presentation/widgets/reschedule_dialog.dart';

/// Primeira abertura (A8G) e as mudanças nos ecrãs que já existiam (A10).

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('cartão da primeira abertura: três pontos e as três ações', (
    tester,
  ) async {
    final taps = <String>[];
    await tester.pumpWidget(
      _app(
        AgendaIntroCard(
          onDismiss: () => taps.add('dismiss'),
          onAddFirstWork: () => taps.add('add'),
          onOpenColors: () => taps.add('colors'),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('A tua agenda'), findsOneWidget);
    expect(
      find.text('Os trabalhos da app aparecem aqui sozinhos'),
      findsOneWidget,
    );
    await tester.tap(find.text('Adicionar o primeiro trabalho'));
    await tester.tap(find.text('O que significam as cores?'));
    await tester.tap(find.text('Agora não'));
    expect(taps, ['add', 'colors', 'dismiss']);
  });

  testWidgets('folha das cores abre e fecha com "Percebi"', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAgendaLegendSheet(context),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('O que significam as cores?'), findsOneWidget);
    await tester.tap(find.text('Percebi'));
    await tester.pumpAndSettle();
    expect(find.text('O que significam as cores?'), findsNothing);
  });

  testWidgets('nota "Estás livre" (verde) com "Ver o dia"', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      _app(
        AgendaInlineWarning(
          data: const AgendaInlineWarningViewData(
            tone: AgendaWarningTone.success,
            message: 'Estás livre neste horário',
            actionLabel: 'Ver o dia',
          ),
          onAction: () => opened = true,
        ),
      ),
    );
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    await tester.tap(find.text('Ver o dia'));
    expect(opened, isTrue);
  });

  testWidgets('botão central passa a ✕ com a folha aberta (M4)', (
    tester,
  ) async {
    Widget nav(bool active) => MaterialApp(
      home: Scaffold(
        bottomNavigationBar: AppBottomNavigation(
          items: [
            for (final l in ['A', 'B', 'C', 'D'])
              AppBottomNavigationItem(
                label: l,
                icon: Icons.circle_outlined,
                selectedIcon: Icons.circle,
              ),
          ],
          selectedIndex: 0,
          onItemSelected: (_) {},
          onCentralActionPressed: () {},
          centralActionActive: active,
        ),
      ),
    );
    await tester.pumpWidget(nav(false));
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    await tester.pumpWidget(nav(true));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
  });

  testWidgets('remarcar com a Agenda: "Era: …" e a nota da nova hora (M3)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => RescheduleDialog.show(
                context,
                agenda: RescheduleAgenda(
                  previousLabel: 'Era: quarta, 28 out · 09:00',
                  check: (_, _) async => const AgendaSlotCheck(
                    note: AgendaInlineWarningViewData(
                      tone: AgendaWarningTone.success,
                      message: 'Estás livre neste dia',
                      actionLabel: 'Ver o dia',
                    ),
                  ),
                  onViewDay: (_, _) {},
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Era: quarta, 28 out · 09:00'), findsOneWidget);
    expect(find.text('Estás livre neste dia'), findsNothing);
  });
}
