import 'package:intl/intl.dart';

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
