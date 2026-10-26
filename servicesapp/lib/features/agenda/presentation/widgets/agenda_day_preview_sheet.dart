import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion_tokens.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/widgets/app_motion.dart';
import '../agenda_day_preview_view_data.dart';
import 'agenda_decorations.dart';
import 'agenda_entry_card.dart';
import 'agenda_list_rows.dart';
import 'agenda_overlap.dart';
import 'agenda_skeleton.dart';

/// Folha "Ver o dia" (A8F, V1 a V3): só para ver. Setas e deslizar mudam o
/// dia; nada se toca nem se grava. Fechar (botão, tocar fora ou puxar para
/// baixo) volta ao formulário tal como estava.
///
/// Sem [data] nem [errorMessage] mostra o esqueleto.
class AgendaDayPreviewSheet extends StatefulWidget {
  const AgendaDayPreviewSheet({
    required this.dayLabel,
    required this.onPreviousDay,
    required this.onNextDay,
    required this.onClose,
    this.data,
    this.errorMessage,
    this.onRetry,
    super.key,
  });

  /// "Sexta, 30 out". Separado de [data] para o cabeçalho não piscar ao
  /// carregar outro mês.
  final String dayLabel;
  final AgendaDayPreviewViewData? data;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback onPreviousDay;
  final VoidCallback onNextDay;
  final VoidCallback onClose;

  /// Altura máxima, em fração do ecrã.
  static const double maxHeightFactor = 0.7;

  /// Velocidade mínima do deslizar para mudar de dia.
  static const double _swipeVelocity = 250;

  @override
  State<AgendaDayPreviewSheet> createState() => _AgendaDayPreviewSheetState();
}

class _AgendaDayPreviewSheetState extends State<AgendaDayPreviewSheet> {
  final _ghostKey = GlobalKey();
  String? _scrolledFor;

  @override
  void initState() {
    super.initState();
    _scheduleGhostScroll();
  }

  @override
  void didUpdateWidget(AgendaDayPreviewSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleGhostScroll();
  }

