import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_filter_chip.dart';
import '../../../core/widgets/app_inline_error.dart';
import '../../../core/widgets/app_motion.dart';
import '../application/admin_providers.dart';
import '../data/admin_partner_stats_models.dart';
import 'widgets/admin_panel_widgets.dart';
import 'widgets/admin_stat_widgets.dart';

/// Meses dos trabalhos concluídos.
const adminPartnerStatsPeriods = <(String, int)>[
  ('3 meses', 3),
  ('6 meses', 6),
  ('12 meses', 12),
];

/// Estatísticas para parceiros (`/admin/estatisticas`, 0084): os números
/// para negociar com gasolineiras, seguradoras e afins. Contas eliminadas,
/// suspensas e de admin não contam.
class AdminPartnerStatsPage extends ConsumerStatefulWidget {
  const AdminPartnerStatsPage({super.key});

  @override
  ConsumerState<AdminPartnerStatsPage> createState() =>
      _AdminPartnerStatsPageState();
}

class _AdminPartnerStatsPageState extends ConsumerState<AdminPartnerStatsPage> {
  int _months = 6;

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(adminPartnerStatsProvider(_months));
    final textTheme = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: () => ref.refresh(adminPartnerStatsProvider(_months).future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.xl),
        children: [
          Text(
            'Estatísticas para parceiros',
            style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Profissionais com perfil feito, combustível que declaram e '
            'trabalhos concluídos. Contas eliminadas, suspensas e de admin '
            'ficam de fora.',
            style:
                textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          statsAsync.when(
            loading: () => const AdminLoadingBlocks(count: 4, height: 180),
            error: (e, _) => AppInlineError(
              message: friendlyError(e),
              onRetry: () => ref.invalidate(adminPartnerStatsProvider(_months)),
            ),
            data: (stats) => AdminPartnerStatsView(
              stats: stats,
              periodChips: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final (label, months) in adminPartnerStatsPeriods)
                    AppFilterChip(
                      label: label,
                      selected: _months == months,
                      onPressed: () => setState(() => _months = months),
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

/// Os cartões, sem Riverpod.
class AdminPartnerStatsView extends StatelessWidget {
  const AdminPartnerStatsView({
    required this.stats,
    required this.periodChips,
    super.key,
  });

  final AdminPartnerStats stats;
  final Widget periodChips;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final estimate = s.estimatedLitersAll;
    final cards = <Widget>[
      AdminStatsCard(
        title: 'Profissionais',
        stats: [
          AdminStat(label: 'Registados', value: '${s.registered}'),
          AdminStat(
            label: 'Ativos (30 dias)',
            value: '${s.active}',
            caption: '${adminPercent(s.active, s.registered)} dos registados',
          ),
          AdminStat(
            label: 'Pro e Pro+',
            value: '${s.pro + s.proPlus}',
            caption: '${s.pro} Pro · ${s.proPlus} Pro+',
          ),
        ],
      ),
      AdminStatsCard(
        title: 'Inquérito de combustível',
        stats: [
          AdminStat(
            label: 'Responderam',
            value: '${s.answered} de ${s.registered}',
            caption: adminPercent(s.answered, s.registered),
          ),
          AdminStat(
            label: 'Declarado por mês',
            value: adminLitersLabel(s.totalLiters),
          ),
          AdminStat(
            label: 'Estimativa para todos',
            value: estimate == null ? '—' : '~${adminLitersLabel(estimate)}',
            caption: 'se os outros gastarem o mesmo',
          ),
        ],
      ),
      _FuelByTypeCard(fuel: s.fuel),
      _DistrictsCard(districts: s.districts, fuel: s.fuel),
      _CompletedCard(months: s.completed, periodChips: periodChips),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, card) in cards.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          AppStaggeredEntrance(index: i, child: card),
        ],
      ],
    );
  }
}

/// Uma linha com nome, valor à direita e barra por baixo.
class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.value,
    required this.fraction,
    this.detail,
  });

  final String label;
  final String value;
  final double fraction;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textPrimary)),
              ),
              Text(value,
                  style: textTheme.titleSmall
                      ?.copyWith(color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: fraction.clamp(0, 1),
              minHeight: AppSizes.progressBarHeight,
              color: AppColors.primary,
              backgroundColor: AppColors.primaryContainer,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(detail!,
                style: textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}

class _FuelByTypeCard extends StatelessWidget {
  const _FuelByTypeCard({required this.fuel});

  final List<AdminFuelTotal> fuel;

  @override
  Widget build(BuildContext context) {
    final max = fuel.fold<double>(0, (a, f) => f.liters > a ? f.liters : a);
    return AdminPanelCard(
      title: 'Combustível por tipo (por mês)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final f in fuel)
            _BarRow(
              label: f.name,
              value: adminLitersLabel(f.liters),
              fraction: max <= 0 ? 0 : f.liters / max,
              detail: f.workers == 1
                  ? '1 Profissional'
                  : '${f.workers} Profissionais',
            ),
        ],
      ),
    );
  }
}

class _DistrictsCard extends StatelessWidget {
  const _DistrictsCard({required this.districts, required this.fuel});

  final List<AdminDistrictStats> districts;
  final List<AdminFuelTotal> fuel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final max = districts.fold<int>(
        0, (a, d) => d.registered > a ? d.registered : a);
    final names = {for (final f in fuel) f.id: f.name};
    return AdminPanelCard(
      title: 'Por distrito',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Distrito aproximado: a capital de distrito mais perto da base '
            'de cada Profissional.',
            style:
                textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (districts.isEmpty)
            Text('Ainda sem Profissionais com base definida.',
                style: textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary)),
          for (final d in districts)
            _BarRow(
              label: d.district,
              value: '${d.registered}',
              fraction: max <= 0 ? 0 : d.registered / max,
              detail: [
                '${d.active} ativos',
                '${d.answered} responderam',
                if (d.totalLiters > 0)
                  d.litersByFuel.entries
                      .where((e) => e.value > 0)
                      .map((e) =>
                          '${names[e.key] ?? e.key} ${adminLitersLabel(e.value)}')
                      .join(', '),
              ].join(' · '),
            ),
        ],
      ),
    );
  }
}

class _CompletedCard extends StatelessWidget {
  const _CompletedCard({required this.months, required this.periodChips});

  final List<AdminCompletedMonth> months;
  final Widget periodChips;

  @override
  Widget build(BuildContext context) {
    final max = months.fold<int>(0, (a, m) => m.total > a ? m.total : a);
    return AdminPanelCard(
      title: 'Trabalhos concluídos por mês',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          periodChips,
          const SizedBox(height: AppSpacing.sm),
          for (final m in months.reversed)
            _BarRow(
              label: adminMonthLabel(m.month),
              value: '${m.total}',
              fraction: max <= 0 ? 0 : m.total / max,
              detail: m.byCategory.isEmpty
                  ? null
                  : (m.byCategory.entries.toList()
                        ..sort((a, b) => b.value.compareTo(a.value)))
                      .map((e) => '${e.key} ${e.value}')
                      .join(' · '),
            ),
        ],
      ),
    );
  }
}
