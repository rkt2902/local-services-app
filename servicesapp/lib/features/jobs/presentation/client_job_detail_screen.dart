import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/error_utils.dart';
import '../../auth/application/auth_providers.dart';
import '../application/job_providers.dart';
import '../data/job_model.dart';
import '../../proposals/data/proposal_model.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../worker/application/worker_providers.dart';
import '../../../core/widgets/address_map_link.dart';
import '../../../core/widgets/photo_viewer_screen.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../../core/widgets/app_filter_chip.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_status_badge.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../../../core/widgets/status_timeline.dart';
import '../../../core/widgets/user_avatar_with_name.dart';
import '../application/job_timeline.dart';
import '../../help_requests/application/help_request_providers.dart';
import '../../help_requests/data/help_request_model.dart';
import '../../ratings/application/rating_providers.dart';
import '../../ratings/presentation/rating_sheet.dart';
import '../../ratings/presentation/ratings_sheet.dart';
import 'widgets/cancel_job_dialog.dart';
import 'widgets/reschedule_dialog.dart';

class ClientJobDetailScreen extends ConsumerStatefulWidget {
  const ClientJobDetailScreen({super.key, required this.jobId});

  final String jobId;

  @override
  ConsumerState<ClientJobDetailScreen> createState() =>
      _ClientJobDetailScreenState();
}

