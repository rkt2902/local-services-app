import 'package:flutter/material.dart';

import 'package:servicesapp/core/theme/app_colors.dart';
import 'package:servicesapp/core/theme/app_motion_tokens.dart';
import 'package:servicesapp/core/theme/app_radius.dart';
import 'package:servicesapp/core/theme/app_sizes.dart';
import 'package:servicesapp/core/theme/app_spacing.dart';
import 'package:servicesapp/core/theme/app_status_color.dart';
import 'package:servicesapp/core/theme/app_status_presentation.dart';
import 'package:servicesapp/core/widgets/app_empty_state.dart';
import 'package:servicesapp/core/widgets/app_motion.dart';
import 'package:servicesapp/core/widgets/app_status_badge.dart';

enum WorkerJobsTab {
  pending,
  scheduled,
  history,
}

/// Uma entrada de "Os meus trabalhos" (design A2): proposta, candidatura a
/// ajudante ou trabalho. Tudo chega já formatado pela integração
/// (worker_jobs_screen.dart); este widget não consulta providers.
class WorkerJobListItemViewData {
  const WorkerJobListItemViewData({
    required this.id,
    required this.title,
    required this.serviceIcon,
    required this.metaLabel,
    required this.status,
    this.roleLabel,
    this.amountLabel,
    this.muted = false,
    this.animateEntrance = true,
  });

  /// Id da proposta ou da candidatura (`entry_id`).
  final String id;
  final String title;
  final IconData serviceIcon;

  /// "Hoje · 9:00 · Cascais", "12/10 · com Rui Costa", já formatado.
  final String metaLabel;

  /// Estado do trabalho; "Não selecionada" e afins só quando não houve
  /// trabalho para este jardineiro.
  final AppStatusPresentation status;

  /// "Ajudante": papel neste trabalho, não um estado.
  final String? roleLabel;

  /// "≈ 60 €" a verde por baixo da linha de detalhe.
  final String? amountLabel;

  /// Registos fechados sem trabalho concluído: tudo a cinzento.
  final bool muted;

  /// `false` nos itens que chegam por paginação (sem entrada escalonada).
  final bool animateEntrance;
}

class WorkerJobsSectionViewData {
  const WorkerJobsSectionViewData({required this.items, this.label});

  /// Mês no Histórico ("Outubro"); `null` sem cabeçalho.
  final String? label;
  final List<WorkerJobListItemViewData> items;
}

/// Estado de uma tab: cada uma carrega e pagina por si.
class WorkerJobsTabViewData {
  const WorkerJobsTabViewData({
    this.sections = const [],
    this.loading = false,
    this.errorMessage,
    this.canLoadMore = false,
    this.loadingMore = false,
  });

  final List<WorkerJobsSectionViewData> sections;
  final bool loading;
  final String? errorMessage;
  final bool canLoadMore;
  final bool loadingMore;

  bool get isEmpty => sections.every((s) => s.items.isEmpty);
}

class WorkerJobsScreen extends StatelessWidget {
  const WorkerJobsScreen({
    required this.selectedTab,
    required this.pendingTabLabel,
    required this.scheduledTabLabel,
    required this.historyTabLabel,
    required this.pending,
    required this.scheduled,
    required this.history,
    required this.onTabSelected,
    required this.onJobPressed,
    required this.onLoadMore,
    super.key,
    this.onRetry,
    this.onRefresh,
    this.highlightedJobId,
    this.onFindJobsPressed,
  });

  final WorkerJobsTab selectedTab;

  /// "Pendentes 3", "Agendados 4", "Histórico", já formatados.
  final String pendingTabLabel;
  final String scheduledTabLabel;
  final String historyTabLabel;

  final WorkerJobsTabViewData pending;
  final WorkerJobsTabViewData scheduled;
  final WorkerJobsTabViewData history;

