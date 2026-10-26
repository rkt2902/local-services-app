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
import 'agenda_controls.dart';
import 'agenda_decorations.dart';
import 'agenda_entry_card.dart';
import 'agenda_list_rows.dart';
import 'agenda_overlap.dart';
import 'agenda_skeleton.dart';

/// Agenda · Hoje (design H1 a H7): controlos do dia e a lista. Só o corpo da
/// tab Agenda; o cabeçalho "Trabalhos" e as tabs ficam no ecrã Trabalhos.
/// Não lê providers: a integração (`worker_agenda_tab.dart`) passa tudo
/// pronto e recebe as ações.
///
/// Os controlos ficam ativos enquanto carrega (H6); só a lista passa a
/// esqueleto.
class AgendaDayView extends StatefulWidget {
  const AgendaDayView({
    required this.dayKey,
    required this.dayLabel,
    required this.range,
    required this.isToday,
    required this.showProposals,
    required this.content,
    required this.onPreviousDay,
    required this.onNextDay,
    required this.onGoToToday,
    required this.onOpenCalendar,
    required this.onRangeChanged,
    required this.onShowProposalsChanged,
    required this.onRefresh,
    required this.onOpenEntry,
    required this.onStartJob,
    required this.onChooseTime,
    required this.onWhatsApp,
    required this.onMap,
    required this.onResolveOverlap,
    required this.onSearchWork,
    required this.onMarkAvailable,
    this.loading = false,
    this.errorMessage,
    this.offlineLabel,
    this.onRetry,
    this.onAddToAgenda,
    this.onChangeUnavailableDates,
    super.key,
  });

  /// "2026-10-28": muda = troca de dia (fade de 180 ms e scroll para agora).
  final String dayKey;

  /// "Hoje, terça 28 out".
  final String dayLabel;
  final AgendaRange range;

  /// O dia mostrado é hoje: sem botão "Hoje" e com scroll até agora.
  final bool isToday;
  final bool showProposals;

  /// Nulo enquanto não há dados (com [loading] ou [errorMessage]).
  final AgendaDayContentViewData? content;
  final bool loading;

  /// Erro sem dados guardados: estado de erro total (H7).
  final String? errorMessage;

  /// "Sem rede · dados das 08:12": erro ao atualizar, mas há dados de antes.
  final String? offlineLabel;

  final VoidCallback onPreviousDay;
  final VoidCallback onNextDay;
  final VoidCallback onGoToToday;
  final VoidCallback onOpenCalendar;
  final ValueChanged<AgendaRange> onRangeChanged;
  final ValueChanged<bool> onShowProposalsChanged;
  final Future<void> Function() onRefresh;
  final VoidCallback? onRetry;

  final ValueChanged<AgendaEntry> onOpenEntry;
  final ValueChanged<AgendaEntry> onStartJob;
  final ValueChanged<AgendaEntry> onChooseTime;
  final ValueChanged<AgendaEntry> onWhatsApp;
  final ValueChanged<AgendaEntry> onMap;

  /// Toque no título de um grupo: "Mudar a hora" de um deles.
  final ValueChanged<List<AgendaEntry>> onResolveOverlap;

  final VoidCallback onSearchWork;

  /// Nulo enquanto o formulário "Adicionar à agenda" não existe.
  final VoidCallback? onAddToAgenda;
  final ValueChanged<AgendaEntry>? onChangeUnavailableDates;

  /// "Já estou livre"; a confirmação fica na integração.
  final ValueChanged<AgendaEntry> onMarkAvailable;

  @override
  State<AgendaDayView> createState() => _AgendaDayViewState();
}

class _AgendaDayViewState extends State<AgendaDayView> {
  final GlobalKey _nowKey = GlobalKey();
  final GlobalKey _overlapKey = GlobalKey();

  Timer? _skeletonDelay;
  bool _refreshSkeleton = false;
  String? _scrolledToNowFor;

  static const _dayFade = Duration(milliseconds: 180);
  static const _refreshSkeletonAfter = Duration(milliseconds: 400);
  static const _swipeVelocity = 250.0;
  static const _rangeSelectorWidth = 200.0;

