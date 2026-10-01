import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/rig_profile.dart';
import '../models/road_event.dart';

class RoadEventService {
  static final RoadEventService instance = RoadEventService._internal();
  RoadEventService._internal();

  Database? _db;

  /// Инициализация и подготовка базы данных SQLite
  Future<void> init() async {
    if (_db != null && _db!.isOpen) return;

    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, "cameras.db");

      if (!await File(path).exists()) {
        final data = await rootBundle.load("assets/database/cameras.db");
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        await File(path).writeAsBytes(bytes, flush: true);
      }

      _db = await openDatabase(path, readOnly: true);
    } catch (e) {
      debugPrint("Ошибка при инициализации базы данных cameras.db: $e");
    }
  }

  /// Проверка подключения к БД с авто-инициализацией
  Future<void> _ensureInitialized() async {
    if (_db == null || !_db!.isOpen) {
      await init();
    }
  }

  /// 1. Загрузка событий в видимой области экрана (без построенного маршрута)
  Future<List<RoadEvent>> getEventsInBounds({
    required double minLat,
    required double maxLat,
    required double minLon,
    required double maxLon,
    RigProfile? activeRig,
  }) async {
    await _ensureInitialized();
    if (_db == null) return [];

    try {
      const query = '''
        SELECT c.id, c.source, c.external_id, c.lat, c.lon, c.azimuth, c.camera_type, c.speed_limit, c.attributes
        FROM speed_cameras c
        JOIN speed_cameras_rtree r ON c.id = r.id
        WHERE r.min_lon <= ? AND r.max_lon >= ?
          AND r.min_lat <= ? AND r.max_lat >= ?
      ''';

      final List<Map<String, dynamic>> rawRows = await _db!.rawQuery(
        query,
        [maxLon, minLon, maxLat, minLat],
      );

      final List<RoadEvent> events = [];

      for (final row in rawRows) {
        final event = RoadEvent.fromSqflite(row);

        if (_shouldIncludeEvent(event, activeRig)) {
          events.add(event);
        }
      }

      return events;
    } catch (e) {
      debugPrint("Ошибка получения событий в границах экрана: $e");
      return [];
    }
  }

  /// 2. Загрузка событий вдоль построенного маршрута
  /// Принимает списки типа `List<LatLng>`, `List<List<double>>` или любые точки координат
  Future<List<RoadEvent>> getEventsForRoute(
      List<dynamic> routePoints, {
        RigProfile? activeRig,
      }) async {
    await _ensureInitialized();
    if (_db == null || routePoints.isEmpty) return [];

    // Безопасно приводим входные точки к объектам LatLng
    final List<LatLng> parsedPoints = _parsePoints(routePoints);
    if (parsedPoints.isEmpty) return [];

    // 1. Вычисляем Bounding Box всего маршрута
    double minLat = parsedPoints.first.latitude;
    double maxLat = parsedPoints.first.latitude;
    double minLon = parsedPoints.first.longitude;
    double maxLon = parsedPoints.first.longitude;

    for (final pt in parsedPoints) {
      if (pt.latitude < minLat) minLat = pt.latitude;
      if (pt.latitude > maxLat) maxLat = pt.latitude;
      if (pt.longitude < minLon) minLon = pt.longitude;
      if (pt.longitude > maxLon) maxLon = pt.longitude;
    }

    // Буфер охвата (~300 метров)
    minLat -= 0.003;
    maxLat += 0.003;
    minLon -= 0.003;
    maxLon += 0.003;

    try {
      // 2. Выборка через R-Tree
      const query = '''
        SELECT c.id, c.source, c.external_id, c.lat, c.lon, c.azimuth, c.camera_type, c.speed_limit, c.attributes
        FROM speed_cameras c
        JOIN speed_cameras_rtree r ON c.id = r.id
        WHERE r.min_lon <= ? AND r.max_lon >= ?
          AND r.min_lat <= ? AND r.max_lat >= ?
      ''';

      final List<Map<String, dynamic>> rawRows = await _db!.rawQuery(
        query,
        [maxLon, minLon, maxLat, minLat],
      );

      final List<RoadEvent> routeEvents = [];

      for (final row in rawRows) {
        final event = RoadEvent.fromSqflite(row);

        // Проверка прилегания объекта к линии маршрута (до 35 метров)
        if (_isNearPolyline(event.lat, event.lon, parsedPoints, maxDistanceMeters: 35.0)) {
          // 3. ФИЛЬТРАЦИЯ: Легковой vs Грузовой
          if (_shouldIncludeEvent(event, activeRig)) {
            routeEvents.add(event);
          }
        }
      }

      return routeEvents;
    } catch (e) {
      debugPrint("Ошибка получения событий для маршрута: $e");
      return [];
    }
  }

  /// Логика разграничения знаков и ограничений для Авто / Грузовика
  bool _shouldIncludeEvent(RoadEvent event, RigProfile? rig) {
    final double totalWeight = rig?.weightTons ?? rig?.weight ?? 0.0;
    final bool isTruck = rig != null && (rig.trailer != null || totalWeight > 3.5);

    if (event.type == RoadEventType.weightControl) {
      return isTruck;
    }

    if (event.type == RoadEventType.heightLimit) {
      final double rigHeight = rig?.heightM ?? rig?.height ?? 1.8;
      final dynamic rawHeight = event.attributes['height_m'] ?? event.attributes['height'];
      final double limitHeight = (rawHeight as num?)?.toDouble() ?? 4.0;

      return rigHeight >= limitHeight;
    }

    return true;
  }

  /// Универсальное приведение любых форматов точек к LatLng из latlong2
  List<LatLng> _parsePoints(List<dynamic> rawPoints) {
    final List<LatLng> result = [];
    for (final pt in rawPoints) {
      if (pt is LatLng) {
        result.add(pt);
      } else if (pt is List && pt.length >= 2) {
        result.add(LatLng((pt[0] as num).toDouble(), (pt[1] as num).toDouble()));
      } else if (pt != null) {
        try {
          final dynamic lat = (pt as dynamic).latitude;
          final dynamic lon = (pt as dynamic).longitude;
          if (lat is num && lon is num) {
            result.add(LatLng(lat.toDouble(), lon.toDouble()));
          }
        } catch (_) {}
      }
    }
    return result;
  }

  /// Проверка нахождения точки рядом с нитью маршрута
  bool _isNearPolyline(
      double lat,
      double lon,
      List<LatLng> polyline, {
        required double maxDistanceMeters,
      }) {
    for (int i = 0; i < polyline.length - 1; i++) {
      final p1 = polyline[i];
      final p2 = polyline[i + 1];

      final dist = _distanceToSegmentMeters(
        lat, lon,
        p1.latitude, p1.longitude,
        p2.latitude, p2.longitude,
      );

      if (dist <= maxDistanceMeters) {
        return true;
      }
    }
    return false;
  }

  /// Расстояние от точки до отрезка на сфере
  double _distanceToSegmentMeters(
      double lat, double lon,
      double lat1, double lon1,
      double lat2, double lon2,
      ) {
    final d1 = _haversine(lat, lon, lat1, lon1);
    final d2 = _haversine(lat, lon, lat2, lon2);
    final lineLen = _haversine(lat1, lon1, lat2, lon2);

    if (lineLen == 0) return d1;

    final t = ((lat - lat1) * (lat2 - lat1) + (lon - lon1) * (lon2 - lon1)) /
        ((lat2 - lat1) * (lat2 - lat1) + (lon2 - lon1) * (lon2 - lon1));
    final clampedT = t.clamp(0.0, 1.0);

    final projLat = lat1 + clampedT * (lat2 - lat1);
    final projLon = lon1 + clampedT * (lon2 - lon1);

    return _haversine(lat, lon, projLat, projLon);
  }

  /// Вычисление дистанции между двумя точками по формуле гаверсинусов (в метрах)
  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}