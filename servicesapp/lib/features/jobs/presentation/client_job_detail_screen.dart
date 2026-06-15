import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/enums.dart';
import '../../auth/application/auth_providers.dart';
import '../application/job_providers.dart';
import '../data/job_model.dart';
import '../../proposals/data/proposal_model.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../worker/application/worker_providers.dart';
import 'widgets/cancel_job_dialog.dart';
import 'widgets/reschedule_dialog.dart';

class ClientJobDetailScreen extends ConsumerStatefulWidget {
  const ClientJobDetailScreen({super.key, required this.job});

  final JobRequest job;

  @override
  ConsumerState<ClientJobDetailScreen> createState() =>
      _ClientJobDetailScreenState();
}

class _ClientJobDetailScreenState
    extends ConsumerState<ClientJobDetailScreen> {
  late JobRequest _job;
  bool _saving = false;
  bool _proposingReschedule = false;
  final Map<String, bool> _accepting = {};
  String _sortBy = 'price';

  @override
  void initState() {
    super.initState();
    _job = widget.job;
  }

  Future<void> _cancelJob() async {
    final result = await CancelJobDialog.show(context, isClient: true);
    if (result == null || !mounted) return;

    setState(() => _saving = true);
    final scaffold = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      final newJobId = await ref.read(jobRepositoryProvider).cancelJob(
            jobId: _job.id,
            reason: result['reason']!,
            reasonDetail: result['reasonDetail'],
          );
      ref.invalidate(clientJobsProvider);
      ref.invalidate(pendingProposalsForJobProvider(_job.id));
      if (newJobId != null) {
        scaffold.showSnackBar(
          const SnackBar(content: Text('Pedido reaberto automaticamente.')),
        );
      } else {
        scaffold.showSnackBar(
          const SnackBar(content: Text('Pedido cancelado.')),
        );
      }
      router.go('/client/jobs');
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
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
    final currentUserId = ref.read(currentUserIdProvider);
    try {
      await ref.read(jobRepositoryProvider).proposeReschedule(
            jobId: _job.id,
            newDate: result['date'] as DateTime,
            newTime: result['time'] as String?,
            newFlexible: result['flexible'] as bool,
          );
      ref.invalidate(clientJobsProvider);
      setState(() {
        _job = _job.copyWith(
          rescheduleStatus: RescheduleStatus.pending,
          rescheduleProposedBy: currentUserId,
        );
      });
      scaffold.showSnackBar(
        const SnackBar(content: Text('Remarcação enviada.')),
      );
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _proposingReschedule = false);
    }
  }

  Future<void> _acceptReschedule() async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await ref.read(jobRepositoryProvider).acceptReschedule(_job.id);
      ref.invalidate(clientJobsProvider);
      setState(() => _job = _job.copyWith(
            confirmedDate: _job.rescheduleProposedDate,
            confirmedTime: _job.rescheduleProposedTime,
            confirmedFlexible: _job.rescheduleProposedFlexible ?? false,
            rescheduleStatus: RescheduleStatus.accepted,
          ));
      scaffold.showSnackBar(
        const SnackBar(content: Text('Nova data aceite.')),
      );
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _rejectReschedule() async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await ref.read(jobRepositoryProvider).rejectReschedule(_job.id);
      ref.invalidate(clientJobsProvider);
      setState(() => _job = _job.copyWith(rescheduleStatus: RescheduleStatus.rejected));
      scaffold.showSnackBar(
        const SnackBar(content: Text('Remarcação recusada.')),
      );
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _acceptProposal(JobProposal proposal) async {
    setState(() => _accepting[proposal.id] = true);
    final scaffold = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref
          .read(proposalRepositoryProvider)
          .acceptProposal(proposal.id, _job.id);
      ref.invalidate(clientJobsProvider);
      ref.invalidate(pendingProposalsForJobProvider(_job.id));
      scaffold.showSnackBar(const SnackBar(content: Text('Proposta aceite!')));
      router.go('/client/jobs');
    } catch (e) {
      scaffold.showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
      if (mounted) setState(() => _accepting[proposal.id] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUserId = ref.watch(currentUserIdProvider);

    // Watch all providers unconditionally at top of build
    final pendingProposalsAsync =
        ref.watch(pendingProposalsForJobProvider(_job.id));
    final acceptedProposalAsync =
        ref.watch(acceptedProposalForJobProvider(_job.id));
    final photosAsync = ref.watch(jobPhotosProvider(_job.id));

    final workerId = acceptedProposalAsync.asData?.value?.workerId ?? '';
    final workerInfoAsync = ref.watch(workerBasicInfoProvider(workerId));

    final (statusLabel, statusColor) =
        _statusInfo(_job.status, _job.proposalCount);

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
                itemBuilder: (_, i) => ClipRRect(
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
            const SizedBox(height: 20),
          ],
        );
      },
    );

    // Reschedule pending banner — shown when the other party proposed a reschedule
    Widget? rescheduleBanner;
    if (_job.rescheduleStatus == RescheduleStatus.pending &&
        _job.rescheduleProposedBy != null &&
        _job.rescheduleProposedBy != currentUserId) {
      final dateStr = _job.rescheduleProposedDate != null
          ? DateFormat('dd/MM/yyyy').format(_job.rescheduleProposedDate!)
          : '—';
      final timeStr = _job.rescheduleProposedFlexible == true
          ? '(horário flexível)'
          : (_job.rescheduleProposedTime != null
              ? 'às ${_job.rescheduleProposedTime}'
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
      if (_job.reopenedFrom != null)
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
          if (_job.addressText.isNotEmpty)
            _detailRow(context, Icons.place_outlined, 'Localização',
                _job.addressText),
          _detailRow(
            context,
            Icons.calendar_today_outlined,
            'Data',
            _job.preferredDate == null
                ? 'Flexível'
                : DateFormat('dd/MM/yyyy').format(_job.preferredDate!),
          ),
          _detailRow(
            context,
            Icons.bolt_outlined,
            'Urgência',
            _job.urgency == Urgency.urgent ? 'Urgente' : 'Normal',
          ),
          if (_job.sizeEstimate != null)
            _detailRow(
              context,
              Icons.straighten_outlined,
              'Dimensão',
              switch (_job.sizeEstimate!) {
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
      Text(_job.description, style: theme.textTheme.bodyMedium),
      const SizedBox(height: 20),
      photosWidget,
    ];

    // ── Open status: two-tab layout ─────────────────────────────────────────

    if (_job.status == JobStatus.open) {
      final proposalTabLabel = pendingProposalsAsync.when(
        data: (list) => 'Propostas (${list.length})',
        loading: () => 'Propostas',
        error: (e, _) => 'Propostas',
      );

      final proposalsTab = pendingProposalsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
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
            title: Text('Pedido #${_job.id.substring(0, 8)}'),
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

    if (_job.status == JobStatus.confirmed) {
      detailChildren.add(
        workerInfoAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              const Text('Não foi possível carregar o contacto.'),
          data: (info) {
            if (workerId.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (info.isEmpty) {
              return const Text('Não foi possível carregar o contacto.');
            }
            final name = info['full_name'] ?? '';
            final phone = info['phone'] ?? '';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Serviço confirmado',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  color: theme.colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.person_outlined),
                            const SizedBox(width: 8),
                            Text(name, style: theme.textTheme.titleMedium),
                          ],
                        ),
                        if (_job.confirmedDate != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.event_available_outlined),
                              const SizedBox(width: 8),
                              Text(
                                _formatConfirmedSchedule(_job),
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: phone.isEmpty
                              ? null
                              : () async {
                                  final clean = phone.replaceAll(
                                      RegExp(r'[\s\-]'), '');
                                  final uri =
                                      Uri.parse('https://wa.me/$clean');
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(uri,
                                        mode: LaunchMode
                                            .externalApplication);
                                  }
                                },
                          icon: const Icon(Icons.chat_outlined),
                          label: const Text('Contactar via WhatsApp'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Cancel + reschedule buttons
                if (_job.rescheduleStatus == RescheduleStatus.pending) ...[
                  if (_job.rescheduleProposedBy == currentUserId)
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
                                _job.rescheduleStatus == RescheduleStatus.pending)
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
                                _job.rescheduleStatus == RescheduleStatus.pending)
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
              ],
            );
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Pedido #${_job.id.substring(0, 8)}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: detailChildren,
        ),
      ),
    );
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

    final estimateStr = _formatEstimate(
        proposal.hourlyRate,
        proposal.estimatedHoursMin,
        proposal.estimatedHoursMax);
    final hoursStr =
        _hoursLabel(proposal.estimatedHoursMin, proposal.estimatedHoursMax);
    final scheduleStr = _formatProposedSchedule(proposal);

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
            ]),
            const Divider(height: 20),
            _cardRow(context, Icons.euro_outlined,
                '${proposal.hourlyRate.toStringAsFixed(2)} €/hora'),
            if (estimateStr.isNotEmpty)
              _cardRow(context, Icons.calculate_outlined, estimateStr),
            if (hoursStr.isNotEmpty)
              _cardRow(context, Icons.schedule_outlined, hoursStr),
            if (scheduleStr.isNotEmpty)
              _cardRow(context, Icons.event_outlined, 'Propõe: $scheduleStr'),
            if (proposal.peopleNeeded > 1)
              _cardRow(context, Icons.group_outlined,
                  'Equipa: ${proposal.peopleNeeded} pessoas'),
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
                onPressed: accepting ? () {} : onAccept,
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
