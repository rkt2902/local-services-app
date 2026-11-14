import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/legal/domain/legal_document.dart';
import '../theme/app_colors.dart';

/// Abre os Termos de utilização no ecrã da app (`/termos`).
Future<void> openTermsOfUse(BuildContext context) =>
    _openLegalPage(context, LegalDocumentKind.terms);

/// Abre a Política de Privacidade no ecrã da app (`/privacidade`).
Future<void> openPrivacyPolicy(BuildContext context) =>
    _openLegalPage(context, LegalDocumentKind.privacy);

Future<void> _openLegalPage(
  BuildContext context,
  LegalDocumentKind kind,
) async {
  // O texto vem empacotado na app: abre sem rede e sem sair da app. Os
  // URLs públicos (AppLinks.termsUrl / privacyPolicyUrl) são para as lojas,
  // o Google Cloud e a Meta.
  await GoRouter.of(context).push(kind.route);
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

  /// Por omissão abrem os ecrãs `/termos` e `/privacidade`.
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
