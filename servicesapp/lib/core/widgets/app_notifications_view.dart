import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion_tokens.dart';
import '../theme/app_radius.dart';
import '../theme/app_sizes.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status_color.dart';
import 'app_empty_state.dart';
import 'app_filter_chip.dart';
import 'app_motion.dart';

enum AppNotificationsFilter { all, jobs }

/// Dados de "Notificações" (design A4), iguais para cliente e jardineiro.
/// A integração (notifications_screen.dart) agrupa, escolhe ícone e tom
/// por tipo e formata os textos; este widget só desenha.
class AppNotificationsViewData {
  const AppNotificationsViewData({
    required this.allFilterLabel,
    required this.jobsFilterLabel,
    required this.hasUnread,
    required this.all,
    required this.jobs,
  });

  /// Ex.: "Todas (9)" e "Trabalhos (6)".
  final String allFilterLabel;
  final String jobsFilterLabel;

  /// Liga "Marcar todas como lidas".
  final bool hasUnread;
  final List<AppNotificationSectionViewData> all;
  final List<AppNotificationSectionViewData> jobs;
}

class AppNotificationSectionViewData {
  const AppNotificationSectionViewData({
    required this.label,
    required this.items,
  });

  /// Ex.: "Hoje"; aparece em maiúsculas.
  final String label;
  final List<AppNotificationItemViewData> items;
}

class AppNotificationItemViewData {
  const AppNotificationItemViewData({
    required this.id,
    required this.title,
    required this.body,
    required this.icon,
    required this.tone,
    required this.unread,
    this.actionLabel,
  });

  final String id;

  /// Já com o trabalho. Ex.: "Nova proposta (Corte de relva, 23/10)".
  final String title;
  final String body;
  final IconData icon;

  /// Um dos cinco tons de estado; "não lida" não é um tom.
  final AppStatusColor tone;
  final bool unread;

  /// Botão no próprio aviso (ex.: "Confirmar conclusão").
  final String? actionLabel;
}

class AppNotificationsView extends StatefulWidget {
  const AppNotificationsView({
    super.key,
    required this.dataAsync,
    required this.onBack,
    required this.onOpen,
    required this.onAction,
    required this.onMarkAllAsRead,
    required this.onRefresh,
    required this.onRetry,
  });

  final AsyncValue<AppNotificationsViewData> dataAsync;
  final VoidCallback onBack;
  final ValueChanged<AppNotificationItemViewData> onOpen;
  final ValueChanged<AppNotificationItemViewData> onAction;

  /// Acaba quando o servidor responde; a lista atualiza pelos providers.
  final Future<void> Function() onMarkAllAsRead;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;

  @override
  State<AppNotificationsView> createState() => _AppNotificationsViewState();
}

class _AppNotificationsViewState extends State<AppNotificationsView> {
  AppNotificationsFilter _filter = AppNotificationsFilter.all;
  bool _marking = false;

  Future<void> _markAll() async {
    if (_marking) return;
    setState(() => _marking = true);
    try {
      await widget.onMarkAllAsRead();
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.dataAsync.value;
    final Widget body;
    if (data != null) {
      body = IndexedStack(
        index: _filter.index,
        children: [
          _NotificationsList(
            key: const PageStorageKey('notifications_all'),
            sections: data.all,
            onOpen: widget.onOpen,
            onAction: widget.onAction,
            onRefresh: widget.onRefresh,
          ),
          _NotificationsList(
            key: const PageStorageKey('notifications_jobs'),
            sections: data.jobs,
            onOpen: widget.onOpen,
            onAction: widget.onAction,
            onRefresh: widget.onRefresh,
          ),
        ],
      );
    } else if (widget.dataAsync.hasError) {
      body = _CenteredState(
        child: AppEmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Não foi possível carregar as notificações',
          message: 'Verifica a ligação e tenta outra vez.',
          actionLabel: 'Tentar novamente',
          onAction: widget.onRetry,
          tone: AppStatusColor.cancelled,
        ),
      );
    } else {
      body = const _LoadingList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          canMarkAll: (data?.hasUnread ?? false) && !_marking,
          marking: _marking,
          onBack: widget.onBack,
          onMarkAll: _markAll,
        ),
        if (data != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                AppFilterChip(
                  label: data.allFilterLabel,
                  selected: _filter == AppNotificationsFilter.all,
                  onPressed: () =>
                      setState(() => _filter = AppNotificationsFilter.all),
                ),
                AppFilterChip(
                  label: data.jobsFilterLabel,
                  selected: _filter == AppNotificationsFilter.jobs,
                  onPressed: () =>
                      setState(() => _filter = AppNotificationsFilter.jobs),
                ),
              ],
            ),
          ),
        Expanded(child: body),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.canMarkAll,
    required this.marking,
    required this.onBack,
    required this.onMarkAll,
  });

  final bool canMarkAll;
  final bool marking;
  final VoidCallback onBack;
  final VoidCallback onMarkAll;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'Voltar',
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Text(
              'Notificações',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: TextButton(
              onPressed: canMarkAll ? onMarkAll : null,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xxs,
                ),
              ),
              child: Text(
                marking ? 'A marcar...' : 'Marcar todas como lidas',
                textAlign: TextAlign.end,
                style: textTheme.labelMedium?.copyWith(
                  color: canMarkAll
                      ? AppColors.primary
                      : AppStatusColor.neutral.foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: child,
      ),
    );
  }
}

