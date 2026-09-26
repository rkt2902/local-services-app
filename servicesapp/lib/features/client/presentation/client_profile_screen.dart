import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_screen_loading_skeleton.dart';
import '../../auth/application/auth_providers.dart';
import '../../jobs/application/job_providers.dart';
import '../../ratings/application/rating_providers.dart';
import '../application/client_providers.dart';
import 'widgets/client_account_view.dart';

const _monthsPt = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

String _memberSinceLabel(DateTime? createdAt) {
  if (createdAt == null) return 'Membro ProJardim';
  return 'Membro desde ${_monthsPt[createdAt.month - 1]} de ${createdAt.year}';
}

class ClientProfileScreen extends ConsumerWidget {
  const ClientProfileScreen({super.key});

  void _showSupportSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Contacto & suporte',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'Precisas de ajuda? Escreve-nos para '
                'suporte@projardim.pt e respondemos o mais depressa possível.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(clientProfileProvider);
    final jobsAsync = ref.watch(clientJobsProvider);
    final userId = ref.watch(currentUserProvider)?.id;
    final ratingSummaryAsync =
        userId == null ? null : ref.watch(ratingSummaryProvider(userId));

    if (profileAsync.isLoading || jobsAsync.isLoading) {
      return const Scaffold(body: AppScreenLoadingSkeleton());
    }

    final error = profileAsync.hasError
        ? profileAsync.error
        : (jobsAsync.hasError ? jobsAsync.error : null);
    if (error != null) {
      return Scaffold(body: Center(child: Text(friendlyError(error))));
    }

    final profile = profileAsync.asData?.value;
    if (profile == null) {
      return const Scaffold(body: Center(child: Text('Perfil não encontrado.')));
    }

    final jobs = jobsAsync.asData?.value ?? [];
    final activeJobs = jobs
        .where((j) =>
            j.status == JobStatus.confirmed ||
            j.status == JobStatus.awaitingConfirmation)
        .length;
    final completedJobs =
        jobs.where((j) => j.status == JobStatus.completed).length;

    final ratingSummary = ratingSummaryAsync?.asData?.value;
    final ratingLabel = ratingSummary == null
        ? '—'
        : ratingSummary.avgRating.toStringAsFixed(1);
    final reviewsLabel = ratingSummary == null
        ? '0 avaliações'
        : '${ratingSummary.ratingCount} avaliações';

    return ClientAccountScreen(
      data: ClientAccountViewData(
        name: profile.fullName,
        memberSinceLabel: _memberSinceLabel(profile.createdAt),
        totalJobs: jobs.length,
        activeJobs: activeJobs,
        completedJobs: completedJobs,
        ratingLabel: ratingLabel,
        reviewsLabel: reviewsLabel,
        avatarImage: profile.avatarUrl != null
            ? NetworkImage(profile.avatarUrl!)
            : null,
      ),
      onSettingsPressed: () => context.push('/client/profile/edit'),
      onDefinitionsPressed: () => context.push('/client/profile/edit'),
      onJobsPressed: () => context.go('/client/jobs'),
      onReviewsPressed: () => context.push('/client/ratings'),
      onSupportPressed: () => _showSupportSheet(context),
      onAboutPressed: () => showAboutDialog(
        context: context,
        applicationName: 'ProJardim',
        applicationVersion: '1.0.0',
        children: const [
          Text(
            'Marketplace de serviços de jardinagem. Liga clientes a '
            'jardineiros na tua zona.',
          ),
        ],
      ),
    );
  }
}
