import '../../../core/config/storage_urls.dart';

// Leituras do pedido direto ("Pedir de novo", migration 0057). Cada uma
// vem de uma RPC que só recebe o id do pedido; a identidade é sempre a do
// utilizador com sessão.

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

/// `get_repeat_hire_for_job`: o jardineiro de um trabalho concluído do
/// cliente, para o cartão "Precisas outra vez?".
class RepeatHireInfo {
  const RepeatHireInfo({
    required this.workerId,
    required this.workerName,
    required this.workerAvatarUrl,
    required this.serviceTypeId,
    required this.jobDate,
    required this.canRequest,
    required this.myStars,
  });

  final String workerId;
  final String workerName;

  /// Vazio sem foto.
  final String workerAvatarUrl;
  final String serviceTypeId;
  final DateTime? jobDate;

  /// `false` quando o jardineiro já não tem perfil (não aceita pedidos).
  final bool canRequest;

  /// Nota que o cliente deu neste trabalho, `null` se ainda não avaliou.
  final int? myStars;

  factory RepeatHireInfo.fromJson(Map<String, dynamic> json) => RepeatHireInfo(
        workerId: json['worker_id'] as String,
        workerName: json['worker_name'] as String? ?? '',
        workerAvatarUrl:
            StorageUrls.trustedOrEmpty(json['worker_avatar_url'] as String?),
        serviceTypeId: json['service_type_id'] as String,
        jobDate: _date(json['job_date']),
        canRequest: json['can_request'] as bool? ?? false,
        myStars: json['my_stars'] as int?,
      );
}

/// `get_my_previous_workers`: uma linha de "Os teus jardineiros".
class PreviousWorker {
  const PreviousWorker({
    required this.workerId,
    required this.workerName,
    required this.workerAvatarUrl,
    required this.lastJobId,
    required this.serviceTypeId,
    required this.jobDate,
  });

  final String workerId;
  final String workerName;
  final String workerAvatarUrl;

  /// Último trabalho concluído com este jardineiro: é a origem do pedido.
  final String lastJobId;
  final String serviceTypeId;
  final DateTime? jobDate;

  factory PreviousWorker.fromJson(Map<String, dynamic> json) => PreviousWorker(
        workerId: json['worker_id'] as String,
        workerName: json['worker_name'] as String? ?? '',
        workerAvatarUrl:
            StorageUrls.trustedOrEmpty(json['worker_avatar_url'] as String?),
        lastJobId: json['last_job_id'] as String,
        serviceTypeId: json['service_type_id'] as String,
        jobDate: _date(json['job_date']),
      );
}

/// `get_direct_request_context`: o trabalho anterior com este cliente, para
/// o jardineiro escolhido ("Já trabalhaste com...").
class DirectRequestContext {
  const DirectRequestContext({
    required this.clientName,
    required this.jobDate,
    required this.serviceTypeId,
    required this.hourlyRate,
  });

  final String clientName;
  final DateTime? jobDate;
  final String serviceTypeId;
  final double? hourlyRate;

  factory DirectRequestContext.fromJson(Map<String, dynamic> json) =>
      DirectRequestContext(
        clientName: json['client_name'] as String? ?? '',
        jobDate: _date(json['job_date']),
        serviceTypeId: json['service_type_id'] as String,
        hourlyRate: (json['hourly_rate'] as num?)?.toDouble(),
      );
}
