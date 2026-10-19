import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_sizes.dart';
import '../theme/app_spacing.dart';
import 'app_motion.dart';
import 'primary_action_button.dart';

/// Folha genérica do design (U1): pega, título com fechar, conteúdo e
/// ação principal em baixo (opcional), mais uma ação secundária em texto
/// (ex.: "Agora não"). Respeita o teclado e faz scroll do conteúdo.
///
/// O widget não navega: [onClose] e as ações decidem. Abrir com [show],
/// que já põe o fundo, os cantos e o `isScrollControlled` certos.
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.title,
    required this.child,
    required this.onClose,
    this.primaryActionLabel,
    this.primaryActionIcon,
    this.onPrimaryAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.isSubmitting = false,
  });

  final String title;
  final Widget child;
  final VoidCallback onClose;
  final String? primaryActionLabel;
  final IconData? primaryActionIcon;
  final VoidCallback? onPrimaryAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  /// Bloqueia fechar e a ação secundária; a principal mostra o loading.
  final bool isSubmitting;

  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool isDismissible = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: isDismissible,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: builder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final primaryLabel = primaryActionLabel;
    final secondaryLabel = secondaryActionLabel;

    return PopScope(
      canPop: !isSubmitting,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s20,
              AppSpacing.xs,
              AppSpacing.s20,
              AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: AppSizes.sheetHandleWidth,
                    height: AppSizes.sheetHandleHeight,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: textTheme.titleLarge
                            ?.copyWith(color: AppColors.textPrimary),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fechar',
                      onPressed: isSubmitting ? null : onClose,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Flexible(
                  child: SingleChildScrollView(
                    child: AppStaggeredEntrance(index: 0, child: child),
                  ),
                ),
                if (primaryLabel != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  AppStaggeredEntrance(
                    index: 1,
                    child: PrimaryActionButton(
                      label: primaryLabel,
                      icon: primaryActionIcon,
                      isLoading: isSubmitting,
                      onPressed: isSubmitting ? null : onPrimaryAction,
                    ),
                  ),
                ],
                if (secondaryLabel != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(
                    onPressed: isSubmitting ? null : onSecondaryAction,
                    child: Text(secondaryLabel),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
