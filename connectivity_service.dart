import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static final Connectivity _connectivity = Connectivity();

  /// Проверяет интернет прямо сейчас
  static Future<bool> hasInternet() async {
    final results = await _connectivity.checkConnectivity();
    return _isConnected(results);
  }

  /// Поток для отслеживания сети в реальном времени
  static Stream<bool> get onConnectivityChanged {
    return _connectivity.onConnectivityChanged.map(_isConnected);
  }

  static bool _isConnected(List<ConnectivityResult> results) {
    return results.any((r) =>
    r == ConnectivityResult.mobile ||
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.ethernet);
  }
}