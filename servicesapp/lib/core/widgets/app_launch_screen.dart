import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion_tokens.dart';
import '../theme/app_sizes.dart';
import '../theme/app_spacing.dart';

/// Ecrã de arranque (`/loading`) enquanto a sessão carrega: o mesmo logo
/// do splash nativo (flutter_native_splash, fundo branco), para não haver
/// salto entre o splash e a app. Entra com um fade e uma escala curtos;
/// sem animação quando o sistema pede menos movimento.
class AppLaunchScreen extends StatelessWidget {
  const AppLaunchScreen({super.key});

  static const logoAsset = 'assets/branding/app_icon_rounded.png';

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final textTheme = Theme.of(context).textTheme;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          logoAsset,
          width: AppSizes.launchLogo,
          height: AppSizes.launchLogo,
          semanticLabel: 'ProJardim',
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'ProJardim',
          style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(
        child: reduceMotion
            ? content
            : TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: AppMotionDuration.screen,
                curve: AppMotionCurve.emphasized,
                builder: (context, t, child) => Opacity(
                  opacity: t,
                  child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
                ),
                child: content,
              ),
      ),
    );
  }
}
