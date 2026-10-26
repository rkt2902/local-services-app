import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/utils/phone_utils.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_toast.dart';
import '../../jobs/application/job_providers.dart';
import '../application/agenda_entry_actions.dart';
import '../application/agenda_entry_form.dart';
import '../application/agenda_providers.dart';
import '../data/agenda_calendar_entry.dart';
import 'agenda_day_presenter.dart';
import 'agenda_entry_detail_presenter.dart';
import 'agenda_entry_detail_view_data.dart';
import 'agenda_entry_editor_screen.dart';
import 'agenda_open_map.dart';
import 'widgets/agenda_entry_detail_view.dart';
import 'widgets/agenda_entry_editor_view.dart';
import 'widgets/agenda_view_parts.dart';

/// Detalhe de um trabalho de fora da app ou de uma indisponibilidade (rota
/// `/worker/agenda/:id?date=`), fora do ShellRoute. Lê a série e a exceção
/// do dia, grava feito, cancelado e reposto aqui mesmo, e volta à Agenda
/// com um [AgendaEditorResult] ao apagar, editar ou "Ver o dia".
class AgendaEntryDetailScreen extends ConsumerStatefulWidget {
  const AgendaEntryDetailScreen({
    super.key,
    required this.entryId,
    this.occurrenceDate,
  });

  final String entryId;

  /// Ocorrência tocada na Agenda (`series_date`).
  final DateTime? occurrenceDate;

  @override
  ConsumerState<AgendaEntryDetailScreen> createState() =>
      _AgendaEntryDetailScreenState();
}

