import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/primary_action_button.dart';
import 'client_proposals_view.dart' show ProposalWorkerAvatar;

/// Detalhe de uma proposta e aceitação (design A6, D). Serve os dois
/// formatos (por hora e valor total): os textos chegam prontos da
/// integração e a validade é decidida no servidor, nunca aqui.
class ClientProposalDetailViewData {
  const ClientProposalDetailViewData({
    required this.proposalId,
    required this.workerId,
    required this.workerName,
    required this.priceTitle,
    required this.priceLabel,
    required this.priceExplanationLabel,
    required this.facts,
    required this.infoLines,
    required this.acceptActionLabel,
    this.workerAvatarUrl,
    this.ratingLabel,
    this.totalLabel,
    this.includeLabels = const [],
    this.notes,
    this.expiringSoonLabel,
    this.expired = false,
    this.expiredTitle,
  });

  final String proposalId;
  final String workerId;
  final String workerName;
  final String? workerAvatarUrl;
  final String? ratingLabel;

  /// "Valor fechado" ou "Preço por hora".
  final String priceTitle;

  /// "450 €" ou "25 €/h".
  final String priceLabel;
  final String priceExplanationLabel;

  /// Por hora: "Total estimado: cerca de 100 a 150 €".
  final String? totalLabel;

  final List<String> includeLabels;
  final String? notes;

  /// Início, Duração, Ajudantes, Válido até.
  final List<ClientProposalFact> facts;

  /// Regras da aceitação (lembretes fixos do produto).
  final List<ClientProposalInfoLine> infoLines;

  /// "Aceitar por 450 €".
  final String acceptActionLabel;

  /// "amanhã, 23:59" quando faltam menos de 48 h.
  final String? expiringSoonLabel;

  final bool expired;

  /// "Este orçamento expirou a 06/11".
  final String? expiredTitle;
}

class ClientProposalFact {
  const ClientProposalFact(this.label, this.value);

  final String label;
  final String value;
}

