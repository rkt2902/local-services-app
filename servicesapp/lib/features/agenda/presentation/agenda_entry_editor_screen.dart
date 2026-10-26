import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/geocoding_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/app_date_picker.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_time_picker.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/service_icon.dart';
import '../../jobs/application/job_providers.dart';
import '../application/agenda_entry_form.dart';
import '../application/agenda_providers.dart';
import '../data/agenda_calendar_entry.dart';
import '../data/agenda_entry_model.dart';
import 'agenda_day_presenter.dart';
import 'agenda_entry_editor_presenter.dart';
import 'agenda_entry_editor_view_data.dart';
import 'agenda_week_presenter.dart';
import 'widgets/agenda_day_cells.dart';
import 'widgets/agenda_entry_editor_view.dart';
import 'widgets/agenda_view_parts.dart';

/// O que aconteceu no formulário, para a Agenda abrir o dia certo e
/// realçar o cartão (F8B).
enum AgendaEditorOutcome { created, updated, deleted }

class AgendaEditorResult {
  const AgendaEditorResult({
    required this.outcome,
    required this.day,
    required this.entryId,
  });

  final AgendaEditorOutcome outcome;
  final DateTime day;

  /// Série criada ou mudada (a nova, em "Este e os seguintes").
  final String entryId;
}

/// Ecrã "Adicionar à agenda" / "Editar" (rotas `/worker/agenda/new` e
/// `/worker/agenda/:id`), fora do ShellRoute. Guarda o estado do
/// formulário, abre os seletores, avisa das sobreposições e grava em
/// `worker_calendar_entries` (0064). Volta com um [AgendaEditorResult].
class AgendaEntryEditorScreen extends ConsumerStatefulWidget {
  const AgendaEntryEditorScreen({
    super.key,
    this.entryId,
    this.occurrenceDate,
    this.initialDate,
    this.initialType = AgendaFormType.work,
  });

  /// Série a editar; nulo = nova.
  final String? entryId;

  /// Ocorrência tocada na Agenda (`series_date`), ao editar uma série.
  final DateTime? occurrenceDate;

  /// Dia já escolhido quando se abre a partir da Agenda.
  final DateTime? initialDate;
  final AgendaFormType initialType;

  @override
  ConsumerState<AgendaEntryEditorScreen> createState() =>
      _AgendaEntryEditorScreenState();
}

