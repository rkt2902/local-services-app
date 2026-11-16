import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/error_utils.dart';
import '../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../core/widgets/app_filter_chip.dart';
import '../../../../core/widgets/app_inline_error.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/app_status_badge.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../application/admin_labels.dart';
import '../../application/admin_providers.dart';
import '../../data/admin_resolve_models.dart';
import 'admin_panel_widgets.dart';

/// Nota mínima de uma ação (igual à BD).
const adminMinNoteLength = 5;

/// O que o admin escreveu no diálogo de uma ação.
class AdminActionInput {
  const AdminActionInput({
    required this.reason,
    required this.note,
    this.publicMessage,
  });

  /// `null` quando a ação não pede motivo (repor avaliação, dispensar).
  final AdminActionReason? reason;
  final String note;
  final String? publicMessage;
}

/// Diálogo de uma ação de suporte: diz o que acontece e quem é avisado,
/// pede motivo da lista e nota, e corre [onSubmit] lá dentro (o erro do
/// servidor aparece no próprio diálogo). Devolve `true` se a ação correu.
Future<bool> showAdminActionDialog(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String consequence,
  required String confirmLabel,
  required Future<void> Function(AdminActionInput input) onSubmit,
  bool destructive = false,
  bool askReason = true,
  String noteLabel = 'Nota (fica no registo)',
  String? publicMessageLabel,
}) async {
  final done = await showDialog<bool>(
    context: context,
    builder: (_) => AdminActionDialog(
      icon: icon,
      title: title,
      consequence: consequence,
      confirmLabel: confirmLabel,
      destructive: destructive,
      askReason: askReason,
      noteLabel: noteLabel,
      publicMessageLabel: publicMessageLabel,
      onSubmit: onSubmit,
    ),
  );
  return done ?? false;
}

class AdminActionDialog extends StatefulWidget {
  const AdminActionDialog({
    required this.icon,
    required this.title,
    required this.consequence,
    required this.confirmLabel,
    required this.onSubmit,
    this.destructive = false,
    this.askReason = true,
    this.noteLabel = 'Nota (fica no registo)',
    this.publicMessageLabel,
    super.key,
  });

  final IconData icon;
  final String title;
  final String consequence;
  final String confirmLabel;
  final Future<void> Function(AdminActionInput input) onSubmit;
  final bool destructive;
  final bool askReason;
  final String noteLabel;

  /// Com texto, mostra um campo opcional com a mensagem que vai no aviso.
  final String? publicMessageLabel;

  @override
  State<AdminActionDialog> createState() => _AdminActionDialogState();
}

class _AdminActionDialogState extends State<AdminActionDialog> {
  final _note = TextEditingController();
  final _public = TextEditingController();
  AdminActionReason? _reason;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _note.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _note.dispose();
    _public.dispose();
    super.dispose();
  }

  bool get _valid =>
      (!widget.askReason || _reason != null) &&
      _note.text.trim().length >= adminMinNoteLength;

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        AdminActionInput(
          reason: _reason,
          note: _note.text.trim(),
          publicMessage: _public.text.trim().isEmpty
              ? null
              : _public.text.trim(),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppConfirmDialog(
      icon: widget.icon,
      title: widget.title,
      message: widget.consequence,
      destructive: widget.destructive,
      confirmLabel: widget.confirmLabel,
      isSubmitting: _submitting,
      errorText: _error,
      onCancel: () => Navigator.pop(context, false),
      onConfirm: _valid && !_submitting ? _submit : null,
      details: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.askReason) ...[
            Text(
              'Motivo',
              style: textTheme.labelLarge?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final reason in AdminActionReason.values)
                  AppFilterChip(
                    label: reason.label,
                    selected: _reason == reason,
                    onPressed: () => setState(() => _reason = reason),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          AppTextField(
            controller: _note,
            label: widget.noteLabel,
            helperText:
                'Só o suporte vê. $adminMinNoteLength carateres ou mais.',
            maxLength: 1000,
            minLines: 2,
            maxLines: 4,
            textInputAction: TextInputAction.newline,
          ),
          if (widget.publicMessageLabel != null) ...[
            const SizedBox(height: AppSpacing.xs),
            AppTextField(
              controller: _public,
              label: widget.publicMessageLabel!,
              helperText: 'Opcional. Sem texto, vai a mensagem padrão.',
              maxLength: 500,
              minLines: 2,
              maxLines: 3,
              textInputAction: TextInputAction.newline,
            ),
          ],
        ],
      ),
    );
  }
}

