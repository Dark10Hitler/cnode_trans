import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

enum RegionStatus { notDownloaded, downloading, ready }

class OfflineRegion {
  final String id;
  final String name;
  final String downloadUrl; // Ссылка на готовую вырезку PMTiles
  RegionStatus status;
  double progress;
  DateTime? lastUpdated;
  String? localPath;

  OfflineRegion({
    required this.id,
    required this.name,
    required this.downloadUrl,
    this.status = RegionStatus.notDownloaded,
    this.progress = 0,
    this.lastUpdated,
    this.localPath,
  });
}

class OfflineRegionsService {
  // Список доступных регионов с URL для скачивания (например, с вашего сервера или GitHub Releases)
  final List<OfflineRegion> regions = [
    OfflineRegion(
      id: 'md',
      name: 'Молдова',
      downloadUrl: 'https://github.com/your-repo/maps/releases/download/v1.0/moldova.pmtiles',
    ),
    OfflineRegion(
      id: 'ro',
      name: 'Румыния',
      downloadUrl: 'https://github.com/your-repo/maps/releases/download/v1.0/romania.pmtiles',
    ),
  ];

  /// Инициализация: проверяем, какие файлы уже скачаны на устройство
  Future<void> init() async {
    final docsDir = await getApplicationDocumentsDirectory();
    for (var region in regions) {
      final file = File('${docsDir.path}/${region.id}.pmtiles');
      if (await file.exists()) {
        region.status = RegionStatus.ready;
        region.progress = 1.0;
        region.localPath = file.path;
        region.lastUpdated = await file.lastModified();
      }
    }
  }

  /// Реальное скачивание файла PMTiles с отслеживанием прогресса
  Stream<double> download(OfflineRegion region) async* {
    region.status = RegionStatus.downloading;
    region.progress = 0.0;

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final filePath = '${docsDir.path}/${region.id}.pmtiles';
      final file = File(filePath);

      final client = http.Client();
      final response = await client.send(
        http.Request('GET', Uri.parse(region.downloadUrl)),
      );

      final contentLength = response.contentLength ?? 0;
      int downloadedBytes = 0;

      final sink = file.openWrite();

      await for (var chunk in response.stream) {
        downloadedBytes += chunk.length;
        sink.add(chunk);

        if (contentLength > 0) {
          region.progress = downloadedBytes / contentLength;
          yield region.progress;
        }
      }

      await sink.close();
      client.close();

      region.status = RegionStatus.ready;
      region.progress = 1.0;
      region.localPath = filePath;
      region.lastUpdated = DateTime.now();
      yield 1.0;
    } catch (e) {
      region.status = RegionStatus.notDownloaded;
      region.progress = 0.0;
      rethrow;
    }
  }

  Stream<double> update(OfflineRegion region) => download(region);
}