class _ClientJobDetailScreenState
    extends ConsumerState<ClientJobDetailScreen> {
  bool _saving = false;
  bool _proposingReschedule = false;
  bool _confirming = false;
  bool _showCompletedFeedback = false;
  String? _selectedProblemId;
  final Map<String, bool> _accepting = {};
  final Set<String> _approvingHelp = {};
  String _sortBy = 'price';

  /// Lista fixa só do lado do Flutter — sem coluna nova em `job_reports`
  /// (que só tem id/job_id/reporter_id/description/created_at). Ao
  /// selecionar, pré-preenche o texto livre existente; não muda o schema.
  static const _commonProblems = [
    (id: 'no_show', label: 'Não apareceu', prefill: 'O prestador não apareceu — '),
    (id: 'late', label: 'Atraso', prefill: 'O prestador chegou com atraso — '),
    (id: 'incomplete', label: 'Incompleto', prefill: 'O trabalho ficou incompleto — '),
  ];

  Future<void> _cancelJob() async {
    final job = ref.read(jobByIdProvider(widget.jobId)).value;
    if (job == null) return;

    // Open jobs have no confirmed worker — simple confirmation, no reason picker
    if (job.status == JobStatus.open) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Cancelar pedido?'),
          content:
              const Text('Tens a certeza que queres cancelar este pedido?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Voltar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Cancelar pedido'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() => _saving = true);
      final scaffold = ScaffoldMessenger.of(context);
      final router = GoRouter.of(context);
      var navigatedAway = false;
      try {
        await ref.read(jobRepositoryProvider).cancelJob(
              jobId: widget.jobId,
              reason: 'no_longer_needed',
              reasonDetail: null,
            );
        navigatedAway = true;
        router.go('/client/jobs');
        scaffold.showSnackBar(
            const SnackBar(content: Text('Pedido cancelado.')));
        ref.invalidate(clientJobsProvider);
        ref.invalidate(pendingProposalsForJobProvider(widget.jobId));
      } catch (e) {
        scaffold.showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      } finally {
        if (!navigatedAway && mounted) setState(() => _saving = false);
      }
      return;
    }

    // Confirmed jobs — step 1: reason picker
    final result = await CancelJobDialog.show(context, isClient: true);
    if (result == null || !mounted) return;

    // Step 2: ask if client wants to republish for a new worker
    final wantsReopen = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Voltar a publicar?'),
        content: const Text(
            'Queres voltar a publicar este pedido para encontrar outro prestador?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sim'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    setState(() => _saving = true);
    final scaffold = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    var navigatedAway = false;
    try {
      final newJobId = await ref.read(jobRepositoryProvider).cancelJob(
            jobId: widget.jobId,
            reason: result['reason']!,
            reasonDetail: result['reasonDetail'],
            clientWantsReopen: wantsReopen ?? false,
          );
      navigatedAway = true;
      router.go('/client/jobs');
      if (newJobId != null) {
        scaffold.showSnackBar(
          const SnackBar(
              content: Text(
                  'Pedido cancelado e reaberto para encontrar outro prestador.')),
        );
      } else {
        scaffold.showSnackBar(const SnackBar(content: Text('Pedido cancelado.')));
      }
      ref.invalidate(clientJobsProvider);
      ref.invalidate(pendingProposalsForJobProvider(widget.jobId));
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (!navigatedAway && mounted) setState(() => _saving = false);
    }
  }

  Future<void> _proposeReschedule() async {
    final result = await RescheduleDialog.show(context);
    if (result == null || !mounted) return;

    setState(() => _proposingReschedule = true);
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await ref.read(jobRepositoryProvider).proposeReschedule(
            jobId: widget.jobId,
            newDate: result['date'] as DateTime,
            newTime: result['time'] as String?,
            newFlexible: result['flexible'] as bool,
          );
      ref.invalidate(clientJobsProvider);
      ref.invalidate(jobByIdProvider(widget.jobId));
      scaffold.showSnackBar(
        const SnackBar(content: Text('Remarcação enviada.')),
      );
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _proposingReschedule = false);
    }
  }

  Future<void> _acceptReschedule() async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await ref.read(jobRepositoryProvider).acceptReschedule(widget.jobId);
      ref.invalidate(clientJobsProvider);
      ref.invalidate(jobByIdProvider(widget.jobId));
      scaffold.showSnackBar(
        const SnackBar(content: Text('Nova data aceite.')),
      );
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _rejectReschedule() async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await ref.read(jobRepositoryProvider).rejectReschedule(widget.jobId);
      ref.invalidate(clientJobsProvider);
      ref.invalidate(jobByIdProvider(widget.jobId));
      scaffold.showSnackBar(
        const SnackBar(content: Text('Remarcação recusada.')),
      );
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    }
  }

  /// Devolve true só depois da RPC confirmar sucesso — a navegação/snackbar
  /// ficam em [_handleConfirmCompleted], que mostra o AppSuccessFeedback
  /// antes de sair do ecrã.
  Future<bool> _confirmJobCompletion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Confirmar conclusão'),
        content: const Text(
            'Confirmas que o trabalho foi concluído conforme esperado?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;

    setState(() => _confirming = true);
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(proposalRepositoryProvider)
          .confirmJobCompletion(widget.jobId);
      ref.invalidate(clientJobsProvider);
      return true;
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(
            content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
      return false;
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _handleConfirmCompleted() async {
    final success = await _confirmJobCompletion();
    if (!mounted || !success) return;

    setState(() => _showCompletedFeedback = true);
    final scaffold = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    await Future<void>.delayed(
      disableAnimations ? Duration.zero : const Duration(milliseconds: 900),
    );
    if (!mounted) return;

    setState(() => _showCompletedFeedback = false);
    scaffold.showSnackBar(
      const SnackBar(content: Text('Trabalho confirmado! Obrigado.')),
    );
    router.go('/client/jobs');
  }

  Future<void> _reportProblem({String prefillText = ''}) async {
    final formKey = GlobalKey<FormState>();
    final descController = TextEditingController(text: prefillText)
      ..selection = TextSelection.collapsed(offset: prefillText.length);
    final scaffold = ScaffoldMessenger.of(context);

    bool submitting = false;
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Reportar problema',
                      style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Descreve o que aconteceu. O teu relato fica registado para referência futura.',
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: descController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Descrição do problema',
                      alignLabelWithHint: true,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().length < 10) {
                        return 'Descreve o problema (mínimo 10 caracteres).';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: submitting
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            setSheetState(() => submitting = true);
                            try {
                              await ref
                                  .read(proposalRepositoryProvider)
                                  .reportJobProblem(
                                    jobId: widget.jobId,
                                    description: descController.text.trim(),
                                  );
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } catch (e) {
                              setSheetState(() => submitting = false);
                              scaffold.showSnackBar(SnackBar(
                                  content: Text(friendlyError(e)),
                                  backgroundColor: Colors.red));
                            }
                          },
                    child: submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Enviar relato'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    descController.dispose();
    if (submitted != true || !mounted) return;

    scaffold.showSnackBar(
      const SnackBar(
          content: Text('Relato enviado. A nossa equipa vai analisar.')),
    );

    if (!mounted) return;
    final confirmAnyway = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Confirmar conclusão?'),
        content: const Text(
            'Queres confirmar a conclusão do trabalho mesmo assim?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Ainda não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Sim, confirmar'),
          ),
        ],
      ),
    );
    if (confirmAnyway == true && mounted) {
      await _handleConfirmCompleted();
    }
  }

  Future<void> _acceptProposal(JobProposal proposal) async {
    setState(() => _accepting[proposal.id] = true);
    final scaffold = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref
          .read(proposalRepositoryProvider)
          .acceptProposal(proposal.id, widget.jobId);
      ref.invalidate(clientJobsProvider);
      ref.invalidate(pendingProposalsForJobProvider(widget.jobId));
      ref.invalidate(jobByIdProvider(widget.jobId));
      // Ecrã de celebração em vez do antigo "snackbar + /client/jobs" —
      // pushReplacement porque este detalhe (na tab "Propostas") já não
      // deve ficar na stack quando o utilizador voltar.
      router.pushReplacement(
        '/client/job/${widget.jobId}/confirmed?workerId=${proposal.workerId}',
      );
    } catch (e) {
      scaffold.showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red));
      if (mounted) setState(() => _accepting[proposal.id] = false);
    }
  }

  Widget _workerContactCard(
    JobRequest job,
    AsyncValue<Map<String, String>> workerInfoAsync,
    ThemeData theme,
  ) {
    return workerInfoAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          const Text('Não foi possível carregar o contacto.'),
      data: (info) {
        if (info.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final name = info['full_name'] ?? '';
        final phone = info['phone'] ?? '';
        final avatarUrl = info['avatar_url'];
        return Card(
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                UserAvatarWithName(name: name, avatarUrl: avatarUrl),
                if (job.confirmedDate != null) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.event_available_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _formatConfirmedSchedule(job),
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ]),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: phone.isEmpty
                      ? null
                      : () async {
                          final clean =
                              phone.replaceAll(RegExp(r'[\s\-]'), '');
                          final uri = Uri.parse('https://wa.me/$clean');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        },
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('Contactar via WhatsApp'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _acceptedProposalCard(JobProposal proposal, ThemeData theme) {
    final estimateStr = _formatEstimate(
        proposal.hourlyRate, proposal.estimatedHoursMin, proposal.estimatedHoursMax);
    final hoursStr =
        _hoursLabel(proposal.estimatedHoursMin, proposal.estimatedHoursMax);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Proposta aceite', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            _cardRow(context, Icons.euro_outlined,
                proposal.hourlyRate > 0
                    ? '${proposal.hourlyRate.toStringAsFixed(2)} €/hora'
                    : 'Preço a definir'),
            if (hoursStr.isNotEmpty)
              _cardRow(context, Icons.schedule_outlined, hoursStr),
            if (estimateStr.isNotEmpty)
              _cardRow(context, Icons.calculate_outlined, estimateStr),
            if (proposal.peopleNeeded > 1)
              _cardRow(context, Icons.group_outlined,
                  '${proposal.peopleNeeded} pessoas'),
          ],
        ),
      ),
    );
  }

  Future<void> _approveHelpRequest(String helpRequestId) async {
    setState(() => _approvingHelp.add(helpRequestId));
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(helpRequestRepositoryProvider)
          .approveHelpRequest(helpRequestId);
      ref.invalidate(helpRequestsForJobProvider(widget.jobId));
      scaffold.showSnackBar(const SnackBar(
        content: Text('Equipa aprovada! O prestador pode agora procurar ajudantes.'),
      ));
    } catch (e) {
      scaffold.showSnackBar(SnackBar(
        content: Text(friendlyError(e)),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) setState(() => _approvingHelp.remove(helpRequestId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ref.watch(jobByIdProvider(widget.jobId)).when(
      loading: () => const Scaffold(
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      ),
      error: (e, _) => Scaffold(
        body: SafeArea(child: Center(child: Text(friendlyError(e)))),
      ),
      data: (job) {
        if (job == null) {
          return const Scaffold(
            body: SafeArea(child: Center(child: Text('Pedido não encontrado.'))),
          );
        }

        final theme = Theme.of(context);
        final currentUserId = ref.watch(currentUserIdProvider);

        // Watch all providers unconditionally inside data branch
        final pendingProposalsAsync =
            ref.watch(pendingProposalsForJobProvider(widget.jobId));
        final acceptedProposalAsync =
            ref.watch(acceptedProposalForJobProvider(widget.jobId));
        final photosAsync = ref.watch(jobPhotosProvider(widget.jobId));

        final workerId = acceptedProposalAsync.asData?.value?.workerId ?? '';
        final workerInfoAsync = ref.watch(workerBasicInfoProvider(workerId));

        final ratingAsync = ref.watch(myRatingForJobProvider(job.id));
        final pendingHelpRequests = (ref
                .watch(helpRequestsForJobProvider(widget.jobId))
                .asData
                ?.value ??
            [])
            .where((hr) => hr.status == HelpRequestStatus.pendingApproval)
            .toList();

        final statusBadge = AppStatusBadge.fromPresentation(
          presentation: job.status.presentation(
            proposalCount: job.proposalCount,
          ),
        );

        final photosWidget = photosAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => const SizedBox.shrink(),
          data: (urls) {
            if (urls.isEmpty) return const SizedBox.shrink();
            return AppStaggeredEntrance(
              index: 4,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fotos',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SizedBox(
                      height: 72,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: urls.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: AppSpacing.xs),
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => PhotoViewerScreen(
                              photoUrls: urls,
                              initialIndex: i,
                            ),
                          )),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.input),
                            child: Image.network(
                              urls[i],
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );

        // Reschedule pending banner — shown when the other party proposed a reschedule
        Widget? rescheduleBanner;
        if (job.rescheduleStatus == RescheduleStatus.pending &&
            job.rescheduleProposedBy != null &&
            job.rescheduleProposedBy != currentUserId) {
          final dateStr = job.rescheduleProposedDate != null
              ? DateFormat('dd/MM/yyyy').format(job.rescheduleProposedDate!)
              : '—';
          final timeStr = job.rescheduleProposedFlexible == true
              ? '(horário flexível)'
              : (job.rescheduleProposedTime != null
                  ? 'às ${job.rescheduleProposedTime}'
                  : '');
          rescheduleBanner = Card(
            color: AppStatusColor.waiting.background,
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Icon(Icons.event_repeat,
                        color: AppStatusColor.waiting.foreground, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'O jardineiro propôs remarcar para $dateStr $timeStr'
                            .trim(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppStatusColor.waiting.foreground),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _acceptReschedule,
                          child: const Text('Aceitar nova data'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _rejectReschedule,
                          child: const Text('Recusar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        final serviceTypesForDetail =
            ref.watch(serviceTypesProvider).asData?.value ?? const [];
        final serviceTypeName = serviceTypesForDetail
                .where((s) => s.id == job.serviceTypeId)
                .map((s) => s.name)
                .firstOrNull ??
            '—';

        // "Publicado→Propostas→Escolher→Confirmado" só faz sentido enquanto
        // o pedido ainda não tem worker escolhido — para os restantes
        // estados usa-se buildJobTimeline (inalterado, partilhado com o
        // lado do worker).
        final timelineSteps = job.status == JobStatus.open
            ? _buildOpenStepperSteps(job)
            : buildJobTimeline(job);

        // Shared: banners + timeline + resumo + metadata + descrição + fotos
        final detailChildren = <Widget>[
          if (job.reopenedFrom != null)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Este pedido foi criado automaticamente após o cancelamento de um pedido anterior.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.primaryPressed),
                    ),
                  ),
                ],
              ),
            ),
          ?rescheduleBanner,
          AppStaggeredEntrance(
            index: 0,
            child: StatusTimeline(steps: timelineSteps),
          ),
          if (job.status == JobStatus.open) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _openExpiryNotice(job),
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AppStaggeredEntrance(
            index: 1,
            child: _ServiceSummaryRow(
              icon: Icons.yard_outlined,
              serviceLabel: serviceTypeName,
              metadataLabel: job.addressText.isNotEmpty
                  ? job.addressText
                  : 'Localização não especificada',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppStaggeredEntrance(
            index: 2,
            child: _JobMetadataCard(
              preferredDateLabel: job.preferredDate == null
                  ? 'Flexível'
                  : DateFormat('dd/MM/yyyy').format(job.preferredDate!),
              urgencyLabel: job.urgency == Urgency.urgent ? 'Urgente' : 'Normal',
              sizeLabel: job.sizeEstimate == null
                  ? null
                  : switch (job.sizeEstimate!) {
                      SizeEstimate.small => 'Pequeno',
                      SizeEstimate.medium => 'Médio',
                      SizeEstimate.large => 'Grande',
                    },
            ),
          ),
          if (job.locationLat != 0 || job.locationLng != 0) ...[
            const SizedBox(height: AppSpacing.sm),
            AddressMapLink(
              address: job.addressText,
              lat: job.locationLat,
              lng: job.locationLng,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: AppSpacing.md),
          AppStaggeredEntrance(
            index: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Descrição',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  job.description,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
          photosWidget,
        ];

        // ── Open status: two-tab layout ─────────────────────────────────────────

        if (job.status == JobStatus.open) {
          final proposalTabLabel = pendingProposalsAsync.when(
            data: (list) => 'Propostas (${list.length})',
            loading: () => 'Propostas',
            error: (e, _) => 'Propostas',
          );

          final proposalsTab = pendingProposalsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(friendlyError(e))),
            data: (proposals) {
              if (proposals.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Nenhuma proposta disponível de momento.'),
                  ),
                );
              }
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
              // ProposalStatus/JobStatus. Critério simples: rating mais alto
              // entre workers com >= 3 avaliações (evita destacar 5★/1 review
              // por acaso). Sem nenhum worker a qualificar, ninguém é marcado.
              String? recommendedWorkerId;
              double bestRating = 0;
              for (final p in sorted) {
                final summary =
                    ref.watch(ratingSummaryProvider(p.workerId)).asData?.value;
                if (summary != null &&
                    summary.ratingCount >= 3 &&
                    summary.avgRating > bestRating) {
                  bestRating = summary.avgRating;
                  recommendedWorkerId = p.workerId;
                }
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                              : () => _acceptProposal(sorted[i]),
                        ),
                      ),
                  ],
                ),
              );
            },
          );

          return DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: AppBar(
                title: Text('Pedido #${widget.jobId.substring(0, 8)}'),
                actions: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    child: Center(child: statusBadge),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Cancelar pedido',
                    onPressed: _saving ? null : _cancelJob,
                  ),
                ],
                bottom: TabBar(
                  tabs: [
                    const Tab(text: 'Detalhes'),
                    Tab(text: proposalTabLabel),
                  ],
                ),
              ),
              body: SafeArea(child: TabBarView(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: detailChildren,
                    ),
                  ),
                  proposalsTab,
                ],
              )),
            ),
          );
        }

        // ── Confirmed status: contact + cancel/reschedule buttons ────────────────

        if (job.status == JobStatus.confirmed) {
          detailChildren.add(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Serviço confirmado', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (acceptedProposalAsync.asData?.value != null) ...[
                _acceptedProposalCard(acceptedProposalAsync.asData!.value!, theme),
                const SizedBox(height: 12),
              ],
              _workerContactCard(job, workerInfoAsync, theme),
              const SizedBox(height: 16),
              // Pending-approval help requests — worker asked for extra team, client must approve
              if (pendingHelpRequests.isNotEmpty) ...[
                ...pendingHelpRequests.map((hr) => _PendingHelpRequestCard(
                      helpRequest: hr,
                      approving: _approvingHelp.contains(hr.id),
                      onApprove: () => _approveHelpRequest(hr.id),
                    )),
                const SizedBox(height: 8),
              ],
              // Cancel + reschedule buttons
              if (job.rescheduleStatus == RescheduleStatus.pending) ...[
                if (job.rescheduleProposedBy == currentUserId)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.hourglass_top,
                            color: theme.colorScheme.onSurfaceVariant,
                            size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Aguarda resposta à remarcação que propuseste.',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Aguarda resposta da remarcação',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_proposingReschedule ||
                              job.rescheduleStatus == RescheduleStatus.pending)
                          ? null
                          : _proposeReschedule,
                      icon: const Icon(Icons.event_repeat),
                      label: const Text('Remarcar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_saving ||
                              job.rescheduleStatus == RescheduleStatus.pending ||
                              (job.confirmedDate != null &&
                               job.confirmedDate!.difference(DateTime.now()).inHours < 24))
                          ? null
                          : _cancelJob,
                      style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error),
                      icon: const Icon(Icons.close),
                      label: const Text('Cancelar'),
                    ),
                  ),
                ],
              ),
              if (job.confirmedDate != null &&
                  job.confirmedDate!.difference(DateTime.now()).inHours < 24) ...[
                const SizedBox(height: 6),
                Text(
                  'Cancelamento disponível até 24h antes da data confirmada.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ));
        }

        // ── Awaiting confirmation: worker marked done, client confirms or reports ──

        if (job.status == JobStatus.awaitingConfirmation) {
          final selectedProblem = _commonProblems
              .where((p) => p.id == _selectedProblemId)
              .firstOrNull;

          detailChildren.add(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _workerContactCard(job, workerInfoAsync, theme),
                const SizedBox(height: AppSpacing.md),
                AppStaggeredEntrance(
                  index: 5,
                  child: Text(
                    'Como correu o trabalho?',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: AppColors.textPrimary),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Confirma a conclusão ou relate um problema. Assim que '
                  'confirmares, podes avaliar o profissional.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.md),
                AppStaggeredEntrance(
                  index: 6,
                  child: PrimaryActionButton(
                    label: 'Trabalho concluído',
                    isLoading: _confirming,
                    onPressed: _confirming ? null : _handleConfirmCompleted,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppStaggeredEntrance(
                  index: 7,
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _confirming
                          ? null
                          : () => _reportProblem(
                                prefillText: selectedProblem?.prefill ?? '',
                              ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppStatusColor.cancelled.foreground,
                        side: BorderSide(
                          color: AppStatusColor.cancelled.foreground,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.input),
                        ),
                      ),
                      icon: const Icon(Icons.error_outline_rounded),
                      label: const Text('Reportar problema'),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Problemas comuns',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final problem in _commonProblems)
                      AppFilterChip(
                        label: problem.label,
                        selected: _selectedProblemId == problem.id,
                        onPressed: () {
                          setState(() {
                            _selectedProblemId =
                                _selectedProblemId == problem.id
                                    ? null
                                    : problem.id;
                          });
                        },
                      ),
                  ],
                ),
              ],
            ),
          );
        }

        if (job.status == JobStatus.completed) {
          detailChildren.add(_workerContactCard(job, workerInfoAsync, theme));
          detailChildren.add(const SizedBox(height: 16));
          // Direção inversa de _buildClientRatingSection logo abaixo (essa
          // é o worker/ajudantes a avaliarem o CLIENTE); este botão abre um
          // ecrã novo para o cliente avaliar o WORKER principal —
          // submit_principal_rating, já usada do lado do worker para
          // avaliar ajudantes, nunca antes chamada a partir do cliente.
          if (workerId.isNotEmpty) {
            detailChildren.add(
              OutlinedButton.icon(
                onPressed: () => context.push(
                  '/client/job/${widget.jobId}/rate-worker?workerId=$workerId',
                ),
                icon: const Icon(Icons.star_outline_rounded),
                label: const Text('Avaliar profissional'),
              ),
            );
            detailChildren.add(const SizedBox(height: 16));
          }
          detailChildren.add(_buildClientRatingSection(theme, ratingAsync));
        }

        return Scaffold(
          appBar: AppBar(
            title: Text('Pedido #${widget.jobId.substring(0, 8)}'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.md),
                child: Center(child: statusBadge),
              ),
            ],
          ),
          body: Stack(
            children: [
              SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: detailChildren,
                  ),
                ),
              ),
              Positioned.fill(
                child: AppSuccessFeedback(
                  visible: _showCompletedFeedback,
                  message: 'Trabalho confirmado',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildClientRatingSection(
      ThemeData theme, AsyncValue<Rating?> ratingAsync) {
    return ratingAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => const SizedBox.shrink(),
      data: (existing) {
        if (existing != null) {
          return Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.check_circle,
                        color: theme.colorScheme.primary, size: 18),
                    const SizedBox(width: 8),
                    Text('Trabalho avaliado',
                        style: theme.textTheme.titleSmall),
                  ]),
                  const SizedBox(height: 8),
                  Row(
                    children: List.generate(
                      5,
                      (i) => Icon(
                        i < existing.stars
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 18,
                        color: Colors.amber,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Avaliar o trabalho',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'Partilha a tua experiência com o prestador e ajudantes.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: _showClientRatingSheet,
                  child: const Text('Avaliar agora'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showClientRatingSheet() async {
    final submitted = await showRatingSheet(
      context: context,
      title: 'Avaliar o trabalho',
      subtitle:
          'A nota é partilhada com o prestador e ajudantes. O comentário aparece no perfil do prestador.',
      onSubmit: (stars, comment) async {
        await ref.read(ratingRepositoryProvider).submitClientRating(
              jobId: widget.jobId,
              stars: stars,
              comment: comment,
            );
      },
    );
    if (submitted != true || !mounted) return;
    ref.invalidate(myRatingForJobProvider(widget.jobId));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text(
          'Avaliação enviada! Cobre o prestador e ajudantes deste trabalho.'),
    ));
  }
}

// ── Proposal card ─────────────────────────────────────────────────────────────

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

  /// Não é ProposalStatus/JobStatus — só um marcador de ranking da app
  /// (ver cálculo em `_ClientJobDetailScreenState.build`).
  final bool recommended;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final workerName =
        proposal.workerName?.isNotEmpty == true ? proposal.workerName! : '—';
    final workerAvatarUrl = proposal.workerAvatarUrl ?? '';
    final ratingSummary =
        ref.watch(ratingSummaryProvider(proposal.workerId)).asData?.value;

    final hoursStr =
        _hoursLabel(proposal.estimatedHoursMin, proposal.estimatedHoursMax);
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
                      backgroundImage: workerAvatarUrl.isNotEmpty
                          ? NetworkImage(workerAvatarUrl)
                          : null,
                      child: workerAvatarUrl.isEmpty
                          ? const Icon(
                              Icons.person_outline_rounded,
                              color: AppColors.primary,
                            )
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
                            style: textTheme.titleMedium
                                ?.copyWith(color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            ratingSummary != null && ratingSummary.ratingCount > 0
                                ? '★ ${ratingSummary.avgRating.toStringAsFixed(1)} '
                                    '(${ratingSummary.ratingCount})'
                                : 'Sem avaliações ainda',
                            style: textTheme.labelMedium
                                ?.copyWith(color: AppColors.textSecondary),
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
                          style: textTheme.titleLarge
                              ?.copyWith(color: AppColors.primary),
                        ),
                        if (hoursStr.isNotEmpty)
                          Text(
                            hoursStr,
                            style: textTheme.labelMedium
                                ?.copyWith(color: AppColors.textSecondary),
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
                      _MetaChip(
                        icon: Icons.calculate_outlined,
                        label: teamEstimateStr,
                      ),
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
                    style: textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

// ── helpers ──────────────────────────────────────────────────────────────────

Widget _cardRow(BuildContext context, IconData icon, String text) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
    ]),
  );
}

