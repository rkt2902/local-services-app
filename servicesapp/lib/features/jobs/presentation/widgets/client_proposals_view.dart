import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/primary_action_button.dart';

/// Dados de "Propostas recebidas" (design A3). A integração
/// (client_proposals_screen.dart) entrega a lista já ordenada e os textos
/// já formatados; este widget não lê providers nem ordena nada.
class ClientProposalsViewData {
  const ClientProposalsViewData({
    required this.headerSubtitle,
    required this.orderingLabel,
    required this.proposals,
  });

  /// Ex.: "Corte de relva · 3 propostas".
  final String headerSubtitle;
  final String orderingLabel;
  final List<ClientProposalCardViewData> proposals;
}

class ClientProposalCardViewData {
  const ClientProposalCardViewData({
    required this.proposalId,
    required this.workerId,
    required this.workerName,
    required this.priceLabel,
    required this.priceDetailLabel,
    required this.scheduleLabel,
    required this.confirmation,
    this.workerAvatarUrl,
    this.ratingLabel,
    this.teamLabel,
    this.notes,
    this.recommended = false,
  });

  final String proposalId;
  final String workerId;
  final String workerName;
  final String? workerAvatarUrl;

  /// Ex.: "4,9 · 38 avaliações"; `null` mostra "Ainda sem avaliações".
  final String? ratingLabel;

  /// Ex.: "48 €" ou "48 a 96 €".
  final String priceLabel;

  /// Ex.: "2 a 4h · 12,00 €/h". Pode vir vazio.
  final String priceDetailLabel;
  final String scheduleLabel;

  /// Ex.: "Equipa de 2"; `null` quando é só o jardineiro.
  final String? teamLabel;

  /// Nota que o jardineiro escreveu na proposta.
  final String? notes;

  /// Destaque visual, não é estado da proposta.
  final bool recommended;

  final ClientProposalConfirmationViewData confirmation;
}

class ClientProposalConfirmationViewData {
  const ClientProposalConfirmationViewData({
    required this.summaryMetaLabel,
    required this.infoLines,
    required this.confirmActionLabel,
  });

  /// Ex.: "Qui, 23/10 · 9:00 · 2 a 4h".
  final String summaryMetaLabel;
  final List<ClientProposalInfoLine> infoLines;

  /// Ex.: "Aceitar proposta · 12,00 €/h".
  final String confirmActionLabel;
}

class ClientProposalInfoLine {
  const ClientProposalInfoLine({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

enum ClientProposalAcceptOutcome { accepted, unavailable, failed }

class ClientProposalAcceptResult {
  const ClientProposalAcceptResult.accepted()
      : outcome = ClientProposalAcceptOutcome.accepted,
        message = null;
  const ClientProposalAcceptResult.unavailable()
      : outcome = ClientProposalAcceptOutcome.unavailable,
        message = null;
  const ClientProposalAcceptResult.failed(this.message)
      : outcome = ClientProposalAcceptOutcome.failed;

  final ClientProposalAcceptOutcome outcome;
  final String? message;
}

class ClientProposalsView extends StatelessWidget {
  const ClientProposalsView({
    super.key,
    required this.dataAsync,
    required this.onBack,
    required this.onRetry,
    required this.onOpenWorkerProfile,
    required this.onAcceptProposal,
    required this.onProposalAccepted,
  });

  final AsyncValue<ClientProposalsViewData> dataAsync;
  final VoidCallback onBack;
  final VoidCallback onRetry;
  final ValueChanged<ClientProposalCardViewData> onOpenWorkerProfile;

  /// Só devolve `accepted` depois de o servidor confirmar.
  final Future<ClientProposalAcceptResult> Function(String proposalId)
      onAcceptProposal;

  /// Chamado com a folha já fechada; quem integra navega.
  final ValueChanged<ClientProposalCardViewData> onProposalAccepted;

  Future<void> _choose(
    BuildContext context,
    ClientProposalCardViewData proposal,
  ) async {
    final accepted = await AppSheet.show<bool>(
      context,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _AcceptProposalSheet(
        proposal: proposal,
        onAccept: onAcceptProposal,
      ),
    );
    if (accepted == true && context.mounted) onProposalAccepted(proposal);
  }

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
                message:
                    'Avisamos-te assim que um jardineiro enviar uma proposta.',
                tone: AppStatusColor.waiting,
              ),
            )
          : _ProposalsList(
              key: const ValueKey('list'),
              data: data,
              onOpenProfile: onOpenWorkerProfile,
              onChoose: (p) => _choose(context, p),
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
    required this.onOpenProfile,
    required this.onChoose,
  });

  final ClientProposalsViewData data;
  final ValueChanged<ClientProposalCardViewData> onOpenProfile;
  final ValueChanged<ClientProposalCardViewData> onChoose;

