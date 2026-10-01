import 'dart:io';
import 'package:fllama/fllama.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/document.dart';
import '../models/driver_profile.dart';
import '../models/rig_profile.dart';
import '../models/road_event.dart'; // Импорт дорожных событий

/// Контекст, который ассистент "видит" в момент ответа на вопрос.
class AssistantContext {
  final DriverProfile? driver;
  final RigProfile? rig;
  final List<AppDocument> rigDocuments;
  final double? currentSpeedKmh;

  // Навигационные данные для штурмана
  final String? currentLocationName;
  final String? destinationName;
  final double? routeDistanceKm;
  final double? estimatedTimeHours;

  final String? roadContext; // Напр.: "Маршрут Бельцы — Яссы, трасса R16"
  final List<RoadEvent> routeEvents; // Дорожные события, отфильтрованные под борт
  final List<String> memoryHints;

  const AssistantContext({
    this.driver,
    this.rig,
    this.rigDocuments = const [],
    this.currentSpeedKmh,
    this.currentLocationName,
    this.destinationName,
    this.routeDistanceKm,
    this.estimatedTimeHours,
    this.roadContext,
    this.routeEvents = const [],
    this.memoryHints = const [],
  });
}

/// Абстракция локального ассистента.
abstract class LocalAiService {
  Future<void> init([String? modelPath]);
  Future<void> initModel(String modelPath);
  Future<String> ask(String query, AssistantContext context);
  String formatForVoice(String text);
}

/// Высококачественная реализация на базе Fllama & Qwen 2.5 ChatML
class LlamaAiService implements LocalAiService {
  LlamaAiService._internal();
  static final LlamaAiService instance = LlamaAiService._internal();

  bool _isInitialized = false;
  double? _contextId;
  final String _defaultModelFileName = 'qwen2.5-1.5b-instruct-q4_k_m.gguf';

  @override
  Future<void> initModel(String modelPath) async {
    await init(modelPath);
  }

  @override
  Future<void> init([String? modelPath]) async {
    if (_isInitialized) return;

    print('[LLAMA] Инициализация локальной языковой модели...');

    final finalModelPath = (modelPath != null && modelPath.isNotEmpty)
        ? modelPath
        : await _extractModelIfNeeded();

    final file = File(finalModelPath);
    if (!await file.exists()) {
      throw Exception('Файл модели не найден по пути: $finalModelPath');
    }

    print('[LLAMA] Загрузка модели в ОЗУ: $finalModelPath');
    final result = await Fllama.instance()?.initContext(
      finalModelPath,
      nCtx: 2048,      // Оптимальное окно контекста
      nThreads: 4,     // Оптимальное число ядер для мобильных CPU
      useMmap: true,   // Быстрая загрузка из памяти без дублирования
    );

    if (result != null && result.containsKey('contextId')) {
      _contextId = (result['contextId'] as num).toDouble();
      _isInitialized = true;
      print('[LLAMA] ✓ Модель успешно инициализирована! contextId: $_contextId');
    } else if (result != null && result.containsKey('id')) {
      _contextId = (result['id'] as num).toDouble();
      _isInitialized = true;
      print('[LLAMA] ✓ Модель успешно инициализирована! ID: $_contextId');
    } else {
      throw Exception('Не удалось инициализировать контекст Fllama. Ответ: $result');
    }
  }

  @override
  Future<String> ask(String query, AssistantContext context) async {
    if (!_isInitialized || _contextId == null) {
      return 'ИИ ещё загружается в память... Подожди пару секунд.';
    }

    final systemPrompt = _buildSystemPrompt(context);

    // Точный стандарт ChatML для Qwen 2.5
    final chatMlPrompt = '''<|im_start|>system
$systemPrompt<|im_end|>
<|im_start|>user
$query<|im_end|>
<|im_start|>assistant
''';

    print('[LLAMA] Генерация ответа...');

    try {
      final result = await Fllama.instance()?.completion(
        _contextId!,
        prompt: chatMlPrompt,
        temperature: 0.2, // Низкая температура исключает выдумки
        topP: 0.85,
        nPredict: 256,    // Емкий ответ
        stop: [
          '<|im_end|>',
          '<|im_start|>',
          '<|endoftext|>',
          '<|eot_id|>',
          'user:',
          'assistant:',
        ],
      );

      if (result != null) {
        final rawText = (result['text'] ?? result['content'] ?? '').toString();
        final cleanedText = _cleanRawOutput(rawText);

        if (cleanedText.isNotEmpty) {
          return cleanedText;
        }
      }

      return 'К сожалению, не удалось сформировать ответ. Попробуй переформулировать вопрос.';
    } catch (e) {
      print('[LLAMA] Ошибка при генерации: $e');
      return 'Произошла ошибка при обработке запроса: $e';
    }
  }

