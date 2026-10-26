import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/utils/phone_utils.dart';
import '../../../core/widgets/address_map_link.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_toast.dart';
import '../../jobs/application/job_providers.dart';
import '../../worker/application/worker_list_invalidation.dart';
import '../../worker/presentation/widgets/start_job_sheet.dart';
import '../application/agenda_providers.dart';
import '../data/agenda_entry_model.dart';
import 'agenda_day_presenter.dart';
import 'agenda_month_presenter.dart';
import 'agenda_month_sheet.dart';
import 'agenda_week_presenter.dart';
import 'agenda_week_view_data.dart';
import 'widgets/agenda_controls.dart';
import 'widgets/agenda_day_view.dart';
import 'widgets/agenda_month_view.dart';
import 'widgets/agenda_week_view.dart';

/// Tab Agenda do ecrã Trabalhos: liga `get_worker_agenda` (0064) às vistas
/// Hoje (`AgendaDayView`), Semana (`AgendaWeekView`) e Mês (`AgendaMonthView`)
/// e trata das ações.
class WorkerAgendaTab extends ConsumerStatefulWidget {
  const WorkerAgendaTab({super.key});

  @override
  ConsumerState<WorkerAgendaTab> createState() => _WorkerAgendaTabState();
}

class _WorkerAgendaTabState extends ConsumerState<WorkerAgendaTab> {
  AgendaRange _range = AgendaRange.day;

  /// Dia mostrado no Hoje; na Semana, o dia preenchido (a semana é a dele).
  late DateTime _day = DateUtils.dateOnly(DateTime.now());
  bool _showProposals = true;

  /// Veio do "Ver o dia" da Semana: o Hoje abre nos que coincidem.
  bool _focusOverlap = false;

  /// Hora da última leitura boa, para a faixa "Sem rede · dados das 08:12".
  DateTime? _loadedAt;

  /// A linha de agora e o "Iniciar" mudam com o relógio.
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void _goTo(DateTime day) => setState(() {
    _day = DateUtils.dateOnly(day);
    _focusOverlap = false;
  });

  /// Semana que começa em [weekStart]: preenche hoje se lá estiver, senão a
  /// segunda.
  void _goToWeek(DateTime weekStart) {
    final today = DateUtils.dateOnly(DateTime.now());
    final inWeek = agendaWeekStart(today) == weekStart;
    _goTo(inWeek ? today : weekStart);
  }

  /// Mês de [month]: escolhe hoje se lá estiver, senão o dia 1.
  void _goToMonth(DateTime month) {
    final today = DateUtils.dateOnly(DateTime.now());
    final inMonth = today.year == month.year && today.month == month.month;
    _goTo(inMonth ? today : DateTime(month.year, month.month));
  }

  /// Abre o Hoje em [day]; com [atConflict], já nos que coincidem.
  void _openDay(DateTime day, {bool atConflict = false}) => setState(() {
    _range = AgendaRange.day;
    _day = DateUtils.dateOnly(day);
    _focusOverlap = atConflict;
  });

  /// Meses lidos para o período mostrado: o do dia no Hoje; na Semana, os
  /// dois quando ela atravessa o fim do mês. A mesma cache serve as duas.
  List<(DateTime, DateTime)> _monthRanges() {
    if (_range != AgendaRange.week) return [agendaMonthRange(_day)];
    final start = agendaWeekStart(_day);
    final first = agendaMonthRange(start);
    final last = agendaMonthRange(agendaWeekDays(start).last);
    return first == last ? [first] : [first, last];
  }

  Future<void> _refresh() async {
    final ranges = _monthRanges();
    for (final range in ranges) {
      ref.invalidate(agendaRangeProvider(range));
    }
    try {
      await Future.wait([
        for (final range in ranges) ref.read(agendaRangeProvider(range).future),
      ]);
    } catch (_) {
      // O erro aparece na vista (faixa sem rede ou estado de erro).
    }
  }

  Future<void> _openCalendar() async {
    final picked = await AppSheet.show<DateTime>(
      context,
      builder: (_) => AgendaMonthSheet(selectedDay: _day),
    );
    if (picked != null && mounted) _goTo(picked);
  }

