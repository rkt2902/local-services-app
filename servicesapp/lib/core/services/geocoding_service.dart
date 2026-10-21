import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart' as native;
import 'package:http/http.dart' as http;

import '../config/app_links.dart';

class GeocodingService {
  static const String _nominatimUrl =
      'https://nominatim.openstreetmap.org/reverse';
  static const String _nominatimSearchUrl =
      'https://nominatim.openstreetmap.org/search';

  /// No browser não se pode mudar o `User-Agent` (e um header extra obriga
  /// a um preflight CORS); o Nominatim identifica a app pelo `Referer`.
  static Map<String, String> get _headers => kIsWeb
      ? const {}
      : {'User-Agent': 'ProJardim/1.0 (${AppLinks.publicDomain})'};

  /// Morada escrita → coordenadas. `null` se não houver resultado; lança em
  /// erro de rede para o ecrã mostrar "Erro ao pesquisar morada".
  ///
  /// No telemóvel usa o geocoder do sistema (package `geocoding`, como
  /// sempre). Na web esse package não existe, por isso usa a pesquisa do
  /// Nominatim, limitada a Portugal.
  static Future<({double lat, double lng})?> searchAddress(String text) async {
    if (!kIsWeb) {
      final locations = await native.locationFromAddress(text);
      if (locations.isEmpty) return null;
      return (lat: locations.first.latitude, lng: locations.first.longitude);
    }
    final uri = Uri.parse(_nominatimSearchUrl).replace(queryParameters: {
      'q': text,
      'format': 'json',
      'limit': '1',
      'countrycodes': 'pt',
      'accept-language': 'pt',
    });
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw Exception('Nominatim search HTTP ${response.statusCode}');
    }
    final results = jsonDecode(response.body) as List<dynamic>;
    if (results.isEmpty) return null;
    final first = results.first as Map<String, dynamic>;
    final lat = double.tryParse(first['lat'] as String? ?? '');
    final lng = double.tryParse(first['lon'] as String? ?? '');
    if (lat == null || lng == null) return null;
    return (lat: lat, lng: lng);
  }

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
        // Sem isto a resposta do Nominatim NUNCA tem a chave `address`
        // (só `display_name` + metadados) — era por isto que
        // `reverseGeocode` devolvia `null` em 100% dos pedidos, não só
        // ocasionalmente por falha de rede. Confirmado na documentação
        // da própria API: o objeto `address` estruturado (road,
        // house_number, city, ...) só vem incluído quando
        // `addressdetails=1` é pedido explicitamente.
        'addressdetails': '1',
      });
      final response = await http.get(
        uri,
        // User-Agent identificável, sem domínio-placeholder — Nominatim
        // documenta que bloqueia/penaliza tráfego com identificação que
        // pareça genérica ou de exemplo (ex.: `example.com`).
        headers: _headers,
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        debugPrint(
          'GeocodingService.reverseGeocode: HTTP ${response.statusCode} — '
          '${response.body}',
        );
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final address = data['address'] as Map<String, dynamic>?;
      if (address == null) {
        debugPrint(
          'GeocodingService.reverseGeocode: resposta sem "address" — '
          '${response.body}',
        );
        return null;
      }

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
    } catch (e) {
      debugPrint('GeocodingService.reverseGeocode: falhou — $e');
      return null;
    }
  }
}