  /// CTA dos estados vazios ("Ver pedidos disponíveis").
  final VoidCallback? onFindJobsPressed;

  final ValueChanged<WorkerJobsTab> onTabSelected;
  final ValueChanged<String> onJobPressed;

  /// Scroll infinito: pede a página seguinte da tab.
  final ValueChanged<WorkerJobsTab> onLoadMore;

  final VoidCallback? onRetry;
  final Future<void> Function()? onRefresh;

  /// Suporte para deep-link de notificações.
  ///
  /// A integração pode manter este ID ativo durante cerca de 1 segundo e
  /// depois limpá-lo.
  final String? highlightedJobId;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    Widget tab(WorkerJobsTab t, WorkerJobsTabViewData data) => _JobsTabContent(
          key: PageStorageKey<String>('worker_jobs_${t.name}'),
          tab: t,
          data: data,
          onRetry: onRetry,
          onRefresh: onRefresh,
          onJobPressed: onJobPressed,
          highlightedJobId: highlightedJobId,
          onLoadMore: data.canLoadMore ? () => onLoadMore(t) : null,
          onFindJobsPressed: onFindJobsPressed,
        );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                style: textTheme.displaySmall?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: _JobsTabs(
                labels: {
                  WorkerJobsTab.pending: pendingTabLabel,
                  WorkerJobsTab.scheduled: scheduledTabLabel,
                  WorkerJobsTab.history: historyTabLabel,
                },
                selectedTab: selectedTab,
                onSelected: onTabSelected,
              ),
            ),
            // IndexedStack e não um fade: cada tab guarda o scroll e as
            // listas podem atualizar em segundo plano sem recomeçar.
            Expanded(
              child: IndexedStack(
                index: selectedTab.index,
                children: [
                  tab(WorkerJobsTab.pending, pending),
                  tab(WorkerJobsTab.scheduled, scheduled),
                  tab(WorkerJobsTab.history, history),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Controlo segmentado igual ao de "Os meus pedidos" do cliente.
class _JobsTabs extends StatelessWidget {
  const _JobsTabs({
    required this.labels,
    required this.selectedTab,
    required this.onSelected,
  });

  final Map<WorkerJobsTab, String> labels;
  final WorkerJobsTab selectedTab;
  final ValueChanged<WorkerJobsTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.divider,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Row(
        children: [
          for (final t in WorkerJobsTab.values) ...[
            if (t.index > 0) const SizedBox(width: AppSpacing.xxs),
            Expanded(
              child: _TabButton(
                label: labels[t]!,
                selected: selectedTab == t,
                onPressed: () => onSelected(t),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.surface : AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.input),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.input),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xs,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(
                color:
                    selected ? AppColors.textPrimary : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
    required this.tab,
    required this.data,
    required this.onRetry,
    required this.onRefresh,
    required this.onJobPressed,
    required this.highlightedJobId,
    required this.onLoadMore,
    this.onFindJobsPressed,
    super.key,
  });

  final WorkerJobsTab tab;
  final WorkerJobsTabViewData data;
  final VoidCallback? onRetry;
  final Future<void> Function()? onRefresh;
  final ValueChanged<String> onJobPressed;
  final String? highlightedJobId;
  final VoidCallback? onLoadMore;
  final VoidCallback? onFindJobsPressed;

  @override
  State<_JobsTabContent> createState() => _JobsTabContentState();
}

/// Linha da lista: cabeçalho de mês ou cartão.
class _Row {
  const _Row.section(this.label)
      : item = null,
        entranceIndex = 0;
  const _Row.item(this.item, this.entranceIndex) : label = null;

  final String? label;
  final WorkerJobListItemViewData? item;
  final int entranceIndex;
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
    if (widget.onLoadMore == null || widget.data.loadingMore) return;
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

  List<_Row> _rows() {
    final rows = <_Row>[];
    var entranceIndex = 0;
    for (final section in widget.data.sections) {
      if (section.items.isEmpty) continue;
      final label = section.label?.trim() ?? '';
      if (label.isNotEmpty) rows.add(_Row.section(label));
      for (final item in section.items) {
        rows.add(_Row.item(item, entranceIndex++));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;

    if (data.loading) {
      return const _JobsSkeletonList();
    }

    if (data.errorMessage != null) {
      return _CenteredState(
        child: AppEmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Não foi possível carregar',
          message: data.errorMessage!,
          tone: AppStatusColor.cancelled,
          actionLabel: widget.onRetry == null ? null : 'Tentar novamente',
          onAction: widget.onRetry,
        ),
      );
    }

    if (data.isEmpty) {
      final emptyState = _EmptyForTab(
        tab: widget.tab,
        onFindJobsPressed: widget.onFindJobsPressed,
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

    final rows = _rows();
    final showFooter = widget.onLoadMore != null && data.loadingMore;

    final list = ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      itemCount: rows.length + (showFooter ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == rows.length) {
          return const Padding(
            padding: EdgeInsets.only(top: AppSpacing.xs),
            child: AppSkeletonShimmer(child: _JobSkeletonCard()),
          );
        }

        final row = rows[index];
        if (row.label != null) {
          return Padding(
            padding: EdgeInsets.only(
              top: index == 0 ? 0 : AppSpacing.sm,
              bottom: AppSpacing.xs,
            ),
            child: Text(
              row.label!.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          );
        }

        final job = row.item!;
        final card = Padding(
          key: _keyFor(job.id),
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _WorkerJobCard(
            job: job,
            highlighted: widget.highlightedJobId == job.id,
            onPressed: () => widget.onJobPressed(job.id),
          ),
        );
        if (!job.animateEntrance) return card;
        return AppStaggeredEntrance(index: row.entranceIndex, child: card);
      },
    );

    if (widget.onRefresh == null) return list;

    return RefreshIndicator(
      onRefresh: widget.onRefresh!,
      child: list,
    );
  }
}

class _EmptyForTab extends StatelessWidget {
  const _EmptyForTab({required this.tab, this.onFindJobsPressed});

  final WorkerJobsTab tab;
  final VoidCallback? onFindJobsPressed;

  @override
  Widget build(BuildContext context) {
    return _CenteredState(child: _state());
  }

  AppEmptyState _state() {
    return switch (tab) {
      WorkerJobsTab.pending => AppEmptyState(
          icon: Icons.send_outlined,
          title: 'Sem propostas pendentes',
          message:
              'As propostas que enviares e as candidaturas a ajudante aparecem aqui.',
          actionLabel:
              onFindJobsPressed == null ? null : 'Ver pedidos disponíveis',
          onAction: onFindJobsPressed,
        ),
      WorkerJobsTab.scheduled => AppEmptyState(
          icon: Icons.event_available_outlined,
          title: 'Nada agendado',
          message:
              'Quando um cliente aceitar a tua proposta, o trabalho aparece aqui.',
          actionLabel:
              onFindJobsPressed == null ? null : 'Ver pedidos disponíveis',
          onAction: onFindJobsPressed,
        ),
      WorkerJobsTab.history => const AppEmptyState(
          icon: Icons.history_rounded,
          title: 'Histórico vazio',
          message:
              'Os trabalhos concluídos, cancelados e não escolhidos ficam guardados aqui.',
          tone: AppStatusColor.neutral,
        ),
    };
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

/// Duração do realce de deep-link — bespoke (docs/motion_spec.md §4,
/// "Deep-link de notificação": "durante 1,3 s"). O desvanecer preenche TODA
/// esta janela (não fica sólido e só depois esbate rápido no fim) — quando
/// [worker_jobs_screen.dart] limpa `highlightedJobId` ao fim de 1,3 s, o
/// card já chegou naturalmente ao branco.
const _highlightFadeDuration = Duration(milliseconds: 1300);

class _WorkerJobCard extends StatefulWidget {
  const _WorkerJobCard({
    required this.job,
    required this.highlighted,
    required this.onPressed,
  });

  final WorkerJobListItemViewData job;
  final bool highlighted;
  final VoidCallback onPressed;

  @override
  State<_WorkerJobCard> createState() => _WorkerJobCardState();
}

class _WorkerJobCardState extends State<_WorkerJobCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _highlightController;
  bool _disableAnimations = false;
  bool _configured = false;

  @override
  void initState() {
    super.initState();
    _highlightController = AnimationController(
      vsync: this,
      duration: _highlightFadeDuration,
      value: widget.highlighted ? 1 : 0,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!_configured) {
      _configured = true;
      // Card já entra realçado (é o caso real de um deep-link): arranca o
      // desvanecer agora, não à espera de um didUpdateWidget que nunca vem.
      if (widget.highlighted && !_disableAnimations) _startFade();
    }
  }

  @override
  void didUpdateWidget(covariant _WorkerJobCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlighted == oldWidget.highlighted) return;
    if (widget.highlighted) {
      _highlightController.value = 1;
      if (!_disableAnimations) _startFade();
    } else {
      // Redução de movimento: sem fade progressivo (docs/motion_spec.md
      // §5) — o corte para o estado normal é instantâneo, aqui.
      _highlightController
        ..stop()
        ..value = 0;
    }
  }

  void _startFade() {
    _highlightController.animateTo(
      0,
      duration: _highlightFadeDuration,
      curve: AppMotionCurve.enter,
    );
  }

  @override
  void dispose() {
    _highlightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final job = widget.job;
    final muted = job.muted;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: widget.onPressed,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: AnimatedBuilder(
          animation: _highlightController,
          builder: (context, child) {
            final t = _highlightController.value;
            // Fundo âmbar claro (mesmo token dos badges "waiting") a
            // desvanecer para a superfície normal do card.
            final background = Color.lerp(
              muted ? AppColors.background : AppColors.surface,
              AppStatusColor.waiting.background,
              t,
            )!;
            final border = Color.lerp(
              AppColors.divider,
              AppStatusColor.waiting.foreground,
              t,
            )!;
            return Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: border),
              ),
              child: child,
            );
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ServiceIcon(icon: job.serviceIcon, muted: muted),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        color: muted
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      job.metaLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (job.amountLabel != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        job.amountLabel!,
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              // Papel e estado empilhados à direita, como no design.
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (job.roleLabel != null) ...[
                    _RoleChip(label: job.roleLabel!),
                    const SizedBox(height: AppSpacing.xxs),
                  ],
                  AppStatusBadge.fromPresentation(presentation: job.status),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceIcon extends StatelessWidget {
  const _ServiceIcon({required this.icon, required this.muted});

  final IconData icon;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSizes.rowIconBox,
      height: AppSizes.rowIconBox,
      decoration: BoxDecoration(
        color: muted
            ? AppStatusColor.neutral.background
            : AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: AppSizes.rowIcon,
        color: muted ? AppStatusColor.neutral.foreground : AppColors.primary,
      ),
    );
  }
}

/// Chip "Ajudante": papel neste trabalho, não estado (cores `info`).
class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppStatusColor.info.background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: textTheme.labelSmall?.copyWith(
          color: AppStatusColor.info.foreground,
          fontWeight: FontWeight.w600,
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
        AppSpacing.xs,
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
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppSizes.rowIconBox,
            height: AppSizes.rowIconBox,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(AppRadius.input),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonLine(widthFactor: 0.55),
                SizedBox(height: AppSpacing.xs),
                _SkeletonLine(widthFactor: 0.8),
                SizedBox(height: AppSpacing.xs),
                _SkeletonLine(widthFactor: 0.25),
              ],
            ),
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
        height: AppSpacing.sm,
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
