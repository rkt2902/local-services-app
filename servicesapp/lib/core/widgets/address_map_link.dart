import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AddressMapLink extends StatelessWidget {
  const AddressMapLink({
    super.key,
    required this.address,
    required this.lat,
    required this.lng,
  });

  final String address;
  final double lat;
  final double lng;

  /// Abre o Google Maps (app ou browser) nestas coordenadas. Público para
  /// ecrãs que querem um botão próprio em vez do link com a morada.
  static Future<void> openInMaps(double lat, double lng) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent('$lat,$lng')}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openMaps() => openInMaps(lat, lng);

  @override
  Widget build(BuildContext context) {
    if (lat == 0 && lng == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final label = address.isNotEmpty ? address : 'Ver no mapa';
    return InkWell(
      onTap: _openMaps,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.map_outlined,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Localização',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      decoration: TextDecoration.underline,
                      decorationColor: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.open_in_new,
                size: 14,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
