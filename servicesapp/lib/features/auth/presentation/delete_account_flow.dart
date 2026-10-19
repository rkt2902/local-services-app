import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../notifications/application/push_notification_service.dart';
import '../application/auth_providers.dart';
import '../application/session_provider.dart';

/// Mensagem quando a base de dados ainda não tem `delete_my_account`
/// (migration 0049 por aplicar).
const _deleteUnavailableMessage =
    'Ainda não é possível eliminar a conta pela app. Tenta mais tarde ou '
    'fala connosco em "Contacto & suporte".';

/// "Eliminar conta" com confirmação em dois passos, partilhado pela conta
/// do cliente e pela do jardineiro.
///
/// 1. Explica o que acontece (dados pessoais apagados, avaliações
///    anónimas, trabalhos em curso primeiro, sem volta atrás).
/// 2. Confirmação final, onde corre o pedido ao servidor. Uma recusa (ex.:
///    trabalho em curso) aparece dentro do próprio diálogo.
///
/// Se correr bem: fecha a sessão neste dispositivo, vai para `/` e avisa.
Future<void> confirmAndDeleteAccount(
    BuildContext context, WidgetRef ref) async {
  final proceed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => const _ExplainDialog(),
  );
  if (proceed != true || !context.mounted) return;

  final deleted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) => _ConfirmDialog(
      onDelete: () => ref.read(authRepositoryProvider).deleteMyAccount(),
    ),
  );
  if (deleted != true || !context.mounted) return;

  // Tudo lido antes dos awaits: ao fechar a sessão o router sai deste ecrã
  // e o `ref` do widget deixa de poder ser usado.
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  final pushService = ref.read(pushNotificationServiceProvider);
  final authRepository = ref.read(authRepositoryProvider);
  final session = ref.read(sessionStatusProvider.notifier);

  // A conta já foi eliminada no servidor: daqui para a frente nada pode
  // impedir a saída. Melhor esforço para limpar o token de push e a sessão.
  try {
    await pushService.unregister();
  } catch (_) {}
  try {
    await authRepository.signOutLocally();
  } catch (_) {}
  try {
    await session.refresh();
  } catch (_) {}

  // T4: navegar, depois SnackBar (os providers dependem do utilizador e
  // reconstroem-se sozinhos com o fim da sessão).
  router.go('/');
  messenger.showSnackBar(
    const SnackBar(content: Text('A tua conta foi eliminada.')),
  );
}

class _ExplainDialog extends StatelessWidget {
  const _ExplainDialog();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const points = [
      'Os teus dados pessoais (nome, telefone e foto) são apagados.',
      'As avaliações que deste e recebeste ficam, mas anónimas.',
      'Trabalhos em curso têm de estar concluídos ou cancelados antes.',
      'Não dá para desfazer.',
    ];
    return AppConfirmDialog(
      icon: Icons.person_off_outlined,
      title: 'Eliminar conta?',
      message: 'Antes de continuares, vê o que acontece:',
      confirmLabel: 'Continuar',
      destructive: true,
      onConfirm: () => Navigator.pop(context, true),
      onCancel: () => Navigator.pop(context, false),
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final point in points) ...[
            if (point != points.first) const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '•',
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    point,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog({required this.onDelete});

  final Future<void> Function() onDelete;

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  bool _deleting = false;
  String? _error;

  Future<void> _delete() async {
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await widget.onDelete();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = rpcErrorMessage(
          e,
          unavailableMessage: _deleteUnavailableMessage,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppConfirmDialog(
      icon: Icons.delete_forever_outlined,
      title: 'Tens a certeza?',
      message: 'A tua conta vai ser eliminada de vez e deixas de conseguir '
          'entrar com este email.',
      confirmLabel: 'Eliminar conta',
      destructive: true,
      isSubmitting: _deleting,
      errorText: _error,
      onConfirm: _delete,
      onCancel: () => Navigator.pop(context, false),
    );
  }
}
