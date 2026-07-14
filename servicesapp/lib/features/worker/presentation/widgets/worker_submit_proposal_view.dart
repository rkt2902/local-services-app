import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/widgets/app_filter_chip.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/primary_action_button.dart';

class WorkerProposalDateSelection {
  const WorkerProposalDateSelection({
    required this.value,
    required this.label,
  });

  final DateTime value;
  final String label;
}

class WorkerProposalTimeSlotViewData {
  const WorkerProposalTimeSlotViewData({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

class WorkerProposalDurationViewData {
  const WorkerProposalDurationViewData({
    required this.id,
    required this.label,
    required this.minimumHours,
    required this.maximumHours,
  });

  final String id;
  final String label;
  final int minimumHours;

  /// `null` = sem limite superior (ex.: opção "+6h"). O widget mostra um
  /// total "a partir de €X" em vez de um intervalo quando for null.
  final int? maximumHours;
}

class WorkerProposalDraft {
  const WorkerProposalDraft({
    required this.hourlyPrice,
    required this.scheduledDate,
    required this.timeSlotId,
    required this.durationOptionId,
    required this.minimumEstimatedHours,
    required this.maximumEstimatedHours,
    required this.needsHelpers,
    required this.helperCount,
    required this.helpersEquipmentRequired,
    required this.message,
  });

  final double hourlyPrice;

  final DateTime scheduledDate;
  final String timeSlotId;

  final String durationOptionId;
  final int minimumEstimatedHours;
  final int? maximumEstimatedHours;

  final bool needsHelpers;
  final int helperCount;
  final bool helpersEquipmentRequired;

  final String message;
}

class WorkerSubmitProposalScreen extends StatefulWidget {
  const WorkerSubmitProposalScreen({
    required this.suggestedHourlyPriceLabel,
    required this.timeSlots,
    required this.durationOptions,
    required this.onBack,
    required this.onSelectDate,
    required this.onSubmit,
    super.key,
    this.initialHourlyPrice,
    this.initialDate,
    this.initialTimeSlotId,
    this.initialDurationOptionId,
    this.initialNeedsHelpers = false,
    this.initialHelperCount = 1,
    this.initialHelpersEquipmentRequired = false,
    this.initialMessage = '',
    this.minimumHelperCount = 1,
    this.maximumHelperCount = 10,
    this.isSubmitting = false,
  });

  final String suggestedHourlyPriceLabel;

  /// Estas opções devem vir da configuração/domínio existente.
  /// O ecrã não cria listas fixas de períodos.
  final List<WorkerProposalTimeSlotViewData> timeSlots;

  /// Estas opções devem vir da configuração/domínio existente.
  /// Exemplos visuais do mockup: 1–2h, 2–4h, 4–6h, +6h.
  final List<WorkerProposalDurationViewData> durationOptions;

  final VoidCallback onBack;

  /// A integração deve abrir o calendário já utilizado no projeto.
  final Future<WorkerProposalDateSelection?> Function() onSelectDate;

  /// A submissão real e a navegação ficam fora do widget.
  final ValueChanged<WorkerProposalDraft> onSubmit;

  final double? initialHourlyPrice;
  final WorkerProposalDateSelection? initialDate;
  final String? initialTimeSlotId;
  final String? initialDurationOptionId;

  final bool initialNeedsHelpers;
  final int initialHelperCount;
  final bool initialHelpersEquipmentRequired;

  final String initialMessage;

  final int minimumHelperCount;
  final int maximumHelperCount;

  final bool isSubmitting;

  @override
  State<WorkerSubmitProposalScreen> createState() {
    return _WorkerSubmitProposalScreenState();
  }
}

class _WorkerSubmitProposalScreenState
    extends State<WorkerSubmitProposalScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _hourlyPriceController;
  late final TextEditingController _messageController;

  WorkerProposalDateSelection? _selectedDate;
  String? _selectedTimeSlotId;
  String? _selectedDurationOptionId;

  late bool _needsHelpers;
  late int _helperCount;
  late bool _equipmentRequired;

  bool _showSelectionErrors = false;

  WorkerProposalDurationViewData? get _selectedDuration {
    final selectedId = _selectedDurationOptionId;

    if (selectedId == null) {
      return null;
    }

    for (final option in widget.durationOptions) {
      if (option.id == selectedId) {
        return option;
      }
    }

    return null;
  }

  double? get _hourlyPrice {
    return _parsePrice(_hourlyPriceController.text);
  }

  String? get _estimatedTotalLabel {
    final price = _hourlyPrice;
    final duration = _selectedDuration;

    if (price == null || duration == null) {
      return null;
    }

    final minimumTotal = price * duration.minimumHours;
    final maximumHours = duration.maximumHours;

    if (maximumHours == null) {
      return '≈ ${duration.label} estimadas · total aproximado a partir de '
          '€${_formatMoney(minimumTotal)}';
    }

    final maximumTotal = price * maximumHours;

    return '≈ ${duration.label} estimadas · total aproximado '
        '€${_formatMoney(minimumTotal)}–${_formatMoney(maximumTotal)}';
  }

  @override
  void initState() {
    super.initState();

    _hourlyPriceController = TextEditingController(
      text: _formatInitialPrice(widget.initialHourlyPrice),
    );

    _messageController = TextEditingController(
      text: widget.initialMessage,
    );

    _selectedDate = widget.initialDate;
    _selectedTimeSlotId = widget.initialTimeSlotId;
    _selectedDurationOptionId =
        widget.initialDurationOptionId;

    _needsHelpers = widget.initialNeedsHelpers;

    _helperCount = widget.initialHelperCount.clamp(
      widget.minimumHelperCount,
      widget.maximumHelperCount,
    );

    _equipmentRequired = widget.initialHelpersEquipmentRequired;

    _hourlyPriceController.addListener(
      _handlePriceChanged,
    );
  }

  void _handlePriceChanged() {
    setState(() {});
  }

  String _formatInitialPrice(double? value) {
    if (value == null) {
      return '';
    }

    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value
        .toStringAsFixed(2)
        .replaceAll('.', ',');
  }

  String _formatMoney(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value
        .toStringAsFixed(2)
        .replaceAll('.', ',');
  }

  double? _parsePrice(String value) {
    return double.tryParse(
      value.trim().replaceAll(',', '.'),
    );
  }

  Future<void> _selectDate() async {
    final result = await widget.onSelectDate();

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _selectedDate = result;
    });
  }

