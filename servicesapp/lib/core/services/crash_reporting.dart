import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Relatórios de falhas (Firebase Crashlytics), só em Android/iOS e só
/// quando o Firebase arrancou (ver `PushNotificationService.initFirebase`).
///
/// Em debug não envia nada, para os erros de desenvolvimento não encherem
/// o painel. Só recolhe falhas técnicas (stack trace, modelo e versão do
/// sistema); nada de dados de perfil nem identificador do utilizador.
class CrashReporting {
  CrashReporting._();

  /// Chamar em `main()` depois de `PushNotificationService.initFirebase()`.
  static Future<void> init({required bool firebaseReady}) async {
    if (!firebaseReady) return;
    try {
      final crashlytics = FirebaseCrashlytics.instance;
      await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
      if (kDebugMode) return;

      FlutterError.onError = crashlytics.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        crashlytics.recordError(error, stack, fatal: true);
        return true;
      };
    } catch (e) {
      debugPrint('Crashlytics desligado ($e)');
    }
  }
}
