import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion_tokens.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/primary_action_button.dart';
import '../../data/agenda_entry_model.dart';
import '../agenda_day_view_data.dart';
import '../agenda_week_view_data.dart';
import 'agenda_controls.dart';
import 'agenda_day_cells.dart';
import 'agenda_overlap.dart';
import 'agenda_skeleton.dart';
import 'agenda_view_parts.dart';

/// Agenda · Semana (design S1 a S3): faixa dos 7 dias e a lista de todos os
/// dias por ordem. Só o corpo da tab Agenda, como o Hoje. Não lê providers:
/// a integração (`worker_agenda_tab.dart`) passa tudo pronto.
///
/// A faixa e a lista andam juntas: tocar num dia desliza a lista até ele, e
/// deslizar a lista muda o dia preenchido.
class AgendaWeekView extends StatefulWidget {
  const AgendaWeekView({
    required this.weekKey,
    required this.rangeLabel,
    required this.isCurrentWeek,
    required this.showProposals,
    required this.days,
    required this.content,
    required this.onPreviousWeek,
    required this.onNextWeek,
    required this.onGoToCurrentWeek,
    required this.onOpenCalendar,
    required this.onRangeChanged,
    required this.onShowProposalsChanged,
    required this.onRefresh,
    required this.onOpenEntry,
    required this.onOpenDay,
    required this.onOpenDayAtConflict,
    required this.onResolveOverlap,
    required this.onSelectedDayChanged,
    required this.onSearchWork,
    this.initialDay,
    this.loading = false,
    this.errorMessage,
    this.offlineLabel,
    this.onRetry,
    this.onAddToAgenda,
    this.onAddToAgendaOnDay,
    super.key,
  });

  /// "2026-10-26" (a segunda): muda = troca de semana (fade de 180 ms).
  final String weekKey;

  /// "27 out a 2 nov".
  final String rangeLabel;

  /// Sem botão "Hoje" na semana atual.
  final bool isCurrentWeek;
  final bool showProposals;

  /// A faixa: existe mesmo a carregar (só faltam os pontos).
  final List<AgendaWeekDayViewData> days;

  /// Nulo enquanto não há dados (com [loading] ou [errorMessage]).
  final AgendaWeekContentViewData? content;

  /// Dia preenchido ao abrir a semana e onde a lista começa: hoje na
  /// semana atual. Ignorado na semana livre.
  final DateTime? initialDay;
  final bool loading;
  final String? errorMessage;
  final String? offlineLabel;

  final VoidCallback onPreviousWeek;
  final VoidCallback onNextWeek;
  final VoidCallback onGoToCurrentWeek;
  final VoidCallback onOpenCalendar;
  final ValueChanged<AgendaRange> onRangeChanged;
  final ValueChanged<bool> onShowProposalsChanged;
  final Future<void> Function() onRefresh;
  final VoidCallback? onRetry;

  /// Toque num cartão com detalhe (trabalho, proposta).
  final ValueChanged<AgendaEntry> onOpenEntry;

  /// Abre o Hoje nesse dia: cabeçalho do dia e entradas sem detalhe (fora
  /// da app, indisponível).
  final ValueChanged<DateTime> onOpenDay;

  /// "Ver o dia" do aviso: o Hoje desse dia, já nos que coincidem.
  final ValueChanged<DateTime> onOpenDayAtConflict;

  /// Toque no título de um grupo: "Mudar a hora" de um deles.
  final ValueChanged<List<AgendaEntry>> onResolveOverlap;

  /// O dia preenchido mudou (toque ou scroll), para o Hoje abrir nele.
  final ValueChanged<DateTime> onSelectedDayChanged;
  final VoidCallback onSearchWork;

  /// "Adicionar à agenda" (semana livre) e o "+" das linhas livres; nulos
  /// escondem os botões.
  final VoidCallback? onAddToAgenda;
  final ValueChanged<DateTime>? onAddToAgendaOnDay;

  @override
  State<AgendaWeekView> createState() => _AgendaWeekViewState();
}

class _AgendaWeekViewState extends State<AgendaWeekView> {
  /// Chaves dos dias da semana mostrada. Novas a cada semana: durante o
  /// fade a semana anterior ainda está na árvore.
  final Map<DateTime, GlobalKey> _sectionKeys = {};

  DateTime? _selected;
  String? _positionedFor;
  bool _programmaticScroll = false;

  Timer? _skeletonDelay;
  bool _refreshSkeleton = false;