  void _decreaseHelperCount() {
    if (_helperCount <= widget.minimumHelperCount) {
      return;
    }

    setState(() {
      _helperCount--;
    });
  }

  void _increaseHelperCount() {
    if (_helperCount >= widget.maximumHelperCount) {
      return;
    }

    setState(() {
      _helperCount++;
    });
  }

  void _submit() {
    setState(() {
      _showSelectionErrors = true;
    });

    final formIsValid =
        _formKey.currentState?.validate() ?? false;

    final duration = _selectedDuration;
    final price = _hourlyPrice;

    if (!formIsValid ||
        price == null ||
        _selectedDate == null ||
        _selectedTimeSlotId == null ||
        duration == null) {
      return;
    }

    widget.onSubmit(
      WorkerProposalDraft(
        hourlyPrice: price,
        scheduledDate: _selectedDate!.value,
        timeSlotId: _selectedTimeSlotId!,
        durationOptionId: duration.id,
        minimumEstimatedHours:
            duration.minimumHours,
        maximumEstimatedHours:
            duration.maximumHours,
        needsHelpers: _needsHelpers,
        helperCount:
            _needsHelpers ? _helperCount : 0,
        helpersEquipmentRequired:
            _needsHelpers ? _equipmentRequired : false,
        message: _messageController.text.trim(),
      ),
    );
  }

