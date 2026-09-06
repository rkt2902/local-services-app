import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_status_presentation.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../../core/utils/error_utils.dart';
import '../../jobs/application/job_providers.dart';
import '../application/worker_job_board_providers.dart';
import '../data/worker_job_board_entry_model.dart';
import 'widgets/worker_jobs_view.dart' as view;

String _tabParam(view.WorkerJobsTab tab) => switch (tab) {
      view.WorkerJobsTab.pending => 'pending',
      view.WorkerJobsTab.scheduled => 'scheduled',
      view.WorkerJobsTab.completed => 'completed',
    };

view.WorkerJobsTab? _tabFromName(String? name) {
  return switch (name) {
    'pending' => view.WorkerJobsTab.pending,
    'scheduled' => view.WorkerJobsTab.scheduled,
    'completed' => view.WorkerJobsTab.completed,
    _ => null,
  };
}

String _formatDate(DateTime? date) {
  if (date == null) return 'Flexível';
  return DateFormat('dd/MM/yyyy').format(date);
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

/// Data/hora do card. Fallback para a data preferida do pedido original só
/// faz sentido para o responsável (job ainda `open`, sem data confirmada) —
/// um ajudante só existe depois de o job já estar `confirmed`, por isso
/// nunca há "preferida" do lado dele; o fallback é um texto neutro.
String _scheduleLabelFor(WorkerJobBoardEntry e) {
  if (e.confirmedDate != null) {
    final date = DateFormat('dd/MM/yyyy').format(e.confirmedDate!);
    if (e.confirmedFlexible) return '$date (flexível)';
    if (e.confirmedTime != null) return '$date às ${e.confirmedTime}';
    return date;
  }
  if (e.role == WorkerJobBoardRole.helper) return 'Horário a combinar';
  return _formatDate(e.preferredDate);
}

/// "Pendentes" significa coisas diferentes consoante o papel: para o
/// responsável o job ainda está `open`, a aguardar decisão do cliente; para
/// o ajudante o job já está `confirmed` — quem decide agora é o
/// responsável. Texto adaptado só nesse cruzamento específico; nas outras
/// tabs os dois papéis mostram o endereço do job.
String _secondaryLabelFor(WorkerJobBoardEntry e, view.WorkerJobsTab tab) {
  if (e.role == WorkerJobBoardRole.helper &&
      tab == view.WorkerJobsTab.pending) {
    return 'Trabalho já confirmado — a aguardar decisão do responsável';
  }
  return e.addressText.isNotEmpty
      ? e.addressText
      : 'Localização não especificada';
}

String _priceLabelFor(WorkerJobBoardEntry e) {
  if (e.role == WorkerJobBoardRole.helper) {
    final rate = e.agreedRate ?? 0;
    return rate > 0 ? '€${rate.toStringAsFixed(2)}/h' : 'A combinar';
  }
  return _formatEstimate(
      e.hourlyRate ?? 0, e.estimatedHoursMin, e.estimatedHoursMax);
}

/// `status` guarda o valor bruto do enum específico do papel — resolve-se
/// com `ProposalStatus` (responsável) ou `HelpAcceptanceStatus` (ajudante).
AppStatusPresentation _statusPresentationFor(WorkerJobBoardEntry e) {
  if (e.role == WorkerJobBoardRole.helper) {
    return HelpAcceptanceStatus.fromValue(e.status).presentation;
  }
  return ProposalStatus.fromValue(e.status).presentation;
}

view.WorkerJobListItemViewData _toViewData(
  WorkerJobBoardEntry e,
  view.WorkerJobsTab tab,
) {
  return view.WorkerJobListItemViewData(
    id: e.entryId,
    title: e.serviceTypeName,
    personName: e.personName,
    locationLabel: _scheduleLabelFor(e),
    secondaryLabel: _secondaryLabelFor(e, tab),
    priceLabel: _priceLabelFor(e),
    status: _statusPresentationFor(e),
    role: e.role == WorkerJobBoardRole.helper
        ? view.WorkerJobRole.helper
        : view.WorkerJobRole.responsible,
  );
}

/// Ecrã "Os meus trabalhos" (Flow 5) — wrapper de integração que liga o
/// board unificado (`get_worker_job_board`, migration 0035: responsável +
/// ajudante, filtrado/ordenado/paginado inteiramente server-side) ao
/// componente apresentacional em `widgets/worker_jobs_view.dart`.
class WorkerJobsScreen extends ConsumerStatefulWidget {
  const WorkerJobsScreen({
    super.key,
    this.highlightedJobId,
    this.initialTab,
  });

  /// Suporte a deep-link de notificações — ver `app_router.dart` (extra da
  /// rota `/worker/jobs`) e `notification_handler.dart`. Compara-se contra
  /// `entry_id` (proposta ou candidatura), nunca `job_id`.
  final String? highlightedJobId;
  final String? initialTab;

  @override
  ConsumerState<WorkerJobsScreen> createState() => _WorkerJobsScreenState();
}

class _WorkerJobsScreenState extends ConsumerState<WorkerJobsScreen> {
  late view.WorkerJobsTab _selectedTab;
  String? _highlightedJobId;
  Timer? _highlightTimer;

  /// Paginação por tab. A página 0 vem sempre do provider (`ref.watch`);
  /// páginas seguintes acumulam-se aqui — mesmo padrão que antes existia só
  /// para "Concluídos", agora generalizado às 3 tabs porque
  /// `get_worker_job_board` pagina qualquer uma delas igualmente bem.
  final Map<view.WorkerJobsTab, int> _pageByTab = {
    for (final t in view.WorkerJobsTab.values) t: 0,
  };
  final Map<view.WorkerJobsTab, List<WorkerJobBoardEntry>> _extraByTab = {
    for (final t in view.WorkerJobsTab.values) t: [],
  };
  final Map<view.WorkerJobsTab, bool> _loadingMoreByTab = {
    for (final t in view.WorkerJobsTab.values) t: false,
  };

  @override
  void initState() {
    super.initState();
    _selectedTab =
        _tabFromName(widget.initialTab) ?? view.WorkerJobsTab.pending;
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

  void _resetPagination(view.WorkerJobsTab tab) {
    _pageByTab[tab] = 0;
    _extraByTab[tab] = [];
    _loadingMoreByTab[tab] = false;
  }

  Future<void> _onRefresh() async {
    setState(() {
      for (final t in view.WorkerJobsTab.values) {
        _resetPagination(t);
      }
    });
    for (final t in view.WorkerJobsTab.values) {
      ref.invalidate(workerJobBoardPageProvider((_tabParam(t), 0)));
    }
    ref.invalidate(jobsInRadiusProvider);
  }

  void _loadMore() {
    final tab = _selectedTab;
    if (_loadingMoreByTab[tab] == true) return;
    setState(() => _loadingMoreByTab[tab] = true);
    final nextPage = (_pageByTab[tab] ?? 0) + 1;
    ref
        .read(workerJobBoardPageProvider((_tabParam(tab), nextPage)).future)
        .then((page) {
      if (!mounted) return;
      setState(() {
        _pageByTab[tab] = nextPage;
        _extraByTab[tab] = [...?_extraByTab[tab], ...page];
        _loadingMoreByTab[tab] = false;
      });
    }).catchError((_) {
      if (mounted) setState(() => _loadingMoreByTab[tab] = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Página 0 das 3 tabs é sempre observada — os badges de contagem
    // precisam do `total_count` de todas, não só da tab selecionada (mesmo
    // comportamento que já existia antes desta refactor).
    final page0ByTab = {
      for (final t in view.WorkerJobsTab.values)
        t: ref.watch(workerJobBoardPageProvider((_tabParam(t), 0))),
    };

    // Reinicia a paginação de uma tab sempre que a respetiva página 0 for
    // invalidada externamente (ex.: notificationSyncProvider), para não
    // misturar páginas extra antigas com dados novos.
    for (final t in view.WorkerJobsTab.values) {
      ref.listen(workerJobBoardPageProvider((_tabParam(t), 0)), (prev, next) {
        if (next.isLoading && mounted) {
          setState(() => _resetPagination(t));
        }
      });
    }

    int totalCountFor(view.WorkerJobsTab tab) {
      final page0 = page0ByTab[tab]!.asData?.value ?? const [];
      return page0.isNotEmpty ? page0.first.totalCount : 0;
    }

    final selectedAsync = page0ByTab[_selectedTab]!;
    final loading = selectedAsync.isLoading && !selectedAsync.hasValue;
    final errorMessage =
        selectedAsync.hasError ? friendlyError(selectedAsync.error!) : null;

    final page0 = selectedAsync.asData?.value ?? const [];
    final extra = _extraByTab[_selectedTab] ?? const [];
    final entries = [...page0, ...extra];
    final totalCount = totalCountFor(_selectedTab);
    final hasMore = entries.length < totalCount;

    final jobs = [for (final e in entries) _toViewData(e, _selectedTab)];

    return view.WorkerJobsScreen(
      selectedTab: _selectedTab,
      pendingCount: totalCountFor(view.WorkerJobsTab.pending),
      scheduledCount: totalCountFor(view.WorkerJobsTab.scheduled),
      completedCount: totalCountFor(view.WorkerJobsTab.completed),
      jobs: jobs,
      loading: loading,
      errorMessage: errorMessage,
      onRetry: () {
        for (final t in view.WorkerJobsTab.values) {
          ref.invalidate(workerJobBoardPageProvider((_tabParam(t), 0)));
        }
      },
      onRefresh: _onRefresh,
      highlightedJobId: _highlightedJobId,
      // Scroll infinito real nas 3 tabs — a RPC pagina qualquer uma delas
      // da mesma forma, por isso deixou de haver razão para restringir a
      // "Concluídos" como acontecia com a paginação anterior (só do lado
      // job_proposals). `hasMore` vem do `total_count` devolvido pela RPC
      // (COUNT(*) OVER()), não de um heurístico de "página cheia".
      onLoadMore: hasMore ? _loadMore : null,
      loadingMore: _loadingMoreByTab[_selectedTab] ?? false,
      onTabSelected: (tab) => setState(() => _selectedTab = tab),
      onJobPressed: (id) {
        final entry = entries.where((e) => e.entryId == id).firstOrNull;
        if (entry == null) return;
        if (entry.role == WorkerJobBoardRole.helper) {
          // Ainda não existe um ecrã de detalhe próprio para o papel de
          // ajudante — reaproveita a tab "As minhas candidaturas", onde já
          // vivem as ações (Desistir, WhatsApp, avaliação).
          context.push('/worker/help-requests', extra: {'initialTabIndex': 1});
          return;
        }
        context.push('/worker/my-job/$id?jobId=${entry.jobId}');
      },
    );
  }
}
