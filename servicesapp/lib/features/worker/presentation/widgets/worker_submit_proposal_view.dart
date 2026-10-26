import 'package:flutter/material.dart';

import '../../../../core/constants/enums.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion_tokens.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/utils/price_labels.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_filter_chip.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/primary_action_button.dart';

class WorkerProposalDateSelection {
  const WorkerProposalDateSelection({required this.value, required this.label});

  final DateTime value;
  final String label;
}

class WorkerProposalTimeSlotViewData {
  const WorkerProposalTimeSlotViewData({required this.id, required this.label});

  final String id;
  final String label;
}

/// Unidade da duração estimada. Por hora é sempre em horas; no valor
/// total o jardineiro escolhe horas ou dias (design A6).
enum WorkerProposalDurationUnit { hours, days }

class WorkerProposalDurationViewData {
  const WorkerProposalDurationViewData({
    required this.id,
    required this.label,
    required this.minimum,
    required this.maximum,
  });

  final String id;
  final String label;

  /// Horas ou dias, conforme a lista de onde vem.
  final int minimum;

  /// `null` = sem limite superior (ex.: "+6h", "Mais de uma semana").
  final int? maximum;
}

/// Uma opção de "O que inclui" (vem da BD, nunca fixa no ecrã).
class WorkerProposalIncludeViewData {
  const WorkerProposalIncludeViewData({required this.id, required this.label});

  final String id;
  final String label;
}

/// Validade escolhida. Ex.: 15 dias, "15 dias", "até 06/11".
class WorkerProposalValiditySelection {
  const WorkerProposalValiditySelection({
    required this.days,
    required this.label,
    required this.untilLabel,
  });

  final int days;
  final String label;
  final String untilLabel;
}

class WorkerProposalDraft {
  const WorkerProposalDraft({
    required this.pricingMode,
    required this.price,
    required this.scheduledDate,
    required this.timeSlotId,
    required this.durationUnit,
    required this.minimumDuration,
    required this.maximumDuration,
    required this.includeIds,
    required this.validityDays,
    required this.needsHelpers,
    required this.helperCount,
    required this.helpersEquipmentRequired,
    required this.message,
  });

  final ProposalPricingMode pricingMode;

  /// Preço por hora ou valor total, conforme [pricingMode].
  final double price;

  final DateTime scheduledDate;
  final String timeSlotId;

  final WorkerProposalDurationUnit durationUnit;
  final int minimumDuration;
  final int? maximumDuration;

  /// Só no valor total.
  final Set<String> includeIds;
  final int validityDays;

  final bool needsHelpers;
  final int helperCount;
  final bool helpersEquipmentRequired;

  final String message;
}

class WorkerSubmitProposalScreen extends StatefulWidget {
  const WorkerSubmitProposalScreen({
    required this.timeSlots,
    required this.durationOptions,
    required this.dayDurationOptions,
    required this.includeOptions,
    required this.initialValidity,
    required this.onBack,
    required this.onSelectDate,
    required this.onSelectValidity,
    required this.onSubmit,
    super.key,
    this.jobSubtitle,
    this.clientDateLabel,
    this.initialPricingMode = ProposalPricingMode.hourly,
    this.pricingModeHint,
    this.suggestedHourlyPriceLabel,
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
    this.submitError,
    this.jobClosed = false,
  });

  /// Ex.: "Limpeza de terreno · Grande".
  final String? jobSubtitle;

  /// Data pretendida pelo cliente, já formatada (ex.: "18/10/2026",
  /// "Flexível" ou o texto de disponibilidade). Aparece junto à data de
  /// início para o jardineiro não ter de voltar ao pedido.
  final String? clientDateLabel;

  final ProposalPricingMode initialPricingMode;

  /// Ex.: "Escolhemos o valor total porque o usaste da última vez."
  final String? pricingModeHint;

  final String? suggestedHourlyPriceLabel;

  /// Estas opções devem vir da configuração/domínio existente.
  /// O ecrã não cria listas fixas de períodos.
  final List<WorkerProposalTimeSlotViewData> timeSlots;

