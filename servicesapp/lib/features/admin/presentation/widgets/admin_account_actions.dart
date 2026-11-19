import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/utils/error_utils.dart';
import '../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../core/widgets/app_inline_error.dart';
import '../../../../core/widgets/app_status_badge.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../application/admin_labels.dart';
import '../../application/admin_providers.dart';
import '../../data/admin_account_models.dart';
import '../../data/admin_resolve_models.dart';
import 'admin_action_dialogs.dart';
import 'admin_file_share.dart';
import 'admin_panel_widgets.dart';
import 'admin_stat_widgets.dart';

/// Cartão "Conta" na ficha do cliente e do jardineiro (fase C, 0080):
/// estado, email, fotos de perfil e as ações sobre a conta. Cada ação
/// pede nota (e motivo, quando muda o que a pessoa pode fazer) e fica no
/// Registo; a BD recusa tudo a quem não é admin com segundo fator.
class AdminAccountCard extends ConsumerWidget {
  const AdminAccountCard({required this.personId, super.key});

  final String personId;

  void _refresh(WidgetRef ref) {
    ref.invalidate(adminAccountProvider(personId));
    ref.invalidate(adminClientDetailProvider(personId));
    ref.invalidate(adminWorkerDetailProvider(personId));
    ref.invalidate(adminActionsProvider);
  }

  Future<void> _suspend(
    BuildContext context,
    WidgetRef ref,
    AdminAccountState a,
  ) async {
    var open = 0;
    final done = await showAdminActionDialog(
      context,
      icon: Icons.block_rounded,
      title: 'Suspender conta',
      consequence: [
        'A pessoa deixa de poder pedir, propor ou ajudar e passa a ver o '
            'ecrã "Conta suspensa". Pedidos abertos dela fecham, propostas '
            'pendentes saem e pedidos diretos à espera dela libertam-se.',
        if (a.jobsInProgress > 0)
          'Tem ${a.jobsInProgress} trabalho(s) aceite(s): ficam como estão; '
              'decide cada um na ficha do pedido.',
        if (a.role == 'worker')
          'Profissional com plano pago: salvo infração grave, usa antes o '
              'aviso de 30 dias (P2B).',
      ].join(' '),
      confirmLabel: 'Suspender',
      destructive: true,
      publicMessageLabel: 'Mensagem para a pessoa (ecrã e aviso na app)',
      onSubmit: (input) async {
        open = await ref
            .read(adminRepositoryProvider)
            .suspendUser(
              personId,
              reason: input.reason!,
              note: input.note,
              publicMessage: input.publicMessage,
            );
      },
    );
    if (!done || !context.mounted) return;
    AppToast.of(context).show(
      open > 0
          ? 'Conta suspensa. Ficaram $open trabalho(s) aceite(s) por decidir.'
          : 'Conta suspensa.',
    );
    _refresh(ref);
  }

  Future<void> _reactivate(BuildContext context, WidgetRef ref) async {
    final done = await showAdminActionDialog(
      context,
      icon: Icons.lock_open_rounded,
      title: 'Reativar conta',
      consequence:
          'A pessoa volta a usar a app normalmente e recebe um aviso. Os '
          'pedidos e propostas fechados na suspensão não voltam.',
      confirmLabel: 'Reativar',
      askReason: false,
      noteLabel: 'Porquê (fica no registo)',
      onSubmit: (input) => ref
          .read(adminRepositoryProvider)
          .reactivateUser(personId, note: input.note),
    );
    if (!done || !context.mounted) return;
    AppToast.of(context).show('Conta reativada.');
    _refresh(ref);
  }

  Future<void> _scheduleClosure(BuildContext context, WidgetRef ref) async {
    DateTime? at;
    final done = await showAdminActionDialog(
      context,
      icon: Icons.event_busy_rounded,
      title: 'Aviso de encerramento (30 dias)',
      consequence:
          'A pessoa recebe hoje um aviso na app com a data e a mensagem. Até '
          'lá usa a app normalmente; na data a conta fica suspensa sozinha. '
          'Envia também o email com os motivos: o painel não envia emails.',
      confirmLabel: 'Marcar encerramento',
      destructive: true,
      publicMessageLabel: 'Motivo para a pessoa (vai no aviso)',
      onSubmit: (input) async {
        at = await ref
            .read(adminRepositoryProvider)
            .scheduleClosure(
              personId,
              reason: input.reason!,
              note: input.note,
              publicMessage: input.publicMessage,
            );
      },
    );
    if (!done || !context.mounted) return;
    AppToast.of(
      context,
    ).show('Encerramento marcado para ${adminDateLabel(at)}.');
    _refresh(ref);
  }

