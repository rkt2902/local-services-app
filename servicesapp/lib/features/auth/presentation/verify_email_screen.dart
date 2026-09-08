// ============================================================
// PREPARAÇÃO — "Confirm email" está DESATIVADO no dashboard do Supabase
// (ver decisions_log.md, 2026-06-05: "Confirmação de email Supabase
// desativada para MVP — reativar antes do launch."). Este ecrã existe
// para esse dia, mas hoje é cosmético: o utilizador chega aqui já com
// sessão ativa (signUp + createProfile já correram) e consegue sempre
// saltar diretamente para /login sem confirmar nada — ver
// choose_role_screen.dart e o botão "Já confirmei — entrar" abaixo.
//
// O que falta para ativar a sério (nenhuma destas 6 coisas está feita):
//   1. Dashboard → Authentication → Providers → Email → ligar "Confirm
//      email".
//   2. Dashboard → Authentication → Email Templates → "Confirm signup" —
//      garantir que o link de redirect aponta para /email-confirmed com
//      os parâmetros certos (ver TODO em email_confirmed_screen.dart
//      sobre token_hash vs. token — não confirmado ao vivo, é o padrão
//      documentado do Supabase, não testado neste projeto).
//   3. Dashboard → Authentication → URL Configuration — registar o
//      Redirect URL da app (custom scheme ou universal/app link).
//   4. pubspec.yaml — adicionar app_links (ou uni_links). Não instalado.
//   5. android/app/src/main/AndroidManifest.xml — intent-filter com
//      android:scheme (ver TODO deixado no ficheiro).
//   6. ios/Runner/Info.plist — CFBundleURLTypes (ver TODO deixado no
//      ficheiro).
//
// O que já está feito e não precisa de mais nada: migration 0036 (ainda
// não aplicada) reforça profiles.id → auth.users(id) ON DELETE CASCADE e
// faz backfill de email_confirmed_at para todos os utilizadores já
// registados, para nenhum ficar preso no dia em que isto for ligado.
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../application/auth_providers.dart';
import '../application/email_confirmation_mode_provider.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, required this.email});

  final String email;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  static const _cooldownSeconds = 60;

  Timer? _cooldownTimer;
  int _secondsLeft = _cooldownSeconds;
  bool _resending = false;

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
      ? 'Pode reenviar em 0:${_secondsLeft.toString().padLeft(2, '0')}'
      : 'Já pode reenviar';

  Future<void> _resend() async {
    if (_secondsLeft > 0 || _resending) return;
    setState(() => _resending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authRepositoryProvider).resendSignupConfirmation(widget.email);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Email reenviado.')));
      _startCooldown();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(e is AuthException ? e.message : 'Ocorreu um erro. Tenta novamente.'),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isDevMode = ref.watch(emailConfirmationModeProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Column(
                  children: [
                    AppStaggeredEntrance(index: 0, child: _EmailWaitingIcon()),
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 1,
                      child: Text(
                        'Confirme o seu email',
                        textAlign: TextAlign.center,
                        style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppStaggeredEntrance(
                      index: 2,
                      child: Text(
                        'Enviámos um link de confirmação para',
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
                    AppStaggeredEntrance(index: 4, child: const _VerificationStepsCard()),
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 5,
                      child: _ResendStatusCard(label: _resendLabel),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Column(
                children: [
                  PrimaryActionButton(
                    label: _resending ? 'A reenviar...' : 'Reenviar email',
                    isLoading: _resending,
                    onPressed: (_secondsLeft > 0 || _resending) ? null : _resend,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: Text(
                      'Já confirmei — entrar',
                      style: textTheme.labelLarge?.copyWith(color: AppColors.primary),
                    ),
                  ),
                  // Só em kDebugMode (emailConfirmationModeProvider) — deixa
                  // testar o visual do passo seguinte sem SMTP configurado.
                  if (isDevMode) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    TextButton.icon(
                      onPressed: () => context.go(
                        '/email-confirmed?email=${Uri.encodeComponent(widget.email)}',
                      ),
                      icon: Icon(Icons.bug_report_outlined,
                          size: 16, color: AppColors.textSecondary),
                      label: Text(
                        'Simular confirmação (dev)',
                        style: textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
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

class _EmailWaitingIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: const BoxDecoration(color: AppColors.primaryContainer, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.mail_outline_rounded, color: AppColors.primary, size: 42),
          Positioned(
            right: -2,
            top: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerificationStepsCard extends StatelessWidget {
  const _VerificationStepsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: const Column(
        children: [
          _VerificationStep(numberLabel: '1', text: 'Abra o email que lhe enviámos.'),
          SizedBox(height: AppSpacing.sm),
          _VerificationStep(numberLabel: '2', text: 'Toque no link "Confirmar email".'),
          SizedBox(height: AppSpacing.sm),
          _VerificationStep(numberLabel: '3', text: 'Volte aqui para entrar na sua conta.'),
        ],
      ),
    );
  }
}

class _VerificationStep extends StatelessWidget {
  const _VerificationStep({required this.numberLabel, required this.text});

  final String numberLabel;
  final String text;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(color: AppColors.primaryContainer, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(numberLabel, style: textTheme.labelMedium?.copyWith(color: AppColors.primary)),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(text, style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary)),
        ),
      ],
    );
  }
}

class _ResendStatusCard extends StatelessWidget {
  const _ResendStatusCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppStatusColor.waiting.background,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppStatusColor.waiting.foreground),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule_outlined, color: AppStatusColor.waiting.foreground),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: AppFadeThroughSwitcher(
              switchKey: label,
              duration: const Duration(milliseconds: 180),
              child: Text(
                label,
                key: ValueKey(label),
                style: textTheme.labelMedium?.copyWith(color: AppStatusColor.waiting.foreground),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
