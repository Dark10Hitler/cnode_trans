import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class PlaceSearchResult {
  final String name;
  final String description;
  final double latitude;
  final double longitude;

  PlaceSearchResult({
    required this.name,
    required this.description,
    required this.latitude,
    required this.longitude,
  });
}

class GeocodingService {
  // Заголовок User-Agent ОБЯЗАТЕЛЕН для OSM/Photon/Nominatim, иначе сервер возвращает 403
  static const Map<String, String> _headers = {
    'User-Agent': 'CNodeTransApp/1.0 (contact: support@cnode.com)',
    'Accept': 'application/json',
  };

  Future<List<PlaceSearchResult>> searchPlaces(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final encodedQuery = Uri.encodeComponent(cleanQuery);

    // 1. Основная попытка: Photon API
    try {
      final url = Uri.parse('https://photon.komoot.io/api/?q=$encodedQuery&limit=5');
      debugPrint('[GEOCODING] Запрос к Photon: $url');

      final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 4));
      debugPrint('[GEOCODING] Photon Status Code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final features = data['features'] as List<dynamic>? ?? [];

        if (features.isNotEmpty) {
          return features.map((f) {
            final props = f['properties'] as Map<String, dynamic>;
            final geometry = f['geometry'] as Map<String, dynamic>;
            final coords = geometry['coordinates'] as List<dynamic>;

            final name = props['name'] ?? props['city'] ?? props['state'] ?? cleanQuery;
            final country = props['country'] ?? '';
            final state = props['state'] ?? '';
            final city = props['city'] ?? '';

            final descParts = [city, state, country]
                .where((s) => s.toString().isNotEmpty && s != name)
                .toList();

            return PlaceSearchResult(
              name: name.toString(),
              description: descParts.join(', '),
              latitude: (coords[1] as num).toDouble(),
              longitude: (coords[0] as num).toDouble(),
            );
          }).toList();
        }
      }
    } catch (e) {
      debugPrint('[GEOCODING Error - Photon]: $e');
    }

    // 2. Резервная попытка: Nominatim OpenStreetMap API
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=$encodedQuery&format=json&limit=5&addressdetails=1',
      );
      debugPrint('[GEOCODING] Запрос к Nominatim: $url');

      final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 4));
      debugPrint('[GEOCODING] Nominatim Status Code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        return data.map((item) {
          final displayName = item['display_name'] as String? ?? '';
          final parts = displayName.split(',');
          final firstName = parts.isNotEmpty ? parts.first.trim() : cleanQuery;
          final restDesc = parts.length > 1 ? parts.sublist(1).join(',').trim() : '';

          return PlaceSearchResult(
            name: firstName,
            description: restDesc,
            latitude: double.parse(item['lat'].toString()),
            longitude: double.parse(item['lon'].toString()),
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('[GEOCODING Error - Nominatim]: $e');
    }

    return [];
  }
}