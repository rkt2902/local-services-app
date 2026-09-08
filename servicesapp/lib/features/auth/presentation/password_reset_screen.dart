import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_motion.dart';
import '../application/auth_controller.dart';
import '../application/password_reset_controller.dart';
import 'new_password_screen.dart';
import 'password_changed_screen.dart';
import 'verify_reset_code_screen.dart';

enum _ResetStep { verifyCode, newPassword, success }

/// Rota `/forgot-password/reset` — contentor único para os passos 2–4 do
/// fluxo de recuperação (verificar código → nova senha → confirmação).
///
/// Só há 2 rotas no router para este fluxo (Part 3): esta e
/// `/forgot-password/request`. Os passos 2–4 trocam-se internamente, sem
/// navegação — decisão deliberada: depois de `verifyOTP` (passo 2) o
/// Supabase autentica mesmo a sessão (recovery session), e ficar na mesma
/// rota evita reavaliar o guard de `RouterNotifier.redirect` a meio do
/// preenchimento da nova senha.
class PasswordResetScreen extends ConsumerStatefulWidget {
  const PasswordResetScreen({super.key, required this.email});

  final String email;

  @override
  ConsumerState<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends ConsumerState<PasswordResetScreen> {
  _ResetStep _step = _ResetStep.verifyCode;

  Future<void> _goToLogin() async {
    // Limpa a sessão de recuperação (temporária) e o estado do controller
    // antes de voltar ao login — o utilizador deve entrar com a senha nova
    // pelo fluxo normal, não continuar "autenticado" pela sessão de reset.
    await ref.read(authControllerProvider.notifier).signOut();
    ref.read(passwordResetControllerProvider.notifier).reset();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    // Lido, não observado: o valor só importa quando se chega ao passo
    // `success`, e nessa altura `verifyOtp` (passo 2) já o deixou estável.
    final isDevBypass = ref.read(passwordResetControllerProvider.notifier).isDevBypassActive;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AppFadeThroughSwitcher(
        switchKey: _step,
        child: switch (_step) {
          _ResetStep.verifyCode => VerifyResetCodeScreen(
              key: const ValueKey('verify'),
              email: widget.email,
              onBack: () => context.pop(),
              onVerified: () => setState(() => _step = _ResetStep.newPassword),
            ),
          _ResetStep.newPassword => NewPasswordScreen(
              key: const ValueKey('new-password'),
              onUpdated: () => setState(() => _step = _ResetStep.success),
            ),
          _ResetStep.success => PasswordChangedScreen(
              key: const ValueKey('success'),
              onGoToLogin: _goToLogin,
              showDevBypassWarning: isDevBypass,
            ),
        },
      ),
    );
  }
}