  void _onRangeChanged(AgendaRange range) {
    setState(() {
      _range = range;
      _focusOverlap = false;
    });
  }

  void _openEntry(AgendaEntry e) {
    final jobId = e.jobId;
    if (jobId == null) return;
    switch (e.kind) {
      case AgendaEntryKind.helperJob:
        // source_id de um ajudante é a candidatura.
        context.push('/worker/help/${e.sourceId}');
      case AgendaEntryKind.appJob ||
          AgendaEntryKind.reschedule ||
          AgendaEntryKind.proposal:
        final proposalId = e.proposalId;
        if (proposalId == null) return;
        context.push('/worker/my-job/$proposalId?jobId=$jobId');
      case AgendaEntryKind.external || AgendaEntryKind.block:
        return;
    }
  }

  /// Mesmo fluxo do detalhe: folha "Iniciar o trabalho agora?", fotos de
  /// antes e `start_job`. Fica na Agenda.
  Future<void> _startJob(AgendaEntry e) async {
    final jobId = e.jobId;
    if (jobId == null) return;
    final toast = AppToast.of(context);
    final started = await StartJobSheet.show(
      context,
      clientName: e.personName ?? 'o cliente',
      onStart: (photos) async {
        try {
          final repo = ref.read(jobRepositoryProvider);
          final paths = <String>[];
          for (final photo in photos) {
            paths.add(
              await repo.uploadWorkPhoto(
                jobId: jobId,
                file: photo,
                before: true,
              ),
            );
          }
          await repo.startJob(jobId, photoPaths: paths);
          return true;
        } catch (err) {
          toast.error(friendlyError(err));
          return false;
        }
      },
    );
    if (!started || !mounted) return;
    // Regra T4: sem navegação; aviso → invalidar.
    toast.show('Trabalho iniciado. O cliente foi avisado.');
    invalidateWorkerLists(ref, jobId: jobId);
  }