  @override
  void dispose() {
    _hourlyPriceController.removeListener(
      _handlePriceChanged,
    );

    _hourlyPriceController.dispose();
    _messageController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final estimatedTotalLabel =
        _estimatedTotalLabel;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          onPressed: widget.onBack,
          tooltip: 'Voltar',
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimary,
          ),
        ),
        titleSpacing: 0,
        title: Text(
          'A sua proposta',
          style: textTheme.titleLarge?.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Preço por hora',
                      style:
                          textTheme.labelMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(
                      height: AppSpacing.xs,
                    ),
                    _HourlyPriceField(
                      controller:
                          _hourlyPriceController,
                      suggestedPriceLabel:
                          widget.suggestedHourlyPriceLabel,
                    ),
                    if (estimatedTotalLabel != null) ...[
                      const SizedBox(
                        height: AppSpacing.xs,
                      ),
                      Text(
                        estimatedTotalLabel,
                        style:
                            textTheme.labelMedium?.copyWith(
                          color:
                              AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(
                      height: AppSpacing.sm,
                    ),
                    Text(
                      'Agendamento',
                      style:
                          textTheme.labelMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(
                      height: AppSpacing.xs,
                    ),
                    _DateSelector(
                      label: _selectedDate?.label ??
                          'Escolher dia no calendário',
                      selected:
                          _selectedDate != null,
                      onPressed: _selectDate,
                    ),
                    if (_showSelectionErrors &&
                        _selectedDate == null) ...[
                      const SizedBox(
                        height: AppSpacing.xxs,
                      ),
                      const _SelectionError(
                        message:
                            'Selecione uma data.',
                      ),
                    ],
                    const SizedBox(
                      height: AppSpacing.xs,
                    ),
                    _TimeSlotSelector(
                      options: widget.timeSlots,
                      selectedId:
                          _selectedTimeSlotId,
                      onSelected: (id) {
                        setState(() {
                          _selectedTimeSlotId = id;
                        });
                      },
                    ),
                    if (_showSelectionErrors &&
                        _selectedTimeSlotId ==
                            null) ...[
                      const SizedBox(
                        height: AppSpacing.xxs,
                      ),
                      const _SelectionError(
                        message:
                            'Selecione um período.',
                      ),
                    ],
                    const SizedBox(
                      height: AppSpacing.sm,
                    ),
                    Text(
                      'Duração estimada do trabalho',
                      style:
                          textTheme.labelMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(
                      height: AppSpacing.xs,
                    ),
                    _DurationSelector(
                      options:
                          widget.durationOptions,
                      selectedId:
                          _selectedDurationOptionId,
                      onSelected: (id) {
                        setState(() {
                          _selectedDurationOptionId =
                              id;
                        });
                      },
                    ),
                    if (_showSelectionErrors &&
                        _selectedDurationOptionId ==
                            null) ...[
                      const SizedBox(
                        height: AppSpacing.xxs,
                      ),
                      const _SelectionError(
                        message:
                            'Selecione uma duração.',
                      ),
                    ],
                    const SizedBox(
                      height: AppSpacing.sm,
                    ),

                    // O estado 4b é apenas este componente
                    // com enabled = true.
                    _HelpersSection(
                      enabled: _needsHelpers,
                      helperCount: _helperCount,
                      canDecrease: _helperCount >
                          widget.minimumHelperCount,
                      canIncrease: _helperCount <
                          widget.maximumHelperCount,
                      equipmentRequired: _equipmentRequired,
                      onEnabledChanged: (value) {
                        setState(() {
                          _needsHelpers = value;
                        });
                      },
                      onDecrease:
                          _decreaseHelperCount,
                      onIncrease:
                          _increaseHelperCount,
                      onEquipmentRequiredChanged: (value) {
                        setState(() {
                          _equipmentRequired = value;
                        });
                      },
                    ),

                    const SizedBox(
                      height: AppSpacing.sm,
                    ),
                    Text(
                      'Mensagem',
                      style:
                          textTheme.labelMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(
                      height: AppSpacing.xs,
                    ),
                    AppTextField(
                      controller: _messageController,
                      label: 'Mensagem opcional',
                      minLines: 2,
                      maxLines: 4,
                      textInputAction:
                          TextInputAction.newline,
                    ),
                    const SizedBox(
                      height: AppSpacing.xs,
                    ),
                    Text(
                      'Descreva o que inclui a proposta '
                      '— varia por serviço.',
                      style:
                          textTheme.labelMedium?.copyWith(
                        color:
                            AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            color: AppColors.background,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: PrimaryActionButton(
              label: 'Enviar proposta',
              isLoading: widget.isSubmitting,
              onPressed: widget.isSubmitting
                  ? null
                  : _submit,
            ),
          ),
        ],
      ),
    );
  }
}

class _HourlyPriceField extends StatelessWidget {
  const _HourlyPriceField({
    required this.controller,
    required this.suggestedPriceLabel,
  });

  final TextEditingController controller;
  final String suggestedPriceLabel;

  double? _parsePrice(String value) {
    return double.tryParse(
      value.trim().replaceAll(',', '.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return TextFormField(
      controller: controller,
      keyboardType:
          const TextInputType.numberWithOptions(
        decimal: true,
      ),
      textInputAction: TextInputAction.next,
      style: textTheme.titleLarge?.copyWith(
        color: AppColors.textPrimary,
      ),
      validator: (value) {
        final price = _parsePrice(value ?? '');

        if (price == null || price <= 0) {
          return 'Introduza um preço válido.';
        }

        return null;
      },
      decoration: InputDecoration(
        prefixText: '€ ',
        prefixStyle:
            textTheme.titleLarge?.copyWith(
          color: AppColors.primary,
        ),
        suffix: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(
              AppRadius.pill,
            ),
          ),
          child: Text(
            'Sugerido: $suggestedPriceLabel',
            style:
                textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            AppRadius.input,
          ),
          borderSide: const BorderSide(
            color: AppColors.primary,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            AppRadius.input,
          ),
          borderSide: const BorderSide(
            color: AppColors.primary,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            AppRadius.input,
          ),
          borderSide: BorderSide(
            color: AppStatusColor
                .cancelled.foreground,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            AppRadius.input,
          ),
          borderSide: BorderSide(
            color: AppStatusColor
                .cancelled.foreground,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

class _DateSelector extends StatelessWidget {
  const _DateSelector({
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
      color: AppColors.surface,
      borderRadius:
          BorderRadius.circular(AppRadius.input),
      child: InkWell(
        onTap: onPressed,
        borderRadius:
            BorderRadius.circular(AppRadius.input),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              AppRadius.input,
            ),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : AppColors.divider,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      textTheme.bodyMedium?.copyWith(
                    color: selected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(
                width: AppSpacing.sm,
              ),
              const Icon(
                Icons.calendar_month_outlined,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeSlotSelector extends StatelessWidget {
  const _TimeSlotSelector({
    required this.options,
    required this.selectedId,
    required this.onSelected,
  });

  final List<WorkerProposalTimeSlotViewData>
      options;

  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return const _EmptyOptionsMessage(
        message: 'Nenhum período disponível.',
      );
    }

    return Row(
      children: [
        for (
          var index = 0;
          index < options.length;
          index++
        ) ...[
          Expanded(
            child: AppFilterChip(
              label: options[index].label,
              selected:
                  selectedId == options[index].id,
              onPressed: () {
                onSelected(options[index].id);
              },
            ),
          ),
          if (index < options.length - 1)
            const SizedBox(
              width: AppSpacing.xs,
            ),
        ],
      ],
    );
  }
}

class _DurationSelector extends StatelessWidget {
  const _DurationSelector({
    required this.options,
    required this.selectedId,
    required this.onSelected,
  });

  final List<WorkerProposalDurationViewData>
      options;

  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return const _EmptyOptionsMessage(
        message:
            'Nenhuma duração disponível.',
      );
    }

    return Row(
      children: [
        for (
          var index = 0;
          index < options.length;
          index++
        ) ...[
          Expanded(
            child: AppFilterChip(
              label: options[index].label,
              selected:
                  selectedId == options[index].id,
              onPressed: () {
                onSelected(options[index].id);
              },
            ),
          ),
          if (index < options.length - 1)
            const SizedBox(
              width: AppSpacing.xs,
            ),
        ],
      ],
    );
  }
}

class _HelpersSection extends StatelessWidget {
  const _HelpersSection({
    required this.enabled,
    required this.helperCount,
    required this.canDecrease,
    required this.canIncrease,
    required this.equipmentRequired,
    required this.onEnabledChanged,
    required this.onDecrease,
    required this.onIncrease,
    required this.onEquipmentRequiredChanged,
  });

  final bool enabled;
  final int helperCount;

  final bool canDecrease;
  final bool canIncrease;

  /// Campo que já existia no fluxo antigo (_ProposalSheet) e não pode
  /// perder-se: se os ajudantes devem trazer equipamento próprio.
  final bool equipmentRequired;

  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final ValueChanged<bool> onEquipmentRequiredChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AnimatedContainer(
      duration: const Duration(
        milliseconds: 220,
      ),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.all(
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: enabled
            ? AppColors.primaryContainer
            : AppColors.surface,
        borderRadius:
            BorderRadius.circular(AppRadius.input),
        border: Border.all(
          color: enabled
              ? AppColors.primary
              : AppColors.divider,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.group_add_outlined,
                color: AppColors.primary,
              ),
              const SizedBox(
                width: AppSpacing.sm,
              ),
              Expanded(
                child: Text(
                  'Preciso de ajudantes',
                  style:
                      textTheme.titleMedium?.copyWith(
                    color: enabled
                        ? AppColors.primary
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              Switch.adaptive(
                value: enabled,
                activeTrackColor:
                    AppColors.primary,
                activeThumbColor:
                    AppColors.surface,
                inactiveTrackColor:
                    AppColors.divider,
                inactiveThumbColor:
                    AppColors.surface,
                onChanged: onEnabledChanged,
              ),
            ],
          ),

          // Este bloco só aparece no estado 4b.
          AnimatedSize(
            duration: const Duration(
              milliseconds: 220,
            ),
            curve: Curves.easeOutCubic,
            child: enabled
                ? Column(
                    children: [
                      const SizedBox(
                        height: AppSpacing.sm,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Quantos ajudantes?',
                              style: textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                color: AppColors
                                    .textSecondary,
                              ),
                            ),
                          ),
                          _HelperCountButton(
                            icon:
                                Icons.remove_rounded,
                            enabled: canDecrease,
                            onPressed: onDecrease,
                          ),
                          SizedBox(
                            width: 38,
                            child: Text(
                              helperCount.toString(),
                              textAlign:
                                  TextAlign.center,
                              style: textTheme
                                  .titleMedium
                                  ?.copyWith(
                                color: AppColors
                                    .textPrimary,
                              ),
                            ),
                          ),
                          _HelperCountButton(
                            icon: Icons.add_rounded,
                            enabled: canIncrease,
                            onPressed: onIncrease,
                          ),
                        ],
                      ),
                      const SizedBox(
                        height: AppSpacing.xs,
                      ),
                      // Switch secundário, discreto — não existia no
                      // mockup de referência, mas o campo já existia no
                      // fluxo antigo (helpersEquipmentRequired) e não
                      // podia perder-se.
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Ajudantes trazem equipamento próprio',
                              style: textTheme.labelMedium
                                  ?.copyWith(
                                color: AppColors
                                    .textSecondary,
                              ),
                            ),
                          ),
                          Transform.scale(
                            scale: 0.8,
                            child: Switch.adaptive(
                              value: equipmentRequired,
                              activeTrackColor:
                                  AppColors.primary,
                              activeThumbColor:
                                  AppColors.surface,
                              inactiveTrackColor:
                                  AppColors.divider,
                              inactiveThumbColor:
                                  AppColors.surface,
                              onChanged:
                                  onEquipmentRequiredChanged,
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _HelperCountButton extends StatelessWidget {
  const _HelperCountButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? onPressed : null,
      constraints: const BoxConstraints(
        minWidth: 36,
        minHeight: 36,
      ),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.surface,
        foregroundColor: enabled
            ? AppColors.primary
            : AppColors.textSecondary,
        disabledForegroundColor:
            AppColors.textSecondary,
        side: const BorderSide(
          color: AppColors.divider,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            AppRadius.input,
          ),
        ),
      ),
      icon: Icon(
        icon,
        size: 20,
      ),
    );
  }
}

class _SelectionError extends StatelessWidget {
  const _SelectionError({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Text(
      message,
      style: textTheme.labelMedium?.copyWith(
        color:
            AppStatusColor.cancelled.foreground,
      ),
    );
  }
}

class _EmptyOptionsMessage extends StatelessWidget {
  const _EmptyOptionsMessage({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Text(
      message,
      style: textTheme.bodyMedium?.copyWith(
        color: AppColors.textSecondary,
      ),
    );
  }
}