  @override
  void initState() {
    super.initState();
    _scheduleScrollToNow();
  }

  @override
  void didUpdateWidget(covariant AgendaDayView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dayKey != widget.dayKey ||
        oldWidget.content != widget.content) {
      _scheduleScrollToNow();
    }
  }

  @override
  void dispose() {
    _skeletonDelay?.cancel();
    super.dispose();
  }

  Duration _scrollDuration(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : AppMotionDuration.fast;

  /// Ao abrir hoje, uma vez por dia mostrado: a linha de agora a um terço
  /// do ecrã.
  void _scheduleScrollToNow() {
    if (!widget.isToday || widget.content == null) return;
    if (_scrolledToNowFor == widget.dayKey) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _nowKey.currentContext;
      if (target == null) return;
      _scrolledToNowFor = widget.dayKey;
      Scrollable.ensureVisible(
        target,
        alignment: 0.35,
        duration: _scrollDuration(context),
        curve: AppMotionCurve.standard,
      );
    });
  }

  void _scrollToOverlap() {
    final target = _overlapKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      alignment: 0.1,
      duration: _scrollDuration(context),
      curve: AppMotionCurve.standard,
    );
  }

  /// Puxar para baixo: o esqueleto só aparece se demorar mais de 400 ms,
  /// para não piscar.
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

  void _onSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < _swipeVelocity) return;
    velocity < 0 ? widget.onNextDay() : widget.onPreviousDay();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _controls(),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: _onSwipe,
            child: AppFadeThroughSwitcher(
              switchKey: widget.dayKey,
              duration: _dayFade,
              child: _body(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _controls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xxs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: AgendaPeriodNav(
              label: widget.dayLabel,
              onPrevious: widget.onPreviousDay,
              onNext: widget.onNextDay,
              onLabelTap: widget.onOpenCalendar,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xs),
            child: Row(
              children: [
                Flexible(
                  flex: 3,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        SizedBox(
                          width: _rangeSelectorWidth,
                          child: AgendaRangeSelector(
                            selected: widget.range,
                            onSelected: widget.onRangeChanged,
                          ),
                        ),
                        if (!widget.isToday) ...[
                          const SizedBox(width: AppSpacing.xs),
                          AgendaTodayButton(onPressed: widget.onGoToToday),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: AgendaProposalsToggle(
                      value: widget.showProposals,
                      onChanged: widget.onShowProposalsChanged,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final content = widget.content;
    if (_refreshSkeleton || (content == null && widget.loading)) {
      return const _DaySkeleton();
    }
    if (content == null) {
      return _Refreshable(
        onRefresh: _refresh,
        child: _CenteredScroll(
          child: AppEmptyState(
            icon: Icons.cloud_off_outlined,
            tone: AppStatusColor.cancelled,
            title: 'Não foi possível carregar a agenda',
            message: widget.errorMessage ?? 'Verifica a rede e tenta outra vez.',
            action: widget.onRetry == null
                ? null
                : ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: AppSizes.emptyActionMinWidth,
                      maxWidth: AppSizes.emptyActionMaxWidth,
                    ),
                    child: IntrinsicWidth(
                      child: PrimaryActionButton(
                        label: 'Tentar de novo',
                        icon: Icons.refresh_rounded,
                        onPressed: widget.onRetry,
                      ),
                    ),
                  ),
          ),
        ),
      );
    }
    if (content.isEmpty) {
      return _Refreshable(
        onRefresh: _refresh,
        child: _CenteredScroll(
          top: widget.offlineLabel == null
              ? null
              : _OfflineBanner(label: widget.offlineLabel!),
          child: _EmptyDay(
            isToday: widget.isToday,
            onSearchWork: widget.onSearchWork,
            onAddToAgenda: widget.onAddToAgenda,
          ),
        ),
      );
    }
    return _Refreshable(onRefresh: _refresh, child: _list(content));
  }

  Widget _list(AgendaDayContentViewData content) {
    final textTheme = Theme.of(context).textTheme;
    final unavailability = content.unavailability;
    final rows = <Widget>[];
    var entrance = 0;

    void add(Widget child, {double gap = AppSpacing.sm}) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: gap),
          child: AppStaggeredEntrance(index: entrance++, child: child),
        ),
      );
    }

    if (widget.offlineLabel != null) {
      add(_OfflineBanner(label: widget.offlineLabel!));
    }
    if (content.summaryLabel.isNotEmpty) {
      add(
        Text(
          content.summaryLabel,
          style: textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textStrong,
          ),
        ),
      );
    }
    if (unavailability != null) {
      add(
        _UnavailableDay(
          data: unavailability,
          onChangeDates: widget.onChangeUnavailableDates == null
              ? null
              : () => widget.onChangeUnavailableDates!(unavailability.source),
          onAvailable: () => widget.onMarkAvailable(unavailability.source),
        ),
      );
      if (content.items.isNotEmpty) {
        add(
          const AgendaOverlapNote(
            level: AgendaNoteLevel.strong,
            highlight: 'Tens trabalhos marcados neste dia.',
            message: ' Continuam de pé: trata deles ou avisa o cliente.',
          ),
        );
      }
    }

    for (final item in content.items) {
      switch (item.kind) {
        case AgendaDayItemKind.section:
          add(_SectionLabel(label: item.label!), gap: AppSpacing.xs);
        case AgendaDayItemKind.now:
          add(AgendaNowLine(key: _nowKey, timeLabel: item.label!));
        case AgendaDayItemKind.free:
          add(AgendaFreeTimeRow(label: item.label!, short: item.short));
        case AgendaDayItemKind.overlapAlert:
          add(
            AgendaOverlapBanner(label: item.label!, onView: _scrollToOverlap),
          );
        case AgendaDayItemKind.overlapGroup:
          final group = item.group!;
          add(
            AgendaOverlapStack(
              key: _overlapKey,
              label: group.label,
              onLabelTap: () => widget.onResolveOverlap([
                for (final e in group.entries) e.source,
              ]),
              children: [for (final e in group.entries) _card(e)],
            ),
          );
        case AgendaDayItemKind.entry:
          add(_card(item.entry!));
      }
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      children: rows,
    );
  }

  Widget _card(AgendaDayEntryViewData e) {
    final source = e.source;
    // No máximo 3 botões; os de dentro não abrem o detalhe.
    final actions = <AgendaCardAction>[
      if (e.showStart)
        AgendaCardAction(
          label: 'Iniciar',
          icon: Icons.play_arrow_rounded,
          primary: true,
          onPressed: () => widget.onStartJob(source),
        ),
      if (e.showChooseTime)
        AgendaCardAction(
          label: 'Marcar hora',
          icon: Icons.more_time_rounded,
          onPressed: () => widget.onChooseTime(source),
        ),
      if (e.showOpenProposal)
        AgendaCardAction(
          label: 'Ver proposta',
          icon: Icons.description_outlined,
          onPressed: () => widget.onOpenEntry(source),
        ),
      if (e.showWhatsApp)
        AgendaCardAction(
          label: 'WhatsApp',
          icon: Icons.chat_outlined,
          onPressed: () => widget.onWhatsApp(source),
        ),
      if (e.showMap)
        AgendaCardAction(
          label: 'Mapa',
          icon: Icons.map_outlined,
          onPressed: () => widget.onMap(source),
        ),
    ].take(3).toList();

    return AgendaEntryCard(
      data: AgendaEntryCardData(
        kind: e.kind,
        title: e.title,
        serviceIcon: e.serviceIcon,
        startLabel: e.startLabel,
        endLabel: e.endLabel,
        dayIndex: e.dayIndex,
        dayCount: e.dayCount,
        timeToArrange: e.timeToArrange,
        subtitle: e.subtitle,
        amountLabel: e.amountLabel,
        pill: e.pill,
        detailLabel: e.detailLabel,
        repeats: e.repeats,
        changedLabel: e.changedLabel,
        done: e.done,
        current: e.current,
        actions: actions,
        onTap: e.canOpen ? () => widget.onOpenEntry(source) : null,
      ),
    );
  }
}

