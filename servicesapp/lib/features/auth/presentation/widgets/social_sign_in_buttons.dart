import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
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
        // Facebook pede o botão azul da marca com texto e "f" brancos.
        _SocialButton(
          label: 'Continuar com Facebook',
          icon: const Icon(
            Icons.facebook,
            size: AppSizes.socialLogo,
            color: AppColors.surface,
          ),
          background: AppColors.facebookBlue,
          foreground: AppColors.surface,
          onPressed: enabled ? () => onPressed(OAuthProvider.facebook) : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        const _LegalNotice(),
      ],
    );
  }
}

/// "Ao continuar com Google ou Facebook aceitas os Termos e a Política de
/// Privacidade.", com os dois nomes a verde (design U5).
class _LegalNotice extends StatelessWidget {
  const _LegalNotice();

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final link = small?.copyWith(
      color: AppColors.primaryPressed,
      fontWeight: FontWeight.w700,
    );
    return Text.rich(
      TextSpan(
        style: small?.copyWith(color: AppColors.textSecondary),
        children: [
          const TextSpan(
              text: 'Ao continuar com Google ou Facebook aceitas os '),
          TextSpan(text: 'Termos', style: link),
          const TextSpan(text: ' e a '),
          TextSpan(text: 'Política de Privacidade', style: link),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.background = AppColors.surface,
    this.foreground = AppColors.textPrimary,
  });

  final String label;
  final Widget icon;
  final VoidCallback? onPressed;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor: background.withValues(alpha: 0.6),
        side: BorderSide(
          color:
              background == AppColors.surface ? AppColors.divider : background,
        ),
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
                    color: foreground,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "G" do Google desenhado com as quatro cores oficiais, sem asset: arco
/// vermelho em cima, amarelo à esquerda, verde em baixo e azul à direita
/// com a barra horizontal.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: AppSizes.socialLogo,
      child: CustomPaint(painter: _GoogleMarkPainter()),
    );
  }
}

class _GoogleMarkPainter extends CustomPainter {
  const _GoogleMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.2;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    Paint arc(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    // Ângulos em radianos, a contar das 3h no sentido dos ponteiros.
    const deg = 3.14159265 / 180;
    canvas.drawArc(
        rect, -40 * deg, -100 * deg, false, arc(AppColors.googleRed));
    canvas.drawArc(
        rect, -140 * deg, -90 * deg, false, arc(AppColors.googleYellow));
    canvas.drawArc(
        rect, 130 * deg, -95 * deg, false, arc(AppColors.googleGreen));
    canvas.drawArc(rect, 35 * deg, -35 * deg, false, arc(AppColors.googleBlue));

    final center = size.center(Offset.zero);
    canvas.drawRect(
      Rect.fromLTRB(
        center.dx,
        center.dy - stroke / 2,
        size.width,
        center.dy + stroke / 2,
      ),
      Paint()..color = AppColors.googleBlue,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
