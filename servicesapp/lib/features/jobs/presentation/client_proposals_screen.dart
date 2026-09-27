import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../../ratings/application/rating_providers.dart';
import '../../ratings/presentation/ratings_sheet.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../proposals/data/proposal_model.dart';
import '../application/job_providers.dart';

/// Ecrã dedicado à lista de propostas de um pedido — antes vivia como aba
/// "Propostas" dentro de `client_job_detail_screen.dart` (removida quando o
/// ecrã de detalhe deixou de ter TabBar). Continua a ser SÓ a lista de
/// propostas recebidas, nunca uma vista de comparação lado-a-lado nova.
class ClientProposalsScreen extends ConsumerStatefulWidget {
  const ClientProposalsScreen({super.key, required this.jobId});

  final String jobId;

  @override
  ConsumerState<ClientProposalsScreen> createState() =>
      _ClientProposalsScreenState();
}

class _ClientProposalsScreenState
    extends ConsumerState<ClientProposalsScreen> {
  String _sortBy = 'price';
  final Map<String, bool> _accepting = {};

  Future<void> _acceptProposal(JobProposal proposal, String serviceLabel) async {
    final accepted = await _showAcceptProposalSheet(proposal, serviceLabel);
    if (accepted == true && mounted) {
      // `go` (não `pushReplacement`) de propósito: este ecrã foi alcançado
      // por um `push` a partir de `ClientJobDetailScreen` (aberto), que
      // continua na stack por baixo. Um `pushReplacement` aqui trocaria só
      // este ecrã, deixando o detalhe antigo (ainda "aberto") preso por
      // baixo do ecrã de confirmação — visível ao premir "voltar" a partir
      // dele. `go` substitui a stack toda pela rota de destino.
      GoRouter.of(context).go(
        '/client/job/${widget.jobId}/confirmed?workerId=${proposal.workerId}',
      );
    }
  }

  Future<bool?> _showAcceptProposalSheet(
    JobProposal proposal,
    String serviceLabel,
  ) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (_) => _AcceptProposalSheet(
        proposal: proposal,
        serviceLabel: serviceLabel,
        onAccept: () => _submitAccept(proposal),
      ),
    );
  }

  Future<_AcceptOutcome> _submitAccept(JobProposal proposal) async {
    setState(() => _accepting[proposal.id] = true);
    try {
      await ref
          .read(proposalRepositoryProvider)
          .acceptProposal(proposal.id, widget.jobId);
      ref.invalidate(clientJobsProvider);
      ref.invalidate(pendingProposalsForJobProvider(widget.jobId));
      ref.invalidate(jobByIdProvider(widget.jobId));
      return const _AcceptOutcome.accepted();
    } catch (e) {
      // A RPC `accept_proposal` não devolve um ERRCODE dedicado para
      // "proposta já processada" — só uma mensagem de texto (ver
      // migrations/0001_consolidated_baseline.sql). Mesma convenção de
      // classificação por texto já usada em
      // `proposal_repository.dart createProposal()`.
      final msg = e.toString();
      if (msg.contains('já não está disponível') ||
          msg.contains('já processada') ||
          msg.contains('não encontrada')) {
        if (mounted) ref.invalidate(pendingProposalsForJobProvider(widget.jobId));
        return const _AcceptOutcome.unavailable();
      }
      return _AcceptOutcome.failed(friendlyError(e));
    } finally {
      if (mounted) setState(() => _accepting.remove(proposal.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final proposalsAsync = ref.watch(pendingProposalsForJobProvider(widget.jobId));
    final jobAsync = ref.watch(jobByIdProvider(widget.jobId));
    final serviceTypes = ref.watch(serviceTypesProvider).asData?.value ?? const [];
    final job = jobAsync.asData?.value;
    final serviceLabel = job == null
        ? '—'
        : serviceTypes
                .where((s) => s.id == job.serviceTypeId)
                .map((s) => s.name)
                .firstOrNull ??
            '—';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: proposalsAsync.when(
          loading: () => _ProposalsLoading(onBack: () => context.pop()),
          error: (e, _) => _ProposalsError(
            onBack: () => context.pop(),
            onRetry: () => ref.invalidate(pendingProposalsForJobProvider(widget.jobId)),
          ),
          data: (proposals) {
            final subtitle = proposals.isEmpty
                ? 'Ainda sem propostas'
                : '${proposals.length} '
                    '${proposals.length == 1 ? 'proposta' : 'propostas'}';

            final sorted = [...proposals];
            if (_sortBy == 'price') {
              sorted.sort((a, b) {
                final aEst = a.hourlyRate * (a.estimatedHoursMin ?? 0);
                final bEst = b.hourlyRate * (b.estimatedHoursMin ?? 0);
                return aEst.compareTo(bEst);
              });
            }
            final anyAccepting = _accepting.values.any((v) => v);

            // "Recomendada" é só um marcador de ranking da app — não é
            // ProposalStatus/JobStatus. Critério: rating mais alto entre
            // workers com >= 3 avaliações (mesma lógica de sempre).
            String? recommendedWorkerId;
            double bestRating = 0;
            for (final p in sorted) {
              final summary = ref.watch(ratingSummaryProvider(p.workerId)).asData?.value;
              if (summary != null &&
                  summary.ratingCount >= 3 &&
                  summary.avgRating > bestRating) {
                bestRating = summary.avgRating;
                recommendedWorkerId = p.workerId;
              }
            }

            return Column(
              children: [
                _ProposalsHeader(subtitle: subtitle, onBack: () => context.pop()),
                Expanded(
                  child: proposals.isEmpty
                      ? const _ProposalsEmpty()
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            AppSpacing.xs,
                            AppSpacing.md,
                            AppSpacing.lg,
                          ),
                          children: [
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'price', label: Text('Por preço')),
                                ButtonSegment(
                                  value: 'rating',
                                  label: Text('Por avaliação'),
                                  tooltip: 'Disponível após as primeiras avaliações',
                                  enabled: false,
                                ),
                              ],
                              selected: {_sortBy},
                              onSelectionChanged: (sel) =>
                                  setState(() => _sortBy = sel.first),
                              style: const ButtonStyle(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            for (var i = 0; i < sorted.length; i++)
                              AppStaggeredEntrance(
                                key: ValueKey(sorted[i].id),
                                index: i,
                                child: _ProposalCard(
                                  proposal: sorted[i],
                                  recommended: sorted[i].workerId == recommendedWorkerId,
                                  accepting: _accepting[sorted[i].id] == true,
                                  onAccept: anyAccepting
                                      ? null
                                      : () => _acceptProposal(sorted[i], serviceLabel),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProposalsHeader extends StatelessWidget {
  const _ProposalsHeader({required this.subtitle, required this.onBack});

  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Propostas recebidas',
                  style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
                ),
                Text(
                  subtitle,
                  style: textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProposalsEmpty extends StatelessWidget {
  const _ProposalsEmpty();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: AppStatusColor.neutral.background,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.description_outlined,
                color: AppStatusColor.neutral.foreground,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Ainda sem propostas',
              style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'As propostas dos jardineiros aparecem aqui.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProposalsLoading extends StatelessWidget {
  const _ProposalsLoading({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ProposalsHeader(subtitle: '', onBack: onBack),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: 3,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, _) => AppSkeletonShimmer(
              child: Container(
                height: 140,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProposalsError extends StatelessWidget {
  const _ProposalsError({required this.onBack, required this.onRetry});

  final VoidCallback onBack;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        _ProposalsHeader(subtitle: '', onBack: onBack),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Não foi possível carregar as propostas.',
                    textAlign: TextAlign.center,
                    style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton(
                      onPressed: onRetry,
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Card de proposta (portado de client_job_detail_screen.dart) ────────────

class _ProposalCard extends ConsumerWidget {
  const _ProposalCard({
    required this.proposal,
    required this.accepting,
    required this.onAccept,
    this.recommended = false,
  });

  final JobProposal proposal;
  final bool accepting;
  final VoidCallback? onAccept;
  final bool recommended;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final workerName =
        proposal.workerName?.isNotEmpty == true ? proposal.workerName! : '—';
    final workerAvatarUrl = proposal.workerAvatarUrl ?? '';
    final ratingSummary =
        ref.watch(ratingSummaryProvider(proposal.workerId)).asData?.value;

    final hoursStr = _hoursLabel(proposal.estimatedHoursMin, proposal.estimatedHoursMax);
    final scheduleStr = _formatProposedSchedule(proposal);
    final teamEstimateStr = _teamTotalEstimate(proposal);
    final priceLabel = proposal.hourlyRate > 0
        ? '${proposal.hourlyRate.toStringAsFixed(2)} €/h'
        : 'Preço a definir';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: recommended ? AppColors.primary : AppColors.divider,
            ),
          ),
          child: Column(
            children: [
              InkWell(
                onTap: ratingSummary != null && ratingSummary.ratingCount > 0
                    ? () => showRatingsSheet(
                          context,
                          workerId: proposal.workerId,
                          workerName: workerName,
                        )
                    : null,
                borderRadius: BorderRadius.circular(AppRadius.input),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: AppColors.primaryContainer,
                      backgroundImage:
                          workerAvatarUrl.isNotEmpty ? NetworkImage(workerAvatarUrl) : null,
                      child: workerAvatarUrl.isEmpty
                          ? const Icon(Icons.person_outline_rounded, color: AppColors.primary)
                          : null,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            workerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            ratingSummary != null && ratingSummary.ratingCount > 0
                                ? '★ ${ratingSummary.avgRating.toStringAsFixed(1)} '
                                    '(${ratingSummary.ratingCount})'
                                : 'Sem avaliações ainda',
                            style: textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            'Enviada ${_relativeTimeLabel(proposal.createdAt)}',
                            style: textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          priceLabel,
                          style: textTheme.titleLarge?.copyWith(color: AppColors.primary),
                        ),
                        if (hoursStr.isNotEmpty)
                          Text(
                            hoursStr,
                            style: textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (scheduleStr.isNotEmpty ||
                  proposal.peopleNeeded > 1 ||
                  teamEstimateStr.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    if (scheduleStr.isNotEmpty)
                      _MetaChip(icon: Icons.event_outlined, label: scheduleStr),
                    if (proposal.peopleNeeded > 1)
                      _MetaChip(
                        icon: Icons.group_outlined,
                        label: 'Equipa: ${proposal.peopleNeeded} pessoas',
                      ),
                    if (teamEstimateStr.isNotEmpty)
                      _MetaChip(icon: Icons.calculate_outlined, label: teamEstimateStr),
                  ],
                ),
              ],
              if (proposal.notes?.isNotEmpty == true) ...[
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    proposal.notes!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              PrimaryActionButton(
                label: 'Escolher',
                isLoading: accepting,
                onPressed: accepting ? null : onAccept,
              ),
            ],
          ),
        ),
        if (recommended)
          Positioned(
            top: -8,
            left: AppSpacing.sm,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                'Recomendada',
                style: textTheme.labelMedium?.copyWith(color: AppColors.surface),
              ),
            ),
          ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: AppSpacing.xxs),
          Text(label, style: textTheme.labelMedium?.copyWith(color: AppColors.primary)),
        ],
      ),
    );
  }
}

// ── Sheet de confirmação de aceitação ───────────────────────────────────────

class _AcceptOutcome {
  const _AcceptOutcome.accepted()
      : isAccepted = true,
        isUnavailable = false,
        errorMessage = null;
  const _AcceptOutcome.unavailable()
      : isAccepted = false,
        isUnavailable = true,
        errorMessage = null;
  const _AcceptOutcome.failed(this.errorMessage)
      : isAccepted = false,
        isUnavailable = false;

  final bool isAccepted;
  final bool isUnavailable;
  final String? errorMessage;
}

enum _SheetState { confirmation, unavailable }

class _AcceptProposalSheet extends StatefulWidget {
  const _AcceptProposalSheet({
    required this.proposal,
    required this.serviceLabel,
    required this.onAccept,
  });

  final JobProposal proposal;
  final String serviceLabel;
  final Future<_AcceptOutcome> Function() onAccept;

  @override
  State<_AcceptProposalSheet> createState() => _AcceptProposalSheetState();
}

class _AcceptProposalSheetState extends State<_AcceptProposalSheet> {
  bool _submitting = false;
  _SheetState _sheetState = _SheetState.confirmation;

  Future<void> _accept() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    final result = await widget.onAccept();
    if (!mounted) return;

    if (result.isAccepted) {
      Navigator.of(context).pop(true);
      return;
    }

    if (result.isUnavailable) {
      setState(() {
        _submitting = false;
        _sheetState = _SheetState.unavailable;
      });
      return;
    }

    setState(() => _submitting = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(result.errorMessage ?? 'Não foi possível aceitar. Tenta novamente.'),
        action: SnackBarAction(label: 'Repetir', onPressed: _accept),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return PopScope(
      canPop: !_submitting,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md + keyboardInset,
        ),
        child: AppFadeThroughSwitcher(
          switchKey: _sheetState,
          duration: const Duration(milliseconds: 220),
          child: _sheetState == _SheetState.unavailable
              ? _UnavailableProposal(
                  key: const ValueKey('proposal_unavailable'),
                  onBackToProposals: () => Navigator.of(context).pop(false),
                )
              : _ProposalConfirmation(
                  key: const ValueKey('proposal_confirmation'),
                  proposal: widget.proposal,
                  serviceLabel: widget.serviceLabel,
                  submitting: _submitting,
                  onConfirm: _accept,
                  onBack: _submitting ? null : () => Navigator.of(context).pop(false),
                ),
        ),
      ),
    );
  }
}

class _ProposalConfirmation extends StatelessWidget {
  const _ProposalConfirmation({
    super.key,
    required this.proposal,
    required this.serviceLabel,
    required this.submitting,
    required this.onConfirm,
    required this.onBack,
  });

  final JobProposal proposal;
  final String serviceLabel;
  final bool submitting;
  final VoidCallback onConfirm;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final priceLabel = proposal.hourlyRate > 0
        ? '${proposal.hourlyRate.toStringAsFixed(2)} €/h'
        : 'preço a definir';
    final proposalDateLabel = _formatProposedSchedule(proposal);

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppStaggeredEntrance(
            index: 0,
            child: Text(
              'Aceitar esta proposta?',
              style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppStaggeredEntrance(
            index: 1,
            child: Text(
              'O profissional recebe a confirmação e o trabalho fica agendado. '
              'As outras propostas são recusadas automaticamente.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppStaggeredEntrance(
            index: 2,
            child: _ProposalSummaryCard(proposal: proposal),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppStaggeredEntrance(
            index: 3,
            child: _AcceptanceDetails(
              serviceLabel: serviceLabel,
              proposalDateLabel: proposalDateLabel.isEmpty ? 'A combinar' : proposalDateLabel,
              // Sem processamento de pagamento na app — o valor é sempre
              // combinado diretamente entre cliente e prestador.
              paymentTimingLabel: 'Combinado diretamente com o profissional',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppStaggeredEntrance(
            index: 4,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Depois de aceitares, podes cancelar até 24h antes da data combinada.',
                    style: textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryActionButton(
            label: submitting ? 'A confirmar...' : 'Aceitar proposta · $priceLabel',
            onPressed: submitting ? null : onConfirm,
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: onBack,
            child: Text(
              'Voltar às propostas',
              style: textTheme.bodyMedium?.copyWith(
                color: onBack == null ? AppStatusColor.neutral.foreground : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProposalSummaryCard extends StatelessWidget {
  const _ProposalSummaryCard({required this.proposal});

  final JobProposal proposal;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final workerName =
        proposal.workerName?.isNotEmpty == true ? proposal.workerName! : '—';
    final workerAvatarUrl = proposal.workerAvatarUrl ?? '';
    final priceLabel = proposal.hourlyRate > 0
        ? '${proposal.hourlyRate.toStringAsFixed(2)} €/h'
        : 'Preço a definir';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primaryContainer,
            backgroundImage: workerAvatarUrl.isNotEmpty ? NetworkImage(workerAvatarUrl) : null,
            child: workerAvatarUrl.isEmpty
                ? const Icon(Icons.person_outline_rounded, color: AppColors.primary)
                : null,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workerName,
                  style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
          Text(priceLabel, style: textTheme.titleLarge?.copyWith(color: AppColors.primary)),
        ],
      ),
    );
  }
}

class _AcceptanceDetails extends StatelessWidget {
  const _AcceptanceDetails({
    required this.serviceLabel,
    required this.proposalDateLabel,
    required this.paymentTimingLabel,
  });

  final String serviceLabel;
  final String proposalDateLabel;
  final String paymentTimingLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        children: [
          _DetailRow(label: 'Serviço', value: serviceLabel),
          const SizedBox(height: AppSpacing.sm),
          _DetailRow(label: 'Data proposta', value: proposalDateLabel),
          const SizedBox(height: AppSpacing.sm),
          _DetailRow(label: 'Pagamento', value: paymentTimingLabel),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
        ),
        const SizedBox(width: AppSpacing.md),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: textTheme.bodyMedium
                ?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _UnavailableProposal extends StatelessWidget {
  const _UnavailableProposal({super.key, required this.onBackToProposals});

  final VoidCallback onBackToProposals;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppStatusColor.cancelled.background,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded, color: AppStatusColor.cancelled.foreground),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: 'Esta proposta já não está disponível. ',
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppStatusColor.cancelled.foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: 'O profissional retirou-a ou o prazo terminou.',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: AppStatusColor.cancelled.foreground),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onBackToProposals,
            child: Text(
              'Ver outras propostas',
              style: textTheme.bodyMedium
                  ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

// ── helpers ──────────────────────────────────────────────────────────────

String _formatProposedSchedule(JobProposal proposal) {
  if (proposal.scheduledDate == null) return '';
  final date = DateFormat('dd/MM/yyyy').format(proposal.scheduledDate!);
  if (proposal.scheduledFlexible) return '$date (horário flexível)';
  if (proposal.scheduledTime != null) return '$date às ${proposal.scheduledTime}';
  return date;
}

String _hoursLabel(double? min, double? max) {
  if (min != null && max != null) return '${min.toStringAsFixed(1)} - ${max.toStringAsFixed(1)} h';
  if (min != null) return '${min.toStringAsFixed(1)} h';
  if (max != null) return '${max.toStringAsFixed(1)} h';
  return '';
}

String _teamTotalEstimate(JobProposal p) {
  if (p.peopleNeeded <= 1 || p.hourlyRate <= 0) return '';
  final factor = p.helpersEquipmentRequired ? 1.0 : 0.75;
  final multiplier = 1 + (p.peopleNeeded - 1) * factor;
  final min = p.estimatedHoursMin;
  final max = p.estimatedHoursMax;
  if (min != null && max != null) {
    final lo = (p.hourlyRate * min * multiplier).round();
    final hi = (p.hourlyRate * max * multiplier).round();
    return '≈ €$lo - €$hi (equipa incluída)';
  } else if (min != null) {
    return '≈ €${(p.hourlyRate * min * multiplier).round()} (equipa incluída)';
  } else if (max != null) {
    return '≈ €${(p.hourlyRate * max * multiplier).round()} (equipa incluída)';
  }
  return '';
}

/// Substitui `expiryLabel` do mock original (doc.txt) — não há prazo por
/// proposta no schema (`job_proposals` não tem coluna de expiração própria,
/// só `job_requests.expires_at` para o pedido inteiro). Mostra há quanto
/// tempo a proposta foi enviada, um dado real, em vez de inventar um prazo.
String _relativeTimeLabel(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'agora';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'há ${diff.inHours}h';
  final days = diff.inDays;
  return 'há $days ${days == 1 ? 'dia' : 'dias'}';
}
