import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../client/application/client_providers.dart';
import '../../help_requests/application/help_request_providers.dart';
import '../../help_requests/data/help_request_model.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/data/job_model.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../proposals/data/proposal_model.dart';
import 'widgets/worker_jobs_view.dart' as view;

List<(JobProposal, JobRequest)> _parseEntries(
    List<Map<String, dynamic>> raw) {
  return raw
      .where((m) => m['job_requests'] != null)
      .map((m) {
        final job = JobRequest.fromJson(
            Map<String, dynamic>.from(m['job_requests'] as Map));
        final proposal =
            JobProposal.fromJson(Map<String, dynamic>.from(m));
        return (proposal, job);
      })
      .toList();
}

String _formatDate(DateTime? date) {
  if (date == null) return 'Flexível';
  return DateFormat('dd/MM/yyyy').format(date);
}

/// Para "Agendados", a data confirmada é mais relevante que a preferida do
/// pedido original — mesma preferência já usada no dashboard
/// (`_confirmedScheduleLabel`).
String _scheduleLabel(JobRequest job) {
  if (job.confirmedDate != null) {
    final date = DateFormat('dd/MM/yyyy').format(job.confirmedDate!);
    if (job.confirmedFlexible) return '$date (flexível)';
    if (job.confirmedTime != null) return '$date às ${job.confirmedTime}';
    return date;
  }
  return _formatDate(job.preferredDate);
}

String _formatEstimate(double rate, double? min, double? max) {
  if (rate <= 0) return 'Preço a definir';
  if (min != null && max != null) {
    return '≈ €${(rate * min).toStringAsFixed(0)} - €${(rate * max).toStringAsFixed(0)}';
  } else if (min != null) {
    return '≈ €${(rate * min).toStringAsFixed(0)}';
  } else if (max != null) {
    return '≈ €${(rate * max).toStringAsFixed(0)}';
  }
  return '';
}

String _helperScheduleLabel(DateTime? date, String? time) {
  if (date == null) return 'Horário a combinar';
  final dateStr = DateFormat('dd/MM/yyyy').format(date);
  if (time == null || time.isEmpty) return dateStr;
  final timeStr = time.length >= 5 ? time.substring(0, 5) : time;
  return '$dateStr às $timeStr';
}

/// Mapeia candidaturas de ajudante (`HelpAcceptanceSummary`) para a mesma
/// tab de estado que o papel de responsável usa — ver docs/state_machine.md.
/// Um help_acceptance só existe depois de o job já estar `confirmed` (ou
/// mais adiante), por isso não há equivalente a "Pendentes" no sentido de
/// job `open`: aqui "pending" significa candidatura enviada, a aguardar
/// decisão do responsável, com o job já confirmado.
/// `rejected`/`cancelled` ficam de fora de propósito — continuam visíveis
/// só na tab "As minhas candidaturas" (secção Histórico).
List<HelpAcceptanceSummary> _helperEntriesForTab(
  List<HelpAcceptanceSummary> all,
  view.WorkerJobsTab tab,
) {
  switch (tab) {
    case view.WorkerJobsTab.pending:
      return all
          .where((a) => a.status == HelpAcceptanceStatus.pending)
          .toList();
    case view.WorkerJobsTab.scheduled:
      return all
          .where((a) =>
              a.status == HelpAcceptanceStatus.accepted &&
              (a.jobStatus == 'confirmed' ||
                  a.jobStatus == 'awaiting_confirmation'))
          .toList();
    case view.WorkerJobsTab.completed:
      return all
          .where((a) =>
              a.status == HelpAcceptanceStatus.accepted &&
              a.jobStatus == 'completed')
          .toList();
  }
}

view.WorkerJobListItemViewData _toHelperViewData(
  HelpAcceptanceSummary a,
  view.WorkerJobsTab tab,
) {
  // "Pendentes" tem um significado diferente para um ajudante: o job já
  // está confirmado, não está em aberto — quem decide agora é o
  // responsável, não o cliente. Texto secundário adaptado para não sugerir
  // que o job ainda não tem data/cliente.
  final secondaryLabel = tab == view.WorkerJobsTab.pending
      ? 'Trabalho já confirmado — a aguardar decisão do responsável'
      : (a.addressText.isNotEmpty
          ? a.addressText
          : 'Localização não especificada');

  return view.WorkerJobListItemViewData(
    id: a.id,
    title: a.serviceTypeName,
    personName: a.principalName,
    locationLabel: _helperScheduleLabel(a.confirmedDate, a.confirmedTime),
    secondaryLabel: secondaryLabel,
    priceLabel: a.agreedRate > 0
        ? '€${a.agreedRate.toStringAsFixed(2)}/h'
        : 'A combinar',
    status: a.status.presentation,
    role: view.WorkerJobRole.helper,
  );
}

