import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/address_map_link.dart';

/// Abre a app de mapas no sítio de uma entrada da agenda: as coordenadas,
/// se houver; senão a morada escrita (ou a zona, numa proposta pendente).
Future<void> openAgendaPlace({double? lat, double? lng, String? label}) async {
  if (lat != null && lng != null) {
    await AddressMapLink.openInMaps(lat, lng);
    return;
  }
  final text = label?.trim() ?? '';
  if (text.isEmpty) return;
  await launchUrl(
    Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(text)}',
    ),
    mode: LaunchMode.externalApplication,
  );
}
