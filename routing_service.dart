import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/rig_profile.dart';

class LatLngPoint {
  final double latitude;
  final double longitude;

  LatLngPoint(this.latitude, this.longitude);
}

class RouteResult {
  final double distanceKm;
  final Duration duration;
  final List<LatLngPoint> points;
  final List<String> restrictions;

  RouteResult({
    required this.distanceKm,
    required this.duration,
    required this.points,
    required this.restrictions,
  });

  /// Фабрика для парсинга JSON-ответа от Valhalla (онлайн или локального C++ движка)
  factory RouteResult.fromValhallaJson(Map<String, dynamic> json) {
    try {
      final trip = json['trip'] as Map<String, dynamic>?;
      if (trip == null) {
        return RouteResult(
          distanceKm: 0.0,
          duration: Duration.zero,
          points: [],
          restrictions: [],
        );
      }

      final summary = trip['summary'] as Map<String, dynamic>? ?? {};
      final double distanceKm = (summary['length'] as num?)?.toDouble() ?? 0.0;
      final double durationSeconds = (summary['time'] as num?)?.toDouble() ?? 0.0;

      final List<LatLngPoint> pointsList = [];
      final List<String> restrictionsList = [];

      final legs = trip['legs'] as List<dynamic>? ?? [];
      for (var leg in legs) {
        if (leg is Map<String, dynamic>) {
          // Декодируем геометрию (Shape)
          final shapeStr = leg['shape'] as String?;
          if (shapeStr != null) {
            pointsList.addAll(_decodePolyline(shapeStr));
          }

          // Собираем предупреждения и ограничения из маневров
          final maneuvers = leg['maneuvers'] as List<dynamic>? ?? [];
          for (var m in maneuvers) {
            if (m is Map<String, dynamic>) {
              final verbalAlert = m['verbal_pre_transition_instruction'] as String?;
              if (verbalAlert != null && verbalAlert.toLowerCase().contains('restriction')) {
                restrictionsList.add(verbalAlert);
              }
            }
          }
        }
      }

      return RouteResult(
        distanceKm: distanceKm,
        duration: Duration(seconds: durationSeconds.round()),
        points: pointsList,
        restrictions: restrictionsList,
      );
    } catch (e) {
      debugPrint('Ошибка декодирования Valhalla JSON: $e');
      return RouteResult(
        distanceKm: 0.0,
        duration: Duration.zero,
        points: [],
        restrictions: [],
      );
    }
  }

  /// Декодер Precision 6 (Valhalla polyline shape)
  static List<LatLngPoint> _decodePolyline(String encoded) {
    List<LatLngPoint> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLngPoint(lat / 1e6, lng / 1e6));
    }
    return points;
  }
}

abstract class RoutingService {
  Future<RouteResult> buildRoute({
    required LatLngPoint origin,
    required LatLngPoint destination,
    required RigProfile rig,
  });
}

class ValhallaRoutingService implements RoutingService {
  final String baseUrl;

  ValhallaRoutingService({this.baseUrl = 'https://valhalla1.openstreetmap.de/route'});

  @override
  Future<RouteResult> buildRoute({
    required LatLngPoint origin,
    required LatLngPoint destination,
    required RigProfile rig,
  }) async {
    final rigValhallaConfig = rig.toValhallaJson();
    final costing = rigValhallaConfig['costing'] as String;
    final costingOptions = rigValhallaConfig['costing_options'] as Map<String, dynamic>;

    final body = {
      "locations": [
        {"lat": origin.latitude, "lon": origin.longitude},
        {"lat": destination.latitude, "lon": destination.longitude}
      ],
      "costing": costing,
      "costing_options": costingOptions,
      "directions_options": {
        "units": "kilometers",
        "language": "ru-RU"
      }
    };

    final response = await http.post(
      Uri.parse(baseUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      final errorJson = jsonDecode(response.body);
      final errorMsg = errorJson['error'] ?? response.body;
      debugPrint('[VALHALLA ERROR] ${response.statusCode}: $errorMsg');
      throw Exception('Не удалось построить маршрут: $errorMsg');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    // Используем единую фабрику парсинга
    return RouteResult.fromValhallaJson(data);
  }
}