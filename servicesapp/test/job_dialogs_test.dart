import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/widgets/app_time_picker.dart';
import 'package:servicesapp/features/worker/presentation/widgets/report_problem_dialog.dart';
import 'package:servicesapp/features/jobs/data/cancel_reasons.dart';
import 'package:servicesapp/features/jobs/presentation/widgets/cancel_job_dialog.dart';
import 'package:servicesapp/features/jobs/presentation/widgets/reschedule_dialog.dart';

Future<void> _open(
  WidgetTester tester,
  Future<Object?> Function(BuildContext) show,
  void Function(Object?) onResult,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => onResult(await show(context)),
          child: const Text('abrir'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

FilledButton _button(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(
      find.ancestor(of: find.text(label), matching: find.byType(FilledButton)),
    );

void main() {
  testWidgets('cancelar só confirma depois de escolher a razão', (
    tester,
  ) async {
    Object? result;
    await _open(
      tester,
      (c) => CancelJobDialog.show(c, isClient: false),
      (r) => result = r,
    );

    expect(_button(tester, 'Cancelar pedido').onPressed, isNull);

    await tester.tap(find.text(CancelReason.label(CancelReason.personalIssue)));
    await tester.pump();
    expect(_button(tester, 'Cancelar pedido').onPressed, isNotNull);

    await tester.tap(find.text('Cancelar pedido').last);
    await tester.pumpAndSettle();
    expect(result, {
      'reason': CancelReason.personalIssue,
      'reasonDetail': null,
    });
  });

  testWidgets('remarcação fica desativada sem data', (tester) async {
    await _open(tester, RescheduleDialog.show, (_) {});

    expect(_button(tester, 'Enviar proposta').onPressed, isNull);
    expect(find.text('Voltar'), findsOneWidget);
  });

  testWidgets('reportar problema pede 10 caracteres antes de enviar', (
    tester,
  ) async {
    Object? result;
    await _open(tester, ReportProblemDialog.show, (r) => result = r);

    await tester.enterText(find.byType(TextField), 'curto');
    await tester.tap(find.text('Enviar'));
    await tester.pump();
    expect(
      find.text('Descreve o problema (mínimo 10 caracteres).'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'O portão estava fechado');
    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();
    expect(result, 'O portão estava fechado');
  });

  testWidgets('seletor de hora em português e em 24h', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pt', 'PT'),
        supportedLocales: const [Locale('pt', 'PT')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppTimePicker(
              context: context,
              initialTime: const TimeOfDay(hour: 14, minute: 0),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Select time'), findsNothing);
    expect(find.text('AM'), findsNothing);
    expect(find.text('14'), findsWidgets);
  });
}
