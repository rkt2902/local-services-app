import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../application/job_providers.dart';
import '../data/job_model.dart';
import '../../proposals/application/proposal_providers.dart';

class ClientJobsScreen extends ConsumerWidget {
  const ClientJobsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(clientJobsProvider);
    final serviceTypesAsync = ref.watch(serviceTypesProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Os meus pedidos'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Ativos'), Tab(text: 'Histórico')],
          ),
        ),
        body: jobsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erro: $e')),
          data: (jobs) => serviceTypesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Erro: $e')),
            data: (serviceTypes) {
              final activeJobs = jobs
                  .where((j) =>
                      j.status == JobStatus.open ||
                      j.status == JobStatus.proposalReceived ||
                      j.status == JobStatus.confirmed)
                  .toList();
              final historyJobs = jobs
                  .where((j) =>
                      j.status == JobStatus.completed ||
                      j.status == JobStatus.noResponse ||
                      j.status == JobStatus.cancelled)
                  .toList();
              return TabBarView(
                children: [
                  _JobList(
                    jobs: activeJobs,
                    serviceTypes: serviceTypes,
                    emptyText: 'Ainda não tens pedidos ativos.',
                  ),
                  _JobList(
                    jobs: historyJobs,
                    serviceTypes: serviceTypes,
                    emptyText: 'Sem histórico.',
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _JobList extends StatelessWidget {
  const _JobList({
    required this.jobs,
    required this.serviceTypes,
    required this.emptyText,
  });

  final List<JobRequest> jobs;
  final List<ServiceType> serviceTypes;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (jobs.isEmpty) {
      return Center(
        child: Text(emptyText, style: Theme.of(context).textTheme.bodyLarge),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: jobs.length,
      itemBuilder: (_, index) =>
          _JobCard(job: jobs[index], serviceTypes: serviceTypes),
    );
  }
}

class _JobCard extends ConsumerWidget {
  const _JobCard({required this.job, required this.serviceTypes});

  final JobRequest job;
  final List<ServiceType> serviceTypes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final serviceName = serviceTypes
            .where((t) => t.id == job.serviceTypeId)
            .map((t) => t.name)
            .firstOrNull ??
        'Desconhecido';

    final dateText = job.preferredDate == null
        ? 'Flexível'
        : DateFormat('dd/MM/yyyy').format(job.preferredDate!);

    final (statusLabel, statusColor) = _statusInfo(job.status);

    Widget? estimateWidget;
    if (job.status == JobStatus.proposalReceived) {
      final proposalAsync = ref.watch(proposalForJobProvider(job.id));
      estimateWidget = proposalAsync.maybeWhen(
        data: (proposal) {
          if (proposal == null) return null;
          final estimate = _formatEstimate(proposal.hourlyRate,
              proposal.estimatedHoursMin, proposal.estimatedHoursMax);
          if (estimate.isEmpty) return null;
          return Text(
            estimate,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          );
        },
        orElse: () => null,
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => context.push('/client/job/${job.id}', extra: job),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(serviceName,
                        style: theme.textTheme.titleMedium),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      statusLabel,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (job.addressText.isNotEmpty)
                Text(
                  job.addressText,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 4),
              Text(dateText, style: theme.textTheme.bodySmall),
              if (estimateWidget != null) ...[
                const SizedBox(height: 8),
                estimateWidget,
              ],
            ],
          ),
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
      JobStatus.awaitingConfirmation =>
        ('A aguardar confirmação', Colors.teal.shade600),
      JobStatus.completed => ('Concluído', Colors.grey.shade600),
      JobStatus.noResponse => ('Sem resposta', Colors.red.shade600),
      JobStatus.cancelled => ('Cancelado', Colors.grey.shade500),
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
