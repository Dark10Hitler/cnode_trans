import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class OfflineAssetsService {
  /// Копирует файл из assets во внутреннее хранилище устройства,
  /// если он еще не был скопирован. Возвращает полный локальный путь.
  static Future<String> prepareAsset(String assetPath, String fileName) async {
    final docDir = await getApplicationDocumentsDirectory();
    final file = File('${docDir.path}/$fileName');

    if (!await file.exists()) {
      debugPrint('[OfflineAssets] Копирование $fileName во внутреннюю память...');
      final byteData = await rootBundle.load(assetPath);
      await file.writeAsBytes(
        byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
      );
      debugPrint('[OfflineAssets] $fileName успешно скопирован: ${file.path}');
    } else {
      debugPrint('[OfflineAssets] $fileName уже готов: ${file.path}');
    }

    return file.path;
  }

  /// Инициализирует все требуемые офлайн-ресурсы проекта
  static Future<Map<String, String>> initAll() async {
    final results = <String, String>{};
    try {
      results['valhalla'] = await prepareAsset(
        'assets/valhalla_tiles.tar',
        'valhalla_tiles.tar',
      );
      results['moldova_map'] = await prepareAsset(
        'assets/maps/moldova.mbtiles',
        'moldova.mbtiles',
      );
      results['romania_map'] = await prepareAsset(
        'assets/maps/romania.pmtiles',
        'romania.pmtiles',
      );
    } catch (e) {
      debugPrint('[OfflineAssets] Ошибка копирования ресурсов: $e');
    }
    return results;
  }
}