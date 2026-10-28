import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/phone_utils.dart';
import '../../../core/utils/price_labels.dart';
import '../../../core/constants/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion_tokens.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../../core/utils/date_labels.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/address_map_link.dart';
import '../../../core/widgets/app_whatsapp_button.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_status_badge.dart';
import '../../../core/widgets/app_tab_header.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../../../core/widgets/user_avatar_with_name.dart';
import '../../../core/widgets/service_icon.dart';
import '../../../core/router/app_back_navigation.dart';
import '../../worker/application/worker_job_rules.dart';
import '../../worker/application/worker_list_invalidation.dart';
import '../../worker/application/worker_providers.dart';
import '../../ratings/application/rating_providers.dart';
import '../../agenda/application/agenda_conflicts.dart';
import '../../agenda/application/agenda_providers.dart';
import '../../agenda/presentation/agenda_slot_check.dart';
import '../../agenda/presentation/widgets/agenda_overlap.dart';
import '../application/help_request_providers.dart';
import '../application/helper_job_state.dart';
import '../data/help_request_model.dart';
import 'widgets/helper_actions.dart';
import '../../../core/widgets/app_toast.dart';

// ─── Root screen ─────────────────────────────────────────────────────────────

class WorkerHelpRequestsScreen extends ConsumerStatefulWidget {
  const WorkerHelpRequestsScreen({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  ConsumerState<WorkerHelpRequestsScreen> createState() =>
      _WorkerHelpRequestsScreenState();
}

class _WorkerHelpRequestsScreenState
    extends ConsumerState<WorkerHelpRequestsScreen> {
  late int _selectedTab = widget.initialTabIndex;

  final Set<String> _appliedIds = {};
  final Set<String> _opening = {};

  void _selectTab(int tab) {
    if (_selectedTab == tab) return;
    setState(() => _selectedTab = tab);
  }

  Future<void> _onDiscoverRefresh() async =>
      ref.invalidate(helpRequestSummariesInRadiusProvider);

  /// Abre o ecrã dedicado "Candidatar-me" (rota `/worker/help-requests/:id/apply`)
  /// em vez de submeter inline. O ecrã devolve `true` via `context.pop(true)`
  /// só depois de o INSERT em `help_acceptances` ser confirmado — aqui só
  /// marcamos o estado local otimista de "já candidatado".
  Future<void> _openApplyScreen(HelpRequestSummary summary) async {
    if (_opening.contains(summary.id)) return;
    setState(() => _opening.add(summary.id));
    try {
      final applied = await context.push<bool>(
        '/worker/help-requests/${summary.id}/apply',
      );
      if (applied == true && mounted) {
        setState(() => _appliedIds.add(summary.id));
      }
    } finally {
      if (mounted) setState(() => _opening.remove(summary.id));
    }
  }

  Widget _buildDiscoverTab() {
    final summaryAsync = ref.watch(helpRequestSummariesInRadiusProvider);
    final workerProfile = ref.watch(workerProfileProvider).value;
    final serviceTypes = ref.watch(serviceTypesProvider).value ?? [];

    return summaryAsync.when(
      loading: () => const _HelpRequestsListLoading(),
      error: (e, _) => _HelpRequestsError(message: friendlyError(e)),
      data: (summaries) {
        // A Agenda de cada mês com pedidos, lida uma vez (a mesma cache do
        // Hoje e do detalhe de um pedido).
        final agendaByMonth = {
          for (final range in {
            for (final s in summaries)
              if (s.confirmedDate case final date?) agendaMonthRange(date),
          })
            range: ref.watch(agendaRangeProvider(range)).asData?.value,
        };
        (AgendaAvailability, String)? agendaFor(HelpRequestSummary s) {
          final date = s.confirmedDate;
          if (date == null) return null;
          final entries = agendaByMonth[agendaMonthRange(date)];
          if (entries == null) return null;
          return agendaRequestAvailability(
            slot: AgendaSlot(
              date: date,
              startMinutes: _minutesOf(s.confirmedTime),
            ),
            entries: entries,
          );
        }

        if (summaries.isEmpty) {
          return LayoutBuilder(
            builder: (context, constraints) => RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _onDiscoverRefresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: constraints.maxHeight,
                  child: _HelpRequestsEmptyState(
                    icon: Icons.group_off_outlined,
                    title: 'Sem pedidos de ajuda agora',
                    message: 'Não há pedidos de ajuda na tua zona.',
                    action: TextButton.icon(
                      onPressed: () => _onDiscoverRefresh(),
                      icon: const Icon(
                        Icons.refresh_rounded,
                        color: AppColors.primary,
                      ),
                      label: Text(
                        'Puxar para atualizar',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _onDiscoverRefresh,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: summaries.length,
            itemBuilder: (context, index) {
              final s = summaries[index];
              final serviceTypeName =
                  serviceTypes
                      .where((t) => t.id == s.serviceTypeId)
                      .firstOrNull
                      ?.name ??
                  '—';

              double? distanceMeters;
              if (workerProfile != null) {
                distanceMeters = Geolocator.distanceBetween(
                  workerProfile.baseLat,
                  workerProfile.baseLng,
                  s.locationLat,
                  s.locationLng,
                );
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: _HelpRequestCard(
                  summary: s,
                  serviceTypeName: serviceTypeName,
                  serviceIcon: serviceTypeIconFor(
                    serviceTypes,
                    s.serviceTypeId,
                  ),
                  distanceMeters: distanceMeters,
                  agenda: agendaFor(s),
                  isApplied: _appliedIds.contains(s.id),
                  isApplying: _opening.contains(s.id),
                  onApply: () => _openApplyScreen(s),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            AppBackHeader(
              title: 'Pedidos de ajuda',
              subtitle: 'Ajuda outros jardineiros',
              onBack: () => goBackOrToRoleHome(context),
              bottom: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: AppTabs(
                  items: [
                    const AppTabItem(label: 'Descobrir'),
                    AppTabItem(
                      label: 'Candidaturas',
                      count: ref
                          .watch(myHelpAcceptancesProvider)
                          .asData
                          ?.value
                          .where(
                            (a) => a.status == HelpAcceptanceStatus.pending,
                          )
                          .length,
                    ),
                  ],
                  selectedIndex: _selectedTab,
                  onSelected: _selectTab,
                ),
              ),
            ),
            Expanded(
              // Nota: o mockup de referência optou por NÃO usar
              // AppFadeThroughSwitcher aqui, para preservar o scroll de
              // cada lista quando os dados são atualizados em segundo
              // plano (PageStorageKey própria por tab). Mantive o pedido
              // explícito de motion na troca de tabs — a chave é o índice
              // da tab (não os dados), por isso um refresh em segundo
              // plano na MESMA tab não re-anima nada; só troca ao mudar
              // de tab.
              child: AppFadeThroughSwitcher(
                switchKey: _selectedTab,
                child: _selectedTab == 0
                    ? _buildDiscoverTab()
                    : _MyApplicationsTab(onGoToDiscover: () => _selectTab(0)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── "As minhas candidaturas" tab ────────────────────────────────────────────

class _MyApplicationsTab extends ConsumerStatefulWidget {
  const _MyApplicationsTab({required this.onGoToDiscover});

  final VoidCallback onGoToDiscover;

  @override
  ConsumerState<_MyApplicationsTab> createState() => _MyApplicationsTabState();
}

/// Subsecções de "As minhas candidaturas" (design U4).
enum _ApplicationsFilter { pending, accepted, history }

class _MyApplicationsTabState extends ConsumerState<_MyApplicationsTab> {
  final Set<String> _withdrawing = {};

  /// `null` até haver dados: abre na primeira subsecção com candidaturas.
  _ApplicationsFilter? _filter;

  Future<void> _onRefresh() async => ref.invalidate(myHelpAcceptancesProvider);

  /// Detalhe da candidatura (`/worker/help/:acceptanceId`).
  void _openDetail(HelpAcceptanceSummary a) =>
      context.push('/worker/help/${a.id}');

  Future<void> _withdraw(HelpAcceptanceSummary ha) async {
    final isPending = ha.status == HelpAcceptanceStatus.pending;
    final confirmed = await confirmHelperWithdraw(
      context,
      isPending: isPending,
    );
    if (!confirmed || !mounted) return;
    final toast = AppToast.of(context);
    setState(() => _withdrawing.add(ha.id));
    try {
      await ref
          .read(helpRequestRepositoryProvider)
          .withdrawHelpAcceptance(ha.id);
      if (!mounted) return;
      // Regra T4 (sem navegação): SnackBar → invalidar.
      toast.show(
        isPending ? 'Candidatura retirada.' : 'Desististe desta ajuda.',
      );
      invalidateWorkerLists(ref);
    } catch (e) {
      if (mounted) {
        toast.error(helpActionErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _withdrawing.remove(ha.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myHelpAcceptancesProvider);
    return async.when(
      loading: () => const _HelpRequestsListLoading(),
      error: (e, _) => _HelpRequestsError(message: friendlyError(e)),
      data: (acceptances) {
        if (acceptances.isEmpty) {
          return LayoutBuilder(
            builder: (context, constraints) => RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _onRefresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: constraints.maxHeight,
                  child: _HelpRequestsEmptyState(
                    icon: Icons.assignment_outlined,
                    title: 'Ainda sem candidaturas',
                    message:
                        'Candidata-te a um pedido de ajuda para trabalhar '
                        'com outros jardineiros.',
                    actionLabel: 'Descobrir pedidos',
                    onAction: widget.onGoToDiscover,
                  ),
                ),
              ),
            ),
          );
        }

        // Uma candidatura num trabalho cancelado/expirado vai para o
        // histórico, mesmo que tenha sido aceite (sem Desistir nem WhatsApp).
        HelperCardKind kindOf(HelpAcceptanceSummary a) =>
            helperCardKind(a.status, a.jobStatus);
        final pending = acceptances
            .where((a) => kindOf(a) == HelperCardKind.pending)
            .toList();
        final accepted = acceptances
            .where((a) => kindOf(a) == HelperCardKind.active)
            .toList();
        final history = acceptances
            .where((a) => kindOf(a) == HelperCardKind.history)
            .toList();

        final filter =
            _filter ??
            (pending.isNotEmpty
                ? _ApplicationsFilter.pending
                : accepted.isNotEmpty
                ? _ApplicationsFilter.accepted
                : _ApplicationsFilter.history);
        final List<Widget> cards = switch (filter) {
          _ApplicationsFilter.pending => [
            for (final a in pending)
              _PendingCard(
                acceptance: a,
                onOpen: () => _openDetail(a),
                isWithdrawing: _withdrawing.contains(a.id),
                onWithdraw: () => _withdraw(a),
              ),
          ],
          _ApplicationsFilter.accepted => [
            for (final a in accepted)
              _AcceptedCard(
                acceptance: a,
                onOpen: () => _openDetail(a),
                isWithdrawing: _withdrawing.contains(a.id),
                onWithdraw: () => _withdraw(a),
              ),
          ],
          _ApplicationsFilter.history => [
            for (final a in history)
              _HistoryCard(acceptance: a, onOpen: () => _openDetail(a)),
          ],
        };

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Row(
                children: [
                  _FilterPill(
                    label: 'Pendentes ${pending.length}',
                    selected: filter == _ApplicationsFilter.pending,
                    onPressed: () =>
                        setState(() => _filter = _ApplicationsFilter.pending),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _FilterPill(
                    label: 'Aceites ${accepted.length}',
                    selected: filter == _ApplicationsFilter.accepted,
                    onPressed: () =>
                        setState(() => _filter = _ApplicationsFilter.accepted),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _FilterPill(
                    label: 'Histórico',
                    selected: filter == _ApplicationsFilter.history,
                    onPressed: () =>
                        setState(() => _filter = _ApplicationsFilter.history),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AppFadeThroughSwitcher(
                switchKey: filter,
                duration: AppMotionDuration.fast,
                child: RefreshIndicator(
                  key: ValueKey(filter),
                  color: AppColors.primary,
                  onRefresh: _onRefresh,
                  child: cards.isEmpty
                      ? LayoutBuilder(
                          builder: (context, constraints) =>
                              SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: SizedBox(
                                  height: constraints.maxHeight,
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(
                                        AppSpacing.lg,
                                      ),
                                      child: _filterEmptyState(filter),
                                    ),
                                  ),
                                ),
                              ),
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            AppSpacing.xs,
                            AppSpacing.md,
                            AppSpacing.lg,
                          ),
                          itemCount: cards.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (_, i) =>
                              AppStaggeredEntrance(index: i, child: cards[i]),
                        ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _filterEmptyState(_ApplicationsFilter filter) => switch (filter) {
    _ApplicationsFilter.pending => const AppEmptyState(
      icon: Icons.hourglass_empty_rounded,
      tone: AppStatusColor.neutral,
      title: 'Sem candidaturas pendentes',
      message: 'As candidaturas à espera de decisão aparecem aqui.',
    ),
    _ApplicationsFilter.accepted => const AppEmptyState(
      icon: Icons.groups_outlined,
      tone: AppStatusColor.neutral,
      title: 'Ainda não estás numa equipa',
      message:
          'Quando fores aceite como ajudante, o trabalho aparece '
          'aqui.',
    ),
    _ApplicationsFilter.history => const AppEmptyState(
      icon: Icons.history_rounded,
      tone: AppStatusColor.neutral,
      title: 'Sem histórico',
      message: 'As candidaturas que já fecharam aparecem aqui.',
    ),
  };
}

/// Pílula de filtro "Pendentes 2 / Aceites 1 / Histórico".
class _FilterPill extends StatelessWidget {
  const _FilterPill({
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
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.divider,
              ),
            ),
            child: Text(
              label,
              style: textTheme.labelMedium?.copyWith(
                color: selected ? AppColors.surface : AppColors.textPrimary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Casca: cabeçalho, loading, vazio, erro ──────────────────────────────────
//
// Só isto foi tocado nesta sessão — os 4 cards (_HelpRequestCard,
// _PendingCard, _AcceptedCard, _HistoryCard) e os helpers que eles usam
// (_jobStatusBadgeFromRaw, _Meta, _scheduleLabel) ficam
// exatamente como estavam, mais abaixo neste ficheiro.

class _HelpRequestsListLoading extends StatelessWidget {
  const _HelpRequestsListLoading();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: 3,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, index) => AppSkeletonShimmer(
        child: Container(
          height: index == 0 ? 176 : 150,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
        ),
      ),
    );
  }
}

class _HelpRequestsEmptyState extends StatelessWidget {
  const _HelpRequestsEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xl,
        ),
        child: AppEmptyState(
          icon: icon,
          title: title,
          message: message,
          actionLabel: actionLabel,
          onAction: onAction,
          action: action,
        ),
      ),
    );
  }
}

class _HelpRequestsError extends StatelessWidget {
  const _HelpRequestsError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
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
              child: Icon(
                Icons.cloud_off_outlined,
                color: AppStatusColor.cancelled.foreground,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

/// Usa o mapeamento único de JobStatus (app_status_presenters.dart) — sem
/// wildcard: `JobStatus.fromValue` lança para qualquer string fora dos 6
/// estados conhecidos, em vez de silenciar num caso genérico "Em aberto".
Widget _jobStatusBadgeFromRaw(String rawStatus) =>
    AppStatusBadge.fromPresentation(
      presentation: JobStatus.fromValue(rawStatus).presentation(),
    );

// ─── Candidature cards ────────────────────────────────────────────────────────

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.acceptance,
    required this.onOpen,
    required this.isWithdrawing,
    required this.onWithdraw,
  });
  final HelpAcceptanceSummary acceptance;
  final VoidCallback onOpen;
  final bool isWithdrawing;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final offered = acceptance.paymentPerHelper;
    final principal = acceptance.principalName.trim().isEmpty
        ? 'o responsável'
        : acceptance.principalName;
    final secondary = textTheme.labelMedium?.copyWith(
      color: AppColors.textSecondary,
    );

    return _TappableCard(
      onTap: onOpen,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: AppSizes.avatarSmall / 2,
                backgroundColor: AppColors.primaryContainer,
                child: Text(
                  principal[0].toUpperCase(),
                  style: textTheme.titleMedium?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      acceptance.serviceTypeName,
                      style: textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text('Responsável: $principal', style: secondary),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              AppStatusBadge(
                label: 'À espera',
                statusColor: AppStatusColor.waiting,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              _Meta(
                icon: Icons.calendar_today_outlined,
                label: acceptance.confirmedDate != null
                    ? _scheduleLabel(
                        acceptance.confirmedDate!,
                        acceptance.confirmedTime,
                      )
                    : 'Horário a combinar',
              ),
              if (acceptance.addressText.isNotEmpty)
                _Meta(
                  icon: Icons.place_outlined,
                  label: acceptance.addressText,
                ),
              if (acceptance.broughtEquipment)
                const _Meta(
                  icon: Icons.handyman_outlined,
                  label: 'Levo equipamento',
                ),
            ],
          ),
          if (offered != null && offered > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'Sugestão do responsável: ',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: hourlyRateLabel(offered)),
                  ],
                ),
                style: textTheme.labelMedium?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  'À espera da decisão de $principal',
                  style: secondary,
                ),
              ),
              TextButton(
                onPressed: isWithdrawing ? null : onWithdraw,
                style: TextButton.styleFrom(
                  foregroundColor: AppStatusColor.cancelled.foreground,
                  textStyle: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(isWithdrawing ? 'A retirar...' : 'Retirar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AcceptedCard extends ConsumerStatefulWidget {
  const _AcceptedCard({
    required this.acceptance,
    required this.onOpen,
    required this.isWithdrawing,
    required this.onWithdraw,
  });
  final HelpAcceptanceSummary acceptance;
  final VoidCallback onOpen;
  final bool isWithdrawing;
  final VoidCallback onWithdraw;

  @override
  ConsumerState<_AcceptedCard> createState() => _AcceptedCardState();
}

class _AcceptedCardState extends ConsumerState<_AcceptedCard> {
  Future<void> _openWhatsApp(String phone) =>
      openWhatsAppOrWarn(context, phone);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompleted = widget.acceptance.jobStatus == 'completed';
    final jobId = widget.acceptance.jobId;

    final ratingAsync = jobId.isNotEmpty
        ? ref.watch(myRatingForJobProvider(jobId))
        : const AsyncData<Rating?>(null);
    final principalId = widget.acceptance.principalWorkerId;
    final principalRatingSummary = principalId.isNotEmpty
        ? ref.watch(ratingSummaryProvider(principalId)).asData?.value
        : null;
    final a = widget.acceptance;
    final secondary = theme.textTheme.labelMedium?.copyWith(
      color: AppColors.textSecondary,
    );
    // Aceite num trabalho por fazer: já entrou na Agenda dele (A12, A6).
    final inTeam = a.jobStatus == 'confirmed';
    final serviceTypes = ref.watch(serviceTypesProvider).value ?? const [];
    final serviceIcon = serviceTypeIconFor(
      serviceTypes,
      serviceTypes.where((t) => t.name == a.serviceTypeName).firstOrNull?.id,
    );

    return _TappableCard(
      onTap: widget.onOpen,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ServiceIconBox(icon: serviceIcon),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.serviceTypeName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: 'Responsável: ${a.principalName}'),
                          if (principalRatingSummary != null &&
                              principalRatingSummary.ratingCount > 0)
                            TextSpan(
                              text:
                                  ' · ★ ${decimalLabel(principalRatingSummary.avgRating, 1)}',
                            ),
                        ],
                      ),
                      style: secondary,
                    ),
                    Text(
                      [
                        a.confirmedDate != null
                            ? _scheduleLabel(a.confirmedDate!, a.confirmedTime)
                            : 'Horário a combinar',
                        if (a.agreedRate > 0) hourlyRateLabel(a.agreedRate),
                      ].join(' · '),
                      style: secondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              inTeam
                  ? AppStatusBadge(
                      label: 'Na equipa',
                      statusColor: AppStatusColor.success,
                      dense: true,
                    )
                  : _jobStatusBadgeFromRaw(a.jobStatus),
            ],
          ),
          if (inTeam) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.event_available,
                    size: AppSizes.inlineIcon,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text.rich(
                      const TextSpan(
                        children: [
                          TextSpan(text: 'Já está na tua agenda com o selo '),
                          TextSpan(
                            text: 'Ajudante',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: '.'),
                        ],
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (a.locationLat != 0 || a.locationLng != 0) ...[
            const SizedBox(height: AppSpacing.xs),
            AddressMapLink(
              address: a.addressText,
              lat: a.locationLat,
              lng: a.locationLng,
            ),
          ],
          if (inTeam || a.principalPhone.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                if (inTeam)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => context.go(
                        '/worker/jobs',
                        extra: const {'initialTab': 'agenda'},
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(
                          0,
                          AppSizes.compactButtonHeight,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.input),
                        ),
                      ),
                      icon: const Icon(
                        Icons.calendar_month_outlined,
                        size: AppSizes.inlineIcon,
                      ),
                      label: const Text('Agenda'),
                    ),
                  ),
                if (inTeam && a.principalPhone.isNotEmpty)
                  const SizedBox(width: AppSpacing.xs),
                if (a.principalPhone.isNotEmpty)
                  Expanded(
                    child: AppWhatsAppButton(
                      compact: true,
                      onPressed: () => _openWhatsApp(a.principalPhone),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          if (isCompleted && jobId.isNotEmpty)
            ratingAsync.when(
              // Loading de "já avaliei este job?", não progresso de uma
              // operação em curso — mesmo tratamento dos outros
              // "a carregar" do app (docs/motion_spec.md §3).
              loading: () => AppSkeletonShimmer(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.input),
                  ),
                ),
              ),
              error: (_, _) => const SizedBox.shrink(),
              data: (existing) {
                if (existing != null) {
                  return Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: theme.colorScheme.primary,
                        size: 18,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        'Responsável avaliado',
                        style: theme.textTheme.bodySmall,
                      ),
                      const Spacer(),
                      Row(
                        children: List.generate(
                          5,
                          (i) => Icon(
                            i < existing.stars
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 16,
                            color: AppColors.logoAccent,
                          ),
                        ),
                      ),
                    ],
                  );
                }
                return SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: _showHelperRatingSheet,
                    child: const Text('Avaliar o responsável'),
                  ),
                );
              },
            )
          else if (helperGiveUpClosedByJobDay(
            widget.acceptance.jobStatus,
            confirmedDate: widget.acceptance.confirmedDate,
          ))
            Text(
              helperGiveUpClosedMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          else if (helperCanWithdraw(
            widget.acceptance.jobStatus,
            confirmedDate: widget.acceptance.confirmedDate,
          ))
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: widget.isWithdrawing ? null : widget.onWithdraw,
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error),
                ),
                child: widget.isWithdrawing
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.error,
                        ),
                      )
                    : const Text('Desistir'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showHelperRatingSheet() =>
      showRatePrincipalSheet(context, ref, widget.acceptance);
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.acceptance, required this.onOpen});
  final HelpAcceptanceSummary acceptance;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _TappableCard(
      onTap: onOpen,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppStatusColor.neutral.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  acceptance.serviceTypeName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Responsável: ${acceptance.principalName}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Builder(
            builder: (context) {
              final override = helperHistoryLabel(
                acceptance.status,
                acceptance.jobStatus,
              );
              return override != null
                  ? AppStatusBadge(
                      label: override,
                      statusColor: AppStatusColor.cancelled,
                    )
                  : AppStatusBadge.fromPresentation(
                      presentation: acceptance.status.presentation,
                    );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Discover tab widgets (unchanged) ────────────────────────────────────────

class _HelpRequestCard extends StatelessWidget {
  const _HelpRequestCard({
    required this.summary,
    required this.serviceTypeName,
    required this.serviceIcon,
    this.distanceMeters,
    this.agenda,
    required this.isApplied,
    required this.isApplying,
    required this.onApply,
  });

  final HelpRequestSummary summary;
  final String serviceTypeName;
  final IconData serviceIcon;
  final double? distanceMeters;

  /// Como o dia do pedido fica na Agenda dele (A12, A4); `null` sem data
  /// ou enquanto a Agenda carrega.
  final (AgendaAvailability, String)? agenda;
  final bool isApplied;
  final bool isApplying;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = textTheme.labelMedium?.copyWith(
      color: AppColors.textSecondary,
    );
    final slots = summary.slotsNeeded;
    final distance = distanceMeters == null
        ? null
        : distanceLabel(distanceMeters!);
    final deadline = helpApplicationsDeadlineLabel(summary.confirmedDate);
    final agenda = this.agenda;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: UserAvatarWithName(
                  name: summary.principalName,
                  avatarUrl: summary.principalAvatarUrl,
                  radius: 18,
                  nameStyle: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  fallbackLabel: 'Jardineiro',
                  subtitle: 'responsável',
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              AppStatusBadge(
                label: '$slots ${slots == 1 ? 'vaga' : 'vagas'}',
                statusColor: AppStatusColor.info,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ServiceIconBox(icon: serviceIcon),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      serviceTypeName,
                      style: textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      summary.confirmedDate != null
                          ? _scheduleLabel(
                              summary.confirmedDate!,
                              summary.confirmedTime,
                            )
                          : 'Horário a combinar',
                      style: secondary,
                    ),
                    if (distance != null) Text('A $distance', style: secondary),
                    if (deadline != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        deadline,
                        style: textTheme.labelMedium?.copyWith(
                          color: AppStatusColor.waiting.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (summary.equipmentRequired || agenda != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                if (summary.equipmentRequired)
                  _CardChip(
                    icon: Icons.handyman_outlined,
                    label: 'Leva equipamento',
                    tone: AppStatusColor.waiting,
                  ),
                if (agenda != null)
                  _CardChip(
                    icon: switch (agenda.$1) {
                      AgendaAvailability.free => Icons.event_available,
                      AgendaAvailability.busyDay => Icons.event_note_outlined,
                      AgendaAvailability.overlap => Icons.warning_rounded,
                    },
                    label: agenda.$1 == AgendaAvailability.free
                        ? 'Cabe na tua agenda'
                        : agenda.$2,
                    tone: switch (agenda.$1) {
                      AgendaAvailability.free => AppStatusColor.success,
                      AgendaAvailability.busyDay => AppStatusColor.info,
                      AgendaAvailability.overlap => AppStatusColor.waiting,
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'POR AJUDANTE',
                      style: textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      summary.paymentPerHelper > 0
                          ? hourlyRateLabel(summary.paymentPerHelper)
                          : 'A combinar',
                      style: textTheme.titleLarge?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: PrimaryActionButton(
                  label: isApplied ? 'Já candidatado' : 'Candidatar-me',
                  height: AppSizes.compactButtonHeight,
                  isLoading: isApplying,
                  onPressed: isApplied || isApplying ? null : onApply,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Quadrado verde-claro com o ícone do serviço (40 px).
class _ServiceIconBox extends StatelessWidget {
  const _ServiceIconBox({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSizes.rowIconBox,
      height: AppSizes.rowIconBox,
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: AppSizes.rowIcon, color: AppColors.primary),
    );
  }
}

/// Etiqueta pequena dos cartões de pedidos de ajuda ("Leva equipamento",
/// "Cabe na tua agenda").
class _CardChip extends StatelessWidget {
  const _CardChip({
    required this.icon,
    required this.label,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final AppStatusColor tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppSizes.metaIcon, color: tone.foreground),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: tone.foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cartão tocável: o fundo é pintado num `Ink` para o ripple aparecer por
/// cima da cor do cartão (feedback de toque, motion_spec §3).
class _TappableCard extends StatelessWidget {
  const _TappableCard({
    required this.onTap,
    required this.padding,
    required this.decoration,
    required this.child,
  });

  final VoidCallback onTap;
  final EdgeInsetsGeometry padding;
  final BoxDecoration decoration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.card);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(padding: padding, decoration: decoration, child: child),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: AppSizes.metaIcon, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// "Sábado, 25/10 · 8:30" (sem hora: só o dia).
String _scheduleLabel(DateTime date, String? time) {
  final day = weekdayDateLabel(date);
  if (time == null || time.length < 5) return day;
  final hour = int.tryParse(time.substring(0, 2));
  final clock = hour == null
      ? time.substring(0, 5)
      : '$hour${time.substring(2, 5)}';
  return '$day · $clock';
}

/// "08:30:00" em minutos desde a meia-noite; `null` sem hora.
int? _minutesOf(String? time) {
  if (time == null || time.length < 5) return null;
  final h = int.tryParse(time.substring(0, 2));
  final m = int.tryParse(time.substring(3, 5));
  if (h == null || m == null) return null;
  return h * 60 + m;
}
