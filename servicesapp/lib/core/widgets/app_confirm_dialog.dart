import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_sizes.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status_color.dart';
import 'app_motion.dart';
import 'primary_action_button.dart';

/// Diálogo de confirmação do design (U1): ícone numa caixa, título,
/// texto e dois botões lado a lado ("Voltar" + ação). Duas variantes:
/// normal (verde) e perigo ([destructive], vermelho), para ações que tiram
/// alguma coisa a alguém (cancelar, retirar, desistir, sair).
///
/// O widget não navega nem chama o backend: [onConfirm]/[onCancel] decidem.
/// Para o caso simples (perguntar e seguir) usar [show], que devolve
/// `true` (confirmou), `false` ("Voltar") ou `null` (fechou por fora).
/// Quando a ação corre dentro do diálogo (ex.: eliminar conta), usar o
/// widget num `StatefulWidget` próprio com [isSubmitting] e [errorText].
class AppConfirmDialog extends StatelessWidget {
  const AppConfirmDialog({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onCancel,
    this.cancelLabel = 'Voltar',
    this.destructive = false,
    this.isSubmitting = false,
    this.details,
    this.errorText,
  });

  final IconData icon;
  final String title;

  /// Texto por baixo do título; `null` quando o [details] chega (ex.: o
  /// seletor de "Alterar vagas").
  final String? message;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool destructive;

  /// Bloqueia os dois botões e o "voltar" do sistema enquanto a ação corre.
  final bool isSubmitting;

  /// Conteúdo extra por baixo do texto (ex.: lista do que acontece).
  final Widget? details;

  /// Erro do servidor mostrado dentro do diálogo, por cima dos botões.
  final String? errorText;

  static Future<bool?> show(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
    required String confirmLabel,
    String cancelLabel = 'Voltar',
    bool destructive = false,
    Widget? details,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AppConfirmDialog(
        icon: icon,
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        destructive: destructive,
        details: details,
        onConfirm: () => Navigator.pop(dialogCtx, true),
        onCancel: () => Navigator.pop(dialogCtx, false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tone =
        destructive ? AppStatusColor.cancelled : AppStatusColor.success;
    final error = errorText;

    return PopScope(
      canPop: !isSubmitting,
      child: Dialog(
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.dialogMaxWidth),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppStaggeredEntrance(
                  index: 0,
                  child: Container(
                    width: AppSizes.dialogIconBox,
                    height: AppSizes.dialogIconBox,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tone.background,
                      borderRadius: BorderRadius.circular(AppRadius.input),
                    ),
                    child: Icon(
                      icon,
                      color: tone.foreground,
                      size: AppSizes.dialogIcon,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppStaggeredEntrance(
                  index: 1,
                  child: Text(
                    title,
                    style: textTheme.titleLarge
                        ?.copyWith(color: AppColors.textPrimary),
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  AppStaggeredEntrance(
                    index: 2,
                    child: Text(
                      message!,
                      style: textTheme.bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
                if (details != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppStaggeredEntrance(index: 3, child: details!),
                ],
                if (error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    error,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppStatusColor.cancelled.foreground,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                AppStaggeredEntrance(
                  index: 4,
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isSubmitting ? null : onCancel,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(
                              AppSizes.compactButtonHeight,
                            ),
                            foregroundColor: AppColors.textPrimary,
                            side: const BorderSide(color: AppColors.divider),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.input),
                            ),
                            textStyle: textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          child: Text(cancelLabel),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: destructive
                            ? _DestructiveButton(
                                label: confirmLabel,
                                isSubmitting: isSubmitting,
                                onPressed: onConfirm,
                              )
                            : PrimaryActionButton(
                                label: confirmLabel,
                                height: AppSizes.compactButtonHeight,
                                isLoading: isSubmitting,
                                onPressed: isSubmitting ? null : onConfirm,
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DestructiveButton extends StatelessWidget {
  const _DestructiveButton({
    required this.label,
    required this.isSubmitting,
    required this.onPressed,
  });

  final String label;
  final bool isSubmitting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final danger = AppStatusColor.cancelled.foreground;
    return FilledButton(
      onPressed: isSubmitting ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: danger,
        foregroundColor: AppColors.surface,
        disabledBackgroundColor: AppStatusColor.cancelled.background,
        minimumSize: const Size.fromHeight(AppSizes.compactButtonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        textStyle: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      child: isSubmitting
          ? SizedBox.square(
              dimension: AppSpacing.md,
              child: CircularProgressIndicator(strokeWidth: 2, color: danger),
            )
          : Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