/// Botão contornado da Agenda: cantos de campo e contorno verde claro, como
/// os botões dos cartões.
ButtonStyle _outlinedStyle(BuildContext context, {double? height}) =>
    OutlinedButton.styleFrom(
      foregroundColor: AppColors.primary,
      minimumSize: Size(0, height ?? AppSizes.headerIconButton),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      side: const BorderSide(color: AppColors.agendaAppBorder, width: 1.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      textStyle: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
    );

/// Pull-to-refresh sem spinner: o esqueleto (depois de 400 ms) é o sinal.
class _Refreshable extends StatelessWidget {
  const _Refreshable({required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator.noSpinner(onRefresh: onRefresh, child: child);
  }
}

/// Estado a meio do espaço, mas a deixar puxar para atualizar.
class _CenteredScroll extends StatelessWidget {
  const _CenteredScroll({required this.child, this.top});

  final Widget child;
  final Widget? top;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (top != null) ...[top!, const SizedBox(height: AppSpacing.lg)],
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tone = AppStatusColor.neutral;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: AppSizes.inlineIcon,
            color: tone.foreground,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: tone.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dia livre (H5): uma frase e dois caminhos.
class _EmptyDay extends StatelessWidget {
  const _EmptyDay({
    required this.isToday,
    required this.onSearchWork,
    this.onAddToAgenda,
  });

  final bool isToday;
  final VoidCallback onSearchWork;
  final VoidCallback? onAddToAgenda;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.wb_sunny_outlined,
      title: isToday ? 'Nada marcado para hoje' : 'Nada marcado neste dia',
      message: onAddToAgenda == null
          ? 'Há pedidos novos na tua zona.'
          : 'Há pedidos novos na tua zona. Ou junta um trabalho que '
                'arranjaste por fora.',
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
                style: _outlinedStyle(context, height: AppSizes.buttonHeight),
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

/// Dia indisponível (H4): bloco riscado com o que foi marcado e as duas
/// saídas.
class _UnavailableDay extends StatelessWidget {
  const _UnavailableDay({
    required this.data,
    required this.onAvailable,
    this.onChangeDates,
  });

  final AgendaDayUnavailabilityViewData data;
  final VoidCallback onAvailable;
  final VoidCallback? onChangeDates;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final buttonStyle = _outlinedStyle(context);

    return AgendaStripes(
      radius: AppRadius.card,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: AppSizes.rowIconBox,
                  height: AppSizes.rowIconBox,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.input),
                  ),
                  child: const Icon(
                    Icons.event_busy_outlined,
                    size: AppSizes.rowIcon,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.title,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textStrong,
                        ),
                      ),
                      Text(
                        data.subtitle,
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            const AgendaPillBadge(pill: AgendaCardPill.block),
            const SizedBox(height: AppSpacing.xl),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Marcaste este dia como indisponível.',
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    data.description,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      if (onChangeDates != null) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            style: buttonStyle,
                            onPressed: onChangeDates,
                            icon: const Icon(
                              Icons.edit_outlined,
                              size: AppSizes.inlineIcon,
                            ),
                            label: const Text('Mudar datas'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                      ],
                      Expanded(
                        child: OutlinedButton.icon(
                          style: buttonStyle,
                          onPressed: onAvailable,
                          icon: const Icon(
                            Icons.event_available_outlined,
                            size: AppSizes.inlineIcon,
                          ),
                          label: const Text('Já estou livre'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Esqueleto do dia (H6): resumo, um cartão completo, separador, outro.
class _DaySkeleton extends StatelessWidget {
  const _DaySkeleton();

  static const double _summaryWidth = 220;
  static const double _summaryHeight = 12;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: AppSkeletonShimmer(
            child: Container(
              width: _summaryWidth,
              height: _summaryHeight,
              decoration: BoxDecoration(
                color: AppColors.agendaNeutralSurface,
                borderRadius: BorderRadius.circular(AppSpacing.s6),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const AgendaEntrySkeleton(),
        const Divider(height: AppSpacing.lg, color: AppColors.divider),
        const AgendaEntrySkeleton(),
      ],
    );
  }
}