String _formatProposedSchedule(JobProposal proposal) {
  if (proposal.scheduledDate == null) return '';
  final date = DateFormat('dd/MM/yyyy').format(proposal.scheduledDate!);
  if (proposal.scheduledFlexible) return '$date (horário flexível)';
  if (proposal.scheduledTime != null) return '$date às ${proposal.scheduledTime}';
  return date;
}

String _formatConfirmedSchedule(JobRequest job) {
  if (job.confirmedDate == null) return '';
  final date = DateFormat('dd/MM/yyyy').format(job.confirmedDate!);
  if (job.confirmedFlexible) return 'Agendado para: $date (horário flexível)';
  if (job.confirmedTime != null) {
    return 'Agendado para: $date às ${job.confirmedTime}';
  }
  return 'Agendado para: $date';
}

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

// ── Ecrã 5 — timeline de 4 estágios (só JobStatus.open) ───────────────────

/// "Publicado → Propostas → Escolher → Confirmado".
///
/// Propostas/Escolher são dois estágios visuais sobre o mesmo
/// `JobStatus.open` — distinguidos só por `job.proposalCount`, sem estado
/// novo no backend. "Confirmado" está sempre `future` aqui porque, por
/// definição, um job com este stepper ainda não tem proposta aceite.
List<StatusTimelineStepData> _buildOpenStepperSteps(JobRequest job) {
  final hasProposals = job.proposalCount > 0;
  return [
    StatusTimelineStepData(
      label: 'Publicado',
      statusColor: AppStatusColor.success,
      state: StatusTimelineStepState.completed,
      subtitle: DateFormat('dd/MM/yyyy').format(job.createdAt),
    ),
    StatusTimelineStepData(
      label: 'Propostas',
      statusColor: AppStatusColor.waiting,
      state: hasProposals
          ? StatusTimelineStepState.completed
          : StatusTimelineStepState.current,
      subtitle: hasProposals
          ? '${job.proposalCount} ${job.proposalCount == 1 ? 'proposta' : 'propostas'}'
          : null,
    ),
    StatusTimelineStepData(
      label: 'Escolher',
      statusColor: AppStatusColor.waiting,
      state: hasProposals
          ? StatusTimelineStepState.current
          : StatusTimelineStepState.future,
    ),
    const StatusTimelineStepData(
      label: 'Confirmado',
      statusColor: AppStatusColor.neutral,
      state: StatusTimelineStepState.future,
    ),
  ];
}