  /// Финальная очистка ответа от остаточных тегов и иероглифов
  String _cleanRawOutput(String raw) {
    String text = raw
        .replaceAll('<|im_end|>', '')
        .replaceAll('<|im_start|>', '')
        .replaceAll('<|endoftext|>', '')
        .replaceAll('<|eot_id|>', '')
        .replaceAll('assistant', '')
        .replaceAll('system', '')
        .replaceAll(RegExp(r'[\u4e00-\u9fa5]'), '') // Блокировка китайских символов
        .trim();

    if (text.startsWith(':')) {
      text = text.substring(1).trim();
    }

    return text;
  }

  /// Очистка ответа от Markdown для TTS
  @override
  String formatForVoice(String text) {
    return text
        .replaceAll(RegExp(r'\*+'), '')       // Удаляет звездочки
        .replaceAll(RegExp(r'#+'), '')        // Удаляет решетки
        .replaceAll(RegExp(r'`+'), '')        // Удаляет код-блоки
        .replaceAll(RegExp(r'[\-\*]\s+'), '') // Удаляет маркеры списков
        .replaceAll(RegExp(r'\s+'), ' ')      // Убирает двойные пробелы
        .trim();
  }

  /// Освобождение ресурсов
  Future<void> dispose() async {
    if (_contextId != null) {
      await Fllama.instance()?.releaseContext(_contextId!);
      _isInitialized = false;
      _contextId = null;
    }
  }

