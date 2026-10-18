import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion_tokens.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_otp_input.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../application/auth_providers.dart';
import '../application/session_provider.dart';
import '../data/auth_repository.dart';

/// Confirmação de email por código de 6 dígitos.
///
/// Só aparece quando "Confirm email" está ligado no Supabase: o registo
/// (`signup_screen.dart`) ou o login de uma conta por confirmar
/// (`login_screen.dart`) trazem o utilizador para aqui, sem sessão. O
/// código vem no email "Confirm signup" (template com `{{ .Token }}`, ver
/// docs/SETUP.md). `verifyOTP` abre a sessão e o router leva a
/// `/choose-role`, onde o perfil é criado. Mesmo padrão do código da
/// recuperação de senha (`verify_reset_code_screen.dart`), sem deep links.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, required this.email});

  final String email;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  static const _codeLength = 6;
  static const _cooldownSeconds = 60;

  Timer? _cooldownTimer;
  int _secondsLeft = _cooldownSeconds;
  int _otpInstanceKey = 0;
  String _code = '';
  bool _verifying = false;
  bool _resending = false;
  String? _error;
  bool _invalidCode = false;

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

  Future<void> _resend() async {
    if (_secondsLeft > 0 || _resending) return;
    setState(() => _resending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authRepositoryProvider).resendSignupConfirmation(widget.email);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Código reenviado.')));
      setState(() {
        _otpInstanceKey++;
        _code = '';
        _error = null;
        _invalidCode = false;
      });
      _startCooldown();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(_messageFor(e)),
        backgroundColor: AppStatusColor.cancelled.foreground,
      ));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _confirm() async {
    if (_code.length != _codeLength || _verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
      _invalidCode = false;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .verifySignupCode(email: widget.email, code: _code);
      if (!mounted) return;
      // Sessão aberta: o router manda para /choose-role (sem papel ainda).
      context.go('/choose-role');
      unawaited(ref.read(sessionStatusProvider.notifier).refresh());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = _messageFor(e);
        _invalidCode = e is AuthException &&
            e.code == PasswordResetErrorCode.invalidCode;
      });
    }
  }

  String _messageFor(Object e) {
    if (e is AuthException) return e.message;
    return 'Ocorreu um erro. Tenta novamente.';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
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
                    onPressed: () => context.go('/login'),
                    tooltip: 'Voltar',
                    icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    'Confirmar email',
                    style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  children: [
                    const SizedBox(height: AppSpacing.sm),
                    AppStaggeredEntrance(index: 0, child: _EmailWaitingIcon()),
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 1,
                      child: Text(
                        'Confirma o teu email',
                        textAlign: TextAlign.center,
                        style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppStaggeredEntrance(
                      index: 2,
                      child: Text(
                        'Enviámos um código de $_codeLength dígitos para',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    AppStaggeredEntrance(
                      index: 3,
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
                      index: 4,
                      child: AppOtpInput(
                        key: ValueKey(_otpInstanceKey),
                        length: _codeLength,
                        enabled: !_verifying,
                        hasError: _invalidCode,
                        onChanged: (value) => setState(() => _code = value),
                        onCompleted: (value) => setState(() => _code = value),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppStaggeredEntrance(
                      index: 5,
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.center,
                        children: [
                          Text(
                            'Não recebeste? Vê também o spam. ',
                            style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                          ),
                          TextButton(
                            onPressed: _secondsLeft <= 0 && !_resending ? _resend : null,
                            child: AppFadeThroughSwitcher(
                              switchKey: _resendLabel,
                              duration: AppMotionDuration.fast,
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
                    // Quem já tem conta não precisa de ficar preso aqui.
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.center,
                      children: [
                        Text(
                          'Já tens conta?',
                          style: textTheme.bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                        TextButton(
                          onPressed: () => context.go('/login'),
                          child: Text(
                            'Entra ou recupera a senha.',
                            style: textTheme.bodyMedium?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: AppStatusColor.cancelled.background,
                          borderRadius: BorderRadius.circular(AppRadius.input),
                        ),
                        child: Text(
                          _error!,
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
                isLoading: _verifying,
                onPressed: _code.length == _codeLength && !_verifying ? _confirm : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmailWaitingIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: const BoxDecoration(color: AppColors.primaryContainer, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: const Icon(Icons.mark_email_unread_outlined, color: AppColors.primary, size: 42),
    );
  }
}
