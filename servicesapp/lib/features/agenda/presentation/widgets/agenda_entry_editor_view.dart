import 'package:flutter/material.dart';

import '../../../../core/services/geocoding_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion_tokens.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/widgets/address_suggestions_list.dart';
import '../../../../core/widgets/app_filter_chip.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/primary_action_button.dart';
import '../../application/agenda_entry_form.dart';
import '../agenda_entry_editor_view_data.dart';

/// Formulário "Adicionar à agenda" / "Editar" (design A8D, F1 a F8A). Só
/// apresentação: os textos chegam prontos em [data], os campos de texto
/// vivem em [controllers] (o ecrã ouve-os) e o resto sai por callbacks.
/// Sem Scaffold: o ecrã põe-no à volta, com a SafeArea.
///
/// A confirmação de sobreposição (F4), a folha da série (F7) e "Sair sem
/// guardar?" são diálogos e folhas abertos pelo ecrã; aqui ficam as peças
/// ([AgendaConflictDialog], [AgendaScopeSheet]).
class AgendaEntryEditorView extends StatelessWidget {
  const AgendaEntryEditorView({
    super.key,
    required this.data,
    required this.controllers,
    required this.onBack,
    required this.onTypeChanged,
    required this.onPickService,
    required this.onAddressSelected,
    required this.onPickDate,
    required this.onPickStartTime,
    required this.onAllDayChanged,
    required this.onDurationSelected,
    required this.onPickEndDate,
    required this.onOpenDayPreview,
    required this.onRecurrenceSelected,
    required this.onPickRecurrenceUntil,
    required this.onRecurrenceNoEnd,
    required this.onReasonSelected,
    required this.onPickEndTime,
    required this.onSave,
    required this.onDelete,
    this.successMessage,
  });

  final AgendaEditorViewData data;
  final AgendaEditorControllers controllers;

  final VoidCallback onBack;
  final ValueChanged<AgendaFormType> onTypeChanged;
  final VoidCallback onPickService;
  final ValueChanged<AddressSuggestion> onAddressSelected;

  /// Data (trabalho) ou "De" (indisponível).
  final VoidCallback onPickDate;
  final VoidCallback onPickStartTime;
  final ValueChanged<bool> onAllDayChanged;
  final ValueChanged<AgendaDurationId> onDurationSelected;

  /// "Até" de vários dias ou da indisponibilidade.
  final VoidCallback onPickEndDate;

  /// "Ver o dia": folha com o dia, sem sair do formulário.
  final VoidCallback onOpenDayPreview;
  final ValueChanged<String> onRecurrenceSelected;
  final VoidCallback onPickRecurrenceUntil;
  final VoidCallback onRecurrenceNoEnd;
  final ValueChanged<AgendaBlockReason> onReasonSelected;
  final VoidCallback onPickEndTime;
  final VoidCallback onSave;
  final VoidCallback onDelete;

  /// Visto verde depois de o servidor confirmar (F8A); nulo esconde.
  final String? successMessage;

