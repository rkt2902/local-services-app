import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/primary_action_button.dart';

/// Passo 4 (final) do fluxo de recuperação — só deve ser mostrado depois da
/// confirmação real do backend de que a senha foi alterada (ou do bypass
/// de dev, sinalizado via [showDevBypassWarning]). Sem AppBar/seta de
/// voltar — este é o estado final, o único caminho é "Ir para o login".
class PasswordChangedScreen extends StatelessWidget {
  const PasswordChangedScreen({
    super.key,
    required this.onGoToLogin,
    this.showDevBypassWarning = false,
  });

  final VoidCallback onGoToLogin;

  /// `true` quando o passo 2 usou o bypass de `kDebugMode` — a senha NÃO foi
  /// realmente alterada (sem sessão de recuperação real). Só pode ser
  /// `true` em debug; em release fica sempre `false`.
  final bool showDevBypassWarning;

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
                            color: AppStatusColor.success.background,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.check_circle_outline_rounded,
                            color: AppStatusColor.success.foreground,
                            size: 36,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppStaggeredEntrance(
                        index: 1,
                        child: Text(
                          'Senha alterada!',
                          textAlign: TextAlign.center,
                          style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      AppStaggeredEntrance(
                        index: 2,
                        child: Text(
                          'A sua senha foi atualizada com sucesso. Já pode entrar.',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                      if (showDevBypassWarning) ...[
                        const SizedBox(height: AppSpacing.md),
                        AppStaggeredEntrance(
                          index: 3,
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: AppStatusColor.waiting.background,
                              borderRadius: BorderRadius.circular(AppRadius.input),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.bug_report_outlined,
                                    color: AppStatusColor.waiting.foreground, size: 20),
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(
                                  child: Text(
                                    'DEV BYPASS — a senha NÃO foi alterada de facto. '
                                    'Só o ecrã foi simulado (sem sessão de recuperação real).',
                                    style: textTheme.labelMedium
                                        ?.copyWith(color: AppStatusColor.waiting.foreground),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.all(AppSpacing.md),
              child: PrimaryActionButton(label: 'Ir para o login', onPressed: onGoToLogin),
            ),
          ],
        ),
      ),
    );
  }
}
