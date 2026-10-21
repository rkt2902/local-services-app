import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/route_guard.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/widgets/app_brand_badge.dart';
import '../../../core/widgets/primary_action_button.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Destino guardado pelo router (rota privada aberta sem sessão): segue
    // para o login, que volta para lá depois de entrar.
    final returnTo =
        GoRouterState.of(context).uri.queryParameters[returnToParam];
    final loginPath = returnTo == null || returnTo.isEmpty
        ? '/login'
        : '/login?$returnToParam=${Uri.encodeComponent(returnTo)}';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Center(
                child: AppBrandBadge(size: 100, iconSize: 48),
              ),
              const SizedBox(height: 28),
              Text(
                'ProJardim',
                style: textTheme.displaySmall?.copyWith(
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Serviços locais ao teu alcance.',
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              PrimaryActionButton(
                label: 'Entrar',
                onPressed: () => context.push(loginPath),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.push('/signup'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  side: const BorderSide(color: AppColors.primary),
                  foregroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  textStyle: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.15,
                  ),
                ),
                child: const Text('Criar conta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
