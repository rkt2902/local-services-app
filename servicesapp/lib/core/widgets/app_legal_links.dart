import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_links.dart';
import '../theme/app_colors.dart';

/// Abre os Termos de utilização no browser, fora da app.
Future<void> openTermsOfUse(BuildContext context) =>
    _openLegalPage(context, AppLinks.termsUrl);

/// Abre a Política de Privacidade no browser, fora da app.
Future<void> openPrivacyPolicy(BuildContext context) =>
    _openLegalPage(context, AppLinks.privacyPolicyUrl);

Future<void> _openLegalPage(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  var opened = false;
  try {
    opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Não foi possível abrir a página. Tenta outra vez.'),
      ),
    );
  }
}

/// "`prefix` + Termos e a Política de Privacidade.", com os dois nomes a verde
/// e com toque (abrem as páginas). Usado na caixa dos termos do registo e na
/// frase do login social.
class AppLegalConsentText extends StatefulWidget {
  const AppLegalConsentText({
    super.key,
    required this.prefix,
    this.style,
    this.textAlign = TextAlign.start,
    this.onTermsPressed,
    this.onPrivacyPressed,
  });

  /// Texto antes de "Termos", com o espaço no fim (ex.: "Aceito os ").
  final String prefix;
  final TextStyle? style;
  final TextAlign textAlign;

  /// Por omissão abrem [AppLinks.termsUrl] e [AppLinks.privacyPolicyUrl].
  final VoidCallback? onTermsPressed;
  final VoidCallback? onPrivacyPressed;

  @override
  State<AppLegalConsentText> createState() => _AppLegalConsentTextState();
}

class _AppLegalConsentTextState extends State<AppLegalConsentText> {
  late final TapGestureRecognizer _terms = TapGestureRecognizer()
    ..onTap = () => (widget.onTermsPressed ?? () => openTermsOfUse(context))();
  late final TapGestureRecognizer _privacy = TapGestureRecognizer()
    ..onTap = () =>
        (widget.onPrivacyPressed ?? () => openPrivacyPolicy(context))();

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style ?? Theme.of(context).textTheme.bodySmall;
    final link = base?.copyWith(
      color: AppColors.primaryPressed,
      fontWeight: FontWeight.w700,
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: widget.prefix),
          TextSpan(text: 'Termos', style: link, recognizer: _terms),
          const TextSpan(text: ' e a '),
          TextSpan(
            text: 'Política de Privacidade',
            style: link,
            recognizer: _privacy,
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: widget.textAlign,
    );
  }
}
