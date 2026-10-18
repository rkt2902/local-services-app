import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_system_state_screen.dart';
import '../application/session_provider.dart';
import 'sign_out_flow.dart';

/// Rota `/session-error`: há sessão mas o perfil não se conseguiu ler
/// (tipicamente sem rede). Antes caía em `/choose-role` como se fosse uma
/// conta nova, com risco de reescrever o perfil. "Tentar novamente" volta a
/// ler a sessão; quando der, o router leva ao início do papel.
class SessionErrorScreen extends ConsumerWidget {
  const SessionErrorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRetrying = ref.watch(sessionStatusProvider).isLoading;
    return AppSystemStateScreen.noInternet(
      message: 'Não foi possível carregar a tua conta. Verifica a ligação '
          'e tenta novamente.',
      isRetrying: isRetrying,
      onRetry: () => ref.read(sessionStatusProvider.notifier).refresh(),
      secondaryActionLabel: 'Terminar sessão',
      onSecondaryAction: () => confirmAndSignOut(context, ref),
    );
  }
}
