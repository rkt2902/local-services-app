import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_sizes.dart';
import '../theme/app_spacing.dart';

/// Logótipo do WhatsApp (fonte de marcas do pacote `font_awesome_flutter`,
/// o mesmo `FontAwesomeIcons.whatsapp`). `const` para o tree-shaking de
/// ícones funcionar no build.
const IconData appWhatsAppIcon = IconData(
  0xf232,
  fontFamily: 'FontAwesomeBrands',
  fontPackage: 'font_awesome_flutter',
);

/// Botão de contacto por WhatsApp, igual em toda a app: fundo branco,
/// contorno do divisor, logótipo verde do WhatsApp e texto numa só linha.
///
/// [compact] é para ficar ao lado de um nome (cartão do cliente, de um
/// ajudante): só "WhatsApp" e a largura do conteúdo. Sem [compact] ocupa a
/// largura toda com "Falar por WhatsApp".
class AppWhatsAppButton extends StatelessWidget {
  const AppWhatsAppButton({
    super.key,
    required this.onPressed,
    this.compact = false,
  });

  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final enabled = onPressed != null;

    final button = OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.divider),
        minimumSize: Size(0, AppSizes.compactButtonHeight),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.sm : AppSpacing.md,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        textStyle: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      icon: Icon(
        appWhatsAppIcon,
        size: AppSizes.infoRowIcon,
        color: enabled ? AppColors.whatsapp : AppColors.textSecondary,
      ),
      label: Text(
        compact ? 'WhatsApp' : 'Falar por WhatsApp',
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
      ),
    );

    return Semantics(
      label: compact ? 'Falar por WhatsApp' : null,
      excludeSemantics: compact,
      button: true,
      child: compact
          ? button
          : SizedBox(width: double.infinity, child: button),
    );
  }
}
