import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../data/job_model.dart';

/// Distingue dois pedidos do mesmo serviço sem mostrar o id: zona e data.
/// Ex.: "Braga · 18/10". Usado por baixo do nome do serviço nos títulos.
///
/// Data: a combinada, senão a preferida, senão o dia em que o pedido foi
/// criado ("pedido a 12/10").
String jobDistinguisherLabel(JobRequest job) {
  final fmt = DateFormat('dd/MM');
  final parts = <String>[];

  final area = jobAreaLabel(job);
  if (area.isNotEmpty) parts.add(area);

  final date = job.confirmedDate ?? job.preferredDate;
  parts.add(date != null
      ? fmt.format(date)
      : 'pedido a ${fmt.format(job.createdAt)}');

  return parts.join(' · ');
}

/// Localidade do pedido ("Cascais"), sem a morada exata.
String jobAreaLabel(JobRequest job) {
  final area = job.locationArea?.trim() ?? '';
  if (area.isNotEmpty) return area;
  // Pedidos antigos sem location_area: último segmento da morada.
  final segments = job.addressText.split(',');
  return segments.last.trim();
}

/// `true` a partir do dia do trabalho confirmado (inclusive). Mesma regra
/// do servidor em `cancel_job` e `propose_reschedule`
/// (`confirmed_date - CURRENT_DATE < 1`): compara DATAS, não horas. Um
/// trabalho de amanhã às 9h ainda se pode cancelar hoje às 23h.
/// Remarcação pendente cuja data proposta já passou (0069): a BD recusa
/// aceitá-la e deixa propor outra por cima, por isso já não bloqueia.
bool isStaleReschedule(JobRequest job, {required DateTime now}) {
  final proposed = job.rescheduleProposedDate;
  if (job.rescheduleStatus != RescheduleStatus.pending || proposed == null) {
    return false;
  }
  final day = DateTime(proposed.year, proposed.month, proposed.day);
  return day.isBefore(DateTime(now.year, now.month, now.day));
}

bool isOnOrAfterJobDay(DateTime? confirmedDate, DateTime now) {
  if (confirmedDate == null) return false;
  final jobDay =
      DateTime(confirmedDate.year, confirmedDate.month, confirmedDate.day);
  final today = DateTime(now.year, now.month, now.day);
  return jobDay.difference(today).inDays < 1;
}

/// Legenda de prazo de um pedido `open`, igual às regras de
/// `auto_expire_jobs` (migration 0046):
/// - sem nenhuma proposta, expira em `expires_at` (48h depois de criado);
/// - com data fixa, expira quando a data passa sem proposta aceite.
/// Com propostas e sem data fixa não expira sozinho: `null`.
String? openJobExpiryNotice(JobRequest job) {
  final parts = <String>[];
  if (job.proposalCount == 0) {
    final when = DateFormat("dd/MM 'às' HH:mm").format(job.expiresAt.toLocal());
    parts.add('Expira a $when se não receber nenhuma proposta');
  }
  if (job.dateMode == DateMode.fixed && job.preferredDate != null) {
    final day = DateFormat('dd/MM').format(job.preferredDate!);
    parts.add(parts.isEmpty
        ? 'Expira se nenhuma proposta for aceite até $day'
        : 'ou se nenhuma for aceite até $day');
  }
  if (parts.isEmpty) return null;
  return '${parts.join(', ')}.';
}

/// Data pretendida pelo cliente: a data fixa, o texto de disponibilidade ou
/// "Flexível".
String jobPreferredDateLabel(JobRequest job) {
  if (job.dateMode == DateMode.availability) {
    final text = job.availabilityText?.trim() ?? '';
    return text.isEmpty ? 'A combinar' : text;
  }
  if (job.preferredDate == null) return 'Flexível';
  return DateFormat('dd/MM/yyyy').format(job.preferredDate!);
}

/// Data com que o formulário de proposta abre: a que o cliente escolheu,
/// se ainda não passou. O jardineiro pode sempre trocar.
DateTime? proposalInitialDate(JobRequest job, DateTime now) {
  final date = job.preferredDate;
  if (date == null || job.dateMode == DateMode.availability) return null;
  final day = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  return day.isBefore(today) ? null : day;
}

/// Texto de "Como correu o trabalho?" à espera da confirmação da cliente.
/// Sem relato fica confirmado às 48 horas; com um relato dela feito depois
/// de o jardineiro concluir, só aos 7 dias (`job_has_client_report`, 0071).
String clientAutoConfirmHint({
  required DateTime? markedDoneAt,
  required DateTime? myLatestReportAt,
}) {
  final reported = myLatestReportAt != null &&
      (markedDoneAt == null || !myLatestReportAt.isBefore(markedDoneAt));
  if (!reported) {
    return 'Confirma a conclusão ou reporta um problema. Sem resposta, '
        'fica confirmado automaticamente 48 horas depois de o '
        'jardineiro o dar por concluído. Depois de confirmares, '
        'podes avaliar o jardineiro.';
  }
  final until = markedDoneAt == null
      ? ''
      : ' (a ${DateFormat('dd/MM').format(markedDoneAt.add(const Duration(days: 7)).toLocal())})';
  return 'Recebemos o teu relato. Se não confirmares, o trabalho fica '
      'confirmado automaticamente 7 dias depois de o jardineiro o dar por '
      'concluído$until. Depois de confirmares, podes avaliar o jardineiro.';
}

/// "09:00:00" (time do Postgres) → "09:00". Texto curto fica como está.
String shortTimeLabel(String time) =>
    time.length >= 5 ? time.substring(0, 5) : time;
