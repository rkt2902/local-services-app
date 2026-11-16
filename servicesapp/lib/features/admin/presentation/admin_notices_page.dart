import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
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
import 'widgets/admin_panel_widgets.dart';
import 'widgets/admin_stat_widgets.dart';

const adminNoticeTitleMax = 80;
const adminNoticeBodyMax = 500;

/// Avisos (`/admin/avisos`, 0081): mensagem da ProJardim a um grupo de
/// jardineiros ou clientes, na app e por push. Primeiro conta quem
/// recebe; a BD só envia se o número ainda for o mesmo.
class AdminNoticesPage extends ConsumerStatefulWidget {
  const AdminNoticesPage({super.key});

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

  @override
  void initState() {
    super.initState();
    _title.addListener(_rebuild);
    _body.addListener(_rebuild);
    _area.addListener(_areaChanged);
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
          );
      if (!mounted) return;
      toast.show('Aviso enviado a $sent pessoas.');
      _title.clear();
      _body.clear();
      setState(() => _count = null);
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
                    for (final (role, label) in const [
                      ('worker', 'Jardineiros'),
                      ('client', 'Clientes'),
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
                  onPressed: textOk && (count ?? 0) > 0 && !_sending
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
