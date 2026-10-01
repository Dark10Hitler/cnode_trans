import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../models/rig_profile.dart';
import '../../models/road_event.dart';
import '../../services/geocoding_service.dart';
import '../../services/location_service.dart';
import '../../services/routing_service.dart';
import '../../services/weather_service.dart';
import '../../services/voice_output_service.dart';
import '../../services/road_event_service.dart';
import '../../state/app_state.dart';

class MapsScreen extends StatefulWidget {
  final VoidCallback? onOpenOfflineMaps;

  const MapsScreen({
    super.key,
    this.onOpenOfflineMaps,
  });

  @override
  State<MapsScreen> createState() => _MapsScreenState();
}

class _MapsScreenState extends State<MapsScreen> {
  final MapController _mapController = MapController();

  final ValhallaRoutingService _routingService = ValhallaRoutingService();
  final GeocodingService _geocodingService = GeocodingService();
  final LocationService _locationService = LocationService();
  final WeatherService _weatherService = WeatherService();
  final VoiceOutputService _voiceOut = VoiceOutputService.instance;

  final TextEditingController _searchController = TextEditingController();
  List<PlaceSearchResult> _searchResults = [];
  bool _isSearching = false;

  LatLng? _startPoint;
  LatLng? _destinationPoint;

  List<LatLng> _routePoints = [];
  List<String> _restrictions = [];
  List<RoadEvent> _roadEvents = []; // Единая модель объектов OpenSpeedCam
  bool _isLoadingRoute = false;
  bool _isNavigatingActive = false;

  double? _routeDistanceKm;
  Duration? _routeDuration;
  String? _errorMessage;

  double _currentSpeedKmh = 0.0;
  String _weatherInfo = 'Загрузка...';
  StreamSubscription<dynamic>? _locationSub;
  Timer? _debounceTimer;
  LatLng? _previousPosition;
  double _currentHeading = 0.0;

  double _currentZoom = 15.0;
  bool _isFollowMode = true;
  bool _isVoiceMuted = false;

  @override
  void initState() {
    super.initState();
    _initLiveTracking();
    _loadRoadEvents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _locationSub?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  /// Загрузка объектов из SQLite базы (cameras.db) через RoadEventService
  Future<void> _loadRoadEvents() async {
    final center = _startPoint ?? const LatLng(47.7610, 27.9250);
    await _loadRoadEventsForCenter(center);
  }

  Future<void> _loadRoadEventsForCenter(LatLng center) async {
    try {
      await RoadEventService.instance.init();
      final activeRig = context.read<AppState>().activeRig;

      List<RoadEvent> fetchedEvents = [];

      // Если построен маршрут — берем события вдоль линии маршрута
      if (_routePoints.isNotEmpty) {
        fetchedEvents = await RoadEventService.instance.getEventsForRoute(
          _routePoints,
          activeRig: activeRig,
        );
      } else {
        // Иначе подгружаем события в видимом прямоугольнике (Bounding Box ~ 8-10 км)
        fetchedEvents = await RoadEventService.instance.getEventsInBounds(
          minLat: center.latitude - 0.08,
          maxLat: center.latitude + 0.08,
          minLon: center.longitude - 0.08,
          maxLon: center.longitude + 0.08,
          activeRig: activeRig,
        );
      }

      if (mounted) {
        setState(() {
          _roadEvents = fetchedEvents;
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки дорожных событий из БД: $e');
    }
  }

  /// Задержка повторного запроса к БД при панорамировании карты
  void _debounceLoadEvents(LatLng center) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && _routePoints.isEmpty) {
        _loadRoadEventsForCenter(center);
      }
    });
  }

