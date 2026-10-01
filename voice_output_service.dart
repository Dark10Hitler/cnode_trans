import 'package:flutter_tts/flutter_tts.dart';

class VoiceOutputService {
  VoiceOutputService._();
  static final VoiceOutputService instance = VoiceOutputService._();

  final FlutterTts _tts = FlutterTts();
  bool _isInit = false;

  Future<void> init() async {
    if (_isInit) return;

    await _tts.setLanguage("ru-RU");
    await _tts.setSpeechRate(0.45); // Оптимальная скорость для водителя
    await _tts.setPitch(1.0);       // Естественный тон
    await _tts.setVolume(1.0);

    // Включаем использование качественных оффлайн-голосов Android
    await _tts.setEngine("com.google.android.tts");

    _isInit = true;
  }

  Future<void> speak(String text) async {
    await init();
    if (text.isEmpty) return;
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}