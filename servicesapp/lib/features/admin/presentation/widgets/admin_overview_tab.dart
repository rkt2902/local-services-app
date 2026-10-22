import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/error_utils.dart';
import '../../../../core/widgets/app_filter_chip.dart';
import '../../../../core/widgets/app_inline_error.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../application/admin_labels.dart';
import '../../application/admin_providers.dart';
import '../../data/admin_models.dart';
import 'admin_stat_widgets.dart';

/// Períodos da visão geral: (rótulo, dias). `null` = desde sempre.
const _periods = <(String, int?)>[
  ('7 dias', 7),
  ('30 dias', 30),
  ('Tudo', null),
];

class AdminOverviewTab extends ConsumerStatefulWidget {
  const AdminOverviewTab({super.key});

  @override
  ConsumerState<AdminOverviewTab> createState() => _AdminOverviewTabState();
}

class _AdminOverviewTabState extends ConsumerState<AdminOverviewTab> {
  int? _days = 30;

  @override
  Widget build(BuildContext context) {
    final overviewAsync = ref.watch(adminOverviewProvider(_days));
    return RefreshIndicator(
      onRefresh: () => ref.refresh(adminOverviewProvider(_days).future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.xl),
        children: [
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              for (final (label, days) in _periods)
                AppFilterChip(
                  label: label,
                  selected: _days == days,
                  onPressed: () => setState(() => _days = days),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          overviewAsync.when(
            loading: () => const AdminLoadingBlocks(),
            error: (error, _) => AppInlineError(
              message: friendlyError(error),
              onRetry: () => ref.invalidate(adminOverviewProvider(_days)),
            ),
            data: (overview) => AppFadeThroughSwitcher(
              switchKey: _days ?? 0,
              child: _OverviewContent(overview: overview),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewContent extends StatelessWidget {
  const _OverviewContent({required this.overview});

  final AdminOverview overview;

  List<Widget> _alerts() {
    final o = overview;
    return [
      if (o.alertOpenWithoutProposals > 0)
        AdminAlertRow(
          icon: Icons.hourglass_empty_rounded,
          message: '${o.alertOpenWithoutProposals} pedidos abertos sem '
              'propostas há mais de 12 horas',
        ),
      if (o.alertReports7d > 0)
        AdminAlertRow(
          icon: Icons.report_outlined,
          message: '${o.alertReports7d} problemas reportados nos últimos '
              '7 dias',
        ),
      if (o.alertFleetCardsPending > 0)
        AdminAlertRow(
          icon: Icons.local_gas_station_outlined,
          message: '${o.alertFleetCardsPending} cartões frota por aprovar',
        ),
      if (o.alertPlansEnding7d > 0)
        AdminAlertRow(
          icon: Icons.event_busy_outlined,
          message: '${o.alertPlansEnding7d} planos acabam nos próximos '
              '7 dias',
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final alerts = _alerts();
    final cards = <Widget>[
      if (alerts.isNotEmpty)
        Column(
          children: [
            for (final (i, alert) in alerts.indexed) ...[
              if (i > 0) const SizedBox(height: AppSpacing.xs),
              alert,
            ],
          ],
        ),
      AdminStatsCard(
        title: 'Utilizadores',
        stats: [
          AdminStat(label: 'Clientes', value: '${o.clientsTotal}',
              caption: '+${o.clientsNew} no período'),
          AdminStat(label: 'Jardineiros', value: '${o.workersTotal}',
              caption: '+${o.workersNew} no período'),
          AdminStat(label: 'Pro', value: '${o.workersPro}'),
          AdminStat(label: 'Pro+', value: '${o.workersProPlus}'),
        ],
      ),
      AdminStatsCard(
        title: 'Pedidos criados no período',
        stats: [
          AdminStat(label: 'Publicados', value: '${o.jobsPublished}'),
          AdminStat(
            label: 'Com proposta em 24 h',
            value: adminPercentLabel(o.jobsWithProposal24h, o.jobsPublished),
            caption: '${o.jobsWithProposal24h} pedidos',
          ),
          AdminStat(
            label: 'Até à 1.ª proposta',
            value: adminHoursLabel(o.avgHoursToFirstProposal),
            caption: 'em média',
          ),
          AdminStat(
            label: 'Aceites',
            value: adminPercentLabel(o.jobsAccepted, o.jobsPublished),
            caption: '${o.jobsAccepted} pedidos',
          ),
          AdminStat(label: 'Concluídos', value: '${o.jobsCompleted}'),
          AdminStat(label: 'Sem resposta', value: '${o.jobsNoResponse}'),
          AdminStat(label: 'Cancelados', value: '${o.jobsCancelled}'),
        ],
      ),
      AdminStatsCard(
        title: 'Qualidade',
        stats: [
          AdminStat(
            label: 'Média das avaliações',
            value: adminRatingLabel(o.avgRating),
            caption: '${o.ratingsCount} avaliações no período',
          ),
        ],
      ),
    ];
    return Column(
      children: [
        for (final (i, card) in cards.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          AppStaggeredEntrance(index: i, child: card),
        ],
      ],
    );
  }
}
