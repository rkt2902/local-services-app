import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart' as native;
import 'package:http/http.dart' as http;

import '../config/app_links.dart';

/// Uma sugestão da pesquisa de morada: [title] é a rua (ou o sítio) e
/// [subtitle] o código postal e a localidade.
class AddressSuggestion {
  const AddressSuggestion({
    required this.title,
    required this.subtitle,
    required this.lat,
    required this.lng,
    this.locality,
  });

  final String title;
  final String subtitle;
  final double lat;
  final double lng;

  /// Cidade, vila ou aldeia, quando a pesquisa a devolve.
  final String? locality;

  /// Texto que fica no campo da morada ao escolher a sugestão.
  String get fullText => subtitle.isEmpty ? title : '$title, $subtitle';
}

/// Respostas do Photon (GeoJSON) → sugestões, só em Portugal e sem
/// repetidos. Pública para os testes.
List<AddressSuggestion> parsePhotonSuggestions(Map<String, dynamic> json) {
  final features = json['features'] as List<dynamic>? ?? const [];
  final out = <AddressSuggestion>[];
  final seen = <String>{};
  for (final f in features) {
    final feature = f as Map<String, dynamic>;
    final props = feature['properties'] as Map<String, dynamic>? ?? const {};
    final code = (props['countrycode'] as String?)?.toUpperCase();
    if (code != null && code != 'PT') continue;
    final coords = (feature['geometry'] as Map<String, dynamic>?)?['coordinates']
        as List<dynamic>?;
    if (coords == null || coords.length < 2) continue;
    final lng = (coords[0] as num).toDouble();
    final lat = (coords[1] as num).toDouble();
    final street = props['street'] as String?;
    final number = props['housenumber'] as String?;
    final name = props['name'] as String?;
    final locality = props['city'] as String? ??
        props['town'] as String? ??
        props['village'] as String? ??
        props['locality'] as String? ??
        props['district'] as String? ??
        props['county'] as String?;
    final title = [
      if (street != null && street.isNotEmpty)
        number != null && number.isNotEmpty ? '$street $number' : street
      else if (name != null && name.isNotEmpty)
        name,
    ].join();
    final subtitle = [
      if (props['postcode'] is String) props['postcode'] as String,
      if (locality != null && locality != title) locality,
    ].join(' ');
    final label = title.isNotEmpty ? title : (locality ?? '');
    if (label.isEmpty) continue;
    final key = '$label|$subtitle';
    if (!seen.add(key)) continue;
    out.add(AddressSuggestion(
      title: label,
      subtitle: label == locality ? '' : subtitle,
      lat: lat,
      lng: lng,
      locality: locality,
    ));
  }
  return out;
}

/// Respostas do Nominatim (`addressdetails=1`) → sugestões. Pública para
/// os testes.
List<AddressSuggestion> parseNominatimSuggestions(List<dynamic> results) {
  final out = <AddressSuggestion>[];
  final seen = <String>{};
  for (final r in results) {
    final m = r as Map<String, dynamic>;
    final lat = double.tryParse(m['lat'] as String? ?? '');
    final lng = double.tryParse(m['lon'] as String? ?? '');
    if (lat == null || lng == null) continue;
    final a = m['address'] as Map<String, dynamic>? ?? const {};
    final locality = a['city'] as String? ??
        a['town'] as String? ??
        a['village'] as String? ??
        a['municipality'] as String? ??
        a['county'] as String?;
    final road = a['road'] as String?;
    final number = a['house_number'] as String?;
    final title = road != null
        ? (number != null ? '$road $number' : road)
        : ((m['name'] as String?)?.isNotEmpty ?? false)
            ? m['name'] as String
            : (locality ?? (m['display_name'] as String? ?? ''));
    if (title.isEmpty) continue;
    final subtitle = [
      if (a['postcode'] is String) a['postcode'] as String,
      if (locality != null && locality != title) locality,
    ].join(' ');
    if (!seen.add('$title|$subtitle')) continue;
    out.add(AddressSuggestion(
      title: title,
      subtitle: subtitle,
      lat: lat,
      lng: lng,
      locality: locality,
    ));
  }
  return out;
}

class GeocodingService {
  static const String _photonUrl = 'https://photon.komoot.io/api/';

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
  /// Usa primeiro [suggestAddresses]. Sem resultado, no telemóvel usa o
  /// geocoder do sistema (package `geocoding`) e na web a pesquisa do
  /// Nominatim, limitada a Portugal.
  static Future<({double lat, double lng})?> searchAddress(String text) async {
    // Primeiro a mesma pesquisa das sugestões (mais tolerante a moradas
    // incompletas); só sem resultado é que segue como antes.
    try {
      final suggestions = await suggestAddresses(text, limit: 1);
      if (suggestions.isNotEmpty) {
        return (lat: suggestions.first.lat, lng: suggestions.first.lng);
      }
    } catch (_) {}
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

  /// Sugestões enquanto se escreve (até [limit]). Primeiro o Photon (feito
  /// para pesquisa à medida que se escreve: aceita moradas incompletas e
  /// erros pequenos), perto de [nearLat]/[nearLng] quando há; se falhar ou
  /// vier vazio, o Nominatim. Lista vazia sem resultados; lança só se os
  /// dois falharem por rede.
  static Future<List<AddressSuggestion>> suggestAddresses(
    String text, {
    double? nearLat,
    double? nearLng,
    int limit = 5,
  }) async {
    final query = text.trim();
    if (query.length < 3) return const [];
    Object? photonError;
    try {
      final uri = Uri.parse(_photonUrl).replace(queryParameters: {
        'q': query,
        'limit': '${limit * 2}',
        // Sem coordenadas, puxa para o centro de Portugal continental.
        'lat': '${nearLat ?? 39.6}',
        'lon': '${nearLng ?? -8.0}',
      });
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final found = parsePhotonSuggestions(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
        if (found.isNotEmpty) return found.take(limit).toList();
      } else {
        photonError = Exception('Photon HTTP ${response.statusCode}');
      }
    } catch (e) {
      photonError = e;
    }
    try {
      final uri = Uri.parse(_nominatimSearchUrl).replace(queryParameters: {
        'q': query,
        'format': 'json',
        'limit': '$limit',
        'countrycodes': 'pt',
        'accept-language': 'pt',
        'addressdetails': '1',
      });
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('Nominatim search HTTP ${response.statusCode}');
      }
      return parseNominatimSuggestions(
        jsonDecode(response.body) as List<dynamic>,
      );
    } catch (e) {
      debugPrint('GeocodingService.suggestAddresses: $photonError / $e');
      rethrow;
    }
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
