import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/primary_action_button.dart';
import 'agenda_controls.dart';

/// Peças comuns às vistas Hoje e Semana: controlos do período, puxar para
/// atualizar, faixa sem rede, erro e botão contornado.

/// Período com setas por cima; por baixo o seletor Hoje · Semana · Mês, o
/// botão "Hoje" (só fora do período atual) e "Mostrar propostas". Igual nas
/// duas vistas, para o cabeçalho não saltar ao trocar.
class AgendaViewControls extends StatelessWidget {
  const AgendaViewControls({
    required this.periodLabel,
    required this.range,
    required this.showToday,
    required this.showProposals,
    required this.onPrevious,
    required this.onNext,
    required this.onOpenCalendar,
    required this.onRangeChanged,
    required this.onGoToToday,
    required this.onShowProposalsChanged,
    super.key,
  });

  /// "Hoje, terça 28 out" ou "27 out a 2 nov".
  final String periodLabel;
  final AgendaRange range;
  final bool showToday;
  final bool showProposals;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onOpenCalendar;
  final ValueChanged<AgendaRange> onRangeChanged;
  final VoidCallback onGoToToday;
  final ValueChanged<bool> onShowProposalsChanged;

  static const _rangeSelectorWidth = 200.0;

  @override
  Widget build(BuildContext context) {
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
              label: periodLabel,
              onPrevious: onPrevious,
              onNext: onNext,
              onLabelTap: onOpenCalendar,
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
                            selected: range,
                            onSelected: onRangeChanged,
                          ),
                        ),
                        if (showToday) ...[
                          const SizedBox(width: AppSpacing.xs),
                          AgendaTodayButton(onPressed: onGoToToday),
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
                      value: showProposals,
                      onChanged: onShowProposalsChanged,
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
}

/// Botão contornado da Agenda: cantos de campo e contorno verde claro, como
/// os botões dos cartões.
ButtonStyle agendaOutlinedButtonStyle(BuildContext context, {double? height}) =>
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
class AgendaRefreshable extends StatelessWidget {
  const AgendaRefreshable({
    required this.onRefresh,
    required this.child,
    super.key,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator.noSpinner(onRefresh: onRefresh, child: child);
  }
}

/// Estado a meio do espaço, mas a deixar puxar para atualizar.
class AgendaCenteredScroll extends StatelessWidget {
  const AgendaCenteredScroll({required this.child, this.top, super.key});

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
                if (top != null) ...[
                  top!,
                  const SizedBox(height: AppSpacing.lg),
                ],
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Sem rede · dados das 08:12": erro ao atualizar, com dados de antes.
class AgendaOfflineBanner extends StatelessWidget {
  const AgendaOfflineBanner({required this.label, super.key});

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

/// Erro sem dados guardados (H7): nuvem riscada e "Tentar de novo".
class AgendaLoadError extends StatelessWidget {
  const AgendaLoadError({this.message, this.onRetry, super.key});

  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.cloud_off_outlined,
      tone: AppStatusColor.cancelled,
      title: 'Não foi possível carregar a agenda',
      message: message ?? 'Verifica a rede e tenta outra vez.',
      action: onRetry == null
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
                  onPressed: onRetry,
                ),
              ),
            ),
    );
  }
}
