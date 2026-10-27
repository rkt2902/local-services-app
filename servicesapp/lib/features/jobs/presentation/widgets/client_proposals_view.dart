import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_motion.dart';

/// Dados de "Propostas recebidas" (designs A3 e A6). A integração
/// (client_proposals_screen.dart) entrega a lista já ordenada e os textos
/// já formatados; este widget não lê providers nem ordena nada. Por hora
/// e valor total ficam juntos e nunca se ordenam pelo número.
class ClientProposalsViewData {
  const ClientProposalsViewData({
    required this.headerSubtitle,
    required this.proposals,
    this.orderingLabel,
  });

  /// Ex.: "Corte de relva · 3 propostas".
  final String headerSubtitle;
  final String? orderingLabel;
  final List<ClientProposalCardViewData> proposals;
}

class ClientProposalCardViewData {
  const ClientProposalCardViewData({
    required this.proposalId,
    required this.workerId,
    required this.workerName,
    required this.priceLabel,
    required this.priceKindLabel,
    required this.totalNoteLabel,
    required this.scheduleLabel,
    this.workerAvatarUrl,
    this.ratingLabel,
    this.totalLabel,
    this.includesLabel,
    this.durationLabel,
    this.validUntilLabel,
    this.teamLabel,
    this.notes,
    this.workerBadgeLabel,
    this.recommended = false,
    this.expired = false,
  });

  final String proposalId;
  final String workerId;
  final String workerName;
  final String? workerAvatarUrl;

  /// Ex.: "4,9 · 38 avaliações"; `null` mostra "Ainda sem avaliações".
  final String? ratingLabel;

  /// Valor grande. Ex.: "25 €/h" ou "450 €".
  final String priceLabel;

  /// Ao lado do valor: "preço por hora" ou "valor fechado".
  final String priceKindLabel;

  /// Linha "Total": "cerca de 100 a 150 €" ou "450 €". `null` por hora sem
  /// duração (a caixa mostra só a nota).
  final String? totalLabel;

  /// "Estimado. Depende das horas feitas." / "Fechado. Não muda com as
  /// horas."
  final String totalNoteLabel;

  /// Ex.: "material, remoção de resíduos".
  final String? includesLabel;

  /// Ex.: "2 a 3 dias", "4 a 6 h".
  final String? durationLabel;

  /// Ex.: "Início 03/11".
  final String scheduleLabel;

  /// Ex.: "Válido até 06/11".
  final String? validUntilLabel;

  /// Ex.: "Leva 2 ajudantes"; `null` quando é só o jardineiro.
  final String? teamLabel;

  /// Nota que o jardineiro escreveu na proposta.
  final String? notes;

  /// Selo opcional (ex.: "Pro"). `null` enquanto não houver o plano.
  final String? workerBadgeLabel;

  /// Destaque visual, não é estado da proposta.
  final bool recommended;

  /// Validade passou (calculado no servidor).
  final bool expired;
}

class ClientProposalsView extends StatelessWidget {
  const ClientProposalsView({
    super.key,
    required this.dataAsync,
    required this.onBack,
    required this.onRetry,
    required this.onOpenProposal,
  });

  final AsyncValue<ClientProposalsViewData> dataAsync;
  final VoidCallback onBack;
  final VoidCallback onRetry;

  /// Abre o detalhe, onde se aceita.
  final ValueChanged<ClientProposalCardViewData> onOpenProposal;

  @override
  Widget build(BuildContext context) {
    final data = dataAsync.value;
    final Widget body;
    if (data != null) {
      body = data.proposals.isEmpty
          ? const _CenteredState(
              key: ValueKey('empty'),
              child: AppEmptyState(
                icon: Icons.hourglass_empty_rounded,
                title: 'Ainda sem propostas',
                message: 'Avisamos-te quando chegar a primeira.',
                tone: AppStatusColor.waiting,
              ),
            )
          : _ProposalsList(
              key: const ValueKey('list'),
              data: data,
              onOpen: onOpenProposal,
            );
    } else if (dataAsync.hasError) {
      body = _CenteredState(
        key: const ValueKey('error'),
        child: AppEmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Não foi possível carregar as propostas',
          message: 'Verifica a ligação e tenta outra vez.',
          actionLabel: 'Tentar novamente',
          onAction: onRetry,
          tone: AppStatusColor.cancelled,
        ),
      );
    } else {
      body = const _LoadingList(key: ValueKey('loading'));
    }

