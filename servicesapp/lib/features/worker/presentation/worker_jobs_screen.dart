import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/theme/app_status_presentation.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/utils/date_labels.dart';
import '../../../core/utils/price_labels.dart';
import '../../proposals/application/proposal_price_labels.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/service_icon.dart';
import '../../agenda/presentation/agenda_entry_editor_screen.dart';
import '../../agenda/presentation/widgets/agenda_legend.dart';
import '../../agenda/presentation/worker_agenda_tab.dart';
import '../../notifications/application/notification_providers.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/data/cancel_reasons.dart';
import '../application/worker_job_rules.dart';
import '../application/worker_job_board_providers.dart';
import '../data/worker_job_board_entry_model.dart';
import 'widgets/worker_jobs_view.dart' as view;

String _tabParam(view.WorkerJobsTab tab) => switch (tab) {
      view.WorkerJobsTab.pending => 'pending',
      view.WorkerJobsTab.scheduled => 'scheduled',
      // A RPC continua a chamar "completed" ao histórico.
      view.WorkerJobsTab.history => 'completed',
    };

/// Nomes antigos das tabs (notificações, Início): "Agendados" passou a ser
/// a Agenda.
view.WorkerJobsSection _sectionFromName(String? name) {
  return switch (name) {
    'pending' || 'proposals' => view.WorkerJobsSection.proposals,
    'completed' || 'history' => view.WorkerJobsSection.history,
    _ => view.WorkerJobsSection.agenda,
  };
}

/// Tabs do board que o ecrã lê: a Agenda vem de `get_worker_agenda`.
const _boardTabs = [view.WorkerJobsTab.pending, view.WorkerJobsTab.history];

final _dayMonth = DateFormat('dd/MM');

/// Localidade do cartão: `location_area` (0053) ou, com a BD antiga, o
/// último segmento da morada (que já é só a zona antes de aceite).
String _areaOf(WorkerJobBoardEntry e) {
  final area = e.locationArea?.trim() ?? '';
  if (area.isNotEmpty) return area;
  return e.addressText.split(',').last.trim();
}

/// "Hoje", "Amanhã" ou "Sex, 24/10".
String _dayLabel(DateTime date, DateTime now) {
  final today = DateUtils.dateOnly(now);
  final day = DateUtils.dateOnly(date);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Hoje';
  if (diff == 1) return 'Amanhã';
  return shortWeekdayDateLabel(date, now: now);
}

/// "Hoje · 9:00" / "Sex, 24/10 · horário flexível" / "Data a combinar".
String _whenLabel(WorkerJobBoardEntry e, DateTime now) {
  final date = e.confirmedDate;
  if (date == null) return 'Data a combinar';
  final day = _dayLabel(date, now);
  if (e.confirmedFlexible) return '$day · horário flexível';
  final time = e.confirmedTime;
  if (time == null || time.length < 5) return day;
  final hour = int.tryParse(time.substring(0, 2));
  return hour == null ? day : '$day · $hour:${time.substring(3, 5)}';
}

String? _estimateOf(WorkerJobBoardEntry e) {
  final fixed = boardFixedPriceLabel(e.pricingMode, e.totalPrice);
  if (fixed != null) return fixed;
  final rate = e.hourlyRate ?? 0;
  if (rate <= 0) return null;
  final total = estimatedTotalLabel(
    rate,
    e.estimatedHoursMin,
    e.estimatedHoursMax,
    peopleNeeded: e.peopleNeeded,
    helpersEquipmentRequired: e.helpersEquipmentRequired,
  );
  return total.isNotEmpty ? total : hourlyRateLabel(rate);
}

/// Data com que um registo entra no Histórico (e o mês em que fica).
DateTime workerHistoryDate(WorkerJobBoardEntry e) =>
    (e.jobUpdatedAt ?? e.confirmedDate ?? e.createdAt).toLocal();

const _monthNames = [
  'Janeiro',
  'Fevereiro',
  'Março',
  'Abril',
  'Maio',
  'Junho',
  'Julho',
  'Agosto',
  'Setembro',
  'Outubro',
  'Novembro',
  'Dezembro',
];

/// "Outubro"; noutro ano, "Outubro de 2025".
@visibleForTesting
String workerHistoryMonthLabel(DateTime date, DateTime now) {
  final month = _monthNames[date.month - 1];
  return date.year == now.year ? month : '$month de ${date.year}';
}