class _AgendaEntryEditorScreenState
    extends ConsumerState<AgendaEntryEditorScreen> {
  static const _successHold = Duration(milliseconds: 900);
  static const _suggestDelay = Duration(milliseconds: 400);

  AgendaEntryForm? _form;
  AgendaEntryForm? _original;
  CalendarEntry? _entry;
  AgendaEditorControllers? _controllers;
  Object? _loadError;

  bool _dirty = false;
  bool _submitting = false;
  String? _success;
  Timer? _successTimer;

  List<AddressSuggestion> _suggestions = const [];
  bool _suggestionsLoading = false;
  Timer? _suggestTimer;
  int _suggestRequest = 0;

  /// Texto posto por uma sugestão: não volta a pesquisar nem limpa as
  /// coordenadas.
  String? _pickedLocation;

  bool get _isEdit => widget.entryId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _load();
    } else {
      final today = DateUtils.dateOnly(DateTime.now());
      _ready(
        AgendaEntryForm.create(
          widget.initialDate ?? today,
          type: widget.initialType,
        ),
      );
    }
  }

  @override
  void dispose() {
    _successTimer?.cancel();
    _suggestTimer?.cancel();
    _controllers?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final (entry, exception) = await ref
          .read(agendaRepositoryProvider)
          .fetchCalendarEntry(
            widget.entryId!,
            occurrenceDate: widget.occurrenceDate,
          );
      if (!mounted) return;
      _entry = entry;
      _ready(
        AgendaEntryForm.fromEntry(
          entry,
          occurrenceDate: widget.occurrenceDate,
          exception: exception,
        ),
      );
      _original = _form;
    } catch (err) {
      if (mounted) setState(() => _loadError = err);
    }
  }

  void _ready(AgendaEntryForm form) {
    final controllers = AgendaEditorControllers(form);
    _pickedLocation = form.locationLat == null ? null : form.location;
    void listen(TextEditingController c, AgendaEntryForm Function(String) f) {
      c.addListener(() {
        final current = _form;
        if (current == null) return;
        final next = f(c.text);
        if (_same(current, next)) return;
        setState(() {
          _form = next;
          _dirty = true;
        });
      });
    }

    listen(controllers.title, (t) => _form!.copyWith(title: t));
    listen(controllers.person, (t) => _form!.copyWith(personName: t));
    listen(controllers.phone, (t) => _form!.copyWith(phone: t));
    listen(controllers.amount, (t) => _form!.copyWith(amount: t));
    listen(controllers.notes, (t) => _form!.copyWith(notes: t));
    listen(controllers.blockNote, (t) => _form!.copyWith(blockNote: t));
    controllers.location.addListener(_onLocationChanged);

    setState(() {
      _form = form;
      _controllers = controllers;
    });
  }

  /// Os ouvintes disparam também ao mudar a seleção; só conta o texto.
  bool _same(AgendaEntryForm a, AgendaEntryForm b) =>
      a.title == b.title &&
      a.personName == b.personName &&
      a.phone == b.phone &&
      a.amount == b.amount &&
      a.notes == b.notes &&
      a.blockNote == b.blockNote;

  void _update(AgendaEntryForm Function(AgendaEntryForm) change) {
    final form = _form;
    if (form == null) return;
    setState(() {
      _form = change(form);
      _dirty = true;
    });
  }

  // ── Morada ────────────────────────────────────────────────────

  void _onLocationChanged() {
    final form = _form;
    final text = _controllers!.location.text;
    if (form == null || text == form.location) return;
    final picked = text == _pickedLocation;
    setState(() {
      _dirty = true;
      _form = form.copyWith(
        location: text,
        locationLat: picked ? form.locationLat : null,
        locationLng: picked ? form.locationLng : null,
      );
    });
    if (!picked) _scheduleSuggestions(text);
  }

  void _scheduleSuggestions(String text) {
    _suggestTimer?.cancel();
    _pickedLocation = null;
    if (text.trim().length < 3) {
      _suggestRequest++;
      if (_suggestions.isNotEmpty || _suggestionsLoading) {
        setState(() {
          _suggestions = const [];
          _suggestionsLoading = false;
        });
      }
      return;
    }
    _suggestTimer = Timer(_suggestDelay, () => _loadSuggestions(text));
  }

  Future<void> _loadSuggestions(String text) async {
    final request = ++_suggestRequest;
    setState(() => _suggestionsLoading = true);
    List<AddressSuggestion> found;
    try {
      found = await GeocodingService.suggestAddresses(text, limit: 4);
    } catch (_) {
      found = const [];
    }
    if (!mounted || request != _suggestRequest) return;
    setState(() {
      _suggestions = found;
      _suggestionsLoading = false;
    });
  }

  void _selectAddress(AddressSuggestion s) {
    _suggestTimer?.cancel();
    _suggestRequest++;
    final text = s.fullText;
    _pickedLocation = text;
    _update((f) => f.copyWith(locationLat: s.lat, locationLng: s.lng));
    setState(() {
      _suggestions = const [];
      _suggestionsLoading = false;
    });
    _controllers!.location.text = text;
    FocusScope.of(context).unfocus();
  }

  // ── Seletores ─────────────────────────────────────────────────

  DateTime get _today => DateUtils.dateOnly(DateTime.now());

  Future<DateTime?> _pickDay(DateTime initial, {DateTime? first}) {
    final today = _today;
    final firstDate = first ?? DateTime(today.year - 1, today.month);
    final lastDate = DateTime(today.year + 2, 12, 31);
    final start = initial.isBefore(firstDate) ? firstDate : initial;
    return showAppDatePicker(
      context: context,
      initialDate: start.isAfter(lastDate) ? lastDate : start,
      firstDate: firstDate,
      lastDate: lastDate,
    );
  }

  Future<int?> _pickTime(int minutes, {String? helpText}) async {
    final picked = await showAppTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      helpText: helpText,
    );
    return picked == null ? null : picked.hour * 60 + picked.minute;
  }

  Future<void> _onPickDate() async {
    final picked = await _pickDay(_form!.date);
    if (picked != null && mounted) _update((f) => f.withDate(picked));
  }

  Future<void> _onPickEndDate() async {
    final form = _form!;
    final initial = form.spanDays > 0
        ? form.lastDay
        : form.date.add(Duration(days: form.isWork ? 1 : 0));
    final picked = await _pickDay(initial, first: form.date);
    if (picked != null && mounted) {
      _update((f) => f.copyWith(endDate: DateUtils.dateOnly(picked)));
    }
  }

  Future<void> _onPickStartTime() async {
    final picked = await _pickTime(_form!.startMinutes);
    if (picked == null || !mounted) return;
    _update((f) {
      if (f.isWork) return f.copyWith(startMinutes: picked);
      // Indisponível: o fim anda com o início, se ficasse antes.
      final length = f.endMinutes - f.startMinutes;
      final end = f.endMinutes > picked
          ? f.endMinutes
          : (picked + (length > 0 ? length : 60)).clamp(0, 24 * 60 - 1);
      return f.copyWith(startMinutes: picked, endMinutes: end);
    });
  }

  Future<void> _onPickEndTime() async {
    final picked = await _pickTime(_form!.endMinutes);
    if (picked != null && mounted) {
      _update((f) => f.copyWith(endMinutes: picked));
    }
  }

  Future<void> _onDurationSelected(AgendaDurationId id) async {
    switch (id.option) {
      case AgendaDurationOption.preset:
        _update(
          (f) => f.copyWith(
            allDay: false,
            multiDay: false,
            durationMinutes: id.minutes,
          ),
        );
      case AgendaDurationOption.allDay:
        _update((f) => f.copyWith(allDay: true, multiDay: false));
      case AgendaDurationOption.multiDay:
        _update(
          (f) => f.copyWith(
            multiDay: true,
            endDate: f.endDate != null && f.endDate!.isAfter(f.date)
                ? f.endDate
                : f.date.add(const Duration(days: 1)),
          ),
        );
      case AgendaDurationOption.custom:
        final picked = await _pickTime(
          _form!.durationMinutes,
          helpText: 'Duração (horas e minutos)',
        );
        if (picked == null || !mounted) return;
        if (picked < AgendaFormLimits.minDuration) return;
        _update(
          (f) => f.copyWith(
            allDay: false,
            multiDay: false,
            durationMinutes: picked,
          ),
        );
    }
  }

  void _onRecurrenceSelected(String value) {
    final recurrence = AgendaRecurrence.fromValue(value);
    _update(
      (f) => f.copyWith(
        recurrence: recurrence,
        recurrenceUntil: recurrence == AgendaRecurrence.none
            ? null
            : f.recurrenceUntil,
      ),
    );
  }

  Future<void> _onPickRecurrenceUntil() async {
    final form = _form!;
    final picked = await _pickDay(
      form.recurrenceUntil ??
          DateTime(form.date.year, form.date.month + 3, form.date.day),
      first: form.date,
    );
    if (picked != null && mounted) {
      _update((f) => f.copyWith(recurrenceUntil: DateUtils.dateOnly(picked)));
    }
  }

  Future<void> _onPickService() async {
    final types =
        ref.read(serviceTypesProvider).asData?.value ?? const <ServiceType>[];
    final picked = await AppSheet.show<_ServiceChoice>(
      context,
      builder: (sheetContext) => _ServicePickerSheet(
        types: types,
        selectedId: _form!.serviceTypeId,
        onSelected: (choice) => Navigator.pop(sheetContext, choice),
        onClose: () => Navigator.pop(sheetContext),
      ),
    );
    if (picked == null || !mounted) return;
    final type = picked.type;
    _update((f) => f.copyWith(serviceTypeId: type?.id));
    // Sem título ainda: o nome do serviço serve de ponto de partida.
    final title = _controllers!.title;
    if (type != null && title.text.trim().isEmpty) title.text = type.name;
  }

  /// "Ver o dia" (F3): o dia numa folha, sem sair do formulário.
  Future<void> _openDayPreview() async {
    final form = _form!;
    final entries = _entries();
    if (entries == null) return;
    final now = DateTime.now();
    final serviceTypes =
        ref.read(serviceTypesProvider).asData?.value ?? const <ServiceType>[];
    final dayEntries =
        agendaEntriesByDay([
          for (final e in entries)
            if (e.sourceId != widget.entryId) e,
        ], showProposals: true)[form.date] ??
        const <AgendaEntry>[];
    final slice = buildAgendaDaySlice(
      day: form.date,
      dayEntries: dayEntries,
      now: now,
      serviceTypes: serviceTypes,
    );
    await AppSheet.show<void>(
      context,
      builder: (sheetContext) => AppSheet(
        title: agendaDayLabel(form.date, now),
        onClose: () => Navigator.pop(sheetContext),
        child: slice.section.isFree
            ? Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  'Nada marcado neste dia.',
                  style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              )
            : Flexible(
                child: SingleChildScrollView(
                  child: AgendaDayItemsList(
                    items: slice.section.items,
                    onOpenEntry: (_) {},
                    onResolveOverlap: (_) {},
                  ),
                ),
              ),
      ),
    );
  }

  // ── Guardar e apagar ──────────────────────────────────────────

  /// Meses lidos para as notas de sobreposição: do primeiro ao último dia
  /// (no máximo 3).
  List<(DateTime, DateTime)> _ranges(AgendaEntryForm form) {
    final ranges = <(DateTime, DateTime)>[];
    var month = DateTime(form.date.year, form.date.month);
    final last = DateTime(form.lastDay.year, form.lastDay.month);
    while (!month.isAfter(last) && ranges.length < 3) {
      ranges.add(agendaMonthRange(month));
      month = DateTime(month.year, month.month + 1);
    }
    return ranges;
  }

  /// Entradas já lidas, ou nulo se alguma ainda falta ou falhou.
  List<AgendaEntry>? _entries() {
    final form = _form;
    if (form == null) return null;
    final reads = [
      for (final r in _ranges(form)) ref.read(agendaRangeProvider(r)),
    ];
    if (!reads.every((r) => r.hasValue)) return null;
    return [for (final r in reads) ...r.value!];
  }

  Future<AgendaSeriesScope?> _askScope({required bool forDelete}) {
    final entry = _entry!;
    final form = _form!;
    final original = _original ?? form;
    final occurrence = widget.occurrenceDate ?? entry.startsOn;
    final data = buildAgendaScope(
      entryTitle: original.isWork
          ? original.title
          : (original.reason ?? AgendaBlockReason.other).title,
      recurrence: entry.recurrence,
      seriesStart: entry.startsOn,
      occurrenceDate: occurrence,
      recurrenceUntil: entry.recurrenceUntil,
      now: DateTime.now(),
      forDelete: forDelete,
      thisDayAllowed: forDelete || form.onlyOccurrenceFieldsChanged(original),
    );
    return AppSheet.show<AgendaSeriesScope>(
      context,
      builder: (sheetContext) => AgendaScopeSheet(
        data: data,
        destructive: forDelete,
        onConfirm: (scope) => Navigator.pop(sheetContext, scope),
      ),
    );
  }

  Future<void> _save() async {
    final form = _form;
    if (form == null || !form.canSave || _submitting) return;
    FocusScope.of(context).unfocus();

    final entries = _entries();
    if (entries != null && form.isWork) {
      final conflict = agendaStrongConflict(
        form: form,
        entries: entries,
        serviceTypes:
            ref.read(serviceTypesProvider).asData?.value ??
            const <ServiceType>[],
        now: DateTime.now(),
        ignoreSourceId: widget.entryId,
      );
      if (conflict != null) {
        final saveAnyway = await AgendaConflictDialog.show(context, conflict);
        if (!mounted) return;
        if (!saveAnyway) {
          // "Mudar a hora": abre logo a hora de início.
          if (!form.allDay && !form.multiDay) await _onPickStartTime();
          return;
        }
      }
    }

    final entry = _entry;
    AgendaSeriesScope? scope;
    if (entry != null && entry.repeats) {
      scope = await _askScope(forDelete: false);
      if (scope == null || !mounted) return;
    }

    final toast = AppToast.of(context);
    setState(() => _submitting = true);
    final AgendaEditorResult result;
    try {
      result = await _write(form, entry, scope);
    } catch (err) {
      if (!mounted) return;
      setState(() => _submitting = false);
      toast.error(friendlyError(err));
      return;
    }
    if (!mounted) return;
    // Só depois de o servidor confirmar (F8A).
    setState(() {
      _submitting = false;
      _success = 'Guardado na agenda';
    });
    _successTimer = Timer(_successHold, () {
      if (mounted) _close(result);
    });
  }

  Future<AgendaEditorResult> _write(
    AgendaEntryForm form,
    CalendarEntry? entry,
    AgendaSeriesScope? scope,
  ) async {
    final repo = ref.read(agendaRepositoryProvider);
    if (entry == null) {
      final id = await repo.createCalendarEntry(form.toRow());
      return AgendaEditorResult(
        outcome: AgendaEditorOutcome.created,
        day: form.date,
        entryId: id,
      );
    }

    var id = entry.id;
    final occurrence = widget.occurrenceDate ?? entry.startsOn;
    final fromStart = !occurrence.isAfter(entry.startsOn);
    switch (scope) {
      case null:
        await repo.updateCalendarEntry(id, form.toRow());
      case AgendaSeriesScope.thisDay:
        await repo.saveException(
          entryId: id,
          occurrenceDate: occurrence,
          values: form.toExceptionRow(occurrence),
        );
      case AgendaSeriesScope.following when !fromStart:
        id = await repo.splitSeries(entryId: id, fromDate: occurrence);
        await repo.deleteException(entryId: id, occurrenceDate: occurrence);
        await repo.updateCalendarEntry(id, form.toRow());
      case AgendaSeriesScope.following || AgendaSeriesScope.all:
        // A série toda anda com a mudança de data desta ocorrência.
        final shift = form.date.difference(occurrence);
        await repo.deleteException(entryId: id, occurrenceDate: occurrence);
        await repo.updateCalendarEntry(
          id,
          form.toRow(startsOn: entry.startsOn.add(shift)),
        );
    }
    return AgendaEditorResult(
      outcome: AgendaEditorOutcome.updated,
      day: form.date,
      entryId: id,
    );
  }

  Future<void> _delete() async {
    final entry = _entry;
    final form = _original ?? _form;
    if (entry == null || form == null || _submitting) return;
    final occurrence = widget.occurrenceDate ?? entry.startsOn;

    AgendaSeriesScope? scope;
    if (entry.repeats) {
      scope = await _askScope(forDelete: true);
      if (scope == null || !mounted) return;
    } else {
      final name = form.isWork
          ? form.title.trim()
          : (form.reason ?? AgendaBlockReason.other).title;
      final confirmed = await AppConfirmDialog.show(
        context,
        icon: Icons.delete_outline_rounded,
        title: 'Apagar da agenda?',
        message: '"$name" sai da tua agenda. Não dá para desfazer.',
        confirmLabel: 'Apagar',
        destructive: true,
      );
      if (confirmed != true || !mounted) return;
    }

    final toast = AppToast.of(context);
    final repo = ref.read(agendaRepositoryProvider);
    setState(() => _submitting = true);
    try {
      switch (scope) {
        case AgendaSeriesScope.thisDay:
          await repo.saveException(
            entryId: entry.id,
            occurrenceDate: occurrence,
            values: AgendaEntryForm.cancelledExceptionRow(),
          );
        case AgendaSeriesScope.following
            when occurrence.isAfter(entry.startsOn):
          await repo.updateCalendarEntry(entry.id, {
            'recurrence_until': agendaDayKey(
              occurrence.subtract(const Duration(days: 1)),
            ),
          });
        case _:
          await repo.deleteCalendarEntry(entry.id);
      }
    } catch (err) {
      if (!mounted) return;
      setState(() => _submitting = false);
      toast.error(friendlyError(err));
      return;
    }
    if (!mounted) return;
    _close(
      AgendaEditorResult(
        outcome: AgendaEditorOutcome.deleted,
        day: occurrence,
        entryId: entry.id,
      ),
    );
  }

  // ── Sair ──────────────────────────────────────────────────────

  void _close([AgendaEditorResult? result]) {
    _dirty = false;
    final router = GoRouter.maybeOf(context);
    if (router != null && router.canPop()) {
      router.pop(result);
    } else if (router != null) {
      router.go('/worker/jobs');
    } else {
      Navigator.of(context).maybePop(result);
    }
  }

  Future<void> _back() async {
    if (!_dirty || _success != null) {
      _close();
      return;
    }
    final leave = await AppConfirmDialog.show(
      context,
      icon: Icons.edit_off_outlined,
      title: 'Sair sem guardar?',
      message: 'O que escreveste nesta entrada perde-se.',
      confirmLabel: 'Sair sem guardar',
      cancelLabel: 'Continuar a editar',
      destructive: true,
    );
    if (leave == true && mounted) _close();
  }

  @override
  Widget build(BuildContext context) {
    final form = _form;
    final controllers = _controllers;
    final Widget body;
    if (form == null || controllers == null) {
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
      final reads = [
        for (final r in _ranges(form)) ref.watch(agendaRangeProvider(r)),
      ];
      final entries = reads.every((r) => r.hasValue)
          ? [for (final r in reads) ...r.value!]
          : null;
      final serviceTypes =
          ref.watch(serviceTypesProvider).asData?.value ??
          const <ServiceType>[];
      body = AgendaEntryEditorView(
        data: buildAgendaEditor(
          form: form,
          isEdit: _isEdit,
          entries: entries,
          serviceTypes: serviceTypes,
          now: DateTime.now(),
          submitting: _submitting,
          ignoreSourceId: widget.entryId,
          suggestions: _suggestions,
          suggestionsLoading: _suggestionsLoading,
        ),
        controllers: controllers,
        successMessage: _success,
        onBack: _back,
        onTypeChanged: (type) => _update((f) => f.switchType(type)),
        onPickService: _onPickService,
        onAddressSelected: _selectAddress,
        onPickDate: _onPickDate,
        onPickStartTime: _onPickStartTime,
        onAllDayChanged: (value) => _update((f) => f.copyWith(allDay: value)),
        onDurationSelected: _onDurationSelected,
        onPickEndDate: _onPickEndDate,
        onOpenDayPreview: _openDayPreview,
        onRecurrenceSelected: _onRecurrenceSelected,
        onPickRecurrenceUntil: _onPickRecurrenceUntil,
        onRecurrenceNoEnd: () =>
            _update((f) => f.copyWith(recurrenceUntil: null)),
        onReasonSelected: (r) => _update((f) => f.copyWith(reason: r)),
        onPickEndTime: _onPickEndTime,
        onSave: _save,
        onDelete: _delete,
      );
    }

    return PopScope(
      canPop: !_dirty || _success != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(child: body),
      ),
    );
  }
}

