import 'package:flutter/foundation.dart';

/// FFI-биндинг к C++ библиотеке Valhalla (заглушка для этапа тестирования).
class ValhallaBindings {
  bool _isConfigured = false;

  /// Инициализация конфигурации
  void init(String configJson) {
    _isConfigured = true;
    debugPrint('[ValhallaBindings] Конфигурация Valhalla загружена из локального файла.');
  }

  /// Генерация маршрута
  String? route(String requestJson) {
    if (!_isConfigured) {
      debugPrint('[ValhallaBindings] Ошибка: Valhalla не инициализирована!');
      return null;
    }
    debugPrint('[ValhallaBindings] Запрос на построение маршрута принят: $requestJson');
    return null; // Пока C++ библиотека (.so) не скомпилирована, возвращаем null
  }
}