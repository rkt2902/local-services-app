import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/theme/app_status_color.dart';
import 'package:servicesapp/core/widgets/app_notifications_view.dart';
import 'package:servicesapp/features/notifications/application/notification_presentation.dart';
import 'package:servicesapp/features/notifications/data/notification_model.dart';
import 'package:servicesapp/features/notifications/data/notification_types.dart';
import 'package:servicesapp/features/notifications/presentation/notifications_screen.dart';

final _now = DateTime(2026, 10, 19, 15);

AppNotification _n(
  String id, {
  String type = NotificationType.helpCandidateApplied,
  String title = 'Novo candidato a ajudante',
  String body = 'Ana Lopes quer ajudar. (Abate de árvore, 24/10)',
  bool read = false,
  DateTime? at,
}) =>
    AppNotification(
      id: id,
      userId: 'u1',
      type: type,
      title: title,
      body: body,
      read: read,
      createdAt: at ?? _now.subtract(const Duration(minutes: 10)),
    );

Widget _screen(
  AsyncValue<AppNotificationsViewData> data, {
  Future<void> Function()? onMarkAll,
  ValueChanged<AppNotificationItemViewData>? onAction,
}) {
  return MaterialApp(
    home: Scaffold(
      body: AppNotificationsView(
        dataAsync: data,
        onBack: () {},
        onOpen: (_) {},
        onAction: onAction ?? (_) {},
        onMarkAllAsRead: onMarkAll ?? () async {},
        onRefresh: () async {},
        onRetry: () {},
      ),
    ),
  );
}

void main() {
  group('apresentação (design A4)', () {
    test('o trabalho passa do corpo para o título e hoje leva há quanto', () {
      final t = notificationTexts(_n('1'), now: _now);
      expect(t.title, 'Novo candidato a ajudante (Abate de árvore, 24/10)');
      expect(t.body, 'Ana Lopes quer ajudar. Há 10 min');

      final old = notificationTexts(
        _n('2', body: 'Ninguém foi escolhido.', at: DateTime(2026, 10, 2, 9)),
        now: _now,
      );
      expect(old.title, 'Novo candidato a ajudante');
      expect(old.body, 'Ninguém foi escolhido.');
    });

    test('tom por tipo segue a legenda', () {
      expect(notificationLook(NotificationType.proposalReceived).tone,
          AppStatusColor.success);
      expect(notificationLook(NotificationType.helpCandidateApplied).tone,
          AppStatusColor.waiting);
      expect(notificationLook(NotificationType.jobMarkedDone).tone,
          AppStatusColor.info);
      expect(notificationLook(NotificationType.jobCancelled).tone,
          AppStatusColor.cancelled);
      expect(notificationLook(NotificationType.jobNoResponse).tone,
          AppStatusColor.neutral);
    });

    test('secções, filtro Trabalhos e botão de confirmar', () {
      final list = [
        _n('1'),
        _n('2',
            type: NotificationType.newJobInRadius,
            at: DateTime(2026, 10, 18, 9)),
        _n('3', read: true, at: DateTime(2026, 10, 1)),
      ];
      final data = notificationsViewData(list, _now);
      expect(data.allFilterLabel, 'Todas (3)');
      expect(data.jobsFilterLabel, 'Trabalhos (2)');
      expect(data.all.map((s) => s.label), ['Hoje', 'Ontem', 'Mais antigas']);
      expect(data.jobs.map((s) => s.label), ['Hoje', 'Mais antigas']);
      expect(data.hasUnread, isTrue);

      expect(
        notificationActionLabel(_n('4', type: NotificationType.jobMarkedDone)),
        'Confirmar conclusão',
      );
      expect(
        notificationActionLabel(
            _n('5', type: NotificationType.jobMarkedDone, read: true)),
        isNull,
      );
    });
  });

  testWidgets('lista, filtros e marcar todas espera pelo servidor',
      (tester) async {
    final data = notificationsViewData([
      _n('1'),
      _n('2', type: NotificationType.jobMarkedDone, title: 'Trabalho feito'),
      _n('3',
          type: NotificationType.newJobInRadius,
          title: 'Novo pedido perto de ti',
          body: 'Há um pedido novo.',
          read: true,
          at: DateTime(2026, 10, 18, 9)),
    ], _now);

    var calls = 0;
    AppNotificationItemViewData? acted;
    await tester.pumpWidget(_screen(
      AsyncData(data),
      onMarkAll: () async => calls++,
      onAction: (item) => acted = item,
    ));
    await tester.pumpAndSettle();

    expect(find.text('HOJE'), findsOneWidget);
    expect(find.text('ONTEM'), findsOneWidget);
    expect(find.text('Novo candidato a ajudante (Abate de árvore, 24/10)'),
        findsOneWidget);

    await tester.tap(find.text('Confirmar conclusão'));
    expect(acted?.id, '2');

    await tester.tap(find.text('Trabalhos (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Novo pedido perto de ti'), findsNothing);

    await tester.tap(find.text('Marcar todas como lidas'));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('vazio, erro e marcar todas desligado sem não lidas',
      (tester) async {
    await tester.pumpWidget(_screen(AsyncData(notificationsViewData(
      [_n('1', read: true)],
      _now,
    ))));
    await tester.pumpAndSettle();
    final button = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Marcar todas como lidas'),
        matching: find.byType(TextButton),
      ),
    );
    expect(button.onPressed, isNull);

    await tester
        .pumpWidget(_screen(AsyncData(notificationsViewData(const [], _now))));
    await tester.pumpAndSettle();
    expect(find.text('Ainda sem notificações'), findsWidgets);

    await tester
        .pumpWidget(_screen(AsyncError(Exception('x'), StackTrace.empty)));
    await tester.pumpAndSettle();
    expect(
        find.text('Não foi possível carregar as notificações'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
  });
}
