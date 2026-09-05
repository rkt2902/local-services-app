import 'package:flutter/material.dart';

import 'package:servicesapp/core/theme/app_colors.dart';
import 'package:servicesapp/core/theme/app_radius.dart';
import 'package:servicesapp/core/theme/app_spacing.dart';
import 'package:servicesapp/core/widgets/app_account_menu_group.dart';
import 'package:servicesapp/core/widgets/app_motion.dart';

class WorkerAccountViewData {
  const WorkerAccountViewData({
    required this.name,
    required this.professionLocationLabel,
    required this.ratingLabel,
    required this.reviewsLabel,
    this.avatarImage,
  });

  final String name;
  final String professionLocationLabel;

  final String ratingLabel;
  final String reviewsLabel;

  final ImageProvider? avatarImage;
}

class WorkerAccountScreen extends StatelessWidget {
  const WorkerAccountScreen({
    required this.data,
    required this.onSettingsPressed,
    required this.onShareCardPressed,
    required this.onQrPressed,
    required this.onJobsPressed,
    required this.onReviewsPressed,
    required this.onDefinitionsPressed,
    required this.onSupportPressed,
    required this.onAboutPressed,
    super.key,
  });

  final WorkerAccountViewData data;

  final VoidCallback onSettingsPressed;
  final VoidCallback onShareCardPressed;
  final VoidCallback onQrPressed;

  final VoidCallback onJobsPressed;
  final VoidCallback onReviewsPressed;

  final VoidCallback onDefinitionsPressed;
  final VoidCallback onSupportPressed;
  final VoidCallback onAboutPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        title: Text(
          'A minha conta',
          style: textTheme.titleLarge?.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            onPressed: onSettingsPressed,
            tooltip: 'Definições',
            icon: const Icon(
              Icons.settings_outlined,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(
            width: AppSpacing.xs,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Column(
          children: [
            AppStaggeredEntrance(
              index: 0,
              child: _WorkerDigitalCard(
                data: data,
              ),
            ),
            const SizedBox(
              height: AppSpacing.md,
            ),
            AppStaggeredEntrance(
              index: 1,
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: onShareCardPressed,
                        style: FilledButton.styleFrom(
                          elevation: 0,
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadius.input,
                            ),
                          ),
                        ),
                        icon: const Icon(
                          Icons.share_outlined,
                        ),
                        label: const Text(
                          'Partilhar',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(
                    width: AppSpacing.xs,
                  ),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: onQrPressed,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(
                          color: AppColors.primary,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppRadius.input,
                          ),
                        ),
                      ),
                      icon: const Icon(
                        Icons.qr_code_rounded,
                      ),
                      label: const Text('QR'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(
              height: AppSpacing.md,
            ),
            const AppStaggeredEntrance(
              index: 2,
              child: _WorkerCardVisibilityInfo(),
            ),
            const SizedBox(
              height: AppSpacing.md,
            ),
            AppStaggeredEntrance(
              index: 3,
              child: AppAccountMenuGroup(
                items: [
                  const AppAccountMenuItem(
                    id: 'jobs',
                    label: 'Os meus trabalhos',
                    icon: Icons.work_outline_rounded,
                  ),
                  AppAccountMenuItem(
                    id: 'reviews',
                    label: 'Avaliações',
                    icon: Icons.star_border_rounded,
                    trailingLabel:
                        '${data.ratingLabel} · ${data.reviewsLabel}',
                  ),
                ],
                onItemPressed: (id) {
                  switch (id) {
                    case 'jobs':
                      onJobsPressed();
                    case 'reviews':
                      onReviewsPressed();
                  }
                },
              ),
            ),
            const SizedBox(
              height: AppSpacing.md,
            ),
            AppStaggeredEntrance(
              index: 4,
              child: AppAccountMenuGroup(
                items: const [
                  AppAccountMenuItem(
                    id: 'settings',
                    label: 'Definições',
                    icon: Icons.settings_outlined,
                  ),
                  AppAccountMenuItem(
                    id: 'support',
                    label: 'Contacto & suporte',
                    icon: Icons.support_agent_outlined,
                  ),
                  AppAccountMenuItem(
                    id: 'about',
                    label: 'Sobre a ProJardim',
                    icon: Icons.info_outline_rounded,
                  ),
                ],
                onItemPressed: (id) {
                  switch (id) {
                    case 'settings':
                      onDefinitionsPressed();
                    case 'support':
                      onSupportPressed();
                    case 'about':
                      onAboutPressed();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkerDigitalCard extends StatelessWidget {
  const _WorkerDigitalCard({
    required this.data,
  });

  final WorkerAccountViewData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(
          AppRadius.card,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 0,
            bottom: -20,
            child: Icon(
              Icons.eco_outlined,
              size: 110,
              color: AppColors.surface.withValues(
                alpha: 0.10,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.eco_outlined,
                    color: AppColors.surface,
                  ),
                  const SizedBox(
                    width: AppSpacing.xs,
                  ),
                  Expanded(
                    child: Text(
                      'ProJardim +',
                      style: textTheme.titleMedium?.copyWith(
                        color: AppColors.surface,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.qr_code_2_rounded,
                    color: AppColors.surface,
                  ),
                ],
              ),
              const SizedBox(
                height: AppSpacing.md,
              ),
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.surface,
                    backgroundImage: data.avatarImage,
                    child: data.avatarImage == null
                        ? const Icon(
                            Icons.person_outline_rounded,
                            color: AppColors.primary,
                          )
                        : null,
                  ),
                  const SizedBox(
                    width: AppSpacing.sm,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleLarge?.copyWith(
                            color: AppColors.surface,
                          ),
                        ),
                        Text(
                          data.professionLocationLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelMedium?.copyWith(
                            color: AppColors.surface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(
                height: AppSpacing.md,
              ),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  _WorkerCardTag(
                    icon: Icons.star_rounded,
                    label:
                        '${data.ratingLabel} (${data.reviewsLabel})',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkerCardTag extends StatelessWidget {
  const _WorkerCardTag({
    required this.label,
    this.icon,
  });

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(
          alpha: 0.18,
        ),
        borderRadius: BorderRadius.circular(
          AppRadius.pill,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 16,
              color: AppColors.surface,
            ),
            const SizedBox(
              width: AppSpacing.xxs,
            ),
          ],
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: AppColors.surface,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkerCardVisibilityInfo extends StatelessWidget {
  const _WorkerCardVisibilityInfo();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(
          AppRadius.card,
        ),
        border: Border.all(
          color: AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Os meus cartões · visibilidade',
                  style: textTheme.labelMedium?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(
                    AppRadius.pill,
                  ),
                ),
                child: Text(
                  'Futuro',
                  style: textTheme.labelMedium?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(
            height: AppSpacing.sm,
          ),
          const _VisibilityRow(
            icon: Icons.link_rounded,
            label: 'Partilha por link ou QR com clientes',
          ),
          const SizedBox(
            height: AppSpacing.xs,
          ),
          const _VisibilityRow(
            icon: Icons.trending_up_rounded,
            label: 'Destaque em pesquisas',
          ),
          const SizedBox(
            height: AppSpacing.xs,
          ),
          const _VisibilityRow(
            icon: Icons.verified_user_outlined,
            label: 'Mais confiança de novos clientes',
          ),
        ],
      ),
    );
  }
}

class _VisibilityRow extends StatelessWidget {
  const _VisibilityRow({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: AppColors.primary,
        ),
        const SizedBox(
          width: AppSpacing.sm,
        ),
        Expanded(
          child: Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
