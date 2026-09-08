import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/enums.dart';

/// Tags internas em [AuthException.code] usadas pelos 3 métodos de
/// recuperação de senha abaixo — não são códigos do Supabase, servem só
/// para `PasswordResetController` decidir que ecrã mostrar (inline vs.
/// `AppSystemStateScreen`) sem ter de re-analisar uma mensagem já traduzida.
abstract final class PasswordResetErrorCode {
  static const network = 'app_network_error';
  static const invalidCode = 'app_invalid_code';
  static const unexpected = 'app_unexpected_error';
}

class AuthRepository {
  final SupabaseClient _client;
  AuthRepository(this._client);

  User? get currentUser => _client.auth.currentUser;
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) async {
    await _client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName, 'phone': phone},
    );
  }

  Future<void> createProfile({
    required String userId,
    required String fullName,
    required String phone,
    required UserRole role,
  }) async {
    await _client.from('profiles').upsert({
      'id': userId,
      'full_name': fullName,
      'phone': phone,
      'role': role.value,
    });
  }

  Future<({String fullName, String phone})?> fetchNameAndPhone(
      String userId) async {
    final data = await _client
        .from('profiles')
        .select('full_name, phone')
        .eq('id', userId)
        .maybeSingle();
    if (data == null) return null;
    return (
      fullName: data['full_name'] as String,
      phone: data['phone'] as String? ?? '',
    );
  }

  Future<UserRole?> fetchUserRole(String userId) async {
    final data = await _client
        .from('profiles')
        .select('role')
        .eq('id', userId)
        .maybeSingle();
    if (data == null) return null;
    return UserRole.fromString(data['role'] as String);
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // ── Recuperação de senha ───────────────────────────────────────────────
  //
  // As 3 chamadas usam a API real do Supabase para reset por OTP (não
  // signInWithOtp — esse é para login, não recuperação):
  //   1. resetPasswordForEmail — pede o envio do código.
  //   2. verifyOTP(type: OtpType.recovery) — troca o código por uma sessão
  //      de recuperação temporária (NÃO OtpType.email, que é para outro
  //      fluxo e não abre a sessão que updateUser precisa).
  //   3. updateUser — só funciona enquanto essa sessão de recuperação
  //      estiver ativa.

  Future<void> requestPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
    } catch (e) {
      _throwClassified(e);
    }
  }

  /// Devolve `true` quando abriu mesmo uma sessão de recuperação real (via
  /// `verifyOTP`) — só nesse caso `updatePassword` vai ter efeito.
  ///
  /// Devolve `false` apenas no bypass de desenvolvimento (ver bloco
  /// `kDebugMode` abaixo); nunca acontece em release, porque `kDebugMode`
  /// é sempre `false` num build de release.
  Future<bool> verifyPasswordResetOtp(String email, String code) async {
    try {
      await _client.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.recovery,
      );
      return true;
    } catch (e) {
      // O bypass só entra em jogo depois de o código REAL já ter falhado —
      // se o dev colar o código verdadeiro recebido por email, verifica-se
      // a sério e updatePassword funciona normalmente. Isto só cobre testar
      // o fluxo visual sem ir ao email/inbox de dev.
      if (kDebugMode && RegExp(r'^\d{6}$').hasMatch(code)) {
        debugPrint(
          '[DEV BYPASS] verifyPasswordResetOtp: código real rejeitado '
          '($e) — a simular sucesso em modo debug. Sem sessão de '
          'recuperação real, updatePassword NÃO vai alterar a senha.',
        );
        return false;
      }
      _throwClassified(e);
    }
  }

  Future<void> updatePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } catch (e) {
      _throwClassified(e);
    }
  }

  // ── Confirmação de email (preparação — Confirm email ainda desativado
  // no dashboard, ver decisions_log.md 2026-06-05) ───────────────────────
  //
  // Reutiliza o mesmo `_throwClassified` do fluxo de recuperação — a
  // classificação (rede / código inválido-expirado / inesperado) não é
  // específica de nenhum dos dois fluxos.

  Future<void> resendSignupConfirmation(String email) async {
    try {
      await _client.auth.resend(type: OtpType.signup, email: email);
    } catch (e) {
      _throwClassified(e);
    }
  }

  /// Verificação via deep link — usada por `email_confirmed_screen.dart`
  /// quando (no futuro, com app_links instalado) a rota `/email-confirmed`
  /// receber os parâmetros reais do template de confirmação. Aceita tanto
  /// o padrão recomendado pelo Supabase (`token_hash` + `type`, que por si
  /// só já satisfaz os asserts internos de `verifyOTP`) como `token` +
  /// `email` explícitos, para cobrir uma customização diferente do
  /// template — confirmar exatamente qual dos dois quando o deep link for
  /// configurado a sério (ver TODO em `email_confirmed_screen.dart`).
  Future<void> verifySignupEmail({
    String? tokenHash,
    String? token,
    String? email,
  }) async {
    try {
      await _client.auth.verifyOTP(
        type: OtpType.signup,
        tokenHash: tokenHash,
        token: token,
        email: email,
      );
    } catch (e) {
      _throwClassified(e);
    }
  }

  /// Classifica o erro e relança sempre um [AuthException] com mensagem em
  /// português e `code` de uma das 3 tags de [PasswordResetErrorCode].
  ///
  /// `AuthRetryableFetchException` com `statusCode == null` é o sinal fiável
  /// de falha de rede — o gotrue só o lança dessa forma quando nem chegou a
  /// obter uma resposta HTTP (ver `gotrue` `fetch.dart _handleError`); com
  /// `statusCode` preenchido (5xx) é um erro real do servidor Supabase, não
  /// de conectividade, por isso cai no bucket "unexpected".
  Never _throwClassified(Object e) {
    if (e is AuthRetryableFetchException && e.statusCode == null) {
      throw AuthException(
        'Sem ligação à internet. Verifica a tua conexão e tenta novamente.',
        code: PasswordResetErrorCode.network,
      );
    }

    final code = e is AuthException ? e.code : null;
    if (code == 'otp_expired' || code == 'otp_disabled') {
      throw AuthException(
        'Código inválido ou expirado. Verifica e tenta novamente.',
        code: PasswordResetErrorCode.invalidCode,
      );
    }
    if (code == 'same_password') {
      throw AuthException(
        'A nova password deve ser diferente da anterior.',
        code: PasswordResetErrorCode.unexpected,
      );
    }
    if (code == 'weak_password') {
      throw AuthException(
        'A password é demasiado fraca. Usa 8+ caracteres, uma maiúscula e um número.',
        code: PasswordResetErrorCode.unexpected,
      );
    }
    if (code == 'over_request_rate_limit' || code == 'over_email_send_rate_limit') {
      throw AuthException(
        'Demasiadas tentativas. Aguarda alguns minutos e tenta novamente.',
        code: PasswordResetErrorCode.unexpected,
      );
    }

    // Backstop para exceções sem `code` estruturado.
    final msg = e.toString().toLowerCase();
    if (msg.contains('expired') || (msg.contains('invalid') && msg.contains('token'))) {
      throw AuthException(
        'Código inválido ou expirado. Verifica e tenta novamente.',
        code: PasswordResetErrorCode.invalidCode,
      );
    }
    if (msg.contains('network') ||
        msg.contains('socket') ||
        msg.contains('failed host lookup') ||
        msg.contains('connection refused') ||
        msg.contains('timeout')) {
      throw AuthException(
        'Sem ligação à internet. Verifica a tua conexão e tenta novamente.',
        code: PasswordResetErrorCode.network,
      );
    }

    throw AuthException(
      'Ocorreu um erro. Tenta novamente.',
      code: PasswordResetErrorCode.unexpected,
    );
  }
}
