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
import '../../../core/utils/price_labels.dart';
import '../../../core/widgets/app_about_dialog.dart';
import '../../../core/widgets/app_screen_loading_skeleton.dart';
import '../../../core/widgets/app_support_sheet.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/presentation/delete_account_flow.dart';
import '../../auth/presentation/sign_out_flow.dart';
import '../../fleet_card/application/fleet_card_providers.dart';
import '../../ratings/application/rating_providers.dart';
import '../application/worker_plan_features.dart';
import '../application/worker_plan_labels.dart';
import '../application/worker_providers.dart';
import '../data/worker_plan_model.dart';
import 'widgets/worker_account_view.dart';
import 'worker_card_share.dart';
import 'worker_plan_sheet.dart';

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
    // Mesmo formato do Perfil do cliente ("4,9", com vírgula).
    final ratingLabel = summary == null || summary.ratingCount == 0
        ? '—'
        : decimalLabel(summary.avgRating, 1);
    final reviewsLabel = summary == null || summary.ratingCount == 0
        ? 'Sem avaliações'
        : summary.ratingCount == 1
            ? '1 avaliação'
            : '${summary.ratingCount} avaliações';
    final stats = ref.watch(myProfileStatsProvider).asData?.value;
    final memberSince = stats?.memberSince;
    final canSharePublicCard = ref
            .watch(workerPublicCardProvider(userId))
            .asData
            ?.value
            ?.canUsePublicCard ??
        true;

    final publicUrl = AppLinks.publicWorkerProfileUrl(userId);

    final fleetCard = fleetCardAsync.asData?.value;
    final fleetCardStatus =
        fleetCard == null ? FleetCardStatus.notRequested : fleetCard.status;
    // Benefícios (cartão frota) são do Pro+. Quem já pediu o cartão antes
    // continua a vê-lo; sem pedido e sem Pro+, abre a folha do plano.
    final fleetCardLocked = !plan.tier.hasPartnerBenefits &&
        fleetCardStatus == FleetCardStatus.notRequested;
    final fleetCardStatusLabel = fleetCardLocked
        ? WorkerPlanTier.proPlus.label
        : fleetCardStatus.presentation.label;

    return WorkerAccountScreen(
      data: WorkerAccountViewData(
        name: profile.fullName,
        professionLocationLabel: professionLocationLabel,
        ratingLabel: ratingLabel,
        reviewsLabel: reviewsLabel,
        completedJobsLabel:
            stats == null ? '—' : '${stats.completedJobs}',
        memberSinceLabel: memberSince == null ? '—' : '${memberSince.year}',
        canSharePublicCard: canSharePublicCard,
        avatarUrl: profile.avatarUrl,
        fleetCardStatusLabel: fleetCardStatusLabel,
        planLabel: workerPlanSummaryLabel(plan),
        planTier: plan.tier,
        earningsTrailingLabel:
            plan.tier.hasEarnings ? null : WorkerPlanTier.pro.label,
      ),
      onSettingsPressed: () => context.push('/worker/profile/edit'),
      onShareCardPressed: () => context.push('/worker/card'),
      onQrPressed: () =>
          _showQrDialog(context, workerPublicCardQrUrl(userId), publicUrl),
      onAgendaPressed: () => context.go('/worker/jobs'),
      onHelpRequestsPressed: () => context.push('/worker/help-requests'),
      onNotificationsPressed: () => context.push('/notifications'),
      onReviewsPressed: () => context.push('/worker/ratings'),
      onFleetCardPressed: () => fleetCardLocked
          ? showWorkerPlanSheet(context, plan)
          : context.push('/worker/fleet-card'),
      onPlanPressed: () => showWorkerPlanSheet(context, plan),
      onEarningsPressed: () => context.push('/worker/earnings'),
      onSupportPressed: () => showSupportContactSheet(context),
      onSignOutPressed: () => confirmAndSignOut(context, ref),
      onDeleteAccountPressed: () => confirmAndDeleteAccount(context, ref),
      onAboutPressed: () => showAppAboutDialog(context),
    );
  }
}
