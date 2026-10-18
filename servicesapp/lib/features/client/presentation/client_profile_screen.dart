import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/utils/price_labels.dart';
import '../../../core/widgets/app_screen_loading_skeleton.dart';
import '../../../core/widgets/app_support_sheet.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/presentation/delete_account_flow.dart';
import '../../auth/presentation/sign_out_flow.dart';
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

  /// Erro ou perfil em falta, com "Tentar novamente" e saída da conta.
  Widget _errorState(BuildContext context, WidgetRef ref, String message) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        title: const Text('A minha conta'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(
                onPressed: () {
                  ref.invalidate(clientProfileProvider);
                  ref.invalidate(clientJobsProvider);
                },
                child: const Text('Tentar novamente'),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: () => confirmAndSignOut(context, ref),
                child: const Text('Terminar sessão'),
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
      return _errorState(context, ref, friendlyError(error));
    }

    final profile = profileAsync.asData?.value;
    if (profile == null) {
      return _errorState(context, ref, 'Perfil não encontrado.');
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
        : decimalLabel(ratingSummary.avgRating, 1);
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
      onSupportPressed: () => showSupportContactSheet(context),
      onSignOutPressed: () => confirmAndSignOut(context, ref),
      onDeleteAccountPressed: () => confirmAndDeleteAccount(context, ref),
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
