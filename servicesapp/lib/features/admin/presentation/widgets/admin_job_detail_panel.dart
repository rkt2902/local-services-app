import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/utils/error_utils.dart';
import '../../../../core/widgets/address_map_link.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_filter_chip.dart';
import '../../../../core/widgets/app_inline_error.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/app_status_badge.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/photo_viewer_screen.dart';
import '../../application/admin_labels.dart';
import '../../application/admin_providers.dart';
import '../../data/admin_support_models.dart';
import '../admin_jobs_page.dart';
import 'admin_panel_widgets.dart';
import 'admin_stat_widgets.dart';

enum AdminJobTab {
  timeline('Linha do tempo', Icons.timeline_rounded),
  photos('Fotos', Icons.photo_library_outlined),
  proposals('Propostas', Icons.request_quote_outlined),
  team('Equipa', Icons.groups_outlined),
  notifications('Avisos', Icons.notifications_none_rounded),
  address('Morada', Icons.place_outlined);

  const AdminJobTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Ficha de um pedido: cabeçalho e 6 separadores. Responde a "o que
/// aconteceu com isto?". Abrir a ficha fica registado (admin_get_job).
class AdminJobDetailPanel extends ConsumerWidget {
  const AdminJobDetailPanel({required this.jobId, this.onClose, super.key});

  final String jobId;

  /// Botão de voltar à lista (só quando a ficha está por cima dela).
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobAsync = ref.watch(adminJobDetailProvider(jobId));
    return jobAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: AdminLoadingBlocks(),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: AppInlineError(
          message: friendlyError(error),
          onRetry: () => ref.invalidate(adminJobDetailProvider(jobId)),
        ),
      ),
      data: (job) => AdminJobDetailView(
        job: job,
        onClose: onClose,
        onOpenPerson: (route) => context.go(route),
        onRefresh: () => ref.refresh(adminJobDetailProvider(jobId).future),
      ),
    );
  }
}

/// Vista pura da ficha (sem providers), para testes.
class AdminJobDetailView extends StatefulWidget {
  const AdminJobDetailView({
    required this.job,
    required this.onOpenPerson,
    required this.onRefresh,
    this.onClose,
    this.initialTab = AdminJobTab.timeline,
    this.photosTab,
    this.addressTab,
    super.key,
  });

  final AdminJobDetail job;
  final ValueChanged<String> onOpenPerson;
  final Future<void> Function() onRefresh;
  final VoidCallback? onClose;
  final AdminJobTab initialTab;

  /// Substituem os separadores que chamam a BD (para testes).
  final Widget? photosTab;
  final Widget? addressTab;

  @override
  State<AdminJobDetailView> createState() => _AdminJobDetailViewState();
}

class _AdminJobDetailViewState extends State<AdminJobDetailView> {
  late AdminJobTab _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          _Header(
            job: job,
            onClose: widget.onClose,
            onOpenPerson: widget.onOpenPerson,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final tab in AdminJobTab.values)
                AppFilterChip(
                  label: _tabLabel(tab, job),
                  leadingIcon: tab.icon,
                  selected: _tab == tab,
                  onPressed: () => setState(() => _tab = tab),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppFadeThroughSwitcher(
            switchKey: _tab,
            child: switch (_tab) {
              AdminJobTab.timeline => _TimelineTab(job: job),
              AdminJobTab.photos =>
                widget.photosTab ?? _PhotosTab(jobId: job.jobId),
              AdminJobTab.proposals => _ProposalsTab(
                proposals: job.proposals,
                onOpenPerson: widget.onOpenPerson,
              ),
              AdminJobTab.team => _TeamTab(
                team: job.team,
                onOpenPerson: widget.onOpenPerson,
              ),
              AdminJobTab.notifications => _NotificationsTab(
                items: job.notifications,
              ),
              AdminJobTab.address => widget.addressTab ?? _AddressTab(job: job),
            },
          ),
        ],
      ),
    );
  }

  String _tabLabel(AdminJobTab tab, AdminJobDetail job) => switch (tab) {
    AdminJobTab.photos => '${tab.label} (${job.photoCount})',
    AdminJobTab.proposals => '${tab.label} (${job.proposals.length})',
    AdminJobTab.notifications => '${tab.label} (${job.notifications.length})',
    _ => tab.label,
  };
}

