import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/device_token_repository.dart';

/// Notificações push via Firebase Cloud Messaging.
///
/// O envio é feito no servidor: cada INSERT em `notifications` dispara a
/// Edge Function `send-push` (migration 0040). Aqui só se regista o token
/// do dispositivo para o utilizador com sessão e se trata o toque na
/// notificação.
///
/// Com a app em primeiro plano o sistema não mostra o push (Android) — o
/// badge/lista in-app já é atualizado pelo stream Realtime, por isso não há
/// notificação local duplicada.
///
/// Sem `google-services.json` / `GoogleService-Info.plist` o Firebase não
/// inicializa e tudo isto fica desligado (a app continua a funcionar).
///
/// Usa a API de tokens FCM (`getToken`/`onTokenRefresh`), marcada como
/// deprecated no firebase_messaging 17 a favor da nova API por FID
/// (`register`/`onRegistered`). Continua suportada e é a que a Edge Function
/// usa (campo `token` do FCM HTTP v1); migrar quando a API FID estabilizar.
// ignore_for_file: deprecated_member_use
class PushNotificationService {
  final DeviceTokenRepository _repo;
  PushNotificationService(this._repo);

  static bool _firebaseReady = false;

  /// false sem configuração do Firebase (ou fora de Android/iOS).
  static bool get isEnabled => _firebaseReady;

  static bool get _supportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Chamar em `main()` antes de `runApp`.
  static Future<void> initFirebase() async {
    if (!_supportedPlatform) return;
    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
    } catch (e) {
      debugPrint('Push desligado: Firebase não configurado ($e)');
    }
  }

  StreamSubscription<String>? _tokenRefreshSub;
  String? _registeredToken;

  String get _platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  /// Pede permissão e associa o token deste dispositivo ao utilizador atual.
  Future<void> registerForCurrentUser() async {
    if (!_firebaseReady) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await messaging.getToken();
      if (token != null) await _save(token);
      _tokenRefreshSub ??= messaging.onTokenRefresh.listen(_save);
    } catch (e) {
      debugPrint('Push: falha a registar token ($e)');
    }
  }

  Future<void> _save(String token) async {
    await _repo.register(token, _platform);
    _registeredToken = token;
  }

  /// Chamar no logout, ANTES de terminar a sessão (a RPC precisa de auth).
  Future<void> unregister() async {
    if (!_firebaseReady) return;
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    try {
      final messaging = FirebaseMessaging.instance;
      final token = _registeredToken ?? await messaging.getToken();
      if (token != null) await _repo.unregister(token);
      await messaging.deleteToken();
    } catch (e) {
      debugPrint('Push: falha a remover token ($e)');
    }
    _registeredToken = null;
  }

  /// Ids de `notifications` cujo push foi tocado — tanto com a app em
  /// background como a abrir a app a partir do push (cold start).
  Stream<String> openedNotificationIds() async* {
    if (!_firebaseReady) return;
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    final initialId = _idOf(initial);
    if (initialId != null) yield initialId;
    yield* FirebaseMessaging.onMessageOpenedApp
        .map(_idOf)
        .where((id) => id != null)
        .cast<String>();
  }

  static String? _idOf(RemoteMessage? message) {
    final id = message?.data['notification_id'];
    return (id is String && id.isNotEmpty) ? id : null;
  }
}

final deviceTokenRepositoryProvider = Provider<DeviceTokenRepository>(
  (ref) => DeviceTokenRepository(ref.watch(supabaseClientProvider)),
);

final pushNotificationServiceProvider = Provider<PushNotificationService>(
  (ref) => PushNotificationService(ref.watch(deviceTokenRepositoryProvider)),
);
