import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/widgets/app_motion.dart';

/// Um número do painel: valor grande, nome por baixo e nota opcional.
class AdminStat {
  const AdminStat({required this.label, required this.value, this.caption});

  final String label;
  final String value;
  final String? caption;
}

/// Cartão com título e uma grelha de [AdminStat] (2 colunas no
/// telemóvel, 3 a partir de 560 de largura).
class AdminStatsCard extends StatelessWidget {
  const AdminStatsCard({required this.title, required this.stats, super.key});

  final String title;
  final List<AdminStat> stats;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  textTheme.titleMedium?.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 560 ? 3 : 2;
              final width = (constraints.maxWidth -
                      AppSpacing.sm * (columns - 1)) /
                  columns;
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final stat in stats)
                    SizedBox(width: width, child: _AdminStatTile(stat: stat)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AdminStatTile extends StatelessWidget {
  const _AdminStatTile({required this.stat});

  final AdminStat stat;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final caption = stat.caption;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(stat.value,
              style: textTheme.titleLarge
                  ?.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.xxs),
          Text(stat.label,
              style: textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondary)),
          if (caption != null)
            Text(caption,
                style: textTheme.labelSmall
                    ?.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/// Linha de alerta (fundo no tom `waiting`).
class AdminAlertRow extends StatelessWidget {
  const AdminAlertRow({required this.icon, required this.message, super.key});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final tone = AppStatusColor.waiting;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Row(
        children: [
          Icon(icon, color: tone.foreground, size: 20),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: tone.foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// Esqueleto de carregamento: blocos no lugar dos cartões.
class AdminLoadingBlocks extends StatelessWidget {
  const AdminLoadingBlocks({this.count = 3, this.height = 140, super.key});

  final int count;
  final double height;

  @override
  Widget build(BuildContext context) {
    return AppSkeletonShimmer(
      child: Column(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            Container(
              height: height,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
