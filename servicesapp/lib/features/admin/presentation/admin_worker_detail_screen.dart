import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/utils/phone_utils.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/app_inline_error.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_status_badge.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/app_whatsapp_button.dart';
import '../../../core/widgets/user_avatar_with_name.dart';
import '../application/admin_labels.dart';
import '../application/admin_providers.dart';
import '../data/admin_models.dart';
import 'widgets/admin_plan_sheet.dart';
import 'widgets/admin_stat_widgets.dart';

/// Ficha de um jardineiro no painel (`/admin/workers/:id`).
class AdminWorkerDetailScreen extends ConsumerWidget {
  const AdminWorkerDetailScreen({required this.workerId, super.key});

  final String workerId;

  Future<void> _editPlan(
      BuildContext context, WidgetRef ref, AdminWorkerDetail worker) async {
    final saved = await showAdminPlanSheet(context, worker: worker);
    if (saved != true || !context.mounted) return;
    // T4: o folha já fechou; aviso, depois invalidar.
    AppToast.of(context).show('Plano atualizado.');
    ref.invalidate(adminWorkerDetailProvider(workerId));
    ref.invalidate(adminWorkersProvider);
    ref.invalidate(adminOverviewProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workerAsync = ref.watch(adminWorkerDetailProvider(workerId));
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        leading: const AppBackButton(fallbackLocation: '/admin'),
        title: Text('Jardineiro',
            style:
                textTheme.titleLarge?.copyWith(color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: workerAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: AdminLoadingBlocks(),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: AppInlineError(
              message: friendlyError(error),
              onRetry: () =>
                  ref.invalidate(adminWorkerDetailProvider(workerId)),
            ),
          ),
          data: (worker) => RefreshIndicator(
            onRefresh: () =>
                ref.refresh(adminWorkerDetailProvider(workerId).future),
            child: _WorkerDetailContent(
              worker: worker,
              onEditPlan: () => _editPlan(context, ref, worker),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkerDetailContent extends StatelessWidget {
  const _WorkerDetailContent({required this.worker, required this.onEditPlan});

  final AdminWorkerDetail worker;
  final VoidCallback onEditPlan;

  @override
  Widget build(BuildContext context) {
    final w = worker;
    final textTheme = Theme.of(context).textTheme;
    final phone = w.phone;

    final sections = <Widget>[
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: UserAvatarWithName(
                    name: w.fullName,
                    avatarUrl: w.avatarUrl,
                    radius: 26,
                    fallbackLabel: 'Sem nome',
                    nameStyle: textTheme.titleLarge
                        ?.copyWith(color: AppColors.textPrimary),
                    subtitle: [
                      if ((w.locationName ?? '').isNotEmpty) w.locationName!,
                      if (w.radiusKm != null) 'raio de ${w.radiusKm} km',
                    ].join(' · '),
                  ),
                ),
                AppStatusBadge(
                  label: w.plan.activeTier.label,
                  statusColor: adminTierStatusColor(w.plan.activeTier),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Registo a ${adminDateLabel(w.createdAt)} · última entrada '
              '${adminRelativeDateLabel(w.lastSignInAt)}',
              style:
                  textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            if (w.services.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                w.services.join(', '),
                style: textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
            if (phone != null && phone.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              AppWhatsAppButton(
                compact: true,
                onPressed: () => openWhatsAppOrWarn(context, phone),
              ),
            ],
          ],
        ),
      ),
      AdminStatsCard(
        title: 'Trabalho',
        stats: [
          AdminStat(label: 'Concluídos', value: '${w.jobsCompleted}'),
          AdminStat(label: 'Em curso ou agendados', value: '${w.jobsActive}'),
          AdminStat(
              label: 'Aceites este mês', value: '${w.jobsThisMonth}'),
          AdminStat(
            label: 'Horas registadas',
            value: adminHoursLabel(w.trackedHours),
            caption: 'pelo temporizador',
          ),
          AdminStat(
            label: 'Total estimado',
            value: adminEuroLabel(w.estimatedRevenue),
            caption: 'dos concluídos',
          ),
          AdminStat(label: 'Como ajudante', value: '${w.helperJobs}'),
        ],
      ),
      AdminStatsCard(
        title: 'Propostas e qualidade',
        stats: [
          AdminStat(label: 'Propostas enviadas', value: '${w.proposalsSent}'),
          AdminStat(
            label: 'Taxa de aceitação',
            value: adminPercentLabel(w.proposalsAccepted, w.proposalsSent),
            caption: '${w.proposalsAccepted} aceites',
          ),
          AdminStat(
            label: 'Tempo de resposta',
            value: adminHoursLabel(w.avgResponseHours),
            caption: 'desde a publicação',
          ),
          AdminStat(
            label: 'Avaliação',
            value: adminRatingLabel(w.avgRating),
            caption: '${w.ratingCount} avaliações',
          ),
          AdminStat(
            label: 'Cancelou',
            value: '${w.jobsCancelledByWorker}',
          ),
        ],
      ),
      _Card(child: _MonthlyBars(months: w.monthlyJobs)),
      _PlanCard(worker: w, onEditPlan: onEditPlan),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.xl),
      children: [
        for (final (i, section) in sections.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          AppStaggeredEntrance(index: i, child: section),
        ],
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: child,
    );
  }
}

/// Trabalhos aceites por mês, nos últimos 6 meses, em barras simples.
class _MonthlyBars extends StatelessWidget {
  const _MonthlyBars({required this.months});

  final List<AdminMonthCount> months;

  static const double _maxBarHeight = 96;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final maxCount = months.fold<int>(0, (m, e) => math.max(m, e.count));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Trabalhos aceites por mês',
            style:
                textTheme.titleMedium?.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final month in months)
              Expanded(
                child: Column(
                  children: [
                    Text('${month.count}',
                        style: textTheme.labelSmall
                            ?.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: AppSpacing.xxs),
                    Container(
                      height: maxCount == 0
                          ? AppSpacing.xxs
                          : math.max(AppSpacing.xxs,
                              _maxBarHeight * month.count / maxCount),
                      margin: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: month.count == 0
                            ? AppColors.divider
                            : AppColors.primary,
                        borderRadius: BorderRadius.circular(AppSpacing.xxs),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(adminMonthShortLabel(month.month),
                        style: textTheme.labelSmall
                            ?.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.worker, required this.onEditPlan});

  final AdminWorkerDetail worker;
  final VoidCallback onEditPlan;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final plan = worker.plan;
    final saved = plan.tier;
    final expired = saved != null && saved.isPaid && !plan.activeTier.isPaid;
    final secondary =
        textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Plano',
                    style: textTheme.titleMedium
                        ?.copyWith(color: AppColors.textPrimary)),
              ),
              AppStatusBadge(
                label: plan.activeTier.label,
                statusColor: adminTierStatusColor(plan.activeTier),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (saved == null)
            Text('Nunca teve plano atribuído: está no Grátis.',
                style: secondary)
          else ...[
            Text(
              '${saved.label} de ${adminDateLabel(plan.startsAt)} a '
              '${plan.endsAt == null ? 'sem fim' : adminDateLabel(plan.endsAt)}'
              '${expired ? ' (acabou, voltou ao Grátis)' : ''}',
              style: secondary,
            ),
            Text(
              plan.verifiedAt == null
                  ? 'Documentos por verificar'
                  : 'Documentos verificados a ${adminDateLabel(plan.verifiedAt)}',
              style: secondary,
            ),
            if ((plan.notes ?? '').isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(plan.notes!, style: textTheme.bodyMedium),
            ],
          ],
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: onEditPlan,
            icon: const Icon(Icons.workspace_premium_outlined),
            label: const Text('Mudar plano'),
          ),
          if (worker.planHistory.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Histórico',
                style: textTheme.titleSmall
                    ?.copyWith(color: AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.xxs),
            for (final change in worker.planHistory)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: Text(
                  '${adminDateLabel(change.createdAt?.toLocal())}: '
                  '${change.tier.label}'
                  '${change.endsAt == null ? '' : ' até ${adminDateLabel(change.endsAt)}'}',
                  style: secondary,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
