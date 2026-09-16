import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/theme/app_status_presentation.dart';
import '../../../../core/widgets/address_map_link.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/app_status_badge.dart';
import '../../../../core/widgets/primary_action_button.dart';

enum ClientJobsTab { active, history }

/// Dados de apresentação de "Os meus pedidos" (cliente).
///
/// A integração (client_jobs_screen.dart) mapeia `clientJobsProvider` +
/// `serviceTypesProvider` para esta estrutura. Este widget não consulta
/// providers, repositories ou Supabase diretamente.
class ClientJobsViewData {
  const ClientJobsViewData({
    required this.activeTabLabel,
    required this.historyTabLabel,
    required this.activeJobs,
    required this.historyJobs,
  });

  /// Já formatado pela integração. Ex.: "Ativos · 3".
  final String activeTabLabel;
  final String historyTabLabel;

  final List<ClientJobListItemViewData> activeJobs;
  final List<ClientJobListItemViewData> historyJobs;
}

class ClientJobListItemViewData {
  const ClientJobListItemViewData({
    required this.jobId,
    required this.title,
    required this.addressText,
    required this.locationLat,
    required this.locationLng,
    required this.dateLabel,
    required this.serviceIcon,
    required this.statusPresentation,
    this.secondaryStatusPresentation,
  });

  final String jobId;
  final String title;

  /// Morada + coordenadas, não um texto já formatado — o card usa
  /// `AddressMapLink` (o mesmo widget tappable já usado nos outros ecrãs),
  /// não uma linha de texto estática.
  final String addressText;
  final double locationLat;
  final double locationLng;

  /// "Hoje"/"Amanhã"/data formatada/"Flexível"/"Ver disponibilidade" —
  /// já convertido de `DateMode`/`preferredDate` pela integração
  /// (`jobDeadlineLabel`, `core/utils/date_labels.dart`).
  final String dateLabel;

  final IconData serviceIcon;

  /// Presenter oficial de `JobStatus` (já inclui a contagem de propostas
  /// no label quando `open` — não é um badge separado).
  final AppStatusPresentation statusPresentation;

  /// Presenter de `RescheduleStatus.pending` quando há remarcação
  /// pendente — `null` na maioria dos casos.
  final AppStatusPresentation? secondaryStatusPresentation;
}

class ClientJobsScreen extends StatefulWidget {
  const ClientJobsScreen({
    super.key,
    required this.dataAsync,
    required this.onOpenJob,
    required this.onCreateJob,
    this.onRetry,
  });

  final AsyncValue<ClientJobsViewData> dataAsync;

  final ValueChanged<String> onOpenJob;
  final VoidCallback onCreateJob;

  final VoidCallback? onRetry;

  @override
  State<ClientJobsScreen> createState() => _ClientJobsScreenState();
}

class _ClientJobsScreenState extends State<ClientJobsScreen> {
  ClientJobsTab _selectedTab = ClientJobsTab.active;

  void _selectTab(ClientJobsTab tab) {
    if (_selectedTab == tab) return;
    setState(() => _selectedTab = tab);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: widget.dataAsync.when(
          loading: () => const _ClientJobsLoading(),
          error: (_, _) => _ClientJobsError(onRetry: widget.onRetry),
          data: (data) => _ClientJobsContent(
            data: data,
            selectedTab: _selectedTab,
            onSelectTab: _selectTab,
            onOpenJob: widget.onOpenJob,
            onCreateJob: widget.onCreateJob,
          ),
        ),
      ),
    );
  }
}

class _ClientJobsContent extends StatelessWidget {
  const _ClientJobsContent({
    required this.data,
    required this.selectedTab,
    required this.onSelectTab,
    required this.onOpenJob,
    required this.onCreateJob,
  });

  final ClientJobsViewData data;
  final ClientJobsTab selectedTab;

  final ValueChanged<ClientJobsTab> onSelectTab;
  final ValueChanged<String> onOpenJob;
  final VoidCallback onCreateJob;

  @override
  Widget build(BuildContext context) {
    final jobs =
        selectedTab == ClientJobsTab.active ? data.activeJobs : data.historyJobs;

    return Column(
      children: [
        _Header(
          activeTabLabel: data.activeTabLabel,
          historyTabLabel: data.historyTabLabel,
          selectedTab: selectedTab,
          onSelectTab: onSelectTab,
        ),
        Expanded(
          // Chave = a tab (índice), não os dados — um refresh em segundo
          // plano na mesma tab não reanima nada, só a troca de tab o faz
          // (mesmo raciocínio já usado no ecrã de pedidos de ajuda).
          child: AppFadeThroughSwitcher(
            switchKey: selectedTab,
            child: jobs.isEmpty
                ? _EmptyState(tab: selectedTab, onCreateJob: onCreateJob)
                : _JobsList(jobs: jobs, tab: selectedTab, onOpenJob: onOpenJob),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.activeTabLabel,
    required this.historyTabLabel,
    required this.selectedTab,
    required this.onSelectTab,
  });

  final String activeTabLabel;
  final String historyTabLabel;
  final ClientJobsTab selectedTab;

  final ValueChanged<ClientJobsTab> onSelectTab;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Os meus pedidos',
            style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          _JobsTabs(
            activeTabLabel: activeTabLabel,
            historyTabLabel: historyTabLabel,
            selectedTab: selectedTab,
            onSelectTab: onSelectTab,
          ),
        ],
      ),
    );
  }
}