view.WorkerJobsTab? _tabFromName(String? name) {
  return switch (name) {
    'pending' => view.WorkerJobsTab.pending,
    'scheduled' => view.WorkerJobsTab.scheduled,
    'completed' => view.WorkerJobsTab.completed,
    _ => null,
  };
}

/// Ecrã "Os meus trabalhos" (Flow 5) — wrapper de integração que liga os
/// providers reais (`pendingWorkerProposalsProvider`,
/// `scheduledWorkerProposalsProvider`, `completedWorkerProposalsProvider`)
/// ao componente apresentacional em `widgets/worker_jobs_view.dart`.
class WorkerJobsScreen extends ConsumerStatefulWidget {
  const WorkerJobsScreen({
    super.key,
    this.highlightedJobId,
    this.initialTab,
  });

  /// Suporte a deep-link de notificações — ver `app_router.dart` (extra da
  /// rota `/worker/jobs`) e `notification_handler.dart`.
  final String? highlightedJobId;
  final String? initialTab;

  @override
  ConsumerState<WorkerJobsScreen> createState() => _WorkerJobsScreenState();
}

class _WorkerJobsScreenState extends ConsumerState<WorkerJobsScreen> {
  late view.WorkerJobsTab _selectedTab;
  String? _highlightedJobId;
  Timer? _highlightTimer;

  final List<(JobProposal, JobRequest)> _additionalCompleted = [];
  int _currentCompletedPage = 0;
  bool _loadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _selectedTab = _tabFromName(widget.initialTab) ?? view.WorkerJobsTab.pending;
    _highlightedJobId = widget.highlightedJobId;
    if (_highlightedJobId != null) {
      _highlightTimer = Timer(const Duration(milliseconds: 1300), () {
        if (mounted) setState(() => _highlightedJobId = null);
      });
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    setState(() {
      _additionalCompleted.clear();
      _currentCompletedPage = 0;
      _hasMore = true;
    });
    ref.invalidate(pendingWorkerProposalsProvider);
    ref.invalidate(scheduledWorkerProposalsProvider);
    ref.invalidate(completedWorkerProposalsProvider(0));
    ref.invalidate(jobsInRadiusProvider);
    ref.invalidate(myHelpAcceptancesProvider);
  }

  void _loadMore() {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final nextPage = _currentCompletedPage + 1;
    ref.read(completedWorkerProposalsProvider(nextPage).future).then((raw) {
      if (!mounted) return;
      final parsed = _parseEntries(raw);
      setState(() {
        _currentCompletedPage = nextPage;
        _additionalCompleted.addAll(parsed);
        _hasMore = parsed.length >= 20;
        _loadingMore = false;
      });
    }).catchError((_) {
      if (mounted) setState(() => _loadingMore = false);
    });
  }

