import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/enums.dart';
import '../../client/application/client_providers.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/data/job_model.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../proposals/data/proposal_model.dart';

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

  Future<void> _withdrawProposal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Retirar proposta?'),
        content: const Text(
            'O pedido ficará disponível para outros jardineiros.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Não'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Retirar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _withdrawing = true);
    try {
      await ref
          .read(proposalRepositoryProvider)
          .withdrawProposal(widget.proposal.id, widget.job.id);
      ref.invalidate(workerProposalsProvider);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.pop();
      messenger.showSnackBar(
          const SnackBar(content: Text('Proposta retirada.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
      setState(() => _withdrawing = false);
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
      builder: (_) => AlertDialog(
        title: const Text('Tens a certeza?'),
        content: const Text('Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Não'),
          ),
          FilledButton(
            onPressed: _completing ? null : () async {
              setState(() => _completing = true);
              try {
                await ref
                    .read(proposalRepositoryProvider)
                    .markJobCompleted(widget.job.id);
                ref.invalidate(workerProposalsProvider);
                ref.invalidate(jobsInRadiusProvider);
                if (mounted) {
                  Navigator.of(context).pop();
                  context.go('/worker/home');
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Trabalho marcado como concluído!')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Erro: $e'),
                        backgroundColor: Colors.red),
                  );
                }
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
                        itemBuilder: (_, i) => ClipRRect(
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
                  '${widget.proposal.hourlyRate.toStringAsFixed(2)} €/h'),
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

            // === ACCEPTED ===
            if (liveStatus == ProposalStatus.accepted) ...[
              if (widget.job.confirmedDate != null) ...[
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
              ),
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
                          'A tua proposta foi recusada pelo cliente.'),
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
                            'Contactar cliente via WhatsApp'),
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
}

// ── helpers ──────────────────────────────────────────────────────────────────

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
      ProposalStatus.rejected => ('Recusada', Colors.red.shade600),
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
