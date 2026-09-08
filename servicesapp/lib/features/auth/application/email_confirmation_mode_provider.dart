import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Só `true` em builds de debug — gate para atalhos de desenvolvimento do
/// fluxo de confirmação de email (ex.: botão "Simular confirmação" em
/// `verify_email_screen.dart`), que evitam depender de SMTP configurado
/// para testar o visual do fluxo completo. Mesmo padrão de
/// `kDebugMode`-gate já usado no bypass de `AuthRepository.
/// verifyPasswordResetOtp` / `PasswordResetController` para o fluxo de
/// recuperação de senha — aqui como provider próprio porque não há
/// nenhuma chamada de rede a interceptar, é só um atalho de navegação.
final emailConfirmationModeProvider = Provider<bool>((ref) => kDebugMode);