  /// Профессиональный Системный Промпт для Qwen 2.5
  String _buildSystemPrompt(AssistantContext context) {
    final sb = StringBuffer();

    sb.writeln('Ты — "CargoNode AI", опытный и надёжный бортовой напарник водителя.');
    sb.writeln('Твоя задача — помогать водителю в рейсе, отвечать на вопросы, следить за безопасностью, габаритами и документами.');
    sb.writeln('');
    sb.writeln('СТРОГИЕ ПРАВИЛА ОБЩЕНИЯ:');
    sb.writeln('1. Отвечай СТРОГО на русском языке. Запрещено использовать английский язык или китайские иероглифы.');
    sb.writeln('2. Будь кратким, конкретным и профессиональным (отвечай в 1-4 предложениях).');
    sb.writeln('3. Пиши чистым разговорным текстом без спецсимволов, звездочек (*), решеток (#) и маркдаун-тегов, так как твой ответ будет зачитываться голосом.');
    sb.writeln('4. ОПИРАЙСЯ ТОЛЬКО НА ДАННЫЕ ИЗ КОНТЕКСТА НИЖЕ. Не придумывай расстояния, маршруты или законы, если их нет в данных.');
    sb.writeln('5. Если вопрос водителя неполный или неясный — вежливо задай уточняющий вопрос.');
    sb.writeln('6. Если видишь проблему (перегруз, просроченный документ, нарушение ADR, ПВК на пути) — сразу предупреди водителя.');
    sb.writeln('7. Учитывай тип ТС: для грузовика критичны ПВК и габариты, для легковой они не важны.');
    sb.writeln('');

    // Контекст Транспортного Средства
    sb.writeln('=== ТЕКУЩЕЕ ТРАНСПОРТНОЕ СРЕДСТВО ===');
    bool isTruck = false;
    if (context.rig != null) {
      final r = context.rig!;
      isTruck = r.combination != null || r.trailer != null || r.weight > 3.5;
      sb.writeln('- Категория: ${isTruck ? "ГРУЗОВОЙ ТРАНСПОРТ / ТЯГАЧ" : "ЛЕГКОВОЙ АВТОМОБИЛЬ"}');
      sb.writeln('- Название/Марка: ${r.label}');
      sb.writeln('- Габариты: Длина ${r.length.toStringAsFixed(1)}м, Ширина ${r.width.toStringAsFixed(1)}м, Высота ${r.height.toStringAsFixed(1)}м');
      sb.writeln('- Полная масса: ${r.weight} т, Нагрузка на ось: ${r.axleLoad} т');
      sb.writeln('- Опасный груз (ADR): ${r.hazmat ? "ДА (Класс ${r.hazmatClass ?? 'не указан'})" : "НЕТ"}');
    } else {
      sb.writeln('Транспортное средство не выбрано в профиле (по умолчанию считается легковым).');
    }

    // Профиль Водителя
    if (context.driver != null) {
      sb.writeln('');
      sb.writeln('=== ПРОФИЛЬ ВОДИТЕЛЯ ===');
      sb.writeln('- Имя: ${context.driver!.fullName}');
      if (context.driver!.licenseCategories != null) {
        sb.writeln('- Категории прав: ${context.driver!.licenseCategories}');
      }
    }

    // Статус Документов
    sb.writeln('');
    sb.writeln('=== ДОКУМЕНТЫ И РЕГИСТРАЦИЯ ===');
    if (context.rigDocuments.isNotEmpty) {
      final expired = context.rigDocuments.where((d) => d.isExpired).toList();
      sb.writeln('- Всего документов в базе: ${context.rigDocuments.length}');
      if (expired.isNotEmpty) {
        sb.writeln('- ВНИМАНИЕ: Просрочено документов (${expired.length}):');
        for (final doc in expired) {
          sb.writeln('  * ${doc.name} (истёк: ${doc.expiryDate})');
        }
      } else {
        sb.writeln('- Все документы действительны.');
      }
    } else {
      sb.writeln('- Документы на ТС не добавлены.');
    }

    // Текущие условия движения и навигации
    sb.writeln('');
    sb.writeln('=== ТЕКУЩАЯ ОБСТАНОВКА И НАВИГАЦИЯ ===');
    bool hasNavigationData = false;

    if (context.currentSpeedKmh != null) {
      sb.writeln('- Скорость движения: ${context.currentSpeedKmh!.toStringAsFixed(0)} км/ч');
      hasNavigationData = true;
    }
    if (context.currentLocationName != null) {
      sb.writeln('- Текущее местоположение: ${context.currentLocationName}');
      hasNavigationData = true;
    }
    if (context.destinationName != null) {
      sb.writeln('- Пункт назначения: ${context.destinationName}');
      hasNavigationData = true;
    }
    if (context.routeDistanceKm != null) {
      sb.writeln('- Дистанция по маршруту: ${context.routeDistanceKm!.toStringAsFixed(0)} км');
      hasNavigationData = true;
    }
    if (context.estimatedTimeHours != null) {
      sb.writeln('- Примерное время в пути: ${context.estimatedTimeHours!.toStringAsFixed(1)} ч.');
      hasNavigationData = true;
    }
    if (context.roadContext != null && context.roadContext!.isNotEmpty) {
      sb.writeln('- Особенности дороги: ${context.roadContext}');
      hasNavigationData = true;
    }

    if (!hasNavigationData) {
      sb.writeln('- Данные навигации и маршрута сейчас недоступны.');
    }

    // Дорожные события и камеры (ОБНОВЛЕНО ДЛЯ АВТО И ГРУЗОВИКА)
    if (context.routeEvents.isNotEmpty) {
      sb.writeln('');
      sb.writeln('=== ОБЪЕКТЫ И КАМЕРЫ НА МАРШРУТЕ ===');

      final speedCams = context.routeEvents.where((e) => e.type == RoadEventType.speedCamera || e.type == RoadEventType.averageSpeed).toList();
      final weightControls = context.routeEvents.where((e) => e.type == RoadEventType.weightControl).toList();
      final heightLimits = context.routeEvents.where((e) => e.type == RoadEventType.heightLimit).toList();
      final redLights = context.routeEvents.where((e) => e.type == RoadEventType.redLight).toList();
      final dangerZones = context.routeEvents.where((e) => e.type == RoadEventType.dangerZone).toList();

      sb.writeln('- Всего релевантных объектов на пути: ${context.routeEvents.length}');
      if (speedCams.isNotEmpty) {
        sb.writeln('- Камер скорости / средняя скорость: ${speedCams.length}');
      }
      if (weightControls.isNotEmpty) {
        if (isTruck) {
          sb.writeln('- ПВК (Весовой контроль): ${weightControls.length} шт. (КРИТИЧНО ДЛЯ ГРУЗОВИКА: задержка и обязательный контроль)');
        } else {
          sb.writeln('- ПВК (Весовой контроль): ${weightControls.length} шт. (Легковой авто проезжает без остановок)');
        }
      }
      if (heightLimits.isNotEmpty) {
        sb.writeln('- Ограничение высоты: ${heightLimits.length} шт.');
      }
      if (redLights.isNotEmpty) {
        sb.writeln('- Камер светофора/разметки: ${redLights.length} шт.');
      }
      if (dangerZones.isNotEmpty) {
        sb.writeln('- Опасных участков: ${dangerZones.length} шт.');
      }
    }

    // Память прошлых диалогов
    if (context.memoryHints.isNotEmpty) {
      sb.writeln('');
      sb.writeln('=== ПАМЯТЬ ПРОШЛЫХ РАЗГОВОРОВ ===');
      for (final hint in context.memoryHints) {
        sb.writeln('- $hint');
      }
    }

    return sb.toString();
  }

  /// Извлечение базовой модели из assets (резервный вариант)
  Future<String> _extractModelIfNeeded() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, _defaultModelFileName));

    if (await file.exists()) {
      return file.path;
    }

    print('[LLAMA] Извлечение резервной модели из assets...');
    final byteData = await rootBundle.load('assets/models/$_defaultModelFileName');
    final buffer = byteData.buffer;

    await file.writeAsBytes(
      buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
    );

    return file.path;
  }
}

// Заглушка на правилах (для тестов)
class RuleBasedAiService implements LocalAiService {
  @override
  Future<void> init([String? modelPath]) async {}

  @override
  Future<void> initModel(String modelPath) async {}

  @override
  Future<String> ask(String query, AssistantContext context) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return 'Работает в режиме базовых правил.';
  }

  @override
  String formatForVoice(String text) => text;
}