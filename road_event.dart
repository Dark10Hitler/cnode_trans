import 'dart:convert';
import 'dart:math';

/// Типы дорожных объектов, предупреждений и камер (OpenSpeedcam / SpeedCamOnline)
enum RoadEventType {
  speedCamera,     // 1: Стационарная камера скорости
  trafficLight,    // 2: Контроль светофора / проезда
  redLight,        // 3: Камера контроля стоп-линии / полосы
  averageSpeed,    // 4, 13: Контроль средней скорости (секция)
  mobileCamera,    // 5: Мобильная засада / передвижная тренога
  speedBump,       // 11: Лежачий полицейский
  pedestrian,      // 12: Пешеходный переход
  railwayCrossing, // 14: Железнодорожный переезд
  weightControl,   // 21: Весовой контроль / Пункт весогабаритного контроля (ПВК)
  heightLimit,     // 22: Ограничение по высоте / низкий мост
  tollBooth,       // 23: Пункт оплаты проезда (ПВП)
  dangerZone,      // 100-107: Опасный участок / опасный поворот / аварийное место
  unknown;         // Неизвестный объект

  /// Человекочитаемое название на русском языке
  String get displayName {
    switch (this) {
      case RoadEventType.speedCamera:
        return 'Камера скорости';
      case RoadEventType.trafficLight:
        return 'Светофор контроля';
      case RoadEventType.redLight:
        return 'Контроль светофора и разметки';
      case RoadEventType.averageSpeed:
        return 'Контроль средней скорости';
      case RoadEventType.mobileCamera:
        return 'Передвижная камера';
      case RoadEventType.speedBump:
        return 'Искусственная неровность';
      case RoadEventType.pedestrian:
        return 'Пешеходный переход';
      case RoadEventType.railwayCrossing:
        return 'Железнодорожный переезд';
      case RoadEventType.weightControl:
        return 'Весовой контроль (ПВК)';
      case RoadEventType.heightLimit:
        return 'Ограничение по высоте';
      case RoadEventType.tollBooth:
        return 'Пункт оплаты (ПВП)';
      case RoadEventType.dangerZone:
        return 'Опасный участок';
      case RoadEventType.unknown:
        return 'Дорожное предупреждение';
    }
  }

  /// Флаг: является ли объект критически важным для грузового транспорта
  bool get isTruckCritical {
    return this == RoadEventType.weightControl ||
        this == RoadEventType.heightLimit ||
        this == RoadEventType.tollBooth;
  }

  /// Безопасное преобразование из любых типов SQLite (число, строка, код OpenSpeedcam)
  static RoadEventType fromDynamic(dynamic rawType) {
    if (rawType == null) return RoadEventType.unknown;

    final String cleanStr = rawType.toString().trim().toLowerCase();

    // 1. Проверка по числовым кодам OpenSpeedcam / SpeedCamOnline / iGO
    switch (cleanStr) {
      case '1':
        return RoadEventType.speedCamera;
      case '2':
        return RoadEventType.trafficLight;
      case '3':
        return RoadEventType.redLight;
      case '4':
      case '13':
        return RoadEventType.averageSpeed;
      case '5':
        return RoadEventType.mobileCamera;
      case '11':
        return RoadEventType.speedBump;
      case '12':
        return RoadEventType.pedestrian;
      case '14':
        return RoadEventType.railwayCrossing;
      case '21':
        return RoadEventType.weightControl;
      case '22':
        return RoadEventType.heightLimit;
      case '23':
        return RoadEventType.tollBooth;
      case '100':
      case '101':
      case '102':
      case '103':
      case '104':
      case '105':
      case '106':
      case '107':
        return RoadEventType.dangerZone;
    }

    // 2. Проверка по строковым текстовым названиям
    switch (cleanStr) {
      case 'static':
      case 'speed_camera':
      case 'camera':
      case 'speedcamera':
        return RoadEventType.speedCamera;
      case 'traffic_light':
      case 'trafficlight':
        return RoadEventType.trafficLight;
      case 'red_light':
      case 'redlight':
      case 'stop_line':
        return RoadEventType.redLight;
      case 'average_speed':
      case 'average':
      case 'averagespeed':
        return RoadEventType.averageSpeed;
      case 'mobile':
      case 'mobile_camera':
      case 'mobilecamera':
      case 'ambush':
        return RoadEventType.mobileCamera;
      case 'speed_bump':
      case 'speedbump':
      case 'bump':
        return RoadEventType.speedBump;
      case 'pedestrian':
      case 'crosswalk':
        return RoadEventType.pedestrian;
      case 'railway':
      case 'railway_crossing':
      case 'railroad':
        return RoadEventType.railwayCrossing;
      case 'weight':
      case 'weight_control':
      case 'pvk':
        return RoadEventType.weightControl;
      case 'danger':
      case 'danger_zone':
      case 'warning':
        return RoadEventType.dangerZone;
      case 'toll':
      case 'toll_booth':
      case 'pvp':
        return RoadEventType.tollBooth;
      case 'height':
      case 'height_limit':
      case 'low_bridge':
        return RoadEventType.heightLimit;
      default:
        return RoadEventType.unknown;
    }
  }

  /// Преобразование из строкового значения (обратная совместимость)
  static RoadEventType fromString(String? typeStr) {
    return fromDynamic(typeStr);
  }

