import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_links.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_support_sheet.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../application/session_provider.dart';
import 'delete_account_flow.dart';
import 'sign_out_flow.dart';

/// Rota `/account-suspended` (0080): o suporte suspendeu a conta. O router
/// manda para aqui qualquer rota enquanto a sessão disser `suspended`; a
/// base de dados recusa pedidos, propostas e ajudas desta conta.
///
/// Fica sempre a saída: contactar o suporte (contestar, Termos 11.2),
/// terminar sessão e eliminar a conta (RGPD; a 0080 deixa-a correr mesmo
/// suspensa).
class AccountSuspendedScreen extends ConsumerWidget {
  const AccountSuspendedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionStatusProvider);
    final message = session.value?.suspendedMessage;
    return AccountSuspendedView(
      supportMessage: message,
      isChecking: session.isLoading,
      onContactSupport: () => showSupportContactSheet(context),
      onCheckAgain: () => ref.read(sessionStatusProvider.notifier).refresh(),
      onSignOut: () => confirmAndSignOut(context, ref),
      onDeleteAccount: () => confirmAndDeleteAccount(context, ref),
    );
  }
}

class AccountSuspendedView extends StatelessWidget {
  const AccountSuspendedView({
    required this.supportMessage,
    required this.isChecking,
    required this.onContactSupport,
    required this.onCheckAgain,
    required this.onSignOut,
    required this.onDeleteAccount,
    super.key,
  });

  /// O que o suporte escreveu ao suspender, se escreveu.
  final String? supportMessage;
  final bool isChecking;
  final VoidCallback onContactSupport;
  final VoidCallback onCheckAgain;
  final VoidCallback onSignOut;
  final VoidCallback onDeleteAccount;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const tone = AppStatusColor.cancelled;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppStaggeredEntrance(
                        index: 0,
                        child: Container(
                          width: AppSizes.emptyIconCircle,
                          height: AppSizes.emptyIconCircle,
                          decoration: BoxDecoration(
                            color: tone.background,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.block_rounded,
                            size: AppSizes.emptyIcon,
                            color: tone.foreground,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppStaggeredEntrance(
                        index: 1,
                        child: Text(
                          'Conta suspensa',
                          textAlign: TextAlign.center,
                          style: textTheme.titleLarge?.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      AppStaggeredEntrance(
                        index: 2,
                        child: Text(
                          supportMessage ??
                              'O suporte da ProJardim suspendeu a tua conta.',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyLarge?.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppStaggeredEntrance(
                        index: 3,
                        child: Text(
                          'Enquanto estiver suspensa não podes pedir nem '
                          'propor trabalhos. Se achas que é um engano, '
                          'escreve para ${AppLinks.supportEmail} nos '
                          'próximos 6 meses e explica o que aconteceu. '
                          'Respondemos por email.',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
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
                    label: 'Contactar suporte',
                    onPressed: onContactSupport,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: AppSpacing.xs,
                    children: [
                      TextButton(
                        onPressed: isChecking ? null : onCheckAgain,
                        child: const Text('Verificar de novo'),
                      ),
                      TextButton(
                        onPressed: onSignOut,
                        child: const Text('Terminar sessão'),
                      ),
                      TextButton(
                        onPressed: onDeleteAccount,
                        style: TextButton.styleFrom(
                          foregroundColor: tone.foreground,
                        ),
                        child: const Text('Eliminar conta'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
