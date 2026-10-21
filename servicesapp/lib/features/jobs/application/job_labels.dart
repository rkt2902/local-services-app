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

  final area = _areaOf(job);
  if (area.isNotEmpty) parts.add(area);

  final date = job.confirmedDate ?? job.preferredDate;
  parts.add(date != null
      ? fmt.format(date)
      : 'pedido a ${fmt.format(job.createdAt)}');

  return parts.join(' · ');
}

String _areaOf(JobRequest job) {
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
