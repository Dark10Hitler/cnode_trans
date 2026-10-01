import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../models/rig_profile.dart';
import '../../models/road_event.dart';
import '../../services/background_nav_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/geocoding_service.dart';
import '../../services/location_service.dart';
import '../../services/offline_routing_service.dart';
import '../../services/road_event_service.dart';
import '../../services/routing_service.dart';
import '../../services/valhalla_bindings.dart';
import '../../services/voice_output_service.dart';
import '../../services/weather_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/assistant_chat_view.dart';
import '../../widgets/rig_summary_card.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _locationService = LocationService();
  final RoutingService _onlineRoutingService = ValhallaRoutingService();
  late final RoutingService _offlineRoutingService;
  final _geocodingService = GeocodingService();
  final _voiceOut = VoiceOutputService.instance;
  final _destinationCtrl = TextEditingController();
  final _weatherService = WeatherService();

  MapLibreMapController? _mapController;

  Position? _position;
  WeatherInfo? _weather;
  PlaceSearchResult? _selectedDestination;
  List<PlaceSearchResult> _searchResults = [];
  Timer? _debounceTimer;

  StreamSubscription<bool>? _connectivitySub;
  bool _isOffline = false;

  bool _locating = false;
  bool _building = false;
  bool _navigating = false;
  bool _isSearching = false;
  RouteResult? _route;
  List<RoadEvent> _currentRoadEvents = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _offlineRoutingService = OfflineRoutingService(ValhallaBindings());
    _initConnectivity();
    _refreshLocation();
    // Инициализируем базу данных дорожных событий
    RoadEventService.instance.init();
  }

  Future<void> _initConnectivity() async {
    final hasNet = await ConnectivityService.hasInternet();
    if (mounted) {
      setState(() {
        _isOffline = !hasNet;
      });
    }

    _connectivitySub = ConnectivityService.onConnectivityChanged.listen((hasNet) {
      if (!mounted) return;
      final newOfflineState = !hasNet;
      if (_isOffline != newOfflineState) {
        setState(() {
          _isOffline = newOfflineState;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isOffline
                  ? 'Соединение потеряно. Переход в автономный режим (Офлайн)'
                  : 'Подключение восстановлено. Онлайн-режим',
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: _isOffline ? AppColors.warning : AppColors.primary,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _destinationCtrl.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    final pos = await _locationService.getCurrentPosition();
    if (!mounted) return;
    setState(() {
      _position = pos;
      _locating = false;
      if (pos == null) _error = 'Нет доступа к GPS. Разреши геолокацию в настройках устройства.';
    });

    if (pos != null) {
      context.read<AppState>().updateSpeed(_locationService.speedKmh(pos));

      if (!_isOffline) {
        _weatherService.current(pos.latitude, pos.longitude).then((w) {
          if (mounted) setState(() => _weather = w);
        }).catchError((_) {});
      }

      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
        );
      }
    }
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
  }

  void _onSearchQueryChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _isSearching = true);

      if (_isOffline) {
        if (mounted) {
          setState(() {
            _isSearching = false;
            _searchResults = [];
          });
        }
        return;
      }

      try {
        final results = await _geocodingService.searchPlaces(query);
        if (!mounted) return;
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _isSearching = false);
      }
    });
  }

  void _selectPlace(PlaceSearchResult place) {
    setState(() {
      _selectedDestination = place;
      _destinationCtrl.text = place.name;
      _searchResults = [];
    });

    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(place.latitude, place.longitude), 10.0),
      );
    }
  }

  /// Отрисовка нити маршрута на карте
  Future<void> _drawRouteOnMap(List<LatLngPoint> points) async {
    if (_mapController == null || points.isEmpty) return;

    await _mapController!.clearLines();

    final latLngList = points.map((p) => LatLng(p.latitude, p.longitude)).toList();

    await _mapController!.addLine(
      LineOptions(
        geometry: latLngList,
        lineColor: "#2196F3",
        lineWidth: 6.0,
        lineOpacity: 0.85,
      ),
    );

    double minLat = latLngList.first.latitude, maxLat = latLngList.first.latitude;
    double minLng = latLngList.first.longitude, maxLng = latLngList.first.longitude;
    for (var p in latLngList) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        left: 40,
        right: 40,
        top: 40,
        bottom: 250,
      ),
    );
  }

  /// Отрисовка камер, засад, светофоров и ПВК на карте
  /// Используем встроенные Material Icons вместо emoji для совместимости
  Future<void> _displayRoadEventsOnMap(List<RoadEvent> events) async {
    if (_mapController == null) return;

    await _mapController!.clearSymbols();

    for (final event in events) {
      String displayText = '';
      Color iconColor = Colors.red;
      IconData iconData = Icons.location_on;

      switch (event.type) {
        case RoadEventType.speedCamera:
        case RoadEventType.averageSpeed:
        case RoadEventType.mobileCamera:
          displayText = event.speedLimit > 0 ? '${event.speedLimit}' : 'CAM';
          iconData = Icons.videocam;
          iconColor = Colors.red;
          break;
        case RoadEventType.trafficLight:
          displayText = 'TL';
          iconData = Icons.traffic;
          iconColor = Colors.amber;
          break;
        case RoadEventType.redLight:
          displayText = 'RL';
          iconData = Icons.traffic;
          iconColor = Colors.red;
          break;
        case RoadEventType.weightControl:
          displayText = 'PVK';
          iconData = Icons.scale;
          iconColor = Colors.orange;
          break;
        case RoadEventType.heightLimit:
          final h = event.attributes['height_m'] ?? event.attributes['height'] ?? '';
          displayText = h.toString().isNotEmpty ? '${h}m' : 'H';
          iconData = Icons.height;
          iconColor = Colors.amber;
          break;
        case RoadEventType.tollBooth:
          displayText = 'PVP';
          iconData = Icons.attach_money;
          iconColor = Colors.teal;
          break;
        case RoadEventType.speedBump:
          displayText = 'SB';
          iconData = Icons.waves;
          iconColor = Colors.brown;
          break;
        case RoadEventType.pedestrian:
          displayText = 'PED';
          iconData = Icons.directions_walk;
          iconColor = Colors.blue;
          break;
        case RoadEventType.railwayCrossing:
          displayText = 'RW';
          iconData = Icons.train;
          iconColor = Colors.indigo;
          break;
        case RoadEventType.dangerZone:
          displayText = '!';
          iconData = Icons.warning;
          iconColor = Colors.red;
          break;
        case RoadEventType.unknown:
        default:
          displayText = '?';
          iconData = Icons.help;
          iconColor = Colors.blueGrey;
          break;
      }

      // Добавляем символ с текстом вместо emoji
      // Это совместимо с Android эмулятором
      await _mapController!.addSymbol(
        SymbolOptions(
          geometry: LatLng(event.lat, event.lon),
          textField: displayText,
          textSize: 12.0,
          textColor: '#FFFFFF', // Белый текст
          textHaloColor: _colorToHex(iconColor), // Цвет иконы как фон
          textHaloWidth: 3.0, // Толщина "ореола" создает эффект кружка
          textOffset: const Offset(0, 0),
          iconSize: 1.0,
        ),
      );
    }
  }

  /// Вспомогательный метод преобразования Color в hex string для MapLibre
  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
  }

  Future<void> _buildRoute(RigProfile rig) async {
    final text = _destinationCtrl.text.trim();
    if (text.isEmpty && _selectedDestination == null) {
      setState(() => _error = 'Введи пункт назначения');
      return;
    }
    if (_position == null) {
      setState(() => _error = 'Сначала определи текущее положение (GPS)');
      return;
    }

    setState(() {
      _building = true;
      _error = null;
      _navigating = false;
      _searchResults = [];
    });

    PlaceSearchResult? targetPlace = _selectedDestination;

    if (!_isOffline && (targetPlace == null || targetPlace.name.toLowerCase() != text.toLowerCase())) {
      try {
        final found = await _geocodingService.searchPlaces(text);
        if (found.isNotEmpty) {
          targetPlace = found.first;
          _selectedDestination = targetPlace;
        } else {
          setState(() {
            _building = false;
            _error = 'Город "$text" не найден. Уточните название.';
          });
          return;
        }
      } catch (_) {
        // Ошибка сети при поиске
      }
    }

    if (targetPlace == null) {
      setState(() {
        _building = false;
        _error = _isOffline
            ? 'В офлайн-режиме выберите точку из результатов или сохранений'
            : 'Точка назначения не найдена.';
      });
      return;
    }

    final destination = LatLngPoint(targetPlace.latitude, targetPlace.longitude);
    final origin = LatLngPoint(_position!.latitude, _position!.longitude);

    try {
      final activeRoutingService = _isOffline ? _offlineRoutingService : _onlineRoutingService;

      RouteResult route;
      try {
        route = await activeRoutingService.buildRoute(
          origin: origin,
          destination: destination,
          rig: rig,
        );
      } catch (e) {
        if (!_isOffline) {
          debugPrint('[MapScreen] Онлайн роутинг не удался. Вызов Offline Valhalla...');
          route = await _offlineRoutingService.buildRoute(
            origin: origin,
            destination: destination,
            rig: rig,
          );
        } else {
          rethrow;
        }
      }

      // Вычисляем геометрию полилинии маршрута для поиска объектов
      final polylinePoints = route.points.map((p) => [p.latitude, p.longitude]).toList();

      // Запрашиваем дорожные события (камеры, ПВК, габариты)
      final events = await RoadEventService.instance.getEventsForRoute(
        polylinePoints,
        activeRig: rig,
      );

      if (!mounted) return;
      setState(() {
        _route = route;
        _currentRoadEvents = events;
        _building = false;
      });

      // Отрисовываем маршрут и события на карте
      await _drawRouteOnMap(route.points);
      await _displayRoadEventsOnMap(events);

      final cameraCount = events.where((e) => e.type == RoadEventType.speedCamera || e.type == RoadEventType.mobileCamera).length;
      final pvkCount = events.where((e) => e.type == RoadEventType.weightControl).length;

      final eventsSummary = events.isNotEmpty
          ? 'На маршруте найдено объектов: ${events.length} (камер: $cameraCount, ПВК: $pvkCount).'
          : 'На маршруте нет зафиксированных камер и постов.';

      final restrictionsInfo = route.restrictions.isNotEmpty
          ? 'Применены ограничения и объезды: ${route.restrictions.join("; ")}.'
          : 'Маршрут оптимален для текущих параметров грузовика.';

      context.read<AppState>().updateRoadContext(
        'Текущий транспорт: ${rig.label} (Высота: ${rig.height}м, Вес: ${rig.weight}т, Нагрузка на ось: ${rig.axleLoad}т). '
            'Маршрут до пункта "${targetPlace.name}": ${route.distanceKm.toStringAsFixed(0)} км, ~${route.duration.inMinutes} мин. '
            '$eventsSummary $restrictionsInfo',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _building = false;
        _error = 'Ошибка построения маршрута: $e';
      });
    }
  }

  Future<void> _toggleNavigation(RigProfile rig) async {
    if (_navigating) {
      await BackgroundNavService.stop();
      setState(() => _navigating = false);
      return;
    }
    setState(() => _navigating = true);
    await BackgroundNavService.start();
    final route = _route;
    if (route != null) {
      final parts = <String>[
        'Маршрут построен для ${rig.label}. ${route.distanceKm.toStringAsFixed(0)} километров, '
            'примерно ${route.duration.inMinutes} минут.',
        if (_currentRoadEvents.isNotEmpty) 'Внимание, на маршруте ${_currentRoadEvents.length} постов и камер.',
        ...route.restrictions,
      ];
      await _voiceOut.speak(parts.join('. '));
    }
  }

  void _openAssistantSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: const AssistantChatView(compact: true),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rig = context.watch<AppState>().activeRig;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: MapLibreMap(
                    styleString: _isOffline
                        ? '{"version": 8, "sources": {}, "layers": []}'
                        : 'https://tiles.openfreemap.org/styles/liberty',
                    initialCameraPosition: const CameraPosition(
                      target: LatLng(47.0105, 28.8638),
                      zoom: 12.0,
                    ),
                    onMapCreated: _onMapCreated,
                    myLocationEnabled: true,
                    myLocationTrackingMode: MyLocationTrackingMode.tracking,
                    trackCameraPosition: true,
                    compassEnabled: true,
                  ),
                ),
                if (!_navigating)
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: AppColors.background,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (rig != null) ...[
                          RigSummaryCard(rig: rig),
                          const SizedBox(height: 12),
                        ] else
                          const Text(
                            'Выбери транспорт на вкладке «Транспорт» — маршрут строится под его габариты.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),

                        TextField(
                          controller: _destinationCtrl,
                          onChanged: _onSearchQueryChanged,
                          decoration: InputDecoration(
                            hintText: _isOffline ? 'Пункт назначения (Офлайн)' : 'Куда едем? (например: Dallas)',
                            prefixIcon: Icon(
                              _isOffline ? Icons.wifi_off_outlined : Icons.flag_outlined,
                              color: _isOffline ? AppColors.warning : null,
                            ),
                            suffixIcon: _isSearching
                                ? const UnconstrainedBox(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                                : (_destinationCtrl.text.isNotEmpty
                                ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _destinationCtrl.clear();
                                _mapController?.clearSymbols();
                                _mapController?.clearLines();
                                setState(() {
                                  _searchResults = [];
                                  _selectedDestination = null;
                                  _route = null;
                                  _currentRoadEvents = [];
                                });
                              },
                            )
                                : null),
                          ),
                        ),

                        if (_searchResults.isNotEmpty)
                          Material(
                            elevation: 6,
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              constraints: const BoxConstraints(maxHeight: 180),
                              child: ListView.separated(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: _searchResults.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = _searchResults[index];
                                  return ListTile(
                                    dense: true,
                                    title: Text(
                                      item.name,
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(
                                      item.description,
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                    onTap: () => _selectPlace(item),
                                  );
                                },
                              ),
                            ),
                          ),

                        const SizedBox(height: 10),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: (_building || rig == null) ? null : () => _buildRoute(rig),
                                child: _building
                                    ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                                    : Text(_isOffline ? 'Маршрут (Офлайн Valhalla)' : 'Построить маршрут'),
                              ),
                            ),
                            if (_route != null) ...[
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                onPressed: rig == null ? null : () => _toggleNavigation(rig),
                                icon: Icon(_navigating ? Icons.stop_circle_outlined : Icons.play_arrow),
                                label: Text(_navigating ? 'Стоп' : 'Старт'),
                              ),
                            ],
                          ],
                        ),
                        if (_route != null) ...[
                          const SizedBox(height: 10),
                          _RouteSummary(
                            route: _route!,
                            eventsCount: _currentRoadEvents.length,
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),

            Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: _StatusOverlay(
                position: _position,
                locating: _locating,
                weather: _weather,
                isOffline: _isOffline,
                speedKmh: _position != null ? _locationService.speedKmh(_position!) : null,
                onRefresh: _refreshLocation,
              ),
            ),

            if (_navigating && _route != null)
              Positioned(
                bottom: 16,
                left: 12,
                right: 12,
                child: _NavigationOverlay(
                  route: _route!,
                  position: _position,
                  speedKmh: _position != null ? _locationService.speedKmh(_position!) : null,
                  eventsCount: _currentRoadEvents.length,
                  onStop: () {
                    if (rig != null) _toggleNavigation(rig);
                  },
                ),
              ),

            Positioned(
              right: 16,
              bottom: _navigating ? 140 : 190,
              child: FloatingActionButton(
                heroTag: 'ai_fab',
                backgroundColor: AppColors.accent,
                onPressed: _openAssistantSheet,
                child: const Icon(Icons.smart_toy_outlined, color: AppColors.onPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusOverlay extends StatelessWidget {
  final Position? position;
  final bool locating;
  final WeatherInfo? weather;
  final bool isOffline;
  final double? speedKmh;
  final VoidCallback onRefresh;

  const _StatusOverlay({
    required this.position,
    required this.locating,
    required this.weather,
    required this.isOffline,
    required this.speedKmh,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background.withOpacity(0.88),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            isOffline ? Icons.wifi_off : Icons.gps_fixed,
            size: 16,
            color: isOffline ? AppColors.warning : AppColors.primary,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              locating
                  ? 'Определяем позицию…'
                  : position != null
                  ? '${position!.latitude.toStringAsFixed(4)}, ${position!.longitude.toStringAsFixed(4)} ${isOffline ? "(Офлайн)" : ""}'
                  : 'GPS недоступен',
              style: TextStyle(
                fontSize: 11,
                color: isOffline ? AppColors.warning : AppColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.speed, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 3),
          Text(
            speedKmh != null ? '${speedKmh!.toStringAsFixed(0)} км/ч' : '—',
            style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 10),
          if (weather != null && !isOffline) ...[
            Text(weather!.emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 3),
            Text('${weather!.temperatureC.round()}°',
                style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          ],
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.refresh, size: 18, color: AppColors.textSecondary),
            onPressed: locating ? null : onRefresh,
          ),
        ],
      ),
    );
  }
}

