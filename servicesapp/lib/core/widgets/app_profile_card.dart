import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_sizes.dart';
import '../theme/app_spacing.dart';
import 'app_initials_avatar.dart';

/// Um número do cartão do Perfil ("12" · "Pedidos"). Chega já formatado.
class AppProfileMetric {
  const AppProfileMetric({required this.value, required this.label});

  final String value;
  final String label;
}

/// Cartão do topo do Perfil (design A11, C4 e J6), igual nos dois papéis:
/// avatar com iniciais, nome, linha de contexto, três números e, no
/// jardineiro, os botões do cartão partilhável ([actions]).
class AppProfileCard extends StatelessWidget {
  const AppProfileCard({
    super.key,
    required this.name,
    required this.subtitle,
    required this.metrics,
    this.avatarUrl,
    this.actions,
    this.onPressed,
  });

  final String name;
  final String subtitle;
  final String? avatarUrl;
  final List<AppProfileMetric> metrics;

  /// Fila por baixo dos números (ex.: "Partilhar" e "QR").
  final Widget? actions;

  /// Toque no nome: editar o perfil.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final actions = this.actions;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(AppRadius.input),
            child: Row(
              children: [
                AppInitialsAvatar(
                  initial: initialsOf(name),
                  radius: AppSizes.profileAvatarRadius,
                  avatarUrl: avatarUrl,
                  textStyle: textTheme.titleLarge,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleLarge?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                for (var i = 0; i < metrics.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.xs),
                  Expanded(child: _MetricTile(metric: metrics[i])),
                ],
              ],
            ),
          ],
          if (actions != null) ...[
            const SizedBox(height: AppSpacing.sm),
            actions,
          ],
        ],
      ),
    );
  }

  /// "Sofia Martins" → "SM"; um só nome → a primeira letra.
  static String initialsOf(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first.characters.first;
    if (parts.length == 1) return first.toUpperCase();
    return (first + parts.last.characters.first).toUpperCase();
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric});

  final AppProfileMetric metric;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Column(
        children: [
          Text(
            metric.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleLarge?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            metric.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
