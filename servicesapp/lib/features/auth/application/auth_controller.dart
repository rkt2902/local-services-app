import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/enums.dart';
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
  const AuthSuccess();
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
      await _repo.signUp(
        email: email,
        password: password,
        fullName: fullName,
        phone: phone,
      );
      state = const AuthSuccess();
    } catch (e) {
      state = AuthError(_mapError(e));
    }
  }

  Future<void> createProfile({
    required String userId,
    required String fullName,
    required String phone,
    required UserRole role,
  }) async {
    state = const AuthLoading();
    try {
      await _repo.createProfile(
        userId: userId,
        fullName: fullName,
        phone: phone,
        role: role,
      );
      state = const AuthSuccess();
      // Fire and forget — don't await, let navigation happen immediately
      ref.read(sessionStatusProvider.notifier).refresh();
    } catch (e) {
      state = AuthError(_mapError(e));
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
      state = AuthError(_mapError(e));
    }
  }

  Future<void> signOut() async {
    state = const AuthLoading();
    try {
      await _repo.signOut();
      await ref.read(sessionStatusProvider.notifier).refresh();
      state = const AuthSuccess();
    } catch (e) {
      state = AuthError(_mapError(e));
    }
  }

  String _mapError(Object e) {
    
    final msg = e.toString().toLowerCase();
    
    if (msg.contains('invalid login')) return 'Email ou password incorretos.';
    if (msg.contains('email already')) return 'Este email já está registado.';
    if (msg.contains('password')) return 'A password deve ter pelo menos 6 caracteres.';
    if (msg.contains('network') || msg.contains('socket')) return 'Sem ligação à internet.';
    debugPrint('AUTH ERROR FULL: $e');
    return 'Ocorreu um erro. Tenta novamente.';
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthControllerState>(AuthController.new);
