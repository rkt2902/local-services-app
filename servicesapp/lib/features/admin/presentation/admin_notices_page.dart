import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../../worker/application/worker_providers.dart';
import '../../worker/data/service_type_model.dart';
import '../application/admin_labels.dart';
import '../application/admin_providers.dart';
import '../data/admin_growth_models.dart';
import '../data/admin_partner_models.dart';
import 'widgets/admin_panel_widgets.dart';
import 'widgets/admin_stat_widgets.dart';

const adminNoticeTitleMax = 80;
const adminNoticeBodyMax = 500;

/// Avisos (`/admin/avisos`, 0081): mensagem da ProJardim a um grupo de
/// jardineiros ou clientes, na app e por push. Primeiro conta quem
/// recebe; a BD só envia se o número ainda for o mesmo.
///
/// Com [partnerId] (`?parceiro=`, botão "Avisar os jardineiros" de um
/// parceiro, 0082) o aviso é só para jardineiros e, ao tocar, abre o
/// ecrã desse parceiro na app.
class AdminNoticesPage extends ConsumerStatefulWidget {
  const AdminNoticesPage({this.partnerId, super.key});

  final String? partnerId;

  @override
  ConsumerState<AdminNoticesPage> createState() => _AdminNoticesPageState();
}

class _AdminNoticesPageState extends ConsumerState<AdminNoticesPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _area = TextEditingController();
  AdminNoticeAudience _audience = const AdminNoticeAudience();
  int? _count;
  bool _counting = false;
  bool _sending = false;

  /// Parceiro do aviso (`null` = aviso normal).
  AdminPartner? _partner;
  late String? _partnerId = widget.partnerId;

  @override
  void initState() {
    super.initState();
    _title.addListener(_rebuild);
    _body.addListener(_rebuild);
    _area.addListener(_areaChanged);
    _loadPartner();
  }

  @override
  void didUpdateWidget(AdminNoticesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.partnerId != widget.partnerId) {
      _partnerId = widget.partnerId;
      _partner = null;
      _loadPartner();
    }
  }

  /// Vai buscar o parceiro e sugere o título e o texto.
  Future<void> _loadPartner() async {
    final id = _partnerId;
    if (id == null) return;
    try {
      final partners = await ref.read(adminRepositoryProvider).fetchPartners();
      final partner = partners.where((p) => p.id == id).firstOrNull;
      if (!mounted || partner == null || _partnerId != id) return;
      final (title, body) = adminPartnerNoticeDraft(partner);
      setState(() {
        _partner = partner;
        if (_title.text.trim().isEmpty) _title.text = title;
        if (_body.text.trim().isEmpty) _body.text = body;
      });
      _setAudience(_audience.copyWith(role: 'worker'));
    } catch (_) {
      // Sem a lista: fica um aviso normal.
    }
  }

  void _clearPartner() {
    setState(() {
      _partner = null;
      _partnerId = null;
    });
    if (widget.partnerId != null) context.go('/admin/avisos');
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _area.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  void _areaChanged() => _setAudience(_audience.copyWith(area: _area.text));

  /// Mudar os filtros obriga a contar outra vez.
  void _setAudience(AdminNoticeAudience next) {
    if (next == _audience) return;
    setState(() {
      _audience = next;
      _count = null;
    });
  }

  Future<void> _countRecipients() async {
    setState(() => _counting = true);
    final toast = AppToast.of(context);
    try {
      final n = await ref
          .read(adminRepositoryProvider)
          .noticeAudience(_audience);
      if (mounted) setState(() => _count = n);
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      if (mounted) setState(() => _counting = false);
    }
  }

  Future<void> _send() async {
    final count = _count;
    if (count == null || count == 0) return;
    final ok = await AppConfirmDialog.show(
      context,
      icon: Icons.campaign_outlined,
      title: 'Enviar a $count pessoas?',
      message:
          'Chega a cada uma na app e por push. Não dá para desfazer nem '
          'editar depois.',
      confirmLabel: 'Enviar',
    );
    if (ok != true || !mounted) return;
    setState(() => _sending = true);
    final toast = AppToast.of(context);
    try {
      final sent = await ref
          .read(adminRepositoryProvider)
          .sendNotice(
            title: _title.text,
            body: _body.text,
            audience: _audience,
            expected: count,
            partnerId: _partner?.id,
          );
      if (!mounted) return;
      toast.show('Aviso enviado a $sent pessoas.');
      _title.clear();
      _body.clear();
      setState(() {
        _count = null;
        _partner = null;
        _partnerId = null;
      });
      ref.invalidate(adminNoticesProvider);
      ref.invalidate(adminActionsProvider);
    } catch (e) {
      // Ex.: o número mudou: conta outra vez.
      toast.error(friendlyError(e));
      if (mounted) setState(() => _count = null);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final services =
        ref.watch(serviceTypesProvider).asData?.value ?? const <ServiceType>[];
    final noticesAsync = ref.watch(adminNoticesProvider);
    final title = _title.text.trim();
    final body = _body.text.trim();
    final textOk =
        title.length >= 3 &&
        title.length <= adminNoticeTitleMax &&
        body.length >= 10 &&
        body.length <= adminNoticeBodyMax;
    final count = _count;
    final a = _audience;
    final partner = _partner;
    final partnerHidden = partner != null && !partner.shownInApp();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        Text(
          'Avisos',
          style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Avisos de serviço da ProJardim a um grupo (mudanças, novidades da '
          'app, manutenção), na app e por push. Promoções e dicas vão nas '
          'dicas da época, que cada pessoa pode desligar.',
          style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        if (partner != null) ...[
          AppStaggeredEntrance(
            index: 0,
            child: AdminNoticePartnerCard(
              partner: partner,
              onRemove: _clearPartner,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        AppStaggeredEntrance(
          index: 0,
          child: AdminPanelCard(
            title: 'Para quem',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final (role, label) in [
                      ('worker', 'Jardineiros'),
                      // Avisos de parceiro são só para jardineiros.
                      if (partner == null) ('client', 'Clientes'),
                    ])
                      AppFilterChip(
                        label: label,
                        selected: a.role == role,
                        onPressed: () => _setAudience(a.copyWith(role: role)),
                      ),
                  ],
                ),
                if (a.isWorkers) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Plano (nenhum escolhido = todos)',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final (tier, label) in const [
                        ('free', 'Grátis'),
                        ('pro', 'Pro'),
                        ('pro_plus', 'Pro+'),
                      ])
                        AppFilterChip(
                          label: label,
                          showCheckmark: true,
                          selected: a.tiers.contains(tier),
                          onPressed: () {
                            final next = {...a.tiers};
                            if (!next.remove(tier)) next.add(tier);
                            _setAudience(a.copyWith(tiers: next));
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<String?>(
                    initialValue: a.serviceTypeId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Serviço'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Todos os serviços'),
                      ),
                      for (final s in services)
                        DropdownMenuItem(value: s.id, child: Text(s.name)),
                    ],
                    onChanged: (id) =>
                        _setAudience(a.copyWith(serviceTypeId: () => id)),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  controller: _area,
                  label: 'Localidade (opcional)',
                  helperText: a.isWorkers
                      ? 'Procura na localidade do perfil do jardineiro.'
                      : 'Clientes com algum pedido nesta localidade.',
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _counting ? null : _countRecipients,
                      icon: _counting
                          ? const SizedBox.square(
                              dimension: AppSizes.inlineSpinner,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.groups_outlined,
                              size: AppSizes.inlineIcon,
                            ),
                      label: const Text('Contar destinatários'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    if (count != null)
                      Expanded(
                        child: Text(
                          count == 0
                              ? 'Ninguém com estes filtros.'
                              : '$count pessoas',
                          style: textTheme.titleSmall?.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppStaggeredEntrance(
          index: 1,
          child: AdminPanelCard(
            title: 'Mensagem',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  controller: _title,
                  label: 'Título',
                  maxLength: adminNoticeTitleMax,
                ),
                const SizedBox(height: AppSpacing.xs),
                AppTextField(
                  controller: _body,
                  label: 'Texto',
                  maxLength: adminNoticeBodyMax,
                  minLines: 3,
                  maxLines: 6,
                  textInputAction: TextInputAction.newline,
                ),
                if (title.isNotEmpty || body.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Pré-visualização',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  AdminNoticePreview(title: title, body: body),
                ],
                const SizedBox(height: AppSpacing.md),
                PrimaryActionButton(
                  label: count == null || count == 0
                      ? 'Conta os destinatários primeiro'
                      : 'Enviar a $count pessoas',
                  isLoading: _sending,
                  onPressed:
                      textOk && (count ?? 0) > 0 && !_sending && !partnerHidden
                      ? _send
                      : null,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Enviados',
          style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xs),
        noticesAsync.when(
          loading: () => const AdminLoadingBlocks(count: 2, height: 90),
          error: (e, _) => AppInlineError(
            message: friendlyError(e),
            onRetry: () => ref.invalidate(adminNoticesProvider),
          ),
          data: (rows) => rows.isEmpty
              ? const AppEmptyState(
                  icon: Icons.campaign_outlined,
                  title: 'Ainda sem avisos',
                  message: 'Os avisos enviados aparecem aqui.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, row) in rows.indexed) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.xs),
                      AppStaggeredEntrance(
                        index: i < 6 ? i : 6,
                        child: AdminNoticeCard(
                          notice: row,
                          serviceName: _serviceName(
                            services,
                            row.audience['service_type_id'],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  static String? _serviceName(List<ServiceType> services, Object? id) {
    if (id is! String) return null;
    for (final s in services) {
      if (s.id == id) return s.name;
    }
    return 'Serviço';
  }
}

/// Como o aviso aparece na lista de notificações da app.
class AdminNoticePreview extends StatelessWidget {
  const AdminNoticePreview({
    required this.title,
    required this.body,
    super.key,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppSizes.rowIconBox,
            height: AppSizes.rowIconBox,
            decoration: const BoxDecoration(
              color: AppColors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.campaign_outlined,
              size: AppSizes.rowIcon,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty ? 'Título' : title,
                  style: textTheme.titleSmall?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  body.isEmpty ? 'Texto do aviso' : body,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AdminNoticeCard extends StatelessWidget {
  const AdminNoticeCard({required this.notice, this.serviceName, super.key});

  final AdminNoticeRow notice;
  final String? serviceName;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final n = notice;
    final secondary = textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondary,
    );
    return AdminPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            n.title,
            style: textTheme.titleSmall?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            n.body,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            adminNoticeAudienceLabel(n.audience, serviceName: serviceName),
            style: secondary,
          ),
          if (n.partnerName != null)
            Text('Abre o parceiro ${n.partnerName}', style: secondary),
          Text(
            [
              '${n.recipients} destinatários',
              '${n.readCount} leram',
              adminDateTimeLabel(n.createdAt),
              ?n.adminEmail,
            ].join(' · '),
            style: secondary,
          ),
        ],
      ),
    );
  }
}

/// O aviso é sobre um parceiro: ao tocar, o jardineiro abre o ecrã dele.
class AdminNoticePartnerCard extends StatelessWidget {
  const AdminNoticePartnerCard({
    required this.partner,
    required this.onRemove,
    super.key,
  });

  final AdminPartner partner;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hidden = !partner.shownInApp();
    return AdminPanelCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(partner.kind.icon, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Aviso sobre ${partner.name}',
                  style: textTheme.titleSmall?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  hidden
                      ? 'Este parceiro não aparece na app (tem de estar '
                            '"Parceiro", com "Mostrar na app" e dentro da '
                            'validade). Muda isso antes de avisar.'
                      : 'Só para jardineiros. Ao tocar no aviso, abre o '
                            'ecrã do parceiro na app.',
                  style: textTheme.bodySmall?.copyWith(
                    color: hidden
                        ? AppStatusColor.cancelled.foreground
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onRemove, child: const Text('Tirar')),
        ],
      ),
    );
  }
}
