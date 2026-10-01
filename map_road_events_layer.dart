import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/road_event.dart';

/// Слой маркеров дорожных событий, камер и предупреждений для flutter_map
class MapRoadEventsLayer extends StatelessWidget {
  final List<RoadEvent> events;
  final Function(RoadEvent)? onEventTap;

  const MapRoadEventsLayer({
    super.key,
    required this.events,
    this.onEventTap,
  });

  @override
  Widget build(BuildContext context) {
    return MarkerLayer(
      markers: events.map((event) {
        return Marker(
          point: LatLng(event.lat, event.lon),
          width: 44,
          height: 44,
          child: GestureDetector(
            onTap: () => onEventTap?.call(event),
            child: _buildEventMarker(event),
          ),
        );
      }).toList(),
    );
  }

  /// Построение маркера события с учетом направления азимута контроля
  Widget _buildEventMarker(RoadEvent event) {
    final Widget iconBadge = _buildEventIcon(event);

    // Если у камеры или знака задан азимут (0..360°), добавляем указатель направления
    if (event.azimuth >= 0 && event.azimuth <= 360) {
      final double radians = event.azimuth * pi / 180.0;

      return Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Стрелочный указатель направления контроля
          Positioned(
            top: -2,
            child: Transform.rotate(
              angle: radians,
              origin: const Offset(0, 14),
              child: const Icon(
                Icons.navigation_rounded,
                color: Colors.redAccent,
                size: 16,
              ),
            ),
          ),
          // Основной круглый бейдж объекта
          iconBadge,
        ],
      );
    }

    return iconBadge;
  }

  /// Генерация круглого бейджа в зависимости от типа события
  Widget _buildEventIcon(RoadEvent event) {
    switch (event.type) {
      case RoadEventType.speedCamera:
        return _buildBadge(
          color: Colors.red.shade700,
          child: Text(
            event.hasSpeedLimit ? '${event.speedLimit}' : 'CAM',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900, // Исправлено: с FontWeight.black на FontWeight.w900
              fontSize: 11,
            ),
          ),
        );

      case RoadEventType.trafficLight:
        return _buildBadge(
          color: Colors.amber.shade900,
          child: const Icon(
            Icons.traffic_rounded,
            color: Colors.white,
            size: 20,
          ),
        );

      case RoadEventType.redLight:
        return _buildBadge(
          color: Colors.red.shade900,
          child: const Icon(
            Icons.traffic_rounded,
            color: Colors.white,
            size: 20,
          ),
        );

      case RoadEventType.averageSpeed:
        return _buildBadge(
          color: Colors.deepPurple.shade700,
          child: Text(
            event.hasSpeedLimit ? '${event.speedLimit}' : 'AVG',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        );

      case RoadEventType.mobileCamera:
        return _buildBadge(
          color: Colors.deepOrange.shade800,
          child: const Icon(
            Icons.photo_camera_rounded,
            color: Colors.white,
            size: 18,
          ),
        );

      case RoadEventType.speedBump:
        return _buildBadge(
          color: Colors.brown.shade600,
          child: const Icon(
            Icons.waves_rounded,
            color: Colors.white,
            size: 20,
          ),
        );

      case RoadEventType.pedestrian:
        return _buildBadge(
          color: Colors.blue.shade700,
          child: const Icon(
            Icons.directions_walk_rounded,
            color: Colors.white,
            size: 20,
          ),
        );

      case RoadEventType.railwayCrossing:
        return _buildBadge(
          color: Colors.indigo.shade900,
          child: const Icon(
            Icons.train_rounded,
            color: Colors.white,
            size: 19,
          ),
        );

      case RoadEventType.weightControl:
        return _buildBadge(
          color: Colors.orange.shade900,
          child: const Icon(
            Icons.scale_rounded,
            color: Colors.white,
            size: 19,
          ),
        );

      case RoadEventType.heightLimit:
        return _buildBadge(
          color: Colors.amber.shade800,
          child: const Icon(
            Icons.height_rounded,
            color: Colors.white,
            size: 20,
          ),
        );

      case RoadEventType.tollBooth:
        return _buildBadge(
          color: Colors.teal.shade700,
          child: const Icon(
            Icons.attach_money_rounded,
            color: Colors.white,
            size: 20,
          ),
        );

      case RoadEventType.dangerZone:
        return _buildBadge(
          color: Colors.red.shade800,
          child: const Icon(
            Icons.warning_amber_rounded,
            color: Colors.white,
            size: 20,
          ),
        );

      case RoadEventType.unknown:
      default:
        return _buildBadge(
          color: Colors.blueGrey.shade600,
          child: const Icon(
            Icons.location_on_rounded,
            color: Colors.white,
            size: 20,
          ),
        );
    }
  }

  /// Вспомогательный виджет для создания круглой плашки с белым обводом и тенью
  Widget _buildBadge({required Color color, required Widget child}) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Center(child: child),
    );
  }
}