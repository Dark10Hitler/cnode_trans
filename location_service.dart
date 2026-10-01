import 'package:geolocator/geolocator.dart';

/// Обёртка над GPS устройства. Полностью офлайн — координаты и скорость
/// со спутников не требуют интернета.
class LocationService {
  Future<bool> ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return false;
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    return serviceEnabled &&
        (permission == LocationPermission.always || permission == LocationPermission.whileInUse);
  }

  Future<Position?> getCurrentPosition() async {
    final ok = await ensurePermission();
    if (!ok) return null;
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  /// Поток позиций (в т.ч. скорость, position.speed в м/с) — используется
  /// на экране "Карта" для живого спидометра и для фоновой навигации.
  Stream<Position> watchPosition() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    );
  }

  double speedKmh(Position position) => position.speed < 0 ? 0 : position.speed * 3.6;
}
