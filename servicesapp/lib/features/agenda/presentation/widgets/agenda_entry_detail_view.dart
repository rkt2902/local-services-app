import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion_tokens.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/app_status_badge.dart';
import '../../../../core/widgets/app_whatsapp_button.dart';
import '../../../../core/widgets/bottom_actions_bar.dart';
import '../../../../core/widgets/primary_action_button.dart';
import '../agenda_entry_detail_view_data.dart';
import 'agenda_decorations.dart';
import 'agenda_entry_card.dart';
import 'agenda_entry_editor_view.dart';
import 'agenda_overlap.dart';

/// Ação do menu "⋯" (D2).
enum AgendaDetailMenuAction { edit, delete }

/// Detalhe de um trabalho de fora da app ou de uma indisponibilidade
/// (design A8E, D1 a D5). Sem estado: o host decide a série, as
/// confirmações e a gravação, e diz quando mostrar o visto e a faixa
/// "Marcado como feito · Desfazer".
class AgendaEntryDetailView extends StatelessWidget {
  const AgendaEntryDetailView({
    super.key,
    required this.data,
    required this.onBack,
    required this.onEdit,
    required this.onDelete,
    required this.onPrimary,
    required this.onCancel,
    required this.onWhatsApp,
    required this.onOpenMap,
    required this.onViewDay,
    this.successMessage,
    this.bannerMessage,
    this.onUndoBanner,
  });

  final AgendaDetailViewData data;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<AgendaDetailPrimary> onPrimary;
  final VoidCallback onCancel;
  final VoidCallback onWhatsApp;
  final VoidCallback onOpenMap;
  final VoidCallback onViewDay;

  /// Visto verde breve, só depois de o servidor confirmar.
  final String? successMessage;

  /// "Marcado como feito" com "Desfazer", durante 6 s (o host conta).
  final String? bannerMessage;
  final VoidCallback? onUndoBanner;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      if (data.overlap case final overlap?)
        AgendaOverlapNote(
          level: AgendaNoteLevel.strong,
          highlight: '${overlap.title} ',
          message: overlap.detail,
          onViewDay: onViewDay,
        ),
      _WhenCard(data: data.when),
      if (data.person case final person?)
        _PersonCard(data: person, onWhatsApp: onWhatsApp),
      if (data.place case final place?)
        _PlaceCard(data: place, onOpenMap: onOpenMap),
      if (data.valueNotes case final valueNotes?)
        _ValueNotesCard(data: valueNotes),
      if (data.unavailableInfo case final info?)
        AgendaOverlapNote(level: AgendaNoteLevel.sameDay, message: info),
    ];

    return Stack(
      children: [
        Column(
          children: [
            _TopBar(
              showMenu: !data.isUnavailable,
              enabled: !data.submitting,
              onBack: onBack,
              onEdit: onEdit,
              onDelete: onDelete,
            ),
            Expanded(
              child: AppFadeThroughSwitcher(
                switchKey: data.state,
                child: ListView(
                  key: ValueKey(data.state),
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  children: [
                    _Hero(data: data),
                    for (final (i, card) in cards.indexed)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.sm,
                          AppSpacing.md,
                          0,
                        ),
                        child: AppStaggeredEntrance(
                          index: i,
                          child: Opacity(
                            opacity: data.isMuted && i > 0 ? 0.86 : 1,
                            child: card,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: AppMotionDuration.fast,
              curve: AppMotionCurve.standard,
              alignment: Alignment.bottomCenter,
              child: bannerMessage == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        0,
                        AppSpacing.md,
                        AppSpacing.xs,
                      ),
                      child: AgendaSavedBanner(
                        message: bannerMessage!,
                        onUndo: onUndoBanner,
                      ),
                    ),
            ),
            _Footer(
              data: data,
              onPrimary: onPrimary,
              onCancel: onCancel,
              onEdit: onEdit,
              onDelete: onDelete,
            ),
          ],
        ),
        if (successMessage != null)
          Positioned.fill(
            child: AppSuccessFeedback(visible: true, message: successMessage!),
          ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.showMenu,
    required this.enabled,
    required this.onBack,
    required this.onEdit,
    required this.onDelete,
  });

  final bool showMenu;
  final bool enabled;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final danger = AppStatusColor.cancelled.foreground;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
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
          const Spacer(),
          if (showMenu)
            PopupMenuButton<AgendaDetailMenuAction>(
              enabled: enabled,
              tooltip: 'Mais opções',
              icon: const Icon(
                Icons.more_horiz_rounded,
                color: AppColors.textPrimary,
              ),
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              onSelected: (action) => switch (action) {
                AgendaDetailMenuAction.edit => onEdit(),
                AgendaDetailMenuAction.delete => onDelete(),
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: AgendaDetailMenuAction.edit,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.edit_outlined,
                        color: AppColors.textStrong,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'Editar',
                        style: textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                // Apagar sempre por último, a vermelho.
                PopupMenuItem(
                  value: AgendaDetailMenuAction.delete,
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, color: danger),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'Apagar',
                        style: textTheme.bodyLarge?.copyWith(
                          color: danger,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.data});

  final AgendaDetailViewData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final done = data.state == AgendaDetailState.done;
    final success = AppStatusColor.success;

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s20,
        AppSpacing.xxs,
        AppSpacing.s20,
        AppSpacing.s20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppSizes.detailHeroBox,
            height: AppSizes.detailHeroBox,
            decoration: BoxDecoration(
              color: data.isUnavailable
                  ? AppColors.surface
                  : done
                  ? success.background
                  : AppColors.agendaNeutralSurface,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            alignment: Alignment.center,
            child: Icon(
              done ? Icons.check_circle_rounded : data.heroIcon,
              size: AppSizes.detailHeroIcon,
              color: done ? success.foreground : AppColors.textStrong,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            data.title,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: done ? AppColors.textStrong : AppColors.textPrimary,
              decoration: data.state == AgendaDetailState.cancelled
                  ? TextDecoration.lineThrough
                  : null,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              if (data.showSourceBadge)
                const AgendaPillBadge(pill: AgendaCardPill.external),
              AppStatusBadge.fromPresentation(presentation: data.status),
            ],
          ),
          if (data.metaLabel case final meta?) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              meta,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: done
                    ? success.foreground
                    : AppStatusColor.cancelled.foreground,
              ),
            ),
          ],
        ],
      ),
    );

    // Indisponível: riscas, como na Agenda (D5).
    if (data.isUnavailable) {
      return AgendaStripes(radius: 0, child: content);
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: content,
    );
  }
}

