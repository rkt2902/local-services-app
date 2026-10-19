import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_status_color.dart';
import '../application/auth_controller.dart';
import '../../../core/widgets/app_confirm_dialog.dart';

/// Terminar sessão com confirmação: pergunta primeiro, chama
/// `AuthController.signOut` e só sai para `/` se correu bem. Se falhar
/// (ex.: sem rede), mostra o erro e deixa o utilizador onde estava, em vez
/// de navegar como se tivesse saído.
///
/// Partilhado pela conta do cliente, pelo perfil do cliente e por
/// `/choose-role`.
Future<void> confirmAndSignOut(BuildContext context, WidgetRef ref) async {
  final confirmed = await AppConfirmDialog.show(
    context,
    icon: null,
    title: 'Terminar sessão?',
    message: 'Vais precisar do teu email e senha para voltar a entrar.',
    confirmLabel: 'Terminar sessão',
    destructive: true,
  );
  if (confirmed != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  await ref.read(authControllerProvider.notifier).signOut();
  final result = ref.read(authControllerProvider);
  if (result is AuthError) {
    messenger.showSnackBar(SnackBar(
      content: Text('Não foi possível terminar a sessão. ${result.message}'),
      backgroundColor: AppStatusColor.cancelled.foreground,
    ));
    return;
  }
  router.go('/');
}
