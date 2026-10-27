import 'package:flutter/widgets.dart';

import '../../../core/services/geocoding_service.dart';
import '../application/agenda_entry_form.dart';

/// Dados já prontos do formulário "Adicionar à agenda" (design A8D, F1 a
/// F7). Calculados por `agenda_entry_editor_presenter.dart`; a vista não
/// formata datas nem decide.

/// Uma escolha em chips ou em lista (duração, repetição, motivo, âmbito).
class AgendaChoiceViewData<T> {
  const AgendaChoiceViewData({
    required this.id,
    required this.label,
    required this.selected,
    this.icon,
    this.subtitle,
    this.enabled = true,
  });

  final T id;
  final String label;
  final bool selected;
  final IconData? icon;
  final String? subtitle;
  final bool enabled;
}

/// [success] só fora do formulário (A10): "Estás livre neste horário".
enum AgendaWarningTone { success, info, waiting }

/// Nota por baixo da data e da hora (F2 leve, F3 forte). Nunca bloqueia.
class AgendaInlineWarningViewData {
  const AgendaInlineWarningViewData({
    required this.tone,
    required this.message,
    this.actionLabel,
  });

  final AgendaWarningTone tone;
  final String message;

  /// "Ver o dia"; nulo sem ação.
  final String? actionLabel;
}

/// Escolha da duração: as fixas, "Dia todo", "Vários dias" e "Outra".
enum AgendaDurationOption { preset, allDay, multiDay, custom }

class AgendaDurationId {
  const AgendaDurationId(this.option, [this.minutes]);

  final AgendaDurationOption option;
  final int? minutes;

  @override
  bool operator ==(Object other) =>
      other is AgendaDurationId &&
      other.option == option &&
      other.minutes == minutes;

  @override
  int get hashCode => Object.hash(option, minutes);
}

class AgendaRecurrenceViewData {
  const AgendaRecurrenceViewData({
    required this.choices,
    required this.showUntil,
    required this.untilLabel,
    required this.noEnd,
    this.summary,
  });

  final List<AgendaChoiceViewData<String>> choices;
  final bool showUntil;

  /// "30 mar 2027", ou "Sem fim".
  final String untilLabel;
  final bool noEnd;

  /// "Todas as terças, até 30 mar 2027".
  final String? summary;
}

class AgendaWorkFormViewData {
  const AgendaWorkFormViewData({
    required this.serviceLabel,
    required this.serviceIcon,
    required this.suggestions,
    required this.suggestionsLoading,
    required this.dateLabel,
    required this.startTimeLabel,
    required this.allDay,
    required this.durationChoices,
    required this.timeSummary,
    required this.multiDay,
    required this.endDateLabel,
    required this.recurrence,
    this.warning,
  });

  /// Nulo = "Escolher serviço".
  final String? serviceLabel;
  final IconData? serviceIcon;

  /// Até 4 moradas enquanto se escreve.
  final List<AddressSuggestion> suggestions;
  final bool suggestionsLoading;

  final String dateLabel;
  final String startTimeLabel;
  final bool allDay;
  final List<AgendaChoiceViewData<AgendaDurationId>> durationChoices;

  /// "Das 16:30 às 17:30".
  final String? timeSummary;
  final bool multiDay;
  final String endDateLabel;
  final AgendaInlineWarningViewData? warning;
  final AgendaRecurrenceViewData recurrence;
}

class AgendaUnavailableFormViewData {
  const AgendaUnavailableFormViewData({
    required this.reasons,
    required this.startDateLabel,
    required this.endDateLabel,
    required this.allDay,
    required this.startTimeLabel,
    required this.endTimeLabel,
    required this.recurrence,
    required this.info,
    this.warning,
  });

  final List<AgendaChoiceViewData<AgendaBlockReason>> reasons;
  final String startDateLabel;
  final String endDateLabel;
  final bool allDay;
  final String startTimeLabel;
  final String endTimeLabel;
  final AgendaRecurrenceViewData recurrence;

  /// "Só aparece na tua agenda…".
  final String info;

  /// Trabalhos que já há nesses dias (ficam na Agenda).
  final AgendaInlineWarningViewData? warning;
}

class AgendaEditorViewData {
  const AgendaEditorViewData({
    required this.title,
    required this.type,
    required this.showTypeSelector,
    required this.showDelete,
    required this.saveLabel,
    required this.canSave,
    required this.submitting,
    required this.work,
    required this.unavailable,
    this.saveHelper,
  });

  /// "Adicionar à agenda" ou "Editar".
  final String title;
  final AgendaFormType type;

  /// Falso ao editar (F7): não se troca um trabalho por indisponível.
  final bool showTypeSelector;
  final bool showDelete;
  final String saveLabel;
  final bool canSave;
  final bool submitting;

  /// Porque o botão está cinzento ("Escreve um título para poder guardar.").
  final String? saveHelper;
  final AgendaWorkFormViewData work;
  final AgendaUnavailableFormViewData unavailable;
}

/// Confirmação ao guardar com as horas a cruzar (F4).
class AgendaConflictDialogData {
  const AgendaConflictDialogData({
    required this.title,
    required this.entryStart,
    required this.entryEnd,
    required this.entryTitle,
    required this.entryMeta,
    required this.summary,
    this.continueLabel = 'Guardar mesmo assim',
  });

  /// "Já tens um trabalho a esta hora".
  final String title;
  final String? entryStart;
  final String? entryEnd;
  final String entryTitle;
  final String? entryMeta;

  /// "O novo fica das 09:30 às 11:30. Cruzam-se 1 h 30." Vazio: sem texto.
  final String summary;

  /// Botão secundário: "Guardar mesmo assim", "Enviar mesmo assim" (A10,
  /// proposta) ou "Pedir mesmo assim" (remarcar).
  final String continueLabel;
}

/// Folha "Guardar a mudança em…" / "Apagar…" numa série (F7).
class AgendaScopeViewData {
  const AgendaScopeViewData({
    required this.title,
    required this.summary,
    required this.options,
    required this.actionLabel,
  });

  final String title;

  /// "Rega da D. Rosa repete todas as terças."
  final String summary;
  final List<AgendaChoiceViewData<AgendaSeriesScope>> options;
  final String actionLabel;
}
