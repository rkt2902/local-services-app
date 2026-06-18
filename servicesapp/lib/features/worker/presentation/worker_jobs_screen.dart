import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/error_utils.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/data/job_model.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../proposals/data/proposal_model.dart';
import '../application/worker_providers.dart';

class WorkerJobsScreen extends ConsumerStatefulWidget {
  const WorkerJobsScreen({super.key});

  @override
  ConsumerState<WorkerJobsScreen> createState() => _WorkerJobsScreenState();
}

class _WorkerJobsScreenState extends ConsumerState<WorkerJobsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.invalidate(workerProposalsProvider));
  }

  @override
  Widget build(BuildContext context) {
    final proposalsAsync = ref.watch(workerProposalsProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Os meus jobs'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Por confirmar'),
              Tab(text: 'Agendados'),
              Tab(text: 'Concluídos'),
            ],
          ),
        ),
        body: proposalsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(friendlyError(e))),
          data: (rawList) {
            final entries = rawList
                .where((item) => item['job_requests'] != null)
                .map((item) {
                  final job = JobRequest.fromJson(
                      Map<String, dynamic>.from(item['job_requests'] as Map));
                  final proposal = JobProposal.fromJson(
                      Map<String, dynamic>.from(item));
                  return (proposal, job);
                })
                .toList();

            final pending = entries
                .where((e) => e.$1.status == ProposalStatus.pending)
                .toList();

            final scheduled = entries
                .where((e) =>
                    e.$1.status == ProposalStatus.accepted &&
                    (e.$2.status == JobStatus.confirmed ||
                        e.$2.status == JobStatus.awaitingConfirmation))
                .toList();

            final done = entries
                .where((e) =>
                    e.$1.status == ProposalStatus.accepted &&
                    e.$2.status == JobStatus.completed)
                .toList();

            return TabBarView(
              children: [
                _JobList(
                  items: pending,
                  emptyText: 'Nenhuma proposta a aguardar resposta.',
                ),
                _JobList(
                  items: scheduled,
                  emptyText: 'Sem trabalhos agendados.',
                ),
                _JobList(
                  items: done,
                  emptyText: 'Ainda não tens trabalhos concluídos.',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
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

String _formatEstimate(double rate, double? min, double? max) {
  if (rate <= 0) return 'Preço a definir';
  if (min != null && max != null) {
    return '≈ €${(rate * min).toStringAsFixed(0)} - €${(rate * max).toStringAsFixed(0)}';
  } else if (min != null) {
    return '≈ €${(rate * min).toStringAsFixed(0)}';
  } else if (max != null) {
    return '≈ €${(rate * max).toStringAsFixed(0)}';
  }
  return '';
}

class _JobList extends ConsumerWidget {
  final List<(JobProposal, JobRequest)> items;
  final String emptyText;

  const _JobList({required this.items, required this.emptyText});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workerAsync = ref.watch(workerProfileProvider);
    final serviceTypes = ref.watch(serviceTypesProvider).value ?? [];
    final workerLat = workerAsync.value?.baseLat;
    final workerLng = workerAsync.value?.baseLng;

    if (items.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(workerProposalsProvider);
            ref.invalidate(jobsInRadiusProvider);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: constraints.maxHeight,
              child: Center(
                child: Text(emptyText,
                    style: Theme.of(context).textTheme.bodyLarge),
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(workerProposalsProvider);
        ref.invalidate(jobsInRadiusProvider);
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final (proposal, job) = items[index];
          final serviceType =
              serviceTypes.where((s) => s.id == job.serviceTypeId).firstOrNull;

          double? distanceMeters;
          if (workerLat != null && workerLng != null) {
            distanceMeters = Geolocator.distanceBetween(
              workerLat,
              workerLng,
              job.locationLat,
              job.locationLng,
            );
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _JobCard(
              proposal: proposal,
              job: job,
              serviceTypeName: serviceType?.name ?? '—',
              distanceMeters: distanceMeters,
            ),
          );
        },
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  final JobProposal proposal;
  final JobRequest job;
  final String serviceTypeName;
  final double? distanceMeters;

  const _JobCard({
    required this.proposal,
    required this.job,
    required this.serviceTypeName,
    this.distanceMeters,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (statusLabel, statusColor) = _proposalStatusInfo(proposal.status);
    final estimate = _formatEstimate(
        proposal.hourlyRate, proposal.estimatedHoursMin, proposal.estimatedHoursMax);

    String? distanceStr;
    if (distanceMeters != null) {
      distanceStr = distanceMeters! < 1000
          ? '${distanceMeters!.round()} m'
          : '${(distanceMeters! / 1000).toStringAsFixed(1)} km';
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(
          '/worker/my-job/${proposal.id}',
          extra: {'proposal': proposal, 'job': job},
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      serviceTypeName,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      statusLabel,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _MetaItem(
                      icon: Icons.calendar_today_outlined,
                      label: _formatDate(job.preferredDate)),
                  if (distanceStr != null)
                    _MetaItem(
                        icon: Icons.place_outlined, label: distanceStr),
                  if (estimate.isNotEmpty)
                    _MetaItem(icon: Icons.euro_outlined, label: estimate),
                ],
              ),
              if (proposal.peopleNeeded > 1) ...[
                const SizedBox(height: 6),
                Chip(
                  avatar: const Icon(Icons.group, size: 16),
                  label: Text(
                    'Equipa: ${proposal.peopleNeeded} pessoas',
                    style: theme.textTheme.labelSmall,
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ],
              if (job.rescheduleStatus == RescheduleStatus.pending) ...[
                const SizedBox(height: 6),
                Chip(
                  avatar: const Icon(Icons.event_repeat, size: 14),
                  label: const Text('Remarcação pendente'),
                  backgroundColor: Colors.orange.shade100,
                  labelStyle: TextStyle(
                      fontSize: 11, color: Colors.orange.shade900),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon,
            size: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
