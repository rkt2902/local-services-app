import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/theme/app_status_color.dart';
import 'package:servicesapp/core/utils/date_labels.dart';
import 'package:servicesapp/core/widgets/app_toast.dart';
import 'package:servicesapp/features/notifications/application/notification_presentation.dart';
import 'package:servicesapp/features/notifications/data/notification_model.dart';
import 'package:servicesapp/features/notifications/data/notification_types.dart';

AppNotification _n(String id, DateTime at, {bool read = false}) =>
    AppNotification(
      id: id,
      userId: 'u1',
      type: NotificationType.helpJobStarted,
      title: 'O trabalho começou',
      body: 'O jardineiro responsável iniciou o trabalho. (Corte de relva, 21/10)',
      read: read,
      createdAt: at,
    );

void main() {
  group('Candidaturas até à véspera', () {
    final now = DateTime(2026, 10, 21, 15);

    test('a véspera é o último dia', () {
      expect(helpApplicationsDeadlineLabel(DateTime(2026, 10, 25), now: now),
          'Candidaturas até 24/10');
      expect(helpApplicationsDeadlineLabel(DateTime(2026, 10, 23), now: now),
          'Candidaturas até amanhã');
      expect(helpApplicationsDeadlineLabel(DateTime(2026, 10, 22), now: now),
          'Candidaturas até hoje');
    });

    test('sem data ou no próprio dia não mostra nada', () {
      expect(helpApplicationsDeadlineLabel(null, now: now), isNull);
      expect(helpApplicationsDeadlineLabel(DateTime(2026, 10, 21), now: now),
          isNull);
    });
  });

  group('Aviso no topo das notificações', () {
    final t = DateTime(2026, 10, 21, 15);

    test('não mostra nada no primeiro carregamento', () {
      expect(notificationForBanner(null, [_n('a', t)]), isNull);
    });

    test('mostra a mais recente das que chegaram', () {
      final old = _n('a', t);
      final first = _n('b', t.add(const Duration(minutes: 1)));
      final newest = _n('c', t.add(const Duration(minutes: 2)));
      expect(notificationForBanner([old], [first, newest, old])?.id, 'c');
      expect(notificationForBanner([old], [old]), isNull);
      expect(
        notificationForBanner([old], [old, _n('d', t, read: true)]),
        isNull,
      );
    });

    test('o contexto passa para o título e não leva "Agora"', () {
      final texts = notificationBannerTexts(_n('a', t));
      expect(texts.title, 'O trabalho começou (Corte de relva, 21/10)');
      expect(texts.body, 'O jardineiro responsável iniciou o trabalho.');
    });

    testWidgets('tocar no aviso abre a notificação e fecha-o', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (context) {
            ctx = context;
            return const Scaffold();
          }),
        ),
      );

      var opened = 0;
      AppToast.of(ctx).notification(
        title: 'Novo candidato a ajudante',
        body: 'Ana quer ajudar.',
        icon: Icons.person_search_outlined,
        color: AppStatusColor.waiting,
        onTap: () => opened++,
      );
      await tester.pumpAndSettle();
      expect(find.text('Novo candidato a ajudante'), findsOneWidget);
      expect(find.text('Ana quer ajudar.'), findsOneWidget);

      await tester.tap(find.text('Ana quer ajudar.'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(find.text('Ana quer ajudar.'), findsNothing);
    });
  });
}