/// Cartão branco com o título em maiúsculas pequenas ("QUANDO").
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.s14,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          child,
        ],
      ),
    );
  }
}

class _WhenCard extends StatelessWidget {
  const _WhenCard({required this.data});

  final AgendaDetailWhenViewData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return _InfoCard(
      title: 'Quando',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.primary,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (data.secondary case final secondary?) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data.secondaryIcon case final icon?) ...[
                  Icon(
                    icon,
                    size: AppSizes.infoRowIcon,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.s6),
                ],
                Expanded(
                  child: Text(
                    secondary,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.textStrong,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (data.exceptionLabel case final exception?) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                const Icon(
                  Icons.edit_calendar_outlined,
                  size: AppSizes.inlineIcon,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  exception,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.data, required this.onWhatsApp});

  final AgendaDetailPersonViewData data;
  final VoidCallback onWhatsApp;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return _InfoCard(
      title: 'Quem',
      child: Row(
        children: [
          Expanded(
            child: Text(
              data.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Só com telefone; nunca um botão vazio nem "Ligar".
          if (data.hasWhatsApp) ...[
            const SizedBox(width: AppSpacing.sm),
            AppWhatsAppButton(onPressed: onWhatsApp, compact: true),
          ],
        ],
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.data, required this.onOpenMap});

  final AgendaDetailPlaceViewData data;
  final VoidCallback onOpenMap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return _InfoCard(
      title: 'Onde',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.address,
            style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (data.canOpenMap) ...[
            const SizedBox(height: AppSpacing.s10),
            OutlinedButton.icon(
              onPressed: onOpenMap,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, AppSizes.linkButtonHeight),
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.agendaAppBorder),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.input),
                ),
              ),
              icon: const Icon(Icons.map_outlined, size: AppSizes.infoRowIcon),
              label: const Text('Abrir no mapa'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ValueNotesCard extends StatelessWidget {
  const _ValueNotesCard({required this.data});

  final AgendaDetailValueNotesViewData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return _InfoCard(
      title: data.sectionTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.value case final value?)
            Text(
              value,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          if (data.value != null && data.notes != null)
            const SizedBox(height: AppSpacing.s6),
          if (data.notes case final notes?)
            Text(
              notes,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textStrong,
                height: 1.4,
              ),
            ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.data,
    required this.onPrimary,
    required this.onCancel,
    required this.onEdit,
    required this.onDelete,
  });

  final AgendaDetailViewData data;
  final ValueChanged<AgendaDetailPrimary> onPrimary;
  final VoidCallback onCancel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final danger = AppStatusColor.cancelled.foreground;
    final busy = data.submitting;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.card),
    );
    final buttonText = textTheme.bodyLarge?.copyWith(
      fontWeight: FontWeight.w700,
    );

    // Indisponível (D5): Apagar + Editar, sem "Marcar como feito".
    if (data.isUnavailable) {
      return BottomActionsBar(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onDelete,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
                    foregroundColor: danger,
                    side: const BorderSide(
                      color: AppColors.agendaExternalBorder,
                    ),
                    shape: shape,
                    textStyle: buttonText,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Apagar'),
                ),
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  onPressed: busy ? null : onEdit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.surface,
                    shape: shape,
                    textStyle: buttonText,
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar'),
                ),
              ),
            ],
          ),
        ],
      );
    }

    final primary = data.primary;
    return BottomActionsBar(
      children: [
        if (primary != null)
          primary.filled
              ? PrimaryActionButton(
                  label: primary.label,
                  icon: primary.icon,
                  isLoading: busy,
                  onPressed: () => onPrimary(primary.kind),
                )
              : OutlinedButton.icon(
                  onPressed: busy ? null : () => onPrimary(primary.kind),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(
                      color: AppColors.agendaExternalBorder,
                    ),
                    shape: shape,
                    textStyle: buttonText,
                  ),
                  icon: busy
                      ? const SizedBox.square(
                          dimension: AppSizes.inlineSpinner,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(primary.icon),
                  label: Text(primary.label),
                ),
        if (data.showCancel) ...[
          const SizedBox(height: AppSpacing.xxs),
          TextButton(
            onPressed: busy ? null : onCancel,
            style: TextButton.styleFrom(
              foregroundColor: danger,
              minimumSize: const Size.fromHeight(AppSizes.compactButtonHeight),
              textStyle: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Cancelar este trabalho'),
          ),
        ],
      ],
    );
  }
}
