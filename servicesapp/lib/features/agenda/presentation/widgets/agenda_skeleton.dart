import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_motion.dart';

/// Esqueleto da Agenda (A9), com brilho; nunca spinner. [compact] imita a
/// linha de 52 px da Semana e do Mês, senão o cartão completo do Hoje.
class AgendaEntrySkeleton extends StatelessWidget {
  const AgendaEntrySkeleton({this.compact = false, super.key});

  final bool compact;

  static const double _fullHeight = 104;
  static const double _compactHeight = 52;

  @override
  Widget build(BuildContext context) {
    Widget bar(double height, {double? width}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.agendaNeutralSurface,
        borderRadius: BorderRadius.circular(AppSpacing.s6),
      ),
    );

    final content = compact
        ? Row(
            children: [
              bar(12, width: 40),
              const SizedBox(width: AppSpacing.s10),
              Expanded(child: bar(12)),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 44,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(16),
                    const SizedBox(height: AppSpacing.s6),
                    bar(11, width: 30),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                width: AppSizes.rowIconBox,
                height: AppSizes.rowIconBox,
                decoration: BoxDecoration(
                  color: AppColors.agendaNeutralSurface,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FractionallySizedBox(widthFactor: 0.7, child: bar(14)),
                    const SizedBox(height: AppSpacing.xs),
                    FractionallySizedBox(widthFactor: 0.5, child: bar(11)),
                    const SizedBox(height: AppSpacing.xs),
                    bar(22, width: 76),
                  ],
                ),
              ),
            ],
          );

    return Semantics(
      label: 'A carregar',
      child: Container(
        height: compact ? _compactHeight : _fullHeight,
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.s14,
          vertical: compact ? 0 : AppSpacing.s14,
        ),
        alignment: compact ? Alignment.centerLeft : null,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(
            compact ? AppRadius.input : AppRadius.card,
          ),
          border: Border.all(color: AppColors.divider),
        ),
        // O brilho passa só pelas barras; o cartão fica branco.
        child: AppSkeletonShimmer(child: content),
      ),
    );
  }
}
