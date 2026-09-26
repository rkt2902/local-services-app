import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/theme/app_status_presentation.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/address_map_link.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_status_badge.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../../../core/widgets/user_avatar_with_name.dart';
import '../../worker/application/worker_providers.dart';
import '../../ratings/application/rating_providers.dart';
import '../../ratings/presentation/rating_sheet.dart';
import '../../ratings/presentation/ratings_sheet.dart';
import '../application/help_request_providers.dart';
import '../data/help_request_model.dart';

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
            padding: const EdgeInsets.all(16),
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
                padding: const EdgeInsets.only(bottom: 8),
                child: _HelpRequestCard(
                  summary: s,
                  serviceTypeName: serviceTypeName,
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

class _MyApplicationsTabState extends ConsumerState<_MyApplicationsTab> {
  final Set<String> _withdrawing = {};

  Future<void> _onRefresh() async => ref.invalidate(myHelpAcceptancesProvider);

  Future<void> _withdraw(HelpAcceptanceSummary ha) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar desistência'),
        content: const Text(
          'Tens a certeza que queres desistir desta ajuda? '
          'O worker principal será notificado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desistir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _withdrawing.add(ha.id));
    try {
      await ref
          .read(helpRequestRepositoryProvider)
          .withdrawHelpAcceptance(ha.id);
      if (!mounted) return;
      ref.invalidate(myHelpAcceptancesProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Desististe desta ajuda.')),
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(friendlyError(e)),
          backgroundColor: Colors.red,
        ));
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
                    message: 'Ainda não te candidataste a nenhum pedido de ajuda.',
                    action: PrimaryActionButton(
                      label: 'Descobrir pedidos',
                      onPressed: widget.onGoToDiscover,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final pending = acceptances
            .where((a) => a.status == HelpAcceptanceStatus.pending)
            .toList();
        final accepted = acceptances
            .where((a) => a.status == HelpAcceptanceStatus.accepted)
            .toList();
        final history = acceptances
            .where((a) =>
                a.status == HelpAcceptanceStatus.rejected ||
                a.status == HelpAcceptanceStatus.cancelled)
            .toList();

        return RefreshIndicator(
          onRefresh: _onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (pending.isNotEmpty) ...[
                const _SectionHeader('Pendentes'),
                ...pending.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PendingCard(acceptance: a),
                  ),
                ),
              ],
              if (accepted.isNotEmpty) ...[
                if (pending.isNotEmpty) const SizedBox(height: 8),
                const _SectionHeader('Aceites'),
                ...accepted.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _AcceptedCard(
                      acceptance: a,
                      isWithdrawing: _withdrawing.contains(a.id),
                      onWithdraw: () => _withdraw(a),
                    ),
                  ),
                ),
              ],
              if (history.isNotEmpty) ...[
                if (pending.isNotEmpty || accepted.isNotEmpty)
                  const SizedBox(height: 8),
                const _SectionHeader('Histórico'),
                ...history.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _HistoryCard(acceptance: a),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─── Casca: cabeçalho, loading, vazio, erro ──────────────────────────────────
//
// Só isto foi tocado nesta sessão — os 4 cards (_HelpRequestCard,
// _PendingCard, _AcceptedCard, _HistoryCard) e os helpers que eles usam
// (_SectionHeader, _jobStatusBadgeFromRaw, _Meta, _scheduleLabel) ficam
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
    final canPop = Navigator.of(context).canPop();

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
              if (canPop)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xxs),
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
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
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xl,
        ),
        child: Column(
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
              child: Icon(icon, size: 34, color: AppStatusColor.neutral.foreground),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.md),
              action!,
            ],
          ],
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// Usa o mapeamento único de JobStatus (app_status_presenters.dart) — sem
/// wildcard: `JobStatus.fromValue` lança para qualquer string fora dos 6
/// estados conhecidos, em vez de silenciar num caso genérico "Em aberto".
Widget _jobStatusBadgeFromRaw(String rawStatus) => AppStatusBadge.fromPresentation(
      presentation: JobStatus.fromValue(rawStatus).presentation(),
    );

