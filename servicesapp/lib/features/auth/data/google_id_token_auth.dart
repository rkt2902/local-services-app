import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Login Google feito pela própria app, que depois só entrega o ID token ao
/// Supabase (`signInWithIdToken`). Assim a pessoa nunca vê o endereço
/// `*.supabase.co`: no Android aparece a folha nativa com "ProJardim" e na
/// web a janela da Google diz projardim.pt (a origem da página).
///
/// Precisa de `--dart-define=GOOGLE_WEB_CLIENT_ID=...` (o ID do cliente
/// OAuth "Aplicação Web" do Google Cloud, o mesmo que está no provider Google
/// do Supabase). Sem ele, a app continua no login antigo por browser
/// (`signInWithOAuth`). Configuração em docs/SETUP.md.
class GoogleIdTokenAuth {
  GoogleIdTokenAuth._();

  static const String webClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// Android: folha nativa. Web: botão da Google. iOS fica no login por
  /// browser até haver app iOS (precisa de um cliente OAuth iOS à parte).
  static bool get enabled =>
      webClientId.isNotEmpty &&
      (kIsWeb || defaultTargetPlatform == TargetPlatform.android);

  static Future<void>? _initialized;

  static Future<void> ensureInitialized() {
    return _initialized ??= GoogleSignIn.instance.initialize(
      // Na web o cliente é o próprio ID web; no Android é o "server client",
      // para o token vir com o público que o Supabase espera.
      clientId: kIsWeb ? webClientId : null,
      serverClientId: kIsWeb ? null : webClientId,
    );
  }

  /// Android: abre a folha das contas Google do telemóvel e devolve o ID
  /// token, ou `null` se a pessoa fechou a folha.
  static Future<String?> pickAccountIdToken() async {
    await ensureInitialized();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      rethrow;
    }
  }

  /// Web: tokens das contas escolhidas no botão da Google.
  static Stream<String> webIdTokens() async* {
    await ensureInitialized();
    await for (final event in GoogleSignIn.instance.authenticationEvents) {
      if (event is GoogleSignInAuthenticationEventSignIn) {
        final token = event.user.authentication.idToken;
        if (token != null && token.isNotEmpty) yield token;
      }
    }
  }

  /// Esquece a conta escolhida, para o próximo login voltar a perguntar.
  /// Melhor esforço: nunca impede terminar a sessão no ProJardim.
  static Future<void> signOut() async {
    if (!enabled || _initialized == null) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }
}
