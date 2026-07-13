import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/theme/app_status_presentation.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../../core/utils/error_utils.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/data/job_model.dart';
import '../../notifications/application/notification_providers.dart';
import '../application/worker_providers.dart';
import '../data/worker_profile_model.dart';
import 'widgets/worker_available_jobs_view.dart' as view;

/// Lista de jobs disponíveis no raio do worker ("Pedidos disponíveis").
///
/// Este ficheiro é o wrapper que liga os providers reais (`jobsInRadiusProvider`,
/// `serviceTypesProvider`, `workerProfileProvider`) ao componente genérico e
/// puramente apresentacional em `widgets/worker_available_jobs_view.dart`.
/// Toda a pesquisa/filtragem é feita aqui, client-side, sobre a lista já
/// devolvida por `jobsInRadiusProvider` — ver notas de risco no relatório.
class WorkerAvailableJobsScreen extends ConsumerStatefulWidget {
  const WorkerAvailableJobsScreen({super.key});

  @override
  ConsumerState<WorkerAvailableJobsScreen> createState() =>
      _WorkerAvailableJobsScreenState();
}

class _WorkerAvailableJobsScreenState
    extends ConsumerState<WorkerAvailableJobsScreen> {
  String _searchQuery = '';
  view.WorkerAvailableJobsFilters _filters =
      const view.WorkerAvailableJobsFilters(
    selectedServiceTypeIds: {},
    urgentOnly: false,
  );

  /// Raio escolhido no chip de distância. `null` = usa o raio do perfil
  /// (comportamento atual, sem filtro extra).
  int? _radiusOverrideKm;

  Future<void> _showComingSoon() async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Em breve', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              const Text(
                'Filtros adicionais (prazo, tamanho do trabalho) vão chegar em breve.',
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fechar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDistance(int profileRadiusKm) async {
    final options = ({2, 5, 10, profileRadiusKm}
          ..removeWhere((r) => r > profileRadiusKm))
        .toList()
      ..sort();
    final currentValue = _radiusOverrideKm ?? profileRadiusKm;

    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Distância', style: Theme.of(ctx).textTheme.titleLarge),
              ),
            ),
            for (final radiusKm in options)
              ListTile(
                title: Text(
                  radiusKm == profileRadiusKm
                      ? 'Até $radiusKm km (raio definido no perfil)'
                      : 'Até $radiusKm km',
                ),
                trailing: radiusKm == currentValue
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(ctx, radiusKm),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (picked == null || !mounted) return;
    setState(() {
      // Igual ao raio do perfil == "sem filtro extra" (já é o que o backend
      // devolve por defeito).
      _radiusOverrideKm = picked == profileRadiusKm ? null : picked;
    });
  }

  List<view.WorkerAvailableJobViewData> _visibleJobs(
    List<JobRequest> allJobs,
    List<ServiceType> serviceTypes,
    WorkerProfile? workerProfile,
  ) {
    final query = _searchQuery.trim().toLowerCase();

    Iterable<JobRequest> filtered = allJobs;

    // 1. Pesquisa por texto — nome do serviço resolvido via join client-side.
    if (query.isNotEmpty) {
      filtered = filtered.where((job) {
        final name = serviceTypes
                .where((s) => s.id == job.serviceTypeId)
                .firstOrNull
                ?.name ??
            '';
        return name.toLowerCase().contains(query);
      });
    }

    // 2. Categoria (se alguma selecionada).
    if (_filters.selectedServiceTypeIds.isNotEmpty) {
      filtered = filtered.where(
        (job) => _filters.selectedServiceTypeIds.contains(job.serviceTypeId),
      );
    }

    // 3. Urgente.
    if (_filters.urgentOnly) {
      filtered = filtered.where((job) => job.urgency == Urgency.urgent);
    }

    // 4. Distância — só filtra client-side se o worker escolheu um raio
    // menor que o do perfil (o raio do perfil já foi aplicado na RPC).
    if (_radiusOverrideKm != null && workerProfile != null) {
      final radiusMeters = _radiusOverrideKm! * 1000;
      filtered = filtered.where((job) {
        final distanceMeters = Geolocator.distanceBetween(
          workerProfile.baseLat,
          workerProfile.baseLng,
          job.locationLat,
          job.locationLng,
        );
        return distanceMeters <= radiusMeters;
      });
    }

    return filtered
        .map((job) => _toViewData(job, serviceTypes, workerProfile))
        .toList();
  }

  view.WorkerAvailableJobViewData _toViewData(
    JobRequest job,
    List<ServiceType> serviceTypes,
    WorkerProfile? workerProfile,
  ) {
    final serviceType =
        serviceTypes.where((s) => s.id == job.serviceTypeId).firstOrNull;

    var locationLabel = '';
    if (workerProfile != null) {
      final distanceMeters = Geolocator.distanceBetween(
        workerProfile.baseLat,
        workerProfile.baseLng,
        job.locationLat,
        job.locationLng,
      );
      locationLabel = distanceMeters < 1000
          ? '${distanceMeters.round()} m'
          : '${(distanceMeters / 1000).toStringAsFixed(1)} km';
    }

    final scheduleLabel = job.preferredDate == null
        ? 'Flexível'
        : DateFormat('dd/MM/yyyy').format(job.preferredDate!);

    AppStatusPresentation? badge;
    if (job.urgency == Urgency.urgent) {
      badge = urgentStatusPresentation;
    } else if (DateTime.now().difference(job.createdAt).inHours < 24) {
      badge = const AppStatusPresentation(
        label: 'Novo',
        color: AppStatusColor.success,
      );
    }

    return view.WorkerAvailableJobViewData(
      id: job.id,
      title: serviceType?.name ?? '',
      locationLabel: locationLabel,
      scheduleLabel: scheduleLabel,
      // O MVP não tem preço no pedido antes de existir uma proposta (ver
      // docs/project_overview.md) — mesma decisão já tomada no dashboard
      // do worker para as "oportunidades".
      priceLabel: 'Preço a combinar',
      icon: Icons.yard_outlined,
      badge: badge,
    );
  }

  @override
  Widget build(BuildContext context) {
    final jobsAsync = ref.watch(jobsInRadiusProvider);
    final workerAsync = ref.watch(workerProfileProvider);
    final serviceTypesAsync = ref.watch(serviceTypesProvider);

    final workerProfile = workerAsync.asData?.value;
    final serviceTypes = serviceTypesAsync.asData?.value ?? <ServiceType>[];
    final profileRadiusKm = workerProfile?.radiusKm ?? 10;
    final effectiveRadiusKm = _radiusOverrideKm ?? profileRadiusKm;

    return view.WorkerAvailableJobsScreen<ServiceType>(
      jobs: jobsAsync.asData == null
          ? const []
          : _visibleJobs(jobsAsync.asData!.value, serviceTypes, workerProfile),
      serviceTypesAsync: serviceTypesAsync,
      serviceTypeIdOf: (s) => s.id,
      serviceTypeLabelOf: (s) => s.name,
      // ServiceType não tem campo de ícone e o MVP só tem 1 categoria
      // (Jardinagem) — ícone genérico para todos (ver relatório).
      serviceTypeIconOf: (_) => Icons.yard_outlined,
      onJobPressed: (id) => context.go('/worker/job/$id'),
      onSearchChanged: (query) => setState(() => _searchQuery = query),
      onFiltersPressed: _showComingSoon,
      onFiltersChanged: (filters) => setState(() => _filters = filters),
      onDistancePressed: () => _pickDistance(profileRadiusKm),
      distanceLabel: '≤ $effectiveRadiusKm km',
      isLoadingJobs: jobsAsync.isLoading,
      jobsErrorMessage:
          jobsAsync.hasError ? friendlyError(jobsAsync.error!) : null,
      onRetryJobs: () => ref.invalidate(jobsInRadiusProvider),
      appBarActions: [
        IconButton(
          icon: const Icon(Icons.group_add_outlined),
          tooltip: 'Pedidos de ajuda',
          onPressed: () => context.push('/worker/help-requests'),
        ),
        _NotificationButton(),
      ],
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
