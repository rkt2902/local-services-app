import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion_tokens.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/theme/app_status_presentation.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/app_status_badge.dart';
import '../../../../core/widgets/primary_action_button.dart';
import '../../../../core/widgets/user_avatar_with_name.dart';
import '../../../agenda/presentation/widgets/agenda_overlap.dart';
import 'worker_direct_request_card.dart';

/// Dados de apresentação do detalhe de uma oportunidade.
///
/// A integração (worker_job_detail_screen.dart) mapeia o model real do
/// pedido para esta estrutura. Este ecrã não consulta providers,
/// repositories ou Supabase diretamente.
class WorkerJobDetailViewData {
  const WorkerJobDetailViewData({
    required this.id,
    required this.title,
    required this.locationLabel,
    required this.distanceLabel,
    required this.deadlineLabel,
    required this.areaLabel,
    required this.budgetLabel,
    required this.description,
    required this.serviceIcon,
    required this.clientName,
    required this.photos,
    this.clientAvatar,
    this.badge,
  });

  final String id;
  final String title;
  final String locationLabel;
  final String distanceLabel;

  final String deadlineLabel;
  final String areaLabel;
  final String budgetLabel;

  final String description;
  final IconData serviceIcon;

  final String clientName;

  /// URL (não ImageProvider) — UserAvatarWithName já resolve a imagem
  /// internamente a partir do URL.
  final String? clientAvatar;

  final List<ImageProvider> photos;
  final AppStatusPresentation? badge;
}

class WorkerJobDetailScreen extends StatelessWidget {
  const WorkerJobDetailScreen({
    required this.data,
    required this.onBack,
    required this.onSendProposalPressed,
    super.key,
    this.onClientPressed,
    this.unavailable = false,
    this.unavailableReason,
    this.onViewMyProposalPressed,
    this.directRequest,
    this.onRetryDirectHistory,
    this.onDeclineDirectPressed,
    this.decliningDirect = false,
    this.directDeclinedMessage,
    this.onSeeOtherJobsPressed,
    this.agendaAvailability,
    this.onAgendaAvailabilityPressed,
  });

  final WorkerJobDetailViewData data;

  /// Chip da Agenda por baixo do prazo (A10, M2): livre, quantos trabalhos
  /// já tem nesse dia ou coincide. Nulo sem data ou sem Agenda. Só
  /// informação: tocar abre "Ver o dia".
  final (AgendaAvailability, String)? agendaAvailability;
  final VoidCallback? onAgendaAvailabilityPressed;

  /// Pedido direto para este jardineiro (design A5, 5b): cartão no topo e,
  /// sem proposta enviada, "Não posso desta vez" no fundo.
  final WorkerDirectRequestViewData? directRequest;
  final VoidCallback? onRetryDirectHistory;
  final VoidCallback? onDeclineDirectPressed;
  final bool decliningDirect;

  /// Depois de recusar: a mensagem do painel e "Ver outras oportunidades".
  final String? directDeclinedMessage;
  final VoidCallback? onSeeOtherJobsPressed;

  final VoidCallback onBack;
  final VoidCallback onSendProposalPressed;
  final VoidCallback? onClientPressed;

  /// Pedido já não aberto (e não é do worker): só leitura, sem
  /// "Enviar proposta".
  final bool unavailable;

  /// Porquê (outro jardineiro ficou com ele, cancelado, expirado), quando
  /// se sabe.
  final String? unavailableReason;

