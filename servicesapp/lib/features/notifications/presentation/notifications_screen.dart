import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/theme/app_motion_tokens.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_filter_chip.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_screen_loading_skeleton.dart';
import '../../auth/application/auth_providers.dart';
import '../application/notification_handler.dart';
import '../application/notification_providers.dart';
import '../data/notification_model.dart';
import '../data/notification_types.dart';

/// Categoria de alto nível de uma notificação. Hoje todos os tipos reais
/// mapeiam para `job`: a app não envia notificações de mensagem (sem chat
/// in-app, só WhatsApp externo) nem de avaliação recebida. Quando essas
/// notificações existirem, acrescenta-se aqui o valor (`message`, `review`,
/// `system`) e o filtro correspondente na UI.
enum _NotificationCategory { job }

// `type` são consts String (não enum), sem exaustividade de compilador
// possível. Todos os tipos reais (ver notification_types.dart) caem em `job`.
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

  /// Marca como lida ANTES de navegar: `NotificationHandler` faz
  /// `context.go()` e este ecrã é desmontado, e usar `ref` depois disso
  /// lançava StateError (e a notificação ficava por ler). O contentor é
  /// capturado antes, para invalidar depois da navegação (regra T4).
  Future<void> _onNotificationPressed(AppNotification notification) async {
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

  @override
  Widget build(BuildContext context) {
    final allAsync = ref.watch(allNotificationsProvider);
    final textTheme = Theme.of(context).textTheme;

    if (allAsync.isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          surfaceTintColor: AppColors.background,
          elevation: 0,
          leading: const AppBackButton(),
          title: const Text('Notificações'),
        ),
        body: const AppScreenLoadingSkeleton(),
      );
    }

    if (allAsync.hasError) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          surfaceTintColor: AppColors.background,
          elevation: 0,
          leading: const AppBackButton(),
          title: const Text('Notificações'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  friendlyError(allAsync.error!),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(
                  onPressed: () => ref.invalidate(allNotificationsProvider),
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
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

    // Contador acumulado entre grupos de data — sem isto, o índice do
    // stagger reinicia a 0 em cada grupo ("HOJE"/"ONTEM"/...) e vários
    // cards de grupos diferentes entram em simultâneo em vez de uma
    // cascata única a descer a lista toda (mesmo padrão já usado em
    // worker_help_requests_lobby_view.dart).
    var entranceIndex = 0;
    int nextIndex() => entranceIndex++;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        leading: const AppBackButton(),
        title: Text(
          'Notificações',
          style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
        ),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: () => _clearAll(all),
              child: const Text('Marcar todas como lidas'),
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
                        for (final notification in group.notifications) ...[
                          AppStaggeredEntrance(
                            key: ValueKey<String>(notification.id),
                            index: nextIndex(),
                            child: _NotificationCard(
                              notification: notification,
                              onPressed: () =>
                                  _onNotificationPressed(notification),
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

    // docs/motion_spec.md §3, "Notificação não-lida": ao ser lida, o fundo
    // tonal desvanece para branco ao longo de 200ms (`AppMotionDuration.fast`
    // — perceptível, não brusco). Reduced motion mantém a cor final mas
    // corta a transição (§5).
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final transitionDuration =
        disableAnimations ? Duration.zero : AppMotionDuration.fast;

    return Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: AnimatedContainer(
          duration: transitionDuration,
          curve: AppMotionCurve.standard,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: notification.read
                ? AppColors.surface
                : AppColors.primaryContainer,
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
                        const SizedBox(width: AppSpacing.xxs),
                        // Sempre no layout (não inserido/removido
                        // condicionalmente) para que a opacidade possa
                        // fazer fade em vez de aparecer/desaparecer
                        // abruptamente (docs/motion_spec.md §3, "Ponto
                        // verde entra com fade").
                        AnimatedOpacity(
                          opacity: notification.read ? 0 : 1,
                          duration: transitionDuration,
                          curve: AppMotionCurve.standard,
                          child: const SizedBox(
                            width: 7,
                            height: 7,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
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
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: AppEmptyState(
          icon: Icons.notifications_none_rounded,
          title: 'Sem notificações',
          message: 'Os avisos sobre os teus pedidos e trabalhos aparecem aqui.',
          tone: AppStatusColor.neutral,
        ),
      ),
    );
  }
}

(IconData, Color) _iconForType(String type) => switch (type) {
      NotificationType.newJobInRadius => (Icons.yard, AppColors.primary),
      NotificationType.proposalReceived =>
        (Icons.description, AppStatusColor.waiting.foreground),
      NotificationType.proposalAccepted =>
        (Icons.check_circle, AppColors.primary),
      NotificationType.proposalRejected =>
        (Icons.cancel, AppStatusColor.cancelled.foreground),
      NotificationType.helpRequestApproved =>
        (Icons.groups_outlined, AppColors.primary),
      NotificationType.helpAccepted =>
        (Icons.person_add_alt_1, AppColors.primary),
      NotificationType.helpRejected =>
        (Icons.person_remove, AppStatusColor.neutral.foreground),
      NotificationType.helpJobCancelled =>
        (Icons.event_busy, AppStatusColor.cancelled.foreground),
      NotificationType.helpRequestReopened =>
        (Icons.group_add_outlined, AppStatusColor.info.foreground),
      NotificationType.helpWithdrew =>
        (Icons.person_remove_alt_1, AppStatusColor.waiting.foreground),
      NotificationType.jobReminder =>
        (Icons.alarm_rounded, AppColors.primary),
      NotificationType.jobStarted =>
        (Icons.play_circle_outline_rounded, AppStatusColor.info.foreground),
      NotificationType.jobUpdated =>
        (Icons.edit_note_rounded, AppStatusColor.info.foreground),
      NotificationType.helpRemoved =>
        (Icons.person_remove_outlined, AppStatusColor.cancelled.foreground),
      NotificationType.helpJobRescheduled =>
        (Icons.event_repeat_rounded, AppStatusColor.waiting.foreground),
      NotificationType.helpJobDone =>
        (Icons.task_alt_rounded, AppStatusColor.info.foreground),
      NotificationType.helpJobCompleted =>
        (Icons.verified_outlined, AppStatusColor.success.foreground),
      NotificationType.helpCandidateApplied =>
        (Icons.person_search_outlined, AppStatusColor.waiting.foreground),
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
