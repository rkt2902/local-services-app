import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/photo_viewer_screen.dart';
import '../../../core/widgets/status_timeline.dart';
import '../../auth/application/auth_providers.dart';
import '../../jobs/application/job_timeline.dart';
import '../../client/application/client_providers.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/data/job_model.dart';
import '../../jobs/presentation/widgets/cancel_job_dialog.dart';
import '../../jobs/presentation/widgets/reschedule_dialog.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../proposals/data/proposal_model.dart';
import '../../ratings/application/rating_providers.dart';
import '../../ratings/presentation/rating_sheet.dart';

class WorkerMyJobDetailScreen extends ConsumerStatefulWidget {
  const WorkerMyJobDetailScreen({
    super.key,
    required this.proposal,
    required this.job,
  });

  final JobProposal proposal;
  final JobRequest job;

  @override
  ConsumerState<WorkerMyJobDetailScreen> createState() =>
      _WorkerMyJobDetailScreenState();
}

class _WorkerMyJobDetailScreenState
    extends ConsumerState<WorkerMyJobDetailScreen> {
  bool _completing = false;
  bool _withdrawing = false;
  bool _cancellingJob = false;
  bool _proposingReschedule = false;
  bool _acceptingReschedule = false;
  bool _rejectingReschedule = false;

  Future<void> _cancelJob() async {
    final result = await CancelJobDialog.show(context, isClient: false);
    if (result == null || !mounted) return;

    setState(() => _cancellingJob = true);
    final scaffold = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      final newJobId = await ref.read(jobRepositoryProvider).cancelJob(
            jobId: widget.job.id,
            reason: result['reason']!,
            reasonDetail: result['reasonDetail'],
          );
      invalidateAllWorkerProposalProviders(ref);
      ref.invalidate(jobsInRadiusProvider);
      scaffold.showSnackBar(SnackBar(
        content: Text(newJobId != null
            ? 'Pedido cancelado. O cliente foi notificado e o pedido foi reaberto.'
            : 'Pedido cancelado.'),
      ));
      router.go('/worker/home');
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _cancellingJob = false);
    }
  }

  Future<void> _proposeReschedule() async {
    final result = await RescheduleDialog.show(context);
    if (result == null || !mounted) return;

    setState(() => _proposingReschedule = true);
    final scaffold = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref.read(jobRepositoryProvider).proposeReschedule(
            jobId: widget.job.id,
            newDate: result['date'] as DateTime,
            newTime: result['time'] as String?,
            newFlexible: result['flexible'] as bool,
          );
      ref.invalidate(scheduledWorkerProposalsProvider);
      scaffold.showSnackBar(
          const SnackBar(content: Text('Remarcação enviada.')));
      router.pop();
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _proposingReschedule = false);
    }
  }

  Future<void> _acceptReschedule() async {
    setState(() => _acceptingReschedule = true);
    final scaffold = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref.read(jobRepositoryProvider).acceptReschedule(widget.job.id);
      ref.invalidate(scheduledWorkerProposalsProvider);
      scaffold.showSnackBar(
          const SnackBar(content: Text('Nova data aceite.')));
      router.pop();
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _acceptingReschedule = false);
    }
  }

  Future<void> _rejectReschedule() async {
    setState(() => _rejectingReschedule = true);
    final scaffold = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref.read(jobRepositoryProvider).rejectReschedule(widget.job.id);
      ref.invalidate(scheduledWorkerProposalsProvider);
      scaffold.showSnackBar(
          const SnackBar(content: Text('Remarcação recusada.')));
      router.pop();
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _rejectingReschedule = false);
    }
  }

  Future<void> _withdrawProposal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Retirar proposta?'),
        content: const Text(
            'O pedido ficará disponível para outros jardineiros.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Não'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Retirar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _withdrawing = true);
    final scaffold = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref
          .read(proposalRepositoryProvider)
          .withdrawProposal(widget.proposal.id, widget.job.id);
      ref.invalidate(pendingWorkerProposalsProvider);
      router.pop();
      scaffold.showSnackBar(
          const SnackBar(content: Text('Proposta retirada.')));
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  Future<void> _openWhatsApp(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[\s\-()]'), '');
    final uri = Uri.parse('https://wa.me/$clean');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _markCompleted() async {
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Tens a certeza?'),
        content: const Text('Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Não'),
          ),
          FilledButton(
            onPressed: _completing ? null : () async {
              final dialogNavigator = Navigator.of(dialogCtx);
              final scaffold = ScaffoldMessenger.of(context);
              final router = GoRouter.of(context);
              setState(() => _completing = true);
              try {
                await ref
                    .read(proposalRepositoryProvider)
                    .markJobCompleted(widget.job.id);
                ref.invalidate(scheduledWorkerProposalsProvider);
                ref.invalidate(completedWorkerProposalsProvider);
                ref.invalidate(jobsInRadiusProvider);
                dialogNavigator.pop();
                router.go('/worker/home');
                scaffold.showSnackBar(
                  const SnackBar(
                      content: Text('Trabalho marcado como concluído!')),
                );
              } catch (e) {
                dialogNavigator.pop();
                scaffold.showSnackBar(
                  SnackBar(
                      content: Text(friendlyError(e)),
                      backgroundColor: Colors.red),
                );
              } finally {
                if (mounted) setState(() => _completing = false);
              }
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUserId = ref.watch(currentUserIdProvider);
    final serviceTypesAsync = ref.watch(serviceTypesProvider);
    final photosAsync = ref.watch(jobPhotosProvider(widget.job.id));
    final clientInfoAsync =
        ref.watch(clientBasicInfoProvider(widget.job.clientId));

    final serviceType = serviceTypesAsync.value
        ?.where((s) => s.id == widget.job.serviceTypeId)
        .firstOrNull;

    final liveStatus = ref
        .watch(proposalByIdProvider(widget.proposal.id))
        .asData?.value?.status ?? widget.proposal.status;

    final liveJobStatus = ref
        .watch(jobByIdProvider(widget.job.id))
        .asData?.value?.status ?? widget.job.status;

    final helpersForRatingAsync =
        ref.watch(acceptedHelpersForJobProvider(widget.job.id));

    final (statusLabel, statusColor) = _proposalStatusInfo(liveStatus);

    final estimate = _formatEstimate(
      widget.proposal.hourlyRate,
      widget.proposal.estimatedHoursMin,
      widget.proposal.estimatedHoursMax,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('O meu trabalho')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status badge
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                statusLabel,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: Colors.white),
              ),
            ),
            const SizedBox(height: 24),

            // Job details
            Text('Trabalho', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _SectionCard(children: [
              _infoRow(context, Icons.yard_outlined, 'Serviço',
                  serviceType?.name ?? '—'),
              _infoRow(context, Icons.calendar_today_outlined, 'Data',
                  _formatDate(widget.job.preferredDate)),
              if (widget.job.addressText.isNotEmpty)
                _infoRow(context, Icons.place_outlined, 'Localização',
                    widget.job.addressText),
              _infoRow(
                  context,
                  Icons.bolt_outlined,
                  'Urgência',
                  widget.job.urgency == Urgency.urgent
                      ? 'Urgente'
                      : 'Normal'),
              if (widget.job.sizeEstimate != null)
                _infoRow(context, Icons.straighten_outlined, 'Dimensão',
                    _sizeLabel(widget.job.sizeEstimate!)),
            ]),
            const SizedBox(height: 20),

            // Description
            Text('Descrição', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(widget.job.description,
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 20),

            // Photos
            photosAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (photos) {
                if (photos.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Fotos', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: photos.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: 8),
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PhotoViewerScreen(
                                photoUrls: photos,
                                initialIndex: i,
                              ),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              photos[i],
                              width: 120,
                              height: 120,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                );
              },
            ),

            // Proposal details
            Text('A minha proposta', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _SectionCard(children: [
              _infoRow(context, Icons.euro_outlined, 'Taxa/hora',
                  widget.proposal.hourlyRate > 0
                      ? '${widget.proposal.hourlyRate.toStringAsFixed(2)} €/h'
                      : 'Preço a definir'),
              if (widget.proposal.estimatedHoursMin != null ||
                  widget.proposal.estimatedHoursMax != null)
                _infoRow(
                    context,
                    Icons.schedule_outlined,
                    'Horas estimadas',
                    _hoursLabel(widget.proposal.estimatedHoursMin,
                        widget.proposal.estimatedHoursMax)),
              if (estimate.isNotEmpty)
                _infoRow(context, Icons.calculate_outlined,
                    'Total estimado', estimate),
              _infoRow(context, Icons.group_outlined, 'Pessoas',
                  '${widget.proposal.peopleNeeded}'),
              if (widget.proposal.notes?.isNotEmpty == true)
                _infoRow(context, Icons.notes_outlined, 'Notas',
                    widget.proposal.notes!),
            ]),
            const SizedBox(height: 20),

            // Job state timeline
            Text('Estado do pedido', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            StatusTimeline(
              steps: buildJobTimeline(
                widget.job.copyWith(status: liveJobStatus),
              ),
            ),
            const SizedBox(height: 20),

            // === ACCEPTED ===
            if (liveStatus == ProposalStatus.accepted) ...[
              // Reschedule banner
              if (widget.job.rescheduleStatus == RescheduleStatus.pending) ...[
                if (widget.job.rescheduleProposedBy != null &&
                    widget.job.rescheduleProposedBy != currentUserId)
                  Card(
                    color: Colors.orange.shade50,
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            Icon(Icons.event_repeat,
                                color: Colors.orange.shade800, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'O cliente propôs remarcar para ${_proposedRescheduleLabel(widget.job)}'
                                    .trim(),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.orange.shade900),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: _acceptingReschedule
                                    ? null
                                    : _acceptReschedule,
                                child: _acceptingReschedule
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white),
                                      )
                                    : const Text('Aceitar nova data'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _rejectingReschedule
                                    ? null
                                    : _rejectReschedule,
                                child: const Text('Recusar'),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  )
                else
                  Card(
                    color: Colors.grey.shade100,
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        Icon(Icons.schedule_outlined,
                            color: Colors.grey.shade600),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Aguarda resposta à remarcação que propuseste para ${_proposedRescheduleLabel(widget.job)}'
                                .trim(),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ]),
                    ),
                  ),
              ],
              if ((widget.job.status == JobStatus.confirmed ||
                      liveJobStatus == JobStatus.awaitingConfirmation) &&
                  widget.job.confirmedDate != null) ...[
                Text('Agendamento', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                _SectionCard(children: [
                  _infoRow(
                    context,
                    Icons.event_available_outlined,
                    'Agendado para',
                    _confirmedScheduleLabel(widget.job),
                  ),
                ]),
                const SizedBox(height: 20),
              ],
              Text('Cliente', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              clientInfoAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (_, _) => const Text(
                    'Não foi possível carregar o contacto.'),
                data: (info) {
                  final phone = info['phone'] ?? '';
                  return Card(
                    color: theme.colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            Icon(Icons.person_outlined,
                                color:
                                    theme.colorScheme.onPrimaryContainer),
                            const SizedBox(width: 8),
                            Text(
                              info['full_name']?.isNotEmpty == true
                                  ? info['full_name']!
                                  : '—',
                              style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme
                                      .colorScheme.onPrimaryContainer),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: phone.isEmpty
                                ? null
                                : () => _openWhatsApp(phone),
                            icon: const Icon(Icons.chat_outlined),
                            label:
                                const Text('Contactar via WhatsApp'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              if (widget.proposal.peopleNeeded > 1) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Icon(Icons.info_outline,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Este trabalho requer '
                          '${widget.proposal.peopleNeeded} pessoas. '
                          'A funcionalidade de equipa estará disponível em breve.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // Cancel + reschedule buttons — only when job is live-confirmed
              if (liveJobStatus == JobStatus.confirmed) ...[
                if (widget.job.rescheduleStatus == RescheduleStatus.pending)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Aguarda resposta da remarcação',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (widget.job.rescheduleStatus == RescheduleStatus.pending ||
                              _proposingReschedule)
                          ? null
                          : _proposeReschedule,
                      icon: const Icon(Icons.event_repeat),
                      label: const Text('Remarcar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (widget.job.rescheduleStatus == RescheduleStatus.pending ||
                              _cancellingJob ||
                              (widget.job.confirmedDate != null &&
                               widget.job.confirmedDate!.difference(DateTime.now()).inHours < 24))
                          ? null
                          : _cancelJob,
                      style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error),
                      icon: const Icon(Icons.close),
                      label: const Text('Cancelar'),
                    ),
                  ),
                ]),
                if (widget.job.confirmedDate != null &&
                    widget.job.confirmedDate!.difference(DateTime.now()).inHours < 24) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Cancelamento disponível até 24h antes da data confirmada.',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 16),
              ],
              if (liveJobStatus == JobStatus.awaitingConfirmation)
                Card(
                  color: theme.colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Icon(Icons.hourglass_top,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Aguarda confirmação do cliente. Já marcaste este trabalho como concluído.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ]),
                  ),
                )
              else if (liveJobStatus == JobStatus.confirmed)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _completing ? null : _markCompleted,
                    child: _completing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Marcar como concluído'),
                  ),
                )
              else if (liveJobStatus == JobStatus.completed)
                _buildCompletedSection(theme, helpersForRatingAsync),
            ],

            // === REJECTED ===
            if (liveStatus == ProposalStatus.rejected) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Icon(Icons.info_outline,
                        color: theme.colorScheme.error),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                          'A tua proposta não foi selecionada. O cliente escolheu outra proposta.'),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              clientInfoAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (info) {
                  final phone = info['phone'] ?? '';
                  if (phone.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _openWhatsApp(phone),
                        icon: const Icon(Icons.chat_outlined),
                        label: const Text(
                            'Contactar cliente para novo pedido'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Podes contactar o cliente para negociar e enviar uma nova proposta.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color:
                                theme.colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  );
                },
              ),
            ],

            // === SUPERSEDED ===
            if (liveStatus == ProposalStatus.superseded) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Icon(Icons.undo,
                        color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                          'Retiraste a tua proposta para este pedido.'),
                    ),
                  ]),
                ),
              ),
            ],

            // === PENDING ===
            if (liveStatus == ProposalStatus.pending) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Icon(Icons.schedule_outlined,
                        color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                          'A tua proposta está a aguardar resposta do cliente.'),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _withdrawing ? null : _withdrawProposal,
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red),
                  child: _withdrawing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Retirar proposta'),
                ),
              ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletedSection(
    ThemeData theme,
    AsyncValue<List<AcceptedHelper>> helpersAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Card(
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(Icons.task_alt, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              const Expanded(
                  child: Text('Trabalho concluído. Obrigado pelo teu trabalho!')),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        Text('Deixa a tua avaliação', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _PrincipalRatingCard(
          jobId: widget.job.id,
          rateeId: widget.job.clientId,
          title: 'Avaliar o cliente',
          submittedLabel: 'Cliente avaliado ✓',
          onSubmit: (stars, comment) =>
              ref.read(ratingRepositoryProvider).submitPrincipalRating(
                    jobId: widget.job.id,
                    rateeId: widget.job.clientId,
                    stars: stars,
                    comment: comment,
                  ),
        ),
        ...helpersAsync.when(
          loading: () =>
              [const SizedBox(height: 8, child: LinearProgressIndicator())],
          error: (_, _) => <Widget>[],
          data: (helpers) => [
            for (final h in helpers)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _PrincipalRatingCard(
                  jobId: widget.job.id,
                  rateeId: h.workerId,
                  title: 'Avaliar: ${h.fullName}',
                  submittedLabel: '${h.fullName} avaliado ✓',
                  onSubmit: (stars, comment) =>
                      ref.read(ratingRepositoryProvider).submitPrincipalRating(
                            jobId: widget.job.id,
                            rateeId: h.workerId,
                            stars: stars,
                            comment: comment,
                          ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ── _PrincipalRatingCard ──────────────────────────────────────────────────────

class _PrincipalRatingCard extends ConsumerStatefulWidget {
  const _PrincipalRatingCard({
    required this.jobId,
    required this.rateeId,
    required this.title,
    required this.submittedLabel,
    required this.onSubmit,
  });

  final String jobId;
  final String rateeId;
  final String title;
  final String submittedLabel;
  final Future<void> Function(int stars, String? comment) onSubmit;

  @override
  ConsumerState<_PrincipalRatingCard> createState() =>
      _PrincipalRatingCardState();
}

class _PrincipalRatingCardState extends ConsumerState<_PrincipalRatingCard> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratingAsync = ref.watch(
        myRatingForJobAndRateeProvider((widget.jobId, widget.rateeId)));

    return ratingAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => const SizedBox.shrink(),
      data: (existing) {
        if (existing != null) {
          return Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                Icon(Icons.check_circle,
                    color: theme.colorScheme.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(widget.submittedLabel,
                        style: theme.textTheme.bodyMedium)),
                Row(
                  children: List.generate(
                    5,
                    (i) => Icon(
                      i < existing.stars
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 16,
                      color: Colors.amber,
                    ),
                  ),
                ),
              ]),
            ),
          );
        }
        return Card(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Expanded(
                  child: Text(widget.title,
                      style: theme.textTheme.bodyMedium)),
              FilledButton.tonal(
                onPressed: _showSheet,
                child: const Text('Avaliar'),
              ),
            ]),
          ),
        );
      },
    );
  }

  Future<void> _showSheet() async {
    final submitted = await showRatingSheet(
      context: context,
      title: widget.title,
      onSubmit: widget.onSubmit,
    );
    if (submitted != true || !mounted) return;
    ref.invalidate(
        myRatingForJobAndRateeProvider((widget.jobId, widget.rateeId)));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Avaliação enviada!')));
  }
}

