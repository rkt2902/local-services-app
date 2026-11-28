import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_filter_chip.dart';
import '../../../core/widgets/app_inline_error.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/app_status_badge.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../application/admin_labels.dart';
import '../application/admin_providers.dart';
import '../data/admin_invite_models.dart';
import '../data/admin_invite_templates.dart';
import 'widgets/admin_invite_preview.dart';
import 'widgets/admin_panel_widgets.dart';
import 'widgets/admin_stat_widgets.dart';

/// Convites por email (`/admin/convites`, 0085): o admin escolhe o modelo,
/// escreve o nome e o email de um Profissional, vê como fica e envia pela
/// Edge Function `send-invite` (Brevo, remetente suporte@projardim.pt).
/// Um destinatário de cada vez; quem pediu para não receber fica bloqueado
/// na BD. Por baixo, o histórico com "Lembrete" e "Não quer receber".
class AdminInvitesPage extends ConsumerStatefulWidget {
  const AdminInvitesPage({super.key});

  @override
  ConsumerState<AdminInvitesPage> createState() => _AdminInvitesPageState();
}

class _AdminInvitesPageState extends ConsumerState<AdminInvitesPage> {
  /// Quem assina fica lembrado enquanto o painel está aberto.
  static String _lastSignedBy = '';

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _subject = TextEditingController();
  final _signedBy = TextEditingController(text: _lastSignedBy);
  final _term = TextEditingController();
  final _search = TextEditingController();

  AdminInviteTemplate _template = AdminInviteTemplate.founderInvite;

