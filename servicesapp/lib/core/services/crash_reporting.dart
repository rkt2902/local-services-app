import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import '../utils/app_log.dart';

/// Envia os erros não tratados para o Firebase Crashlytics (AUD-07,
/// auditoria de 13/11). Antes, um crash num telemóvel ficava invisível.
///
/// - Só recolhe em release; em debug e profile os erros ficam na consola.
/// - Só corre quando o Firebase arrancou (Android e iOS com o
///   `google-services.json` / `GoogleService-Info.plist`); na web não faz
///   nada.
/// - Não envia o id, o nome nem o email da pessoa: só o erro e a stack.
abstract final class CrashReporting {
  static bool _enabled = false;

  /// Chamar em `main()` depois de `PushNotificationService.initFirebase()`.
  static Future<void> init({required bool firebaseReady}) async {
    if (!firebaseReady || kIsWeb) return;
    try {
      final crashlytics = FirebaseCrashlytics.instance;
      await crashlytics.setCrashlyticsCollectionEnabled(kReleaseMode);
      if (!kReleaseMode) return;
      _enabled = true;

      final previousFlutterHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        previousFlutterHandler?.call(details);
        crashlytics.recordFlutterFatalError(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        crashlytics.recordError(error, stack, fatal: true);
        return true;
      };
    } catch (e) {
      appLog('Crashlytics desligado ($e)');
    }
  }

  /// Regista um erro apanhado que não deve acontecer (não fatal).
  static void recordNonFatal(Object error, StackTrace stack, {String? reason}) {
    if (!_enabled) return;
    FirebaseCrashlytics.instance.recordError(error, stack, reason: reason);
  }
}
