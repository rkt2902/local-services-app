import 'dart:convert';
import 'package:http/http.dart' as http;

class GeocodingService {
  static const String _nominatimUrl =
      'https://nominatim.openstreetmap.org/reverse';

  /// Returns {locationName, addressText} from lat/lng via Nominatim.
  /// locationName = city or town (for public display, no street)
  /// addressText = full human-readable address (for job address_text)
  /// Returns null on any error — callers must handle gracefully.
  static Future<({String locationName, String addressText})?> reverseGeocode(
    double lat,
    double lng,
  ) async {
    try {
      final uri = Uri.parse(_nominatimUrl).replace(queryParameters: {
        'lat': lat.toString(),
        'lon': lng.toString(),
        'format': 'json',
        'accept-language': 'pt',
      });
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'ProJardim/1.0 (projardim@example.com)'},
      );
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final address = data['address'] as Map<String, dynamic>?;
      if (address == null) return null;

      // locationName: most specific populated place name available
      final locationName =
          address['city'] as String? ??
          address['town'] as String? ??
          address['village'] as String? ??
          address['county'] as String? ??
          'Portugal';

      // addressText: road + house_number + postcode + city
      final parts = <String>[
        if (address['road'] != null) address['road'] as String,
        if (address['house_number'] != null) address['house_number'] as String,
        if (address['postcode'] != null) address['postcode'] as String,
        locationName,
      ];
      final addressText = parts.join(', ');

      return (locationName: locationName, addressText: addressText);
    } catch (_) {
      return null;
    }
  }
}