  /// Enquanto o admin não mexe no assunto, segue a primeira sugestão.
  bool _subjectEdited = false;
  bool _sending = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _subject.text = _template.subjectOptions('').first;
    _name.addListener(_nameChanged);
    for (final c in [_email, _signedBy, _term]) {
      c.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _subject, _signedBy, _term, _search]) {
      c.dispose();
    }
    super.dispose();
  }

  void _rebuild() => setState(() {});

  void _nameChanged() {
    if (!_subjectEdited) {
      _subject.text = _template.subjectOptions(_name.text).first;
    }
    setState(() {});
  }

  void _setTemplate(AdminInviteTemplate template) {
    setState(() {
      _template = template;
      _subjectEdited = false;
      _subject.text = template.subjectOptions(_name.text).first;
    });
  }

  void _pickSubject(String subject) {
    setState(() {
      _subject.text = subject;
      _subjectEdited = subject != _template.subjectOptions(_name.text).first;
    });
  }

  AdminInviteDraft get _draft => AdminInviteDraft(
    template: _template,
    recipientName: _name.text,
    recipientEmail: _email.text,
    subject: _subject.text,
    signedBy: _signedBy.text,
    founderTerm: _term.text,
  );

  /// Lembrete a partir do histórico: mesmo nome e email.
  void _prefillReminder(AdminInviteRow row) {
    _name.text = row.recipientName;
    _email.text = row.recipientEmail;
    _setTemplate(AdminInviteTemplate.founderReminder);
    AppToast.of(context).show('Lembrete preparado. Reveja e envie.');
  }

  Future<void> _review() async {
    final draft = _draft;
    if (!draft.isComplete) return;
    final toast = AppToast.of(context);
    final repo = ref.read(adminRepositoryProvider);
    setState(() => _sending = true);
    AdminInviteEmailInfo info;
    try {
      info = await repo.fetchInviteEmailInfo(draft.recipientEmail);
    } catch (e) {
      toast.error(friendlyError(e));
      if (mounted) setState(() => _sending = false);
      return;
    }
    if (!mounted) return;
    setState(() => _sending = false);
    if (info.optedOut) {
      toast.error(
        'Este email pediu para não receber mensagens'
        '${info.optedOutAt == null ? '' : ' (${adminDateLabel(info.optedOutAt)})'}. '
        'Não é possível enviar.',
      );
      return;
    }
    if (info.overDailyLimit) {
      toast.error(
        'Chegou ao limite de ${info.dailyLimit} convites em 24 horas. '
        'Tente amanhã.',
      );
      return;
    }
    final warnings = <String>[
      if (info.sentCount > 0)
        'Já recebeu ${info.sentCount} '
            '${info.sentCount == 1 ? 'email' : 'emails'} nossos, o último '
            '${adminRelativeDateLabel(info.lastSentAt)}'
            '${info.lastTemplate == null ? '' : ' (${info.lastTemplate!.label.toLowerCase()})'}.',
      'Hoje: ${info.sentToday} de ${info.dailyLimit} convites.',
    ];
    final ok = await AppConfirmDialog.show(
      context,
      icon: Icons.mail_outline_rounded,
      title: 'Enviar para ${draft.recipientEmail.trim()}?',
      message:
          '"${draft.subject.trim()}", de suporte@projardim.pt. Não dá para '
          'desfazer depois de enviado.',
      confirmLabel: 'Enviar',
      details: Text(
        warnings.join('\n'),
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _sending = true);
    try {
      await repo.sendInvite(draft);
      if (!mounted) return;
      _lastSignedBy = _signedBy.text.trim();
      toast.show('Convite enviado para ${draft.recipientEmail.trim()}.');
      _name.clear();
      _email.clear();
      ref.invalidate(adminInvitesProvider);
      ref.invalidate(adminActionsProvider);
    } on AdminInviteException catch (e) {
      toast.error(e.message);
      // Um envio recusado pelo Brevo fica no histórico como falhado.
      ref.invalidate(adminInvitesProvider);
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _markOptout(AdminInviteRow row) async {
    final ok = await AppConfirmDialog.show(
      context,
      icon: Icons.unsubscribe_outlined,
      title: 'Não enviar mais para ${row.recipientEmail}?',
      message:
          'Use quando a pessoa respondeu "não" ou pediu por outra via. Fica '
          'registado e a BD passa a recusar qualquer envio para este email.',
      confirmLabel: 'Marcar',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    final toast = AppToast.of(context);
    try {
      await ref
          .read(adminRepositoryProvider)
          .setInviteOptout(row.recipientEmail, note: 'Marcado no painel');
      if (!mounted) return;
      toast.show('Registado. Não volta a receber emails nossos.');
      ref.invalidate(adminInvitesProvider);
      ref.invalidate(adminActionsProvider);
    } catch (e) {
      toast.error(friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final draft = _draft;
    final message = buildAdminInvite(draft);
    final invitesAsync = ref.watch(adminInvitesProvider(_query));
    final emailText = _email.text.trim();
    final emailError =
        emailText.isNotEmpty && !adminInviteEmailLooksValid(emailText);

    final form = AdminPanelCard(
      title: 'Convite',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final t in AdminInviteTemplate.values)
                AppFilterChip(
                  label: t.label,
                  selected: t == _template,
                  onPressed: () => _setTemplate(t),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            _template.description,
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _name,
            label: 'Nome do Profissional',
            hintText: 'Como aparece no "Bom dia, ..."',
            maxLength: adminInviteNameMax,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppTextField(
            controller: _email,
            label: 'Email',
            keyboardType: TextInputType.emailAddress,
            helperText: emailError
                ? 'Este email não parece válido.'
                : 'Só contactos que conhece ou que lhe deram o email.',
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: _subject,
            label: 'Assunto',
            maxLength: adminInviteSubjectMax,
            onChanged: (_) => setState(() => _subjectEdited = true),
          ),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final s in _template.subjectOptions(_name.text))
                AppFilterChip(
                  label: s,
                  selected: _subject.text.trim() == s,
                  onPressed: () => _pickSubject(s),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _signedBy,
            label: 'Assinado por',
            hintText: 'O seu nome',
            maxLength: adminInviteSignedByMax,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppTextField(
            controller: _term,
            label: 'Duração do Pro de fundador (opcional)',
            hintText: 'durante 12 meses',
            maxLength: adminInviteFounderTermMax,
            helperText: 'Vazio: o email diz só "Plano Pro grátis".',
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryActionButton(
            label: 'Rever e enviar',
            isLoading: _sending,
            onPressed: draft.isComplete && !_sending ? _review : null,
          ),
        ],
      ),
    );

    final preview = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Pré-visualização',
          style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppFadeThroughSwitcher(
          switchKey: _template,
          child: AdminInvitePreview(message: message),
        ),
      ],
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        Text(
          'Convites',
          style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Convites por email a Profissionais, de suporte@projardim.pt, um de '
          'cada vez. As respostas chegam ao email de suporte. Cada email leva '
          'um link para deixar de receber.',
          style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        const AppStaggeredEntrance(index: 0, child: _SetupNotice()),
        const SizedBox(height: AppSpacing.sm),
        AppStaggeredEntrance(
          index: 1,
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < adminSplitMinWidth) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    form,
                    const SizedBox(height: AppSpacing.md),
                    preview,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: adminListColumnWidth, child: form),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(child: preview),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Enviados',
          style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppSearchField(
          controller: _search,
          hintText: 'Procurar por nome ou email',
          onSubmitted: (value) => setState(() => _query = value.trim()),
          onClear: () => setState(() => _query = ''),
        ),
        const SizedBox(height: AppSpacing.sm),
        invitesAsync.when(
          loading: () => const AdminLoadingBlocks(count: 2, height: 90),
          error: (e, _) => AppInlineError(
            message: isMissingRpcError(e)
                ? 'Falta aplicar a migration 0085 na base de dados.'
                : friendlyError(e),
            onRetry: () => ref.invalidate(adminInvitesProvider),
          ),
          data: (rows) => rows.isEmpty
              ? AppEmptyState(
                  icon: Icons.mail_outline_rounded,
                  title: _query.isEmpty
                      ? 'Ainda sem convites'
                      : 'Sem resultados',
                  message: _query.isEmpty
                      ? 'Os convites enviados aparecem aqui.'
                      : 'Nenhum convite para "$_query".',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, row) in rows.indexed) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.xs),
                      AppStaggeredEntrance(
                        index: i < 6 ? i : 6,
                        child: AdminInviteCard(
                          invite: row,
                          onReminder: () => _prefillReminder(row),
                          onOptout: () => _markOptout(row),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// O que falta para o envio funcionar (domínio, Brevo, função).
class _SetupNotice extends StatelessWidget {
  const _SetupNotice();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tone = AppStatusColor.waiting;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: AppSizes.inlineIcon,
            color: tone.foreground,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Para os emails chegarem, o domínio projardim.pt tem de estar '
              'ativo com o DNS e o Brevo repostos, e a função send-invite '
              'publicada com a chave do Brevo (SETUP, secção 10). Até lá a '
              'pré-visualização funciona mas o envio dá erro.',
              style: textTheme.bodySmall?.copyWith(color: tone.foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminInviteCard extends StatelessWidget {
  const AdminInviteCard({
    required this.invite,
    required this.onReminder,
    required this.onOptout,
    super.key,
  });

  final AdminInviteRow invite;
  final VoidCallback onReminder;
  final VoidCallback onOptout;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final r = invite;
    final secondary = textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondary,
    );
    final statusColor = switch (r.status) {
      AdminInviteStatus.sent => AppStatusColor.success,
      AdminInviteStatus.failed => AppStatusColor.cancelled,
      AdminInviteStatus.pending => AppStatusColor.waiting,
    };
    return AdminPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.recipientName,
                      style: textTheme.titleSmall?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(r.recipientEmail, style: secondary),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xxs,
                runSpacing: AppSpacing.xxs,
                alignment: WrapAlignment.end,
                children: [
                  if (r.optedOut)
                    const AppStatusBadge(
                      label: 'Não quer receber',
                      statusColor: AppStatusColor.neutral,
                      dense: true,
                    ),
                  AppStatusBadge(
                    label: r.status.label,
                    statusColor: statusColor,
                    dense: true,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            r.subject,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
          ),
          Text(
            [
              r.template?.label ?? 'Modelo antigo',
              adminDateTimeLabel(r.sentAt ?? r.createdAt),
              ?r.adminEmail,
            ].join(' · '),
            style: secondary,
          ),
          if (r.status == AdminInviteStatus.failed && r.error != null)
            Text(
              r.error!,
              style: textTheme.bodySmall?.copyWith(
                color: AppStatusColor.cancelled.foreground,
              ),
            ),
          if (!r.optedOut) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                if (r.template != AdminInviteTemplate.founderReminder)
                  TextButton.icon(
                    onPressed: onReminder,
                    icon: const Icon(
                      Icons.replay_rounded,
                      size: AppSizes.inlineIcon,
                    ),
                    label: const Text('Lembrete'),
                  ),
                TextButton.icon(
                  onPressed: onOptout,
                  icon: const Icon(
                    Icons.unsubscribe_outlined,
                    size: AppSizes.inlineIcon,
                  ),
                  label: const Text('Não quer receber'),
                ),
              ],
            ),
          ],
          if (r.optedOut)
            Text(
              'Pediu para não receber a ${adminDateLabel(r.optedOutAt)}.',
              style: secondary,
            ),
        ],
      ),
    );
  }
}
