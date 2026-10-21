import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../notifications/application/push_notification_service.dart';
import '../application/auth_providers.dart';
import '../application/session_provider.dart';
import '../../../core/widgets/app_toast.dart';

/// Mensagem quando a base de dados ainda não tem `delete_my_account`
/// (migration 0049 por aplicar).
const _deleteUnavailableMessage =
    'Ainda não é possível eliminar a conta pela app. Tenta mais tarde ou '
    'fala connosco em "Contacto e suporte".';

/// "Eliminar conta" com confirmação em dois passos, partilhado pela conta
/// do cliente e pela do jardineiro.
///
/// 1. Explica o que acontece (dados pessoais apagados, avaliações como
///    "Conta eliminada", trabalhos em curso primeiro).
/// 2. Confirmação final ("Não dá para desfazer."), onde corre o pedido ao servidor. Uma recusa (ex.:
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
  final toast = AppToast.of(context);
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
  toast.show('A tua conta foi eliminada.');
}

class _ExplainDialog extends StatelessWidget {
  const _ExplainDialog();

  @override
  Widget build(BuildContext context) {
    // O que `delete_my_account` (0049) faz: anonimiza o perfil, o nome
    // passa a "Conta eliminada" e recusa se houver trabalhos em curso.
    return AppConfirmDialog(
      icon: null,
      title: 'Eliminar conta?',
      stepLabel: '1/2',
      confirmLabel: 'Continuar',
      destructive: true,
      outlinedConfirm: true,
      onConfirm: () => Navigator.pop(context, true),
      onCancel: () => Navigator.pop(context, false),
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ImpactRow(
            icon: Icons.delete_outline_rounded,
            color: AppStatusColor.cancelled.foreground,
            label: 'Os teus dados pessoais são apagados.',
          ),
          const SizedBox(height: AppSpacing.sm),
          _ImpactRow(
            icon: Icons.visibility_off_outlined,
            color: AppStatusColor.neutral.foreground,
            label: 'As avaliações ficam como "Conta eliminada".',
          ),
          const SizedBox(height: AppSpacing.sm),
          _ImpactRow(
            icon: Icons.pending_actions_outlined,
            color: AppStatusColor.waiting.foreground,
            label: 'Os trabalhos em curso têm de estar fechados.',
          ),
        ],
      ),
    );
  }
}

class _ImpactRow extends StatelessWidget {
  const _ImpactRow({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: AppSizes.inlineIcon, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
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
    return AppConfirmDialog(
      icon: null,
      title: 'Tens a certeza?',
      stepLabel: '2/2',
      message: 'Não dá para desfazer.',
      confirmLabel: 'Eliminar conta',
      destructive: true,
      isSubmitting: _deleting,
      errorText: _error,
      onConfirm: _delete,
      onCancel: () => Navigator.pop(context, false),
    );
  }
}