  Future<void> _cancelClosure(BuildContext context, WidgetRef ref) async {
    final done = await showAdminActionDialog(
      context,
      icon: Icons.event_available_rounded,
      title: 'Cancelar encerramento',
      consequence: 'A conta continua ativa e a pessoa recebe um aviso.',
      confirmLabel: 'Cancelar encerramento',
      askReason: false,
      noteLabel: 'Porquê (fica no registo)',
      onSubmit: (input) => ref
          .read(adminRepositoryProvider)
          .cancelClosure(personId, note: input.note),
    );
    if (!done || !context.mounted) return;
    AppToast.of(context).show('Encerramento cancelado.');
    _refresh(ref);
  }

  Future<void> _resendCode(
    BuildContext context,
    WidgetRef ref,
    AdminAccountState a,
  ) async {
    final ok = await AppConfirmDialog.show(
      context,
      icon: Icons.mark_email_unread_outlined,
      title: 'Reenviar código?',
      message:
          'Vai um email novo com o código de confirmação para '
          '${a.emailMasked ?? 'o email da conta'}. Fica no registo.',
      confirmLabel: 'Reenviar',
    );
    if (ok != true || !context.mounted) return;
    final toast = AppToast.of(context);
    try {
      await ref.read(adminRepositoryProvider).resendConfirmationCode(personId);
      toast.show('Código reenviado.');
    } catch (e) {
      toast.error(friendlyError(e));
    }
    ref.invalidate(adminActionsProvider);
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final toast = AppToast.of(context);
    try {
      final data = await ref
          .read(adminRepositoryProvider)
          .exportUserData(personId);
      final text = const JsonEncoder.withIndent('  ').convert(data);
      final name = adminExportFileName(personId, DateTime.now());
      final shared = await adminShareTextFile(
        name: name,
        mimeType: 'application/json',
        text: text,
      );
      toast.show(
        shared
            ? 'Dados exportados. Envia o ficheiro à pessoa por email.'
            // Sem folha de partilha (alguns browsers): ficou no clipboard.
            : 'Dados copiados. Cola num ficheiro $name.',
      );
    } catch (e) {
      toast.error(friendlyError(e));
    }
    ref.invalidate(adminActionsProvider);
  }

  Future<void> _erase(
    BuildContext context,
    WidgetRef ref,
    AdminAccountState a,
  ) async {
    AdminErasedFiles? files;
    final done = await showAdminActionDialog(
      context,
      icon: Icons.delete_forever_outlined,
      title: 'Eliminar conta a pedido',
      consequence:
          'O mesmo que "Eliminar conta" na app: apaga nome, telefone, fotos '
          'e textos, cancela pedidos abertos, retira propostas e bloqueia o '
          'email 90 dias. As avaliações ficam como "Conta eliminada". Não dá '
          'para desfazer. Se a pessoa pediu os dados, exporta primeiro.',
      confirmLabel: 'Eliminar conta',
      destructive: true,
      askReason: false,
      noteLabel: 'Pedido: quem pediu, quando e por onde',
      onSubmit: (input) async {
        files = await ref
            .read(adminRepositoryProvider)
            .eraseUser(personId, note: input.note);
      },
    );
    if (!done || !context.mounted) return;
    final erased = files;
    if (erased != null) {
      await showDialog<void>(
        context: context,
        builder: (_) => AdminErasedFilesDialog(files: erased),
      );
    }
    if (!context.mounted) return;
    AppToast.of(context).show('Conta eliminada.');
    _refresh(ref);
  }

