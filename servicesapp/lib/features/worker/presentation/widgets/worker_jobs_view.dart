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
import 'package:servicesapp/core/widgets/app_tab_header.dart';
import 'package:servicesapp/core/widgets/home_notification_button.dart';

enum WorkerJobsTab { pending, scheduled, history }

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
    this.warningLabel,
    this.withdrawLabel,
    this.withdrawing = false,
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

  /// Choca com a Agenda (R1): "Coincide com Poda, Sintra, 09:00 a 12:00".
  /// Contorno âmbar e nota tocável que abre "Ver o dia".
  final String? warningLabel;

  /// "Retirar proposta"; nulo = sem botão (candidaturas, fechadas).
  final String? withdrawLabel;
  final bool withdrawing;
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

/// Tabs do ecrã Trabalhos (design A8): Agenda (Hoje, Semana, Mês), as
/// propostas e candidaturas por responder, e o histórico.
enum WorkerJobsSection { agenda, proposals, history }

/// Ecrã Trabalhos: cabeçalho, tabs e o conteúdo de cada uma. A Agenda chega
/// já montada ([agenda]); Propostas e Histórico são as listas do board.
class WorkerJobsScreen extends StatelessWidget {
  const WorkerJobsScreen({
    required this.selectedSection,
    required this.agenda,
    required this.pending,
    required this.history,
    required this.onSectionSelected,
    required this.onJobPressed,
    required this.onLoadMore,
    required this.onNotificationsPressed,
    required this.onColorsPressed,
    super.key,
    this.proposalsCount,
    this.unreadNotifications = 0,
    this.onRetry,
    this.onRefresh,
    this.highlightedJobId,
    this.onFindJobsPressed,
    this.onOpenDayPreview,
    this.onWithdraw,
  });

  final WorkerJobsSection selectedSection;

  /// Corpo da tab Agenda.
  final Widget agenda;

  /// Contador ao lado de "Propostas"; nulo ou 0 = sem contador.
  final int? proposalsCount;

  final WorkerJobsTabViewData pending;
  final WorkerJobsTabViewData history;

  /// Número no sino; 0 = sem número.
  final int unreadNotifications;
  final VoidCallback onNotificationsPressed;

  /// "Cores": folha "O que significam as cores".
  final VoidCallback onColorsPressed;

  /// CTA dos estados vazios ("Ver pedidos disponíveis").
  final VoidCallback? onFindJobsPressed;

  final ValueChanged<WorkerJobsSection> onSectionSelected;
  final ValueChanged<String> onJobPressed;

  /// Toque na nota de aviso de um cartão: "Ver o dia" com esta proposta.
  final ValueChanged<String>? onOpenDayPreview;