/// Escolha da folha de serviços: [type] nulo = "Sem serviço".
class _ServiceChoice {
  const _ServiceChoice(this.type);

  final ServiceType? type;
}

/// Lista pesquisável dos serviços da base de dados (`serviceTypesProvider`).
class _ServicePickerSheet extends StatefulWidget {
  const _ServicePickerSheet({
    required this.types,
    required this.selectedId,
    required this.onSelected,
    required this.onClose,
  });

  final List<ServiceType> types;
  final String? selectedId;
  final ValueChanged<_ServiceChoice> onSelected;
  final VoidCallback onClose;

  @override
  State<_ServicePickerSheet> createState() => _ServicePickerSheetState();
}

class _ServicePickerSheetState extends State<_ServicePickerSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final query = _search.text.trim().toLowerCase();
    final shown = [
      for (final t in widget.types)
        if (query.isEmpty ||
            t.name.toLowerCase().contains(query) ||
            t.categoryName.toLowerCase().contains(query))
          t,
    ];
    return AppSheet(
      title: 'Escolher serviço',
      onClose: widget.onClose,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSearchField(
            controller: _search,
            hintText: 'Procurar serviço',
            onChanged: (_) => setState(() {}),
            onClear: () => setState(_search.clear),
          ),
          const SizedBox(height: AppSpacing.xs),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.5,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                if (widget.selectedId != null && query.isEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.close_rounded,
                      color: AppColors.textSecondary,
                    ),
                    title: const Text('Sem serviço'),
                    onTap: () => widget.onSelected(const _ServiceChoice(null)),
                  ),
                for (final t in shown)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      serviceIconFor(t.icon),
                      color: AppColors.primary,
                    ),
                    title: Text(t.name),
                    subtitle: Text(t.categoryName),
                    selected: t.id == widget.selectedId,
                    trailing: t.id == widget.selectedId
                        ? const Icon(
                            Icons.check_rounded,
                            color: AppColors.primary,
                          )
                        : null,
                    onTap: () => widget.onSelected(_ServiceChoice(t)),
                  ),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      widget.types.isEmpty
                          ? 'Não foi possível carregar os serviços.'
                          : 'Nenhum serviço com esse nome.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
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