  Future<void> _openMap(AgendaEntry e) async {
    final lat = e.locationLat;
    final lng = e.locationLng;
    if (lat != null && lng != null) {
      await AddressMapLink.openInMaps(lat, lng);
      return;
    }
    // Proposta pendente: só a zona.
    final label = e.locationLabel?.trim() ?? '';
    if (label.isEmpty) return;
    await launchUrl(
      Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(label)}',
      ),
      mode: LaunchMode.externalApplication,
    );
  }

  /// "Mudar a hora" de um dos que coincidem: abre o trabalho escolhido,
  /// onde se pede a remarcação.
  Future<void> _resolveOverlap(List<AgendaEntry> entries) async {
    final openable = [
      for (final e in entries)
        if (e.jobId != null) e,
    ];
    if (openable.isEmpty) return;
    if (openable.length == 1) {
      _openEntry(openable.single);
      return;
    }
    final serviceTypes =
        ref.read(serviceTypesProvider).asData?.value ?? const <ServiceType>[];
    final chosen = await AppSheet.show<AgendaEntry>(
      context,
      builder: (sheetContext) => AppSheet(
        title: 'Qual queres mudar?',
        onClose: () => Navigator.pop(sheetContext),
        child: _OverlapChoice(
          entries: openable,
          serviceTypes: serviceTypes,
          onSelected: (e) => Navigator.pop(sheetContext, e),
        ),
      ),
    );
    if (chosen != null && mounted) _openEntry(chosen);
  }

  /// "Já estou livre": só o dia mostrado, depois de confirmar.
  Future<void> _markAvailable(AgendaEntry block) async {
    final dayLabel = agendaShortDate(_day, now: DateTime.now());
    final confirmed = await AppConfirmDialog.show(
      context,
      icon: Icons.event_available_outlined,
      title: 'Já estás livre a $dayLabel?',
      message: block.isMultiDay
          ? 'Tiramos a indisponibilidade só deste dia. Os outros dias ficam '
                'como estão.'
          : 'Tiramos a indisponibilidade deste dia.',
      confirmLabel: 'Sim, estou livre',
    );
    if (confirmed != true || !mounted) return;
    final toast = AppToast.of(context);
    try {
      await ref
          .read(agendaRepositoryProvider)
          .freeDay(
            entryId: block.sourceId,
            seriesDate: block.seriesDate,
            day: _day,
          );
    } catch (err) {
      toast.error(friendlyError(err));
      return;
    }
    if (!mounted) return;
    // Regra T4: sem navegação; aviso → invalidar.
    toast.show('Dia libertado.');
    ref.invalidate(agendaRangeProvider);
  }

  @override
  Widget build(BuildContext context) {
    final ranges = _monthRanges();
    final reads = [
      for (final range in ranges) ref.watch(agendaRangeProvider(range)),
    ];
    for (final range in ranges) {
      ref.listen(agendaRangeProvider(range), (_, next) {
        if (next.hasValue && !next.hasError && !next.isLoading) {
          _loadedAt = DateTime.now();
        }
      });
    }
    final hasError = reads.any((r) => r.hasError);
    final entries = reads.every((r) => r.hasValue)
        ? [for (final r in reads) ...r.value!]
        : null;
    if (_loadedAt == null && entries != null && !hasError) {
      _loadedAt = DateTime.now();
    }

    final serviceTypes =
        ref.watch(serviceTypesProvider).asData?.value ?? const <ServiceType>[];
    final now = DateTime.now();
    final loadedAt = _loadedAt;
    final offline = hasError && entries != null && loadedAt != null
        ? 'Sem rede · dados das ${formatMinutes(loadedAt.hour * 60 + loadedAt.minute)}'
        : null;
    final loading = reads.any((r) => r.isLoading) && entries == null;
    void retry() {
      for (final range in ranges) {
        ref.invalidate(agendaRangeProvider(range));
      }
    }

    final view = _range == AgendaRange.month
        ? _monthView(
            entries: entries,
            now: now,
            serviceTypes: serviceTypes,
            loading: loading,
            offline: offline,
            onRetry: retry,
          )
        : _range == AgendaRange.week
        ? _weekView(
            entries: entries,
            now: now,
            serviceTypes: serviceTypes,
            loading: loading,
            offline: offline,
            onRetry: retry,
          )
        : _dayView(
            entries: entries,
            now: now,
            serviceTypes: serviceTypes,
            loading: loading,
            offline: offline,
            onRetry: retry,
          );
    return AppFadeThroughSwitcher(switchKey: _range, child: view);
  }

  Widget _dayView({
    required List<AgendaEntry>? entries,
    required DateTime now,
    required List<ServiceType> serviceTypes,
    required bool loading,
    required String? offline,
    required VoidCallback onRetry,
  }) {
    final today = DateUtils.dateOnly(now);
    return AgendaDayView(
      dayKey: agendaDayKey(_day),
      dayLabel: agendaDayLabel(_day, now),
      range: AgendaRange.day,
      isToday: _day == today,
      showProposals: _showProposals,
      content: entries == null
          ? null
          : buildAgendaDay(
              day: _day,
              entries: entries,
              now: now,
              showProposals: _showProposals,
              serviceTypes: serviceTypes,
            ),
      loading: loading,
      focusOverlap: _focusOverlap,
      offlineLabel: offline,
      onRetry: onRetry,
      onPreviousDay: () => _goTo(_day.subtract(const Duration(days: 1))),
      onNextDay: () => _goTo(_day.add(const Duration(days: 1))),
      onGoToToday: () => _goTo(now),
      onOpenCalendar: _openCalendar,
      onRangeChanged: _onRangeChanged,
      onShowProposalsChanged: (value) => setState(() => _showProposals = value),
      onRefresh: _refresh,
      onOpenEntry: _openEntry,
      onStartJob: _startJob,
      onChooseTime: _openEntry,
      onWhatsApp: (e) => openWhatsAppOrWarn(context, e.personPhone ?? ''),
      onMap: _openMap,
      onResolveOverlap: _resolveOverlap,
      onSearchWork: () => context.go('/worker/available-jobs'),
      onMarkAvailable: _markAvailable,
    );
  }

  Widget _weekView({
    required List<AgendaEntry>? entries,
    required DateTime now,
    required List<ServiceType> serviceTypes,
    required bool loading,
    required String? offline,
    required VoidCallback onRetry,
  }) {
    final weekStart = agendaWeekStart(_day);
    AgendaWeekContentViewData build(List<AgendaEntry> list) => buildAgendaWeek(
      weekStart: weekStart,
      entries: list,
      now: now,
      showProposals: _showProposals,
      serviceTypes: serviceTypes,
    );
    final content = entries == null ? null : build(entries);
    return AgendaWeekView(
      weekKey: agendaDayKey(weekStart),
      rangeLabel: agendaWeekRangeLabel(weekStart, now),
      isCurrentWeek: weekStart == agendaWeekStart(now),
      showProposals: _showProposals,
      // A carregar, a faixa já mostra os dias, sem pontos.
      days: (content ?? build(const [])).days,
      content: content,
      initialDay: _day,
      loading: loading,
      offlineLabel: offline,
      onRetry: onRetry,
      onPreviousWeek: () => _goToWeek(
        DateTime(weekStart.year, weekStart.month, weekStart.day - 7),
      ),
      onNextWeek: () => _goToWeek(
        DateTime(weekStart.year, weekStart.month, weekStart.day + 7),
      ),
      onGoToCurrentWeek: () => _goTo(now),
      onOpenCalendar: _openCalendar,
      onRangeChanged: _onRangeChanged,
      onShowProposalsChanged: (value) => setState(() => _showProposals = value),
      onRefresh: _refresh,
      onOpenEntry: _openEntry,
      onOpenDay: _openDay,
      onOpenDayAtConflict: (day) => _openDay(day, atConflict: true),
      onResolveOverlap: _resolveOverlap,
      // Só guarda o dia, para o Hoje abrir nele; a vista já o mostra.
      onSelectedDayChanged: (day) => _day = day,
      onSearchWork: () => context.go('/worker/available-jobs'),
    );
  }

  Widget _monthView({
    required List<AgendaEntry>? entries,
    required DateTime now,
    required List<ServiceType> serviceTypes,
    required bool loading,
    required String? offline,
    required VoidCallback onRetry,
  }) {
    AgendaMonthContentViewData build(List<AgendaEntry> list) =>
        buildAgendaMonth(
          selectedDay: _day,
          entries: list,
          now: now,
          showProposals: _showProposals,
          serviceTypes: serviceTypes,
        );
    final content = entries == null ? null : build(entries);
    return AgendaMonthView(
      monthKey: '${_day.year}-${_day.month}',
      monthLabel: agendaMonthLabel(_day),
      isCurrentMonth: _day.year == now.year && _day.month == now.month,
      showProposals: _showProposals,
      // A carregar, a grelha já mostra os dias, sem pontos.
      cells: (content ?? build(const [])).cells,
      selectedDay: _day,
      selected: content?.selected,
      loading: loading,
      offlineLabel: offline,
      onRetry: onRetry,
      onPreviousMonth: () => _goToMonth(DateTime(_day.year, _day.month - 1)),
      onNextMonth: () => _goToMonth(DateTime(_day.year, _day.month + 1)),
      onGoToToday: () => _goTo(now),
      onOpenCalendar: _openCalendar,
      onRangeChanged: _onRangeChanged,
      onShowProposalsChanged: (value) => setState(() => _showProposals = value),
      onRefresh: _refresh,
      onSelectDay: _goTo,
      onOpenDay: _openDay,
      onOpenEntry: _openEntry,
      onResolveOverlap: _resolveOverlap,
    );
  }
}

class _OverlapChoice extends StatelessWidget {
  const _OverlapChoice({
    required this.entries,
    required this.serviceTypes,
    required this.onSelected,
  });

  final List<AgendaEntry> entries;
  final List<ServiceType> serviceTypes;
  final ValueChanged<AgendaEntry> onSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Abre o trabalho para combinar outra hora com o cliente.',
          style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final e in entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              serviceTypes
                      .where((t) => t.id == e.serviceTypeId)
                      .firstOrNull
                      ?.name ??
                  e.title ??
                  'Trabalho',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              [
                if (e.startMinutes != null) formatMinutes(e.startMinutes!),
                if (e.personName != null) e.personName!,
              ].join(' · '),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => onSelected(e),
          ),
      ],
    );
  }
}
