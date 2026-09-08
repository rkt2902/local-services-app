import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_otp_input.dart';
import '../../../core/widgets/app_system_state_screen.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../application/password_reset_controller.dart';

/// Passo 2 do fluxo de recuperação (dentro da rota `/forgot-password/reset`,
/// ver `password_reset_screen.dart`) — código OTP + reenvio com cooldown.
class VerifyResetCodeScreen extends ConsumerStatefulWidget {
  const VerifyResetCodeScreen({
    super.key,
    required this.email,
    required this.onBack,
    required this.onVerified,
  });

  final String email;
  final VoidCallback onBack;
  final VoidCallback onVerified;

  @override
  ConsumerState<VerifyResetCodeScreen> createState() => _VerifyResetCodeScreenState();
}

class _VerifyResetCodeScreenState extends ConsumerState<VerifyResetCodeScreen> {
  static const _codeLength = 6;
  static const _cooldownSeconds = 60;

  Timer? _cooldownTimer;
  int _secondsLeft = _cooldownSeconds;
  int _otpInstanceKey = 0;
  String _code = '';

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _secondsLeft = _cooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft -= 1);
      }
    });
  }

  String get _resendLabel => _secondsLeft > 0
      ? 'Reenviar em 0:${_secondsLeft.toString().padLeft(2, '0')}'
      : 'Reenviar código';

  /// Reenvio não passa pelo `state` partilhado do controller (esse decide
  /// a transição de passo do wizard, via `PasswordResetSuccess` — misturar
  /// os dois faria um reenvio avançar o utilizador para o passo 3 por
  /// engano). Usa `resendCode`, que devolve/lança diretamente.
  Future<void> _resend() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(passwordResetControllerProvider.notifier).resendCode(widget.email);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Código reenviado.')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(describePasswordResetError(e)),
        backgroundColor: Colors.red,
      ));
    }
    if (!mounted) return;
    setState(() {
      _otpInstanceKey++;
      _code = '';
    });
    _startCooldown();
  }

  void _handleOtpChanged(String value) => setState(() => _code = value);

  void _confirm() {
    final resetState = ref.read(passwordResetControllerProvider);
    if (_code.length != _codeLength || resetState is PasswordResetLoading) return;
    ref.read(passwordResetControllerProvider.notifier).verifyOtp(
          email: widget.email,
          code: _code,
        );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final resetState = ref.watch(passwordResetControllerProvider);
    final isSubmitting = resetState is PasswordResetLoading;

    ref.listen<PasswordResetState>(passwordResetControllerProvider, (prev, next) {
      if (next is PasswordResetSuccess) widget.onVerified();
    });

    if (resetState is PasswordResetError &&
        resetState.kind != PasswordResetErrorKind.invalidCode) {
      return resetState.kind == PasswordResetErrorKind.network
          ? AppSystemStateScreen.noInternet(onRetry: _confirm)
          : AppSystemStateScreen.genericError(onRetry: _confirm);
    }

    final inlineError =
        resetState is PasswordResetError && resetState.kind == PasswordResetErrorKind.invalidCode
            ? resetState.message
            : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(title: 'Verificar código', onBack: widget.onBack),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  children: [
                    AppStaggeredEntrance(
                      index: 0,
                      child: Text(
                        'Introduza o código',
                        style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppStaggeredEntrance(
                      index: 1,
                      child: Text(
                        'Enviámos um código de $_codeLength dígitos para',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    AppStaggeredEntrance(
                      index: 2,
                      child: Text(
                        widget.email,
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppStaggeredEntrance(
                      index: 3,
                      child: AppOtpInput(
                        key: ValueKey(_otpInstanceKey),
                        length: _codeLength,
                        enabled: !isSubmitting,
                        hasError: inlineError != null,
                        onChanged: _handleOtpChanged,
                        onCompleted: _handleOtpChanged,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppStaggeredEntrance(
                      index: 4,
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.center,
                        children: [
                          Text(
                            'Não recebeu? ',
                            style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                          ),
                          TextButton(
                            onPressed: _secondsLeft <= 0 ? _resend : null,
                            child: AppFadeThroughSwitcher(
                              switchKey: _resendLabel,
                              duration: const Duration(milliseconds: 180),
                              child: Text(
                                _resendLabel,
                                key: ValueKey(_resendLabel),
                                style: textTheme.bodyMedium?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
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
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppStatusColor.cancelled.foreground,
                          ),
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
                label: 'Confirmar',
                isLoading: isSubmitting,
                onPressed: _code.length == _codeLength && !isSubmitting ? _confirm : null,
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
          Text(title, style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
