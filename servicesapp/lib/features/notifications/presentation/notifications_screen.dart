import 'dart:async';

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
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/app_toast.dart';

/// "Notificações" (design A4 e A11), o mesmo ecrã para cliente e jardineiro.
/// Liga `allNotificationsProvider` ao [AppNotificationsView], que só desenha.
/// No cliente é o separador "Alertas" da shell ([inShell], sem seta); no
/// jardineiro abre pelo sino, como ecrã à parte.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key, this.inShell = false});

  final bool inShell;

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  static const _undoFor = Duration(seconds: 6);

  /// Ids limpos pelo último "Limpar tudo", enquanto o "Desfazer" está à
  /// vista.
  List<String>? _clearedIds;
  Timer? _undoTimer;

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }

  /// N2: confirmação obrigatória com o número real; só limpa quando o
  /// servidor responde (sem apagar antes). Depois, "Desfazer" durante 6 s.
  Future<void> _clearAll(int total) async {
    final confirmed = await AppConfirmDialog.show(
      context,
      icon: Icons.delete_sweep_outlined,
      title: total == 1
          ? 'Apagar a notificação?'
          : 'Apagar as $total notificações?',
      message: 'Saem desta lista para sempre. Os teus trabalhos e pedidos '
          'não mudam.',
      confirmLabel: 'Apagar para sempre',
      cancelLabel: 'Não apagar',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    final toast = AppToast.of(context);
    try {
      final ids = await ref.read(notificationRepositoryProvider).clearAll();
      if (!mounted) return;
      _showUndo(ids);
      ref.invalidate(allNotificationsProvider);
    } catch (e) {
      toast.error(friendlyError(e));
    }
  }

  void _showUndo(List<String> ids) {
    _undoTimer?.cancel();
    setState(() => _clearedIds = ids);
    _undoTimer = Timer(_undoFor, () {
      if (mounted) setState(() => _clearedIds = null);
    });
  }

  Future<void> _undoClear() async {
    final ids = _clearedIds;
    if (ids == null) return;
    _undoTimer?.cancel();
    setState(() => _clearedIds = null);
    final toast = AppToast.of(context);
    try {
      await ref.read(notificationRepositoryProvider).restore(ids);
      if (!mounted) return;
      ref.invalidate(allNotificationsProvider);
    } catch (e) {
      toast.error(friendlyError(e));
    }
  }
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

    final cleared = _clearedIds;
    final total = async.value?.length ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: !widget.inShell,
        child: AppNotificationsView(
          title: widget.inShell ? 'Alertas' : 'Notificações',
          dataAsync: async.whenData((list) => notificationsViewData(list, now)),
          onBack: widget.inShell ? null : () => goBackOrToRoleHome(context),
          onClearAll: () => _clearAll(total),
          undoMessage: cleared == null
              ? null
              : cleared.length == 1
                  ? '1 notificação apagada'
                  : '${cleared.length} notificações apagadas',
          onUndo: _undoClear,
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