/// Selo do prazo (verde, âmbar, vermelho).
class AdminDeadlineBadge extends StatelessWidget {
  const AdminDeadlineBadge({
    required this.dueAt,
    this.closed = false,
    this.dense = true,
    super.key,
  });

  final DateTime? dueAt;
  final bool closed;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tone = adminDeadlineTone(dueAt, closed: closed);
    return AppStatusBadge(
      label: adminDeadlineLabel(dueAt, closed: closed),
      statusColor: adminDeadlineStatusColor(tone),
      dense: dense,
    );
  }
}

/// Diálogo "Abrir caso". Devolve o id do caso criado, ou `null`.
Future<String?> showAdminCreateCaseDialog(
  BuildContext context,
  WidgetRef ref, {
  String? personId,
  String? jobId,
  String? reportId,
  AdminCaseKind initialKind = AdminCaseKind.help,
  String initialSummary = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _CreateCaseDialog(
      repositoryCall:
          ({
            required AdminCaseKind kind,
            required String summary,
            String? contactEmail,
          }) => ref
              .read(adminRepositoryProvider)
              .createCase(
                kind: kind,
                summary: summary,
                personId: personId,
                jobId: jobId,
                reportId: reportId,
                contactEmail: contactEmail,
              ),
      initialKind: initialKind,
      initialSummary: initialSummary,
      askEmail: personId == null && reportId == null,
    ),
  );
}

typedef _CreateCaseCall =
    Future<String> Function({
      required AdminCaseKind kind,
      required String summary,
      String? contactEmail,
    });

class _CreateCaseDialog extends StatefulWidget {
  const _CreateCaseDialog({
    required this.repositoryCall,
    required this.initialKind,
    required this.initialSummary,
    required this.askEmail,
  });

  final _CreateCaseCall repositoryCall;
  final AdminCaseKind initialKind;
  final String initialSummary;
  final bool askEmail;

  @override
  State<_CreateCaseDialog> createState() => _CreateCaseDialogState();
}

class _CreateCaseDialogState extends State<_CreateCaseDialog> {
  late final _summary = TextEditingController(text: widget.initialSummary);
  final _email = TextEditingController();
  late AdminCaseKind _kind = widget.initialKind;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _summary.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _summary.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final id = await widget.repositoryCall(
        kind: _kind,
        summary: _summary.text,
        contactEmail: _email.text,
      );
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppConfirmDialog(
      icon: Icons.support_agent_rounded,
      title: 'Abrir caso de suporte',
      message:
          'O prazo conta a partir de agora: ${_kind.label.toLowerCase()}, '
          '${_kind.deadline}. A confirmação de receção é até ao próximo dia '
          'útil. Ninguém é avisado na app.',
      confirmLabel: 'Abrir caso',
      cancelLabel: 'Voltar',
      isSubmitting: _submitting,
      errorText: _error,
      onCancel: () => Navigator.pop(context),
      onConfirm: _summary.text.trim().isEmpty || _submitting ? null : _submit,
      details: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tipo',
            style: textTheme.labelLarge?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final kind in AdminCaseKind.values)
                AppFilterChip(
                  label: kind.label,
                  selected: _kind == kind,
                  onPressed: () => setState(() => _kind = kind),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: _summary,
            label: 'Resumo',
            hintText: 'O que a pessoa pede, em poucas palavras',
            maxLength: 2000,
            minLines: 2,
            maxLines: 5,
            textInputAction: TextInputAction.newline,
          ),
          if (widget.askEmail) ...[
            const SizedBox(height: AppSpacing.xs),
            AppTextField(
              controller: _email,
              label: 'Email de quem escreveu (opcional)',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
            ),
          ],
        ],
      ),
    );
  }
}

/// Fundo de qualquer ficha (pedido, cliente, jardineiro): casos de
/// suporte ligados e notas internas (só admins veem).
class AdminRecordFooter extends ConsumerWidget {
  const AdminRecordFooter({
    required this.targetId,
    this.personId,
    this.jobId,
    super.key,
  });

