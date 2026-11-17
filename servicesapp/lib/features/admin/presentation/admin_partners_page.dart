import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_sizes.dart';
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
  partners('Parceiros'),
  fleet('Cartões frota');

  const AdminPartnersTab(this.label);
  final String label;
}

/// Parceiros (`/admin/parceiros`, 0082): os parceiros (gasolineiras,
/// lojas, etc.) com tudo o que aparece na app e o que há perto de cada um,
/// e os cartões frota para aprovar, recusar ou retirar (`?tab=frota`).
class AdminPartnersPage extends ConsumerStatefulWidget {
  const AdminPartnersPage({
    this.initialTab = AdminPartnersTab.partners,
    super.key,
  });

  final AdminPartnersTab initialTab;

  @override
  ConsumerState<AdminPartnersPage> createState() => _AdminPartnersPageState();
}

class _AdminPartnersPageState extends ConsumerState<AdminPartnersPage> {
  late AdminPartnersTab _tab = widget.initialTab;

  @override
  void didUpdateWidget(AdminPartnersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // O alerta da Visão geral abre `?tab=frota` com a página já aberta.
    if (oldWidget.initialTab != widget.initialTab) _tab = widget.initialTab;
  }

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
            ? 'O cartão fica ativo e o profissional é avisado.'
            : 'Atenção: o plano é ${adminPlanLabel(card.plan)} e o cartão '
                  'frota é do Pro+. O cartão fica ativo na mesma e o '
                  'profissional é avisado.',
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

  // ── Parceiros ──

  Future<void> _edit([AdminPartner? partner]) async {
    final toast = AppToast.of(context);
    final saved = await showAdminPartnerEditor(context, partner: partner);
    if (saved != true || !mounted) return;
    toast.show(
      partner == null ? 'Parceiro adicionado.' : 'Alterações gravadas.',
    );
    ref.invalidate(adminPartnersProvider);
    ref.invalidate(adminMapZonesProvider);
  }

  Future<void> _delete(AdminPartner partner) async {
    final toast = AppToast.of(context);
    final ok = await AppConfirmDialog.show(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'Apagar ${partner.name}?',
      message:
          'Sai da app, da lista e do mapa, e a foto é apagada. Fica no '
          'Registo. Se a parceria acabou, podes antes mudar o estado para '
          '"Terminado".',
      confirmLabel: 'Apagar',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(adminRepositoryProvider).deletePartner(partner.id);
      if (!mounted) return;
      toast.show('Parceiro apagado.');
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
          'Os parceiros que os profissionais veem na tab Parceiros da app, e '
          'os cartões frota do Pro+. No Mapa, a camada "Parceiros" mostra '
          'os que têm localização ao lado das zonas sem resposta e da '
          'densidade de profissionais.',
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
            AdminPartnersTab.partners => _partners(context),
            AdminPartnersTab.fleet => _fleet(context),
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
                      'Os pedidos de cartão frota dos profissionais '
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

  Widget _partners(BuildContext context) {
    final partnersAsync = ref.watch(adminPartnersProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('Adicionar parceiro'),
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
                  icon: Icons.storefront_outlined,
                  title: 'Ainda sem parceiros',
                  message:
                      'Adiciona os parceiros e os que estão em conversa. Os '
                      'que marcares "Mostrar na app" aparecem aos '
                      'profissionais; com localização, aparecem no mapa.',
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
                          onNotify: () =>
                              context.go('/admin/avisos?parceiro=${p.id}'),
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
              'Mensagem ao profissional: ${c.reviewMessage}',
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
            label: 'Mensagem ao profissional',
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

/// Um parceiro: estado, se aparece na app, o que tem preenchido e o que
/// há perto.
class AdminPartnerTile extends StatelessWidget {
  const AdminPartnerTile({
    required this.partner,
    required this.onEdit,
    required this.onDelete,
    this.onNotify,
    super.key,
  });

  final AdminPartner partner;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// "Avisar os profissionais" (só para os que aparecem na app).
  final VoidCallback? onNotify;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final p = partner;
    final secondary = textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondary,
    );
    final uncovered =
        p.hasLocation &&
        p.status != AdminPartnerStatus.ended &&
        p.workersCovering == 0;
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
                    if (p.shownInApp())
                      const AppStatusBadge(
                        label: 'Na app',
                        statusColor: AppStatusColor.success,
                        dense: true,
                      )
                    else if (p.visibleInApp)
                      const AppStatusBadge(
                        label: 'Não aparece na app',
                        statusColor: AppStatusColor.waiting,
                        dense: true,
                      ),
                    if (p.proPlusOnly && adminPartnerHasCodes(p))
                      const AppStatusBadge(
                        label: 'Códigos só Pro+',
                        statusColor: AppStatusColor.neutral,
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
            [p.kind.label, ?p.brand, ?p.address, ?p.locality].join(' · '),
            style: secondary,
          ),
          if (p.headline != null)
            Text(
              p.headline!,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.primary),
            ),
          const SizedBox(height: AppSpacing.xxs),
          Text(adminPartnerFilledLabel(p), style: secondary),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            adminPartnerReachLabel(p),
            style: textTheme.bodyMedium?.copyWith(
              color: uncovered
                  ? AppStatusColor.cancelled.foreground
                  : AppColors.textPrimary,
            ),
          ),
          if (adminPartnerUsageLabel(p) case final usage?) ...[
            const SizedBox(height: AppSpacing.xxs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(right: AppSpacing.xxs),
                  child: Icon(
                    Icons.insights_outlined,
                    size: AppSizes.metaIcon,
                    color: AppColors.textSecondary,
                  ),
                ),
                Expanded(child: Text(usage, style: secondary)),
              ],
            ),
          ],
          if (p.notes != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(p.notes!, style: secondary),
          ],
          if (onNotify != null && p.shownInApp()) ...[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onNotify,
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Avisar os profissionais'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