class _JobsTabs extends StatelessWidget {
  const _JobsTabs({
    required this.activeTabLabel,
    required this.historyTabLabel,
    required this.selectedTab,
    required this.onSelectTab,
  });

  final String activeTabLabel;
  final String historyTabLabel;
  final ClientJobsTab selectedTab;

  final ValueChanged<ClientJobsTab> onSelectTab;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.divider,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabButton(
              label: activeTabLabel,
              selected: selectedTab == ClientJobsTab.active,
              onPressed: () => onSelectTab(ClientJobsTab.active),
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: _TabButton(
              label: historyTabLabel,
              selected: selectedTab == ClientJobsTab.history,
              onPressed: () => onSelectTab(ClientJobsTab.history),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: selected ? AppColors.surface : AppColors.background,
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.input),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(
              color: selected ? AppColors.textPrimary : AppColors.textSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _JobsList extends StatelessWidget {
  const _JobsList({required this.jobs, required this.tab, required this.onOpenJob});

  final List<ClientJobListItemViewData> jobs;
  final ClientJobsTab tab;

  final ValueChanged<String> onOpenJob;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: PageStorageKey<String>('client_jobs_${tab.name}'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xxs,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      itemCount: jobs.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final job = jobs[index];

        return AppStaggeredEntrance(
          index: index,
          child: _JobCard(
            job: job,
            historical: tab == ClientJobsTab.history,
            onTap: () => onOpenJob(job.jobId),
          ),
        );
      },
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job, required this.historical, required this.onTap});

  final ClientJobListItemViewData job;
  final bool historical;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasLocation = job.locationLat != 0 || job.locationLng != 0;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ServiceIcon(icon: job.serviceIcon, historical: historical),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        job.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  AppStatusBadge.fromPresentation(presentation: job.statusPresentation),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (hasLocation)
                AddressMapLink(
                  address: job.addressText,
                  lat: job.locationLat,
                  lng: job.locationLng,
                ),
              if (hasLocation) const SizedBox(height: AppSpacing.xs),
              _MetadataRow(
                icon: Icons.calendar_today_outlined,
                label: job.dateLabel,
                foreground: AppColors.textSecondary,
              ),
              if (job.secondaryStatusPresentation != null) ...[
                const SizedBox(height: AppSpacing.sm),
                AppStatusBadge.fromPresentation(
                  presentation: job.secondaryStatusPresentation!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceIcon extends StatelessWidget {
  const _ServiceIcon({required this.icon, required this.historical});

  final IconData icon;
  final bool historical;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: historical ? AppStatusColor.neutral.background : AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: 22,
        color: historical ? AppStatusColor.neutral.foreground : AppColors.primary,
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.icon, required this.label, required this.foreground});

  final IconData icon;
  final String label;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: foreground),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelMedium?.copyWith(color: foreground),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// EMPTY STATES
// -----------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.tab, required this.onCreateJob});

  final ClientJobsTab tab;
  final VoidCallback onCreateJob;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: AppStaggeredEntrance(
          index: 0,
          child: tab == ClientJobsTab.active
              ? _ActiveEmpty(onCreateJob: onCreateJob)
              : const _HistoryEmpty(),
        ),
      ),
    );
  }
}

class _ActiveEmpty extends StatelessWidget {
  const _ActiveEmpty({required this.onCreateJob});

  final VoidCallback onCreateJob;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: const BoxDecoration(
            color: AppColors.primaryContainer,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.yard_outlined, color: AppColors.primary, size: 34),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Ainda sem pedidos ativos',
          textAlign: TextAlign.center,
          style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Crie um pedido e receba propostas de jardineiros perto de si.',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: 180,
          child: PrimaryActionButton(label: 'Criar pedido', onPressed: onCreateJob),
        ),
      ],
    );
  }
}

class _HistoryEmpty extends StatelessWidget {
  const _HistoryEmpty();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: AppStatusColor.neutral.background,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(Icons.history_rounded, color: AppStatusColor.neutral.foreground, size: 34),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Sem histórico',
          textAlign: TextAlign.center,
          style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Os pedidos concluídos e cancelados aparecem aqui.',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// LOADING / ERROR
// -----------------------------------------------------------------------------

class _ClientJobsLoading extends StatelessWidget {
  const _ClientJobsLoading();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Os meus pedidos',
                style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppSkeletonShimmer(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.input),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xxs,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            itemCount: 3,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, _) => AppSkeletonShimmer(
              child: Container(
                height: 112,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ClientJobsError extends StatelessWidget {
  const _ClientJobsError({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: AppStaggeredEntrance(
          index: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppStatusColor.cancelled.background,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(Icons.cloud_off_outlined, color: AppStatusColor.cancelled.foreground),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Não foi possível carregar os seus pedidos.',
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Verifique a ligação e tente novamente.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(
                  onPressed: onRetry,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.divider),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.input),
                    ),
                  ),
                  child: Text(
                    'Tentar novamente',
                    style: textTheme.bodyMedium
                        ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
