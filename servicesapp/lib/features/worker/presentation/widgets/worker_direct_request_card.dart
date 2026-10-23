import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/widgets/app_initials_avatar.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/primary_action_button.dart';

/// Pedido direto do lado do jardineiro (design A5, 5a a 5c): etiqueta
/// "Pedido só para ti", cartão com o histórico com o cliente e o painel
/// depois de dizer "Não posso desta vez". Tom `info` (o "Urgente" usa o
/// `cancelled`). O prazo vem do servidor; aqui só se mostra.

/// Etiqueta "Pedido só para ti · faltam 18 h".
class WorkerDirectRequestTag extends StatelessWidget {
  const WorkerDirectRequestTag({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    const tone = AppStatusColor.info;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.assignment_ind_outlined,
            size: AppSizes.metaIcon,
            color: tone.foreground,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tone.foreground,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class WorkerDirectHistoryViewData {
  const WorkerDirectHistoryViewData({
    required this.clientInitial,
    required this.label,
    this.clientAvatarUrl,
  });

  final String clientInitial;
  final String? clientAvatarUrl;

  /// "Já trabalhaste com Marta a 12/09/2026, Corte de relva, 12,00 €/h".
  final String label;
}

class WorkerDirectRequestViewData {
  const WorkerDirectRequestViewData({
    required this.tagLabel,
    required this.explanationLabel,
    required this.history,
    this.titleLabel,
    this.outsideAreaLabel,
    this.noticeLabel,
  });

  final String tagLabel;

  /// "Marta pediu-te orçamento pelo teu cartão" (A7); `null` sem título.
  final String? titleLabel;
  final String explanationLabel;

  /// "Fora da tua área, a 12 km": o pedido aparece na mesma (A7).
  final String? outsideAreaLabel;

  /// Depois do prazo ("Marta vai decidir se mostra o pedido a outros
  /// jardineiros."); `null` enquanto a reserva corre.
  final String? noticeLabel;

  /// `null` dentro do `data`: sem histórico, fica só a etiqueta e a
  /// explicação.
  final AsyncValue<WorkerDirectHistoryViewData?> history;
}

/// Cartão no topo do detalhe da oportunidade (5b).
class WorkerDirectRequestCard extends StatelessWidget {
  const WorkerDirectRequestCard({
    super.key,
    required this.data,
    this.onRetryHistory,
  });

  final WorkerDirectRequestViewData data;
  final VoidCallback? onRetryHistory;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkerDirectRequestTag(label: data.tagLabel),
          const SizedBox(height: AppSpacing.sm),
          if (data.titleLabel != null) ...[
            Text(
              data.titleLabel!,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
          ],
          Text(
            data.explanationLabel,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (data.outsideAreaLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _DirectNote(
              icon: Icons.near_me_outlined,
              tone: AppStatusColor.waiting,
              title: data.outsideAreaLabel!,
              description:
                  'Podes enviar proposta na mesma. Conta com a deslocação.',
            ),
          ],
          if (data.noticeLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _DirectNote(
              icon: Icons.schedule_outlined,
              tone: AppStatusColor.neutral,
              title: data.noticeLabel!,
            ),
          ],
          AppFadeThroughSwitcher(
            switchKey: data.history.isLoading
                ? 'loading'
                : data.history.hasError
                    ? 'error'
                    : 'data',
            child: data.history.when(
              loading: () => const _HistorySkeleton(),
              error: (_, _) => _HistoryError(onRetry: onRetryHistory),
              data: (history) => history == null
                  ? const SizedBox.shrink()
                  : _History(history: history),
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectNote extends StatelessWidget {
  const _DirectNote({
    required this.icon,
    required this.tone,
    required this.title,
    this.description,
  });

  final IconData icon;
  final AppStatusColor tone;
  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppSizes.infoRowIcon, color: tone.foreground),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.labelMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    description!,
                    style: textTheme.labelMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.history});

  final WorkerDirectHistoryViewData history;

  @override
  Widget build(BuildContext context) {
    return Column(
        children: [
          const _HistoryDivider(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppInitialsAvatar(
                initial: history.clientInitial,
                avatarUrl: history.clientAvatarUrl,
                radius: AppSizes.directAvatarRadius,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  history.label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ],
    );
  }
}

class _HistoryDivider extends StatelessWidget {
  const _HistoryDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Divider(height: 1, color: AppColors.divider),
    );
  }
}

class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double widthFactor) => FractionallySizedBox(
          widthFactor: widthFactor,
          child: AppSkeletonShimmer(
            child: Container(
              height: AppSpacing.sm,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _HistoryDivider(),
        bar(1),
        const SizedBox(height: AppSpacing.xs),
        bar(0.6),
      ],
    );
  }
}

class _HistoryError extends StatelessWidget {
  const _HistoryError({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        const _HistoryDivider(),
        Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: AppSizes.infoRowIcon,
              color: AppStatusColor.cancelled.foreground,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                'Não foi possível carregar o histórico com este cliente.',
                style: textTheme.labelMedium?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                child: Text(
                  'Tentar novamente',
                  style: textTheme.labelMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Botões do fundo do pedido direto (5b, 5c): "Enviar proposta" e "Não
/// posso desta vez"; enquanto avisa o cliente, os dois ficam bloqueados.
class WorkerDirectRequestActions extends StatelessWidget {
  const WorkerDirectRequestActions({
    super.key,
    required this.onSendProposalPressed,
    required this.onDeclinePressed,
    this.declining = false,
  });

  final VoidCallback onSendProposalPressed;
  final VoidCallback onDeclinePressed;
  final bool declining;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryActionButton(
          label: 'Enviar proposta',
          onPressed: declining ? null : onSendProposalPressed,
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: AppSizes.compactButtonHeight,
          child: OutlinedButton(
            onPressed: declining ? null : onDeclinePressed,
            style: OutlinedButton.styleFrom(
              backgroundColor: AppColors.surface,
              disabledBackgroundColor: AppColors.surface,
              side: const BorderSide(color: AppColors.divider),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
            ),
            child: Text(
              declining ? 'A avisar...' : 'Não posso desta vez',
              style: textTheme.bodyMedium?.copyWith(
                color: declining
                    ? AppStatusColor.neutral.foreground
                    : AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Depois de "Não posso desta vez" (5c, "Recusou").
class WorkerDirectDeclinedPanel extends StatelessWidget {
  const WorkerDirectDeclinedPanel({
    super.key,
    required this.message,
    required this.onSeeOtherJobsPressed,
  });

  final String message;
  final VoidCallback onSeeOtherJobsPressed;

  @override
  Widget build(BuildContext context) {
    return AppStaggeredEntrance(
      index: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          PrimaryActionButton(
            label: 'Ver outras oportunidades',
            onPressed: onSeeOtherJobsPressed,
          ),
        ],
      ),
    );
  }
}