  final String targetId;
  final String? personId;
  final String? jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminLinkedCasesCard(
          targetId: targetId,
          personId: personId,
          jobId: jobId,
        ),
        const SizedBox(height: AppSpacing.sm),
        AdminNotesCard(targetId: targetId),
      ],
    );
  }
}

class AdminLinkedCasesCard extends ConsumerWidget {
  const AdminLinkedCasesCard({
    required this.targetId,
    this.personId,
    this.jobId,
    super.key,
  });

  final String targetId;
  final String? personId;
  final String? jobId;

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final id = await showAdminCreateCaseDialog(
      context,
      ref,
      personId: personId,
      jobId: jobId,
    );
    if (id == null || !context.mounted) return;
    context.go('/admin/suporte/$id');
    AppToast.of(context).show('Caso aberto.');
    ref.invalidate(adminCasesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final casesAsync = ref.watch(adminCasesForTargetProvider(targetId));
    return AdminPanelCard(
      title: 'Casos de suporte',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          casesAsync.when(
            loading: () => const SizedBox(
              height: 24,
              child: Center(child: LinearProgressIndicator()),
            ),
            error: (e, _) => AppInlineError(
              message: friendlyError(e),
              onRetry: () =>
                  ref.invalidate(adminCasesForTargetProvider(targetId)),
            ),
            data: (cases) => cases.isEmpty
                ? Text(
                    'Nenhum caso.',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  )
                : Column(
                    children: [
                      for (final c in cases)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: AdminCaseRowCard(
                            row: c,
                            onPressed: () =>
                                context.go('/admin/suporte/${c.caseId}'),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton.icon(
            onPressed: () => _create(context, ref),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Abrir caso'),
          ),
        ],
      ),
    );
  }
}

/// Linha de um caso (Caixa de suporte e fundo das fichas).
class AdminCaseRowCard extends StatelessWidget {
  const AdminCaseRowCard({
    required this.row,
    required this.onPressed,
    this.selected = false,
    super.key,
  });

  final AdminCaseRow row;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final awaitingAck = row.firstReplyAt == null && !row.closed;
    return AdminListTileCard(
      selected: selected,
      onPressed: onPressed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '#${row.number} · ${row.kind?.label ?? row.kindValue}',
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              AdminDeadlineBadge(dueAt: row.nextDueAt, closed: row.closed),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            row.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            [
              row.status.label,
              if (awaitingAck) 'sem resposta ainda',
              if (row.personName != null) row.personName!,
              adminDateTimeLabel(row.createdAt),
            ].join(' · '),
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Notas internas de uma ficha, com campo para escrever outra.
class AdminNotesCard extends ConsumerStatefulWidget {
  const AdminNotesCard({required this.targetId, super.key});

  final String targetId;

  @override
  ConsumerState<AdminNotesCard> createState() => _AdminNotesCardState();
}

class _AdminNotesCardState extends ConsumerState<AdminNotesCard> {
  final _body = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _body.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(adminRepositoryProvider)
          .addNote(widget.targetId, _body.text);
      if (!mounted) return;
      _body.clear();
      AppToast.of(context).show('Nota guardada.');
      ref.invalidate(adminNotesProvider(widget.targetId));
    } catch (e) {
      if (mounted) AppToast.of(context).show(friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(adminNotesProvider(widget.targetId));
    return AdminPanelCard(
      title: 'Notas internas',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          notesAsync.when(
            loading: () => const SizedBox(
              height: 24,
              child: Center(child: LinearProgressIndicator()),
            ),
            error: (e, _) => AppInlineError(
              message: friendlyError(e),
              onRetry: () =>
                  ref.invalidate(adminNotesProvider(widget.targetId)),
            ),
            data: (notes) => AdminNotesList(notes: notes),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: _body,
            label: 'Nova nota (só o suporte vê)',
            maxLength: 4000,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.newline,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: _body.text.trim().isEmpty || _saving ? null : _save,
              child: const Text('Guardar nota'),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminNotesList extends StatelessWidget {
  const AdminNotesList({required this.notes, super.key});

  final List<AdminNote> notes;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (notes.isEmpty) {
      return Text(
        'Sem notas.',
        style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, n) in notes.indexed)
          AppStaggeredEntrance(
            index: i < 6 ? i : 6,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.body,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    '${adminDateTimeLabel(n.createdAt)}'
                    '${n.authorEmail == null ? '' : ' · ${n.authorEmail}'}',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