  /// Duração em horas (os dois formatos). Ex.: 1–2h, 2–4h, 4–6h, +6h.
  final List<WorkerProposalDurationViewData> durationOptions;

  /// Duração em dias (só no valor total). Ex.: 1 dia, 2 a 3 dias.
  final List<WorkerProposalDurationViewData> dayDurationOptions;

  /// Opções de "O que inclui". Vazia: a secção não aparece.
  final List<WorkerProposalIncludeViewData> includeOptions;

  final WorkerProposalValiditySelection initialValidity;

  final VoidCallback onBack;

  /// A integração deve abrir o calendário já utilizado no projeto, no dia
  /// escolhido de momento (`current`), se houver.
  final Future<WorkerProposalDateSelection?> Function(DateTime? current)
      onSelectDate;

  /// A integração abre a escolha da validade.
  final Future<WorkerProposalValiditySelection?> Function() onSelectValidity;

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

  /// Erro do último envio ("Tentar novamente" volta a enviar).
  final String? submitError;

  /// O pedido fechou entretanto: o botão fica bloqueado.
  final bool jobClosed;

  @override
  State<WorkerSubmitProposalScreen> createState() {
    return _WorkerSubmitProposalScreenState();
  }
}

class _WorkerSubmitProposalScreenState
    extends State<WorkerSubmitProposalScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _priceController;
  late final TextEditingController _messageController;

  late ProposalPricingMode _pricingMode;

  /// O preço por hora e o valor total não partilham o campo: ao trocar de
  /// formato o valor de cada um fica guardado.
  String _hourlyText = '';
  String _totalText = '';

  WorkerProposalDateSelection? _selectedDate;
  String? _selectedTimeSlotId;
  String? _selectedDurationOptionId;
  WorkerProposalDurationUnit _durationUnit = WorkerProposalDurationUnit.hours;
  final Set<String> _includeIds = {};
  late WorkerProposalValiditySelection _validity;

  late bool _needsHelpers;
  late int _helperCount;
  late bool _equipmentRequired;

  bool _showSelectionErrors = false;

  bool get _isFixed => _pricingMode == ProposalPricingMode.fixedTotal;

  List<WorkerProposalDurationViewData> get _durationChoices =>
      _durationUnit == WorkerProposalDurationUnit.days
          ? widget.dayDurationOptions
          : widget.durationOptions;

  WorkerProposalDurationViewData? get _selectedDuration {
    final selectedId = _selectedDurationOptionId;

    if (selectedId == null) {
      return null;
    }

    for (final option in _durationChoices) {
      if (option.id == selectedId) {
        return option;
      }
    }

    return null;
  }

  double? get _price {
    return _parsePrice(_priceController.text);
  }

  String? get _estimatedTotalLabel {
    if (_isFixed) return null;
    final price = _price;
    final duration = _selectedDuration;

    if (price == null || duration == null) {
      return null;
    }

    // Total da equipa toda (o cliente vê este mesmo valor nas propostas).
    final teamPrice = teamHourlyRate(
      price,
      peopleNeeded: _needsHelpers ? _helperCount + 1 : 1,
      helpersEquipmentRequired: _needsHelpers && _equipmentRequired,
    );
    final teamNote = _needsHelpers ? ' com a equipa' : '';
    final minimumTotal = teamPrice * duration.minimum;
    final maximumHours = duration.maximum;

    if (maximumHours == null) {
      return 'Total aproximado$teamNote: a partir de '
          '${_formatMoney(minimumTotal)} €';
    }

    final maximumTotal = teamPrice * maximumHours;

    return 'Total aproximado$teamNote: ${_formatMoney(minimumTotal)} a '
        '${_formatMoney(maximumTotal)} €';
  }

  @override
  void initState() {
    super.initState();

    _pricingMode = widget.initialPricingMode;
    _hourlyText = _formatInitialPrice(widget.initialHourlyPrice);
    _priceController = TextEditingController(
      text: _isFixed ? _totalText : _hourlyText,
    );

    _messageController = TextEditingController(text: widget.initialMessage);

    _selectedDate = widget.initialDate;
    _selectedTimeSlotId = widget.initialTimeSlotId;
    _selectedDurationOptionId = widget.initialDurationOptionId;
    _validity = widget.initialValidity;

    _needsHelpers = widget.initialNeedsHelpers;

    _helperCount = widget.initialHelperCount.clamp(
      widget.minimumHelperCount,
      widget.maximumHelperCount,
    );

    _equipmentRequired = widget.initialHelpersEquipmentRequired;

    _priceController.addListener(_handlePriceChanged);
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

    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  String _formatMoney(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  double? _parsePrice(String value) {
    return double.tryParse(value.trim().replaceAll(',', '.'));
  }

  void _setPricingMode(ProposalPricingMode mode) {
    if (mode == _pricingMode) return;
    setState(() {
      if (_isFixed) {
        _totalText = _priceController.text;
      } else {
        _hourlyText = _priceController.text;
      }
      _pricingMode = mode;
      _priceController.text = _isFixed ? _totalText : _hourlyText;
      // Por hora a duração é sempre em horas.
      if (!_isFixed && _durationUnit == WorkerProposalDurationUnit.days) {
        _durationUnit = WorkerProposalDurationUnit.hours;
        _selectedDurationOptionId = null;
      }
      _showSelectionErrors = false;
    });
    _formKey.currentState?.reset();
  }

  void _setDurationUnit(WorkerProposalDurationUnit unit) {
    if (unit == _durationUnit) return;
    setState(() {
      _durationUnit = unit;
      _selectedDurationOptionId = null;
    });
  }

  Future<void> _selectDate() async {
    final result = await widget.onSelectDate(_selectedDate?.value);

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _selectedDate = result;
    });
  }

  Future<void> _selectValidity() async {
    final result = await widget.onSelectValidity();
    if (!mounted || result == null) return;
    setState(() => _validity = result);
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
    if (widget.jobClosed) return;
    setState(() {
      _showSelectionErrors = true;
    });

    final formIsValid = _formKey.currentState?.validate() ?? false;

    final duration = _selectedDuration;
    final price = _price;

    if (!formIsValid ||
        price == null ||
        _selectedDate == null ||
        _selectedTimeSlotId == null ||
        duration == null) {
      return;
    }

    widget.onSubmit(
      WorkerProposalDraft(
        pricingMode: _pricingMode,
        price: price,
        scheduledDate: _selectedDate!.value,
        timeSlotId: _selectedTimeSlotId!,
        durationUnit: _durationUnit,
        minimumDuration: duration.minimum,
        maximumDuration: duration.maximum,
        includeIds: _isFixed ? {..._includeIds} : const {},
        validityDays: _validity.days,
        needsHelpers: _needsHelpers,
        helperCount: _needsHelpers ? _helperCount : 0,
        helpersEquipmentRequired: _needsHelpers ? _equipmentRequired : false,
        message: _messageController.text.trim(),
      ),
    );
  }

  @override
  void dispose() {
    _priceController.removeListener(_handlePriceChanged);

    _priceController.dispose();
    _messageController.dispose();

    super.dispose();
  }

  String get _submitLabel {
    final price = _price;
    if (_isFixed && price != null && price > 0) {
      return 'Enviar proposta de ${_formatMoney(price)} €';
    }
    return 'Enviar proposta';
  }

  List<_SummaryLine> get _summaryLines {
    final duration = _selectedDuration;
    final includes = [
      for (final o in widget.includeOptions)
        if (_includeIds.contains(o.id)) o.label,
    ];
    return [
      if (_isFixed && includes.isNotEmpty)
        _SummaryLine('Inclui', includes.join(', ')),
      if (!_isFixed && _estimatedTotalLabel != null)
        _SummaryLine(
          'Total aproximado',
          _estimatedTotalLabel!.split(': ').last,
        ),
      if (duration != null) _SummaryLine('Duração', duration.label),
      if (_selectedDate != null) _SummaryLine('Início', _selectedDate!.label),
      _SummaryLine('Válido até', _validity.untilLabel.replaceFirst('até ', '')),
      if (_needsHelpers) _SummaryLine('Ajudantes', '$_helperCount'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final estimatedTotalLabel = _estimatedTotalLabel;
    final price = _price;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          onPressed: widget.onBack,
          tooltip: 'Fechar',
          icon: const Icon(
            Icons.close_rounded,
            color: AppColors.textPrimary,
          ),
        ),
        titleSpacing: 0,
        title: AppBarTitle(
          title: 'Enviar proposta',
          subtitle: widget.jobSubtitle,
        ),
      ),
      body: SafeArea(
        child: Column(
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppStaggeredEntrance(
                        index: 0,
                        child: _PricingModeSwitch(
                          selected: _pricingMode,
                          onChanged: _setPricingMode,
                        ),
                      ),
                      if (widget.pricingModeHint != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.history_rounded,
                              size: AppSizes.metaIcon,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: AppSpacing.xxs),
                            Expanded(
                              child: Text(
                                widget.pricingModeHint!,
                                style: textTheme.labelSmall?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        _isFixed ? 'Valor total' : 'Preço por hora',
                        style: textTheme.labelMedium?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      _PriceField(
                        key: ValueKey(_pricingMode),
                        controller: _priceController,
                        fixedTotal: _isFixed,
                        suggestedPriceLabel: _isFixed
                            ? null
                            : widget.suggestedHourlyPriceLabel,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _isFixed
                            ? 'É o valor que o cliente paga, faças as horas '
                                'que fizeres.'
                            : estimatedTotalLabel ??
                                'Escolhe a duração para veres o total '
                                    'aproximado.',
                        style: textTheme.labelMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (_isFixed && widget.includeOptions.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'O que inclui',
                          style: textTheme.labelMedium?.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            for (final option in widget.includeOptions)
                              AppFilterChip(
                                label: option.label,
                                selected: _includeIds.contains(option.id),
                                showCheckmark: true,
                                onPressed: () => setState(() {
                                  if (!_includeIds.remove(option.id)) {
                                    _includeIds.add(option.id);
                                  }
                                }),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        AppTextField(
                          controller: _messageController,
                          label: 'Mais alguma coisa? (opcional)',
                          minLines: 2,
                          maxLines: 4,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Duração estimada',
                              style: textTheme.labelMedium?.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (_isFixed && widget.dayDurationOptions.isNotEmpty)
                            _UnitToggle(
                              selected: _durationUnit,
                              onChanged: _setDurationUnit,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      _DurationSelector(
                        options: _durationChoices,
                        columns:
                            _durationUnit == WorkerProposalDurationUnit.days
                                ? 2
                                : 4,
                        selectedId: _selectedDurationOptionId,
                        onSelected: (id) {
                          setState(() {
                            _selectedDurationOptionId = id;
                          });
                        },
                      ),
                      if (_showSelectionErrors &&
                          _selectedDuration == null) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        const _SelectionError(
                          message: 'Seleciona uma duração.',
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Data de início',
                        style: textTheme.labelMedium?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (widget.clientDateLabel != null) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          'O cliente pediu: ${widget.clientDateLabel}',
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xs),
                      _DateSelector(
                        label:
                            _selectedDate?.label ??
                            'Escolher dia no calendário',
                        selected: _selectedDate != null,
                        onPressed: _selectDate,
                      ),
                      if (_showSelectionErrors && _selectedDate == null) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        const _SelectionError(message: 'Seleciona uma data.'),
                      ],
                      const SizedBox(height: AppSpacing.xs),
                      _TimeSlotSelector(
                        options: widget.timeSlots,
                        selectedId: _selectedTimeSlotId,
                        onSelected: (id) {
                          setState(() {
                            _selectedTimeSlotId = id;
                          });
                        },
                      ),
                      if (_showSelectionErrors &&
                          _selectedTimeSlotId == null) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        const _SelectionError(message: 'Seleciona um período.'),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Validade do orçamento',
                        style: textTheme.labelMedium?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      _ValidityField(
                        validity: _validity,
                        onPressed: _selectValidity,
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // O estado 4b é apenas este componente
                      // com enabled = true.
                      _HelpersSection(
                        enabled: _needsHelpers,
                        helperCount: _helperCount,
                        canDecrease: _helperCount > widget.minimumHelperCount,
                        canIncrease: _helperCount < widget.maximumHelperCount,
                        equipmentRequired: _equipmentRequired,
                        onEnabledChanged: (value) {
                          setState(() {
                            _needsHelpers = value;
                          });
                        },
                        onDecrease: _decreaseHelperCount,
                        onIncrease: _increaseHelperCount,
                        onEquipmentRequiredChanged: (value) {
                          setState(() {
                            _equipmentRequired = value;
                          });
                        },
                      ),

                      if (!_isFixed) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Mensagem',
                          style: textTheme.labelMedium?.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        AppTextField(
                          controller: _messageController,
                          label: 'Mensagem opcional',
                          minLines: 2,
                          maxLines: 4,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Descreve o que inclui a proposta '
                          '(varia por serviço).',
                          style: textTheme.labelMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      if (price != null && price > 0) ...[
                        const SizedBox(height: AppSpacing.md),
                        _ProposalSummaryCard(
                          priceTitle: _isFixed ? 'Valor fechado' : 'Preço por hora',
                          priceLabel: _isFixed
                              ? '${_formatMoney(price)} €'
                              : '${_formatMoney(price)} €/h',
                          lines: _summaryLines,
                        ),
                      ],
                      if (widget.jobClosed) ...[
                        const SizedBox(height: AppSpacing.md),
                        const _SubmitStateCard(
                          icon: Icons.lock_outline_rounded,
                          tone: AppStatusColor.neutral,
                          message: 'Este pedido já não aceita propostas. O '
                              'que escreveste não foi enviado.',
                        ),
                      ] else if (widget.submitError != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        _SubmitStateCard(
                          icon: Icons.error_outline_rounded,
                          tone: AppStatusColor.cancelled,
                          message: widget.submitError!,
                          onRetry: widget.isSubmitting ? null : _submit,
                        ),
                      ],
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
                label: widget.isSubmitting ? 'A enviar...' : _submitLabel,
                isLoading: widget.isSubmitting,
                onPressed: (widget.isSubmitting || widget.jobClosed)
                    ? null
                    : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryLine {
  const _SummaryLine(this.label, this.value);

  final String label;
  final String value;
}

/// "Preço por hora | Valor total".
class _PricingModeSwitch extends StatelessWidget {
  const _PricingModeSwitch({required this.selected, required this.onChanged});

  final ProposalPricingMode selected;
  final ValueChanged<ProposalPricingMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.divider,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentButton(
              label: 'Preço por hora',
              selected: selected == ProposalPricingMode.hourly,
              onPressed: () => onChanged(ProposalPricingMode.hourly),
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: _SegmentButton(
              label: 'Valor total',
              selected: selected == ProposalPricingMode.fixedTotal,
              onPressed: () => onChanged(ProposalPricingMode.fixedTotal),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Horas | Dias", pequeno, ao lado de "Duração estimada".
class _UnitToggle extends StatelessWidget {
  const _UnitToggle({required this.selected, required this.onChanged});

  final WorkerProposalDurationUnit selected;
  final ValueChanged<WorkerProposalDurationUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.divider,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SegmentButton(
            label: 'Horas',
            compact: true,
            selected: selected == WorkerProposalDurationUnit.hours,
            onPressed: () => onChanged(WorkerProposalDurationUnit.hours),
          ),
          _SegmentButton(
            label: 'Dias',
            compact: true,
            selected: selected == WorkerProposalDurationUnit.days,
            onPressed: () => onChanged(WorkerProposalDurationUnit.days),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(
      compact ? AppRadius.pill : AppRadius.input,
    );
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          child: AnimatedContainer(
            duration:
                disableAnimations ? Duration.zero : AppMotionDuration.fast,
            curve: AppMotionCurve.standard,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? AppSpacing.sm : AppSpacing.xs,
              vertical: compact ? AppSpacing.xxs : AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: selected ? AppColors.surface : Colors.transparent,
              borderRadius: radius,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: (compact ? textTheme.labelMedium : textTheme.bodyMedium)
                  ?.copyWith(
                color: selected ? AppColors.primary : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PriceField extends StatelessWidget {
  const _PriceField({
    super.key,
    required this.controller,
    required this.fixedTotal,
    required this.suggestedPriceLabel,
  });

  final TextEditingController controller;
  final bool fixedTotal;

  /// Null/vazio = sem preço sugerido — o chip "Sugerido: ..." não é
  /// mostrado (o wrapper só passa um valor quando o worker tem
  /// `default_hourly_rate` definido no perfil).
  final String? suggestedPriceLabel;

  double? _parsePrice(String value) {
    return double.tryParse(value.trim().replaceAll(',', '.'));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasSuggestion = suggestedPriceLabel != null &&
        suggestedPriceLabel!.isNotEmpty;

    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
      validator: (value) {
        final price = _parsePrice(value ?? '');

        if (price == null || price <= 0) {
          return fixedTotal
              ? 'Indica o valor total da proposta.'
              : 'Introduz um preço válido.';
        }

        return null;
      },
      decoration: InputDecoration(
        hintText: '0',
        suffixText: fixedTotal ? '€' : '€/h',
        suffixStyle:
            textTheme.titleMedium?.copyWith(color: AppColors.textSecondary),
        helper: hasSuggestion
            ? Text(
                'Sugerido: $suggestedPriceLabel',
                style: textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              )
            : null,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: AppStatusColor.cancelled.foreground),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(
            color: AppStatusColor.cancelled.foreground,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

/// "Validade do orçamento": "15 dias" e "até 06/11" à direita.
class _ValidityField extends StatelessWidget {
  const _ValidityField({required this.validity, required this.onPressed});

  final WorkerProposalValiditySelection validity;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.input),
        child: Container(
          width: double.infinity,
          constraints:
              const BoxConstraints(minHeight: AppSizes.dateFieldMinHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.input),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  validity.label,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                validity.untilLabel,
                style: textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Resumo da proposta" antes de enviar.
class _ProposalSummaryCard extends StatelessWidget {
  const _ProposalSummaryCard({
    required this.priceTitle,
    required this.priceLabel,
    required this.lines,
  });

  final String priceTitle;
  final String priceLabel;
  final List<_SummaryLine> lines;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'RESUMO DA PROPOSTA',
            style: textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  priceTitle,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                priceLabel,
                style: textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.label,
                    style: textTheme.labelMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      line.value,
                      textAlign: TextAlign.end,
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
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

/// Erro ao enviar (com "Tentar novamente") ou pedido já fechado.
class _SubmitStateCard extends StatelessWidget {
  const _SubmitStateCard({
    required this.icon,
    required this.tone,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final AppStatusColor tone;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Row(
        children: [
          Icon(icon, size: AppSizes.infoRowIcon, color: tone.foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text(
                'Tentar novamente',
                style: textTheme.labelMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
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
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.input),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.input),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.divider,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: selected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
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

  final List<WorkerProposalTimeSlotViewData> options;

  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return const _EmptyOptionsMessage(message: 'Nenhum período disponível.');
    }

    return Row(
      children: [
        for (var index = 0; index < options.length; index++) ...[
          Expanded(
            child: AppFilterChip(
              label: options[index].label,
              selected: selectedId == options[index].id,
              onPressed: () {
                onSelected(options[index].id);
              },
            ),
          ),
          if (index < options.length - 1) const SizedBox(width: AppSpacing.xs),
        ],
      ],
    );
  }
}

class _DurationSelector extends StatelessWidget {
  const _DurationSelector({
    required this.options,
    required this.columns,
    required this.selectedId,
    required this.onSelected,
  });

  final List<WorkerProposalDurationViewData> options;

  /// 4 por linha nas horas, 2 nos dias (os textos são maiores).
  final int columns;

  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return const _EmptyOptionsMessage(message: 'Nenhuma duração disponível.');
    }

    return Column(
      children: [
        for (var start = 0; start < options.length; start += columns) ...[
          if (start > 0) const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              for (var index = start; index < start + columns; index++) ...[
                Expanded(
                  child: index < options.length
                      ? AppFilterChip(
                          label: options[index].label,
                          selected: selectedId == options[index].id,
                          onPressed: () {
                            onSelected(options[index].id);
                          },
                        )
                      : const SizedBox.shrink(),
                ),
                if (index < start + columns - 1)
                  const SizedBox(width: AppSpacing.xs),
              ],
            ],
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

    // docs/motion_spec.md §3: cartão de estado (fast · standard). Reduced
    // motion mantém a cor/estado final mas corta a transição (§5).
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final transitionDuration =
        disableAnimations ? Duration.zero : AppMotionDuration.fast;

    return AnimatedContainer(
      duration: transitionDuration,
      curve: AppMotionCurve.standard,
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: enabled ? AppColors.primaryContainer : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(
          color: enabled ? AppColors.primary : AppColors.divider,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.group_add_outlined, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Preciso de ajudantes',
                  style: textTheme.titleMedium?.copyWith(
                    color: enabled ? AppColors.primary : AppColors.textPrimary,
                  ),
                ),
              ),
              Switch.adaptive(
                value: enabled,
                activeTrackColor: AppColors.primary,
                activeThumbColor: AppColors.surface,
                inactiveTrackColor: AppColors.divider,
                inactiveThumbColor: AppColors.surface,
                onChanged: onEnabledChanged,
              ),
            ],
          ),

          // Este bloco só aparece no estado 4b.
          AnimatedSize(
            duration: transitionDuration,
            curve: AppMotionCurve.standard,
            child: enabled
                ? Column(
                    children: [
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Quantos ajudantes?',
                              style: textTheme.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          _HelperCountButton(
                            icon: Icons.remove_rounded,
                            tooltip: 'Menos um ajudante',
                            enabled: canDecrease,
                            onPressed: onDecrease,
                          ),
                          SizedBox(
                            width: 38,
                            child: Text(
                              helperCount.toString(),
                              textAlign: TextAlign.center,
                              style: textTheme.titleMedium?.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          _HelperCountButton(
                            icon: Icons.add_rounded,
                            tooltip: 'Mais um ajudante',
                            enabled: canIncrease,
                            onPressed: onIncrease,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      // Switch secundário, discreto — não existia no
                      // mockup de referência, mas o campo já existia no
                      // fluxo antigo (helpersEquipmentRequired) e não
                      // podia perder-se.
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Ajudantes trazem equipamento próprio',
                              style: textTheme.labelMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          Transform.scale(
                            scale: 0.8,
                            child: Switch.adaptive(
                              value: equipmentRequired,
                              activeTrackColor: AppColors.primary,
                              activeThumbColor: AppColors.surface,
                              inactiveTrackColor: AppColors.divider,
                              inactiveThumbColor: AppColors.surface,
                              onChanged: onEquipmentRequiredChanged,
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
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? onPressed : null,
      tooltip: tooltip,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.surface,
        foregroundColor: enabled ? AppColors.primary : AppColors.textSecondary,
        disabledForegroundColor: AppColors.textSecondary,
        side: const BorderSide(color: AppColors.divider),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
      ),
      icon: Icon(icon, size: 20),
    );
  }
}

class _SelectionError extends StatelessWidget {
  const _SelectionError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Text(
      message,
      style: textTheme.labelMedium?.copyWith(
        color: AppStatusColor.cancelled.foreground,
      ),
    );
  }
}

class _EmptyOptionsMessage extends StatelessWidget {
  const _EmptyOptionsMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Text(
      message,
      style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
    );
  }
}
