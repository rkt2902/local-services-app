import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/core/utils/date_labels.dart';
import 'package:servicesapp/features/client/presentation/widgets/job_schedule_fields.dart';

void main() {
  group('weekdayDateLabel', () {
    final now = DateTime(2026, 10, 19);

    test('dia da semana e dia/mês no mesmo ano', () {
      expect(
          weekdayDateLabel(DateTime(2026, 10, 25), now: now), 'Domingo, 25/10');
      expect(
          weekdayDateLabel(DateTime(2026, 10, 24), now: now), 'Sábado, 24/10');
    });

    test('junta o ano quando é outro ano', () {
      expect(weekdayDateLabel(DateTime(2027, 1, 4), now: now),
          'Segunda, 04/01/2027');
    });
  });

  group('JobScheduleFields', () {
    Future<List<DateMode>> pump(
      WidgetTester tester, {
      required DateMode mode,
      DateTime? date,
      String? missingDateHint,
    }) async {
      final changes = <DateMode>[];
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: JobScheduleFields(
            dateMode: mode,
            onDateModeChanged: changes.add,
            date: date,
            onPickDate: () {},
            availabilityController: controller,
            missingDateHint: missingDateHint,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return changes;
    }

    testWidgets('data fixa mostra o campo de data e a dica sem data',
        (tester) async {
      await pump(tester,
          mode: DateMode.fixed, missingDateHint: 'Escolhe uma data.');
      expect(find.text('Data'), findsOneWidget);
      expect(find.text('Escolher data'), findsOneWidget);
      expect(find.text('Escolhe uma data.'), findsOneWidget);
    });

    testWidgets('disponibilidade mostra o texto livre com contador',
        (tester) async {
      await pump(tester, mode: DateMode.availability);
      expect(find.byType(TextField), findsOneWidget);
      expect(
          find.text('Diz por palavras tuas quando dá jeito'), findsOneWidget);
      expect(find.text('Data'), findsNothing);
    });

    testWidgets('tocar num modo avisa o ecrã', (tester) async {
      final changes = await pump(tester, mode: DateMode.flexible);
      expect(find.text('Combinas a data com o jardineiro.'), findsOneWidget);
      await tester.tap(find.text('Disponibilidade'));
      await tester.tap(find.text('Data fixa'));
      expect(changes, [DateMode.availability, DateMode.fixed]);
    });
  });
}