  @override
  Widget build(BuildContext context) {
    final work = data.type == AgendaFormType.work;
    return Stack(
      children: [
        Column(
          children: [
            _TopBar(
              title: data.title,
              onBack: onBack,
              showDelete: data.showDelete,
              onDelete: onDelete,
            ),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (data.showTypeSelector) ...[
                      _TypeSelector(
                        selected: data.type,
                        onChanged: onTypeChanged,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    AppFadeThroughSwitcher(
                      switchKey: data.type,
                      child: work
                          ? _WorkForm(
                              data: data.work,
                              controllers: controllers,
                              onPickService: onPickService,
                              onAddressSelected: onAddressSelected,
                              onPickDate: onPickDate,
                              onPickStartTime: onPickStartTime,
                              onAllDayChanged: onAllDayChanged,
                              onDurationSelected: onDurationSelected,
                              onPickEndDate: onPickEndDate,
                              onOpenDayPreview: onOpenDayPreview,
                              onRecurrenceSelected: onRecurrenceSelected,
                              onPickRecurrenceUntil: onPickRecurrenceUntil,
                              onRecurrenceNoEnd: onRecurrenceNoEnd,
                            )
                          : _UnavailableForm(
                              data: data.unavailable,
                              note: controllers.blockNote,
                              onReasonSelected: onReasonSelected,
                              onPickStartDate: onPickDate,
                              onPickEndDate: onPickEndDate,
                              onAllDayChanged: onAllDayChanged,
                              onPickStartTime: onPickStartTime,
                              onPickEndTime: onPickEndTime,
                              onRecurrenceSelected: onRecurrenceSelected,
                              onPickRecurrenceUntil: onPickRecurrenceUntil,
                              onRecurrenceNoEnd: onRecurrenceNoEnd,
                            ),
                    ),
                  ],
                ),
              ),
            ),
            _SaveFooter(
              label: data.saveLabel,
              helper: data.saveHelper,
              submitting: data.submitting,
              onPressed: data.canSave ? onSave : null,
            ),
          ],
        ),
        if (successMessage != null)
          Positioned.fill(
            child: AppSuccessFeedback(visible: true, message: successMessage!),
          ),
      ],
    );
  }
}

/// Os campos de texto do formulário. Vivem no ecrã, que os ouve e passa o
/// texto para o [AgendaEntryForm]; a vista só os mostra.
class AgendaEditorControllers {
  AgendaEditorControllers([AgendaEntryForm? form])
    : title = TextEditingController(text: form?.title ?? ''),
      person = TextEditingController(text: form?.personName ?? ''),
      phone = TextEditingController(text: form?.phone ?? ''),
      location = TextEditingController(text: form?.location ?? ''),
      amount = TextEditingController(text: form?.amount ?? ''),
      notes = TextEditingController(text: form?.notes ?? ''),
      blockNote = TextEditingController(text: form?.blockNote ?? '');

  final TextEditingController title;
  final TextEditingController person;
  final TextEditingController phone;
  final TextEditingController location;
  final TextEditingController amount;
  final TextEditingController notes;
  final TextEditingController blockNote;

  List<TextEditingController> get all => [
    title,
    person,
    phone,
    location,
    amount,
    notes,
    blockNote,
  ];

  void dispose() {
    for (final c in all) {
      c.dispose();
    }
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.onBack,
    required this.showDelete,
    required this.onDelete,
  });

  final String title;
  final VoidCallback onBack;
  final bool showDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final danger = AppStatusColor.cancelled.foreground;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxs,
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'Voltar',
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleLarge?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (showDelete)
            TextButton.icon(
              onPressed: onDelete,
              style: TextButton.styleFrom(foregroundColor: danger),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Apagar'),
            ),
        ],
      ),
    );
  }
}

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({required this.selected, required this.onChanged});

  final AgendaFormType selected;
  final ValueChanged<AgendaFormType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TypeButton(
            selected: selected == AgendaFormType.work,
            icon: Icons.work_outline_rounded,
            label: 'Trabalho',
            onPressed: () => onChanged(AgendaFormType.work),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _TypeButton(
            selected: selected == AgendaFormType.unavailable,
            icon: Icons.event_busy_outlined,
            label: 'Indisponível',
            onPressed: () => onChanged(AgendaFormType.unavailable),
          ),
        ),
      ],
    );
  }
}