class _RouteSummary extends StatelessWidget {
  final RouteResult route;
  final int eventsCount;

  const _RouteSummary({
    required this.route,
    required this.eventsCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${route.distanceKm.toStringAsFixed(1)} км · ${route.duration.inMinutes} мин',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (eventsCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Объектов: $eventsCount',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.danger,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          if (route.restrictions.isNotEmpty)
            ...route.restrictions.map(
                  (r) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 16),
                    const SizedBox(width: 6),
                    Expanded(child: Text(r, style: const TextStyle(fontSize: 12))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavigationOverlay extends StatelessWidget {
  final RouteResult route;
  final Position? position;
  final double? speedKmh;
  final int eventsCount;
  final VoidCallback onStop;

  const _NavigationOverlay({
    required this.route,
    required this.position,
    required this.speedKmh,
    required this.eventsCount,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.navigation, color: AppColors.primary, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Режим навигации',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${route.distanceKm.toStringAsFixed(1)} км · ~${route.duration.inMinutes} мин',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.cancel, color: AppColors.danger, size: 30),
                onPressed: onStop,
                tooltip: 'Завершить навигацию',
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.speed, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    speedKmh != null ? '${speedKmh!.toStringAsFixed(0)} км/ч' : '0 км/ч',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              if (eventsCount > 0)
                Row(
                  children: [
                    const Icon(Icons.camera_alt_outlined, size: 18, color: AppColors.danger),
                    const SizedBox(width: 4),
                    Text(
                      'Объектов: $eventsCount',
                      style: const TextStyle(fontSize: 12, color: AppColors.danger, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