  /// Não nulo quando o worker já tem uma proposta pendente neste pedido:
  /// troca "Enviar proposta" por "Ver a minha proposta".
  final VoidCallback? onViewMyProposalPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          onPressed: onBack,
          tooltip: 'Voltar',
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimary,
          ),
        ),
        titleSpacing: 0,
        title: Text(
          'Detalhe do pedido',
          style: textTheme.titleLarge?.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (directRequest != null && !unavailable) ...[
                      AppStaggeredEntrance(
                        index: 0,
                        child: WorkerDirectRequestCard(
                          data: directRequest!,
                          onRetryHistory: onRetryDirectHistory,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    _ServiceHeader(
                      title: data.title,
                      locationLabel: data.locationLabel,
                      distanceLabel: data.distanceLabel,
                      icon: data.serviceIcon,
                      badge: data.badge,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: _InformationCard(
                            label: 'Prazo',
                            value: data.deadlineLabel,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: _InformationCard(
                            label: 'Área',
                            value: data.areaLabel,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: _InformationCard(
                            label: 'Orçam.',
                            value: data.budgetLabel,
                            highlighted: true,
                          ),
                        ),
                      ],
                    ),
                    if (agendaAvailability case (
                      final availability,
                      final label,
                    ) when !unavailable) ...[
                      const SizedBox(height: AppSpacing.xs),
                      AppFadeThroughSwitcher(
                        switchKey: label,
                        duration: AppMotionDuration.fast,
                        child: Align(
                          key: ValueKey(label),
                          alignment: Alignment.centerLeft,
                          child: AgendaAvailabilityChip(
                            availability: availability,
                            label: label,
                            onPressed: onAgendaAvailabilityPressed,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Descrição',
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      data.description,
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (data.photos.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      _JobPhotos(
                        photos: data.photos,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    const Divider(
                      color: AppColors.divider,
                      height: 1,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Material(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(
                        AppRadius.input,
                      ),
                      child: InkWell(
                        onTap: onClientPressed,
                        borderRadius: BorderRadius.circular(
                          AppRadius.input,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.xs,
                          ),
                          child: UserAvatarWithName(
                            name: data.clientName,
                            avatarUrl: data.clientAvatar,
                            radius: 22,
                            fallbackLabel: 'Cliente',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              color: AppColors.background,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: _buildFooter(context),
            ),
          ],
        ),
      ),
    );
  }
}

extension on WorkerJobDetailScreen {
  Widget _buildFooter(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (unavailable) {
      return WorkerJobUnavailableBanner(reason: unavailableReason);
    }

    final declinedMessage = directDeclinedMessage;
    if (declinedMessage != null && onSeeOtherJobsPressed != null) {
      return WorkerDirectDeclinedPanel(
        message: declinedMessage,
        onSeeOtherJobsPressed: onSeeOtherJobsPressed!,
      );
    }

    if (onViewMyProposalPressed != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.schedule_outlined,
                color: AppStatusColor.waiting.foreground,
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  'Proposta enviada, à espera do cliente',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: AppStatusColor.waiting.foreground),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          PrimaryActionButton(
            label: 'Ver a minha proposta',
            onPressed: onViewMyProposalPressed,
          ),
        ],
      );
    }

    final onDecline = onDeclineDirectPressed;
    if (directRequest != null && onDecline != null) {
      return WorkerDirectRequestActions(
        onSendProposalPressed: onSendProposalPressed,
        onDeclinePressed: onDecline,
        declining: decliningDirect,
      );
    }

    return PrimaryActionButton(
      label: 'Enviar proposta',
      onPressed: onSendProposalPressed,
    );
  }
}

/// "Este pedido já não está disponível." + motivo (se se souber). Usado no
/// rodapé do detalhe e no ecrã inteiro quando o pedido nem sequer carrega.
class WorkerJobUnavailableBanner extends StatelessWidget {
  const WorkerJobUnavailableBanner({super.key, this.reason});

  final String? reason;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = AppStatusColor.neutral;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.block_outlined, color: color.foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Este pedido já não está disponível.',
                  style: textTheme.titleSmall?.copyWith(color: color.foreground),
                ),
                if (reason != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    reason!,
                    style: textTheme.bodyMedium
                        ?.copyWith(color: color.foreground),
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

class _ServiceHeader extends StatelessWidget {
  const _ServiceHeader({
    required this.title,
    required this.locationLabel,
    required this.distanceLabel,
    required this.icon,
    required this.badge,
  });

  final String title;
  final String locationLabel;
  final String distanceLabel;
  final IconData icon;
  final AppStatusPresentation? badge;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(
              AppRadius.input,
            ),
          ),
          child: Icon(
            icon,
            color: AppColors.primary,
            size: 24,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                distanceLabel.isEmpty
                    ? locationLabel
                    : '$locationLabel · $distanceLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (badge != null) ...[
          const SizedBox(width: AppSpacing.xs),
          AppStatusBadge.fromPresentation(
            presentation: badge!,
          ),
        ],
      ],
    );
  }
}

class _InformationCard extends StatelessWidget {
  const _InformationCard({
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      constraints: const BoxConstraints(
        minHeight: 60,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(
          AppRadius.input,
        ),
        border: Border.all(
          color: AppColors.divider,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: textTheme.titleMedium?.copyWith(
                color: highlighted
                    ? AppColors.primary
                    : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JobPhotos extends StatelessWidget {
  const _JobPhotos({
    required this.photos,
  });

  final List<ImageProvider> photos;

  @override
  Widget build(BuildContext context) {
    final visiblePhotos = photos.take(2).toList();
    final remainingCount = photos.length - visiblePhotos.length;

    return SizedBox(
      height: 68,
      child: Row(
        children: [
          for (var index = 0; index < visiblePhotos.length; index++) ...[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  AppRadius.input,
                ),
                child: Image(
                  image: visiblePhotos[index],
                  height: 68,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) {
                    return const _PhotoPlaceholder();
                  },
                ),
              ),
            ),
            if (index != visiblePhotos.length - 1 ||
                remainingCount > 0)
              const SizedBox(width: AppSpacing.xs),
          ],
          if (remainingCount > 0)
            Expanded(
              child: _RemainingPhotos(
                remainingCount: remainingCount,
              ),
            ),
        ],
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      alignment: Alignment.center,
      color: AppColors.primaryContainer,
      child: const Icon(
        Icons.image_outlined,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _RemainingPhotos extends StatelessWidget {
  const _RemainingPhotos({
    required this.remainingCount,
  });

  final int remainingCount;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      height: 68,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(
          AppRadius.input,
        ),
        border: Border.all(
          color: AppColors.divider,
        ),
      ),
      child: Text(
        '+$remainingCount',
        style: textTheme.titleMedium?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
