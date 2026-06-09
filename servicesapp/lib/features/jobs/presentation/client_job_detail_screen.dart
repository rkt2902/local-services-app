import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/enums.dart';
import '../application/job_providers.dart';
import '../data/job_model.dart';
import '../../proposals/data/proposal_model.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../worker/application/worker_providers.dart';

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

  @override
  void initState() {
    super.initState();
    _job = widget.job;
  }

  Future<void> _cancelJob() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancelar pedido?'),
        content:
            const Text('Tens a certeza? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Não'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref.read(jobRepositoryProvider).cancelJob(_job.id);
      ref.invalidate(clientJobsProvider);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.pop();
      messenger.showSnackBar(
          const SnackBar(content: Text('Pedido cancelado.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _acceptProposal(JobProposal proposal) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(proposalRepositoryProvider)
          .acceptProposal(proposal.id, _job.id);
      ref.invalidate(clientJobsProvider);
      ref.invalidate(proposalForJobProvider(_job.id));
      if (!mounted) return;
      setState(() {
        _job = _job.copyWith(
          status: JobStatus.confirmed,
          acceptedProposalId: proposal.id,
        );
      });
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proposta aceite!')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _rejectProposal(JobProposal proposal) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(proposalRepositoryProvider)
          .rejectProposal(proposal.id, _job.id);
      ref.invalidate(clientJobsProvider);
      ref.invalidate(proposalForJobProvider(_job.id));
      if (!mounted) return;
      setState(() {
        _job = _job.copyWith(status: JobStatus.open);
      });
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proposta recusada.')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showProposalSheet(JobProposal proposal) {
    bool accepting = false;
    bool rejecting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final theme = Theme.of(ctx);
          final total = proposal.hourlyRate * proposal.estimatedHours;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Proposta do jardineiro',
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: 16),
                  _sheetRow(ctx, 'Taxa/hora',
                      '${proposal.hourlyRate.toStringAsFixed(2)} €/hora'),
                  _sheetRow(ctx, 'Horas estimadas',
                      '${proposal.estimatedHours.toStringAsFixed(1)} h'),
                  _sheetRow(ctx, 'Total estimado',
                      '≈ €${total.toStringAsFixed(0)}'),
                  _sheetRow(ctx, 'Pessoas', '${proposal.peopleNeeded}'),
                  if (proposal.notes != null &&
                      proposal.notes!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('Notas',
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text(proposal.notes!,
                        style: theme.textTheme.bodyMedium),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: (accepting || rejecting)
                              ? null
                              : () async {
                                  final confirmed =
                                      await showDialog<bool>(
                                    context: ctx,
                                    builder: (_) => AlertDialog(
                                      title: const Text(
                                          'Recusar proposta?'),
                                      content: const Text(
                                          'O pedido voltará a estar disponível para outros jardineiros.'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text('Não'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          style: TextButton.styleFrom(
                                              foregroundColor: Colors.red),
                                          child:
                                              const Text('Recusar'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed != true) return;
                                  setSheetState(() => rejecting = true);
                                  await _rejectProposal(proposal);
                                },
                          child: rejecting
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Text('Recusar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: (accepting || rejecting)
                              ? null
                              : () async {
                                  setSheetState(() => accepting = true);
                                  await _acceptProposal(proposal);
                                },
                          child: accepting
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white))
                              : const Text('Aceitar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sheetRow(BuildContext ctx, String label, String value) {
    final theme = Theme.of(ctx);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Text(value,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Watch all providers unconditionally at the top of build
    final pendingProposalAsync = ref.watch(proposalForJobProvider(_job.id));
    final acceptedProposalId = _job.acceptedProposalId ?? '';
    final acceptedProposalAsync =
        ref.watch(proposalByIdProvider(acceptedProposalId));
    final photosAsync = ref.watch(jobPhotosProvider(_job.id));
    final workerId = acceptedProposalAsync.asData?.value?.workerId ?? '';
    final workerInfoAsync = ref.watch(workerBasicInfoProvider(workerId));

    final canCancel = _job.status == JobStatus.open ||
        _job.status == JobStatus.proposalReceived;

    final (statusLabel, statusColor) = _statusInfo(_job.status);

    return Scaffold(
      appBar: AppBar(
        title: Text('Pedido #${_job.id.substring(0, 8)}'),
        actions: [
          if (canCancel)
            IconButton(
              icon: const Icon(Icons.cancel_outlined),
              tooltip: 'Cancelar pedido',
              onPressed: _saving ? null : _cancelJob,
            ),
        ],
      ),
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

            // Info card
            _DetailSection(
              children: [
                _detailRow(context, Icons.place_outlined, 'Localização',
                    _job.addressText),
                _detailRow(
                  context,
                  Icons.calendar_today_outlined,
                  'Data',
                  _job.preferredDate == null
                      ? 'Flexível'
                      : DateFormat('dd/MM/yyyy')
                          .format(_job.preferredDate!),
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

            // Photos
            photosAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
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
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: 8),
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
            ),

            // Proposal section (proposal_received)
            if (_job.status == JobStatus.proposalReceived)
              pendingProposalAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Erro: $e'),
                data: (proposal) {
                  if (proposal == null) {
                    return const Text(
                        'Nenhuma proposta pendente encontrada.');
                  }
                  final total =
                      proposal.hourlyRate * proposal.estimatedHours;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Proposta recebida',
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Card(
                        child: InkWell(
                          onTap: () => _showProposalSheet(proposal),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '≈ €${total.toStringAsFixed(0)}',
                                        style: theme.textTheme.titleLarge
                                            ?.copyWith(
                                                color: theme
                                                    .colorScheme.primary),
                                      ),
                                      Text(
                                        '${proposal.hourlyRate.toStringAsFixed(2)} €/h · ${proposal.estimatedHours.toStringAsFixed(1)} h · ${proposal.peopleNeeded} pessoa${proposal.peopleNeeded > 1 ? 's' : ''}',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_outlined),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),

            // Confirmed section
            if (_job.status == JobStatus.confirmed &&
                acceptedProposalId.isNotEmpty)
              workerInfoAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Erro: $e'),
                data: (info) {
                  if (info.isEmpty) return const SizedBox.shrink();
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
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.person_outlined),
                                  const SizedBox(width: 8),
                                  Text(name,
                                      style:
                                          theme.textTheme.titleMedium),
                                ],
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: phone.isEmpty
                                    ? null
                                    : () async {
                                        final clean = phone.replaceAll(
                                            RegExp(r'[\s\-]'), '');
                                        final uri = Uri.parse(
                                            'https://wa.me/$clean');
                                        if (await canLaunchUrl(uri)) {
                                          await launchUrl(uri,
                                              mode: LaunchMode
                                                  .externalApplication);
                                        }
                                      },
                                icon: const Icon(Icons.chat_outlined),
                                label: const Text(
                                    'Contactar via WhatsApp'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

(String, Color) _statusInfo(JobStatus status) => switch (status) {
      JobStatus.open => ('À espera de proposta', Colors.blue.shade600),
      JobStatus.proposalReceived =>
        ('Proposta recebida', Colors.orange.shade700),
      JobStatus.confirmed => ('Confirmado', Colors.green.shade600),
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