class _TypeButton extends StatelessWidget {
  const _TypeButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = selected ? AppColors.primary : AppColors.textSecondary;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.card),
      side: BorderSide(
        color: selected ? AppColors.primary : AppColors.divider,
        width: selected ? 2 : 1,
      ),
    );
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppMotionDuration.fast,
        decoration: ShapeDecoration(
          color: selected ? AppColors.primaryContainer : AppColors.surface,
          shape: shape,
        ),
        child: Material(
          type: MaterialType.transparency,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              height: AppSizes.buttonHeight + AppSpacing.sm,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        color: selected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Duration _fast(BuildContext context) => MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : AppMotionDuration.fast;

class _WorkForm extends StatelessWidget {
  const _WorkForm({
    required this.data,
    required this.controllers,
    required this.onPickService,
    required this.onAddressSelected,
    required this.onPickDate,
    required this.onPickStartTime,
    required this.onAllDayChanged,
    required this.onDurationSelected,
    required this.onPickEndDate,
    required this.onOpenDayPreview,
    required this.onRecurrenceSelected,
    required this.onPickRecurrenceUntil,
    required this.onRecurrenceNoEnd,
  });

  final AgendaWorkFormViewData data;
  final AgendaEditorControllers controllers;
  final VoidCallback onPickService;
  final ValueChanged<AddressSuggestion> onAddressSelected;
  final VoidCallback onPickDate;
  final VoidCallback onPickStartTime;
  final ValueChanged<bool> onAllDayChanged;
  final ValueChanged<AgendaDurationId> onDurationSelected;
  final VoidCallback onPickEndDate;
  final VoidCallback onOpenDayPreview;
  final ValueChanged<String> onRecurrenceSelected;
  final VoidCallback onPickRecurrenceUntil;
  final VoidCallback onRecurrenceNoEnd;

  @override
  Widget build(BuildContext context) {
    final warning = data.warning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          title: 'O quê',
          children: [
            AppTextField(
              controller: controllers.title,
              label: 'Título',
              maxLength: AgendaFormLimits.titleMax,
            ),
            _PickerField(
              label: 'Serviço · opcional',
              value: data.serviceLabel ?? 'Escolher serviço',
              placeholder: data.serviceLabel == null,
              icon: data.serviceIcon ?? Icons.search_rounded,
              onPressed: onPickService,
            ),
          ],
        ),
        _Section(
          title: 'Quem',
          optional: true,
          children: [
            AppTextField(
              controller: controllers.person,
              label: 'Nome do cliente',
              maxLength: AgendaFormLimits.personMax,
            ),
            AppTextField(
              controller: controllers.phone,
              label: 'Telefone',
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
            ),
            const _InfoLine(
              icon: Icons.lock_outline_rounded,
              label: 'Só para abrires o WhatsApp. Só tu vês estes dados.',
            ),
          ],
        ),
        _Section(
          title: 'Onde',
          optional: true,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  controller: controllers.location,
                  label: 'Morada ou zona',
                  maxLength: AgendaFormLimits.locationMax,
                ),
                AddressSuggestionsList(
                  suggestions: data.suggestions,
                  loading: data.suggestionsLoading,
                  onSelected: onAddressSelected,
                ),
              ],
            ),
          ],
        ),
        _Section(
          title: 'Quando',
          children: [
            _PickerField(
              label: 'Data',
              value: data.dateLabel,
              icon: Icons.calendar_today_outlined,
              onPressed: onPickDate,
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: AnimatedOpacity(
                    duration: _fast(context),
                    opacity: data.allDay ? 0.45 : 1,
                    child: _PickerField(
                      label: 'Hora de início',
                      value: data.allDay ? 'Dia todo' : data.startTimeLabel,
                      icon: Icons.schedule_rounded,
                      onPressed: data.allDay ? null : onPickStartTime,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _ToggleField(
                    label: 'Dia todo',
                    value: data.allDay,
                    onChanged: onAllDayChanged,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Label('Duração'),
                const SizedBox(height: AppSpacing.xs),
                _Choices(
                  choices: data.durationChoices,
                  onPressed: onDurationSelected,
                ),
              ],
            ),
            if (data.timeSummary != null)
              _InfoLine(
                icon: Icons.schedule_rounded,
                label: data.timeSummary!,
                strong: true,
              ),
            _Reveal(
              visible: data.multiDay,
              child: _PickerField(
                label: 'Até',
                value: data.endDateLabel,
                icon: Icons.event_outlined,
                onPressed: onPickEndDate,
              ),
            ),
            AppFadeThroughSwitcher(
              switchKey: warning?.message ?? 'sem-aviso',
              duration: const Duration(milliseconds: 150),
              child: warning == null
                  ? const SizedBox(width: double.infinity)
                  : _Warning(data: warning, onAction: onOpenDayPreview),
            ),
          ],
        ),
        _Recurrence(
          data: data.recurrence,
          onSelected: onRecurrenceSelected,
          onPickUntil: onPickRecurrenceUntil,
          onNoEnd: onRecurrenceNoEnd,
        ),
        _Section(
          title: 'Extra',
          optional: true,
          last: true,
          children: [
            AppTextField(
              controller: controllers.amount,
              label: 'Valor combinado',
              prefixText: '€ ',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const _InfoLine(
              icon: Icons.lock_outline_rounded,
              label: 'Só tu vês este valor.',
            ),
            AppTextField(
              controller: controllers.notes,
              label: 'Notas',
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              minLines: 3,
              maxLines: 5,
              maxLength: AgendaFormLimits.notesMax,
            ),
          ],
        ),
      ],
    );
  }
}

