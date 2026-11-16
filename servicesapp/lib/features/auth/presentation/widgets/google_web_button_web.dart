import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as gsi;

import '../../../../core/theme/app_sizes.dart';

/// "Continuar com Google" desenhado pela própria Google. A janela que abre
/// mostra projardim.pt (a origem da página), não o Supabase.
Widget buildGoogleWebButton({required double width}) {
  return gsi.renderButton(
    configuration: gsi.GSIButtonConfiguration(
      type: gsi.GSIButtonType.standard,
      theme: gsi.GSIButtonTheme.outline,
      size: gsi.GSIButtonSize.large,
      text: gsi.GSIButtonText.continueWith,
      shape: gsi.GSIButtonShape.rectangular,
      logoAlignment: gsi.GSIButtonLogoAlignment.center,
      minimumWidth: width.clamp(1, AppSizes.googleWebButtonMaxWidth),
      locale: 'pt-PT',
    ),
  );
}
