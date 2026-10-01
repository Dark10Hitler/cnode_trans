import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class ModelManagerService {
  // Переходим на Qwen 2.5 1.5B Instruct (идеально для русского языка и ChatML)
  static const String modelUrl =
      'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf';
  static const String modelFileName = 'qwen2.5-1.5b-instruct-q4_k_m.gguf';

  static Future<String> getOrDownloadModelPath({
    required Function(int received, int total) onProgress,
  }) async {
    final docDir = await getApplicationDocumentsDirectory();
    final modelFile = File('${docDir.path}/$modelFileName');

    if (await modelFile.exists()) {
      final length = await modelFile.length();
      // Ожидаемый размер Qwen 2.5 1.5B Q4_K_M ~ 980 МБ
      if (length > 800 * 1024 * 1024) {
        debugPrint('[ModelManager] Модель найдена: ${modelFile.path}');
        return modelFile.path;
      } else {
        await modelFile.delete();
      }
    }

    final dio = Dio(
      BaseOptions(
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        },
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(hours: 1),
      ),
    );

    await dio.download(
      modelUrl,
      modelFile.path,
      onReceiveProgress: onProgress,
    );

    return modelFile.path;
  }
}