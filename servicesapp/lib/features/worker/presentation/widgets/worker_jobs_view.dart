import 'package:flutter/material.dart';

import 'package:servicesapp/core/theme/app_colors.dart';
import 'package:servicesapp/core/theme/app_radius.dart';
import 'package:servicesapp/core/theme/app_spacing.dart';
import 'package:servicesapp/core/theme/app_status_presentation.dart';
import 'package:servicesapp/core/widgets/app_motion.dart';
import 'package:servicesapp/core/widgets/app_status_badge.dart';

enum WorkerJobsTab {
  pending,
  scheduled,
  completed,
}

class WorkerJobListItemViewData {
  const WorkerJobListItemViewData({
    required this.id,
    required this.title,
    required this.personName,
    required this.locationLabel,
    required this.secondaryLabel,
    required this.priceLabel,
    required this.status,
    this.muted = false,
  });

  final String id;
  final String title;
  final String personName;
  final String locationLabel;
  final String secondaryLabel;
  final String priceLabel;
  final AppStatusPresentation status;

  /// Exemplo: proposta rejeitada ou substituída.
  final bool muted;
}

class WorkerJobsScreen extends StatelessWidget {
  const WorkerJobsScreen({
    required this.selectedTab,
    required this.pendingCount,
    required this.scheduledCount,
    required this.completedCount,
    required this.jobs,
    required this.onTabSelected,
    required this.onJobPressed,
    super.key,
    this.loading = false,
    this.errorMessage,
    this.onRetry,
    this.onRefresh,
    this.highlightedJobId,
    this.onLoadMore,
    this.loadingMore = false,
  });

  final WorkerJobsTab selectedTab;

  final int pendingCount;
  final int scheduledCount;
  final int completedCount;

  /// A integração deve passar apenas os itens correspondentes à tab atual.
  final List<WorkerJobListItemViewData> jobs;

  final ValueChanged<WorkerJobsTab> onTabSelected;
  final ValueChanged<String> onJobPressed;

  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final Future<void> Function()? onRefresh;

  /// Suporte para deep-link de notificações.
  ///
  /// A integração pode manter este ID ativo durante cerca de 1 segundo e
  /// depois limpá-lo.
  final String? highlightedJobId;

