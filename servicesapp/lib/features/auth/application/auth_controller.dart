import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/enums.dart';
import '../../notifications/application/push_notification_service.dart';
import '../../../core/utils/error_utils.dart';
import '../data/auth_repository.dart';
import 'auth_providers.dart';
import 'session_provider.dart';

sealed class AuthControllerState {
  const AuthControllerState();
}

class AuthIdle extends AuthControllerState {
  const AuthIdle();
}

class AuthLoading extends AuthControllerState {
  const AuthLoading();
}

class AuthError extends AuthControllerState {
  final String message;
  const AuthError(this.message);
}

class AuthSuccess extends AuthControllerState {
  /// Só no registo: `true` quando "Confirm email" está ligado no Supabase e
  /// o utilizador tem de escrever o código do email antes de continuar.
  final bool needsEmailConfirmation;
  const AuthSuccess({this.needsEmailConfirmation = false});
}

/// Login de uma conta com email por confirmar. O código já foi reenviado;
/// o ecrã de login leva para `/verify-email`.
class AuthEmailNotConfirmed extends AuthControllerState {
  final String email;
  const AuthEmailNotConfirmed(this.email);
}

class AuthController extends Notifier<AuthControllerState> {
  @override
  AuthControllerState build() => const AuthIdle();

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) async {
    state = const AuthLoading();
    try {
      final needsConfirmation = await _repo.signUp(
        email: email,
        password: password,
        fullName: fullName,
        phone: phone,
      );
      state = AuthSuccess(needsEmailConfirmation: needsConfirmation);
    } catch (e) {
      state = AuthError(friendlyError(e));
    }
  }

  Future<void> createProfile({
    required String userId,
    required String fullName,
    required String phone,
    required UserRole role,
    String? socialAvatarUrl,
  }) async {
    state = const AuthLoading();
    try {
      // Conta Google/Facebook: copia a foto para o Storage antes de criar o
      // perfil (melhor esforço, null se falhar).
      final avatarUrl = socialAvatarUrl == null
          ? null
          : await _repo.importSocialAvatar(userId, socialAvatarUrl);
      await _repo.createProfile(
        userId: userId,
        fullName: fullName,
        phone: phone,
        role: role,
        avatarUrl: avatarUrl,
      );
      state = const AuthSuccess();
      // Fire and forget — don't await, let navigation happen immediately
      ref.read(sessionStatusProvider.notifier).refresh();
    } catch (e) {
      state = AuthError(friendlyError(e));
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    state = const AuthLoading();
    try {
      await _repo.signIn(email: email, password: password);
      await ref.read(sessionStatusProvider.notifier).refresh();
      state = const AuthSuccess();
    } catch (e) {
      if (_isEmailNotConfirmed(e)) {
        // Melhor esforço: se o reenvio falhar (limite de 60s, rede), o
        // ecrã de verificação tem o botão de reenviar.
        try {
          await _repo.resendSignupConfirmation(email);
        } catch (_) {}
        state = AuthEmailNotConfirmed(email);
        return;
      }
      state = AuthError(friendlyError(e));
    }
  }

  /// Abre o login do Google ou do Facebook. A sessão chega depois por
  /// redirect (`onAuthStateChange`) e o router decide o destino, por isso
  /// isto só muda o estado se não der para abrir a página.
  Future<void> signInWithSocial(
    OAuthProvider provider, {
    String? returnTo,
  }) async {
    try {
      await _repo.signInWithSocial(provider, returnTo: returnTo);
    } catch (e) {
      state = AuthError(friendlyError(e));
    }
  }

  Future<void> signOut() async {
    state = const AuthLoading();
    try {
      await ref.read(pushNotificationServiceProvider).unregister();
      await _repo.signOut();
      await ref.read(sessionStatusProvider.notifier).refresh();
      state = const AuthSuccess();
    } catch (e) {
      state = AuthError(friendlyError(e));
    }
  }
}

bool _isEmailNotConfirmed(Object e) {
  if (e is AuthException && e.code == 'email_not_confirmed') return true;
  return e.toString().toLowerCase().contains('email not confirmed');
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthControllerState>(AuthController.new);