/// Linha de detalhe e valor de um cartão (design A2), por tab e papel.
@visibleForTesting
({String meta, String? amount}) workerJobCardText(
  WorkerJobBoardEntry e,
  view.WorkerJobsTab tab,
  DateTime now,
) {
  final isHelper = e.role == WorkerJobBoardRole.helper;
  final withPerson = e.personName.isNotEmpty ? 'com ${e.personName}' : null;
  String join(List<String?> parts) =>
      parts.whereType<String>().where((p) => p.isNotEmpty).join(' · ');

  switch (tab) {
    case view.WorkerJobsTab.pending:
      final sent = _dayMonth.format(e.createdAt.toLocal());
      if (isHelper) {
        return (meta: join(['Candidatura a $sent', withPerson]), amount: null);
      }
      return (
        meta: join(['Proposta enviada a $sent', _areaOf(e)]),
        amount: _estimateOf(e),
      );

    case view.WorkerJobsTab.scheduled:
      if (e.jobStatus == 'awaiting_confirmation') {
        final done = e.markedDoneAt?.toLocal();
        if (done == null) {
          return (meta: 'À espera da confirmação do cliente', amount: null);
        }
        final left = done
            .add(const Duration(hours: WorkerJobDayRules.autoConfirmHours))
            .difference(now);
        final hours = (left.inMinutes / 60).ceil();
        final when = hours <= 0 ? 'em breve' : 'em ${hours}h';
        return (
          meta:
              'Feito a ${_dayMonth.format(done)} · confirma automaticamente $when',
          amount: null,
        );
      }
      if (isHelper) {
        return (meta: join([_whenLabel(e, now), withPerson]), amount: null);
      }
      return (
        meta: join([_whenLabel(e, now), _areaOf(e)]),
        amount: _estimateOf(e),
      );

    case view.WorkerJobsTab.history:
      final date = _dayMonth.format(workerHistoryDate(e));
      final mine = e.status == 'accepted';
      final String detail;
      if (e.jobStatus == 'completed' && mine) {
        detail =
            isHelper ? (withPerson ?? '') : join([_areaOf(e), _estimateOf(e)]);
      } else if (e.jobStatus == 'no_response') {
        detail = 'expirou sem resposta';
      } else if (e.jobStatus == 'cancelled' &&
          e.cancelReason == CancelReason.expired) {
        detail = 'expirou sem ser concluído';
      } else if (e.jobStatus == 'cancelled' &&
          (mine || e.status == 'pending')) {
        detail = e.cancelledByMe
            ? 'cancelaste'
            : e.cancelledByClient
                ? 'cancelado pelo cliente'
                : 'cancelado';
      } else if (isHelper) {
        detail = e.status == 'rejected'
            ? 'a equipa ficou completa'
            : (withPerson ?? '');
      } else if (e.status == 'rejected') {
        detail = 'o cliente escolheu outra proposta';
      } else if (e.status == 'superseded') {
        detail = 'retiraste a proposta';
      } else {
        detail = _areaOf(e);
      }
      return (meta: join([date, detail]), amount: null);
  }
}

/// Badge do cartão. Com `jobStatus` (0048) diz em que ponto está o
/// trabalho ("Agendado", "À espera do cliente", "Cancelado"); sem ele cai
/// no estado da proposta ou candidatura, como antes.
AppStatusPresentation _statusPresentationFor(WorkerJobBoardEntry e) {
  final fromJob = workerBoardJobPresentation(
    e.status,
    e.jobStatus,
    cancelReason: e.cancelReason,
    started: e.startedAt != null,
  );
  if (fromJob != null) return fromJob;
  if (e.role == WorkerJobBoardRole.helper) {
    return HelpAcceptanceStatus.fromValue(e.status).presentation;
  }
  return ProposalStatus.fromValue(e.status).presentation;
}

/// Estado do trabalho para uma proposta ou candidatura, ou `null` quando o
/// estado da própria proposta/candidatura diz mais (ainda pendente, não
/// selecionada num pedido que seguiu com outro, ou BD sem `job_status`).
/// Regra do design A2: o badge é o estado do trabalho; "Não selecionada" é
/// a exceção, porque aí não houve trabalho.
@visibleForTesting
AppStatusPresentation? workerBoardJobPresentation(
  String entryStatus,
  String? jobStatus, {
  String? cancelReason,
  bool started = false,
}) {
  if (jobStatus == null) return null;
  final isMine = entryStatus == 'accepted';
  final expired = jobStatus == 'no_response' ||
      (jobStatus == 'cancelled' && cancelReason == CancelReason.expired);
  if (jobStatus == 'cancelled' || jobStatus == 'no_response') {
    if (!isMine && entryStatus != 'pending' && entryStatus != 'rejected') {
      return null;
    }
    if (expired) {
      return const AppStatusPresentation(
        label: 'Expirado',
        color: AppStatusColor.neutral,
      );
    }
    // Cancelado a vermelho só quando o trabalho era deste jardineiro.
    return isMine
        ? JobStatus.cancelled.presentation()
        : const AppStatusPresentation(
            label: 'Cancelado',
            color: AppStatusColor.neutral,
          );
  }
  if (!isMine) return null;
  return switch (jobStatus) {
    'confirmed' => started
        ? const AppStatusPresentation(
            label: 'Em curso',
            color: AppStatusColor.info,
          )
        : const AppStatusPresentation(
            label: 'Agendado',
            color: AppStatusColor.success,
          ),
    'awaiting_confirmation' => const AppStatusPresentation(
        label: 'À espera do cliente',
        color: AppStatusColor.waiting,
      ),
    'completed' => const AppStatusPresentation(
        label: 'Concluído',
        color: AppStatusColor.success,
      ),
    _ => null,
  };
}

