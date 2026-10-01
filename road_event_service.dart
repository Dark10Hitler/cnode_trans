import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/rig_profile.dart';
import '../models/road_event.dart';

class RoadEventService {
  static final RoadEventService instance = RoadEventService._internal();
  RoadEventService._internal();

  Database? _db;
  bool _isInitialized = false;

  /// Инициализация и подготовка базы данных SQLite с поддержкой R*Tree
  Future<void> init() async {
    if (_isInitialized && _db != null && _db!.isOpen) {
      debugPrint('[🔹 RoadEventService] ✓ Database already initialized');
      return;
    }

    try {
      debugPrint('[🔹 RoadEventService] Starting initialization...');

      // 1. Гарантируем инициализацию FFI для поддержки R*Tree
      if (Platform.isAndroid || Platform.isIOS) {
        debugPrint('[🔹 RoadEventService] Platform: ${Platform.operatingSystem}');
        sqfliteFfiInit();
        // Используем databaseFactoryFfi вместо обычного databaseFactory!
        final factory = databaseFactoryFfi;
        debugPrint('[🔹 RoadEventService] ✓ FFI factory initialized');
      }

      // 2. Получаем правильный путь к БД
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, "cameras.db");
      debugPrint('[🔹 RoadEventService] Database path: $path');

      // 3. Создаем папку, если её нет
      await Directory(dbPath).create(recursive: true);

      // 4. Если БД не существует — копируем из assets
      if (!await File(path).exists()) {
        debugPrint('[🔹 RoadEventService] Copying cameras.db from assets...');
        try {
          final data = await rootBundle.load("assets/database/cameras.db");
          final bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          await File(path).writeAsBytes(bytes, flush: true);
          debugPrint('[🔹 RoadEventService] ✓ cameras.db copied (${bytes.length} bytes)');
        } catch (e) {
          debugPrint('[🔹 RoadEventService] ✗ Failed to copy from assets: $e');
          rethrow;
        }
      } else {
        final fileSize = await File(path).length();
        debugPrint('[🔹 RoadEventService] ✓ cameras.db exists (${fileSize} bytes)');
      }

      // 5. КРИТИЧНО: Открываем БД через databaseFactoryFfi, а не openDatabase()!
      debugPrint('[🔹 RoadEventService] Opening database via FFI...');
      _db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          readOnly: true,
          onOpen: (db) async {
            debugPrint('[🔹 RoadEventService] ✓ Database opened successfully');

            // Проверяем таблицы
            try {
              final tables = await db.query(
                'sqlite_master',
                where: "type='table' AND name LIKE '%speed_cameras%'",
                columns: ['name'],
              );

              debugPrint('[🔹 RoadEventService] Found ${tables.length} speed_cameras tables:');
              for (final table in tables) {
                debugPrint('[🔹 RoadEventService]   • ${table['name']}');
              }

              // Проверяем R*Tree индекс
              final rtreeCheck = await db.query(
                'sqlite_master',
                where: "type='table' AND name='speed_cameras_rtree'",
                columns: ['name'],
              );

              if (rtreeCheck.isNotEmpty) {
                debugPrint('[🔹 RoadEventService] ✓ R*Tree index FOUND and available');
              } else {
                debugPrint('[🔹 RoadEventService] ⚠ R*Tree index NOT found');
              }

              // Тестовый запрос
              try {
                final testResult = await db.rawQuery(
                  'SELECT COUNT(*) as cnt FROM speed_cameras LIMIT 1'
                );
                final count = (testResult.first['cnt'] as int?) ?? 0;
                debugPrint('[🔹 RoadEventService] ✓ Total cameras in DB: $count');
              } catch (e) {
                debugPrint('[🔹 RoadEventService] ⚠ Test query failed: $e');
              }
            } catch (e) {
              debugPrint('[🔹 RoadEventService] ⚠ Table check error: $e');
            }
          },
        ),
      );

      _isInitialized = true;
      debugPrint('[🔹 RoadEventService] ✅ INITIALIZATION COMPLETE!');
    } catch (e, stackTrace) {
      debugPrint('[🔹 RoadEventService] ❌ CRITICAL ERROR: $e');
      debugPrint('[🔹 RoadEventService] Stack: $stackTrace');
      _isInitialized = false;
      rethrow;
    }
  }

  /// Проверка подключения к БД с авто-инициализацией
  Future<void> _ensureInitialized() async {
    if (_isInitialized && _db != null && _db!.isOpen) {
      return;
    }

    debugPrint('[🔹 RoadEventService] Auto-initializing...');
    await init();
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
    if (_db == null || !_db!.isOpen) {
      debugPrint('[🔹 RoadEventService] ✗ Database not initialized for bounds query');
      return [];
    }

    try {
      debugPrint('[🔹 RoadEventService] Query bounds: lat($minLat-$maxLat) lon($minLon-$maxLon)');

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

      debugPrint('[🔹 RoadEventService] Found ${rawRows.length} events in bounds');

      final List<RoadEvent> events = [];

      for (final row in rawRows) {
        try {
          final event = RoadEvent.fromSqflite(row);

          if (_shouldIncludeEvent(event, activeRig)) {
            events.add(event);
          }
        } catch (e) {
          debugPrint('[🔹 RoadEventService] Error parsing event: $e');
        }
      }

      debugPrint('[🔹 RoadEventService] ✓ Returning ${events.length} filtered events');
      return events;
    } catch (e, stackTrace) {
      debugPrint('[🔹 RoadEventService] ✗ Error in getEventsInBounds: $e');
      debugPrint('[🔹 RoadEventService] Stack: $stackTrace');
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
    if (_db == null || !_db!.isOpen || routePoints.isEmpty) {
      debugPrint('[🔹 RoadEventService] ✗ Database not ready or empty route');
      return [];
    }

    // Безопасно приводим входные точки к объектам LatLng
    final List<LatLng> parsedPoints = _parsePoints(routePoints);
    if (parsedPoints.isEmpty) {
      debugPrint('[🔹 RoadEventService] ✗ No valid points in route');
      return [];
    }

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
      debugPrint('[🔹 RoadEventService] Query route: lat($minLat-$maxLat) lon($minLon-$maxLon)');

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

      debugPrint('[🔹 RoadEventService] Found ${rawRows.length} candidates near route');

      final List<RoadEvent> routeEvents = [];

      for (final row in rawRows) {
        try {
          final event = RoadEvent.fromSqflite(row);

          // Проверка прилегания объекта к линии маршрута (до 35 метров)
          if (_isNearPolyline(event.lat, event.lon, parsedPoints, maxDistanceMeters: 35.0)) {
            // 3. ФИЛЬТРАЦИЯ: Легковой vs Грузовой
            if (_shouldIncludeEvent(event, activeRig)) {
              routeEvents.add(event);
              debugPrint('[🔹 RoadEventService]   • Found: ${event.type.name} at (${event.lat}, ${event.lon})');
            }
          }
        } catch (e) {
          debugPrint('[🔹 RoadEventService] Error parsing route event: $e');
        }
      }

      debugPrint('[🔹 RoadEventService] ✓ Returning ${routeEvents.length} route events');
      return routeEvents;
    } catch (e, stackTrace) {
      debugPrint('[🔹 RoadEventService] ✗ Error in getEventsForRoute: $e');
      debugPrint('[🔹 RoadEventService] Stack: $stackTrace');
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

  /// Закрытие БД при выходе из приложения
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
      _isInitialized = false;
      debugPrint('[🔹 RoadEventService] Database closed');
    }
  }
}