class _NotificationsList extends StatelessWidget {
  const _NotificationsList({
    super.key,
    required this.sections,
    required this.onOpen,
    required this.onAction,
    required this.onRefresh,
  });

  final List<AppNotificationSectionViewData> sections;
  final ValueChanged<AppNotificationItemViewData> onOpen;
  final ValueChanged<AppNotificationItemViewData> onAction;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (sections.every((s) => s.items.isEmpty)) {
      // Com scroll para o pull-to-refresh funcionar também no vazio.
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: onRefresh,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: constraints.maxHeight,
              child: const _CenteredState(
                child: AppEmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'Ainda sem notificações',
                  message: 'Quando houver novidades sobre os teus trabalhos, '
                      'avisamos-te aqui.',
                ),
              ),
            ),
          ),
        ),
      );
    }

    var entrance = 0;
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: [
          for (final section in sections)
            if (section.items.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.xs,
                  bottom: AppSpacing.xs,
                ),
                child: Text(
                  section.label.toUpperCase(),
                  style: textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              AppStaggeredEntrance(
                index: entrance++,
                child: _SectionCard(
                  items: section.items,
                  onOpen: onOpen,
                  onAction: onAction,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
        ],
      ),
    );
  }
}

/// Uma secção é um cartão com as notificações separadas por linhas, como
/// no design.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.items,
    required this.onOpen,
    required this.onAction,
  });

  final List<AppNotificationItemViewData> items;
  final ValueChanged<AppNotificationItemViewData> onOpen;
  final ValueChanged<AppNotificationItemViewData> onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.divider),
            _NotificationRow(
              key: ValueKey(items[i].id),
              item: items[i],
              onOpen: () => onOpen(items[i]),
              onAction: items[i].actionLabel == null
                  ? null
                  : () => onAction(items[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    super.key,
    required this.item,
    required this.onOpen,
    required this.onAction,
  });

  final AppNotificationItemViewData item;
  final VoidCallback onOpen;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final action = item.actionLabel;

    // docs/motion_spec.md §3, "Notificação não-lida": ao ser lida, o fundo
    // e o ponto desvanecem; reduced motion corta a transição (§5).
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = disableAnimations ? Duration.zero : AppMotionDuration.fast;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onOpen,
        child: AnimatedContainer(
          duration: duration,
          curve: AppMotionCurve.standard,
          color: item.unread ? AppColors.primaryContainer : AppColors.surface,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: AppSizes.rowIconBox,
                height: AppSizes.rowIconBox,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: item.tone.background,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                ),
                child: Icon(
                  item.icon,
                  size: AppSizes.rowIcon,
                  color: item.tone.foreground,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      item.body,
                      style: textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                    if (action != null && onAction != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      FilledButton(
                        onPressed: onAction,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.surface,
                          minimumSize: const Size(0, AppSizes.rowIconBox),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.input),
                          ),
                          textStyle: textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        child: Text(action),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              // Sempre no layout para o ponto poder desvanecer.
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s6),
                child: AnimatedOpacity(
                  opacity: item.unread ? 1 : 0,
                  duration: duration,
                  curve: AppMotionCurve.standard,
                  child: Container(
                    width: AppSizes.unreadDot,
                    height: AppSizes.unreadDot,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    Widget block(double height, {double? width}) => AppSkeletonShimmer(
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
          ),
        );

    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        block(AppSpacing.sm, width: AppSizes.notificationSkeletonLabel),
        const SizedBox(height: AppSpacing.xs),
        block(AppSizes.notificationSkeletonSection),
        const SizedBox(height: AppSpacing.md),
        block(AppSpacing.sm, width: AppSizes.notificationSkeletonLabel),
        const SizedBox(height: AppSpacing.xs),
        block(AppSizes.notificationSkeletonSection),
      ],
    );
  }
}
