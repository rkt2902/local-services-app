import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/enums.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../application/admin_labels.dart';
import '../../application/admin_providers.dart';
import '../../data/admin_repository.dart';
import '../../data/admin_support_models.dart';
import 'admin_action_dialogs.dart';
import 'admin_panel_widgets.dart';

/// Ações que o suporte pode fazer num pedido com este estado.
enum AdminJobAction {
  cancel('Cancelar pedido', Icons.event_busy_outlined),
  reopen('Reabrir por 48 horas', Icons.restart_alt_rounded),
  complete('Marcar como concluído', Icons.task_alt_rounded),
  undoConfirmation('Anular a confirmação', Icons.undo_rounded);

  const AdminJobAction(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Mesmas regras das RPCs da 0079 (a BD volta a verificar).
List<AdminJobAction> adminJobActionsFor(JobStatus? status) => switch (status) {
  JobStatus.open => const [AdminJobAction.cancel],
  JobStatus.confirmed || JobStatus.awaitingConfirmation => const [
    AdminJobAction.complete,
    AdminJobAction.cancel,
  ],
  JobStatus.completed => const [AdminJobAction.undoConfirmation],
  JobStatus.noResponse => const [AdminJobAction.reopen],
  JobStatus.cancelled || null => const [],
};

/// Cartão "Ações do suporte" na ficha do pedido: botões pelo estado e as
/// avaliações do trabalho, com "Ocultar".
class AdminJobActionsCard extends ConsumerWidget {
  const AdminJobActionsCard({required this.job, super.key});

  final AdminJobDetail job;

  String get _client => job.client?.fullName ?? 'o cliente';
  String get _worker => job.worker?.fullName ?? 'o jardineiro';

  String _consequence(AdminJobAction action) => switch (action) {
    AdminJobAction.cancel =>
      'O pedido fica cancelado pelo suporte. Propostas pendentes recusadas, '
          'equipa de ajudantes cancelada. Recebem aviso: $_client'
          '${job.worker == null ? '' : ' e $_worker'}'
          '${job.team.isEmpty ? '' : ', e os ajudantes'}.',
    AdminJobAction.reopen =>
      'O pedido volta a estar aberto a propostas durante 48 horas, visível '
          'a todos os jardineiros da zona. Uma data fixa que já passou fica '
          'a combinar. Recebe aviso: $_client.',
    AdminJobAction.complete =>
      'O trabalho fica concluído, como se $_client tivesse confirmado. '
          'Recebem aviso: $_client e $_worker.',
    AdminJobAction.undoConfirmation =>
      'O trabalho volta a "à espera de confirmação" e $_client tem 7 dias '
          'novos para confirmar ou relatar um problema. Recebem aviso: '
          '$_client e $_worker.',
  };

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    AdminJobAction action,
  ) async {
    AdminRepository repo() => ref.read(adminRepositoryProvider);
    final done = await showAdminActionDialog(
      context,
      icon: action.icon,
      title: action.label,
      consequence: _consequence(action),
      confirmLabel: action.label,
      destructive: action == AdminJobAction.cancel,
      publicMessageLabel: action == AdminJobAction.cancel
          ? 'Mensagem no aviso aos dois'
          : null,
      onSubmit: (input) => switch (action) {
        AdminJobAction.cancel => repo().cancelJob(
          job.jobId,
          reason: input.reason!,
          note: input.note,
          publicMessage: input.publicMessage,
        ),
        AdminJobAction.reopen => repo().reopenJob(
          job.jobId,
          reason: input.reason!,
          note: input.note,
        ),
        AdminJobAction.complete => repo().setJobStatus(
          job.jobId,
          status: 'completed',
          reason: input.reason!,
          note: input.note,
        ),
        AdminJobAction.undoConfirmation => repo().setJobStatus(
          job.jobId,
          status: 'awaiting_confirmation',
          reason: input.reason!,
          note: input.note,
        ),
      },
    );
    if (!done || !context.mounted) return;
    AppToast.of(context).show('Feito. Ficou no registo.');
    ref.invalidate(adminJobDetailProvider(job.jobId));
    ref.invalidate(adminJobsProvider);
  }

  Future<void> _hideRating(
    BuildContext context,
    WidgetRef ref,
    AdminRatingItem rating,
  ) async {
    final done = await showAdminActionDialog(
      context,
      icon: Icons.visibility_off_outlined,
      title: 'Ocultar avaliação',
      consequence:
          'Deixa de aparecer na app e de contar para a média. Não se apaga: '
          'podes repor em Avaliações. ${rating.personName ?? 'Quem avaliou'} '
          'recebe um aviso com o motivo e como contestar.',
      confirmLabel: 'Ocultar',
      destructive: true,
      onSubmit: (input) => ref
          .read(adminRepositoryProvider)
          .hideRating(rating.id!, reason: input.reason!, note: input.note),
    );
    if (!done || !context.mounted) return;
    AppToast.of(context).show('Avaliação ocultada.');
    ref.invalidate(adminJobDetailProvider(job.jobId));
    ref.invalidate(adminRatingsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final actions = adminJobActionsFor(job.status);
    final ratings = job.ratings.where((r) => r.id != null).toList();
    return AdminPanelCard(
      title: 'Ações do suporte',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (actions.isEmpty)
            Text(
              'Este pedido está fechado. Não há ações de estado.',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          else
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final action in actions)
                  OutlinedButton.icon(
                    onPressed: () => _run(context, ref, action),
                    icon: Icon(action.icon, size: 18),
                    label: Text(action.label),
                  ),
              ],
            ),
          if (ratings.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Avaliações deste trabalho',
              style: textTheme.labelLarge?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            for (final r in ratings)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        '${'★' * r.stars} · ${r.personName ?? 'Sem nome'} · '
                        '${adminDateLabel(r.createdAt)}'
                        '${r.comment == null ? '' : '\n"${r.comment}"'}',
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _hideRating(context, ref, r),
                    child: const Text('Ocultar'),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
