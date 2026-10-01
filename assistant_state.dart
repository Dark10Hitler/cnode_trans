import 'package:flutter/foundation.dart';

import '../services/local_ai_service.dart';
import '../services/memory_service.dart';
import '../services/model_manager_service.dart';
import '../services/voice_input_service.dart';
import '../services/voice_output_service.dart';
import 'app_state.dart';

class ChatMessage {
  final String text;
  final bool fromUser;
  const ChatMessage(this.text, this.fromUser);
}

enum ModelStatus { notReady, downloading, initializing, ready, error }

class AssistantState extends ChangeNotifier {
  final LocalAiService ai = LlamaAiService.instance;
  final VectorMemoryService memory = SimpleMemoryStore();

  AppState? _appState;

  final List<ChatMessage> messages = [
    const ChatMessage(
      'Привет! Я локальный бортовой помощник CargoNode. Говори или пиши — отвечу без интернета, '
          'с учётом параметров твоего борта и документов.',
      false,
    ),
  ];

  bool isThinking = false;
  bool isListening = false;

  ModelStatus modelStatus = ModelStatus.notReady;
  double downloadProgress = 0.0;
  String statusMessage = 'Инициализация...';

  AssistantState() {
    _initAIModel();
  }

  Future<void> _initAIModel() async {
    try {
      modelStatus = ModelStatus.downloading;
      statusMessage = 'Проверка наличия модели ИИ...';
      notifyListeners();

      final modelPath = await ModelManagerService.getOrDownloadModelPath(
        onProgress: (received, total) {
          if (total > 0) {
            downloadProgress = received / total;
            statusMessage =
            'Скачивание ИИ-модели Llama 3.2: ${(downloadProgress * 100).toStringAsFixed(1)}%';
            notifyListeners();
          }
        },
      );

      modelStatus = ModelStatus.initializing;
      statusMessage = 'Загрузка модели в память...';
      notifyListeners();

      await ai.initModel(modelPath);

      modelStatus = ModelStatus.ready;
      statusMessage = 'ИИ готов к работе';
      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('[AssistantState] Ошибка инициализации модели: $e\n$stackTrace');
      modelStatus = ModelStatus.error;
      statusMessage = 'Ошибка загрузки ИИ: $e';
      notifyListeners();
    }
  }

  void updateAppState(AppState appState) {
    _appState = appState;
  }

  Future<void> send(String text, [AssistantContext? context]) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || isThinking) return;

    if (modelStatus != ModelStatus.ready) {
      messages.add(ChatMessage(
        'ИИ ещё загружается или возникла ошибка ($statusMessage). Пожалуйста, подождите...',
        false,
      ));
      notifyListeners();
      return;
    }

    messages.add(ChatMessage(trimmed, true));
    isThinking = true;
    notifyListeners();

    try {
      await memory.remember(trimmed);
      final hints = await memory.recall(trimmed);

      final baseContext = context ?? _buildContextFromAppState();

      // ИСПРАВЛЕНО: Теперь переносятся ВСЕ навигационные поля и память
      final enriched = AssistantContext(
        driver: baseContext.driver,
        rig: baseContext.rig,
        rigDocuments: baseContext.rigDocuments,
        currentSpeedKmh: baseContext.currentSpeedKmh,
        currentLocationName: baseContext.currentLocationName,
        destinationName: baseContext.destinationName,
        routeDistanceKm: baseContext.routeDistanceKm,
        estimatedTimeHours: baseContext.estimatedTimeHours,
        roadContext: baseContext.roadContext,
        memoryHints: hints,
      );

      final answer = await ai.ask(trimmed, enriched);

      messages.add(ChatMessage(answer, false));
      isThinking = false;
      notifyListeners();

      // Озвучивание осуществляется централизованно здесь
      final voiceText = ai.formatForVoice(answer);
      await VoiceOutputService.instance.speak(voiceText);
    } catch (e) {
      isThinking = false;
      messages.add(ChatMessage('Ошибка при генерации ответа: $e', false));
      notifyListeners();
    }
  }

  Future<void> startVoiceInput() async {
    if (isThinking || isListening) return;

    await VoiceOutputService.instance.stop();

    isListening = true;
    notifyListeners();

    await VoiceInputService.instance.listen(
      onResult: (text, isFinal) {
        if (isFinal && text.isNotEmpty) {
          isListening = false;
          notifyListeners();
          send(text);
        }
      },
    );
  }

  Future<void> stopVoiceInput() async {
    await VoiceInputService.instance.stop();
    isListening = false;
    notifyListeners();
  }

  AssistantContext _buildContextFromAppState() {
    if (_appState == null) return const AssistantContext();

    return AssistantContext(
      driver: _appState!.driverProfile,
      rig: _appState!.activeRig,
      rigDocuments: _appState!.documents,
      currentSpeedKmh: _appState!.currentSpeedKmh,
      currentLocationName: _appState!.currentLocationName,
      destinationName: _appState!.destinationName,
      routeDistanceKm: _appState!.routeDistanceKm,
      estimatedTimeHours: _appState!.estimatedTimeHours,
      roadContext: _appState!.roadContext,
    );
  }
}