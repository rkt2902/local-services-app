import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/error_utils.dart';
import '../application/client_providers.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/data/job_model.dart';
import '../../notifications/application/notification_providers.dart';

class ClientHomeScreen extends ConsumerWidget {
  const ClientHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profileAsync = ref.watch(clientProfileProvider);
    final jobsAsync = ref.watch(clientJobsProvider);
    final serviceTypesAsync = ref.watch(serviceTypesProvider);

    final firstName = profileAsync.maybeWhen(
      data: (p) => p?.fullName.split(' ').first ?? '',
      orElse: () => '',
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('LocalServices'),
        actions: [
          _NotificationButton(),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              firstName.isEmpty ? 'Olá!' : 'Olá, $firstName!',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Pedidos recentes',
                    style: theme.textTheme.titleMedium),
                TextButton(
                  onPressed: () => context.push('/client/jobs'),
                  child: const Text('Ver todos →'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            jobsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text(friendlyError(e)),
              data: (jobs) {
                final activeJobs = jobs
                    .where((j) =>
                        j.status == JobStatus.open ||
                        j.status == JobStatus.confirmed)
                    .take(3)
                    .toList();

                if (activeJobs.isEmpty) {
                  return _EmptyJobsCard(
                    onTap: () => context.push('/client/create-job'),
                  );
                }

                return serviceTypesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text(friendlyError(e)),
                  data: (serviceTypes) => Column(
                    children: activeJobs.map((job) {
                      final serviceName = serviceTypes
                              .where((t) => t.id == job.serviceTypeId)
                              .map((t) => t.name)
                              .firstOrNull ??
                          'Desconhecido';
                      return _CompactJobCard(
                        job: job,
                        serviceName: serviceName,
                        onTap: () => context.push('/client/job/${job.id}'),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyJobsCard extends StatelessWidget {
  const _EmptyJobsCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.yard_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Ainda não tens pedidos ativos.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onTap,
              child: const Text('Criar primeiro pedido'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactJobCard extends StatelessWidget {
  const _CompactJobCard({
    required this.job,
    required this.serviceName,
    required this.onTap,
  });

  final JobRequest job;
  final String serviceName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (statusLabel, statusColor) = _statusChip(job.status, job.proposalCount);
    final dateText = job.preferredDate == null
        ? 'Flexível'
        : DateFormat('dd/MM/yyyy').format(job.preferredDate!);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(serviceName,
                        style: theme.textTheme.titleSmall),
                    Text(
                      job.addressText,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(dateText,
                        style: theme.textTheme.bodySmall),
                  ],
                ),
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
        ),
      ),
    );
  }
}

class _NotificationButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadCountProvider);
    return IconButton(
      icon: Badge(
        label: Text('$count'),
        isLabelVisible: count > 0,
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () => context.push('/notifications'),
    );
  }
}

(String, Color) _statusChip(JobStatus status, int proposalCount) =>
    switch (status) {
      JobStatus.open when proposalCount > 0 =>
        ('$proposalCount proposta${proposalCount > 1 ? 's' : ''}',
        Colors.orange.shade700),
      JobStatus.open => ('À espera', Colors.blue.shade600),
      JobStatus.confirmed => ('Confirmado', Colors.green.shade600),
      JobStatus.awaitingConfirmation =>
        ('A confirmar', Colors.teal.shade600),
      JobStatus.completed => ('Concluído', Colors.grey.shade600),
      JobStatus.noResponse => ('Sem resposta', Colors.red.shade600),
      JobStatus.cancelled => ('Cancelado', Colors.grey.shade500),
    };
