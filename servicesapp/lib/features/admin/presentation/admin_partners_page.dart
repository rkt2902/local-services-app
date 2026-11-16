import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_filter_chip.dart';
import '../../../core/widgets/app_inline_error.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_status_badge.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_toast.dart';
import '../application/admin_labels.dart';
import '../application/admin_providers.dart';
import '../data/admin_partner_models.dart';
import 'admin_map_page.dart' show adminPlanLabel;
import 'widgets/admin_panel_widgets.dart';
import 'widgets/admin_partner_editor.dart';
import 'widgets/admin_stat_widgets.dart';

/// Separadores da página Parceiros.
enum AdminPartnersTab {
  fleet('Cartões frota'),
  stations('Gasolineiras');

  const AdminPartnersTab(this.label);
  final String label;
}

/// Parceiros (`/admin/parceiros`, 0082): cartões frota para aprovar,
/// recusar ou retirar, e as gasolineiras parceiras (ou em conversa) com o
/// que há perto de cada uma. `?tab=gasolineiras` abre o segundo.
class AdminPartnersPage extends ConsumerStatefulWidget {
  const AdminPartnersPage({
    this.initialTab = AdminPartnersTab.fleet,
    super.key,
  });

  final AdminPartnersTab initialTab;

  @override
  ConsumerState<AdminPartnersPage> createState() => _AdminPartnersPageState();
}

class _AdminPartnersPageState extends ConsumerState<AdminPartnersPage> {
  late AdminPartnersTab _tab = widget.initialTab;
  String? _fleetStatus = 'pending';

  // ── Cartões frota ──