  /// Ao abrir, e ao voltar ao dia do formulário, o fantasma fica à vista.
  void _scheduleGhostScroll() {
    final data = widget.data;
    if (data == null || !data.hasGhost) {
      if (data != null) _scrolledFor = null;
      return;
    }
    if (_scrolledFor == data.dayKey) return;
    _scrolledFor = data.dayKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _ghostKey.currentContext;
      if (!mounted || target == null) return;
      final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      Scrollable.ensureVisible(
        target,
        alignment: 0.25,
        duration: reduce ? Duration.zero : AppMotionDuration.fast,
        curve: AppMotionCurve.standard,
      );
    });
  }

  void _onSwipe(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    if (v.abs() < AgendaDayPreviewSheet._swipeVelocity) return;
    v < 0 ? widget.onNextDay() : widget.onPreviousDay();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final data = widget.data;
    final maxHeight =
        MediaQuery.sizeOf(context).height *
        AgendaDayPreviewSheet.maxHeightFactor;

    final Widget content;
    final Object switchKey;
    if (widget.errorMessage != null) {
      switchKey = 'error';
      content = _PreviewError(
        message: widget.errorMessage!,
        onRetry: widget.onRetry,
      );
    } else if (data == null) {
      switchKey = 'loading';
      content = const _PreviewSkeleton();
    } else {
      switchKey = data.dayKey;
      content = _Timeline(data: data, ghostKey: _ghostKey);
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: AppSizes.sheetHandleWidth,
                  height: AppSizes.sheetHandleHeight,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  IconButton(
                    onPressed: widget.onPreviousDay,
                    tooltip: 'Dia anterior',
                    icon: const Icon(
                      Icons.chevron_left_rounded,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Expanded(
                    child: Semantics(
                      header: true,
                      liveRegion: true,
                      child: Text(
                        widget.dayLabel,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onNextDay,
                    tooltip: 'Dia seguinte',
                    icon: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Flexible(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragEnd: _onSwipe,
                  child: AppFadeThroughSwitcher(
                    switchKey: switchKey,
                    duration: AppMotionDuration.fast,
                    child: content,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton(
                onPressed: widget.onClose,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
                  backgroundColor: AppColors.agendaNeutralSurface,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.input),
                  ),
                  textStyle: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Fechar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.data, required this.ghostKey});

  final AgendaDayPreviewViewData data;
  final GlobalKey ghostKey;

  Widget _item(AgendaPreviewItem item) {
    return switch (item) {
      AgendaPreviewSectionItem(:final label) => _SectionLabel(label: label),
      AgendaPreviewFreeItem(:final label, :final short) => AgendaFreeTimeRow(
        label: label,
        short: short,
      ),
      AgendaPreviewGhostItem() => _GhostBlock(key: ghostKey, item: item),
      AgendaPreviewEntryItem(:final entry, :final conflict) => _ConflictRail(
        show: conflict,
        child: AgendaWeekEntryRow(
          kind: entry.kind,
          title: entry.title,
          startLabel: entry.startLabel,
          endLabel: entry.endLabel,
          subtitle: entry.subtitle,
          repeats: entry.repeats,
          timeToArrange: entry.timeToArrange,
          dayIndex: entry.dayIndex,
          dayCount: entry.dayCount,
          pill: entry.pill,
          done: entry.done,
        ),
      ),
      AgendaPreviewGroupItem(:final label, :final children) =>
        AgendaOverlapStack(
          label: label,
          children: [for (final child in children) _item(child)],
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    void add(Widget child) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: AppSpacing.xs));
      rows.add(AppStaggeredEntrance(index: rows.length ~/ 2, child: child));
    }

    for (final item in data.items) {
      add(_item(item));
    }
    final empty = data.empty;
    if (empty != null) add(_EmptyNote(data: empty));

    final list = SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
    // A frase fica sempre à vista, mesmo com o scroll até ao fantasma.
    final label = data.assessmentLabel;
    if (data.assessment == AgendaPreviewAssessment.none || label == null) {
      return list;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppStaggeredEntrance(
          index: 0,
          child: _AssessmentBanner(assessment: data.assessment, label: label),
        ),
        const SizedBox(height: AppSpacing.sm),
        Flexible(child: list),
      ],
    );
  }
}

/// Frase de cima: cabe (success), choca (waiting), pouco intervalo (info),
/// proposta enviada (neutro).
class _AssessmentBanner extends StatelessWidget {
  const _AssessmentBanner({required this.assessment, required this.label});

  final AgendaPreviewAssessment assessment;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (AppStatusColor tone, IconData icon) = switch (assessment) {
      AgendaPreviewAssessment.conflict => (
        AppStatusColor.waiting,
        Icons.warning_rounded,
      ),
      AgendaPreviewAssessment.tight => (
        AppStatusColor.info,
        Icons.info_outline_rounded,
      ),
      AgendaPreviewAssessment.tentative => (
        AppStatusColor.neutral,
        Icons.hourglass_top_rounded,
      ),
      _ => (AppStatusColor.success, Icons.check_circle_outline_rounded),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s14,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: tone.background,
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: AppSizes.rowIcon, color: tone.foreground),
            const SizedBox(width: AppSpacing.s10),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tone.foreground,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// O que se está a marcar: tracejado verde, nunca tocável.
class _GhostBlock extends StatelessWidget {
  const _GhostBlock({required this.item, super.key});

  final AgendaPreviewGhostItem item;

  @override
  Widget build(BuildContext context) {
    final warning = AppStatusColor.waiting.foreground;
    return Semantics(
      label: item.conflict ? '${item.label}. Choca com outro.' : item.label,
      excludeSemantics: true,
      child: AgendaDashedBorder(
        radius: AppRadius.input,
        color: AppColors.primary,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppSizes.dateFieldMinHeight,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s14,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.edit_calendar_outlined,
                size: AppSizes.emphasisIcon,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Text(
                  item.label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryPressed,
                  ),
                ),
              ),
              if (item.conflict) ...[
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  Icons.warning_rounded,
                  size: AppSizes.emphasisIcon,
                  color: warning,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Faixa âmbar à esquerda de uma entrada de dia todo que choca.
class _ConflictRail extends StatelessWidget {
  const _ConflictRail({required this.show, required this.child});

  final bool show;
  final Widget child;

  static const double _barWidth = 4;

  @override
  Widget build(BuildContext context) {
    if (!show) return child;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: _barWidth,
            decoration: BoxDecoration(
              color: AppColors.agendaOverlapBar,
              borderRadius: BorderRadius.circular(_barWidth),
            ),
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// "Nada mais neste dia": parte da lista, não ocupa a folha toda.
class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.data});

  final AgendaPreviewEmptyViewData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        children: [
          const Icon(
            Icons.event_available_outlined,
            size: AppSizes.emptyIcon,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            data.body,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewSkeleton extends StatelessWidget {
  const _PreviewSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      physics: NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgendaEntrySkeleton(compact: true),
          SizedBox(height: AppSpacing.xs),
          AgendaEntrySkeleton(compact: true),
          SizedBox(height: AppSpacing.xs),
          AgendaEntrySkeleton(compact: true),
        ],
      ),
    );
  }
}

class _PreviewError extends StatelessWidget {
  const _PreviewError({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: AppSizes.emptyIcon,
              color: AppStatusColor.cancelled.foreground,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Não foi possível carregar este dia',
              textAlign: TextAlign.center,
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar de novo'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
