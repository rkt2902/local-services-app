import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/password_policy.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_password_strength_meter.dart';
import '../../../core/widgets/app_system_state_screen.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../application/password_reset_controller.dart';

/// Passo 3 do fluxo de recuperação (dentro da rota `/forgot-password/reset`).
/// Depende da sessão de recuperação aberta no passo 2 — `updatePassword`
/// falha (ou é simulado, no bypass de dev) se essa sessão não existir.
class NewPasswordScreen extends ConsumerStatefulWidget {
  const NewPasswordScreen({super.key, required this.onUpdated});

  final VoidCallback onUpdated;

  @override
  ConsumerState<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends ConsumerState<NewPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _passwordVisible = false;
  bool _confirmVisible = false;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_onFieldChanged);
    _confirmController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() => setState(() {});

  @override
  void dispose() {
    _passwordController.removeListener(_onFieldChanged);
    _confirmController.removeListener(_onFieldChanged);
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _passwordsMatch =>
      _confirmController.text.isNotEmpty && _passwordController.text == _confirmController.text;

  void _submit() {
    final resetState = ref.read(passwordResetControllerProvider);
    final policy = evaluatePasswordPolicy(_passwordController.text);
    if (!policy.meetsAllRules || !_passwordsMatch || resetState is PasswordResetLoading) {
      return;
    }
    ref.read(passwordResetControllerProvider.notifier).updatePassword(_passwordController.text);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final resetState = ref.watch(passwordResetControllerProvider);
    final isSubmitting = resetState is PasswordResetLoading;

    ref.listen<PasswordResetState>(passwordResetControllerProvider, (prev, next) {
      if (next is PasswordResetSuccess) widget.onUpdated();
    });

    if (resetState is PasswordResetError && resetState.kind == PasswordResetErrorKind.network) {
      return AppSystemStateScreen.noInternet(onRetry: _submit);
    }

    // Ao contrário do passo 2, erros "unexpected" (ex.: same_password,
    // weak_password — os que updateUser realmente devolve) ficam inline:
    // são feedback de formulário, não falhas de infraestrutura. Part 5 só
    // pediu full-screen para requestPasswordReset/verifyPasswordResetOtp.
    final inlineError = resetState is PasswordResetError ? resetState.message : null;

    final policy = evaluatePasswordPolicy(_passwordController.text);
    final showMismatch = _confirmController.text.isNotEmpty && !_passwordsMatch;
    final canSubmit = policy.meetsAllRules && _passwordsMatch && !isSubmitting;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const _Header(title: 'Nova senha'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppStaggeredEntrance(
                      index: 0,
                      child: Text(
                        'Crie uma nova senha para a sua conta.',
                        style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 1,
                      child: AppTextField(
                        controller: _passwordController,
                        label: 'Nova senha',
                        obscureText: !_passwordVisible,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.newPassword],
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                          icon: Icon(
                            _passwordVisible
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppStaggeredEntrance(
                      index: 2,
                      child: AppTextField(
                        controller: _confirmController,
                        label: 'Confirmar senha',
                        obscureText: !_confirmVisible,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.newPassword],
                        onFieldSubmitted: (_) => _submit(),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _confirmVisible = !_confirmVisible),
                          icon: Icon(
                            _confirmVisible
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    if (showMismatch) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        'As senhas não coincidem.',
                        style: textTheme.labelMedium
                            ?.copyWith(color: AppStatusColor.cancelled.foreground),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 3,
                      child: AppPasswordStrengthMeter(password: _passwordController.text),
                    ),
                    if (inlineError != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: AppStatusColor.cancelled.background,
                          borderRadius: BorderRadius.circular(AppRadius.input),
                        ),
                        child: Text(
                          inlineError,
                          style: textTheme.bodyMedium
                              ?.copyWith(color: AppStatusColor.cancelled.foreground),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.all(AppSpacing.md),
              child: PrimaryActionButton(
                label: 'Guardar nova senha',
                isLoading: isSubmitting,
                onPressed: canSubmit ? _submit : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      // Sem seta de voltar: uma vez consumido o código no passo 2, não há
      // para onde recuar (a sessão de recuperação é de utilização única).
      child: Text(title, style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary)),
    );
  }
}
