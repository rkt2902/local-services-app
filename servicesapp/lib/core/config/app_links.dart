import 'package:flutter/foundation.dart';

/// Domínio público e contactos da app.
///
/// Os valores reais entram por `--dart-define` (como `SUPABASE_URL`), por
/// isso mudar de domínio não mexe em código: ver `docs/SETUP.md`.
///
/// - `APP_PUBLIC_URL`: endereço público da app, sem `/` no fim (por exemplo
///   `https://projardim.pt` ou `https://projardim.netlify.app`).
/// - `SUPPORT_EMAIL`: email de suporte mostrado em "Contacto e suporte".
abstract final class AppLinks {
  const AppLinks._();

  static const String _placeholderDomain = 'https://projardim.pt';

  static const String _configuredDomain =
      String.fromEnvironment('APP_PUBLIC_URL');

  static const String supportEmail = String.fromEnvironment(
    'SUPPORT_EMAIL',
    defaultValue: 'suporte@projardim.pt',
  );

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

  static String publicWorkerProfileUrl(String workerId) =>
      '$publicDomain/w/$workerId';

  static String _stripTrailingSlash(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}
