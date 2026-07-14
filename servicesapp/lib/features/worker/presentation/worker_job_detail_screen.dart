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
import '../../auth/application/auth_providers.dart';
import '../../client/application/client_providers.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/data/job_model.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../proposals/data/proposal_model.dart';
import '../application/worker_providers.dart';
import 'widgets/worker_job_detail_view.dart' as view;

/// Detalhe de uma oportunidade ("Pedidos disponíveis" → detalhe).
///
/// Wrapper que liga os providers reais ao componente apresentacional em
/// widgets/worker_job_detail_view.dart.
class WorkerJobDetailScreen extends ConsumerWidget {
  const WorkerJobDetailScreen({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobAsync = ref.watch(jobByIdProvider(jobId));

    return jobAsync.when(
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
        return _buildDetail(context, ref, job);
      },
    );
  }

  Widget _buildDetail(BuildContext context, WidgetRef ref, JobRequest job) {
    final serviceTypes = ref.watch(serviceTypesProvider).asData?.value ?? [];
    final workerProfile = ref.watch(workerProfileProvider).asData?.value;
    final photos = ref.watch(jobPhotosProvider(jobId)).asData?.value ?? [];
    final clientInfo =
        ref.watch(clientBasicInfoProvider(job.clientId)).asData?.value;

    final currentUserId = ref.watch(currentUserIdProvider) ?? '';
    final workerProposalAsync = currentUserId.isEmpty
        ? const AsyncValue<JobProposal?>.data(null)
        : ref.watch(workerProposalForJobProvider((jobId, currentUserId)));
    final alreadySent = workerProposalAsync.asData?.value != null;

    final serviceType =
        serviceTypes.where((s) => s.id == job.serviceTypeId).firstOrNull;

    var distanceLabel = '';
    if (workerProfile != null) {
      final meters = Geolocator.distanceBetween(
        workerProfile.baseLat,
        workerProfile.baseLng,
        job.locationLat,
        job.locationLng,
      );
      distanceLabel = meters < 1000
          ? '${meters.round()} m'
          : '${(meters / 1000).toStringAsFixed(1)} km';
    }

    AppStatusPresentation? badge;
    if (job.urgency == Urgency.urgent) {
      badge = urgentStatusPresentation;
    } else if (DateTime.now().difference(job.createdAt).inHours < 24) {
      badge = const AppStatusPresentation(
        label: 'Novo',
        color: AppStatusColor.success,
      );
    }

    final avatarUrl = clientInfo?['avatar_url'];

    final data = view.WorkerJobDetailViewData(
      id: job.id,
      title: serviceType?.name ?? '',
      locationLabel: job.addressText.isNotEmpty
          ? job.addressText
          : 'Localização não especificada',
      distanceLabel: distanceLabel,
      deadlineLabel: _deadlineLabel(job),
      areaLabel: _areaLabel(job),
      // O MVP não tem orçamento no pedido (só nasce quando um worker
      // propõe) — mesma decisão já usada no dashboard e na lista de
      // pedidos disponíveis.
      budgetLabel: 'Preço a combinar',
      description: job.description,
      serviceIcon: Icons.yard_outlined,
      clientName: clientInfo?['full_name'] ?? '',
      clientAvatar: (avatarUrl != null && avatarUrl.isNotEmpty)
          ? avatarUrl
          : null,
      photos: photos.map((url) => NetworkImage(url) as ImageProvider).toList(),
      badge: badge,
    );

    return view.WorkerJobDetailScreen(
      data: data,
      onBack: () => context.pop(),
      onSendProposalPressed: alreadySent
          ? () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Já enviaste uma proposta para este pedido.'),
                ),
              )
          : () => context.push('/worker/job/$jobId/propose'),
    );
  }
}

/// O pedido nunca tem hora, só data (ou flexível, ou texto livre) — ver
/// docs (JobRequest.preferredDate é DateTime sem componente de hora útil).
String _deadlineLabel(JobRequest job) {
  switch (job.dateMode) {
    case DateMode.fixed:
      final date = job.preferredDate;
      if (date == null) return 'Data a combinar';
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final target = DateTime(date.year, date.month, date.day);
      if (target == today) return 'Hoje';
      if (target == tomorrow) return 'Amanhã';
      return DateFormat('dd/MM/yyyy').format(date);
    case DateMode.flexible:
      return 'Flexível';
    case DateMode.availability:
      return 'Ver disponibilidade';
  }
}

String _areaLabel(JobRequest job) => switch (job.sizeEstimate) {
      SizeEstimate.small => 'Pequeno',
      SizeEstimate.medium => 'Médio',
      SizeEstimate.large => 'Grande',
      null => 'Não especificado',
    };
