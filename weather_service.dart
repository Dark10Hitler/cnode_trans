import 'dart:convert';

import 'package:http/http.dart' as http;

class WeatherInfo {
  final double temperatureC;
  final double windKmh;
  final int weatherCode;
  const WeatherInfo({required this.temperatureC, required this.windKmh, required this.weatherCode});

  /// Краткая расшифровка WMO weather_code.
  String get emoji {
    if (weatherCode == 0) return '☀️';
    if (weatherCode <= 3) return '⛅';
    if (weatherCode == 45 || weatherCode == 48) return '🌫️';
    if (weatherCode >= 51 && weatherCode <= 67) return '🌧️';
    if (weatherCode >= 71 && weatherCode <= 77) return '🌨️';
    if (weatherCode >= 80 && weatherCode <= 82) return '🌦️';
    if (weatherCode >= 95) return '⛈️';
    return '🌡️';
  }
}

/// Реальная погода через Open-Meteo — бесплатный публичный API без ключа.
/// Требует интернет (в отличие от GPS/маршрута — это единственная часть
/// экрана "Карта", которой честно нужна сеть).
class WeatherService {
  Future<WeatherInfo?> current(double lat, double lon) async {
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lat&longitude=$lon&current=temperature_2m,weather_code,wind_speed_10m&timezone=auto',
    );
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final current = data['current'] as Map<String, dynamic>?;
      if (current == null) return null;
      return WeatherInfo(
        temperatureC: (current['temperature_2m'] as num).toDouble(),
        windKmh: (current['wind_speed_10m'] as num).toDouble(),
        weatherCode: (current['weather_code'] as num).toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}