  Future<void> _hidePhoto(
    BuildContext context,
    WidgetRef ref,
    String url, {
    required bool avatar,
  }) async {
    final done = await showAdminActionDialog(
      context,
      icon: Icons.hide_image_outlined,
      title: avatar ? 'Retirar foto de perfil' : 'Retirar foto do perfil',
      consequence:
          'A foto sai do perfil e fica guardada à parte (com o motivo). A '
          'pessoa recebe um aviso e pode pôr outra.',
      confirmLabel: 'Retirar',
      destructive: true,
      onSubmit: (input) => ref
          .read(adminRepositoryProvider)
          .hideProfilePhoto(
            personId,
            url: url,
            reason: input.reason!,
            note: input.note,
          ),
    );
    if (!done || !context.mounted) return;
    AppToast.of(context).show('Foto retirada.');
    _refresh(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(adminAccountProvider(personId));
    return accountAsync.when(
      loading: () => const AdminLoadingBlocks(count: 1, height: 140),
      error: (e, _) => AdminPanelCard(
        title: 'Conta',
        child: AppInlineError(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(adminAccountProvider(personId)),
        ),
      ),
      data: (a) => AdminAccountView(
        account: a,
        onSuspend: () => _suspend(context, ref, a),
        onReactivate: () => _reactivate(context, ref),
        onScheduleClosure: () => _scheduleClosure(context, ref),
        onCancelClosure: () => _cancelClosure(context, ref),
        onResendCode: () => _resendCode(context, ref, a),
        onExport: () => _export(context, ref),
        onErase: () => _erase(context, ref, a),
        onHidePhoto: (url, {required avatar}) =>
            _hidePhoto(context, ref, url, avatar: avatar),
      ),
    );
  }
}

/// "projardim-dados-4f8f1350-2026-11-16.json".
String adminExportFileName(String personId, DateTime now) {
  final id = personId.length > 8 ? personId.substring(0, 8) : personId;
  final d = now.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return 'projardim-dados-$id-${d.year}-${two(d.month)}-${two(d.day)}.json';
}

typedef AdminHidePhotoCallback =
    void Function(String url, {required bool avatar});

/// Vista pura do cartão "Conta". Mostra só as ações que fazem sentido no
/// estado atual (a BD recusa as outras de qualquer forma).
class AdminAccountView extends StatelessWidget {
  const AdminAccountView({
    required this.account,
    required this.onSuspend,
    required this.onReactivate,
    required this.onScheduleClosure,
    required this.onCancelClosure,
    required this.onResendCode,
    required this.onExport,
    required this.onErase,
    required this.onHidePhoto,
    super.key,
  });

  final AdminAccountState account;
  final VoidCallback onSuspend;
  final VoidCallback onReactivate;
  final VoidCallback onScheduleClosure;
  final VoidCallback onCancelClosure;
  final VoidCallback onResendCode;
  final VoidCallback onExport;
  final VoidCallback onErase;
  final AdminHidePhotoCallback onHidePhoto;

  @override
  Widget build(BuildContext context) {
    final a = account;
    final textTheme = Theme.of(context).textTheme;
    final (statusLabel, statusColor) = adminAccountStatus(a);
    final secondary = textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondary,
    );
    final canAct = !a.isDeleted && !a.isAdmin;

