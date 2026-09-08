import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_repository.dart';
import 'auth_providers.dart';

enum PasswordResetErrorKind { network, invalidCode, unexpected }

sealed class PasswordResetState {
  const PasswordResetState();
}

class PasswordResetIdle extends PasswordResetState {
  const PasswordResetIdle();
}

class PasswordResetLoading extends PasswordResetState {
  const PasswordResetLoading();
}

class PasswordResetError extends PasswordResetState {
  const PasswordResetError(this.message, this.kind);
  final String message;
  final PasswordResetErrorKind kind;
}

class PasswordResetSuccess extends PasswordResetState {
  const PasswordResetSuccess();
}

/// Mensagem amigável para um erro lançado por qualquer chamada deste fluxo
/// — incluindo `resendCode`, que não passa pelo `state` do controller (ver
/// nota em `resendCode` abaixo), por isso os callers precisam de formatar
/// o erro diretamente a partir do `catch`.
String describePasswordResetError(Object e) =>
    e is AuthException ? e.message : 'Ocorreu um erro. Tenta novamente.';

/// Controller único para todo o fluxo de recuperação de senha (os 3 passos
/// pós-email vivem numa só rota — ver `password_reset_screen.dart` — por
/// isso partilham este controller em vez de um por ecrã).
class PasswordResetController extends Notifier<PasswordResetState> {
  @override
  PasswordResetState build() => const PasswordResetIdle();

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  /// `true` só quando `verifyOtp` teve de recorrer ao bypass de
  /// desenvolvimento (kDebugMode + código sintaticamente válido, mas
  /// rejeitado pelo Supabase real) — nesse caso não existe sessão de
  /// recuperação real, por isso `updatePassword` também simula em vez de
  /// chamar o Supabase. Ver `AuthRepository.verifyPasswordResetOtp`.
  bool _devBypassActive = false;
  bool get isDevBypassActive => _devBypassActive;

  void reset() {
    _devBypassActive = false;
    state = const PasswordResetIdle();
  }

  /// Anti-enumeração (Part 2.5): a UI tem de mostrar sempre "se o email
  /// estiver registado, recebe um código" e avançar — independentemente de
  /// a conta existir. O Supabase já não revela isso na resposta (sucesso
  /// sempre), mas garantimos aqui também: só um erro de REDE impede o
  /// avanço; qualquer outro erro é silenciado (registado só para
  /// diagnóstico) e tratado como sucesso.
  Future<void> requestReset(String email) async {
    state = const PasswordResetLoading();
    try {
      await _repo.requestPasswordReset(email);
      state = const PasswordResetSuccess();
    } catch (e) {
      if (_classify(e) == PasswordResetErrorKind.network) {
        state = PasswordResetError(describePasswordResetError(e), PasswordResetErrorKind.network);
        return;
      }
      debugPrint(
        'requestPasswordReset: erro não-rede silenciado por anti-enumeration: $e',
      );
      state = const PasswordResetSuccess();
    }
  }

  Future<void> verifyOtp({required String email, required String code}) async {
    state = const PasswordResetLoading();
    try {
      final realSession = await _repo.verifyPasswordResetOtp(email, code);
      _devBypassActive = !realSession;
      state = const PasswordResetSuccess();
    } catch (e) {
      state = PasswordResetError(describePasswordResetError(e), _classify(e));
    }
  }

  /// Reenvio do código a partir do passo 2. Não mexe no `state` partilhado
  /// de propósito: `state` é o que o wizard (`password_reset_screen.dart`)
  /// observa para decidir quando avançar de passo via `PasswordResetSuccess`
  /// — se o reenvio passasse por lá, completar um reenvio pareceria uma
  /// verificação de OTP bem-sucedida e avançaria o utilizador por engano.
  /// O caller (`VerifyResetCodeScreen._resend`) trata o `Future` diretamente
  /// (SnackBar de sucesso/erro), usando `describePasswordResetError` acima
  /// para formatar uma eventual exceção.
  Future<void> resendCode(String email) => _repo.requestPasswordReset(email);

  Future<void> updatePassword(String newPassword) async {
    state = const PasswordResetLoading();
    if (_devBypassActive) {
      debugPrint(
        '[DEV BYPASS] updatePassword: senha NÃO foi alterada — sessão de '
        'recuperação era simulada (ver verifyPasswordResetOtp).',
      );
      state = const PasswordResetSuccess();
      return;
    }
    try {
      await _repo.updatePassword(newPassword);
      state = const PasswordResetSuccess();
    } catch (e) {
      state = PasswordResetError(describePasswordResetError(e), _classify(e));
    }
  }

  PasswordResetErrorKind _classify(Object e) {
    final code = e is AuthException ? e.code : null;
    return switch (code) {
      PasswordResetErrorCode.network => PasswordResetErrorKind.network,
      PasswordResetErrorCode.invalidCode => PasswordResetErrorKind.invalidCode,
      _ => PasswordResetErrorKind.unexpected,
    };
  }
}

final passwordResetControllerProvider =
    NotifierProvider<PasswordResetController, PasswordResetState>(
  PasswordResetController.new,
);
