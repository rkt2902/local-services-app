import 'package:flutter/material.dart';

import 'package:servicesapp/core/theme/app_colors.dart';
import 'package:servicesapp/core/theme/app_radius.dart';
import 'package:servicesapp/core/theme/app_spacing.dart';
import 'package:servicesapp/core/widgets/app_account_menu_group.dart';
import 'package:servicesapp/core/widgets/app_motion.dart';

class ClientAccountViewData {
  const ClientAccountViewData({
    required this.name,
    required this.memberSinceLabel,
    required this.totalJobs,
    required this.activeJobs,
    required this.completedJobs,
    this.avatarImage,
  });

  final String name;
  final String memberSinceLabel;
  final ImageProvider? avatarImage;

  final int totalJobs;
  final int activeJobs;
  final int completedJobs;
}

class ClientAccountScreen extends StatelessWidget {
  const ClientAccountScreen({
    required this.data,
    required this.onSettingsPressed,
    required this.onJobsPressed,
    required this.onDefinitionsPressed,
    required this.onSupportPressed,
    required this.onAboutPressed,
    super.key,
  });

  final ClientAccountViewData data;

  final VoidCallback onSettingsPressed;
  final VoidCallback onJobsPressed;
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
              child: _ClientIdentityCard(
                data: data,
              ),
            ),
            const SizedBox(
              height: AppSpacing.md,
            ),
            AppStaggeredEntrance(
              index: 1,
              child: AppAccountMenuGroup(
                items: const [
                  AppAccountMenuItem(
                    id: 'jobs',
                    label: 'Os meus pedidos',
                    icon: Icons.receipt_long_outlined,
                  ),
                ],
                onItemPressed: (id) {
                  switch (id) {
                    case 'jobs':
                      onJobsPressed();
                  }
                },
              ),
            ),
            const SizedBox(
              height: AppSpacing.md,
            ),
            AppStaggeredEntrance(
              index: 2,
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

class _ClientIdentityCard extends StatelessWidget {
  const _ClientIdentityCard({
    required this.data,
  });

  final ClientAccountViewData data;

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
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleLarge?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      data.memberSinceLabel,
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
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
          Row(
            children: [
              Expanded(
                child: _AccountMetric(
                  value: data.totalJobs.toString(),
                  label: 'Pedidos',
                  foreground: AppColors.primary,
                ),
              ),
              const SizedBox(
                width: AppSpacing.xs,
              ),
              Expanded(
                child: _AccountMetric(
                  value: data.activeJobs.toString(),
                  label: 'Em curso',
                  foreground: AppColors.textSecondary,
                ),
              ),
              const SizedBox(
                width: AppSpacing.xs,
              ),
              Expanded(
                child: _AccountMetric(
                  value: data.completedJobs.toString(),
                  label: 'Concluídos',
                  foreground: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountMetric extends StatelessWidget {
  const _AccountMetric({
    required this.value,
    required this.label,
    required this.foreground,
  });

  final String value;
  final String label;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(
          AppRadius.input,
        ),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: textTheme.titleMedium?.copyWith(
              color: foreground,
            ),
          ),
          const SizedBox(
            height: AppSpacing.xxs,
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
