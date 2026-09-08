// ============================================================
// PREPARAÇÃO — alvo do deep link futuro do email de confirmação. Hoje
// "Confirm email" está DESATIVADO no Supabase (ver
// verify_email_screen.dart e decisions_log.md 2026-06-05), por isso este
// ecrã é aberto SEM parâmetros na quase totalidade dos casos (navegação
// interna a partir de verify_email_screen.dart) e mostra só o visual
// estático de sucesso, sem tentar verificar nada.
//
// TODO(deep link real) — quando "Confirm email" for ligado a sério:
//   - Confirmar contra o template de "Confirm signup" configurado no
//     dashboard (Authentication → Email Templates) que parâmetros o
//     redirect URL realmente envia. O padrão assumido aqui —
//     ?token_hash=...&type=signup — é o recomendado pela documentação do
//     Supabase para este fluxo (evita o flow implícito baseado em
//     fragment #access_token=...), mas NÃO foi testado neste projeto.
//     Um template customizado com {{ .Token }} em vez de {{ .TokenHash }}
//     chegaria antes como ?token=...&email=...&type=signup — os dois
//     casos já estão cobertos abaixo, mas confirmar qual é o real.
//   - Se o Supabase usar o flow implícito (fragment, não query string),
//     os parâmetros vêm depois de "#", não de "?" — GoRouterState.uri.
//     queryParameters não os apanha; nesse caso a app teria de os ler do
//     URI completo recebido pelo plugin de deep link (app_links) antes de
//     entregar ao go_router, não daqui.
//   - Instalar app_links (ou uni_links) no pubspec.yaml — não instalado.
//   - Registar intent-filter no AndroidManifest.xml (TODO deixado lá) e
//     CFBundleURLTypes no Info.plist (TODO deixado lá).
//   - Registar o Redirect URL correspondente em Authentication → URL
//     Configuration no dashboard.
//
// Migration 0036 (não aplicada) já trata do resto: profiles.id ganhou
// ON DELETE CASCADE reforçado para auth.users(id), e todos os
// utilizadores já registados foram marcados como confirmados (backfill)
// para não ficarem presos no dia em que isto for ligado.
// ============================================================

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

class EmailConfirmedScreen extends ConsumerStatefulWidget {
  const EmailConfirmedScreen({
    super.key,
    this.email,
    this.tokenHash,
    this.token,
  });

  final String? email;

  /// Parâmetro `token_hash` do redirect — padrão recomendado pelo
  /// Supabase para este fluxo. Ver TODO no topo do ficheiro.
  final String? tokenHash;

  /// Parâmetro `token` do redirect — só usado se `tokenHash` vier vazio
  /// (customização alternativa do template).
  final String? token;

  @override
  ConsumerState<EmailConfirmedScreen> createState() => _EmailConfirmedScreenState();
}

class _EmailConfirmedScreenState extends ConsumerState<EmailConfirmedScreen> {
  bool _verifying = false;
  String? _errorMessage;

  bool get _hasDeepLinkParams =>
      (widget.tokenHash != null && widget.tokenHash!.isNotEmpty) ||
      (widget.token != null && widget.token!.isNotEmpty);

  @override
  void initState() {
    super.initState();
    // Situação atual (sem confirmação ativa, sem deep link real): nunca
    // entra aqui, o ecrã mostra logo o visual estático abaixo.
    if (_hasDeepLinkParams) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
    }
  }

  Future<void> _verify() async {
    setState(() {
      _verifying = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authRepositoryProvider).verifySignupEmail(
            tokenHash: widget.tokenHash,
            token: widget.token,
            email: widget.email,
          );
      if (!mounted) return;
      setState(() => _verifying = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _errorMessage = e is AuthException ? e.message : 'Ocorreu um erro. Tenta novamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (_verifying) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Não foi possível confirmar o email',
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: Text(
                      'Voltar ao login',
                      style: textTheme.labelLarge?.copyWith(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Visual estático de sucesso — usado hoje sempre (sem parâmetros de
    // deep link) e também depois de uma verificação real bem-sucedida.
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
                    const SizedBox(height: AppSpacing.xl),
                    AppStaggeredEntrance(index: 0, child: _SuccessIcon()),
                    const SizedBox(height: AppSpacing.lg),
                    AppStaggeredEntrance(
                      index: 1,
                      child: Text(
                        'Email confirmado!',
                        textAlign: TextAlign.center,
                        style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppStaggeredEntrance(
                      index: 2,
                      child: Text(
                        'A sua conta ProJardim está pronta.\nEntre para começar.',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                    if (widget.email != null && widget.email!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      AppStaggeredEntrance(
                        index: 3,
                        child: _VerifiedEmailCard(emailLabel: widget.email!),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              color: AppColors.surface,
              padding: const EdgeInsets.all(AppSpacing.md),
              child: PrimaryActionButton(
                label: 'Entrar na minha conta',
                onPressed: () => context.go('/login'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(color: AppStatusColor.success.background, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(color: AppStatusColor.success.foreground, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: const Icon(Icons.check_rounded, color: AppColors.surface, size: 38),
      ),
    );
  }
}

class _VerifiedEmailCard extends StatelessWidget {
  const _VerifiedEmailCard({required this.emailLabel});

  final String emailLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user_outlined, color: AppStatusColor.success.foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  emailLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Verificado',
                  style: textTheme.labelMedium?.copyWith(color: AppStatusColor.success.foreground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