view.WorkerJobListItemViewData _toViewData(
  WorkerJobBoardEntry e,
  view.WorkerJobsTab tab,
  DateTime now,
  List<ServiceType> serviceTypes, {
  required bool animateEntrance,
}) {
  final text = workerJobCardText(e, tab, now);
  // Ícone pelo id do serviço (0053); com a BD antiga, pelo nome.
  final byName =
      serviceTypes.where((t) => t.name == e.serviceTypeName).firstOrNull;
  final icon = e.serviceTypeId != null
      ? serviceTypeIconFor(serviceTypes, e.serviceTypeId)
      : serviceIconFor(byName?.icon);
  final completedMine = e.status == 'accepted' && e.jobStatus == 'completed';
  return view.WorkerJobListItemViewData(
    id: e.entryId,
    title: e.serviceTypeName,
    serviceIcon: icon,
    metaLabel: text.meta,
    amountLabel: text.amount,
    status: _statusPresentationFor(e),
    roleLabel: e.role == WorkerJobBoardRole.helper ? 'Ajudante' : null,
    muted: tab == view.WorkerJobsTab.history && !completedMine,
    animateEntrance: animateEntrance,
  );
}

/// Ecrã Trabalhos (Flow 5, design A8) — wrapper de integração. A tab Agenda
/// é `WorkerAgendaTab` (0064); Propostas e Histórico ligam o board unificado
/// (`get_worker_job_board`, migration 0035: responsável + ajudante,
/// filtrado/ordenado/paginado inteiramente server-side) ao componente
/// apresentacional em `widgets/worker_jobs_view.dart`.
class WorkerJobsScreen extends ConsumerStatefulWidget {
  const WorkerJobsScreen({
    super.key,
    this.highlightedJobId,
    this.initialTab,
    this.agendaResult,
  });

  /// Suporte a deep-link de notificações — ver `app_router.dart` (extra da
  /// rota `/worker/jobs`) e `notification_handler.dart`. Compara-se contra
  /// `entry_id` (proposta ou candidatura), nunca `job_id`.
  final String? highlightedJobId;
  final String? initialTab;

  /// Guardado no "Adicionar à agenda" aberto pelo "+": a Agenda abre no
  /// dia e realça o cartão.
  final AgendaEditorResult? agendaResult;

  @override
  ConsumerState<WorkerJobsScreen> createState() => _WorkerJobsScreenState();
}

