import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion_tokens.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_sizes.dart';
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

  /// "0:42" enquanto o reenvio está bloqueado.
  String get _cooldownLabel =>
      '${_secondsLeft ~/ 60}:${(_secondsLeft % 60).toString().padLeft(2, '0')}';

  Future<void> _resend() async {
    if (_secondsLeft > 0 || _resending) return;
    setState(() => _resending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(authRepositoryProvider)
          .resendSignupConfirmation(widget.email);
      if (!mounted) return;
      messenger
          .showSnackBar(const SnackBar(content: Text('Código reenviado.')));
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
        _invalidCode =
            e is AuthException && e.code == PasswordResetErrorCode.invalidCode;
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
    final secondary = textTheme.bodyMedium?.copyWith(
      color: AppColors.textSecondary,
    );
    final smallSecondary = textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondary,
    );
    final smallLink = textTheme.bodySmall?.copyWith(
      color: AppColors.primaryPressed,
      fontWeight: FontWeight.w700,
    );
    const compactLink = ButtonStyle(
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      ),
      minimumSize: WidgetStatePropertyAll(Size.zero),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xs,
                AppSpacing.xs,
                AppSpacing.md,
                0,
              ),
              child: IconButton(
                onPressed: _verifying ? null : () => context.go('/login'),
                tooltip: 'Voltar',
                icon: const Icon(
                  Icons.arrow_back,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppStaggeredEntrance(
                      index: 0,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _EmailWaitingIcon(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppStaggeredEntrance(
                      index: 1,
                      child: Text(
                        'Confirma o teu email',
                        style: textTheme.displaySmall?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppStaggeredEntrance(
                      index: 2,
                      child: Text.rich(
                        TextSpan(
                          style: secondary,
                          children: [
                            const TextSpan(
                              text:
                                  'Enviámos um código de $_codeLength dígitos para ',
                            ),
                            TextSpan(
                              text: widget.email,
                              style: textTheme.bodyMedium?.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppStaggeredEntrance(
                      index: 3,
                      child: AppOtpInput(
                        key: ValueKey(_otpInstanceKey),
                        length: _codeLength,
                        enabled: !_verifying,
                        hasError: _invalidCode,
                        onChanged: (value) => setState(() {
                          _code = value;
                          _error = null;
                          _invalidCode = false;
                        }),
                        onCompleted: (value) => setState(() => _code = value),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Container(
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
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 4,
                      child: PrimaryActionButton(
                        label: 'Confirmar',
                        isLoading: _verifying,
                        onPressed: _code.length == _codeLength && !_verifying
                            ? _confirm
                            : null,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppStaggeredEntrance(
                      index: 5,
                      child: Column(
                        children: [
                          AppFadeThroughSwitcher(
                            switchKey: _secondsLeft > 0,
                            duration: AppMotionDuration.fast,
                            child: _secondsLeft > 0
                                ? Padding(
                                    key: const ValueKey('resend_wait'),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: AppSpacing.xs,
                                    ),
                                    child: Text.rich(
                                      TextSpan(
                                        style: secondary,
                                        children: [
                                          const TextSpan(text: 'Reenviar em '),
                                          TextSpan(
                                            text: _cooldownLabel,
                                            style:
                                                textTheme.bodyMedium?.copyWith(
                                              color: AppColors.textPrimary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : TextButton(
                                    key: const ValueKey('resend_ready'),
                                    onPressed: _resending || _verifying
                                        ? null
                                        : _resend,
                                    child: Text(
                                      _resending
                                          ? 'A reenviar...'
                                          : 'Reenviar código',
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: AppColors.primaryPressed,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            'Não recebeste? Vê também o spam.',
                            textAlign: TextAlign.center,
                            style: smallSecondary,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Quem já tem conta não precisa de ficar preso aqui.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                ),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Já tens conta com este email?',
                        style: smallSecondary),
                    TextButton(
                      style: compactLink,
                      onPressed: _verifying ? null : () => context.go('/login'),
                      child: Text('Entra', style: smallLink),
                    ),
                    Text('ou', style: smallSecondary),
                    TextButton(
                      style: compactLink,
                      onPressed: _verifying
                          ? null
                          : () => context.go(
                                '/forgot-password/request'
                                '?email=${Uri.encodeComponent(widget.email)}',
                              ),
                      child: Text('recupera a senha', style: smallLink),
                    ),
                    Text('.', style: smallSecondary),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmailWaitingIcon extends StatelessWidget {
  const _EmailWaitingIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSizes.authHeaderIcon,
      height: AppSizes.authHeaderIcon,
      decoration: const BoxDecoration(
        color: AppColors.primaryContainer,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.mark_email_unread_outlined,
        color: AppColors.primary,
        size: AppSizes.authHeaderGlyph,
      ),
    );
  }
}
