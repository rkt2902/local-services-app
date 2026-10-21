import 'package:flutter/foundation.dart';

import 'supabase_config.dart';

/// URLs de fotos que a app aceita mostrar.
///
/// `profiles.avatar_url` é texto livre na BD: qualquer conta pode gravar lá
/// um URL externo por REST direto e, se a app o carregasse, o dono desse
/// servidor ficava a saber o IP de quem abre o perfil (review de 16/10).
/// Por isso só se mostram URLs públicos do Storage do próprio projeto. O
/// prefixo vem de `SUPABASE_URL` (--dart-define), por isso continua certo
/// se o projeto mudar de domínio, sem migration.
abstract final class StorageUrls {
  const StorageUrls._();

  /// Devolve [url] se for uma foto do Storage do projeto, senão `null`.
  static String? trustedOrNull(String? url) =>
      trustedForProject(url, supabaseUrl: SupabaseConfig.url);

  /// Versão com o URL do projeto explícito, para testes.
  @visibleForTesting
  static String? trustedForProject(
    String? url, {
    required String supabaseUrl,
  }) {
    if (url == null || url.isEmpty || supabaseUrl.isEmpty) return null;
    final base = supabaseUrl.endsWith('/')
        ? supabaseUrl.substring(0, supabaseUrl.length - 1)
        : supabaseUrl;
    return url.startsWith('$base/storage/v1/object/public/') ? url : null;
  }

  /// Igual a [trustedOrNull], mas com `''` em vez de `null`, para os mapas
  /// `{'full_name', 'avatar_url'}` que já usam string vazia como "sem foto".
  static String trustedOrEmpty(String? url) => trustedOrNull(url) ?? '';
}
