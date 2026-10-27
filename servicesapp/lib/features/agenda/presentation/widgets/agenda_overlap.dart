import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';

/// Cartões que coincidem, empilhados com a faixa âmbar (A4, solução B):
/// mantêm a largura toda e os botões; o título diz o intervalo que se cruza.
class AgendaOverlapStack extends StatelessWidget {
  const AgendaOverlapStack({
    required this.label,
    required this.children,
    this.onLabelTap,
    super.key,
  });

  /// "Coincidem das 09:30 às 11:00".
  final String label;
  final List<Widget> children;

  /// Toque no título: "Mudar a hora" de um deles.
  final VoidCallback? onLabelTap;

  static const double _barWidth = 4;

  @override
  Widget build(BuildContext context) {
    final tone = AppStatusColor.waiting;
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: onLabelTap,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xxs,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_rounded,
                          size: AppSizes.emphasisIcon,
                          color: tone.foreground,
                        ),
                        const SizedBox(width: AppSpacing.s6),
                        Expanded(
                          child: Text(
                            label,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: tone.foreground,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                for (final child in children) ...[
                  const SizedBox(height: AppSpacing.xs),
                  child,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Nível da nota de sobreposição nos formulários (A5).
enum AgendaNoteLevel {
  /// As horas cruzam-se (tom waiting).
  strong,

  /// Mesmo dia sem hora (tom info).
  sameDay,

  /// Pouco intervalo (tom info, ícone de temporizador).
  shortGap,

  /// Coincide com uma proposta enviada (neutro).
  tentative,
}

/// Nota por baixo do campo de data/hora. Nunca bloqueia o botão de enviar;
/// "Ver o dia" abre a folha com o Hoje desse dia.
class AgendaOverlapNote extends StatelessWidget {
  const AgendaOverlapNote({
    required this.level,
    required this.message,
    this.highlight,
    this.onViewDay,
    super.key,
  });

  final AgendaNoteLevel level;

  /// Texto a seguir a [highlight]: ", Cascais, 09:00 a 11:00".
  final String message;

  /// Parte a negrito no início: "Coincide com Corte de relva".
  final String? highlight;

  final VoidCallback? onViewDay;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final (Color bg, Color fg, IconData icon) = switch (level) {
      AgendaNoteLevel.strong => (
        AppStatusColor.waiting.background,
        AppStatusColor.waiting.foreground,
        Icons.warning_rounded,
      ),
      AgendaNoteLevel.sameDay => (
        AppStatusColor.info.background,
        AppStatusColor.info.foreground,
        Icons.info_outline_rounded,
      ),
      AgendaNoteLevel.shortGap => (
        AppStatusColor.info.background,
        AppStatusColor.info.foreground,
        Icons.timer_outlined,
      ),
      AgendaNoteLevel.tentative => (
        AppColors.agendaNeutralSurface,
        AppColors.textStrong,
        Icons.hourglass_top_rounded,
      ),
    };

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s14,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: AppSizes.rowIcon, color: fg),
            const SizedBox(width: AppSpacing.s10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    if (highlight != null)
                      TextSpan(
                        text: highlight,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    TextSpan(text: message),
                  ],
                ),
                style: textTheme.bodyMedium?.copyWith(color: fg, height: 1.4),
              ),
            ),
            if (onViewDay != null) ...[
              const SizedBox(width: AppSpacing.xs),
              InkWell(
                onTap: onViewDay,
                borderRadius: BorderRadius.circular(AppRadius.input),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxs),
                  child: Text(
                    'Ver o dia',
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Disponibilidade junto à data de um pedido (A5). Só o jardineiro a vê.
enum AgendaAvailability { free, busyDay, overlap }

class AgendaAvailabilityChip extends StatelessWidget {
  const AgendaAvailabilityChip({
    required this.availability,
    required this.label,
    this.onPressed,
    super.key,
  });

  final AgendaAvailability availability;

  /// "Estás livre", "Já tens 2 trabalhos neste dia", "Coincide com um
  /// trabalho".
  final String label;

  /// Abre a folha "Ver o dia".
  final VoidCallback? onPressed;

  static const double _height = 36;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, IconData icon) = switch (availability) {
      AgendaAvailability.free => (
        AppColors.primaryContainer,
        AppColors.primary,
        Icons.event_available,
      ),
      AgendaAvailability.busyDay => (
        AppStatusColor.info.background,
        AppStatusColor.info.foreground,
        Icons.event_note_outlined,
      ),
      AgendaAvailability.overlap => (
        AppStatusColor.waiting.background,
        AppStatusColor.waiting.foreground,
        Icons.warning_rounded,
      ),
    };

    return Semantics(
      button: onPressed != null,
      child: Material(
        color: bg,
        shape: const StadiumBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const StadiumBorder(),
          child: Container(
            height: _height,
            padding: const EdgeInsets.only(
              left: AppSpacing.s10,
              right: AppSpacing.s14,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: AppSizes.inlineIcon, color: fg),
                const SizedBox(width: AppSpacing.s6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Aviso no topo do Hoje quando há horas que se cruzam (H2). "Ver" desliza
/// até ao grupo; na Semana, "Ver o dia" abre o Hoje desse dia.
class AgendaOverlapBanner extends StatelessWidget {
  const AgendaOverlapBanner({
    required this.label,
    required this.onView,
    this.actionLabel = 'Ver',
    this.actionIcon = Icons.arrow_downward_rounded,
    super.key,
  });

  /// "2 trabalhos ao mesmo tempo às 14:00".
  final String label;
  final VoidCallback onView;

  /// Na Semana: "Ver o dia", sem seta (abre o Hoje desse dia).
  final String actionLabel;
  final IconData? actionIcon;

  @override
  Widget build(BuildContext context) {
    final tone = AppStatusColor.waiting;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s14,
        AppSpacing.xxs,
        AppSpacing.xxs,
        AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_rounded,
            size: AppSizes.emphasisIcon,
            color: tone.foreground,
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text(
                label,
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: tone.foreground,
                ),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onView,
            iconAlignment: IconAlignment.end,
            style: TextButton.styleFrom(
              foregroundColor: tone.foreground,
              minimumSize: const Size(0, AppSizes.headerIconButton),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10),
            ),
            icon: actionIcon == null
                ? null
                : Icon(actionIcon, size: AppSizes.inlineIcon),
            label: Text(
              actionLabel,
              style: textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: tone.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
