import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_filter_chip.dart';
import '../../../core/widgets/app_inline_error.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_status_badge.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_toast.dart';
import '../application/admin_labels.dart';
import '../application/admin_providers.dart';
import '../data/admin_resolve_models.dart';
import 'widgets/admin_action_dialogs.dart';
import 'widgets/admin_panel_widgets.dart';
import 'widgets/admin_stat_widgets.dart';

/// Caixa de suporte (`/admin/suporte` e `/admin/suporte/:caseId`): o que
/// precisa de resposta, pelo prazo mais próximo.
class AdminCasesPage extends StatelessWidget {
  const AdminCasesPage({this.selectedCaseId, super.key});

  final String? selectedCaseId;

  @override
  Widget build(BuildContext context) {
    final id = selectedCaseId;
    return AdminSplitView(
      list: AdminCasesList(selectedCaseId: id),
      detailKey: id,
      detailBuilder: id == null
          ? null
          : (overlay) => AdminCaseDetailPanel(
              key: ValueKey(id),
              caseId: id,
              onClose: overlay ? () => context.go('/admin/suporte') : null,
            ),
      emptyDetail: const AppEmptyState(
        icon: Icons.support_agent_rounded,
        title: 'Escolhe um caso',
        message:
            'O caso abre aqui, com as notas, a resposta enviada e a '
            'decisão.',
      ),
    );
  }
}

class AdminCasesList extends ConsumerWidget {
  const AdminCasesList({this.selectedCaseId, super.key});

  final String? selectedCaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(adminCasesFilterProvider);
    final casesAsync = ref.watch(adminCasesProvider(filter));
    final reportsAsync = ref.watch(
      adminReportsProvider((status: null, page: 0)),
    );
    final textTheme = Theme.of(context).textTheme;
    void set(AdminCasesFilter f) =>
        ref.read(adminCasesFilterProvider.notifier).update(f);

    Future<void> create() async {
      final id = await showAdminCreateCaseDialog(context, ref);
      if (id == null || !context.mounted) return;
      context.go('/admin/suporte/$id');
      AppToast.of(context).show('Caso aberto.');
      ref.invalidate(adminCasesProvider);
    }

    final newReports = reportsAsync.asData?.value
        .where((r) => r.status == 'new')
        .length;

