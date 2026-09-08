import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_system_state_screen.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../application/password_reset_controller.dart';

/// Rota `/forgot-password/request` — passo 1 do fluxo de recuperação.
/// Pede o email e chama `resetPasswordForEmail`. Por desenho anti-enumeração
/// (ver `PasswordResetController.requestReset`), avança sempre para o passo
/// seguinte, exceto quando o pedido falha mesmo por falta de rede.
class RequestPasswordResetScreen extends ConsumerStatefulWidget {
  const RequestPasswordResetScreen({super.key, this.prefilledEmail});

  final String? prefilledEmail;

  @override
  ConsumerState<RequestPasswordResetScreen> createState() =>
      _RequestPasswordResetScreenState();
}

class _RequestPasswordResetScreenState
    extends ConsumerState<RequestPasswordResetScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.prefilledEmail ?? '');
    // Estado limpo de propósito — este ecrã pode ser reaberto depois de um
    // pedido anterior (ex.: o utilizador voltou atrás a partir do passo 2).
    Future.microtask(
      () => ref.read(passwordResetControllerProvider.notifier).reset(),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Introduza o email.';
    if (!text.contains('@')) return 'Email inválido.';
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    ref
        .read(passwordResetControllerProvider.notifier)
        .requestReset(_emailController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final resetState = ref.watch(passwordResetControllerProvider);
    final isSubmitting = resetState is PasswordResetLoading;

    ref.listen<PasswordResetState>(passwordResetControllerProvider, (prev, next) {
      if (next is PasswordResetSuccess) {
        final email = _emailController.text.trim();
        context.push('/forgot-password/reset?email=${Uri.encodeComponent(email)}');
      }
    });

    if (resetState is PasswordResetError) {
      return resetState.kind == PasswordResetErrorKind.network
          ? AppSystemStateScreen.noInternet(onRetry: _submit)
          : AppSystemStateScreen.genericError(onRetry: _submit);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(title: 'Recuperar senha', onBack: () => context.pop()),
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    children: [
                      AppStaggeredEntrance(
                        index: 0,
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            borderRadius: BorderRadius.circular(AppRadius.card),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.lock_reset_rounded, color: AppColors.primary),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppStaggeredEntrance(
                        index: 1,
                        child: Text(
                          'Esqueceu-se da senha?',
                          textAlign: TextAlign.center,
                          style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      AppStaggeredEntrance(
                        index: 2,
                        child: Text(
                          'Indique o email da sua conta. Se estiver registado, '
                          'enviamos um código para confirmar.',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppStaggeredEntrance(
                        index: 3,
                        child: AppTextField(
                          controller: _emailController,
                          label: 'Email',
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.email],
                          validator: _validateEmail,
                          onFieldSubmitted: (_) => _submit(),
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
              child: PrimaryActionButton(
                label: 'Enviar código',
                isLoading: isSubmitting,
                onPressed: isSubmitting ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Text(title, style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}
