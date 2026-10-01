import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/rig_profile.dart';
import 'routing_service.dart';
import 'valhalla_bindings.dart';
import 'valhalla_init_service.dart';

class OfflineRoutingService implements RoutingService {
  final ValhallaBindings _valhalla;
  bool _isInitialized = false;

  OfflineRoutingService(this._valhalla);

  /// Инициализация C++ движка
  Future<void> init() async {
    if (_isInitialized) return;

    final tarPath = await ValhallaInitService.prepareTiles();

    final configMap = {
      "mjolnir": {
        "tile_extract": tarPath,
      },
      "loki": {
        "actions": ["route"],
      },
      "thor": {},
    };

    try {
      _valhalla.init(jsonEncode(configMap));
      _isInitialized = true;
      debugPrint('OfflineRoutingService: Valhalla успешно инициализирована!');
    } catch (e) {
      debugPrint('OfflineRoutingService: Ошибка инициализации: $e');
    }
  }

  /// Адаптер под единый интерфейс RoutingService
  @override
  Future<RouteResult> buildRoute({
    required LatLngPoint origin,
    required LatLngPoint destination,
    required RigProfile rig,
  }) async {
    final rawResult = await route(
      waypoints: [
        LatLng(origin.latitude, origin.longitude),
        LatLng(destination.latitude, destination.longitude),
      ],
      profile: rig,
    );

    if (rawResult == null) {
      throw Exception('Не удалось построить офлайн-маршрут (Valhalla вернула null).');
    }

    // Парсим результат от Valhalla в общую модель RouteResult
    return RouteResult.fromValhallaJson(rawResult);
  }

  /// Прямой вызов построения маршрута
  Future<Map<String, dynamic>?> route({
    required List<LatLng> waypoints,
    required RigProfile profile,
  }) async {
    if (!_isInitialized) {
      await init();
    }

    if (waypoints.length < 2) return null;

    final locations = waypoints
        .map((point) => {
      'lat': point.latitude,
      'lon': point.longitude,
    })
        .toList();

    final profileJson = profile.toValhallaJson();

    final requestMap = {
      'locations': locations,
      'costing': profileJson['costing'],
      'costing_options': profileJson['costing_options'],
      'directions_options': {
        'units': 'kilometers',
        'language': 'ru-RU',
      },
    };

    final requestJsonString = jsonEncode(requestMap);

    try {
      final responseString = await compute(
        _routeInIsolate,
        _RouteParam(_valhalla, requestJsonString),
      );

      if (responseString == null || responseString.isEmpty) return null;

      return jsonDecode(responseString) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Ошибка построения маршрута: $e');
      return null;
    }
  }
}

class _RouteParam {
  final ValhallaBindings valhalla;
  final String requestJson;

  _RouteParam(this.valhalla, this.requestJson);
}

String? _routeInIsolate(_RouteParam param) {
  return param.valhalla.route(param.requestJson);
}