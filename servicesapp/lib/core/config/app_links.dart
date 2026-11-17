import 'package:flutter/foundation.dart';

/// Domínio público e contactos da app.
///
/// Os valores reais entram por `--dart-define` (como `SUPABASE_URL`), por
/// isso mudar de domínio não mexe em código: ver `docs/SETUP.md`.
///
/// - `APP_PUBLIC_URL`: endereço público da app, sem `/` no fim (por exemplo
///   `https://projardim.pt` ou `https://projardim.netlify.app`).
/// - `SUPPORT_EMAIL`: email de suporte mostrado em "Contacto e suporte".
/// - `TERMS_URL` / `PRIVACY_POLICY_URL`: só para forçar outro endereço. Por
///   omissão, `<domínio>/termos` e `<domínio>/privacidade` (páginas
///   estáticas geradas de `assets/legal/` por `tool/build_legal_pages.py`).
abstract final class AppLinks {
  const AppLinks._();

  static const String _placeholderDomain = 'https://projardim.pt';

  static const String _configuredDomain =
      String.fromEnvironment('APP_PUBLIC_URL');

  static const String _defaultSupportEmail = 'suporte@projardim.pt';

  static const String _configuredSupportEmail =
      String.fromEnvironment('SUPPORT_EMAIL');

  /// O `SUPPORT_EMAIL` do build quando é um email; senão o de omissão. Uma
  /// variável do GitHub com outro texto (o site chegou a mostrar "Noth")
  /// já não aparece em "Contacto e suporte".
  static String get supportEmail =>
      supportEmailOrDefault(_configuredSupportEmail);

  @visibleForTesting
  static String supportEmailOrDefault(String configured) {
    final value = configured.trim();
    final looksLikeEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
    return looksLikeEmail ? value : _defaultSupportEmail;
  }

  static const String _configuredTermsUrl = String.fromEnvironment(
    'TERMS_URL',
  );

  static const String _configuredPrivacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
  );

  /// Página pública dos Termos (`<domínio>/termos`), para as lojas, o
  /// Google Cloud e a Meta. Dentro da app abre o ecrã `/termos`.
  static String get termsUrl => _configuredTermsUrl.isNotEmpty
      ? _configuredTermsUrl
      : '$publicDomain/termos';

  /// Página pública da Política de Privacidade (`<domínio>/privacidade`).
  static String get privacyPolicyUrl => _configuredPrivacyPolicyUrl.isNotEmpty
      ? _configuredPrivacyPolicyUrl
      : '$publicDomain/privacidade';

  /// Livro de Reclamações Eletrónico (obrigatório informar o consumidor).
  static const String complaintsBookUrl = 'https://www.livroreclamacoes.pt';

  /// "Continuar com Facebook" só aparece com
  /// `--dart-define=FACEBOOK_LOGIN_ENABLED=true`. Enquanto a app da Meta
  /// estiver em Development (sem verificação de negócio), quem não é tester
  /// recebe um erro da Meta, por isso o botão fica escondido por omissão.
  static const bool facebookLoginEnabled =
      bool.fromEnvironment('FACEBOOK_LOGIN_ENABLED');

  /// Prazo de resposta prometido em "Contacto e suporte".
  static const String supportResponseTime = 'Respondemos em 1 dia útil';

  /// `true` quando há um domínio real definido no build.
  static bool get hasConfiguredDomain => _configuredDomain.isNotEmpty;

  /// Ordem: o domínio definido no build; na web sem definição, o próprio
  /// site onde a app está alojada (a rota /w/:workerId é pública); nas apps
  /// nativas sem definição, o placeholder.
  static String get publicDomain {
    if (hasConfiguredDomain) return _stripTrailingSlash(_configuredDomain);
    if (kIsWeb) return Uri.base.origin;
    return _placeholderDomain;
  }

  /// Cartão público do jardineiro. [source] (`qr`, `link`) vai em `?src=`
  /// para o servidor saber de onde veio a visita (A7, migration 0059).
  static String publicWorkerProfileUrl(String workerId, {String? source}) =>
      source == null
          ? '$publicDomain/w/$workerId'
          : '$publicDomain/w/$workerId?src=$source';

  static String _stripTrailingSlash(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}
