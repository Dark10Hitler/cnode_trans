import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../services/map_download_service.dart';

class OfflineMapsScreen extends StatefulWidget {
  const OfflineMapsScreen({super.key});

  @override
  State<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends State<OfflineMapsScreen> {
  final MapDownloadService _downloadService = MapDownloadService();
  final Map<String, bool> _downloadedStates = {};
  final Map<String, double> _downloadProgress = {};
  final Map<String, CancelToken> _cancelTokens = {};

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    for (var region in MapDownloadService.availableRegions) {
      final isDownloaded = await _downloadService.isMapDownloaded(region);
      setState(() {
        _downloadedStates[region.id] = isDownloaded;
      });
    }
  }

  Future<void> _startDownload(OfflineMapRegion region) async {
    final cancelToken = CancelToken();
    _cancelTokens[region.id] = cancelToken;

    setState(() {
      _downloadProgress[region.id] = 0.0;
    });

    try {
      await _downloadService.downloadMap(
        region: region,
        cancelToken: cancelToken,
        onProgress: (received, total) {
          if (total > 0) {
            setState(() {
              _downloadProgress[region.id] = received / total;
            });
          }
        },
      );

      setState(() {
        _downloadedStates[region.id] = true;
        _downloadProgress.remove(region.id);
        _cancelTokens.remove(region.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadProgress.remove(region.id);
        _cancelTokens.remove(region.id);
      });

      if (!CancelToken.isCancel(e as DioException)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки карты: ${region.country}')),
        );
      }
    }
  }

  Future<void> _cancelDownload(String regionId) async {
    _cancelTokens[regionId]?.cancel();
    _cancelTokens.remove(regionId);
    setState(() {
      _downloadProgress.remove(regionId);
    });
  }

  Future<void> _deleteMap(OfflineMapRegion region) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить карту ${region.country}?'),
        content: Text('Файл карты (${region.sizeMb.round()} МБ) будет удален с устройства.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _downloadService.deleteMap(region);
      setState(() {
        _downloadedStates[region.id] = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    double totalDownloadedMb = 0;
    for (var r in MapDownloadService.availableRegions) {
      if (_downloadedStates[r.id] == true && !r.isBuiltIn) {
        totalDownloadedMb += r.sizeMb;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Загрузка карт (Офлайн)'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Информационная карточка занятого места (как в HERE WeGo)
          Container(
            width: double.infinity,
            color: Theme.of(context).primaryColor.withOpacity(0.08),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.sd_storage_outlined, size: 36, color: Colors.blue),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Занято офлайн-картами',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Загружено дополнительно: ${totalDownloadedMb.round()} МБ',
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Список карт
          Expanded(
            child: ListView.separated(
              itemCount: MapDownloadService.availableRegions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final region = MapDownloadService.availableRegions[index];
                final isDownloaded = _downloadedStates[region.id] ?? false;
                final progress = _downloadProgress[region.id];
                final isDownloading = progress != null;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: region.isBuiltIn
                        ? Colors.green.withOpacity(0.1)
                        : isDownloaded
                        ? Colors.blue.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.1),
                    child: Icon(
                      region.isBuiltIn
                          ? Icons.star
                          : isDownloaded
                          ? Icons.map
                          : Icons.public,
                      color: region.isBuiltIn
                          ? Colors.green
                          : isDownloaded
                          ? Colors.blue
                          : Colors.grey,
                    ),
                  ),
                  title: Text(
                    region.country,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(region.regionName),
                      const SizedBox(height: 4),
                      if (isDownloading) ...[
                        LinearProgressIndicator(value: progress),
                        const SizedBox(height: 2),
                        Text(
                          'Загрузка: ${(progress * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(fontSize: 11, color: Colors.blue),
                        ),
                      ] else ...[
                        Text(
                          region.isBuiltIn
                              ? 'Встроена в приложение'
                              : 'Размер: ${region.sizeMb.round()} МБ',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ]
                    ],
                  ),
                  trailing: region.isBuiltIn
                      ? const Chip(
                    label: Text('Базовая', style: TextStyle(fontSize: 11)),
                    backgroundColor: Color(0xFFE8F5E9),
                  )
                      : isDownloading
                      ? IconButton(
                    icon: const Icon(Icons.close, color: Colors.orange),
                    tooltip: 'Отменить',
                    onPressed: () => _cancelDownload(region.id),
                  )
                      : isDownloaded
                      ? IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'Удалить карту',
                    onPressed: () => _deleteMap(region),
                  )
                      : IconButton(
                    icon: const Icon(Icons.download_for_offline_outlined, color: Colors.blue),
                    tooltip: 'Скачать',
                    onPressed: () => _startDownload(region),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}