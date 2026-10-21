import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;
import '../../../core/router/route_guard.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_brand_badge.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../application/auth_controller.dart';
import 'widgets/social_sign_in_buttons.dart';
import '../../../core/widgets/app_toast.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (ref.read(authControllerProvider) is AuthLoading) return;
    if (!_formKey.currentState!.validate()) return;
    // Destino original (rota privada aberta sem sessão), se houver.
    final returnTo =
        GoRouterState.of(context).uri.queryParameters[returnToParam];
    await ref.read(authControllerProvider.notifier).signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
    if (!mounted) return;
    final currentState = ref.read(authControllerProvider);
    if (currentState is! AuthSuccess) return;
    // O router decide o destino pelo papel: o início do papel ou, se veio
    // de uma rota privada, essa rota (resolveRedirect/safeReturnTarget).
    context.go(
      returnTo == null || returnTo.isEmpty
          ? '/'
          : '/?$returnToParam=${Uri.encodeComponent(returnTo)}',
    );
  }

  Future<void> _signInWithSocial(OAuthProvider provider) async {
    final returnTo = GoRouterState.of(
      context,
    ).uri.queryParameters[returnToParam];
    await ref
        .read(authControllerProvider.notifier)
        .signInWithSocial(provider, returnTo: returnTo);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState is AuthLoading;

    ref.listen(authControllerProvider, (_, next) {
      if (next is AuthEmailNotConfirmed) {
        context.go('/verify-email?email=${Uri.encodeComponent(next.email)}');
        return;
      }
      if (next is AuthError) {
        AppToast.of(context).error(next.message);
      }
    });

    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.xl,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    children: [
                      const AppStaggeredEntrance(
                        index: 0,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: AppBrandBadge(
                            size: AppSizes.authBrandBadge,
                            iconSize: AppSizes.authBrandIcon,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppStaggeredEntrance(
                        index: 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bem-vindo de volta',
                              style: textTheme.displaySmall?.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              'Entra na tua conta ProJardim',
                              style: textTheme.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppStaggeredEntrance(
                        index: 2,
                        child: AppTextField(
                          controller: _emailController,
                          label: 'Email',
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            if (text.isEmpty) return 'Introduz o email.';
                            if (!text.contains('@')) return 'Email inválido.';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s14),
                      AppStaggeredEntrance(
                        index: 3,
                        child: AppTextField(
                          controller: _passwordController,
                          label: 'Senha',
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => _submit(),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Mostrar senha'
                                : 'Esconder senha',
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          validator: (value) {
                            if ((value ?? '').isEmpty) {
                              return 'Introduz a senha.';
                            }
                            if ((value ?? '').length < 6) {
                              return 'Mínimo 6 caracteres.';
                            }
                            return null;
                          },
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: isLoading
                              ? null
                              : () {
                                  final email = _emailController.text.trim();
                                  context.push(
                                    '/forgot-password/request'
                                    '${email.isNotEmpty ? '?email=${Uri.encodeComponent(email)}' : ''}',
                                  );
                                },
                          child: Text(
                            'Esqueceste-te da senha?',
                            style: textTheme.labelLarge?.copyWith(
                              color: AppColors.primaryPressed,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      AppStaggeredEntrance(
                        index: 4,
                        child: PrimaryActionButton(
                          label: 'Entrar',
                          isLoading: isLoading,
                          onPressed: _submit,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s18),
                      AppStaggeredEntrance(
                        index: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Divider(color: AppColors.divider),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm,
                                  ),
                                  child: Text(
                                    'ou',
                                    style: textTheme.labelLarge?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                                const Expanded(
                                  child: Divider(color: AppColors.divider),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.s18),
                            SocialSignInButtons(
                              enabled: !isLoading,
                              onPressed: _signInWithSocial,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Com o teclado aberto o rodapé subia colado ao teclado e
            // tapava o botão "Entrar". Esconde-se enquanto se escreve.
            if (!keyboardOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Não tens conta?',
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    TextButton(
                      onPressed: isLoading ? null : () => context.go('/signup'),
                      child: Text(
                        'Criar conta',
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.primaryPressed,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
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