    return RefreshIndicator(
      onRefresh: () {
        ref.invalidate(adminReportsProvider);
        return ref.refresh(adminCasesProvider(filter).future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Caixa de suporte',
                  style: textTheme.titleLarge?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: create,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Novo caso'),
              ),
            ],
          ),
          if (newReports != null && newReports > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Material(
              color: AppStatusColor.waiting.background,
              borderRadius: BorderRadius.circular(AppRadius.input),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.input),
                onTap: () => context.go('/admin/denuncias'),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Row(
                    children: [
                      Icon(
                        Icons.flag_outlined,
                        size: 20,
                        color: AppStatusColor.waiting.foreground,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          newReports == 1
                              ? '1 reporte novo por tratar'
                              : '$newReports reportes novos por tratar',
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppStatusColor.waiting.foreground,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: AppStatusColor.waiting.foreground,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final (value, label) in const [
                (null, 'Por tratar'),
                ('open', 'Abertos'),
                ('waiting_user', 'À espera da pessoa'),
                ('resolved', 'Resolvidos'),
                ('all', 'Todos'),
              ])
                AppFilterChip(
                  label: label,
                  selected: filter.status == value,
                  onPressed: () => set(filter.copyWith(status: value)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              AppFilterChip(
                label: 'Todos os tipos',
                selected: filter.kind == null,
                onPressed: () => set(filter.copyWith(kind: null)),
              ),
              for (final kind in AdminCaseKind.values)
                AppFilterChip(
                  label: kind.label,
                  selected: filter.kind == kind,
                  onPressed: () => set(filter.copyWith(kind: kind)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          casesAsync.when(
            loading: () => const AdminLoadingBlocks(count: 4, height: 88),
            error: (error, _) => AppInlineError(
              message: friendlyError(error),
              onRetry: () => ref.invalidate(adminCasesProvider(filter)),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'Nada por tratar',
                  message:
                      'Quando chegar um email ou um reporte, abre um caso '
                      'para o prazo começar a contar.',
                );
              }
              final total = rows.first.totalCount;
              final late = rows
                  .where(
                    (r) =>
                        adminDeadlineTone(r.nextDueAt, closed: r.closed) ==
                        AdminDeadlineTone.red,
                  )
                  .length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    [
                      total == 1 ? '1 caso' : '$total casos',
                      if (late > 0) '$late atrasados',
                    ].join(' · '),
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  for (final (i, row) in rows.indexed) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.xs),
                    AppStaggeredEntrance(
                      index: i < 6 ? i : 6,
                      child: AdminCaseRowCard(
                        row: row,
                        selected: row.caseId == selectedCaseId,
                        onPressed: () =>
                            context.go('/admin/suporte/${row.caseId}'),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  AdminPager(
                    page: filter.page,
                    pages: (total / adminCasesPageSize).ceil(),
                    onPage: (p) => set(filter.copyWith(page: p)),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Ficha de um caso. Abrir fica registado (admin_get_case).
class AdminCaseDetailPanel extends ConsumerWidget {
  const AdminCaseDetailPanel({required this.caseId, this.onClose, super.key});

  final String caseId;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caseAsync = ref.watch(adminCaseDetailProvider(caseId));

    void refreshAll(String message) {
      AppToast.of(context).show(message);
      ref.invalidate(adminCaseDetailProvider(caseId));
      ref.invalidate(adminCasesProvider);
      ref.invalidate(adminCasesForTargetProvider);
      ref.invalidate(adminReportsProvider);
    }

    return caseAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: AdminLoadingBlocks(),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: AppInlineError(
          message: friendlyError(error),
          onRetry: () => ref.invalidate(adminCaseDetailProvider(caseId)),
        ),
      ),
      data: (detail) => RefreshIndicator(
        onRefresh: () => ref.refresh(adminCaseDetailProvider(caseId).future),
        child: AdminCaseDetailView(
          detail: detail,
          onClose: onClose,
          onOpen: (route) => context.go(route),
          onAddNote: (body, isReply) async {
            await ref
                .read(adminRepositoryProvider)
                .addCaseNote(caseId, body: body, isReply: isReply);
            if (context.mounted) {
              refreshAll(isReply ? 'Resposta registada.' : 'Nota guardada.');
            }
          },
          onSetStatus: (status, decision) async {
            await ref
                .read(adminRepositoryProvider)
                .updateCase(caseId, status: status, decision: decision);
            if (context.mounted) {
              refreshAll(
                status == AdminCaseStatus.resolved
                    ? 'Caso fechado.'
                    : 'Caso atualizado.',
              );
            }
          },
        ),
      ),
    );
  }
}

/// Vista pura do caso (sem providers), para testes.
class AdminCaseDetailView extends StatefulWidget {
  const AdminCaseDetailView({
    required this.detail,
    required this.onOpen,
    required this.onAddNote,
    required this.onSetStatus,
    this.onClose,
    super.key,
  });

  final AdminCaseDetail detail;
  final ValueChanged<String> onOpen;
  final Future<void> Function(String body, bool isReply) onAddNote;
  final Future<void> Function(AdminCaseStatus status, String? decision)
  onSetStatus;
  final VoidCallback? onClose;

  @override
  State<AdminCaseDetailView> createState() => _AdminCaseDetailViewState();
}

class _AdminCaseDetailViewState extends State<AdminCaseDetailView> {
  final _note = TextEditingController();
  late final _decision = TextEditingController(
    text: widget.detail.decision ?? '',
  );
  bool _isReply = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _note.addListener(() => setState(() {}));
    _decision.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _note.dispose();
    _decision.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) AppToast.of(context).show(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final row = d.row;
    final textTheme = Theme.of(context).textTheme;
    final decision = _decision.text.trim();

    final sections = <Widget>[
      AdminPanelCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (widget.onClose != null)
                  IconButton(
                    tooltip: 'Voltar à lista',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                Expanded(
                  child: Text(
                    'Caso #${row.number} · ${row.kind?.label ?? row.kindValue}',
                    style: textTheme.titleLarge?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                AppStatusBadge(
                  label: row.status.label,
                  statusColor: adminCaseStatusColor(row.status),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              row.summary,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AdminInfoRow(
              label: 'Confirmar receção',
              value: row.firstReplyAt != null
                  ? 'Feito a ${adminDateTimeLabel(row.firstReplyAt)}'
                  : adminDateTimeLabel(row.ackDueAt),
              trailing: row.firstReplyAt != null
                  ? null
                  : AdminDeadlineBadge(dueAt: row.ackDueAt, closed: row.closed),
            ),
            AdminInfoRow(
              label: 'Prazo da decisão',
              value:
                  '${adminDateTimeLabel(row.dueAt)} (${row.kind?.deadline ?? ''})',
              trailing: AdminDeadlineBadge(
                dueAt: row.dueAt,
                closed: row.closed,
              ),
            ),
            AdminInfoRow(
              label: 'Aberto',
              value: adminDateTimeLabel(row.createdAt),
            ),
            if (row.closedAt != null)
              AdminInfoRow(
                label: 'Fechado',
                value: adminDateTimeLabel(row.closedAt),
              ),
            if (d.replyEmail != null)
              AdminInfoRow(
                label: 'Responder para',
                value: d.replyEmail!,
                trailing: AdminCopyButton(
                  value: d.replyEmail!,
                  tooltip: 'Copiar email',
                ),
              ),
            if (row.personId != null)
              _LinkRow(
                label: d.personRole == 'worker' ? 'Profissional' : 'Pessoa',
                value: row.personName ?? adminShortId(row.personId!),
                onTap: () => widget.onOpen(
                  d.personRole == 'worker'
                      ? '/admin/workers/${row.personId}'
                      : '/admin/clientes/${row.personId}',
                ),
              ),
            if (row.jobId != null)
              _LinkRow(
                label: 'Pedido',
                value:
                    '${d.jobService ?? 'Pedido'} · ${adminShortId(row.jobId!)}',
                onTap: () => widget.onOpen('/admin/pedidos/${row.jobId}'),
              ),
          ],
        ),
      ),
      if (d.reports.isNotEmpty)
        AdminPanelCard(
          title: 'Reportes ligados',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in d.reports)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          '${adminDateTimeLabel(r.createdAt)}: ${r.description}',
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      AppStatusBadge(
                        label: adminReportStatus(r.status).$1,
                        statusColor: adminReportStatus(r.status).$2,
                        dense: true,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      AdminPanelCard(
        title: 'Notas e respostas',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (d.notes.isEmpty)
              Text(
                'Ainda nada. A primeira resposta enviada por email conta '
                'como confirmação de receção.',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            for (final n in d.notes)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppStatusBadge(
                      label: n.isReply ? 'Resposta enviada' : 'Nota interna',
                      statusColor: n.isReply
                          ? AppStatusColor.success
                          : AppStatusColor.neutral,
                      dense: true,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    SelectableText(
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
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                AppFilterChip(
                  label: 'Nota interna',
                  selected: !_isReply,
                  onPressed: () => setState(() => _isReply = false),
                ),
                AppFilterChip(
                  label: 'Resposta enviada por email',
                  leadingIcon: Icons.mail_outline_rounded,
                  selected: _isReply,
                  onPressed: () => setState(() => _isReply = true),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            AppTextField(
              controller: _note,
              label: _isReply
                  ? 'Cola aqui o email que enviaste'
                  : 'Nota (só o suporte vê)',
              maxLength: 8000,
              minLines: 2,
              maxLines: 6,
              textInputAction: TextInputAction.newline,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: _note.text.trim().isEmpty || _busy
                    ? null
                    : () => _run(() async {
                        await widget.onAddNote(_note.text.trim(), _isReply);
                        _note.clear();
                      }),
                child: Text(_isReply ? 'Registar resposta' : 'Guardar nota'),
              ),
            ),
          ],
        ),
      ),
      AdminPanelCard(
        title: 'Decisão',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: _decision,
              label: 'Decisão fundamentada',
              hintText:
                  'O que se decidiu e porquê. É o que se responde à pessoa.',
              maxLength: 4000,
              minLines: 2,
              maxLines: 6,
              textInputAction: TextInputAction.newline,
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                if (row.status != AdminCaseStatus.waitingUser && !row.closed)
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => widget.onSetStatus(
                              AdminCaseStatus.waitingUser,
                              decision.isEmpty ? null : decision,
                            ),
                          ),
                    child: const Text('À espera da pessoa'),
                  ),
                if (row.status == AdminCaseStatus.waitingUser || row.closed)
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => widget.onSetStatus(
                              AdminCaseStatus.open,
                              decision.isEmpty ? null : decision,
                            ),
                          ),
                    child: Text(
                      row.closed ? 'Reabrir caso' : 'Voltar a aberto',
                    ),
                  ),
                if (!row.closed)
                  FilledButton(
                    onPressed: decision.isEmpty || _busy
                        ? null
                        : () => _run(
                            () => widget.onSetStatus(
                              AdminCaseStatus.resolved,
                              decision,
                            ),
                          ),
                    child: const Text('Fechar com esta decisão'),
                  ),
              ],
            ),
          ],
        ),
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        for (final (i, section) in sections.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          AppStaggeredEntrance(index: i < 6 ? i : 6, child: section),
        ],
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: onTap, child: Text(value)),
            ),
          ),
        ],
      ),
    );
  }
}
