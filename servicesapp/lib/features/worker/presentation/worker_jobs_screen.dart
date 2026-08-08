import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/error_utils.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../client/application/client_providers.dart';
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

    final jobs = [
      for (final entry in entries)
        _toViewData(entry.$1, entry.$2, serviceTypes),
    ];

    return view.WorkerJobsScreen(
      selectedTab: _selectedTab,
      pendingCount: pendingAsync.asData?.value.length ?? 0,
      scheduledCount: scheduledAsync.asData?.value.length ?? 0,
      completedCount: completedPage0.length + _additionalCompleted.length,
      jobs: jobs,
      loading: loading,
      errorMessage: errorMessage,
      onRetry: () {
        ref.invalidate(pendingWorkerProposalsProvider);
        ref.invalidate(scheduledWorkerProposalsProvider);
        ref.invalidate(completedWorkerProposalsProvider(0));
      },
      onRefresh: _onRefresh,
      highlightedJobId: _highlightedJobId,
      onLoadMore: _selectedTab == view.WorkerJobsTab.completed && _hasMore
          ? _loadMore
          : null,
      loadingMore: _loadingMore,
      onTabSelected: (tab) => setState(() => _selectedTab = tab),
      onJobPressed: (proposalId) {
        final jobId = jobIdByProposalId[proposalId];
        if (jobId == null) return;
        context.push('/worker/my-job/$proposalId?jobId=$jobId');
      },
    );
  }
}