  @override
  Widget build(BuildContext context) {
    final proposals = data.proposals;

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
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              data.orderingLabel,
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
            child: _ProposalCard(
              proposal: proposal,
              onOpenProfile: () => onOpenProfile(proposal),
              onChoose: () => onChoose(proposal),
            ),
          ),
        );
      },
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.proposal,
    required this.onOpenProfile,
    required this.onChoose,
  });

  final ClientProposalCardViewData proposal;
  final VoidCallback onOpenProfile;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final notes = proposal.notes;
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.card),
    );
    final buttonPadding = const EdgeInsets.symmetric(horizontal: AppSpacing.xs);
    final buttonText =
        textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: proposal.recommended ? AppColors.primary : AppColors.divider,
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
                flex: 3,
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
                        if (proposal.recommended) const _RecommendedChip(),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    _RatingLine(label: proposal.ratingLabel),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Flexível para não rebentar com letra grande em ecrãs
              // estreitos; o valor parte em duas linhas antes disso.
              Flexible(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      proposal.priceLabel,
                      textAlign: TextAlign.end,
                      style: textTheme.titleLarge
                          ?.copyWith(color: AppColors.textPrimary),
                    ),
                    if (proposal.priceDetailLabel.isNotEmpty)
                      Text(
                        proposal.priceDetailLabel,
                        textAlign: TextAlign.end,
                        style: textTheme.labelSmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xxs,
            children: [
              _MetaItem(
                icon: Icons.event_outlined,
                label: proposal.scheduleLabel,
              ),
              if (proposal.teamLabel != null)
                _MetaItem(
                  icon: Icons.group_outlined,
                  label: proposal.teamLabel!,
                ),
            ],
          ),
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              notes,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: AppSizes.compactButtonHeight,
                  child: OutlinedButton(
                    onPressed: onOpenProfile,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.divider),
                      shape: buttonShape,
                      padding: buttonPadding,
                      textStyle: buttonText,
                    ),
                    child: const Text(
                      'Ver perfil e avaliações',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                flex: 2,
                child: proposal.recommended
                    ? PrimaryActionButton(
                        label: 'Escolher',
                        height: AppSizes.compactButtonHeight,
                        onPressed: onChoose,
                      )
                    : SizedBox(
                        height: AppSizes.compactButtonHeight,
                        child: OutlinedButton(
                          onPressed: onChoose,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            shape: buttonShape,
                            padding: buttonPadding,
                            textStyle: buttonText,
                          ),
                          child: const Text('Escolher'),
                        ),
                      ),
              ),
            ],
          ),
        ],
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

// ── Folha "Aceitar esta proposta?" ──────────────────────────────────────────

class _AcceptProposalSheet extends StatefulWidget {
  const _AcceptProposalSheet({required this.proposal, required this.onAccept});

  final ClientProposalCardViewData proposal;
  final Future<ClientProposalAcceptResult> Function(String proposalId) onAccept;

  @override
  State<_AcceptProposalSheet> createState() => _AcceptProposalSheetState();
}

class _AcceptProposalSheetState extends State<_AcceptProposalSheet> {
  bool _submitting = false;
  bool _unavailable = false;
  String? _error;

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    ClientProposalAcceptResult result;
    try {
      result = await widget.onAccept(widget.proposal.proposalId);
    } catch (_) {
      result = const ClientProposalAcceptResult.failed(null);
    }
    if (!mounted) return;

    switch (result.outcome) {
      case ClientProposalAcceptOutcome.accepted:
        Navigator.of(context).pop(true);
      case ClientProposalAcceptOutcome.unavailable:
        setState(() {
          _submitting = false;
          _unavailable = true;
        });
      case ClientProposalAcceptOutcome.failed:
        // Erro dentro da folha: um SnackBar ficava escondido por trás dela.
        // O botão de aceitar serve de "Repetir".
        setState(() {
          _submitting = false;
          _error = result.message ??
              'Não foi possível aceitar a proposta. Tenta novamente.';
        });
    }
  }

  void _close() => Navigator.of(context).pop(false);

  @override
  Widget build(BuildContext context) {
    return AppFadeThroughSwitcher(
      switchKey: _unavailable,
      child: _unavailable ? _buildUnavailable() : _buildConfirmation(),
    );
  }

  Widget _buildUnavailable() {
    return AppSheet(
      key: const ValueKey('unavailable'),
      title: '',
      onClose: _close,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: AppEmptyState(
          icon: Icons.block_rounded,
          title: 'Esta proposta já não está disponível',
          message: 'O jardineiro pode tê-la retirado. '
              'Escolhe outra da lista.',
          tone: AppStatusColor.neutral,
          action: OutlinedButton(
            onPressed: _close,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.divider),
              minimumSize: const Size(
                AppSizes.emptyActionMinWidth,
                AppSizes.compactButtonHeight,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
            ),
            child: const Text('Ver propostas'),
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmation() {
    final confirmation = widget.proposal.confirmation;
    return AppSheet(
      key: const ValueKey('confirmation'),
      title: 'Aceitar esta proposta?',
      onClose: _close,
      isSubmitting: _submitting,
      primaryActionLabel: confirmation.confirmActionLabel,
      onPrimaryAction: _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetSummary(proposal: widget.proposal),
          const SizedBox(height: AppSpacing.md),
          for (final line in confirmation.infoLines)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _InfoRow(line: line),
            ),
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppStatusColor.cancelled.background,
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              child: Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppStatusColor.cancelled.foreground,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SheetSummary extends StatelessWidget {
  const _SheetSummary({required this.proposal});

  final ClientProposalCardViewData proposal;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
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
                Text(
                  proposal.workerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall
                      ?.copyWith(color: AppColors.textPrimary),
                ),
                Text(
                  proposal.confirmation.summaryMetaLabel,
                  style: textTheme.labelSmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            proposal.priceLabel,
            style:
                textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.line});

  final ClientProposalInfoLine line;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(line.icon, size: AppSizes.infoRowIcon, color: AppColors.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            line.label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }
}
