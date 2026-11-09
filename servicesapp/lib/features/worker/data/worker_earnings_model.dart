import '../../../core/constants/enums.dart';

/// Uma linha de `get_my_earnings` (migration 0067): um trabalho feito pelo
/// próprio, como responsável ou como ajudante.
class WorkerEarningEntry {
  const WorkerEarningEntry({
    required this.jobId,
    required this.asHelper,
    required this.serviceName,
    required this.doneOn,
    required this.awaitingConfirmation,
    required this.pricingMode,
    required this.rate,
    this.totalPrice,
    this.workedMinutes,
    this.estimatedHoursMin,
    this.estimatedHoursMax,
    this.helpersCost,
  });

  final String jobId;

  /// Ajudante (paga por `agreed_rate`) ou responsável.
  final bool asHelper;
  final String serviceName;

  /// Dia em que foi marcado como feito (hora de Lisboa).
  final DateTime doneOn;

  /// Feito mas ainda à espera da confirmação do cliente.
  final bool awaitingConfirmation;
  final ProposalPricingMode pricingMode;

  /// €/h: o da proposta (responsável) ou o acordado (ajudante).
  final double rate;

  /// Só no valor total fechado.
  final double? totalPrice;

  /// Tempo registado; `null` sem "Iniciar" registado.
  final int? workedMinutes;
  final double? estimatedHoursMin;
  final double? estimatedHoursMax;

  /// Só responsável: o que vai para os ajudantes, pelas horas registadas.
  final double? helpersCost;

  factory WorkerEarningEntry.fromJson(Map<String, dynamic> json) {
    double? num_(String key) => (json[key] as num?)?.toDouble();
    return WorkerEarningEntry(
      jobId: json['job_id'] as String,
      asHelper: json['role'] == 'helper',
      serviceName: json['service_type_name'] as String? ?? 'Trabalho',
      doneOn: DateTime.parse(json['done_on'] as String),
      awaitingConfirmation: json['job_status'] == 'awaiting_confirmation',
      pricingMode:
          ProposalPricingMode.fromString(json['pricing_mode'] as String?),
      rate: num_('rate') ?? 0,
      totalPrice: num_('total_price'),
      workedMinutes: (json['worked_minutes'] as num?)?.toInt(),
      estimatedHoursMin: num_('estimated_hours_min'),
      estimatedHoursMax: num_('estimated_hours_max'),
      helpersCost: num_('helpers_cost'),
    );
  }
}
