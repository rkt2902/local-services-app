import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status_color.dart';
import 'app_motion.dart';
import 'primary_action_button.dart';

/// Ecrã cheio para um estado de sistema (sem internet, erro genérico, etc.)
/// — genérico e reutilizável em qualquer parte da app, nada específico de
/// nenhum fluxo. Ícone + título + mensagem + botão primário obrigatório +
/// botão secundário opcional.
///
/// Os construtores nomeados [AppSystemStateScreen.noInternet] e
/// [AppSystemStateScreen.genericError] cobrem os 2 casos mais comuns com a
/// cópia e ícones já definidos; o construtor base fica disponível para
/// qualquer outro estado de sistema futuro.
class AppSystemStateScreen extends StatelessWidget {
  const AppSystemStateScreen({
    super.key,
    required this.icon,
    required this.iconBackground,
    required this.iconForeground,
    required this.title,
    required this.message,
    required this.primaryActionLabel,
    required this.onPrimaryAction,
    this.isPrimaryActionLoading = false,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  factory AppSystemStateScreen.noInternet({
    Key? key,
    required VoidCallback onRetry,
    bool isRetrying = false,
    String? message,
  }) =>
      AppSystemStateScreen(
        key: key,
        icon: Icons.wifi_off_rounded,
        iconBackground: AppStatusColor.neutral.background,
        iconForeground: AppStatusColor.neutral.foreground,
        title: 'Sem ligação à internet',
        message: message ??
            'Verifica a tua ligação Wi-Fi ou dados móveis e tenta novamente.',
        primaryActionLabel: 'Tentar novamente',
        onPrimaryAction: onRetry,
        isPrimaryActionLoading: isRetrying,
      );

  factory AppSystemStateScreen.genericError({
    Key? key,
    required VoidCallback onRetry,
    bool isRetrying = false,
    String? message,
    String? secondaryActionLabel,
    VoidCallback? onSecondaryAction,
  }) =>
      AppSystemStateScreen(
        key: key,
        icon: Icons.error_outline_rounded,
        iconBackground: AppStatusColor.cancelled.background,
        iconForeground: AppStatusColor.cancelled.foreground,
        title: 'Algo correu mal',
        message: message ??
            'Não foi possível concluir a ação. Tenta novamente ou contacta o suporte.',
        primaryActionLabel: 'Tentar novamente',
        onPrimaryAction: onRetry,
        isPrimaryActionLoading: isRetrying,
        secondaryActionLabel: secondaryActionLabel ?? 'Contactar suporte',
        onSecondaryAction: onSecondaryAction,
      );

  final IconData icon;
  final Color iconBackground;
  final Color iconForeground;
  final String title;
  final String message;

  final String primaryActionLabel;
  final VoidCallback onPrimaryAction;
  final bool isPrimaryActionLoading;

  /// Ex.: "Contactar suporte". `null` = botão não aparece — o caller decide,
  /// este widget não assume que um canal de suporte existe.
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppStaggeredEntrance(
                        index: 0,
                        child: Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: iconBackground,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(icon, size: 34, color: iconForeground),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppStaggeredEntrance(
                        index: 1,
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: textTheme.titleLarge
                              ?.copyWith(color: AppColors.textPrimary),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      AppStaggeredEntrance(
                        index: 2,
                        child: Text(
                          message,
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  PrimaryActionButton(
                    label: primaryActionLabel,
                    isLoading: isPrimaryActionLoading,
                    onPressed: isPrimaryActionLoading ? null : onPrimaryAction,
                  ),
                  if (secondaryActionLabel != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    TextButton(
                      onPressed: onSecondaryAction,
                      child: Text(
                        secondaryActionLabel!,
                        style: textTheme.bodyMedium?.copyWith(
                          color: onSecondaryAction == null
                              ? AppStatusColor.neutral.foreground
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