  void _initLiveTracking() async {
    final hasPermission = await _locationService.ensurePermission();
    if (!hasPermission) return;

    final initialPos = await _locationService.getCurrentPosition();
    if (initialPos != null && mounted) {
      final startLatLng = LatLng(initialPos.latitude, initialPos.longitude);
      setState(() {
        _startPoint = startLatLng;
      });
      _loadWeather(initialPos.latitude, initialPos.longitude);
      _loadRoadEventsForCenter(startLatLng);
    }

    _locationSub = _locationService.watchPosition().listen((pos) {
      if (!mounted) return;

      final latLng = LatLng(pos.latitude, pos.longitude);
      final speedKmh = _locationService.speedKmh(pos);

      if (_previousPosition != null) {
        final heading = _calculateBearing(_previousPosition!, latLng);
        if (speedKmh > 1.5) {
          _currentHeading = heading;
        }
      }
      _previousPosition = latLng;

      setState(() {
        _currentSpeedKmh = speedKmh;
        _startPoint = latLng;
      });

      context.read<AppState>().updateSpeed(speedKmh);

      if (_isNavigatingActive && _isFollowMode) {
        _mapController.moveAndRotate(
          latLng,
          16.5,
          -_currentHeading,
        );
      }
    });
  }

  double _calculateBearing(LatLng start, LatLng end) {
    final lat1 = start.latitude * (pi / 180.0);
    final lon1 = start.longitude * (pi / 180.0);
    final lat2 = end.latitude * (pi / 180.0);
    final lon2 = end.longitude * (pi / 180.0);

    final dLon = lon2 - lon1;
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    final radians = atan2(y, x);
    return radians * (180.0 / pi);
  }