  /// Scroll infinito da tab "Concluídos" — chamado quando o utilizador se
  /// aproxima do fim da lista. `null` nas tabs sem paginação.
  final VoidCallback? onLoadMore;
  final bool loadingMore;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(
                'Os meus trabalhos',
                style: textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _JobsTabButton(
                      label: 'Pendentes',
                      count: pendingCount,
                      selected:
                          selectedTab == WorkerJobsTab.pending,
                      onPressed: () {
                        onTabSelected(WorkerJobsTab.pending);
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: _JobsTabButton(
                      label: 'Agendados',
                      count: scheduledCount,
                      selected:
                          selectedTab == WorkerJobsTab.scheduled,
                      onPressed: () {
                        onTabSelected(WorkerJobsTab.scheduled);
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: _JobsTabButton(
                      label: 'Concluídos',
                      count: completedCount,
                      selected:
                          selectedTab == WorkerJobsTab.completed,
                      onPressed: () {
                        onTabSelected(WorkerJobsTab.completed);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Divider(
              height: 1,
              color: AppColors.divider,
            ),
            Expanded(
              child: AppFadeThroughSwitcher(
                switchKey: selectedTab,
                child: _JobsTabContent(
                  key: ValueKey<WorkerJobsTab>(selectedTab),
                  jobs: jobs,
                  loading: loading,
                  errorMessage: errorMessage,
                  onRetry: onRetry,
                  onRefresh: onRefresh,
                  onJobPressed: onJobPressed,
                  highlightedJobId: highlightedJobId,
                  onLoadMore: onLoadMore,
                  loadingMore: loadingMore,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobsTabButton extends StatelessWidget {
  const _JobsTabButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count',
      child: Material(
        color: selected
            ? AppColors.primary
            : AppColors.surface,
        borderRadius: BorderRadius.circular(
          AppRadius.pill,
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(
            AppRadius.pill,
          ),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: 48,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                AppRadius.pill,
              ),
              border: selected
                  ? null
                  : Border.all(
                      color: AppColors.divider,
                    ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$label\n$count',
                textAlign: TextAlign.center,
                style: textTheme.labelMedium?.copyWith(
                  color: selected
                      ? AppColors.surface
                      : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _JobsTabContent extends StatefulWidget {
  const _JobsTabContent({
    required this.jobs,
    required this.loading,
    required this.errorMessage,
    required this.onRetry,
    required this.onRefresh,
    required this.onJobPressed,
    required this.highlightedJobId,
    required this.onLoadMore,
    required this.loadingMore,
    super.key,
  });

  final List<WorkerJobListItemViewData> jobs;
  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final Future<void> Function()? onRefresh;
  final ValueChanged<String> onJobPressed;
  final String? highlightedJobId;
  final VoidCallback? onLoadMore;
  final bool loadingMore;

  @override
  State<_JobsTabContent> createState() => _JobsTabContentState();
}

class _JobsTabContentState extends State<_JobsTabContent> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = {};
  String? _scrolledToHighlightId;

  static const double _loadMoreThreshold = 300;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeScrollToHighlighted();
    });
  }

  @override
  void didUpdateWidget(covariant _JobsTabContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlightedJobId != oldWidget.highlightedJobId) {
      _scrolledToHighlightId = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeScrollToHighlighted();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (widget.onLoadMore == null || widget.loadingMore) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels < _loadMoreThreshold) {
      widget.onLoadMore!();
    }
  }

  void _maybeScrollToHighlighted() {
    if (!mounted) return;
    final id = widget.highlightedJobId;
    if (id == null || id == _scrolledToHighlightId) return;
    final key = _itemKeys[id];
    final targetContext = key?.currentContext;
    if (targetContext == null) return;
    _scrolledToHighlightId = id;
    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: 0.2,
    );
  }

  GlobalKey _keyFor(String id) {
    return _itemKeys.putIfAbsent(id, GlobalKey.new);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const _JobsSkeletonList();
    }

    if (widget.errorMessage != null) {
      return _JobsMessageState(
        icon: Icons.error_outline_rounded,
        message: widget.errorMessage!,
        actionLabel:
            widget.onRetry == null ? null : 'Tentar novamente',
        onActionPressed: widget.onRetry,
      );
    }

    if (widget.jobs.isEmpty) {
      final emptyState = const _JobsMessageState(
        icon: Icons.work_outline_rounded,
        message:
            'Não existem trabalhos nesta categoria.',
      );

      if (widget.onRefresh == null) return emptyState;

      return LayoutBuilder(
        builder: (context, constraints) => RefreshIndicator(
          onRefresh: widget.onRefresh!,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: constraints.maxHeight,
              child: emptyState,
            ),
          ),
        ),
      );
    }

    final showFooter = widget.onLoadMore != null && widget.loadingMore;

    final list = ListView.separated(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      itemCount: widget.jobs.length + (showFooter ? 1 : 0),
      separatorBuilder: (_, _) {
        return const SizedBox(height: AppSpacing.sm);
      },
      itemBuilder: (context, index) {
        if (index == widget.jobs.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
            ),
          );
        }

        final job = widget.jobs[index];

        return AppStaggeredEntrance(
          key: _keyFor(job.id),
          index: index,
          child: _WorkerJobCard(
            job: job,
            highlighted: widget.highlightedJobId == job.id,
            onPressed: () => widget.onJobPressed(job.id),
          ),
        );
      },
    );

    if (widget.onRefresh == null) return list;

    return RefreshIndicator(
      onRefresh: widget.onRefresh!,
      child: list,
    );
  }
}

class _WorkerJobCard extends StatelessWidget {
  const _WorkerJobCard({
    required this.job,
    required this.highlighted,
    required this.onPressed,
  });

  final WorkerJobListItemViewData job;
  final bool highlighted;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Opacity(
      opacity: job.muted ? 0.58 : 1,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(
          AppRadius.card,
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(
            AppRadius.card,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: highlighted
                  ? AppColors.primaryContainer
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(
                AppRadius.card,
              ),
              border: Border.all(
                color: highlighted
                    ? AppColors.primary
                    : AppColors.divider,
              ),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            job.title,
                            maxLines: 2,
                            overflow:
                                TextOverflow.ellipsis,
                            style: textTheme.titleMedium?.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(
                            height: AppSpacing.xxs,
                          ),
                          Text(
                            job.personName.isEmpty
                                ? job.locationLabel
                                : '${job.personName} · '
                                    '${job.locationLabel}',
                            maxLines: 1,
                            overflow:
                                TextOverflow.ellipsis,
                            style:
                                textTheme.labelMedium?.copyWith(
                              color:
                                  AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    AppStatusBadge.fromPresentation(
                      presentation: job.status,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        job.secondaryLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      job.priceLabel,
                      maxLines: 1,
                      style:
                          textTheme.titleMedium?.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JobsSkeletonList extends StatelessWidget {
  const _JobsSkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      itemCount: 3,
      separatorBuilder: (_, _) {
        return const SizedBox(height: AppSpacing.sm);
      },
      itemBuilder: (context, index) {
        return AppStaggeredEntrance(
          index: index,
          child: const AppSkeletonShimmer(
            child: _JobSkeletonCard(),
          ),
        );
      },
    );
  }
}

class _JobSkeletonCard extends StatelessWidget {
  const _JobSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(
          AppRadius.card,
        ),
        border: Border.all(
          color: AppColors.divider,
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonLine(widthFactor: 0.52),
          SizedBox(height: AppSpacing.xs),
          _SkeletonLine(widthFactor: 0.36),
          Spacer(),
          Row(
            children: [
              Expanded(
                child: _SkeletonLine(widthFactor: 0.55),
              ),
              SizedBox(width: AppSpacing.lg),
              SizedBox(
                width: 52,
                child: _SkeletonLine(widthFactor: 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({
    required this.widthFactor,
  });

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: 12,
        decoration: BoxDecoration(
          color: AppColors.divider,
          borderRadius: BorderRadius.circular(
            AppRadius.pill,
          ),
        ),
      ),
    );
  }
}

class _JobsMessageState extends StatelessWidget {
  const _JobsMessageState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onActionPressed,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onActionPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 40,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            if (actionLabel != null &&
                onActionPressed != null) ...[
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: onActionPressed,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