  Future<void> _approve(AdminFleetCardRow card) async {
    final toast = AppToast.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => _SubmitDialog(
        icon: Icons.verified_outlined,
        title: 'Aprovar o cartão de ${card.workerName}?',
        message: card.planHasBenefit
            ? 'O cartão fica ativo e o jardineiro é avisado.'
            : 'Atenção: o plano é ${adminPlanLabel(card.plan)} e o cartão '
                  'frota é do Pro+. O cartão fica ativo na mesma e o '
                  'jardineiro é avisado.',
        confirmLabel: 'Aprovar',
        onSubmit: () =>
            ref.read(adminRepositoryProvider).approveFleetCard(card.id),
      ),
    );
    if (ok != true || !mounted) return;
    toast.show('Cartão aprovado.');
    ref.invalidate(adminFleetCardsProvider);
  }

  Future<void> _reject(AdminFleetCardRow card) async {
    final toast = AppToast.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AdminFleetRejectDialog(
        card: card,
        onSubmit: (reason, message) => ref
            .read(adminRepositoryProvider)
            .rejectFleetCard(card.id, reason: reason, message: message),
      ),
    );
    if (ok != true || !mounted) return;
    toast.show(card.isActive ? 'Cartão retirado.' : 'Cartão recusado.');
    ref.invalidate(adminFleetCardsProvider);
  }

  // ── Gasolineiras ──

  Future<void> _edit([AdminPartnerLocation? partner]) async {
    final toast = AppToast.of(context);
    final saved = await showAdminPartnerEditor(context, partner: partner);
    if (saved != true || !mounted) return;
    toast.show(
      partner == null ? 'Gasolineira adicionada.' : 'Alterações gravadas.',
    );
    ref.invalidate(adminPartnersProvider);
    ref.invalidate(adminMapZonesProvider);
  }

  Future<void> _delete(AdminPartnerLocation partner) async {
    final toast = AppToast.of(context);
    final ok = await AppConfirmDialog.show(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'Apagar ${partner.name}?',
      message:
          'Sai da lista e do mapa. Fica no Registo que foi apagada. Se a '
          'parceria acabou, podes antes mudar o estado para "Terminada".',
      confirmLabel: 'Apagar',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(adminRepositoryProvider).deletePartner(partner.id);
      if (!mounted) return;
      toast.show('Gasolineira apagada.');
      ref.invalidate(adminPartnersProvider);
      ref.invalidate(adminMapZonesProvider);
    } catch (e) {
      toast.error(friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        Text(
          'Parceiros',
          style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Cartões frota dos jardineiros Pro+ e as gasolineiras parceiras. '
          'No Mapa, a camada "Gasolineiras" mostra-as ao lado das zonas sem '
          'resposta e da densidade de jardineiros.',
          style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final tab in AdminPartnersTab.values)
              AppFilterChip(
                label: tab.label,
                selected: _tab == tab,
                onPressed: () => setState(() => _tab = tab),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppFadeThroughSwitcher(
          switchKey: _tab,
          child: switch (_tab) {
            AdminPartnersTab.fleet => _fleet(context),
            AdminPartnersTab.stations => _stations(context),
          },
        ),
      ],
    );
  }

  Widget _fleet(BuildContext context) {
    final cardsAsync = ref.watch(adminFleetCardsProvider(_fleetStatus));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final (label, status) in adminFleetFilters)
              AppFilterChip(
                label: label,
                selected: _fleetStatus == status,
                showCheckmark: true,
                onPressed: () => setState(() => _fleetStatus = status),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        cardsAsync.when(
          loading: () => const AdminLoadingBlocks(count: 2, height: 120),
          error: (e, _) => AppInlineError(
            message: friendlyError(e),
            onRetry: () => ref.invalidate(adminFleetCardsProvider),
          ),
          data: (cards) => cards.isEmpty
              ? AppEmptyState(
                  icon: Icons.local_gas_station_outlined,
                  title: _fleetStatus == 'pending'
                      ? 'Nenhum cartão por aprovar'
                      : 'Sem cartões',
                  message:
                      'Os pedidos de cartão frota dos jardineiros '
                      'aparecem aqui.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, card) in cards.indexed) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.xs),
                      AppStaggeredEntrance(
                        index: i < 6 ? i : 6,
                        child: AdminFleetCardTile(
                          card: card,
                          onApprove: () => _approve(card),
                          onReject: () => _reject(card),
                          onOpenWorker: () =>
                              context.go('/admin/workers/${card.workerId}'),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _stations(BuildContext context) {
    final partnersAsync = ref.watch(adminPartnersProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('Adicionar gasolineira'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        partnersAsync.when(
          loading: () => const AdminLoadingBlocks(count: 2, height: 110),
          error: (e, _) => AppInlineError(
            message: friendlyError(e),
            onRetry: () => ref.invalidate(adminPartnersProvider),
          ),
          data: (partners) => partners.isEmpty
              ? const AppEmptyState(
                  icon: Icons.local_gas_station_outlined,
                  title: 'Ainda sem gasolineiras',
                  message:
                      'Adiciona as parceiras e as que estão em conversa para '
                      'as ver no mapa ao lado da procura e dos jardineiros.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, p) in partners.indexed) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.xs),
                      AppStaggeredEntrance(
                        index: i < 6 ? i : 6,
                        child: AdminPartnerTile(
                          partner: p,
                          onEdit: () => _edit(p),
                          onDelete: () => _delete(p),
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

/// Um pedido de cartão frota: dados lidos do cartão, plano e ações.
class AdminFleetCardTile extends StatelessWidget {
  const AdminFleetCardTile({
    required this.card,
    required this.onApprove,
    required this.onReject,
    required this.onOpenWorker,
    super.key,
  });

  final AdminFleetCardRow card;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onOpenWorker;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final c = card;
    final (statusLabel, statusTone) = adminFleetStatus(c.status);
    final secondary = textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondary,
    );
    return AdminPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                c.workerName,
                style: textTheme.titleSmall?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              AppStatusBadge(
                label: statusLabel,
                statusColor: statusTone,
                dense: true,
              ),
              AppStatusBadge(
                label: adminPlanLabel(c.plan),
                statusColor: c.planHasBenefit
                    ? AppStatusColor.info
                    : AppStatusColor.neutral,
                dense: true,
              ),
              if (c.workerSuspended)
                const AppStatusBadge(
                  label: 'Conta suspensa',
                  statusColor: AppStatusColor.cancelled,
                  dense: true,
                ),
              if (!c.isLatest)
                const AppStatusBadge(
                  label: 'Substituído por um pedido novo',
                  statusColor: AppStatusColor.neutral,
                  dense: true,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            [
              ?c.locationName,
              'pedido ${adminRelativeDateLabel(c.createdAt)}',
              if (c.attempts > 1) '${c.attempts} pedidos no total',
            ].join(' · '),
            style: secondary,
          ),
          const SizedBox(height: AppSpacing.xs),
          AdminInfoRow(label: 'Nome no cartão', value: c.holderName ?? '—'),
          AdminInfoRow(label: 'Número', value: c.cardNumber ?? '—'),
          AdminInfoRow(label: 'Código de barras', value: c.barcodeValue),
          if (!c.planHasBenefit && c.isPending) ...[
            const SizedBox(height: AppSpacing.xs),
            AdminAlertRow(
              icon: Icons.info_outline_rounded,
              message:
                  'Plano ${adminPlanLabel(c.plan)}: o cartão frota é do Pro+.',
            ),
          ],
          if (c.reviewMessage != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Mensagem ao jardineiro: ${c.reviewMessage}',
              style: secondary,
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              if (c.isLatest && c.isPending) ...[
                FilledButton(
                  onPressed: onApprove,
                  child: const Text('Aprovar'),
                ),
                OutlinedButton(
                  onPressed: onReject,
                  child: const Text('Recusar'),
                ),
              ],
              if (c.isLatest && c.isActive)
                OutlinedButton(
                  onPressed: onReject,
                  child: const Text('Retirar'),
                ),
              TextButton(
                onPressed: onOpenWorker,
                child: const Text('Abrir ficha'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Recusar ou retirar: motivo da lista e mensagem opcional ao jardineiro
/// (obrigatória em "Outro").
class AdminFleetRejectDialog extends StatefulWidget {
  const AdminFleetRejectDialog({
    required this.card,
    required this.onSubmit,
    super.key,
  });

  final AdminFleetCardRow card;
  final Future<void> Function(AdminFleetRejectReason reason, String? message)
  onSubmit;

  @override
  State<AdminFleetRejectDialog> createState() => _AdminFleetRejectDialogState();
}

class _AdminFleetRejectDialogState extends State<AdminFleetRejectDialog> {
  final _message = TextEditingController();
  AdminFleetRejectReason? _reason;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _message.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  bool get _valid {
    final reason = _reason;
    if (reason == null) return false;
    return reason != AdminFleetRejectReason.other ||
        _message.text.trim().length >= 10;
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final text = _message.text.trim();
      await widget.onSubmit(_reason!, text.isEmpty ? null : text);
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
    final revoke = widget.card.isActive;
    final reason = _reason;
    return AppConfirmDialog(
      icon: Icons.block_rounded,
      title: revoke ? 'Retirar o cartão frota?' : 'Recusar o cartão frota?',
      message: revoke
          ? 'O cartão deixa de estar ativo e ${widget.card.workerName} é '
                'avisado com a mensagem abaixo.'
          : '${widget.card.workerName} é avisado com a mensagem abaixo e '
                'pode pedir outra vez.',
      confirmLabel: revoke ? 'Retirar' : 'Recusar',
      destructive: true,
      isSubmitting: _submitting,
      errorText: _error,
      onCancel: () => Navigator.pop(context, false),
      onConfirm: _valid && !_submitting ? _submit : null,
      details: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Motivo',
            style: textTheme.labelLarge?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final r in AdminFleetRejectReason.values)
                AppFilterChip(
                  label: r.label,
                  selected: reason == r,
                  onPressed: () => setState(() => _reason = r),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: _message,
            label: 'Mensagem ao jardineiro',
            helperText: reason == null || reason.message == null
                ? 'Obrigatória no motivo "Outro" (10 carateres ou mais).'
                : 'Opcional. Sem texto vai: "${reason.message}"',
            maxLength: 300,
            minLines: 2,
            maxLines: 3,
            textInputAction: TextInputAction.newline,
          ),
        ],
      ),
    );
  }
}

/// Confirmação que corre a ação lá dentro (o erro aparece no diálogo).
class _SubmitDialog extends StatefulWidget {
  const _SubmitDialog({
    required this.icon,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.onSubmit,
  });

  final IconData icon;
  final String title;
  final String message;
  final String confirmLabel;
  final Future<void> Function() onSubmit;

  @override
  State<_SubmitDialog> createState() => _SubmitDialogState();
}

class _SubmitDialogState extends State<_SubmitDialog> {
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit();
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
  Widget build(BuildContext context) => AppConfirmDialog(
    icon: widget.icon,
    title: widget.title,
    message: widget.message,
    confirmLabel: widget.confirmLabel,
    isSubmitting: _submitting,
    errorText: _error,
    onCancel: () => Navigator.pop(context, false),
    onConfirm: _submitting ? null : _submit,
  );
}

/// Uma gasolineira: estado, morada e o que há perto.
class AdminPartnerTile extends StatelessWidget {
  const AdminPartnerTile({
    required this.partner,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final AdminPartnerLocation partner;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final p = partner;
    final secondary = textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondary,
    );
    final uncovered =
        p.status != AdminPartnerStatus.ended && p.workersCovering == 0;
    return AdminPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      p.name,
                      style: textTheme.titleSmall?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    AppStatusBadge(
                      label: p.status.label,
                      statusColor: p.status.tone,
                      dense: true,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Alterar',
                onPressed: onEdit,
                icon: const Icon(
                  Icons.edit_outlined,
                  color: AppColors.textSecondary,
                ),
              ),
              IconButton(
                tooltip: 'Apagar',
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          Text(
            [?p.brand, ?p.address, ?p.locality].join(' · '),
            style: secondary,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            adminPartnerReachLabel(p),
            style: textTheme.bodyMedium?.copyWith(
              color: uncovered
                  ? AppStatusColor.cancelled.foreground
                  : AppColors.textPrimary,
            ),
          ),
          if (p.notes != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(p.notes!, style: secondary),
          ],
        ],
      ),
    );
  }
}
