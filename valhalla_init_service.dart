import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class ValhallaInitService {
  /// Распаковывает/копирует valhalla_tiles.tar во внутреннее хранилище приложения
  static Future<String> prepareTiles() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final tarFile = File('${docsDir.path}/valhalla_tiles.tar');

    if (!await tarFile.exists()) {
      debugPrint('[ValhallaInitService] Копирование valhalla_tiles.tar из assets...');
      final byteData = await rootBundle.load('assets/valhalla_tiles.tar');
      final buffer = byteData.buffer;
      await tarFile.writeAsBytes(
        buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
      );
      debugPrint('[ValhallaInitService] Файл скопирован по пути: ${tarFile.path}');
    } else {
      debugPrint('[ValhallaInitService] Граф тайлов уже существует по пути: ${tarFile.path}');
    }

    return tarFile.path;
  }
}