/// `expires_at` é o prazo de expiração do PEDIDO INTEIRO (`created_at` +
/// 48h, para `no_response`), não um prazo dedicado a propostas — a frase
/// evita implicar o contrário.
String _openExpiryNotice(JobRequest job) {
  final formatted = DateFormat("dd/MM 'às' HH:mm").format(job.expiresAt);
  return 'Expira a $formatted se não houver nenhuma proposta aceite até lá';
}

class _ServiceSummaryRow extends StatelessWidget {
  const _ServiceSummaryRow({
    required this.icon,
    required this.serviceLabel,
    required this.metadataLabel,
  });

  final IconData icon;
  final String serviceLabel;
  final String metadataLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
          child: Icon(icon, color: AppColors.primary),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                serviceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                metadataLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _JobMetadataCard extends StatelessWidget {
  const _JobMetadataCard({
    required this.preferredDateLabel,
    required this.urgencyLabel,
    this.sizeLabel,
  });

  final String preferredDateLabel;
  final String urgencyLabel;
  final String? sizeLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          _MetadataRow(label: 'Data preferida', value: preferredDateLabel),
          const SizedBox(height: AppSpacing.sm),
          _MetadataRow(label: 'Urgência', value: urgencyLabel),
          if (sizeLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _MetadataRow(label: 'Dimensão', value: sizeLabel!),
          ],
        ],
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          value,
          style: textTheme.bodyMedium?.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PendingHelpRequestCard extends StatelessWidget {
  const _PendingHelpRequestCard({
    required this.helpRequest,
    required this.approving,
    required this.onApprove,
  });

  final HelpRequest helpRequest;
  final bool approving;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppStatusColor.waiting.background,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.group_add_outlined,
                  color: AppStatusColor.waiting.foreground, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'O prestador pediu ajuda extra para este trabalho',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppStatusColor.waiting.foreground),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              '${helpRequest.slotsNeeded} '
              'ajudante${helpRequest.slotsNeeded == 1 ? '' : 's'}'
              '${helpRequest.equipmentRequired ? ' · Equipamento exigido' : ''}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppStatusColor.waiting.foreground),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: approving ? null : onApprove,
              child: approving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Aprovar equipa'),
            ),
          ],
        ),
      ),
    );
  }
}
