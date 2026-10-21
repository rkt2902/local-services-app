import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/phone_utils.dart';
import '../../../core/utils/price_labels.dart';
import '../../../core/constants/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion_tokens.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/theme/app_status_presentation.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../../core/utils/date_labels.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/address_map_link.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_status_badge.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../../../core/widgets/user_avatar_with_name.dart';
import '../../../core/widgets/service_icon.dart';
import '../../../core/router/app_back_navigation.dart';
import '../../worker/application/worker_job_rules.dart';
import '../../worker/application/worker_list_invalidation.dart';
import '../../worker/application/worker_providers.dart';
import '../../ratings/application/rating_providers.dart';
import '../../ratings/presentation/worker_ratings_sheet.dart';
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
              final serviceTypeName = serviceTypes
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
                  serviceIcon: serviceTypeIconFor(serviceTypes, s.serviceTypeId),
                  distanceMeters: distanceMeters,
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
            _HelpRequestsHeader(
              selectedTab: _selectedTab,
              onSelected: _selectTab,
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
                    : _MyApplicationsTab(
                        onGoToDiscover: () => _selectTab(0),
                      ),
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
  void _openDetail(HelpAcceptanceSummary a) => context.push('/worker/help/${a.id}');

  Future<void> _withdraw(HelpAcceptanceSummary ha) async {
    final isPending = ha.status == HelpAcceptanceStatus.pending;
    final confirmed = await confirmHelperWithdraw(context, isPending: isPending);
    if (!confirmed || !mounted) return;
    final toast = AppToast.of(context);
    setState(() => _withdrawing.add(ha.id));
    try {
      await ref
          .read(helpRequestRepositoryProvider)
          .withdrawHelpAcceptance(ha.id);
      if (!mounted) return;
      // Regra T4 (sem navegação): SnackBar → invalidar.
      toast.show(isPending ? 'Candidatura retirada.' : 'Desististe desta ajuda.');
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
                    message: 'Candidata-te a um pedido de ajuda para trabalhar '
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

        final filter = _filter ??
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
                                  padding: const EdgeInsets.all(AppSpacing.lg),
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
                          itemBuilder: (_, i) => AppStaggeredEntrance(
                            index: i,
                            child: cards[i],
                          ),
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
            message: 'Quando fores aceite como ajudante, o trabalho aparece '
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

class _HelpRequestsHeader extends StatelessWidget {
  const _HelpRequestsHeader({
    required this.selectedTab,
    required this.onSelected,
  });

  final int selectedTab;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Sempre visível: aberto por notificação (context.go) não há
              // stack, e o voltar cai para a home do papel.
              Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xxs),
                  child: IconButton(
                    onPressed: () => goBackOrToRoleHome(context),
                    tooltip: 'Voltar',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                  ),
                ),
              Text(
                'Pedidos de ajuda',
                style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(AppRadius.input),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _TabPill(
                    label: 'Descobrir',
                    selected: selectedTab == 0,
                    onPressed: () => onSelected(0),
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: _TabPill(
                    label: 'As minhas candidaturas',
                    selected: selectedTab == 1,
                    onPressed: () => onSelected(1),
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

class _TabPill extends StatelessWidget {
  const _TabPill({
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
      color: selected ? AppColors.surface : AppColors.divider,
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
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
              style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
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
Widget _jobStatusBadgeFromRaw(String rawStatus) => AppStatusBadge.fromPresentation(
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
    final secondary =
        textTheme.labelMedium?.copyWith(color: AppColors.textSecondary);

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
                  style:
                      textTheme.titleMedium?.copyWith(color: AppColors.primary),
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
                style: textTheme.labelMedium
                    ?.copyWith(color: AppColors.textPrimary),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Text('À espera da decisão de $principal',
                    style: secondary),
              ),
              TextButton(
                onPressed: isWithdrawing ? null : onWithdraw,
                style: TextButton.styleFrom(
                  foregroundColor: AppStatusColor.cancelled.foreground,
                  textStyle: textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
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
              children: [
                Expanded(
                  child: Text(
                    widget.acceptance.serviceTypeName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _jobStatusBadgeFromRaw(widget.acceptance.jobStatus),
              ],
            ),
            const SizedBox(height: AppSpacing.s6),
            AppStatusBadge.fromPresentation(
              presentation: HelpAcceptanceStatus.accepted.presentation,
            ),
            const SizedBox(height: AppSpacing.s6),
            Row(
              children: [
                Expanded(
                  child: _Meta(
                    icon: Icons.person_outline,
                    label: 'Responsável: ${widget.acceptance.principalName}',
                  ),
                ),
                if (principalRatingSummary != null &&
                    principalRatingSummary.ratingCount > 0)
                  GestureDetector(
                    onTap: () => showWorkerRatingsSheet(
                      context,
                      workerId: principalId,
                      workerName: widget.acceptance.principalName,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 12, color: AppColors.logoAccent),
                        const SizedBox(width: 2),
                        Text(
                          decimalLabel(principalRatingSummary.avgRating, 1),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (widget.acceptance.agreedRate > 0) ...[
              const SizedBox(height: AppSpacing.xxs),
              _Meta(
                icon: Icons.euro_outlined,
                label: '${hourlyRateLabel(widget.acceptance.agreedRate)} acordado',
              ),
            ],
            if (widget.acceptance.confirmedDate != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              _Meta(
                icon: Icons.event_available_outlined,
                label: _scheduleLabel(
                  widget.acceptance.confirmedDate!,
                  widget.acceptance.confirmedTime,
                ),
              ),
            ],
            if (widget.acceptance.locationLat != 0 || widget.acceptance.locationLng != 0) ...[
              const SizedBox(height: AppSpacing.xxs),
              AddressMapLink(
                address: widget.acceptance.addressText,
                lat: widget.acceptance.locationLat,
                lng: widget.acceptance.locationLng,
              ),
            ],
            if (widget.acceptance.principalPhone.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xxs),
              OutlinedButton.icon(
                onPressed: () =>
                    _openWhatsApp(widget.acceptance.principalPhone),
                icon: const Icon(Icons.chat_outlined, size: 18),
                label: const Text('Falar por WhatsApp'),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.s6),
                  textStyle: Theme.of(context).textTheme.bodySmall,
                ),
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
                    return Row(children: [
                      Icon(Icons.check_circle,
                          color: theme.colorScheme.primary, size: 18),
                      const SizedBox(width: AppSpacing.xs),
                      Text('Responsável avaliado',
                          style: theme.textTheme.bodySmall),
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
                    ]);
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
            else if (helperCanWithdraw(widget.acceptance.jobStatus))
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
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
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Builder(builder: (context) {
            final override =
                helperHistoryLabel(acceptance.status, acceptance.jobStatus);
            return override != null
                ? AppStatusBadge(
                    label: override,
                    statusColor: AppStatusColor.cancelled,
                  )
                : AppStatusBadge.fromPresentation(
                    presentation: acceptance.status.presentation,
                  );
          }),
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
    required this.isApplied,
    required this.isApplying,
    required this.onApply,
  });

  final HelpRequestSummary summary;
  final String serviceTypeName;
  final IconData serviceIcon;
  final double? distanceMeters;
  final bool isApplied;
  final bool isApplying;
  final VoidCallback onApply;

  String? _distanceStr() {
    if (distanceMeters == null) return null;
    return distanceLabel(distanceMeters!);
  }

  /// Ex.: "12/09/2026 às 09:00 · 8 km". Horário vem da migration 0034
  /// (`confirmed_date`/`confirmed_time` do job, ainda antes da candidatura).
  String _scheduleAndDistanceLabel() {
    final schedule = summary.confirmedDate != null
        ? _scheduleLabel(summary.confirmedDate!, summary.confirmedTime)
        : 'Horário a combinar';
    final dist = _distanceStr();
    return dist == null ? schedule : '$schedule · $dist';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                  nameStyle: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                  fallbackLabel: 'Jardineiro',
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              AppStatusBadge.fromPresentation(
                presentation: AppStatusPresentation(
                  label:
                      '${summary.slotsNeeded} vaga${summary.slotsNeeded == 1 ? '' : 's'}',
                  color: AppStatusColor.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                ),
                alignment: Alignment.center,
                child:
                    Icon(serviceIcon, color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      serviceTypeName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      _scheduleAndDistanceLabel(),
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (summary.locationLat != 0 || summary.locationLng != 0) ...[
            const SizedBox(height: AppSpacing.xs),
            InkWell(
              onTap: () async {
                final uri = Uri.parse(
                  'https://www.google.com/maps/search/?api=1'
                  '&query=${Uri.encodeComponent('${summary.locationLat},${summary.locationLng}')}',
                );
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.map_outlined,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.s6),
                    Text(
                      'Ver no mapa',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.primary,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          if (summary.equipmentRequired)
            Row(children: [
              const Icon(Icons.build, size: 16, color: AppColors.primary),
              const SizedBox(width: AppSpacing.s6),
              Text(
                'Equipamento obrigatório',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ])
          else
            Row(children: [
              const Icon(Icons.check_circle_outline,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.s6),
              Text('Sem equipamento necessário',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary)),
            ]),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.input),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Pagamento por ajudante',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
                Text(
                  summary.paymentPerHelper > 0
                      ? hourlyRateLabel(summary.paymentPerHelper)
                      : 'A combinar',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          PrimaryActionButton(
            label: isApplied ? 'Já candidatado' : 'Candidatar-me',
            isLoading: isApplying,
            onPressed: isApplied || isApplying ? null : onApply,
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
        child: Ink(
          padding: padding,
          decoration: decoration,
          child: child,
        ),
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
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: AppColors.textSecondary),
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
  final clock = hour == null ? time.substring(0, 5) : '$hour${time.substring(2, 5)}';
  return '$day · $clock';
}