// ── helpers ──────────────────────────────────────────────────────────────────

String _proposedRescheduleLabel(JobRequest job) {
  if (job.rescheduleProposedDate == null) return '';
  final date = DateFormat('dd/MM/yyyy').format(job.rescheduleProposedDate!);
  if (job.rescheduleProposedFlexible == true) return '$date (horário flexível)';
  if (job.rescheduleProposedTime != null) {
    return '$date às ${job.rescheduleProposedTime}';
  }
  return date;
}

String _confirmedScheduleLabel(JobRequest job) {
  if (job.confirmedDate == null) return '';
  final date = DateFormat('dd/MM/yyyy').format(job.confirmedDate!);
  if (job.confirmedFlexible) return '$date (horário flexível)';
  if (job.confirmedTime != null) return '$date às ${job.confirmedTime}';
  return date;
}

(String, Color) _proposalStatusInfo(ProposalStatus status) => switch (status) {
      ProposalStatus.pending => ('Aguarda resposta', Colors.orange.shade700),
      ProposalStatus.accepted => ('Aceite', Colors.green.shade600),
      ProposalStatus.rejected => ('Não selecionada', Colors.red.shade600),
      ProposalStatus.superseded => ('Substituída', Colors.grey.shade500),
    };

String _formatDate(DateTime? date) {
  if (date == null) return 'Flexível';
  return DateFormat('dd/MM/yyyy').format(date);
}

String _sizeLabel(SizeEstimate size) => switch (size) {
      SizeEstimate.small => 'Pequeno',
      SizeEstimate.medium => 'Médio',
      SizeEstimate.large => 'Grande',
    };

String _formatEstimate(double rate, double? min, double? max) {
  if (min != null && max != null) {
    return '≈ €${(rate * min).toStringAsFixed(0)} - €${(rate * max).toStringAsFixed(0)}';
  } else if (min != null) {
    return '≈ €${(rate * min).toStringAsFixed(0)}';
  } else if (max != null) {
    return '≈ €${(rate * max).toStringAsFixed(0)}';
  }
  return '';
}

String _hoursLabel(double? min, double? max) {
  if (min != null && max != null) {
    return '${min.toStringAsFixed(1)} - ${max.toStringAsFixed(1)} h';
  } else if (min != null) {
    return '${min.toStringAsFixed(1)} h';
  } else if (max != null) {
    return '${max.toStringAsFixed(1)} h';
  }
  return '';
}

Widget _infoRow(
    BuildContext context, IconData icon, String label, String value) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              Text(value, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(children: children),
        ),
      );
}