    return AdminPanelCard(
      title: 'Conta',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              AppStatusBadge(
                label: statusLabel,
                statusColor: statusColor,
                dense: true,
              ),
              if (a.isAdmin)
                const AppStatusBadge(
                  label: 'Admin',
                  statusColor: AppStatusColor.info,
                  dense: true,
                ),
            ],
          ),
          if (a.isSuspended) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Motivo: ${AdminActionReason.labelOf(a.suspendedReason)}',
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            if (a.suspendedMessage != null)
              Text('Mensagem: "${a.suspendedMessage}"', style: secondary),
          ],
          if (a.hasClosing) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Motivo: ${AdminActionReason.labelOf(a.closingReason)}. Na data '
              'a conta fica suspensa sozinha.',
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            if (a.closingMessage != null)
              Text('Mensagem: "${a.closingMessage}"', style: secondary),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            [
              if (a.emailMasked != null)
                'Email ${a.emailMasked}'
                    '${a.emailConfirmed == false ? ' (por confirmar)' : ''}',
              'último acesso ${adminRelativeDateLabel(a.lastSignInAt)}',
              '${a.jobsInProgress} trabalho(s) aceite(s) em curso',
            ].join(' · '),
            style: secondary,
          ),
          if (a.avatarUrl != null || a.portfolio.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (a.avatarUrl != null)
                  _ProfilePhoto(
                    url: a.avatarUrl!,
                    label: 'Foto de perfil',
                    onHide: canAct
                        ? () => onHidePhoto(a.avatarUrl!, avatar: true)
                        : null,
                  ),
                for (final url in a.portfolio)
                  _ProfilePhoto(
                    url: url,
                    label: 'Portefólio',
                    onHide: canAct
                        ? () => onHidePhoto(url, avatar: false)
                        : null,
                  ),
              ],
            ),
          ],
          if (canAct) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                if (a.isSuspended)
                  TextButton.icon(
                    onPressed: onReactivate,
                    icon: const Icon(
                      Icons.lock_open_rounded,
                      size: AppSizes.inlineIcon,
                    ),
                    label: const Text('Reativar'),
                  )
                else
                  TextButton.icon(
                    onPressed: onSuspend,
                    icon: const Icon(
                      Icons.block_rounded,
                      size: AppSizes.inlineIcon,
                    ),
                    label: const Text('Suspender'),
                  ),
                if (a.hasClosing)
                  TextButton.icon(
                    onPressed: onCancelClosure,
                    icon: const Icon(
                      Icons.event_available_rounded,
                      size: AppSizes.inlineIcon,
                    ),
                    label: const Text('Cancelar encerramento'),
                  )
                else if (!a.isSuspended)
                  TextButton.icon(
                    onPressed: onScheduleClosure,
                    icon: const Icon(
                      Icons.event_busy_rounded,
                      size: AppSizes.inlineIcon,
                    ),
                    label: const Text('Encerrar em 30 dias'),
                  ),
                if (a.emailConfirmed == false)
                  TextButton.icon(
                    onPressed: onResendCode,
                    icon: const Icon(
                      Icons.mark_email_unread_outlined,
                      size: AppSizes.inlineIcon,
                    ),
                    label: const Text('Reenviar código'),
                  ),
                TextButton.icon(
                  onPressed: onExport,
                  icon: const Icon(
                    Icons.download_rounded,
                    size: AppSizes.inlineIcon,
                  ),
                  label: const Text('Exportar dados'),
                ),
                TextButton.icon(
                  onPressed: a.deletionBlocker == null ? onErase : null,
                  icon: const Icon(
                    Icons.delete_forever_outlined,
                    size: AppSizes.inlineIcon,
                  ),
                  label: const Text('Eliminar a pedido'),
                ),
              ],
            ),
            if (a.deletionBlocker != null)
              Text('Para eliminar: ${a.deletionBlocker}', style: secondary),
          ] else if (a.isDeleted) ...[
            const SizedBox(height: AppSpacing.xs),
            TextButton.icon(
              onPressed: onExport,
              icon: const Icon(
                Icons.download_rounded,
                size: AppSizes.inlineIcon,
              ),
              label: const Text('Exportar o que resta'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfilePhoto extends StatelessWidget {
  const _ProfilePhoto({required this.url, required this.label, this.onHide});

  final String url;
  final String label;
  final VoidCallback? onHide;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      width: AppSizes.adminProfilePhoto,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.input),
            child: Image.network(
              url,
              width: AppSizes.adminProfilePhoto,
              height: AppSizes.adminProfilePhoto,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: AppSizes.adminProfilePhoto,
                height: AppSizes.adminProfilePhoto,
                color: AppColors.divider,
                child: const Icon(
                  Icons.broken_image_outlined,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (onHide != null)
            TextButton(onPressed: onHide, child: const Text('Retirar')),
        ],
      ),
    );
  }
}

/// Depois de eliminar: os ficheiros no Storage que ficam para apagar à mão
/// (Supabase > Storage). A lista também fica no Registo.
class AdminErasedFilesDialog extends StatelessWidget {
  const AdminErasedFilesDialog({required this.files, super.key});

  final AdminErasedFiles files;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final text = files.asText;
    return AlertDialog(
      title: const Text('Conta eliminada'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Falta apagar os ficheiros no Supabase (Storage). A base de '
              'dados não os consegue apagar; a lista também fica no Registo.',
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SelectableText(
              text,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (context.mounted) AppToast.of(context).show('Lista copiada.');
          },
          child: const Text('Copiar lista'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
