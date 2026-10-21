import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_back_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_notifications_view.dart';
import '../../auth/application/auth_providers.dart';
import '../application/notification_handler.dart';
import '../application/notification_presentation.dart';
import '../application/notification_providers.dart';
import '../data/notification_model.dart';
import '../../../core/widgets/app_toast.dart';

/// "Notificações" (design A4), o mesmo ecrã para cliente e jardineiro. Liga
/// `allNotificationsProvider` ao [AppNotificationsView], que só desenha.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// Sem atualização otimista: só fica tudo lido quando o servidor o
  /// confirma e a lista volta a ser lida.
  Future<void> _markAllAsRead() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final toast = AppToast.of(context);
    try {
      await ref.read(notificationRepositoryProvider).markAllAsRead(user.id);
      if (!mounted) return;
      ref.invalidate(allNotificationsProvider);
      await ref.read(allNotificationsProvider.future);
    } catch (e) {
      toast.error(friendlyError(e));
    }
  }

  /// Marca como lida ANTES de navegar: `NotificationHandler` faz
  /// `context.go()` e este ecrã é desmontado, e usar `ref` depois disso
  /// lançava StateError (e a notificação ficava por ler). O contentor é
  /// capturado antes, para invalidar depois da navegação (regra T4).
  Future<void> _open(AppNotification notification) async {
    final repo = ref.read(notificationRepositoryProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    if (!notification.read) {
      try {
        await repo.markAsRead(notification.id);
      } catch (_) {
        // Sem rede: abre na mesma, fica por ler.
      }
    }
    if (!mounted) return;
    await NotificationHandler.handle(context, ref, notification);
    container.invalidate(allNotificationsProvider);
  }

  Future<void> _refresh() async {
    ref.invalidate(allNotificationsProvider);
    try {
      await ref.read(allNotificationsProvider.future);
    } catch (_) {
      // O erro aparece no próprio ecrã.
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(allNotificationsProvider);
    final now = DateTime.now();
    final byId = {
      for (final n in async.value ?? const <AppNotification>[]) n.id: n,
    };

    void openItem(AppNotificationItemViewData item) {
      final n = byId[item.id];
      if (n != null) _open(n);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: AppNotificationsView(
          dataAsync: async.whenData((list) => notificationsViewData(list, now)),
          onBack: () => goBackOrToRoleHome(context),
          onOpen: openItem,
          // "Confirmar conclusão" abre o pedido, onde o cliente vê as fotos
          // e confirma (o mesmo destino do toque no aviso).
          onAction: openItem,
          onMarkAllAsRead: _markAllAsRead,
          onRefresh: _refresh,
          onRetry: () => ref.invalidate(allNotificationsProvider),
        ),
      ),
    );
  }
}

/// Lista do servidor (a mais recente primeiro) → dados do ecrã.
AppNotificationsViewData notificationsViewData(
  List<AppNotification> list,
  DateTime now,
) {
  List<AppNotificationSectionViewData> sectionsOf(List<AppNotification> ns) => [
        for (final s in notificationSections(ns, now))
          AppNotificationSectionViewData(
            label: s.label,
            items: [for (final n in s.items) notificationItem(n, now)],
          ),
      ];

  final jobs = list.where((n) => isJobNotification(n.type)).toList();
  return AppNotificationsViewData(
    allFilterLabel: 'Todas (${list.length})',
    jobsFilterLabel: 'Trabalhos (${jobs.length})',
    hasUnread: list.any((n) => !n.read),
    all: sectionsOf(list),
    jobs: sectionsOf(jobs),
  );
}

AppNotificationItemViewData notificationItem(AppNotification n, DateTime now) {
  final look = notificationLook(n.type);
  final texts = notificationTexts(n, now: now);
  return AppNotificationItemViewData(
    id: n.id,
    title: texts.title,
    body: texts.body,
    icon: look.icon,
    tone: look.tone,
    unread: !n.read,
    actionLabel: notificationActionLabel(n),
  );
}