// ─── Candidature cards ────────────────────────────────────────────────────────

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.acceptance});
  final HelpAcceptanceSummary acceptance;

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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppStatusColor.waiting.background,
              borderRadius: BorderRadius.circular(AppRadius.input),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.hourglass_top_outlined,
                color: AppStatusColor.waiting.foreground),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        acceptance.serviceTypeName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    AppStatusBadge.fromPresentation(
                      presentation: HelpAcceptanceStatus.pending.presentation,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                _Meta(
                  icon: Icons.person_outline,
                  label: 'Principal: ${acceptance.principalName}',
                ),
                if (acceptance.broughtEquipment) ...[
                  const SizedBox(height: 4),
                  _Meta(
                    icon: Icons.build_outlined,
                    label: 'Levo equipamento',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AcceptedCard extends ConsumerStatefulWidget {
  const _AcceptedCard({
    required this.acceptance,
    required this.isWithdrawing,
    required this.onWithdraw,
  });
  final HelpAcceptanceSummary acceptance;
  final bool isWithdrawing;
  final VoidCallback onWithdraw;

  @override
  ConsumerState<_AcceptedCard> createState() => _AcceptedCardState();
}

class _AcceptedCardState extends ConsumerState<_AcceptedCard> {
  Future<void> _openWhatsApp(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[\s\-()]'), '');
    final uri = Uri.parse('https://wa.me/$clean');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

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

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppStatusColor.success.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppStatusColor.success.foreground),
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
            const SizedBox(height: 6),
            AppStatusBadge.fromPresentation(
              presentation: HelpAcceptanceStatus.accepted.presentation,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _Meta(
                    icon: Icons.person_outline,
                    label: 'Principal: ${widget.acceptance.principalName}',
                  ),
                ),
                if (principalRatingSummary != null &&
                    principalRatingSummary.ratingCount > 0)
                  GestureDetector(
                    onTap: () => showRatingsSheet(
                      context,
                      workerId: principalId,
                      workerName: widget.acceptance.principalName,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 12, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text(
                          principalRatingSummary.avgRating.toStringAsFixed(1),
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
              const SizedBox(height: 4),
              _Meta(
                icon: Icons.euro_outlined,
                label:
                    '${widget.acceptance.agreedRate.toStringAsFixed(2).replaceAll('.', ',')} €/h acordado',
              ),
            ],
            if (widget.acceptance.confirmedDate != null) ...[
              const SizedBox(height: 4),
              _Meta(
                icon: Icons.event_available_outlined,
                label: _scheduleLabel(
                  widget.acceptance.confirmedDate!,
                  widget.acceptance.confirmedTime,
                ),
              ),
            ],
            if (widget.acceptance.locationLat != 0 || widget.acceptance.locationLng != 0) ...[
              const SizedBox(height: 4),
              AddressMapLink(
                address: widget.acceptance.addressText,
                lat: widget.acceptance.locationLat,
                lng: widget.acceptance.locationLng,
              ),
            ],
            if (widget.acceptance.principalPhone.isNotEmpty) ...[
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: () =>
                    _openWhatsApp(widget.acceptance.principalPhone),
                icon: const Icon(Icons.chat_outlined, size: 18),
                label: const Text('Contactar principal via WhatsApp'),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  textStyle: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            const SizedBox(height: 12),
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
                      const SizedBox(width: 8),
                      Text('Prestador avaliado',
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
                            color: Colors.amber,
                          ),
                        ),
                      ),
                    ]);
                  }
                  return SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: _showHelperRatingSheet,
                      child: const Text('Avaliar o prestador'),
                    ),
                  );
                },
              )
            else if (!isCompleted)
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

  Future<void> _showHelperRatingSheet() async {
    final jobId = widget.acceptance.jobId;
    final submitted = await showRatingSheet(
      context: context,
      title: 'Avaliar o prestador principal',
      subtitle: widget.acceptance.principalName,
      successMessage: 'Avaliação enviada!',
      onSubmit: (stars, comment) async {
        await ref.read(ratingRepositoryProvider).submitHelperRating(
              jobId: jobId,
              stars: stars,
              comment: comment,
            );
      },
    );
    if (submitted != true || !mounted) return;
    ref.invalidate(myRatingForJobProvider(jobId));
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.acceptance});
  final HelpAcceptanceSummary acceptance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
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
                  'Principal: ${acceptance.principalName}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          AppStatusBadge.fromPresentation(
            presentation: acceptance.status.presentation,
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
    this.distanceMeters,
    required this.isApplied,
    required this.isApplying,
    required this.onApply,
  });

  final HelpRequestSummary summary;
  final String serviceTypeName;
  final double? distanceMeters;
  final bool isApplied;
  final bool isApplying;
  final VoidCallback onApply;

  String? _distanceStr() {
    if (distanceMeters == null) return null;
    return distanceMeters! < 1000
        ? '${distanceMeters!.round()} m'
        : '${(distanceMeters! / 1000).toStringAsFixed(1)} km';
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
                  radius: 18,
                  nameStyle: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
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
                    const Icon(Icons.yard_outlined, color: AppColors.primary),
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
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.map_outlined,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
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
              const SizedBox(width: 6),
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
              const SizedBox(width: 6),
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
                      ? '€${summary.paymentPerHelper.toStringAsFixed(2)}/hora'
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

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon,
            size: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

String _scheduleLabel(DateTime date, String? time) {
  final dateStr = DateFormat('dd/MM/yyyy').format(date);
  if (time == null) return dateStr;
  final timeStr = time.length >= 5 ? time.substring(0, 5) : time;
  return '$dateStr às $timeStr';
}
