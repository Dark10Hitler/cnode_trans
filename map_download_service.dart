import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum MapStatus { notDownloaded, downloading, downloaded }

class OfflineMapRegion {
  final String id;
  final String country;
  final String regionName;
  final String fileName;
  final String downloadUrl;
  final double sizeMb;
  final bool isBuiltIn;

  OfflineMapRegion({
    required this.id,
    required this.country,
    required this.regionName,
    required this.fileName,
    required this.downloadUrl,
    required this.sizeMb,
    this.isBuiltIn = false,
  });
}

class MapDownloadService {
  final Dio _dio = Dio();

  // Список доступных стран (по аналогии с HERE WeGo)
  static final List<OfflineMapRegion> availableRegions = [
    OfflineMapRegion(
      id: 'md',
      country: 'Молдова',
      regionName: 'Вся страна',
      fileName: 'moldova.mbtiles',
      downloadUrl: '',
      sizeMb: 45.0,
      isBuiltIn: true, // Встроена в assets
    ),
    OfflineMapRegion(
      id: 'ro',
      country: 'Румыния',
      regionName: 'Вся страна',
      fileName: 'romania.pmtiles',
      downloadUrl: 'https://build.protomaps.com/20240101/romania.pmtiles',
      sizeMb: 420.0,
    ),
    OfflineMapRegion(
      id: 'ua',
      country: 'Украина',
      regionName: 'Вся страна',
      fileName: 'ukraine.pmtiles',
      downloadUrl: 'https://build.protomaps.com/20240101/ukraine.pmtiles',
      sizeMb: 680.0,
    ),
  ];

  Future<String> getLocalFilePath(String fileName) async {
    final docsDir = await getApplicationDocumentsDirectory();
    return '${docsDir.path}/$fileName';
  }

  Future<bool> isMapDownloaded(OfflineMapRegion region) async {
    if (region.isBuiltIn) return true;
    final path = await getLocalFilePath(region.fileName);
    final file = File(path);
    return await file.exists() && (await file.length() > 0);
  }

  Future<void> downloadMap({
    required OfflineMapRegion region,
    required Function(int downloadedBytes, int totalBytes) onProgress,
    required CancelToken cancelToken,
  }) async {
    if (region.isBuiltIn) return;

    final savePath = await getLocalFilePath(region.fileName);

    try {
      await _dio.download(
        region.downloadUrl,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: onProgress,
      );
      debugPrint('Карта ${region.country} успешно загружена.');
    } catch (e) {
      final file = File(savePath);
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    }
  }

  Future<void> deleteMap(OfflineMapRegion region) async {
    if (region.isBuiltIn) return;
    final path = await getLocalFilePath(region.fileName);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Получить список всех скачанных локально файлов карт для подключения в Leaflet / MapLibre
  Future<List<String>> getDownloadedMapPaths() async {
    final List<String> paths = [];
    for (var region in availableRegions) {
      if (!region.isBuiltIn && await isMapDownloaded(region)) {
        paths.add(await getLocalFilePath(region.fileName));
      }
    }
    return paths;
  }
}