  view.WorkerJobListItemViewData _toViewData(
    JobProposal proposal,
    JobRequest job,
    List<ServiceType> serviceTypes,
  ) {
    final serviceType =
        serviceTypes.where((s) => s.id == job.serviceTypeId).firstOrNull;
    final clientInfo =
        ref.watch(clientBasicInfoProvider(job.clientId)).asData?.value;

    return view.WorkerJobListItemViewData(
      id: proposal.id,
      title: serviceType?.name ?? '—',
      personName: clientInfo?['full_name'] ?? '',
      locationLabel: _scheduleLabel(job),
      secondaryLabel: job.addressText.isNotEmpty
          ? job.addressText
          : 'Localização não especificada',
      priceLabel: _formatEstimate(
        proposal.hourlyRate,
        proposal.estimatedHoursMin,
        proposal.estimatedHoursMax,
      ),
      status: proposal.status.presentation,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingAsync = ref.watch(pendingWorkerProposalsProvider);
    final scheduledAsync = ref.watch(scheduledWorkerProposalsProvider);
    final completedAsync = ref.watch(completedWorkerProposalsProvider(0));
    final serviceTypes = ref.watch(serviceTypesProvider).asData?.value ?? [];
    // Trabalhos como ajudante — lista única (RPC sem paginação, ver nota em
    // _loadMore mais abaixo), fatiada client-side pela mesma regra de estado
    // que as 3 tabs já usam para o papel de responsável.
    final helperAcceptances =
        ref.watch(myHelpAcceptancesProvider).asData?.value ??
            const <HelpAcceptanceSummary>[];

    // Reset pagination state whenever page 0 is invalidated externally
    // (e.g. by notificationSyncProvider) so stale pages don't mix with fresh data.
    ref.listen(completedWorkerProposalsProvider(0), (prev, next) {
      if (next.isLoading && mounted) {
        setState(() {
          _additionalCompleted.clear();
          _currentCompletedPage = 0;
          _hasMore = true;
        });
      }
    });

    final selectedAsync = switch (_selectedTab) {
      view.WorkerJobsTab.pending => pendingAsync,
      view.WorkerJobsTab.scheduled => scheduledAsync,
      view.WorkerJobsTab.completed => completedAsync,
    };

    final completedPage0 = completedAsync.asData?.value ?? const [];

    var entries = <(JobProposal, JobRequest)>[];
    final loading = selectedAsync.isLoading && !selectedAsync.hasValue;
    final errorMessage =
        selectedAsync.hasError ? friendlyError(selectedAsync.error!) : null;

    if (selectedAsync.hasValue) {
      entries = _parseEntries(selectedAsync.value!);
      if (_selectedTab == view.WorkerJobsTab.completed) {
        entries = [...entries, ..._additionalCompleted];
      }
    }

    final jobIdByProposalId = {
      for (final entry in entries) entry.$1.id: entry.$2.id,
    };

    final principalJobs = [
      for (final entry in entries)
        _toViewData(entry.$1, entry.$2, serviceTypes),
    ];

    // Candidaturas de ajudante para a tab atual — fundidas na mesma lista.
    // Ordem: propostas como responsável primeiro, ajudante depois. Não há
    // interleaving cronológico entre as duas fontes (ver nota de paginação
    // abaixo); dentro de cada tab isto é aceitável porque o volume por
    // worker é baixo neste MVP.
    final helperEntriesForTab =
        _helperEntriesForTab(helperAcceptances, _selectedTab);
    final helperJobIds = {for (final a in helperEntriesForTab) a.id};
    final helperJobs = [
      for (final a in helperEntriesForTab) _toHelperViewData(a, _selectedTab),
    ];

    final jobs = [...principalJobs, ...helperJobs];

    // Contagens dos badges das tabs somam sempre os dois papéis, independente
    // da tab selecionada (mesma forma como já eram calculadas antes, só que
    // agora incluindo `_helperEntriesForTab` para as outras duas tabs).
    final pendingHelperCount =
        _helperEntriesForTab(helperAcceptances, view.WorkerJobsTab.pending)
            .length;
    final scheduledHelperCount =
        _helperEntriesForTab(helperAcceptances, view.WorkerJobsTab.scheduled)
            .length;
    final completedHelperCount =
        _helperEntriesForTab(helperAcceptances, view.WorkerJobsTab.completed)
            .length;

    return view.WorkerJobsScreen(
      selectedTab: _selectedTab,
      pendingCount: (pendingAsync.asData?.value.length ?? 0) + pendingHelperCount,
      scheduledCount:
          (scheduledAsync.asData?.value.length ?? 0) + scheduledHelperCount,
      completedCount: completedPage0.length +
          _additionalCompleted.length +
          completedHelperCount,
      jobs: jobs,
      loading: loading,
      errorMessage: errorMessage,
      onRetry: () {
        ref.invalidate(pendingWorkerProposalsProvider);
        ref.invalidate(scheduledWorkerProposalsProvider);
        ref.invalidate(completedWorkerProposalsProvider(0));
        ref.invalidate(myHelpAcceptancesProvider);
      },
      onRefresh: _onRefresh,
      highlightedJobId: _highlightedJobId,
      // Scroll infinito continua a paginar só o lado "responsável"
      // (job_proposals via .range()). `get_my_help_acceptances` não tem
      // LIMIT/OFFSET (ver improvements.md — B1 Fase 9); em vez de acoplar
      // essa paginação aqui, a lista de ajudante é carregada inteira de
      // uma vez (mesmo padrão já usado na tab "As minhas candidaturas") e
      // fica sempre visível, por cima ou por baixo consoante a página do
      // lado responsável já carregada. `_hasMore`/`_loadMore` não contam
      // itens de ajudante — continuam a refletir só as páginas de
      // `job_proposals`, por isso nunca ficam incorretos.
      onLoadMore: _selectedTab == view.WorkerJobsTab.completed && _hasMore
          ? _loadMore
          : null,
      loadingMore: _loadingMore,
      onTabSelected: (tab) => setState(() => _selectedTab = tab),
      onJobPressed: (id) {
        if (helperJobIds.contains(id)) {
          // Ainda não existe um ecrã de detalhe próprio para o papel de
          // ajudante — reaproveita a tab "As minhas candidaturas", onde já
          // vivem as ações (Desistir, WhatsApp, avaliação).
          context.push('/worker/help-requests', extra: {'initialTabIndex': 1});
          return;
        }
        final jobId = jobIdByProposalId[id];
        if (jobId == null) return;
        context.push('/worker/my-job/$id?jobId=$jobId');
      },
    );
  }
}