  /// "Retirar proposta": a integração pede confirmação e grava.
  final ValueChanged<String>? onWithdraw;

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
      onOpenDayPreview: onOpenDayPreview,
      onWithdraw: onWithdraw,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTabHeader(
              title: 'Trabalhos',
              actions: [
                if (selectedSection == WorkerJobsSection.agenda)
                  _ColorsButton(onPressed: onColorsPressed),
                HomeNotificationButton(
                  unreadCount: unreadNotifications,
                  onPressed: onNotificationsPressed,
                ),
              ],
              bottom: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                ),
                child: AppTabs(
                  items: [
                    const AppTabItem(label: 'Agenda'),
                    AppTabItem(label: 'Propostas', count: proposalsCount),
                    const AppTabItem(label: 'Histórico'),
                  ],
                  selectedIndex: selectedSection.index,
                  onSelected: (i) =>
                      onSectionSelected(WorkerJobsSection.values[i]),
                ),
              ),
            ),
            // IndexedStack e não um fade: cada tab guarda o scroll e as
            // listas podem atualizar em segundo plano sem recomeçar.
            Expanded(
              child: IndexedStack(
                index: selectedSection.index,
                children: [
                  agenda,
                  tab(WorkerJobsTab.pending, pending),
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

/// "Cores" no cabeçalho da Agenda: ícone com legenda por baixo.
class _ColorsButton extends StatelessWidget {
  const _ColorsButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'O que significam as cores',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.input),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppSizes.headerIconButton,
            minHeight: AppSizes.headerIconButton,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.palette_outlined,
                size: AppSizes.emphasisIcon,
                color: AppColors.textPrimary,
              ),
              ExcludeSemantics(
                child: Text(
                  'Cores',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
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
    this.onOpenDayPreview,
    this.onWithdraw,
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
  final ValueChanged<String>? onOpenDayPreview;
  final ValueChanged<String>? onWithdraw;

  @override
  State<_JobsTabContent> createState() => _JobsTabContentState();
}

/// Linha da lista: cabeçalho de mês ou cartão.
class _Row {
  const _Row.section(this.label) : item = null, entranceIndex = 0;
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
            child: SizedBox(height: constraints.maxHeight, child: emptyState),
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
            onWarningPressed: widget.onOpenDayPreview == null
                ? null
                : () => widget.onOpenDayPreview!(job.id),
            onWithdraw: widget.onWithdraw == null
                ? null
                : () => widget.onWithdraw!(job.id),
          ),
        );
        if (!job.animateEntrance) return card;
        return AppStaggeredEntrance(index: row.entranceIndex, child: card);
      },
    );

    if (widget.onRefresh == null) return list;

    return RefreshIndicator(onRefresh: widget.onRefresh!, child: list);
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
        icon: Icons.inbox_outlined,
        tone: AppStatusColor.neutral,
        title: 'Sem propostas à espera',
        message:
            'Quando enviares uma proposta ou te candidatares como ajudante, aparece aqui.',
        actionLabel: onFindJobsPressed == null ? null : 'Procurar trabalho',
        onAction: onFindJobsPressed,
      ),
      WorkerJobsTab.scheduled => AppEmptyState(
        icon: Icons.event_available_outlined,
        title: 'Nada agendado',
        message:
            'Quando um cliente aceitar a tua proposta, o trabalho aparece aqui.',
        actionLabel: onFindJobsPressed == null
            ? null
            : 'Ver pedidos disponíveis',
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
    this.onWarningPressed,
    this.onWithdraw,
  });

  final WorkerJobListItemViewData job;
  final bool highlighted;
  final VoidCallback onPressed;
  final VoidCallback? onWarningPressed;
  final VoidCallback? onWithdraw;

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
            final warned = job.warningLabel != null;
            // Com aviso de agenda o contorno fica âmbar e mais grosso (R1).
            final border = warned
                ? AppStatusColor.waiting.foreground
                : Color.lerp(
                    AppColors.divider,
                    AppStatusColor.waiting.foreground,
                    t,
                  )!;
            return Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: border, width: warned ? 2 : 1),
              ),
              child: child,
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
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
                        // Papel e estado por baixo do título, e não ao lado:
                        // ao lado roubavam a largura e cortavam a data, a
                        // hora e o preço.
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.xxs,
                          runSpacing: AppSpacing.xxs,
                          children: [
                            if (job.roleLabel != null)
                              _RoleChip(label: job.roleLabel!),
                            AppStatusBadge.fromPresentation(
                              presentation: job.status,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
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
                            maxLines: 1,
                            softWrap: false,
                            style: textTheme.bodyMedium?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (job.warningLabel != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _AgendaWarningNote(
                  label: job.warningLabel!,
                  onPressed: widget.onWarningPressed,
                ),
              ],
              if (job.withdrawLabel != null && widget.onWithdraw != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(
                    onPressed: job.withdrawing ? null : widget.onWithdraw,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppStatusColor.cancelled.foreground,
                      minimumSize: const Size(0, AppSizes.headerIconButton),
                      side: const BorderSide(
                        color: AppColors.divider,
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                      ),
                      textStyle: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(
                      job.withdrawing ? 'A retirar…' : job.withdrawLabel!,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Nota âmbar "Coincide com ..." (R1). Toque abre "Ver o dia" e não abre o
/// cartão (o InkWell de dentro fica com o gesto).
class _AgendaWarningNote extends StatelessWidget {
  const _AgendaWarningNote({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tone = AppStatusColor.waiting;
    return Material(
      color: tone.background,
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.input),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.s10,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_rounded,
                size: AppSizes.emphasisIcon,
                color: tone.foreground,
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ),
              if (onPressed != null) ...[
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  Icons.chevron_right_rounded,
                  size: AppSizes.emphasisIcon,
                  color: tone.foreground,
                  semanticLabel: 'Ver o dia',
                ),
              ],
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
          child: const AppSkeletonShimmer(child: _JobSkeletonCard()),
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
  const _SkeletonLine({required this.widthFactor});

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
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
    );
  }
}