class _UnavailableForm extends StatelessWidget {
  const _UnavailableForm({
    required this.data,
    required this.note,
    required this.onReasonSelected,
    required this.onPickStartDate,
    required this.onPickEndDate,
    required this.onAllDayChanged,
    required this.onPickStartTime,
    required this.onPickEndTime,
    required this.onRecurrenceSelected,
    required this.onPickRecurrenceUntil,
    required this.onRecurrenceNoEnd,
  });

  final AgendaUnavailableFormViewData data;
  final TextEditingController note;
  final ValueChanged<AgendaBlockReason> onReasonSelected;
  final VoidCallback onPickStartDate;
  final VoidCallback onPickEndDate;
  final ValueChanged<bool> onAllDayChanged;
  final VoidCallback onPickStartTime;
  final VoidCallback onPickEndTime;
  final ValueChanged<String> onRecurrenceSelected;
  final VoidCallback onPickRecurrenceUntil;
  final VoidCallback onRecurrenceNoEnd;

  @override
  Widget build(BuildContext context) {
    final warning = data.warning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          title: 'Motivo',
          children: [
            _Choices(
              choices: data.reasons,
              showIcons: true,
              onPressed: onReasonSelected,
            ),
            AppTextField(
              controller: note,
              label: 'Nota · opcional',
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              minLines: 2,
              maxLines: 4,
              maxLength: AgendaFormLimits.notesMax,
            ),
          ],
        ),
        _Section(
          title: 'Quando',
          children: [
            Row(
              children: [
                Expanded(
                  child: _PickerField(
                    label: 'De',
                    value: data.startDateLabel,
                    icon: Icons.calendar_today_outlined,
                    onPressed: onPickStartDate,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _PickerField(
                    label: 'Até',
                    value: data.endDateLabel,
                    icon: Icons.event_outlined,
                    onPressed: onPickEndDate,
                  ),
                ),
              ],
            ),
            _ToggleField(
              label: 'Dia todo',
              value: data.allDay,
              onChanged: onAllDayChanged,
            ),
            _Reveal(
              visible: !data.allDay,
              child: Row(
                children: [
                  Expanded(
                    child: _PickerField(
                      label: 'Hora de início',
                      value: data.startTimeLabel,
                      icon: Icons.schedule_rounded,
                      onPressed: onPickStartTime,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _PickerField(
                      label: 'Hora de fim',
                      value: data.endTimeLabel,
                      icon: Icons.schedule_rounded,
                      onPressed: onPickEndTime,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        _Recurrence(
          data: data.recurrence,
          onSelected: onRecurrenceSelected,
          onPickUntil: onPickRecurrenceUntil,
          onNoEnd: onRecurrenceNoEnd,
        ),
        _NeutralInfo(label: data.info),
        if (warning != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _Warning(data: warning),
        ],
      ],
    );
  }
}

class _Recurrence extends StatelessWidget {
  const _Recurrence({
    required this.data,
    required this.onSelected,
    required this.onPickUntil,
    required this.onNoEnd,
  });

  final AgendaRecurrenceViewData data;
  final ValueChanged<String> onSelected;
  final VoidCallback onPickUntil;
  final VoidCallback onNoEnd;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Repetir',
      children: [
        _Choices(choices: data.choices, onPressed: onSelected),
        _Reveal(
          visible: data.showUntil,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: _PickerField(
                      label: 'Até',
                      value: data.untilLabel,
                      placeholder: data.noEnd,
                      icon: Icons.event_outlined,
                      onPressed: onPickUntil,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    height: AppSizes.buttonHeight,
                    child: Center(
                      child: AppFilterChip(
                        label: 'Sem fim',
                        selected: data.noEnd,
                        showCheckmark: data.noEnd,
                        onPressed: onNoEnd,
                      ),
                    ),
                  ),
                ],
              ),
              if (data.summary != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _InfoLine(
                  icon: Icons.repeat_rounded,
                  label: data.summary!,
                  strong: true,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Bloco com o título em maiúsculas ("O QUÊ", "QUEM · opcional") e os
/// campos espaçados por igual.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.optional = false,
    this.last = false,
  });

  final String title;
  final List<Widget> children;
  final bool optional;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              text: title.toUpperCase(),
              style: textTheme.labelMedium?.copyWith(
                color: AppColors.textStrong,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
              ),
              children: [
                if (optional)
                  TextSpan(
                    text: ' · opcional',
                    style: textTheme.labelMedium?.copyWith(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// Campo que abre um seletor (data, hora, serviço).
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onPressed,
    this.placeholder = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onPressed;

  /// Valor por escolher ("Escolher serviço"): texto mais claro.
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.input),
      side: const BorderSide(color: AppColors.divider),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Label(label),
        const SizedBox(height: AppSpacing.xxs),
        Material(
          color: AppColors.surface,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              height: AppSizes.buttonHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: AppSizes.infoRowIcon,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          color: placeholder
                              ? AppColors.textSecondary
                              : AppColors.textPrimary,
                          fontWeight: placeholder
                              ? FontWeight.w400
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                    if (onPressed != null)
                      const Icon(
                        Icons.expand_more_rounded,
                        color: AppColors.textSecondary,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ToggleField extends StatelessWidget {
  const _ToggleField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSizes.buttonHeight,
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _Choices<T> extends StatelessWidget {
  const _Choices({
    required this.choices,
    required this.onPressed,
    this.showIcons = false,
  });

  final List<AgendaChoiceViewData<T>> choices;
  final ValueChanged<T> onPressed;
  final bool showIcons;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final choice in choices)
          AppFilterChip(
            label: choice.label,
            selected: choice.selected,
            leadingIcon: showIcons ? choice.icon : null,
            showCheckmark: choice.selected && !showIcons,
            onPressed: () => onPressed(choice.id),
          ),
      ],
    );
  }
}

/// Campo que aparece e desaparece a deslizar (200 ms, nota 9).
class _Reveal extends StatelessWidget {
  const _Reveal({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: _fast(context),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: visible ? child : const SizedBox(width: double.infinity),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    this.strong = false,
  });

  final IconData icon;
  final String label;

  /// Resumo (horas, repetição): texto escuro e a negrito.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: AppSizes.inlineIcon, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: strong ? AppColors.textPrimary : AppColors.textSecondary,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

class _NeutralInfo extends StatelessWidget {
  const _NeutralInfo({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tone = AppStatusColor.neutral;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.visibility_outlined,
            size: AppSizes.infoRowIcon,
            color: tone.foreground,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Nota de sobreposição: azul (leve) ou âmbar (forte). Nunca bloqueia.
class _Warning extends StatelessWidget {
  const _Warning({required this.data, this.onAction});

  final AgendaInlineWarningViewData data;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final strong = data.tone == AgendaWarningTone.waiting;
    final tone = strong ? AppStatusColor.waiting : AppStatusColor.info;
    final action = data.actionLabel;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            strong ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
            size: AppSizes.infoRowIcon,
            color: tone.foreground,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              data.message,
              style: textTheme.bodySmall?.copyWith(
                color: strong ? tone.foreground : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (action != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: tone.foreground,
                visualDensity: VisualDensity.compact,
                textStyle: textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: Text(action),
            ),
        ],
      ),
    );
  }
}

class _SaveFooter extends StatelessWidget {
  const _SaveFooter({
    required this.label,
    required this.helper,
    required this.submitting,
    required this.onPressed,
  });

  final String label;
  final String? helper;
  final bool submitting;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (helper != null) ...[
            Text(
              helper!,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          PrimaryActionButton(
            label: submitting ? 'A guardar…' : label,
            icon: Icons.check_rounded,
            isLoading: submitting,
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}

/// Esqueleto enquanto se lê a entrada a editar.
class AgendaEditorSkeleton extends StatelessWidget {
  const AgendaEditorSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget block(double height) => AppSkeletonShimmer(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppColors.divider,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        block(AppSizes.buttonHeight),
        const SizedBox(height: AppSpacing.lg),
        block(AppSizes.buttonHeight * 2),
        const SizedBox(height: AppSpacing.lg),
        block(AppSizes.buttonHeight * 3),
        const SizedBox(height: AppSpacing.lg),
        block(AppSizes.buttonHeight * 2),
      ],
    );
  }
}

/// Confirmação com as horas a cruzar (F4): "Mudar a hora" é a ação
/// principal; tocar fora faz o mesmo. Devolve `true` para guardar.
class AgendaConflictDialog extends StatelessWidget {
  const AgendaConflictDialog({
    super.key,
    required this.data,
    required this.onChangeTime,
    required this.onSaveAnyway,
  });

  final AgendaConflictDialogData data;
  final VoidCallback onChangeTime;
  final VoidCallback onSaveAnyway;

  static Future<bool> show(
    BuildContext context,
    AgendaConflictDialogData data,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AgendaConflictDialog(
        data: data,
        onChangeTime: () => Navigator.pop(dialogContext, false),
        onSaveAnyway: () => Navigator.pop(dialogContext, true),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tone = AppStatusColor.waiting;
    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.dialogMaxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppStaggeredEntrance(
                index: 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: AppSizes.dialogIconBox,
                    height: AppSizes.dialogIconBox,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tone.background,
                      borderRadius: BorderRadius.circular(AppRadius.input),
                    ),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: tone.foreground,
                      size: AppSizes.dialogIcon,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppStaggeredEntrance(
                index: 1,
                child: Text(
                  data.title,
                  style: textTheme.titleLarge?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppStaggeredEntrance(index: 2, child: _ConflictEntry(data: data)),
              const SizedBox(height: AppSpacing.sm),
              AppStaggeredEntrance(
                index: 3,
                child: Text(
                  data.summary,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppStaggeredEntrance(
                index: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PrimaryActionButton(
                      label: 'Mudar a hora',
                      icon: Icons.schedule_rounded,
                      onPressed: onChangeTime,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    OutlinedButton(
                      onPressed: onSaveAnyway,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(
                          AppSizes.compactButtonHeight,
                        ),
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.divider),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.input),
                        ),
                        textStyle: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: const Text('Guardar mesmo assim'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConflictEntry extends StatelessWidget {
  const _ConflictEntry({required this.data});

  final AgendaConflictDialogData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final start = data.entryStart;
    final end = data.entryEnd;
    final meta = data.entryMeta;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.divider),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ColoredBox(
              color: AppColors.primary,
              child: SizedBox(width: AppSpacing.xxs),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Row(
                  children: [
                    if (start != null) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            start,
                            style: textTheme.titleMedium?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (end != null)
                            Text(
                              end,
                              style: textTheme.labelSmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.entryTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (meta != null)
                            Text(
                              meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Conteúdo da folha "Guardar a mudança em…" / "Apagar…" (F7). Guarda a
/// escolha e devolve-a em [onConfirm].
class AgendaScopeSheet extends StatefulWidget {
  const AgendaScopeSheet({
    super.key,
    required this.data,
    required this.onConfirm,
    this.destructive = false,
    this.onCancel,
  });

  final AgendaScopeViewData data;
  final ValueChanged<AgendaSeriesScope> onConfirm;
  final bool destructive;

  /// Com ele, a folha do detalhe (D3): um toque numa opção escolhe logo e
  /// o botão de baixo é [AgendaScopeViewData.actionLabel] ("Cancelar").
  final VoidCallback? onCancel;

  @override
  State<AgendaScopeSheet> createState() => _AgendaScopeSheetState();
}

class _AgendaScopeSheetState extends State<AgendaScopeSheet> {
  late AgendaSeriesScope _selected = widget.data.options
      .firstWhere((o) => o.selected, orElse: () => widget.data.options.last)
      .id;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: AppSizes.sheetHandleWidth,
                height: AppSizes.sheetHandleHeight,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              widget.data.title,
              style: textTheme.titleLarge?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              widget.data.summary,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final (i, option) in widget.data.options.indexed) ...[
              AppStaggeredEntrance(
                index: i,
                child: _ScopeOption(
                  data: option,
                  selected: option.id == _selected,
                  onPressed: !option.enabled
                      ? null
                      : widget.onCancel != null
                      ? () => widget.onConfirm(option.id)
                      : () => setState(() => _selected = option.id),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            const SizedBox(height: AppSpacing.xs),
            if (widget.onCancel != null)
              FilledButton(
                onPressed: widget.onCancel,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
                  backgroundColor: AppColors.agendaNeutralSurface,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.input),
                  ),
                  textStyle: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(widget.data.actionLabel),
              )
            else if (widget.destructive)
              FilledButton(
                onPressed: () => widget.onConfirm(_selected),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
                  backgroundColor: AppStatusColor.cancelled.foreground,
                  foregroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.input),
                  ),
                  textStyle: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(widget.data.actionLabel),
              )
            else
              PrimaryActionButton(
                label: widget.data.actionLabel,
                onPressed: () => widget.onConfirm(_selected),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScopeOption extends StatelessWidget {
  const _ScopeOption({
    required this.data,
    required this.selected,
    required this.onPressed,
  });

  final AgendaChoiceViewData<AgendaSeriesScope> data;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final enabled = onPressed != null;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.input),
      side: BorderSide(
        color: selected ? AppColors.primary : AppColors.divider,
        width: selected ? 2 : 1,
      ),
    );
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Semantics(
        selected: selected,
        enabled: enabled,
        child: Material(
          color: selected ? AppColors.primaryContainer : AppColors.surface,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                children: [
                  Icon(
                    data.icon ??
                        (selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded),
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.label,
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (data.subtitle != null)
                          Text(
                            data.subtitle!,
                            style: textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Guardado na agenda · Desfazer" no topo da Agenda, depois de voltar
/// (F8B). Sem [onUndo], só o texto.
class AgendaSavedBanner extends StatelessWidget {
  const AgendaSavedBanner({super.key, required this.message, this.onUndo});

  final String message;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tone = AppStatusColor.success;
    return AppStaggeredEntrance(
      index: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.xxs,
          AppSpacing.xxs,
          AppSpacing.xxs,
        ),
        constraints: const BoxConstraints(minHeight: AppSizes.linkButtonHeight),
        decoration: BoxDecoration(
          color: tone.background,
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_rounded,
              size: AppSizes.infoRowIcon,
              color: tone.foreground,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                message,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (onUndo != null)
              TextButton(
                onPressed: onUndo,
                style: TextButton.styleFrom(foregroundColor: tone.foreground),
                child: const Text('Desfazer'),
              ),
          ],
        ),
      ),
    );
  }
}
