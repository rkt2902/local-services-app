import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/config/app_links.dart';
import '../../../core/constants/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_about_dialog.dart';
import '../../../core/widgets/app_screen_loading_skeleton.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_support_sheet.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/presentation/delete_account_flow.dart';
import '../../auth/presentation/sign_out_flow.dart';
import '../../fleet_card/application/fleet_card_providers.dart';
import '../../ratings/application/rating_providers.dart';
import '../application/worker_plan_labels.dart';
import '../application/worker_providers.dart';
import '../data/worker_plan_model.dart';
import 'widgets/worker_account_view.dart';
import 'worker_card_share.dart';

class WorkerProfileScreen extends ConsumerWidget {
  const WorkerProfileScreen({super.key});

  void _showQrDialog(BuildContext context, String qrUrl, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'O meu QR',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              QrImageView(
                data: qrUrl,
                size: 220,
                backgroundColor: AppColors.surface,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                url,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPlanSheet(BuildContext context, WorkerPlan plan) {
    AppSheet.show<void>(
      context,
      builder: (sheetContext) => AppSheet(
        title: 'Plano ${plan.tier.label}',
        onClose: () => Navigator.of(sheetContext).pop(),
        child: Text(
          workerPlanExplanation(plan),
          style: Theme.of(sheetContext)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(workerProfileProvider);
    final serviceTypesAsync = ref.watch(serviceTypesProvider);
    final userId = ref.watch(currentUserProvider)?.id;
    final ratingSummaryAsync = userId == null
        ? null
        : ref.watch(ratingSummaryProvider(userId));
    final fleetCardAsync = ref.watch(myFleetCardProvider);
    final plan =
        ref.watch(myWorkerPlanProvider).asData?.value ?? WorkerPlan.unavailable;

    if (profileAsync.isLoading || serviceTypesAsync.isLoading) {
      return const Scaffold(body: AppScreenLoadingSkeleton());
    }

    final error =
        profileAsync.hasError ? profileAsync.error : serviceTypesAsync.error;
    if (error != null) {
      return Scaffold(body: Center(child: Text(friendlyError(error))));
    }

    final profile = profileAsync.asData?.value;
    if (profile == null || userId == null) {
      return const Scaffold(body: Center(child: Text('Perfil não encontrado.')));
    }

    final serviceTypes = serviceTypesAsync.asData?.value ?? [];
    final serviceName = serviceTypes
        .where((t) => profile.serviceTypeIds.contains(t.id))
        .map((t) => t.name)
        .firstOrNull;
    final professionLocationParts = [
      ?serviceName,
      if (profile.locationName.isNotEmpty) profile.locationName,
    ];
    final professionLocationLabel = professionLocationParts.isEmpty
        ? 'Jardineiro ProJardim'
        : professionLocationParts.join(' · ');

    final summary = ratingSummaryAsync?.asData?.value;
    final ratingLabel =
        summary == null ? '—' : summary.avgRating.toStringAsFixed(1);
    final reviewsLabel =
        summary == null ? '0 avaliações' : '${summary.ratingCount} avaliações';

    final publicUrl = AppLinks.publicWorkerProfileUrl(userId);

    final fleetCard = fleetCardAsync.asData?.value;
    final fleetCardStatus =
        fleetCard == null ? FleetCardStatus.notRequested : fleetCard.status;
    final fleetCardStatusLabel = fleetCardStatus.presentation.label;

    return WorkerAccountScreen(
      data: WorkerAccountViewData(
        name: profile.fullName,
        professionLocationLabel: professionLocationLabel,
        ratingLabel: ratingLabel,
        reviewsLabel: reviewsLabel,
        avatarImage: profile.avatarUrl != null
            ? NetworkImage(profile.avatarUrl!)
            : null,
        fleetCardStatusLabel: fleetCardStatusLabel,
        planLabel: workerPlanSummaryLabel(plan),
      ),
      onSettingsPressed: () => context.push('/worker/profile/edit'),
      onDefinitionsPressed: () => context.push('/worker/profile/edit'),
      onShareCardPressed: () => shareWorkerPublicCard(userId),
      onQrPressed: () =>
          _showQrDialog(context, workerPublicCardQrUrl(userId), publicUrl),
      onJobsPressed: () => context.go('/worker/jobs'),
      onReviewsPressed: () => context.push('/worker/ratings'),
      onFleetCardPressed: () => context.push('/worker/fleet-card'),
      onPlanPressed: () => _showPlanSheet(context, plan),
      onSupportPressed: () => showSupportContactSheet(context),
      onSignOutPressed: () => confirmAndSignOut(context, ref),
      onDeleteAccountPressed: () => confirmAndDeleteAccount(context, ref),
      onAboutPressed: () => showAppAboutDialog(context),
    );
  }
}