class _Header extends StatelessWidget {
  const _Header({
    required this.job,
    required this.onClose,
    required this.onOpenPerson,
  });

  final AdminJobDetail job;
  final VoidCallback? onClose;
  final ValueChanged<String> onOpenPerson;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheduled = job.confirmedDate != null
        ? '${adminDateLabel(job.confirmedDate)}'
              '${job.confirmedTime == null ? '' : ' às ${adminTimeLabel(job.confirmedTime)}'}'
        : job.preferredDate != null
        ? 'Preferida ${adminDateLabel(job.preferredDate)}'
        : 'A combinar';
    final deadlines = <(String, DateTime?)>[
      ('Expira', job.expiresAt),
      ('Confirmação automática', job.autoConfirmAt),
      ('Reserva de 24 horas', job.directUntil),
    ].where((d) => d.$2 != null).toList();

    return AdminPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (onClose != null)
                IconButton(
                  tooltip: 'Voltar à lista',
                  onPressed: onClose,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              Expanded(
                child: Text(
                  job.serviceName ?? 'Pedido',
                  style: textTheme.titleLarge?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (job.urgent) ...[
                const AppStatusBadge(
                  label: 'Urgente',
                  statusColor: AppStatusColor.cancelled,
                  dense: true,
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              AdminJobStatusBadge(
                status: job.status,
                statusValue: job.statusValue,
                proposalCount: job.proposalCount,
                dense: false,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          AdminInfoRow(
            label: 'Id',
            value: adminShortId(job.jobId),
            trailing: AdminCopyButton(value: job.jobId, tooltip: 'Copiar id'),
          ),
          _PersonRow(
            label: 'Cliente',
            person: job.client,
            route: job.client == null
                ? null
                : '/admin/clientes/${job.client!.id}',
            onOpen: onOpenPerson,
          ),
          _PersonRow(
            label: 'Jardineiro',
            person: job.worker ?? job.directWorker,
            suffix: job.worker == null && job.directWorker != null
                ? ' (pedido direto)'
                : '',
            route: (job.worker ?? job.directWorker) == null
                ? null
                : '/admin/workers/${(job.worker ?? job.directWorker)!.id}',
            onOpen: onOpenPerson,
          ),
          AdminInfoRow(label: 'Zona', value: job.locationArea ?? '—'),
          AdminInfoRow(label: 'Data', value: scheduled),
          AdminInfoRow(
            label: 'Pedido direto',
            value: job.isDirect ? 'Sim' : 'Não',
          ),
          AdminInfoRow(
            label: 'Criado',
            value: adminDateTimeLabel(job.createdAt),
          ),
          if (job.cancelReason != null)
            AdminInfoRow(
              label: 'Motivo do cancelamento',
              value: [job.cancelReason!, ?job.cancelReasonDetail].join(' · '),
            ),
          for (final (label, at) in deadlines)
            AdminInfoRow(
              label: label,
              value: '${adminDateTimeLabel(at)} (${adminCountdownLabel(at)})',
            ),
          if (job.description != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              job.description!,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (job.reports.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            for (final r in job.reports)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppStatusColor.cancelled.background,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                ),
                child: Text(
                  'Reporte de ${r.reporterName ?? 'alguém'} a '
                  '${adminDateTimeLabel(r.createdAt)}: ${r.description}',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppStatusColor.cancelled.foreground,
                  ),
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Ficha aberta ${job.views} ${job.views == 1 ? 'vez' : 'vezes'} '
            'pelo suporte (fica registado).',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.label,
    required this.person,
    required this.route,
    required this.onOpen,
    this.suffix = '',
  });

  final String label;
  final AdminPersonRef? person;
  final String? route;
  final ValueChanged<String> onOpen;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final p = person;
    final name = p == null
        ? '—'
        : '${p.fullName ?? 'Sem nome'}${p.deleted ? ' (conta eliminada)' : ''}$suffix';
    return AdminInfoRow(
      label: label,
      value: name,
      trailing: route == null
          ? null
          : TextButton(
              onPressed: () => onOpen(route!),
              child: const Text('Abrir ficha'),
            ),
    );
  }
}

// ── Separadores ─────────────────────────────────────────────────

class _TimelineTab extends StatelessWidget {
  const _TimelineTab({required this.job});

  final AdminJobDetail job;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (job.timeline.isEmpty) {
      return const AppEmptyState(
        icon: Icons.timeline_rounded,
        title: 'Sem eventos',
        message: 'Este pedido ainda não tem eventos registados.',
      );
    }
    final hasBackfill = job.timeline.any((e) => e.isBackfill);
    return AdminPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasBackfill)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                'Pedido anterior ao registo de eventos: parte da linha do '
                'tempo foi reconstruída a partir das datas guardadas.',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          for (final (i, e) in job.timeline.indexed)
            AppStaggeredEntrance(
              index: i < 6 ? i : 6,
              child: _TimelineItem(
                event: e,
                isLast: i == job.timeline.length - 1,
              ),
            ),
        ],
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.event, required this.isLast});

