import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/error_utils.dart';
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
Future<void> confirmAndDeleteAccount(BuildContext context, WidgetRef ref) async {
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
    return AlertDialog(
      title: const Text('Eliminar conta?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Antes de continuares, vê o que acontece:',
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            for (final point in points) ...[
              const SizedBox(height: AppSpacing.xs),
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Voltar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(
            foregroundColor: AppStatusColor.cancelled.foreground,
          ),
          child: const Text('Continuar'),
        ),
      ],
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
    final textTheme = Theme.of(context).textTheme;
    final danger = AppStatusColor.cancelled.foreground;
    return AlertDialog(
      title: const Text('Tens a certeza?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A tua conta vai ser eliminada de vez e deixas de conseguir '
            'entrar com este email.',
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: textTheme.bodyMedium?.copyWith(color: danger),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : () => Navigator.pop(context, false),
          child: const Text('Voltar'),
        ),
        FilledButton(
          onPressed: _deleting ? null : _delete,
          style: FilledButton.styleFrom(
            backgroundColor: danger,
            foregroundColor: AppColors.surface,
          ),
          child: _deleting
              ? SizedBox.square(
                  dimension: AppSpacing.md,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: danger,
                  ),
                )
              : const Text('Eliminar conta'),
        ),
      ],
    );
  }
}
