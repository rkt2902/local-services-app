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
import '../../../core/widgets/photo_viewer_screen.dart';
import '../../../core/widgets/status_timeline.dart';
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
  final Map<String, bool> _accepting = {};
  final Set<String> _approvingHelp = {};
  String _sortBy = 'price';

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
      try {
        await ref.read(jobRepositoryProvider).cancelJob(
              jobId: widget.jobId,
              reason: 'no_longer_needed',
              reasonDetail: null,
            );
        ref.invalidate(clientJobsProvider);
        ref.invalidate(pendingProposalsForJobProvider(widget.jobId));
        scaffold.showSnackBar(
            const SnackBar(content: Text('Pedido cancelado.')));
        router.go('/client/jobs');
      } catch (e) {
        scaffold.showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      } finally {
        if (mounted) setState(() => _saving = false);
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
    try {
      final newJobId = await ref.read(jobRepositoryProvider).cancelJob(
            jobId: widget.jobId,
            reason: result['reason']!,
            reasonDetail: result['reasonDetail'],
            clientWantsReopen: wantsReopen ?? false,
          );
      ref.invalidate(clientJobsProvider);
      ref.invalidate(pendingProposalsForJobProvider(widget.jobId));
      if (newJobId != null) {
        scaffold.showSnackBar(
          const SnackBar(
              content: Text(
                  'Pedido cancelado e reaberto para encontrar outro prestador.')),
        );
      } else {
        scaffold.showSnackBar(const SnackBar(content: Text('Pedido cancelado.')));
      }
      router.go('/client/jobs');
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
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

  Future<void> _confirmJobCompletion() async {
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
    if (confirmed != true || !mounted) return;

    setState(() => _confirming = true);
    final scaffold = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref
          .read(proposalRepositoryProvider)
          .confirmJobCompletion(widget.jobId);
      ref.invalidate(clientJobsProvider);
      scaffold.showSnackBar(
        const SnackBar(content: Text('Trabalho confirmado! Obrigado.')),
      );
      router.go('/client/jobs');
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(
            content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _reportProblem() async {
    final formKey = GlobalKey<FormState>();
    final descController = TextEditingController();
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
      await _confirmJobCompletion();
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
      scaffold.showSnackBar(const SnackBar(content: Text('Proposta aceite!')));
      router.go('/client/jobs');
    } catch (e) {
      scaffold.showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red));
      if (mounted) setState(() => _accepting[proposal.id] = false);
    }
  }

  Widget _workerContactCard(
    JobRequest job,
    AsyncValue<Map<String, dynamic>> workerInfoAsync,
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
        return Card(
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.person_outlined),
                  const SizedBox(width: 8),
                  Text(name, style: theme.textTheme.titleMedium),
                ]),
                if (job.confirmedDate != null) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.event_available_outlined),
                    const SizedBox(width: 8),
                    Text(
                      _formatConfirmedSchedule(job),
                      style: theme.textTheme.bodyMedium,
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
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text(friendlyError(e))),
      ),
      data: (job) {
        if (job == null) {
          return const Scaffold(
            body: Center(child: Text('Pedido não encontrado.')),
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

        final (statusLabel, statusColor) =
            _statusInfo(job.status, job.proposalCount);

        final statusBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            statusLabel,
            style: theme.textTheme.labelMedium?.copyWith(color: Colors.white),
          ),
        );

        final photosWidget = photosAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => const SizedBox.shrink(),
          data: (urls) {
            if (urls.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fotos', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                SizedBox(
                  height: 120,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: urls.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PhotoViewerScreen(
                          photoUrls: urls,
                          initialIndex: i,
                        ),
                      )),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          urls[i],
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
                        'O jardineiro propôs remarcar para $dateStr $timeStr'
                            .trim(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.orange.shade900),
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

        // Shared: status badge + info card + description + photos
        final detailChildren = <Widget>[
          if (job.reopenedFrom != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: theme.colorScheme.secondary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Este pedido foi criado automaticamente após o cancelamento de um pedido anterior.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ?rescheduleBanner,
          statusBadge,
          const SizedBox(height: 24),
          _DetailSection(
            children: [
              if (job.addressText.isNotEmpty)
                _detailRow(context, Icons.place_outlined, 'Localização',
                    job.addressText),
              _detailRow(
                context,
                Icons.calendar_today_outlined,
                'Data',
                job.preferredDate == null
                    ? 'Flexível'
                    : DateFormat('dd/MM/yyyy').format(job.preferredDate!),
              ),
              _detailRow(
                context,
                Icons.bolt_outlined,
                'Urgência',
                job.urgency == Urgency.urgent ? 'Urgente' : 'Normal',
              ),
              if (job.sizeEstimate != null)
                _detailRow(
                  context,
                  Icons.straighten_outlined,
                  'Dimensão',
                  switch (job.sizeEstimate!) {
                    SizeEstimate.small => 'Pequeno',
                    SizeEstimate.medium => 'Médio',
                    SizeEstimate.large => 'Grande',
                  },
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Descrição', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(job.description, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 20),
          photosWidget,
          Text('Estado do pedido', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          StatusTimeline(steps: buildJobTimeline(job)),
          const SizedBox(height: 20),
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
                    const SizedBox(height: 12),
                    ...sorted.map((p) => _ProposalCard(
                          key: ValueKey(p.id),
                          proposal: p,
                          accepting: _accepting[p.id] == true,
                          onAccept:
                              anyAccepting ? null : () => _acceptProposal(p),
                        )),
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
              body: TabBarView(
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
              ),
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
          detailChildren.add(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _workerContactCard(job, workerInfoAsync, theme),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.task_alt,
                                color: theme.colorScheme.primary, size: 24),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'O prestador marcou este trabalho como concluído',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Confirma se o trabalho foi feito conforme esperado.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _confirming ? null : _confirmJobCompletion,
                  style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Confirmar conclusão'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _confirming ? null : _reportProblem,
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Reportar problema'),
                ),
              ],
            ),
          );
        }

        if (job.status == JobStatus.completed) {
          detailChildren.add(_workerContactCard(job, workerInfoAsync, theme));
          detailChildren.add(const SizedBox(height: 16));
          detailChildren.add(_buildClientRatingSection(theme, ratingAsync));
        }

        return Scaffold(
          appBar: AppBar(
            title: Text('Pedido #${widget.jobId.substring(0, 8)}'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: detailChildren,
            ),
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
    super.key,
    required this.proposal,
    required this.accepting,
    required this.onAccept,
  });

  final JobProposal proposal;
  final bool accepting;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final workerNameAsync = ref.watch(workerNameProvider(proposal.workerId));
    final workerName = workerNameAsync.asData?.value.isNotEmpty == true
        ? workerNameAsync.asData!.value
        : '—';
    final ratingSummary =
        ref.watch(ratingSummaryProvider(proposal.workerId)).asData?.value;

    final estimateStr = _formatEstimate(
        proposal.hourlyRate,
        proposal.estimatedHoursMin,
        proposal.estimatedHoursMax);
    final hoursStr =
        _hoursLabel(proposal.estimatedHoursMin, proposal.estimatedHoursMax);
    final scheduleStr = _formatProposedSchedule(proposal);
    final teamEstimateStr = _teamTotalEstimate(proposal);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.person_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(workerName, style: theme.textTheme.titleMedium),
              ),
              if (ratingSummary != null && ratingSummary.ratingCount > 0)
                GestureDetector(
                  onTap: () => showRatingsSheet(
                    context,
                    workerId: proposal.workerId,
                    workerName: workerName,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 14, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text(
                        ratingSummary.avgRating.toStringAsFixed(1),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ]),
            const Divider(height: 20),
            _cardRow(context, Icons.euro_outlined,
                proposal.hourlyRate > 0
                    ? '${proposal.hourlyRate.toStringAsFixed(2)} €/hora'
                    : 'Preço a definir'),
            if (estimateStr.isNotEmpty)
              _cardRow(context, Icons.calculate_outlined, estimateStr),
            if (hoursStr.isNotEmpty)
              _cardRow(context, Icons.schedule_outlined, hoursStr),
            if (scheduleStr.isNotEmpty)
              _cardRow(context, Icons.event_outlined, 'Propõe: $scheduleStr'),
            if (proposal.peopleNeeded > 1)
              _cardRow(context, Icons.group_outlined,
                  'Equipa: ${proposal.peopleNeeded} pessoas'),
            if (teamEstimateStr.isNotEmpty)
              _cardRow(context, Icons.calculate_outlined, teamEstimateStr),
            if (proposal.notes?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                proposal.notes!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: accepting ? null : onAccept,
                child: accepting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Aceitar esta proposta'),
              ),
            ),
          ],
        ),
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

(String, Color) _statusInfo(JobStatus status, int proposalCount) =>
    switch (status) {
      JobStatus.open when proposalCount > 0 =>
        ('$proposalCount proposta${proposalCount > 1 ? 's' : ''}',
        Colors.orange.shade700),
      JobStatus.open => ('À espera de proposta', Colors.blue.shade600),
      JobStatus.confirmed => ('Confirmado', Colors.green.shade600),
      JobStatus.awaitingConfirmation =>
        ('A aguardar confirmação', Colors.teal.shade600),
      JobStatus.completed => ('Concluído', Colors.grey.shade600),
      JobStatus.noResponse => ('Sem resposta', Colors.red.shade600),
      JobStatus.cancelled => ('Cancelado', Colors.grey.shade500),
    };

Widget _detailRow(
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

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(children: children),
      ),
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
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.secondaryContainer,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.group_add_outlined,
                  color: theme.colorScheme.onSecondaryContainer, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'O prestador pediu ajuda extra para este trabalho',
                  style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              '${helpRequest.slotsNeeded} '
              'ajudante${helpRequest.slotsNeeded == 1 ? '' : 's'}'
              '${helpRequest.equipmentRequired ? ' · Equipamento exigido' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer),
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