  final AdminJobEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isAdmin = event.actorKind == AdminActorKind.admin;
    final reason = event.data['reason_detail'] ?? event.data['reason'];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.xxs),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isAdmin ? AppColors.logoAccent : AppColors.primary,
                  ),
                ),
                if (!isLast)
                  const Expanded(
                    child: VerticalDivider(
                      width: 2,
                      thickness: 2,
                      color: AppColors.divider,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    adminJobEventLabel(event.type, event.data),
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    '${adminDateTimeLabel(event.at)} · '
                    '${adminActorLabel(event.actorKind, event.actorName)}',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (reason is String && reason.isNotEmpty)
                    Text(
                      'Motivo: $reason',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotosTab extends ConsumerWidget {
  const _PhotosTab({required this.jobId});

  final String jobId;

  static const _kindLabels = {
    'request': 'Do pedido',
    'before': 'Antes',
    'after': 'Depois',
    'completion': 'Ao concluir',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final photosAsync = ref.watch(adminJobPhotosProvider(jobId));
    return photosAsync.when(
      loading: () => const AdminLoadingBlocks(count: 2, height: 120),
      error: (e, _) => AppInlineError(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(adminJobPhotosProvider(jobId)),
      ),
      data: (photos) {
        if (photos.isEmpty) {
          return const AppEmptyState(
            icon: Icons.photo_library_outlined,
            title: 'Sem fotos',
            message: 'Nem o cliente nem o jardineiro juntaram fotos.',
          );
        }
        final urls = photos.map((p) => p.url).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ver as fotos fica registado.',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final (i, photo) in photos.indexed)
                  SizedBox(
                    width: 160,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.input),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PhotoViewerScreen(
                                photoUrls: urls,
                                initialIndex: i,
                              ),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              AppRadius.input,
                            ),
                            child: Image.network(
                              photo.url,
                              width: 160,
                              height: 120,
                              cacheWidth: 320,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                width: 160,
                                height: 120,
                                color: AppColors.divider,
                                child: const Icon(
                                  Icons.broken_image_outlined,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          '${_kindLabels[photo.kind] ?? photo.kind} · '
                          '${photo.takenBy == 'client' ? 'cliente' : 'jardineiro'}',
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          adminDateTimeLabel(photo.createdAt),
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ProposalsTab extends StatelessWidget {
  const _ProposalsTab({required this.proposals, required this.onOpenPerson});

  final List<AdminProposalItem> proposals;
  final ValueChanged<String> onOpenPerson;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (proposals.isEmpty) {
      return const AppEmptyState(
        icon: Icons.request_quote_outlined,
        title: 'Sem propostas',
        message: 'Nenhum jardineiro enviou proposta para este pedido.',
      );
    }
    return Column(
      children: [
        for (final (i, p) in proposals.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          AppStaggeredEntrance(
            index: i < 6 ? i : 6,
            child: AdminPanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.workerName ?? 'Jardineiro sem nome',
                          style: textTheme.titleSmall?.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Builder(
                        builder: (_) {
                          final (label, color) = adminProposalStatus(
                            p.status,
                            p.isAccepted,
                          );
                          return AppStatusBadge(
                            label: label,
                            statusColor: color,
                            dense: true,
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AdminInfoRow(label: 'Preço', value: adminProposalPrice(p)),
                  AdminInfoRow(
                    label: 'Duração',
                    value: adminProposalDuration(p),
                  ),
                  if (p.scheduledDate != null)
                    AdminInfoRow(
                      label: 'Data proposta',
                      value:
                          '${adminDateLabel(p.scheduledDate)}'
                          '${p.scheduledTime == null ? '' : ' às ${adminTimeLabel(p.scheduledTime)}'}',
                    ),
                  if (p.peopleNeeded > 1)
                    AdminInfoRow(label: 'Pessoas', value: '${p.peopleNeeded}'),
                  if (p.includes.isNotEmpty)
                    AdminInfoRow(label: 'Inclui', value: p.includes.join(', ')),
                  if (p.validUntil != null)
                    AdminInfoRow(
                      label: 'Válida até',
                      value: adminDateLabel(p.validUntil),
                    ),
                  if (p.notes != null)
                    AdminInfoRow(label: 'Nota', value: p.notes!),
                  AdminInfoRow(
                    label: 'Enviada',
                    value: adminDateTimeLabel(p.createdAt),
                  ),
                  AdminInfoRow(
                    label: 'Última mudança',
                    value: adminDateTimeLabel(p.updatedAt),
                  ),
                  if (p.workerId != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () =>
                            onOpenPerson('/admin/workers/${p.workerId}'),
                        child: const Text('Abrir ficha do jardineiro'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// "15 €/h" ou "120 € (valor total)".
String adminProposalPrice(AdminProposalItem p) {
  if (p.isFixedTotal) {
    return p.totalPrice == null
        ? '—'
        : '${adminEuroLabel(p.totalPrice!)} (valor total)';
  }
  return p.hourlyRate == null ? '—' : '${adminEuroLabel(p.hourlyRate!)}/h';
}

/// "2 a 4 h" ou "3 dias".
String adminProposalDuration(AdminProposalItem p) {
  String range(num? a, num? b, String unit) {
    if (a == null) return '—';
    final fa = a % 1 == 0 ? a.toInt().toString() : a.toString();
    if (b == null || b == a) return '$fa $unit';
    final fb = b % 1 == 0 ? b.toInt().toString() : b.toString();
    return '$fa a $fb $unit';
  }

  if (p.daysMin != null) return range(p.daysMin, p.daysMax, 'dias');
  return range(p.hoursMin, p.hoursMax, 'h');
}

class _TeamTab extends StatelessWidget {
  const _TeamTab({required this.team, required this.onOpenPerson});

  final List<AdminHelpRequestItem> team;
  final ValueChanged<String> onOpenPerson;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (team.isEmpty) {
      return const AppEmptyState(
        icon: Icons.groups_outlined,
        title: 'Sem equipa',
        message: 'O jardineiro não pediu ajudantes para este pedido.',
      );
    }
    return Column(
      children: [
        for (final (i, h) in team.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          AppStaggeredEntrance(
            index: i < 6 ? i : 6,
            child: AdminPanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Pedido de ajuda · ${h.slotsNeeded} '
                          '${h.slotsNeeded == 1 ? 'vaga' : 'vagas'}',
                          style: textTheme.titleSmall?.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Builder(
                        builder: (_) {
                          final (label, color) = adminHelpStatus(h.status);
                          return AppStatusBadge(
                            label: label,
                            statusColor: color,
                            dense: true,
                          );
                        },
                      ),
                    ],
                  ),
                  Text(
                    [
                      'Criado ${adminDateTimeLabel(h.createdAt)}',
                      if (h.afterConfirmation) 'depois de confirmado',
                      if (h.equipmentRequired) 'com equipamento',
                    ].join(' · '),
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  if (h.acceptances.isEmpty)
                    Text(
                      'Ainda sem candidatos.',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  for (final a in h.acceptances)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  a.workerName ?? 'Sem nome',
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  [
                                    if (a.agreedRate != null)
                                      '${adminEuroLabel(a.agreedRate!)}/h combinado',
                                    if (a.broughtEquipment) 'leva equipamento',
                                    adminDateTimeLabel(a.createdAt),
                                  ].join(' · '),
                                  style: textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                if (a.message != null)
                                  Text(
                                    '"${a.message}"',
                                    style: textTheme.bodySmall?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Builder(
                            builder: (_) {
                              final (label, color) = adminHelpStatus(a.status);
                              return AppStatusBadge(
                                label: label,
                                statusColor: color,
                                dense: true,
                              );
                            },
                          ),
                          if (a.workerId != null)
                            IconButton(
                              tooltip: 'Abrir ficha',
                              onPressed: () =>
                                  onOpenPerson('/admin/workers/${a.workerId}'),
                              icon: const Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _NotificationsTab extends StatelessWidget {
  const _NotificationsTab({required this.items});

  final List<AdminNotificationItem> items;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (items.isEmpty) {
      return const AppEmptyState(
        icon: Icons.notifications_off_outlined,
        title: 'Sem avisos',
        message: 'A app não enviou avisos ligados a este pedido.',
      );
    }
    return AdminPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Push: "tinha aparelho" diz se a pessoa tinha um telemóvel '
            'registado quando o aviso saiu. Sem aparelho, o aviso só aparece '
            'dentro da app.',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final (i, n) in items.indexed) ...[
            if (i > 0)
              const Divider(height: AppSpacing.md, color: AppColors.divider),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.title ?? n.type,
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '${n.userName ?? 'Sem nome'} '
                        '(${switch (n.userRole) {
                          'client' => 'cliente',
                          'worker' => 'jardineiro',
                          _ => 'outro',
                        }}) · ${adminDateTimeLabel(n.createdAt)}',
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xxs,
                  children: [
                    AppStatusBadge(
                      label: n.read ? 'Lido' : 'Por ler',
                      statusColor: n.read
                          ? AppStatusColor.success
                          : AppStatusColor.waiting,
                      dense: true,
                    ),
                    AppStatusBadge(
                      label: n.hadPushToken ? 'Tinha aparelho' : 'Sem aparelho',
                      statusColor: n.hadPushToken
                          ? AppStatusColor.info
                          : AppStatusColor.neutral,
                      dense: true,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Morada exata só com um clique, que fica registado.
class _AddressTab extends ConsumerStatefulWidget {
  const _AddressTab({required this.job});

  final AdminJobDetail job;

  @override
  ConsumerState<_AddressTab> createState() => _AddressTabState();
}

class _AddressTabState extends ConsumerState<_AddressTab> {
  AdminRevealedAddress? _address;
  bool _loading = false;

  Future<void> _reveal() async {
    setState(() => _loading = true);
    try {
      final address = await ref
          .read(adminRepositoryProvider)
          .revealAddress(widget.job.jobId);
      if (mounted) setState(() => _address = address);
    } catch (e) {
      if (mounted) AppToast.of(context).show(friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminAddressView(
      zone: widget.job.locationArea,
      hasAddress: widget.job.hasAddress,
      address: _address,
      loading: _loading,
      onReveal: _reveal,
    );
  }
}

/// Vista pura do separador Morada.
class AdminAddressView extends StatelessWidget {
  const AdminAddressView({
    required this.zone,
    required this.hasAddress,
    required this.address,
    required this.loading,
    required this.onReveal,
    super.key,
  });

  final String? zone;
  final bool hasAddress;
  final AdminRevealedAddress? address;
  final bool loading;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final a = address;
    return AdminPanelCard(
      child: AppFadeThroughSwitcher(
        switchKey: a == null ? 'hidden' : 'shown',
        child: a == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AdminInfoRow(label: 'Zona', value: zone ?? '—'),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'A morada exata é um dado pessoal. Só a abras se precisares '
                    'dela para resolver o caso: a consulta fica registada.',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: hasAddress && !loading ? onReveal : null,
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: Text(hasAddress ? 'Mostrar morada' : 'Sem morada'),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (a.lat != null && a.lng != null)
                    AddressMapLink(
                      address: a.addressText ?? '',
                      lat: a.lat!,
                      lng: a.lng!,
                    )
                  else
                    SelectableText(
                      a.addressText ?? '—',
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  if (a.workerLocationName != null)
                    AdminInfoRow(
                      label: 'Base do jardineiro',
                      value: a.workerLocationName!,
                    ),
                  if (a.distanceKm != null)
                    AdminInfoRow(
                      label: 'Distância em linha reta',
                      value: '${a.distanceKm!.toStringAsFixed(1)} km',
                    ),
                  if (a.workerBaseLat != null && a.workerBaseLng != null)
                    AddressMapLink(
                      address: 'Base do jardineiro no mapa',
                      lat: a.workerBaseLat!,
                      lng: a.workerBaseLng!,
                    ),
                ],
              ),
      ),
    );
  }
}
