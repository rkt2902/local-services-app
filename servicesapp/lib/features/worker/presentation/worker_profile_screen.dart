import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/app_links.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_utils.dart';
import '../../auth/application/auth_providers.dart';
import '../../ratings/application/rating_providers.dart';
import '../../ratings/presentation/ratings_sheet.dart';
import '../application/worker_providers.dart';
import 'widgets/worker_account_view.dart';

class WorkerProfileScreen extends ConsumerWidget {
  const WorkerProfileScreen({super.key});

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

  void _showQrDialog(BuildContext context, String url) {
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
                data: url,
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

    if (profileAsync.isLoading || serviceTypesAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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

    return WorkerAccountScreen(
      data: WorkerAccountViewData(
        name: profile.fullName,
        professionLocationLabel: professionLocationLabel,
        ratingLabel: ratingLabel,
        reviewsLabel: reviewsLabel,
        avatarImage: profile.avatarUrl != null
            ? NetworkImage(profile.avatarUrl!)
            : null,
      ),
      onSettingsPressed: () => context.push('/worker/profile/edit'),
      onDefinitionsPressed: () => context.push('/worker/profile/edit'),
      onShareCardPressed: () => SharePlus.instance.share(
        ShareParams(
          text: 'Vê o meu perfil na ProJardim: $publicUrl',
        ),
      ),
      onQrPressed: () => _showQrDialog(context, publicUrl),
      onJobsPressed: () => context.go('/worker/jobs'),
      onReviewsPressed: () => showRatingsSheet(
        context,
        workerId: userId,
        workerName: 'As minhas avaliações',
      ),
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