    return Column(
      children: [
        _Header(subtitle: data?.headerSubtitle, onBack: onBack),
        Expanded(
          child: AppFadeThroughSwitcher(
            switchKey: body.key!,
            child: body,
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.subtitle, required this.onBack});

  /// `null` enquanto carrega (mostra um esqueleto).
  final String? subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final subtitle = this.subtitle;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
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
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Propostas recebidas',
                  style: textTheme.titleLarge
                      ?.copyWith(color: AppColors.textPrimary),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({super.key, required this.child});

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

class _ProposalsList extends StatelessWidget {
  const _ProposalsList({
    super.key,
    required this.data,
    required this.onOpen,
  });

  final ClientProposalsViewData data;
  final ValueChanged<ClientProposalCardViewData> onOpen;

  @override
  Widget build(BuildContext context) {
    final proposals = data.proposals;
    final ordering = data.orderingLabel;

    return ListView.builder(
      key: const PageStorageKey('client_job_proposals'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      itemCount: proposals.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          if (ordering == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              ordering,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          );
        }
        final proposal = proposals[index - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: AppStaggeredEntrance(
            key: ValueKey(proposal.proposalId),
            index: index - 1,
            child: proposal.expired
                ? _ExpiredProposalCard(
                    proposal: proposal,
                    onTap: () => onOpen(proposal),
                  )
                : _ProposalCard(
                    proposal: proposal,
                    onTap: () => onOpen(proposal),
                  ),
          ),
        );
      },
    );
  }
}

/// Cartão do design A6: o valor grande segue o formato do jardineiro, e a
/// caixa "Total" fica no mesmo sítio nos dois formatos, com o tipo escrito
/// por baixo.
class _ProposalCard extends StatelessWidget {
  const _ProposalCard({required this.proposal, required this.onTap});

  final ClientProposalCardViewData proposal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final notes = proposal.notes;
    final includes = proposal.includesLabel;

    return Semantics(
      button: true,
      label: 'Proposta de ${proposal.workerName}, ${proposal.priceLabel} '
          '${proposal.priceKindLabel}',
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: proposal.recommended
                    ? AppColors.primary
                    : AppColors.divider,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ProposalWorkerAvatar(
                      name: proposal.workerName,
                      avatarUrl: proposal.workerAvatarUrl,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: AppSpacing.xs,
                            runSpacing: AppSpacing.xxs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                proposal.workerName,
                                style: textTheme.titleMedium
                                    ?.copyWith(color: AppColors.textPrimary),
                              ),
                              if (proposal.workerBadgeLabel != null)
                                _WorkerBadge(label: proposal.workerBadgeLabel!),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          _RatingLine(label: proposal.ratingLabel),
                        ],
                      ),
                    ),
                    if (proposal.recommended) ...[
                      const SizedBox(width: AppSpacing.xs),
                      const _RecommendedChip(),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: AppSpacing.xs,
                  children: [
                    Text(
                      proposal.priceLabel,
                      style: textTheme.headlineSmall
                          ?.copyWith(color: AppColors.textPrimary),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                      child: Text(
                        proposal.priceKindLabel,
                        style: textTheme.labelMedium
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                _TotalBox(
                  totalLabel: proposal.totalLabel,
                  noteLabel: proposal.totalNoteLabel,
                ),
                if (includes != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Inclui: ',
                          style: textTheme.labelMedium?.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(text: includes),
                      ],
                    ),
                    style: textTheme.labelMedium
                        ?.copyWith(color: AppColors.textPrimary),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    if (proposal.durationLabel != null)
                      _MetaItem(
                        icon: Icons.schedule_outlined,
                        label: proposal.durationLabel!,
                      ),
                    _MetaItem(
                      icon: Icons.event_outlined,
                      label: proposal.scheduleLabel,
                    ),
                    if (proposal.teamLabel != null)
                      _MetaItem(
                        icon: Icons.group_outlined,
                        label: proposal.teamLabel!,
                      ),
                    if (proposal.validUntilLabel != null)
                      _MetaItem(
                        icon: Icons.timer_outlined,
                        label: proposal.validUntilLabel!,
                      ),
                  ],
                ),
                if (notes != null && notes.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    notes,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Caixa "Total" (mesmo sítio nos dois formatos).
class _TotalBox extends StatelessWidget {
  const _TotalBox({required this.totalLabel, required this.noteLabel});

  final String? totalLabel;
  final String noteLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textPrimary),
                ),
              ),
              if (totalLabel != null)
                Text(
                  totalLabel!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          Text(
            noteLabel,
            style: textTheme.labelSmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Orçamento expirado na lista: cinzento, com a etiqueta "Expirada".
class _ExpiredProposalCard extends StatelessWidget {
  const _ExpiredProposalCard({required this.proposal, required this.onTap});

  final ClientProposalCardViewData proposal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const tone = AppStatusColor.neutral;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      proposal.workerName,
                      style: textTheme.titleMedium
                          ?.copyWith(color: AppColors.textPrimary),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: tone.background,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      'Expirada',
                      style: textTheme.labelSmall?.copyWith(
                        color: tone.foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                proposal.priceLabel,
                style: textTheme.titleLarge?.copyWith(color: tone.foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selo opcional ao lado do nome.
class _WorkerBadge extends StatelessWidget {
  const _WorkerBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.logoAccent),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

/// Foto do jardineiro ou as iniciais num círculo verde claro.
class ProposalWorkerAvatar extends StatelessWidget {
  const ProposalWorkerAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
  });

  final String name;
  final String? avatarUrl;

  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return '$first$last'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    final hasPhoto = url != null && url.isNotEmpty;
    return CircleAvatar(
      radius: AppSizes.avatarSmall / 2,
      backgroundColor: AppColors.primaryContainer,
      backgroundImage: hasPhoto ? NetworkImage(url) : null,
      child: hasPhoto
          ? null
          : Text(
              initialsOf(name),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
    );
  }
}

class _RecommendedChip extends StatelessWidget {
  const _RecommendedChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        'Recomendada',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _RatingLine extends StatelessWidget {
  const _RatingLine({required this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(color: AppColors.textSecondary);
    final label = this.label;
    if (label == null) return Text('Ainda sem avaliações', style: style);
    return Row(
      children: [
        const Icon(
          Icons.star_border_rounded,
          size: AppSizes.ratingStar,
          color: AppColors.logoAccent,
        ),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(child: Text(label, style: style)),
      ],
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: AppSizes.metaIcon, color: AppColors.primary),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      itemCount: 3,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, _) => AppSkeletonShimmer(
        child: Container(
          height: AppSizes.proposalCardSkeleton,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
        ),
      ),
    );
  }
}