class _WorkerJobsScreenState extends ConsumerState<WorkerJobsScreen> {
  late view.WorkerJobsSection _selectedSection;
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
    _selectedSection = _sectionFromName(widget.initialTab);
    _highlightedJobId = widget.highlightedJobId;
    if (_highlightedJobId != null) {
      _highlightTimer = Timer(const Duration(milliseconds: 1300), () {
        if (mounted) setState(() => _highlightedJobId = null);
      });
    }
  }

  @override
  void didUpdateWidget(covariant WorkerJobsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.agendaResult != null &&
        widget.agendaResult != oldWidget.agendaResult) {
      setState(() => _selectedSection = view.WorkerJobsSection.agenda);
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
      for (final t in _boardTabs) {
        _resetPagination(t);
      }
    });
    for (final t in _boardTabs) {
      ref.invalidate(workerJobBoardPageProvider((_tabParam(t), 0)));
    }
    ref.invalidate(jobsInRadiusProvider);
  }

  void _loadMore(view.WorkerJobsTab tab) {
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
    // Página 0 das 2 listas é sempre observada: a contagem de Propostas vem
    // do `total_count` e as listas ficam montadas (cada tab guarda o seu
    // scroll).
    final page0ByTab = {
      for (final t in _boardTabs)
        t: ref.watch(workerJobBoardPageProvider((_tabParam(t), 0))),
    };

    // Reinicia a paginação de uma tab sempre que a respetiva página 0 for
    // invalidada externamente (ex.: notificationSyncProvider), para não
    // misturar páginas extra antigas com dados novos.
    for (final t in _boardTabs) {
      ref.listen(workerJobBoardPageProvider((_tabParam(t), 0)), (prev, next) {
        if (next.isLoading && mounted) {
          setState(() => _resetPagination(t));
        }
      });
    }

    final serviceTypes =
        ref.watch(serviceTypesProvider).asData?.value ?? const <ServiceType>[];
    final now = DateTime.now();

    int totalCountFor(view.WorkerJobsTab tab) {
      final page0 = page0ByTab[tab]!.asData?.value ?? const [];
      return page0.isNotEmpty ? page0.first.totalCount : 0;
    }

    final entriesByTab = <view.WorkerJobsTab, List<WorkerJobBoardEntry>>{};

    view.WorkerJobsTabViewData tabData(view.WorkerJobsTab tab) {
      final async = page0ByTab[tab]!;
      final page0 = async.asData?.value ?? const <WorkerJobBoardEntry>[];
      final extra = _extraByTab[tab] ?? const <WorkerJobBoardEntry>[];
      entriesByTab[tab] = [...page0, ...extra];

      final items = [
        for (final e in page0)
          (e, _toViewData(e, tab, now, serviceTypes, animateEntrance: true)),
        for (final e in extra)
          (e, _toViewData(e, tab, now, serviceTypes, animateEntrance: false)),
      ];

      final List<view.WorkerJobsSectionViewData> sections;
      if (tab == view.WorkerJobsTab.history) {
        // Um cabeçalho por mês, pela ordem da RPC (mais recente primeiro).
        sections = [];
        for (final (entry, item) in items) {
          final label = workerHistoryMonthLabel(workerHistoryDate(entry), now);
          if (sections.isEmpty || sections.last.label != label) {
            sections
                .add(view.WorkerJobsSectionViewData(label: label, items: []));
          }
          sections.last.items.add(item);
        }
      } else {
        sections = [
          view.WorkerJobsSectionViewData(
            items: [for (final (_, item) in items) item],
          ),
        ];
      }

      return view.WorkerJobsTabViewData(
        sections: sections,
        loading: async.isLoading && !async.hasValue,
        errorMessage: async.hasError && !async.hasValue
            ? friendlyError(async.error!)
            : null,
        canLoadMore: entriesByTab[tab]!.length < totalCountFor(tab),
        loadingMore: _loadingMoreByTab[tab] ?? false,
      );
    }

    final pending = tabData(view.WorkerJobsTab.pending);
    final history = tabData(view.WorkerJobsTab.history);

    return view.WorkerJobsScreen(
      selectedSection: _selectedSection,
      agenda: WorkerAgendaTab(savedResult: widget.agendaResult),
      // Sem contagem no histórico: só cresce, o número não ajuda a decidir.
      proposalsCount: totalCountFor(view.WorkerJobsTab.pending),
      pending: pending,
      history: history,
      hasUnreadNotifications: ref.watch(unreadCountProvider) > 0,
      onNotificationsPressed: () => context.push('/notifications'),
      onColorsPressed: () => AppSheet.show<void>(
        context,
        builder: (_) => const SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.s20,
              AppSpacing.lg,
              AppSpacing.s20,
              AppSpacing.md,
            ),
            child: AgendaLegendSheet(),
          ),
        ),
      ),
      onRetry: () {
        for (final t in _boardTabs) {
          ref.invalidate(workerJobBoardPageProvider((_tabParam(t), 0)));
        }
      },
      onRefresh: _onRefresh,
      highlightedJobId: _highlightedJobId,
      // Scroll infinito real nas 3 tabs: `canLoadMore` vem do `total_count`
      // devolvido pela RPC (COUNT(*) OVER()), não de um heurístico de
      // "página cheia".
      onLoadMore: _loadMore,
      onSectionSelected: (section) =>
          setState(() => _selectedSection = section),
      onFindJobsPressed: () => context.go('/worker/available-jobs'),
      onJobPressed: (id) {
        final entry = entriesByTab.values
            .expand((list) => list)
            .where((e) => e.entryId == id)
            .firstOrNull;
        if (entry == null) return;
        if (entry.role == WorkerJobBoardRole.helper) {
          // `entry_id` de uma linha de ajudante é o id da candidatura.
          context.push('/worker/help/${entry.entryId}');
          return;
        }
        context.push('/worker/my-job/$id?jobId=${entry.jobId}');
      },
    );
  }
}