class ClientProposalInfoLine {
  const ClientProposalInfoLine({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

enum ClientProposalAcceptOutcome { accepted, expired, unavailable, failed }

class ClientProposalAcceptResult {
  const ClientProposalAcceptResult.accepted()
      : outcome = ClientProposalAcceptOutcome.accepted,
        message = null;
  const ClientProposalAcceptResult.expired()
      : outcome = ClientProposalAcceptOutcome.expired,
        message = null;
  const ClientProposalAcceptResult.unavailable()
      : outcome = ClientProposalAcceptOutcome.unavailable,
        message = null;
  const ClientProposalAcceptResult.failed(this.message)
      : outcome = ClientProposalAcceptOutcome.failed;

  final ClientProposalAcceptOutcome outcome;
  final String? message;
}

class ClientProposalDetailView extends StatefulWidget {
  const ClientProposalDetailView({
    super.key,
    required this.dataAsync,
    required this.onBack,
    required this.onRetry,
    required this.onOpenWorkerProfile,
    required this.onAccept,
    required this.onAccepted,
    required this.onBackToList,
  });

  /// `data(null)`: a proposta já não está na lista (retirada ou aceite
  /// outra).
  final AsyncValue<ClientProposalDetailViewData?> dataAsync;
  final VoidCallback onBack;
  final VoidCallback onRetry;
  final VoidCallback onOpenWorkerProfile;

  /// Só devolve `accepted` depois de o servidor confirmar.
  final Future<ClientProposalAcceptResult> Function(String proposalId)
      onAccept;

  /// Chamado depois da aceitação confirmada; quem integra navega.
  final VoidCallback onAccepted;
  final VoidCallback onBackToList;

  @override
  State<ClientProposalDetailView> createState() =>
      _ClientProposalDetailViewState();
}

class _ClientProposalDetailViewState extends State<ClientProposalDetailView> {
  bool _accepting = false;
  bool _expiredNow = false;
  bool _unavailable = false;
  String? _error;

  Future<void> _accept(ClientProposalDetailViewData data) async {
    if (_accepting) return;
    setState(() {
      _accepting = true;
      _error = null;
    });

    ClientProposalAcceptResult result;
    try {
      result = await widget.onAccept(data.proposalId);
    } catch (_) {
      result = const ClientProposalAcceptResult.failed(null);
    }
    if (!mounted) return;

    switch (result.outcome) {
      case ClientProposalAcceptOutcome.accepted:
        setState(() => _accepting = false);
        widget.onAccepted();
      case ClientProposalAcceptOutcome.expired:
        setState(() {
          _accepting = false;
          _expiredNow = true;
        });
      case ClientProposalAcceptOutcome.unavailable:
        setState(() {
          _accepting = false;
          _unavailable = true;
        });
      case ClientProposalAcceptOutcome.failed:
        setState(() {
          _accepting = false;
          _error = result.message ??
              'Não foi possível aceitar a proposta. Tenta novamente.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.dataAsync.value;
    final Widget body;
    final String title;

    if (widget.dataAsync.hasValue && (data == null || _unavailable)) {
      title = 'Proposta';
      body = _Centered(
        key: const ValueKey('unavailable'),
        child: AppEmptyState(
          icon: Icons.block_rounded,
          title: 'Esta proposta já não está disponível',
          message: 'O jardineiro pode tê-la retirado. Escolhe outra da lista.',
          actionLabel: 'Ver propostas',
          onAction: widget.onBackToList,
          tone: AppStatusColor.neutral,
        ),
      );
    } else if (data != null) {
      title = 'Proposta de ${data.workerName.split(' ').first}';
      body = _DetailBody(
        key: const ValueKey('data'),
        data: data,
        expired: data.expired || _expiredNow,
        accepting: _accepting,
        error: _error,
        onOpenProfile: widget.onOpenWorkerProfile,
        onAccept: () => _accept(data),
      );
    } else if (widget.dataAsync.hasError) {
      title = 'Proposta';
      body = _Centered(
        key: const ValueKey('error'),
        child: AppEmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Não foi possível carregar a proposta',
          message: 'Verifica a ligação e tenta outra vez.',
          actionLabel: 'Tentar novamente',
          onAction: widget.onRetry,
          tone: AppStatusColor.cancelled,
        ),
      );
    } else {
      title = 'Proposta';
      body = const _DetailSkeleton(key: ValueKey('loading'));
    }

    return Column(
      children: [
        _Header(title: title, onBack: widget.onBack),
        Expanded(
          child: AppFadeThroughSwitcher(switchKey: body.key!, child: body),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
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
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({super.key, required this.child});

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

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    super.key,
    required this.data,
    required this.expired,
    required this.accepting,
    required this.error,
    required this.onOpenProfile,
    required this.onAccept,
  });

  final ClientProposalDetailViewData data;
  final bool expired;
  final bool accepting;
  final String? error;
  final VoidCallback onOpenProfile;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final notes = data.notes;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            children: [
              AppStaggeredEntrance(
                index: 0,
                child: Row(
                  children: [
                    ProposalWorkerAvatar(
                      name: data.workerName,
                      avatarUrl: data.workerAvatarUrl,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.workerName,
                            style: textTheme.titleMedium
                                ?.copyWith(color: AppColors.textPrimary),
                          ),
                          if (data.ratingLabel != null)
                            Text(
                              data.ratingLabel!,
                              style: textTheme.labelMedium
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                          InkWell(
                            onTap: onOpenProfile,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.xxs,
                              ),
                              child: Text(
                                'Ver perfil e avaliações',
                                style: textTheme.labelMedium?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppStaggeredEntrance(
                index: 1,
                child: _PriceHero(data: data, expired: expired),
              ),
              if (data.includeLabels.isNotEmpty ||
                  (notes != null && notes.isNotEmpty)) ...[
                const SizedBox(height: AppSpacing.sm),
                AppStaggeredEntrance(
                  index: 2,
                  child: _IncludesCard(
                    labels: data.includeLabels,
                    notes: notes,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              AppStaggeredEntrance(
                index: 3,
                child: _FactsCard(facts: data.facts),
              ),
              if (expired) ...[
                const SizedBox(height: AppSpacing.sm),
                _StateBanner(
                  icon: Icons.timer_off_outlined,
                  tone: AppStatusColor.neutral,
                  title: data.expiredTitle ?? 'Este orçamento expirou',
                  message: 'Já não dá para aceitar. Escolhe outra proposta '
                      'ou espera por novas.',
                ),
              ] else if (data.expiringSoonLabel != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _ExpiringSoonRow(label: data.expiringSoonLabel!),
              ],
              if (!expired) ...[
                const SizedBox(height: AppSpacing.md),
                for (final line in data.infoLines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _InfoRow(line: line),
                  ),
              ],
              if (error != null) ...[
                const SizedBox(height: AppSpacing.xs),
                _StateBanner(
                  icon: Icons.error_outline_rounded,
                  tone: AppStatusColor.cancelled,
                  message: error!,
                ),
              ],
            ],
          ),
        ),
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: PrimaryActionButton(
            label: accepting ? 'A aceitar...' : data.acceptActionLabel,
            isLoading: accepting,
            onPressed: (expired || accepting) ? null : onAccept,
          ),
        ),
      ],
    );
  }
}

class _PriceHero extends StatelessWidget {
  const _PriceHero({required this.data, required this.expired});

  final ClientProposalDetailViewData data;
  final bool expired;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tone = expired ? AppStatusColor.neutral : AppStatusColor.success;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.priceTitle.toUpperCase(),
            style: textTheme.labelSmall?.copyWith(
              color: tone.foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            data.priceLabel,
            style: textTheme.headlineMedium?.copyWith(
              color: expired ? tone.foreground : AppColors.textPrimary,
            ),
          ),
          if (data.totalLabel != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              data.totalLabel!,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            data.priceExplanationLabel,
            style:
                textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _IncludesCard extends StatelessWidget {
  const _IncludesCard({required this.labels, required this.notes});

  final List<String> labels;
  final String? notes;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final notes = this.notes;

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
          Text(
            labels.isEmpty ? 'NOTA DO JARDINEIRO' : 'INCLUI',
            style: textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          for (final label in labels)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_rounded,
                    size: AppSizes.inlineIcon,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      label,
                      style: textTheme.bodyMedium
                          ?.copyWith(color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '"$notes"',
              style: textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _FactsCard extends StatelessWidget {
  const _FactsCard({required this.facts});

  final List<ClientProposalFact> facts;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          for (var i = 0; i < facts.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    facts[i].label,
                    style: textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      facts[i].value,
                      textAlign: TextAlign.end,
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
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

/// "Válido até · amanhã, 23:59" (tom de espera).
class _ExpiringSoonRow extends StatelessWidget {
  const _ExpiringSoonRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const tone = AppStatusColor.waiting;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Válido até',
              style: textTheme.bodyMedium?.copyWith(
                color: tone.foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: tone.foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StateBanner extends StatelessWidget {
  const _StateBanner({
    required this.icon,
    required this.tone,
    required this.message,
    this.title,
  });

  final IconData icon;
  final AppStatusColor tone;
  final String? title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppSizes.infoRowIcon, color: tone.foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                Text(
                  message,
                  style: textTheme.bodySmall
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

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget block(double height) => AppSkeletonShimmer(
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
          ),
        );

    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        block(AppSizes.avatarSmall),
        const SizedBox(height: AppSpacing.md),
        block(AppSizes.proposalCardSkeleton),
        const SizedBox(height: AppSpacing.sm),
        block(AppSizes.proposalCardSkeleton),
      ],
    );
  }
}