class _AgendaEntryDetailScreenState
    extends ConsumerState<AgendaEntryDetailScreen> {
  static const _successHold = Duration(milliseconds: 900);
  static const _bannerFor = Duration(seconds: 6);

  /// Muda em "Este e os seguintes" (a série nova fica com este dia).
  late String _entryId = widget.entryId;
  CalendarEntry? _entry;
  CalendarException? _exception;
  Object? _loadError;

  bool _submitting = false;
  String? _success;
  String? _banner;
  Timer? _successTimer;
  Timer? _bannerTimer;

  DateTime get _occurrence => widget.occurrenceDate ?? _entry!.startsOn;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _successTimer?.cancel();
    _bannerTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final (entry, exception) = await ref
          .read(agendaRepositoryProvider)
          .fetchCalendarEntry(_entryId, occurrenceDate: widget.occurrenceDate);
      if (!mounted) return;
      setState(() {
        _entry = entry;
        _exception = exception;
      });
    } catch (err) {
      if (mounted) setState(() => _loadError = err);
    }
  }

  // ── Ações ─────────────────────────────────────────────────────

  /// Grava, volta a ler e só depois avisa (regra T4: sem navegação; aviso →
  /// invalidar). Devolve `false` se falhou (o erro já foi mostrado).
  Future<bool> _run(Future<void> Function() write, {String? toast}) async {
    if (_submitting) return false;
    final toaster = AppToast.of(context);
    setState(() => _submitting = true);
    try {
      await write();
      await _load();
    } catch (err) {
      if (mounted) {
        setState(() => _submitting = false);
        toaster.error(friendlyError(err));
      }
      return false;
    }
    if (!mounted) return false;
    setState(() => _submitting = false);
    if (toast != null) toaster.show(toast);
    ref.invalidate(agendaRangeProvider);
    return true;
  }

  Future<void> _onPrimary(AgendaDetailPrimary kind) async {
    final entry = _entry;
    if (entry == null) return;
    final repo = ref.read(agendaRepositoryProvider);
    switch (kind) {
      case AgendaDetailPrimary.markDone:
        final ok = await _run(
          () => markCalendarOccurrenceDone(
            repo,
            entry: entry,
            occurrence: _occurrence,
          ),
        );
        if (!ok || !mounted) return;
        // Visto breve e depois a faixa com "Desfazer" (D4).
        _bannerTimer?.cancel();
        setState(() => _success = 'Feito');
        _successTimer?.cancel();
        _successTimer = Timer(_successHold, () {
          if (!mounted) return;
          setState(() {
            _success = null;
            _banner = 'Marcado como feito';
          });
          _bannerTimer = Timer(_bannerFor, () {
            if (mounted) setState(() => _banner = null);
          });
        });
      case AgendaDetailPrimary.undoDone:
        await _undoDone();
      case AgendaDetailPrimary.restore:
        final exception = _exception;
        await _run(
          () => restoreCalendarOccurrence(
            repo,
            entry: entry,
            exception: exception,
            occurrence: _occurrence,
          ),
          toast: 'Trabalho reposto.',
        );
    }
  }

  Future<void> _undoDone() async {
    final entry = _entry;
    if (entry == null) return;
    _bannerTimer?.cancel();
    setState(() => _banner = null);
    final exception = _exception;
    await _run(
      () => undoCalendarOccurrenceDone(
        ref.read(agendaRepositoryProvider),
        entry: entry,
        exception: exception,
        occurrence: _occurrence,
      ),
      toast: 'Voltou a marcado.',
    );
  }

  /// Folha "Este trabalho repete-se" (D3): um toque escolhe.
  Future<AgendaSeriesScope?> _askScope(AgendaDetailScopeAction action) {
    final data = buildAgendaDetailScope(
      entry: _entry!,
      occurrence: _occurrence,
      action: action,
      now: DateTime.now(),
    );
    return AppSheet.show<AgendaSeriesScope>(
      context,
      builder: (sheetContext) => AgendaScopeSheet(
        data: data,
        onConfirm: (scope) => Navigator.pop(sheetContext, scope),
        onCancel: () => Navigator.pop(sheetContext),
      ),
    );
  }

  Future<void> _cancel() async {
    final entry = _entry;
    if (entry == null || _submitting) return;
    AgendaSeriesScope? scope;
    if (entry.repeats) {
      scope = await _askScope(AgendaDetailScopeAction.cancel);
      if (scope == null || !mounted) return;
    }
    final text = agendaCancelConfirm(
      entry: entry,
      exception: _exception,
      occurrence: _occurrence,
      scope: scope,
      now: DateTime.now(),
    );
    final confirmed = await AppConfirmDialog.show(
      context,
      icon: Icons.event_busy_outlined,
      title: text.title,
      message: text.message,
      confirmLabel: 'Cancelar trabalho',
      cancelLabel: 'Não cancelar',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      _entryId = await cancelCalendarOccurrences(
        ref.read(agendaRepositoryProvider),
        entry: entry,
        occurrence: _occurrence,
        scope: scope,
      );
    }, toast: 'Trabalho cancelado. Fica na agenda, riscado.');
  }

  Future<void> _delete() async {
    final entry = _entry;
    if (entry == null || _submitting) return;
    AgendaSeriesScope? scope;
    if (entry.repeats) {
      scope = await _askScope(AgendaDetailScopeAction.delete);
      if (scope == null || !mounted) return;
    }
    final text = agendaDeleteConfirm(
      entry: entry,
      exception: _exception,
      occurrence: _occurrence,
      scope: scope,
      now: DateTime.now(),
    );
    final confirmed = await AppConfirmDialog.show(
      context,
      icon: Icons.delete_outline_rounded,
      title: text.title,
      message: text.message,
      confirmLabel: 'Apagar',
      cancelLabel: 'Não apagar',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    final toast = AppToast.of(context);
    setState(() => _submitting = true);
    try {
      await deleteCalendarOccurrences(
        ref.read(agendaRepositoryProvider),
        entry: entry,
        occurrence: _occurrence,
        scope: scope,
      );
    } catch (err) {
      if (!mounted) return;
      setState(() => _submitting = false);
      toast.error(friendlyError(err));
      return;
    }
    if (!mounted) return;
    // A Agenda mostra o aviso e volta a ler (regra T4).
    _close(
      AgendaEditorResult(
        outcome: AgendaEditorOutcome.deleted,
        day: _occurrence,
        entryId: entry.id,
      ),
    );
  }

  /// O formulário pergunta os dias ao guardar (sabe o que mudou); ao
  /// voltar, a Agenda abre o dia com o cartão realçado.
  Future<void> _edit() async {
    if (_entry == null || _submitting) return;
    final result = await context.push<AgendaEditorResult>(
      '/worker/agenda/$_entryId/edit?date=${agendaDayKey(_occurrence)}',
    );
    if (result != null && mounted) _close(result);
  }

  void _viewDay() {
    final entry = _entry;
    if (entry == null) return;
    final form = AgendaEntryForm.fromEntry(
      entry,
      occurrenceDate: _occurrence,
      exception: _exception,
    );
    _close(
      AgendaEditorResult(
        outcome: AgendaEditorOutcome.viewDay,
        day: form.date,
        entryId: entry.id,
      ),
    );
  }

  void _close([AgendaEditorResult? result]) {
    final router = GoRouter.maybeOf(context);
    if (router != null && router.canPop()) {
      router.pop(result);
    } else if (router != null) {
      router.go('/worker/jobs');
    } else {
      Navigator.of(context).maybePop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    final Widget body;
    if (entry == null) {
      body = Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: _close,
              tooltip: 'Voltar',
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: _loadError == null
                ? const AgendaEditorSkeleton()
                : AgendaLoadError(
                    message: friendlyError(_loadError!),
                    onRetry: _load,
                  ),
          ),
        ],
      );
    } else {
      final form = AgendaEntryForm.fromEntry(
        entry,
        occurrenceDate: _occurrence,
        exception: _exception,
      );
      final month = ref.watch(agendaRangeProvider(agendaMonthRange(form.date)));
      final serviceTypes =
          ref.watch(serviceTypesProvider).asData?.value ??
          const <ServiceType>[];
      body = AgendaEntryDetailView(
        data: buildAgendaEntryDetail(
          entry: entry,
          exception: _exception,
          occurrence: _occurrence,
          entries: month.asData?.value,
          serviceTypes: serviceTypes,
          now: DateTime.now(),
          submitting: _submitting,
        ),
        successMessage: _success,
        bannerMessage: _banner,
        onUndoBanner: _undoDone,
        onBack: _close,
        onEdit: _edit,
        onDelete: _delete,
        onPrimary: _onPrimary,
        onCancel: _cancel,
        onWhatsApp: () => openWhatsAppOrWarn(context, entry.personPhone ?? ''),
        onOpenMap: () => openAgendaPlace(
          lat: entry.locationLat,
          lng: entry.locationLng,
          label: entry.locationLabel,
        ),
        onViewDay: _viewDay,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: body),
    );
  }
}