  static const _weekFade = Duration(milliseconds: 180);
  static const _dayScroll = Duration(milliseconds: 300);
  static const _refreshSkeletonAfter = Duration(milliseconds: 400);
  static const _swipeVelocity = 250.0;

  /// Uma secção conta como "a do topo" até este tanto abaixo do topo.
  static const _topSlack = 24.0;

  @override
  void initState() {
    super.initState();
    _positionAtInitialDay();
  }

  @override
  void didUpdateWidget(covariant AgendaWeekView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.weekKey != widget.weekKey) {
      _sectionKeys.clear();
      _positionedFor = null;
      _selected = null;
    }
    _positionAtInitialDay();
    // Calendário com um dia da mesma semana: desliza até ele.
    final day = widget.initialDay;
    if (oldWidget.weekKey == widget.weekKey &&
        day != oldWidget.initialDay &&
        day != null &&
        day != _selected &&
        _selected != null) {
      _selected = day;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollTo(day, duration: _duration(_dayScroll));
      });
    }
  }

  @override
  void dispose() {
    _skeletonDelay?.cancel();
    super.dispose();
  }

  GlobalKey _keyFor(DateTime day) =>
      _sectionKeys.putIfAbsent(day, () => GlobalKey());

  Duration _duration(Duration normal) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : normal;

  /// Ao abrir uma semana com dados, uma vez: o dia inicial preenchido e a
  /// lista a começar nele (os dias antes ficam por cima).
  void _positionAtInitialDay() {
    final content = widget.content;
    if (content == null || _positionedFor == widget.weekKey) return;
    _positionedFor = widget.weekKey;
    if (content.isEmpty) {
      _selected = null;
      return;
    }
    final initial = widget.initialDay;
    _selected = initial != null && content.days.any((d) => d.date == initial)
        ? initial
        : content.days.first.date;
    final day = _selected!;
    if (day == content.days.first.date) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollTo(day, duration: Duration.zero);
    });
  }

  Future<void> _scrollTo(DateTime day, {required Duration duration}) async {
    final target = _sectionKeys[day]?.currentContext;
    if (target == null) return;
    _programmaticScroll = true;
    try {
      await Scrollable.ensureVisible(
        target,
        duration: duration,
        curve: AppMotionCurve.standard,
      );
    } finally {
      _programmaticScroll = false;
    }
  }

  void _select(DateTime day) {
    if (_selected != day) {
      setState(() => _selected = day);
      widget.onSelectedDayChanged(day);
    }
  }

  void _onDayTap(DateTime day) {
    final content = widget.content;
    if (content == null) return;
    if (content.isEmpty) {
      // Semana livre: o dia serve para marcar alguma coisa nele.
      final add = widget.onAddToAgendaOnDay;
      add == null ? widget.onOpenDay(day) : add(day);
      return;
    }
    _select(day);
    _scrollTo(day, duration: _duration(_dayScroll));
  }

  /// Scroll à mão: o dia preenchido é o último cujo cabeçalho já passou o
  /// topo da lista.
  bool _onScroll(ScrollNotification notification) {
    if (_programmaticScroll || notification is! ScrollUpdateNotification) {
      return false;
    }
    final viewport = notification.context?.findRenderObject();
    final content = widget.content;
    if (viewport is! RenderBox || content == null) return false;
    final top = viewport.localToGlobal(Offset.zero).dy + _topSlack;

    DateTime? current;
    for (final day in content.days) {
      final box = _sectionKeys[day.date]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      if (box.localToGlobal(Offset.zero).dy <= top) {
        current = day.date;
      } else {
        break;
      }
    }
    // No fim da lista os últimos dias não chegam ao topo: fica o último.
    final metrics = notification.metrics;
    if (metrics.pixels >= metrics.maxScrollExtent - 1) {
      current = content.days.last.date;
    }
    _select(current ?? content.days.first.date);
    return false;
  }

  /// Puxar para baixo: o esqueleto só aparece se demorar mais de 400 ms.
  Future<void> _refresh() async {
    _skeletonDelay?.cancel();
    _skeletonDelay = Timer(_refreshSkeletonAfter, () {
      if (mounted) setState(() => _refreshSkeleton = true);
    });
    try {
      await widget.onRefresh();
    } finally {
      _skeletonDelay?.cancel();
      if (mounted && _refreshSkeleton) {
        setState(() => _refreshSkeleton = false);
      }
    }
  }

  void _onStripSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < _swipeVelocity) return;
    velocity < 0 ? widget.onNextWeek() : widget.onPreviousWeek();
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    final showSummary =
        content != null &&
        !_refreshSkeleton &&
        content.summaryLabel.isNotEmpty &&
        !content.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AgendaViewControls(
          periodLabel: widget.rangeLabel,
          range: AgendaRange.week,
          showToday: !widget.isCurrentWeek,
          showProposals: widget.showProposals,
          onPrevious: widget.onPreviousWeek,
          onNext: widget.onNextWeek,
          onOpenCalendar: widget.onOpenCalendar,
          onRangeChanged: widget.onRangeChanged,
          onGoToToday: widget.onGoToCurrentWeek,
          onShowProposalsChanged: widget.onShowProposalsChanged,
        ),
        Expanded(
          child: AppFadeThroughSwitcher(
            switchKey: widget.weekKey,
            duration: _weekFade,
            child: Column(
              key: ValueKey(widget.weekKey),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragEnd: _onStripSwipe,
                  child: _DayStrip(
                    days: widget.days,
                    selected: _selected,
                    onDayTap: _onDayTap,
                  ),
                ),
                if (showSummary)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      0,
                      AppSpacing.md,
                      AppSpacing.xs,
                    ),
                    child: Text(
                      content.summaryLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textStrong,
                      ),
                    ),
                  ),
                // Fixos por cima da lista: a semana atual abre em hoje e o
                // aviso não pode ficar escondido nos dias de cima.
                if (_hasList && widget.offlineLabel != null)
                  _fixed(AgendaOfflineBanner(label: widget.offlineLabel!)),
                if (_hasList && content!.overlap != null)
                  _fixed(
                    AgendaOverlapBanner(
                      label: content.overlap!.label,
                      actionLabel: 'Ver o dia',
                      actionIcon: null,
                      onView: () =>
                          widget.onOpenDayAtConflict(content.overlap!.day),
                    ),
                  ),
                Expanded(child: _body()),
              ],
            ),
          ),
        ),
      ],
    );
  }

  bool get _hasList =>
      !_refreshSkeleton && widget.content != null && !widget.content!.isEmpty;

  Widget _fixed(Widget child) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      0,
      AppSpacing.md,
      AppSpacing.xs,
    ),
    child: child,
  );

  Widget _body() {
    final content = widget.content;
    if (_refreshSkeleton || (content == null && widget.loading)) {
      return const _WeekSkeleton();
    }
    if (content == null) {
      return AgendaRefreshable(
        onRefresh: _refresh,
        child: AgendaCenteredScroll(
          child: AgendaLoadError(
            message: widget.errorMessage,
            onRetry: widget.onRetry,
          ),
        ),
      );
    }
    if (content.isEmpty) {
      return AgendaRefreshable(
        onRefresh: _refresh,
        child: AgendaCenteredScroll(
          top: widget.offlineLabel == null
              ? null
              : AgendaOfflineBanner(label: widget.offlineLabel!),
          child: _EmptyWeek(
            rangeLabel: widget.rangeLabel,
            onSearchWork: widget.onSearchWork,
            onAddToAgenda: widget.onAddToAgenda,
          ),
        ),
      );
    }
    return AgendaRefreshable(
      onRefresh: _refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: _list(content),
      ),
    );
  }

  Widget _list(AgendaWeekContentViewData content) {
    // Todos os dias montados (são 7): o toque na faixa precisa de chegar a
    // qualquer um, mesmo fora do ecrã.
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < content.sections.length; i++)
            KeyedSubtree(
              key: _keyFor(content.sections[i].date),
              child: AppStaggeredEntrance(
                index: i,
                child: _Section(
                  section: content.sections[i],
                  onOpenEntry: (e) => e.canOpen
                      ? widget.onOpenEntry(e.source)
                      : widget.onOpenDay(content.sections[i].date),
                  onOpenDay: () => widget.onOpenDay(content.sections[i].date),
                  onResolveOverlap: widget.onResolveOverlap,
                  onAdd: widget.onAddToAgendaOnDay == null
                      ? null
                      : () => widget.onAddToAgendaOnDay!(
                          content.sections[i].date,
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// --- Faixa dos 7 dias -------------------------------------------------------

class _DayStrip extends StatelessWidget {
  const _DayStrip({
    required this.days,
    required this.selected,
    required this.onDayTap,
  });

  final List<AgendaWeekDayViewData> days;
  final DateTime? selected;
  final ValueChanged<DateTime> onDayTap;

  static const double _cellHeight = 76;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s10,
        AppSpacing.xs,
        AppSpacing.s10,
        AppSpacing.s10,
      ),
      child: Row(
        children: [
          for (var i = 0; i < days.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.s6),
            Expanded(
              child: AgendaDayCell(
                day: days[i],
                selected: days[i].date == selected,
                onTap: () => onDayTap(days[i].date),
                height: _cellHeight,
                showWeekday: true,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// --- Lista ------------------------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({
    required this.section,
    required this.onOpenEntry,
    required this.onOpenDay,
    required this.onResolveOverlap,
    this.onAdd,
  });

  final AgendaWeekSectionViewData section;
  final ValueChanged<AgendaDayEntryViewData> onOpenEntry;
  final VoidCallback onOpenDay;
  final ValueChanged<List<AgendaEntry>> onResolveOverlap;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    if (section.isFree) {
      return _FreeDayRow(section: section, onAdd: onAdd);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(section: section, onTap: onOpenDay),
          AgendaDayItemsList(
            items: section.items,
            onOpenEntry: onOpenEntry,
            onResolveOverlap: onResolveOverlap,
          ),
        ],
      ),
    );
  }
}

/// "Terça, 28 out · 3 trabalhos [Hoje] ⚠". Toque: abre esse dia no Hoje.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section, required this.onTap});

  final AgendaWeekSectionViewData section;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxs,
          AppSpacing.s10,
          AppSpacing.xxs,
          AppSpacing.xs,
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xxs,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: section.label),
                  if (section.countLabel != null)
                    TextSpan(
                      text: ' · ${section.countLabel}',
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
              style: textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            if (section.isToday) const _TodayTag(),
            if (section.hasOverlap)
              Icon(
                Icons.warning_rounded,
                size: AppSizes.inlineIcon,
                color: AppStatusColor.waiting.foreground,
                semanticLabel: 'Trabalhos que coincidem',
              ),
          ],
        ),
      ),
    );
  }
}

