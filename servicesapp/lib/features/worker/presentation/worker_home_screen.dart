import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/data/job_model.dart';
import '../application/worker_providers.dart';

class WorkerHomeScreen extends ConsumerWidget {
  const WorkerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(jobsInRadiusProvider);
    final workerAsync = ref.watch(workerProfileProvider);
    final serviceTypesAsync = ref.watch(serviceTypesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LocalServices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: null,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(jobsInRadiusProvider),
        child: jobsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erro: $e')),
          data: (jobs) {
            if (jobs.isEmpty) {
              return LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: constraints.maxHeight,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'Não há pedidos na tua zona neste momento.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }

            final workerProfile = workerAsync.value;
            final serviceTypes = serviceTypesAsync.value ?? [];

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: jobs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final job = jobs[index];
                final serviceType = serviceTypes
                    .where((s) => s.id == job.serviceTypeId)
                    .firstOrNull;

                double? distanceMeters;
                if (workerProfile != null) {
                  distanceMeters = Geolocator.distanceBetween(
                    workerProfile.baseLat,
                    workerProfile.baseLng,
                    job.locationLat,
                    job.locationLng,
                  );
                }

                return _JobCard(
                  job: job,
                  serviceTypeName: serviceType?.name ?? '',
                  distanceMeters: distanceMeters,
                  onTap: () =>
                      context.go('/worker/job/${job.id}', extra: job),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  final JobRequest job;
  final String serviceTypeName;
  final double? distanceMeters;
  final VoidCallback onTap;

  const _JobCard({
    required this.job,
    required this.serviceTypeName,
    this.distanceMeters,
    required this.onTap,
  });

  String _formatDate() {
    if (job.preferredDate == null) return 'Flexível';
    return DateFormat('dd/MM/yyyy').format(job.preferredDate!);
  }

  String _formatDistance() {
    if (distanceMeters == null) return '';
    if (distanceMeters! < 1000) return '${distanceMeters!.round()} m';
    return '${(distanceMeters! / 1000).toStringAsFixed(1)} km';
  }

  String? _sizeLabel() => switch (job.sizeEstimate) {
        SizeEstimate.small => 'Pequeno',
        SizeEstimate.medium => 'Médio',
        SizeEstimate.large => 'Grande',
        null => null,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final distanceStr = _formatDistance();
    final sizeLabel = _sizeLabel();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
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
                  if (job.urgency == Urgency.urgent)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Urgente',
                        style: TextStyle(color: Colors.white, fontSize: 12),
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
                      label: _formatDate()),
                  if (distanceStr.isNotEmpty)
                    _MetaItem(
                        icon: Icons.place_outlined, label: distanceStr),
                  if (sizeLabel != null)
                    _MetaItem(
                        icon: Icons.straighten_outlined, label: sizeLabel),
                ],
              ),
              if (job.addressText.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  job.addressText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
