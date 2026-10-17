import 'package:flutter/foundation.dart';

/// Domínio público da app — placeholder até haver um domínio real registado
/// (ver `docs/improvements.md`, "Nome próprio em português").
abstract final class AppLinks {
  const AppLinks._();

  static const String _placeholderDomain = 'https://projardim.pt';

  /// Na web o link aponta para o próprio site onde a app está alojada
  /// (a rota /w/:workerId é pública), por isso funciona já. Nas apps
  /// nativas continua o placeholder até haver domínio.
  static String get _publicDomain =>
      kIsWeb ? Uri.base.origin : _placeholderDomain;

  static String publicWorkerProfileUrl(String workerId) =>
      '$_publicDomain/w/$workerId';
}