class _TodayTag extends StatelessWidget {
  const _TodayTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.primary, width: 1.5),
      ),
      child: Text(
        'Hoje',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

/// "Domingo, 2 nov · Livre ----- (+)". Com [onAdd], toque abre "Adicionar à
/// agenda" nesse dia.
class _FreeDayRow extends StatelessWidget {
  const _FreeDayRow({required this.section, this.onAdd});

  final AgendaWeekSectionViewData section;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onAdd,
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.headerIconButton),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          child: Row(
            children: [
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: section.label),
                      TextSpan(
                        text: ' · Livre',
                        style: textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textStrong,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Divider(color: AppColors.agendaExternalBorder),
              ),
              if (onAdd != null) ...[
                const SizedBox(width: AppSpacing.sm),
                const Icon(
                  Icons.add_circle_outline_rounded,
                  color: AppColors.primary,
                  semanticLabel: 'Adicionar à agenda',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Semana livre (S3): uma frase e dois caminhos.
class _EmptyWeek extends StatelessWidget {
  const _EmptyWeek({
    required this.rangeLabel,
    required this.onSearchWork,
    this.onAddToAgenda,
  });

  final String rangeLabel;
  final VoidCallback onSearchWork;
  final VoidCallback? onAddToAgenda;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.event_available_outlined,
      title: 'Semana livre',
      message: 'Ainda não tens nada de $rangeLabel.',
      action: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrimaryActionButton(
            label: 'Procurar trabalho',
            icon: Icons.search_rounded,
            onPressed: onSearchWork,
          ),
          if (onAddToAgenda != null) ...[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: AppSizes.buttonHeight,
              child: OutlinedButton.icon(
                style: agendaOutlinedButtonStyle(
                  context,
                  height: AppSizes.buttonHeight,
                ),
                onPressed: onAddToAgenda,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Adicionar à agenda'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Esqueleto da lista (A9): dois dias com cabeçalho e linhas compactas.
class _WeekSkeleton extends StatelessWidget {
  const _WeekSkeleton();

  static const double _headerWidth = 150;
  static const double _headerHeight = 14;

  @override
  Widget build(BuildContext context) {
    Widget header() => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AppSkeletonShimmer(
          child: Container(
            width: _headerWidth,
            height: _headerHeight,
            decoration: BoxDecoration(
              color: AppColors.agendaNeutralSurface,
              borderRadius: BorderRadius.circular(AppSpacing.s6),
            ),
          ),
        ),
      ),
    );

    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      children: [
        for (var day = 0; day < 2; day++) ...[
          header(),
          const AgendaEntrySkeleton(compact: true),
          const SizedBox(height: AppSpacing.xs),
          const AgendaEntrySkeleton(compact: true),
        ],
      ],
    );
  }
}
