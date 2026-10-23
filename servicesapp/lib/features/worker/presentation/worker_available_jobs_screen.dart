import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/price_labels.dart';
import '../../../core/constants/enums.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/theme/app_status_presentation.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/service_icon.dart';
import '../../auth/application/auth_providers.dart';
import '../../jobs/application/direct_request_labels.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/data/job_model.dart';
import '../../notifications/application/notification_providers.dart';
import '../application/worker_providers.dart';
import '../data/worker_profile_model.dart';
import 'widgets/worker_available_jobs_view.dart' as view;
import '../../../core/theme/app_spacing.dart';

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
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.s20, AppSpacing.lg, AppSpacing.xxs),
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
            const SizedBox(height: AppSpacing.xs),
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

  /// Pedido direto (0057, 0059) ainda reservado a este jardineiro: à
  /// espera dele, ou parado depois do prazo à espera do cliente (ainda pode
  /// propor). O servidor só manda `direct_worker_id` ao próprio.
  bool _isDirectForMe(JobRequest job) {
    final myId = ref.read(currentUserIdProvider);
    return (job.isDirectWaiting || job.isDirectOnHold) &&
        myId != null &&
        job.directWorkerId == myId;
  }

  List<view.WorkerAvailableJobViewData> _visibleJobs(
    List<JobRequest> allJobs,
    List<ServiceType> serviceTypes,
    WorkerProfile? workerProfile,
  ) {
    final query = _searchQuery.trim().toLowerCase();

    // Pedidos só para mim (A7): fixos no topo, fora de pesquisa, filtros e
    // raio. Não mudam o raio nem os filtros para o resto.
    final pinned = allJobs.where(_isDirectForMe).toList();
    Iterable<JobRequest> filtered =
        allJobs.where((job) => !_isDirectForMe(job));

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

    return [...pinned, ...filtered]
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

    final forMe = _isDirectForMe(job);
    var locationLabel = '';
    if (workerProfile != null) {
      final distanceMeters = Geolocator.distanceBetween(
        workerProfile.baseLat,
        workerProfile.baseLng,
        job.locationLat,
        job.locationLng,
      );
      // Fora do raio: pedido direto ou pedido mostrado mais longe (0062).
      locationLabel = distanceMeters > workerProfile.radiusKm * 1000
          ? outsideAreaLabel(distanceMeters / 1000)
          : distanceMeters < 1000
              ? '${distanceMeters.round()} m'
              : '${decimalLabel(distanceMeters / 1000, 1)} km';
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

    final directUntil = job.directUntil;
    return view.WorkerAvailableJobViewData(
      id: job.id,
      directTagLabel: !forMe
          ? null
          : job.isDirectOnHold
              ? 'Pedido só para ti · prazo terminado'
              : directUntil != null
                  ? 'Pedido só para ti · '
                      '${directTimeLeftLabel(directUntil, DateTime.now())}'
                  : 'Pedido só para ti',
      title: serviceType?.name ?? '',
      locationLabel: locationLabel,
      scheduleLabel: scheduleLabel,
      // O MVP não tem preço no pedido antes de existir uma proposta (ver
      // docs/project_overview.md) — mesma decisão já tomada no dashboard
      // do worker para as "oportunidades".
      priceLabel: 'Preço a combinar',
      icon: serviceIconFor(serviceType?.icon),
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
      serviceTypeIconOf: (s) => serviceIconFor(s.icon),
      onJobPressed: (id) => context.push('/worker/job/$id'),
      onSearchChanged: (query) => setState(() => _searchQuery = query),
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
      tooltip: 'Notificações',
      icon: Badge(
        label: Text('$count'),
        isLabelVisible: count > 0,
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () => context.push('/notifications'),
    );
  }
}
