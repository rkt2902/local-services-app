import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion_tokens.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/primary_action_button.dart';
import '../../data/agenda_entry_model.dart';
import '../agenda_day_view_data.dart';
import 'agenda_controls.dart';
import 'agenda_decorations.dart';
import 'agenda_entry_card.dart';
import 'agenda_entry_editor_view.dart';
import 'agenda_list_rows.dart';
import 'agenda_overlap.dart';
import 'agenda_skeleton.dart';
import 'agenda_view_parts.dart';

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
    this.focusOverlap = false,
    this.errorMessage,
    this.offlineLabel,
    this.onRetry,
    this.onAddToAgenda,
    this.onChangeUnavailableDates,
    this.highlightSourceId,
    this.savedMessage,
    this.onUndoSaved,
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

  /// Veio do "Ver o dia" da Semana: ao abrir, desliza até aos trabalhos que
  /// coincidem em vez da linha de agora.
  final bool focusOverlap;

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

  /// "Adicionar à agenda" no dia vazio; nulo esconde o botão.
  final VoidCallback? onAddToAgenda;
  final ValueChanged<AgendaEntry>? onChangeUnavailableDates;

  /// Entrada acabada de guardar (F8B): cartão realçado e scroll até ele.
  final String? highlightSourceId;

  /// "Guardado na agenda" no topo, com "Desfazer" se houver [onUndoSaved].
  final String? savedMessage;
  final VoidCallback? onUndoSaved;

  /// "Já estou livre"; a confirmação fica na integração.
  final ValueChanged<AgendaEntry> onMarkAvailable;

  @override
  State<AgendaDayView> createState() => _AgendaDayViewState();
}

class _AgendaDayViewState extends State<AgendaDayView> {
  // Uma chave por dia: durante o fade o dia anterior ainda está na árvore.
  final Map<String, GlobalKey> _nowKeys = {};
  final Map<String, GlobalKey> _overlapKeys = {};

  GlobalKey get _nowKey =>
      _nowKeys.putIfAbsent(widget.dayKey, () => GlobalKey());
  GlobalKey get _overlapKey =>
      _overlapKeys.putIfAbsent(widget.dayKey, () => GlobalKey());
  final Map<String, GlobalKey> _highlightKeys = {};
  GlobalKey get _highlightKey =>
      _highlightKeys.putIfAbsent(widget.dayKey, () => GlobalKey());

  /// Já se deslizou até este cartão realçado.
  String? _scrolledToHighlight;

  Timer? _skeletonDelay;
  bool _refreshSkeleton = false;
  String? _scrolledToNowFor;

  static const _dayFade = Duration(milliseconds: 180);
  static const _refreshSkeletonAfter = Duration(milliseconds: 400);
  static const _swipeVelocity = 250.0;

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
    _scheduleScrollToHighlight();
  }

  /// Depois de guardar no formulário: desliza até ao cartão novo, quando
  /// ele já estiver na lista.
  void _scheduleScrollToHighlight() {
    final id = widget.highlightSourceId;
    if (id == null || _scrolledToHighlight == id) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _scrolledToHighlight == id) return;
      final target = _highlightKey.currentContext;
      if (target == null) return;
      _scrolledToHighlight = id;
      Scrollable.ensureVisible(
        target,
        alignment: 0.3,
        duration: _scrollDuration(context),
        curve: AppMotionCurve.standard,
      );
    });
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

  /// Ao abrir um dia, uma vez: a linha de agora a um terço do ecrã (hoje)
  /// ou, vindo do "Ver o dia" da Semana, os trabalhos que coincidem.
  void _scheduleScrollToNow() {
    if (widget.content == null) return;
    if (widget.highlightSourceId != null) return;
    if (!widget.isToday && !widget.focusOverlap) return;
    if (_scrolledToNowFor == widget.dayKey) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = widget.focusOverlap
          ? _overlapKey.currentContext
          : _nowKey.currentContext;
      if (target == null) return;
      _scrolledToNowFor = widget.dayKey;
      Scrollable.ensureVisible(
        target,
        alignment: widget.focusOverlap ? 0.1 : 0.35,
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
    return AgendaViewControls(
      periodLabel: widget.dayLabel,
      range: widget.range,
      showToday: !widget.isToday,
      showProposals: widget.showProposals,
      onPrevious: widget.onPreviousDay,
      onNext: widget.onNextDay,
      onOpenCalendar: widget.onOpenCalendar,
      onRangeChanged: widget.onRangeChanged,
      onGoToToday: widget.onGoToToday,
      onShowProposalsChanged: widget.onShowProposalsChanged,
    );
  }

  Widget _body() {
    final content = widget.content;
    if (_refreshSkeleton || (content == null && widget.loading)) {
      return const _DaySkeleton();
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
          top: _topBanners(),
          child: _EmptyDay(
            isToday: widget.isToday,
            onSearchWork: widget.onSearchWork,
            onAddToAgenda: widget.onAddToAgenda,
          ),
        ),
      );
    }
    return AgendaRefreshable(onRefresh: _refresh, child: _list(content));
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
      add(AgendaOfflineBanner(label: widget.offlineLabel!));
    }
    if (widget.savedMessage != null) {
      add(
        AgendaSavedBanner(
          message: widget.savedMessage!,
          onUndo: widget.onUndoSaved,
        ),
      );
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

  /// Faixas por cima do dia vazio: sem rede e "Guardado na agenda".
  Widget? _topBanners() {
    final offline = widget.offlineLabel;
    final saved = widget.savedMessage;
    if (offline == null && saved == null) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (offline != null) AgendaOfflineBanner(label: offline),
        if (offline != null && saved != null)
          const SizedBox(height: AppSpacing.sm),
        if (saved != null)
          AgendaSavedBanner(message: saved, onUndo: widget.onUndoSaved),
      ],
    );
  }

  Widget _card(AgendaDayEntryViewData e) {
    final source = e.source;
    final highlighted =
        widget.highlightSourceId != null &&
        source.sourceId == widget.highlightSourceId;
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

    final card = AgendaEntryCard(
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
        highlighted: highlighted,
        actions: actions,
        onTap: e.canOpen ? () => widget.onOpenEntry(source) : null,
      ),
    );
    return highlighted ? KeyedSubtree(key: _highlightKey, child: card) : card;
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
    final buttonStyle = agendaOutlinedButtonStyle(context);

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