  Future<void> _loadWeather(double lat, double lon) async {
    try {
      final weather = await _weatherService.current(lat, lon);
      if (weather != null && mounted) {
        setState(() {
          _weatherInfo =
          '${weather.emoji} ${weather.temperatureC.toStringAsFixed(0)}°C, ${weather.windKmh.toStringAsFixed(0)} км/ч';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _weatherInfo = 'Погода недоступна');
      }
    }
  }

  void _zoomIn() {
    final newZoom = (_mapController.camera.zoom + 1.0).clamp(3.0, 18.0);
    setState(() {
      _currentZoom = newZoom;
    });
    _mapController.move(_mapController.camera.center, newZoom);
  }

  void _zoomOut() {
    final newZoom = (_mapController.camera.zoom - 1.0).clamp(3.0, 18.0);
    setState(() {
      _currentZoom = newZoom;
    });
    _mapController.move(_mapController.camera.center, newZoom);
  }

  void _recenterToMyLocation() {
    if (_startPoint != null) {
      setState(() {
        _isFollowMode = true;
        _currentZoom = 16.0;
      });
      _mapController.moveAndRotate(_startPoint!, 16.0, 0);
      _loadRoadEventsForCenter(_startPoint!);
    }
  }

  Future<void> _searchPlaces(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.length < 2) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() => _isSearching = true);
    try {
      final results = await _geocodingService.searchPlaces(cleanQuery);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _selectDestination(PlaceSearchResult place) {
    final destLatLng = LatLng(place.latitude, place.longitude);
    setState(() {
      _destinationPoint = destLatLng;
      _searchController.text = place.name;
      _searchResults = [];
    });
    FocusScope.of(context).unfocus();
    _mapController.move(destLatLng, 14.0);
    _buildRoute();
  }

  Future<void> _buildRoute() async {
    final appState = context.read<AppState>();
    final currentRig = appState.activeRig;

    if (_startPoint == null || _destinationPoint == null) {
      setState(() => _errorMessage = 'Укажите точку назначения');
      return;
    }

    if (currentRig == null) {
      _showRigSelectorDialog();
      return;
    }

    setState(() {
      _isLoadingRoute = true;
      _errorMessage = null;
    });

    try {
      final route = await _routingService.buildRoute(
        origin: LatLngPoint(_startPoint!.latitude, _startPoint!.longitude),
        destination: LatLngPoint(
          _destinationPoint!.latitude,
          _destinationPoint!.longitude,
        ),
        rig: currentRig,
      );

      if (mounted) {
        setState(() {
          _routePoints = route.points
              .map((p) => LatLng(p.latitude, p.longitude))
              .toList();
          _routeDistanceKm = route.distanceKm;
          _routeDuration = route.duration;
          _restrictions = route.restrictions;
          _isLoadingRoute = false;
          _isFollowMode = false;
        });

        _fitRouteToScreen();
        // Подгружаем спидкамы вдоль нового маршрута
        _loadRoadEvents();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingRoute = false;
          _errorMessage = 'Ошибка построения маршрута: $e';
        });
      }
    }
  }

  void _fitRouteToScreen() {
    if (_routePoints.isEmpty) return;

    double minLat = _routePoints.first.latitude;
    double maxLat = _routePoints.first.latitude;
    double minLng = _routePoints.first.longitude;
    double maxLng = _routePoints.first.longitude;

    for (var point in _routePoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;
    final center = LatLng(centerLat, centerLng);

    final latDiff = (maxLat - minLat).abs();
    final lngDiff = (maxLng - minLng).abs();
    final maxDiff = max(latDiff, lngDiff);

    double targetZoom = 12.0;
    if (maxDiff > 5.0) {
      targetZoom = 6.0;
    } else if (maxDiff > 2.0) {
      targetZoom = 7.5;
    } else if (maxDiff > 1.0) {
      targetZoom = 8.8;
    } else if (maxDiff > 0.5) {
      targetZoom = 10.0;
    } else if (maxDiff > 0.2) {
      targetZoom = 11.5;
    } else if (maxDiff > 0.05) {
      targetZoom = 13.0;
    } else {
      targetZoom = 14.5;
    }

    _mapController.moveAndRotate(center, targetZoom, 0);
  }

  void _toggleNavigation() async {
    setState(() {
      _isNavigatingActive = !_isNavigatingActive;
      _isFollowMode = _isNavigatingActive;
    });

    if (_isNavigatingActive) {
      if (_startPoint != null) {
        _mapController.moveAndRotate(_startPoint!, 16.5, -_currentHeading);
      }
      if (_routePoints.isNotEmpty && !_isVoiceMuted) {
        final distStr = _routeDistanceKm?.toStringAsFixed(0) ?? '0';
        final timeStr = _routeDuration?.inMinutes.toString() ?? '0';
        await _voiceOut.speak(
          'Маршрут построен. Дистанция $distStr километров. Время в пути $timeStr минут. Следуйте по маршруту.',
        );
      }
    } else {
      _fitRouteToScreen();
    }
  }

  /// Построение значка объекта OpenSpeedCam на основе глобального enum RoadEventType
  Widget _buildRoadEventMarker(RoadEvent event) {
    Widget badgeWidget;

    switch (event.type) {
      case RoadEventType.speedCamera:
      case RoadEventType.averageSpeed:
      case RoadEventType.mobileCamera:
        badgeWidget = Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: event.type == RoadEventType.mobileCamera
                  ? Colors.orange.shade800
                  : Colors.red.shade700,
              width: 3,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            event.speedLimit != null && event.speedLimit! > 0
                ? '${event.speedLimit}'
                : '📷',
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
        break;

      case RoadEventType.weightControl:
        badgeWidget = Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.blue.shade800,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 4),
            ],
          ),
          child: const Icon(Icons.scale, color: Colors.white, size: 18),
        );
        break;

      case RoadEventType.heightLimit:
        badgeWidget = Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.purple.shade700,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 4),
            ],
          ),
          child: const Icon(Icons.vertical_align_center,
              color: Colors.white, size: 18),
        );
        break;

      case RoadEventType.redLight:
      case RoadEventType.trafficLight:
        badgeWidget = Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 4),
            ],
          ),
          child: const Icon(Icons.traffic, color: Colors.redAccent, size: 18),
        );
        break;

      case RoadEventType.dangerZone:
        badgeWidget = Container(
          width: 30,
          height: 30,
          decoration: const BoxDecoration(
            color: Colors.amber,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.warning_amber_rounded,
              color: Colors.black, size: 20),
        );
        break;

      case RoadEventType.speedBump:
        badgeWidget = Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.amber.shade800,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.waves, color: Colors.white, size: 18),
        );
        break;

      case RoadEventType.railwayCrossing:
        badgeWidget = Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.brown.shade700,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.train, color: Colors.white, size: 18),
        );
        break;

      case RoadEventType.pedestrian:
        badgeWidget = Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.blue.shade600,
            shape: BoxShape.circle,
          ),
          child:
          const Icon(Icons.directions_walk, color: Colors.white, size: 18),
        );
        break;

      default:
        badgeWidget = Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: Colors.redAccent,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.info_outline, color: Colors.white, size: 16),
        );
        break;
    }

    if (event.azimuth != null && event.azimuth! >= 0) {
      return Transform.rotate(
        angle: event.azimuth! * (pi / 180.0),
        child: badgeWidget,
      );
    }

    return badgeWidget;
  }

  void _showRigSelectorDialog() {
    final appState = context.read<AppState>();
    final rigs = appState.rigs;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Выберите авто / сцепку',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon:
                    const Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(color: AppColors.surfaceHigh),
              if (rigs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'Нет сохраненных сцепок. Добавьте в разделе "Транспорт"',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: rigs.length,
                    itemBuilder: (context, index) {
                      final rig = rigs[index];
                      final isSelected = appState.activeRig?.id == rig.id;
                      return ListTile(
                        leading: Icon(
                          Icons.local_shipping,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          size: 32,
                        ),
                        title: Text(
                          rig.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          'Вес: ${rig.weightTons.toStringAsFixed(1)}т | Выс: ${rig.heightM}м | Длин: ${rig.lengthM}м | Осей: ${rig.axles}',
                          style:
                          const TextStyle(color: AppColors.textSecondary),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle,
                            color: AppColors.primary)
                            : null,
                        onTap: () async {
                          await appState.setActiveRig(rig.id);
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (_destinationPoint != null) {
                            _buildRoute();
                          } else {
                            _loadRoadEvents();
                          }
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = _routePoints.isNotEmpty ? 170.0 : 100.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            // 1. КАРТА
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _startPoint ?? const LatLng(47.7610, 27.9250),
                initialZoom: _currentZoom,
                onPositionChanged: (position, hasGesture) {
                  if (hasGesture && _isFollowMode) {
                    setState(() => _isFollowMode = false);
                  }
                  if (position.center != null) {
                    _debounceLoadEvents(position.center!);
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.cnode.trans',
                ),

                // СЛОЙ ДОРОЖНЫХ ОБЪЕКТОВ OPENSPEEDCAM ИЗ SQLite
                MarkerLayer(
                  markers: _roadEvents.map((event) {
                    return Marker(
                      point: LatLng(event.lat, event.lon),
                      width: 36,
                      height: 36,
                      child: _buildRoadEventMarker(event),
                    );
                  }).toList(),
                ),

                // СЛОЙ МАРШРУТА
                if (_routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        color: AppColors.primaryDark,
                        strokeWidth: 7.0,
                      ),
                    ],
                  ),

                // СЛОЙ ТЕКУЩЕЙ ПОЗИЦИИ И НАЗНАЧЕНИЯ
                MarkerLayer(
                  markers: [
                    if (_startPoint != null)
                      Marker(
                        point: _startPoint!,
                        width: 48,
                        height: 48,
                        child: Transform.rotate(
                          angle: _currentHeading * (pi / 180.0),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.3),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const Icon(
                                Icons.navigation,
                                color: AppColors.primary,
                                size: 36,
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_destinationPoint != null)
                      Marker(
                        point: _destinationPoint!,
                        width: 44,
                        height: 44,
                        child: const Icon(
                          Icons.location_on,
                          color: AppColors.danger,
                          size: 42,
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // 2. ВЕРХНЯЯ СТРОКА ПОИСКА И ТРАНСПОРТА
            Positioned(
              top: 10,
              left: 12,
              right: 12,
              child: Column(
                children: [
                  Card(
                    color: AppColors.surface,
                    elevation: 6,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.search,
                              color: AppColors.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              onChanged: _searchPlaces,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Поиск места или адреса...',
                                border: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                fillColor: Colors.transparent,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          if (_isSearching)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            )
                          else if (_searchController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.close,
                                  color: AppColors.textSecondary),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchResults = [];
                                  _destinationPoint = null;
                                  _routePoints = [];
                                });
                                _loadRoadEvents();
                              },
                            ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.local_shipping,
                                color: AppColors.primary),
                            tooltip: 'Выбрать ТС',
                            onPressed: _showRigSelectorDialog,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_searchResults.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      constraints: const BoxConstraints(maxHeight: 220),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 6)
                        ],
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, __) => const Divider(
                            height: 1, color: AppColors.surfaceHigh),
                        itemBuilder: (context, index) {
                          final item = _searchResults[index];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.location_on_outlined,
                                color: AppColors.accent),
                            title: Text(
                              item.name,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: item.description.isNotEmpty
                                ? Text(
                              item.description,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                                : null,
                            onTap: () => _selectDestination(item),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),

            // 3. ПРАВАЯ НИЖНЯЯ ПАНЕЛЬ
            Positioned(
              bottom: bottomPadding,
              right: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'where_am_i',
                    backgroundColor:
                    _isFollowMode ? AppColors.primary : AppColors.surface,
                    onPressed: _recenterToMyLocation,
                    child: Icon(
                      Icons.my_location,
                      color: _isFollowMode
                          ? AppColors.onPrimary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'download_maps',
                    backgroundColor: AppColors.surface,
                    onPressed: widget.onOpenOfflineMaps,
                    child: const Icon(Icons.download_for_offline,
                        color: AppColors.accent),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 4)
                      ],
                    ),
                    child: Column(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.add,
                              size: 22, color: AppColors.textPrimary),
                          onPressed: _zoomIn,
                          tooltip: 'Увеличить',
                        ),
                        const Divider(height: 1, color: AppColors.surfaceHigh),
                        IconButton(
                          icon: const Icon(Icons.remove,
                              size: 22, color: AppColors.textPrimary),
                          onPressed: _zoomOut,
                          tooltip: 'Уменьшить',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 4. ЛЕВАЯ НИЖНЯЯ ПАНЕЛЬ (СПИДОМЕТР + ПОГОДА)
            Positioned(
              bottom: bottomPadding,
              left: 12,
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.surfaceHigh, width: 1.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _currentSpeedKmh.toStringAsFixed(0),
                          style: const TextStyle(
                            color: AppColors.success,
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'км/ч',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wb_sunny_outlined,
                            color: AppColors.warning, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          _weatherInfo,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // 5. КНОПКА ГОЛОСОВОГО АССИСТЕНТА
            Positioned(
              bottom: bottomPadding + 8,
              left: 150,
              child: FloatingActionButton.small(
                heroTag: 'voice_btn',
                backgroundColor:
                _isVoiceMuted ? AppColors.surfaceHigh : AppColors.primary,
                onPressed: () {
                  setState(() {
                    _isVoiceMuted = !_isVoiceMuted;
                  });
                  _voiceOut.speak(
                    _isVoiceMuted ? 'Голос выключен' : 'Голос включен',
                  );
                },
                child: Icon(
                  _isVoiceMuted ? Icons.volume_off : Icons.record_voice_over,
                  color: _isVoiceMuted
                      ? AppColors.textSecondary
                      : AppColors.onPrimary,
                ),
              ),
            ),

            // 6. НИЖНЯЯ ПАНЕЛЬ МАРШРУТА И ОШИБОК
            if (_isLoadingRoute)
              Positioned(
                bottom: 16,
                left: 12,
                right: 12,
                child: Card(
                  color: AppColors.surface,
                  child: const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: AppColors.primary),
                        SizedBox(width: 12),
                        Text(
                          'Расчет грузового маршрута...',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_routePoints.isNotEmpty)
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Card(
                  color: AppColors.surface,
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_routeDistanceKm?.toStringAsFixed(1)} км',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                                Text(
                                  'Время в пути: ~${_routeDuration?.inMinutes} мин',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            ElevatedButton.icon(
                              icon: Icon(_isNavigatingActive
                                  ? Icons.stop
                                  : Icons.navigation),
                              label: Text(
                                  _isNavigatingActive ? 'СТОП' : 'ПОЕХАЛИ'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isNavigatingActive
                                    ? AppColors.danger
                                    : AppColors.success,
                                foregroundColor: AppColors.onPrimary,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 12),
                                textStyle: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              onPressed: _toggleNavigation,
                            ),
                          ],
                        ),
                        if (_restrictions.isNotEmpty) ...[
                          const Divider(
                              height: 12, color: AppColors.surfaceHigh),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: _restrictions
                                  .map((r) => Text(
                                '⚠️️ $r',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.warning,
                                  fontWeight: FontWeight.w600,
                                ),
                              ))
                                  .toList(),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

            if (_errorMessage != null)
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Card(
                  color: AppColors.danger,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: AppColors.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}