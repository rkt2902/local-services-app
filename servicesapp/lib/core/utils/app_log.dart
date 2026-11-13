import 'package:flutter/foundation.dart';

/// Registo de diagnóstico só para builds de debug (AUD-22). Em release não
/// escreve nada no logcat: as mensagens podem levar moradas, emails ou
/// detalhes de erros do servidor. Os erros que interessam em produção vão
/// para o Crashlytics (ver `crash_reporting.dart`).
void appLog(String message) {
  if (kDebugMode) debugPrint(message);
}
