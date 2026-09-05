import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_filter_chip.dart';
import '../../../core/widgets/app_motion.dart';
import '../../auth/application/auth_providers.dart';
import '../application/notification_handler.dart';
import '../application/notification_providers.dart';
import '../data/notification_model.dart';
import '../data/notification_types.dart';

/// Categoria de alto nível de uma notificação. Hoje todos os 19 tipos reais
/// mapeiam para `job` — a app não envia notificações de mensagem (sem chat
/// in-app, só WhatsApp externo) nem de avaliação recebida. `message` e
/// `system` ficam preparados no enum para quando essas notificações
/// existirem; sem conteúdo real hoje, não têm filtro próprio na UI.
enum _NotificationCategory { job, message, review, system }

// `type` são consts String (não enum) — sem exaustividade de compilador
// possível. Todos os 19 tipos reais (ver notification_types.dart) caem em
// `job` hoje; `message`/`review`/`system` ficam sem produtores.
_NotificationCategory _categoryForType(String type) => _NotificationCategory.job;

enum _NotificationFilter { all, jobs }

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _optimisticClear = false;
  _NotificationFilter _filter = _NotificationFilter.all;

  Future<void> _clearAll(List<AppNotification> all) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final repo = ref.read(notificationRepositoryProvider);
    final scaffold = ScaffoldMessenger.of(context);
    setState(() => _optimisticClear = true);
    try {
      await repo.markAllAsRead(user.id);
      ref.invalidate(allNotificationsProvider);
    } catch (e) {
      if (mounted) {
        scaffold.showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _optimisticClear = false);
    }
  }

  Future<void> _onNotificationPressed(AppNotification notification) async {
    await NotificationHandler.handle(context, ref, notification);
    await ref.read(notificationRepositoryProvider).markAsRead(notification.id);
    ref.invalidate(allNotificationsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final allAsync = ref.watch(allNotificationsProvider);
    final textTheme = Theme.of(context).textTheme;

    if (allAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (allAsync.hasError) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Notificações')),
        body: Center(child: Text(friendlyError(allAsync.error!))),
      );
    }

    final all = _optimisticClear
        ? (allAsync.asData?.value ?? []).map((n) => n.copyWith(read: true)).toList()
        : (allAsync.asData?.value ?? <AppNotification>[]);

    final jobsCount =
        all.where((n) => _categoryForType(n.type) == _NotificationCategory.job).length;
    final visible = _filter == _NotificationFilter.all
        ? all
        : all.where((n) => _categoryForType(n.type) == _NotificationCategory.job).toList();

    final groups = _groupByDate(visible);
    final hasUnread = all.any((n) => !n.read);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        title: Text(
          'Notificações',
          style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
        ),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: () => _clearAll(all),
              child: const Text('Limpar'),
            ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                AppFilterChip(
                  label: 'Todas (${all.length})',
                  selected: _filter == _NotificationFilter.all,
                  onPressed: () =>
                      setState(() => _filter = _NotificationFilter.all),
                ),
                const SizedBox(width: AppSpacing.xs),
                AppFilterChip(
                  label: 'Trabalhos ($jobsCount)',
                  selected: _filter == _NotificationFilter.jobs,
                  onPressed: () =>
                      setState(() => _filter = _NotificationFilter.jobs),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: groups.isEmpty
                ? const _NotificationsEmptyState()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.xl,
                    ),
                    children: [
                      for (final group in groups) ...[
                        Padding(
                          padding: const EdgeInsets.only(
                            top: AppSpacing.sm,
                            bottom: AppSpacing.xs,
                          ),
                          child: Text(
                            group.label,
                            style: textTheme.labelMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        for (var i = 0; i < group.notifications.length; i++) ...[
                          AppStaggeredEntrance(
                            index: i,
                            child: _NotificationCard(
                              notification: group.notifications[i],
                              onPressed: () =>
                                  _onNotificationPressed(group.notifications[i]),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                        ],
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _NotificationGroup {
  const _NotificationGroup({required this.label, required this.notifications});

  final String label;
  final List<AppNotification> notifications;
}

List<_NotificationGroup> _groupByDate(List<AppNotification> notifications) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));

  final todayList = <AppNotification>[];
  final yesterdayList = <AppNotification>[];
  final olderList = <AppNotification>[];

  for (final n in notifications) {
    final day = DateTime(n.createdAt.year, n.createdAt.month, n.createdAt.day);
    if (day == today) {
      todayList.add(n);
    } else if (day == yesterday) {
      yesterdayList.add(n);
    } else {
      olderList.add(n);
    }
  }

  return [
    if (todayList.isNotEmpty) _NotificationGroup(label: 'HOJE', notifications: todayList),
    if (yesterdayList.isNotEmpty)
      _NotificationGroup(label: 'ONTEM', notifications: yesterdayList),
    if (olderList.isNotEmpty)
      _NotificationGroup(label: 'MAIS ANTIGAS', notifications: olderList),
  ];
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification, required this.onPressed});

  final AppNotification notification;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final (icon, color) = _iconForType(notification.type);

    return Material(
      color: notification.read ? AppColors.surface : AppColors.primaryContainer,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.input),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: (notification.read
                                    ? textTheme.bodyMedium
                                    : textTheme.titleMedium)
                                ?.copyWith(color: AppColors.textPrimary),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          _relativeTime(notification.createdAt),
                          style: textTheme.labelMedium
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                        if (!notification.read) ...[
                          const SizedBox(width: AppSpacing.xxs),
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      notification.body,
                      style: textTheme.bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationsEmptyState extends StatelessWidget {
  const _NotificationsEmptyState();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.notifications_none_rounded,
            size: 64,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Sem notificações.',
            style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

(IconData, Color) _iconForType(String type) => switch (type) {
      NotificationType.newJobInRadius => (Icons.yard, Colors.green.shade600),
      NotificationType.proposalReceived =>
        (Icons.description, Colors.orange.shade700),
      NotificationType.proposalAccepted =>
        (Icons.check_circle, Colors.green.shade600),
      NotificationType.proposalRejected =>
        (Icons.cancel, Colors.red.shade600),
      NotificationType.helpRequestApproved =>
        (Icons.groups_outlined, Colors.green.shade600),
      NotificationType.helpAccepted =>
        (Icons.person_add_alt_1, Colors.green.shade600),
      NotificationType.helpRejected =>
        (Icons.person_remove, Colors.grey.shade600),
      NotificationType.helpJobCancelled =>
        (Icons.event_busy, Colors.red.shade400),
      NotificationType.helpRequestReopened =>
        (Icons.group_add_outlined, Colors.blue.shade600),
      NotificationType.helpWithdrew =>
        (Icons.person_remove_alt_1, Colors.orange.shade700),
      // Restantes 9 tipos (jobCancelled, jobReopened, reschedule*,
      // jobMarkedDone, jobCompleted, jobNoResponse): sem ícone dedicado,
      // caem no genérico de "trabalho" — todos são eventos de job.
      _ => (Icons.work_outline_rounded, AppColors.primary),
    };

String _relativeTime(DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime);
  if (diff.inMinutes < 1) return 'agora';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'há ${diff.inHours}h';
  return 'há ${diff.inDays} dia${diff.inDays > 1 ? 's' : ''}';
}