  /// Преобразование в строковый идентификатор для сохранения в БД
  String toDbString() {
    switch (this) {
      case RoadEventType.speedCamera:
        return 'static';
      case RoadEventType.trafficLight:
        return 'traffic_light';
      case RoadEventType.redLight:
        return 'red_light';
      case RoadEventType.averageSpeed:
        return 'average_speed';
      case RoadEventType.mobileCamera:
        return 'mobile';
      case RoadEventType.speedBump:
        return 'speed_bump';
      case RoadEventType.pedestrian:
        return 'pedestrian';
      case RoadEventType.railwayCrossing:
        return 'railway';
      case RoadEventType.weightControl:
        return 'weight';
      case RoadEventType.dangerZone:
        return 'danger';
      case RoadEventType.tollBooth:
        return 'toll';
      case RoadEventType.heightLimit:
        return 'height';
      case RoadEventType.unknown:
        return 'unknown';
    }
  }
}

/// Универсальная модель дорожного события / камеры / объекта для карты и ИИ
class RoadEvent {
  final int id;
  final String source;
  final String? externalId;
  final double lat;
  final double lon;
  final int azimuth; // Направление контроля в градусах (0..360), или -1 (во все стороны)
  final RoadEventType type;
  final int speedLimit; // Ограничение скорости в км/ч (0, если нет)
  final Map<String, dynamic> attributes;

  const RoadEvent({
    required this.id,
    required this.source,
    this.externalId,
    required this.lat,
    required this.lon,
    required this.azimuth,
    required this.type,
    required this.speedLimit,
    this.attributes = const {},
  });

  /// Конструктор для создания объекта из Map, возвращаемого SQLite
  factory RoadEvent.fromSqflite(Map<String, dynamic> map) {
    Map<String, dynamic> parsedAttrs = {};

    // Парсим сохраненный JSON атрибутов, если он есть
    if (map['attributes'] != null) {
      if (map['attributes'] is String && (map['attributes'] as String).isNotEmpty) {
        try {
          parsedAttrs = jsonDecode(map['attributes'] as String) as Map<String, dynamic>;
        } catch (_) {
          parsedAttrs = {};
        }
      } else if (map['attributes'] is Map) {
        parsedAttrs = Map<String, dynamic>.from(map['attributes'] as Map);
      }
    }

    // Безопасное получение координат из разного именования колонок БД
    final double latitude = (map['lat'] ?? map['LAT'] ?? map['latitude'] ?? 0.0) as double;
    final double longitude = (map['lon'] ?? map['LON'] ?? map['longitude'] ?? 0.0) as double;

    // Безопасное чтение типа
    final dynamic rawType = map['camera_type'] ?? map['type'] ?? map['TYPE'] ?? map['type_code'];

    // Безопасное чтение азимута и ограничения скорости
    final int readAzimuth = (map['azimuth'] ?? map['AZIMUTH'] ?? map['dir'] as num?)?.toInt() ?? -1;
    final int readSpeed = (map['speed_limit'] ?? map['speed'] ?? map['SPEED'] as num?)?.toInt() ?? 0;

    return RoadEvent(
      id: (map['id'] ?? map['ID'] as num?)?.toInt() ?? 0,
      source: map['source'] as String? ?? 'openspeedcam',
      externalId: (map['external_id'] ?? map['ext_id'])?.toString(),
      lat: latitude,
      lon: longitude,
      azimuth: readAzimuth,
      type: RoadEventType.fromDynamic(rawType),
      speedLimit: readSpeed,
      attributes: parsedAttrs,
    );
  }

  /// Сериализация объекта в Map для SQLite или сохранений
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'source': source,
      'external_id': externalId,
      'lat': lat,
      'lon': lon,
      'azimuth': azimuth,
      'camera_type': type.toDbString(),
      'speed_limit': speedLimit,
      'attributes': jsonEncode(attributes),
    };
  }

  /// Быстрая проверка: установлено ли ограничение скорости
  bool get hasSpeedLimit => speedLimit > 0;

  /// Проверка: находится ли камера в направлении движения грузовика
  /// [driverHeading] — текущий курс грузовика в градусах (0..360)
  /// [maxAngleDifference] — допустимый угол отклонения (по умолчанию 45°)
  bool isFacingDriver(double driverHeading, {double maxAngleDifference = 45.0}) {
    // Если азимут равен -1, значит объект контролирует все направления (360°)
    if (azimuth == -1) return true;

    // Вычисляем минимальную разницу углов с учетом цикличности круга (0..360°)
    double diff = (azimuth - driverHeading).abs() % 360;
    if (diff > 180) {
      diff = 360 - diff;
    }

    return diff <= maxAngleDifference;
  }

  /// Вычисление точной дистанции до объекта в метрах по формуле гаверсинусов
  double distanceToMeters(double targetLat, double targetLon) {
    const double earthRadiusMeters = 6371000.0;
    final double dLat = _degreesToRadians(targetLat - lat);
    final double dLon = _degreesToRadians(targetLon - lon);

    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat)) *
            cos(_degreesToRadians(targetLat)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadiusMeters * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * pi / 180.0;
  }

  /// Готовый текст фразы для проактивной озвучки голосовым ИИ-ассистентом
  String get voiceWarningText {
    final buffer = StringBuffer();
    buffer.write(type.displayName);

    if (hasSpeedLimit) {
      buffer.write(', ограничение $speedLimit километров в час');
    }

    return buffer.toString();
  }

  @override
  String toString() {
    return 'RoadEvent(id: $id, type: ${type.name}, speedLimit: ${speedLimit}km/h, lat: $lat, lon: $lon, azimuth: $azimuth)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is RoadEvent &&
              runtimeType == other.runtimeType &&
              id == other.id;

  @override
  int get hashCode => id.hashCode;
}