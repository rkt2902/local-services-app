import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import 'app_motion.dart';

/// Skeleton genérico para o loading inicial de um ecrã — substitui um
/// `Center(child: CircularProgressIndicator())` solto nos ecrãs que hoje só
/// mostram um spinner enquanto o provider principal carrega
/// (docs/motion_spec.md §3, "Skeleton de loading": "usar sempre em vez de
/// spinner em listas e formulários").
///
/// Devolve só o conteúdo (sem `Scaffold` próprio) para caber tanto como
/// `body:` de um `Scaffold`/`AppBar` já existentes como dentro de um `.when`
/// que ainda não montou nenhum. Forma genérica (bloco de destaque + linhas),
/// não um layout pixel-a-pixel do conteúdo final de cada ecrã.
class AppScreenLoadingSkeleton extends StatelessWidget {
  const AppScreenLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSkeletonShimmer(
              child: Container(
                width: double.infinity,
                height: 120,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (var i = 0; i < 3; i++) ...[
              AppSkeletonShimmer(
                child: Container(
                  width: double.infinity,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}
