import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/theme/app_status_presentation.dart';
import '../../../../core/widgets/address_map_link.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/app_status_badge.dart';
import '../../../../core/widgets/app_tab_header.dart';
import '../../../../core/widgets/user_avatar_with_name.dart';

enum ClientJobsTab { active, history }

/// Dados de apresentação do separador "Pedidos" (cliente).
///
/// A integração (client_jobs_screen.dart) mapeia `clientJobsProvider` +
/// `serviceTypesProvider` para esta estrutura. Este widget não consulta
/// providers, repositories ou Supabase diretamente.
class ClientJobsViewData {
  const ClientJobsViewData({
    required this.activeJobs,
    required this.historyJobs,
  });

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
    this.workerName,
    this.workerAvatarUrl,
    this.nextStepLabel,
    this.needsAction = false,
  });

  final String jobId;
  final String title;

  /// Morada + coordenadas, não um texto já formatado — o card usa
  /// `AddressMapLink` (o mesmo widget tappable já usado nos outros ecrãs),
  /// não uma linha de texto estática.
  final String addressText;
  final double locationLat;
  final double locationLng;

  /// "Hoje"/"Amanhã"/data formatada/"Flexível"/texto de disponibilidade,
  /// já convertido de `DateMode`/`preferredDate`/`availabilityText` pela
  /// integração (`jobDeadlineLabel`, `core/utils/date_labels.dart`).
  final String dateLabel;

  final IconData serviceIcon;

  /// Presenter oficial de `JobStatus` (já inclui a contagem de propostas
  /// no label quando `open` — não é um badge separado).
  final AppStatusPresentation statusPresentation;

  /// Presenter de `RescheduleStatus.pending` quando há remarcação
  /// pendente — `null` na maioria dos casos.
  final AppStatusPresentation? secondaryStatusPresentation;

  /// Preenchido só quando o job já tem um worker aceite (`confirmed`,
  /// `awaitingConfirmation`, `completed`) — `null` em `open`/`noResponse`/
  /// `cancelled`, onde não há ninguém para mostrar.
  final String? workerName;
  final String? workerAvatarUrl;

  /// O que acontece a seguir (só pedidos em curso). Ex.: "Tens 2 propostas
  /// para ver." Igual ao que o Início mostra.
  final String? nextStepLabel;

  /// Realça [nextStepLabel] quando o pedido espera por uma ação do cliente.
  final bool needsAction;
}

class ClientJobsScreen extends StatefulWidget {
  const ClientJobsScreen({
    super.key,
    required this.dataAsync,
    required this.onOpenJob,
    required this.onCreateJob,
    this.onRetry,
    this.onRefresh,
  });

  final AsyncValue<ClientJobsViewData> dataAsync;

  final ValueChanged<String> onOpenJob;
  final VoidCallback onCreateJob;

  final VoidCallback? onRetry;

  /// Pull-to-refresh: o indicador roda até o `Future` terminar.
  final Future<void> Function()? onRefresh;

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
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTabHeader(
              title: 'Pedidos',
              bottom: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                ),
                child: AppTabs(
                  items: [
                    AppTabItem(
                      label: 'Ativos',
                      count: widget.dataAsync.value?.activeJobs.length,
                    ),
                    const AppTabItem(label: 'Histórico'),
                  ],
                  selectedIndex: _selectedTab.index,
                  onSelected: (i) => _selectTab(ClientJobsTab.values[i]),
                ),
              ),
            ),
            Expanded(
              child: widget.dataAsync.when(
                loading: () => const _ClientJobsLoading(),
                error: (_, _) => _ClientJobsError(onRetry: widget.onRetry),
                data: (data) => _ClientJobsContent(
                  data: data,
                  selectedTab: _selectedTab,
                  onOpenJob: widget.onOpenJob,
                  onCreateJob: widget.onCreateJob,
                  onRefresh: widget.onRefresh,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClientJobsContent extends StatelessWidget {
  const _ClientJobsContent({
    required this.data,
    required this.selectedTab,
    required this.onOpenJob,
    required this.onCreateJob,
    this.onRefresh,
  });

  final ClientJobsViewData data;
  final ClientJobsTab selectedTab;

  final ValueChanged<String> onOpenJob;
  final VoidCallback onCreateJob;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final jobs =
        selectedTab == ClientJobsTab.active ? data.activeJobs : data.historyJobs;

    return Column(
      children: [
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          // Chave = a tab (índice), não os dados — um refresh em segundo
          // plano na mesma tab não reanima nada, só a troca de tab o faz
          // (mesmo raciocínio já usado no ecrã de pedidos de ajuda).
          child: AppFadeThroughSwitcher(
            switchKey: selectedTab,
            child: _Refreshable(
              onRefresh: onRefresh,
              child: jobs.isEmpty
                  ? _EmptyState(tab: selectedTab, onCreateJob: onCreateJob)
                  : _JobsList(
                      jobs: jobs,
                      tab: selectedTab,
                      onOpenJob: onOpenJob,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// [RefreshIndicator] só quando há `onRefresh`. O filho tem de ser
/// sempre rolável (`AlwaysScrollableScrollPhysics`), mesmo com pouco
/// conteúdo, para o gesto funcionar.
class _Refreshable extends StatelessWidget {
  const _Refreshable({required this.onRefresh, required this.child});

  final Future<void> Function()? onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final refresh = onRefresh;
    if (refresh == null) return child;
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: refresh,
      child: child,
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
      physics: const AlwaysScrollableScrollPhysics(),
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
              if (job.nextStepLabel != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  job.nextStepLabel!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: job.needsAction
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontWeight: job.needsAction ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
              if (job.workerName != null) ...[
                const SizedBox(height: AppSpacing.sm),
                UserAvatarWithName(
                  name: job.workerName!,
                  avatarUrl: job.workerAvatarUrl,
                  radius: 14,
                  nameStyle: textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  fallbackLabel: 'Jardineiro',
                ),
              ],
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
    // Rolável mesmo vazio, para o pull-to-refresh funcionar aqui também.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - AppSpacing.lg * 2)
                .clamp(0, double.infinity),
          ),
          child: Center(
            child: tab == ClientJobsTab.active
                ? _ActiveEmpty(onCreateJob: onCreateJob)
                : const _HistoryEmpty(),
          ),
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
    return AppEmptyState(
      icon: Icons.yard_outlined,
      title: 'Ainda sem pedidos ativos',
      message: 'Cria um pedido e recebe propostas de jardineiros perto de ti.',
      actionLabel: 'Criar pedido',
      onAction: onCreateJob,
    );
  }
}

class _HistoryEmpty extends StatelessWidget {
  const _HistoryEmpty();

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.history_rounded,
      title: 'Sem histórico',
      message: 'Os pedidos concluídos e cancelados aparecem aqui.',
      tone: AppStatusColor.neutral,
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
    return Column(
      children: [
        const SizedBox(height: AppSpacing.sm),
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
                'Não foi possível carregar os teus pedidos.',
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Verifica a ligação e tenta novamente.',
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
