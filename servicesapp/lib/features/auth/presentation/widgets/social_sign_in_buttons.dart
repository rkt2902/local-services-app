import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';

/// "Continuar com Google" e "Continuar com Facebook", no login e no
/// registo. Quem entra pela primeira vez assim não passa pela caixa dos
/// termos do registo por email, por isso a frase dos termos vai aqui.
class SocialSignInButtons extends StatelessWidget {
  const SocialSignInButtons({
    super.key,
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final ValueChanged<OAuthProvider> onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SocialButton(
          label: 'Continuar com Google',
          icon: const _GoogleMark(),
          onPressed: enabled ? () => onPressed(OAuthProvider.google) : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        _SocialButton(
          label: 'Continuar com Facebook',
          icon: const Icon(
            Icons.facebook,
            size: 22,
            color: AppColors.facebookBlue,
          ),
          onPressed: enabled ? () => onPressed(OAuthProvider.facebook) : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Ao continuar com Google ou Facebook aceitas os Termos e a '
          'Política de Privacidade.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: AppColors.surface,
        disabledBackgroundColor: AppColors.surface,
        side: const BorderSide(color: AppColors.divider),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon,
          const SizedBox(width: AppSpacing.s10),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Marca simples do Google (círculo com as 4 cores), sem asset de imagem.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            AppColors.googleBlue,
            AppColors.googleGreen,
            AppColors.googleYellow,
            AppColors.googleRed,
          ],
        ),
      ),
    );
  }
}
