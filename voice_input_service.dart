import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Голосовой ввод (распознавание речи) — основной способ общения с
/// ассистентом за рулём.
class VoiceInputService {
  VoiceInputService._internal();
  static final VoiceInputService instance = VoiceInputService._internal();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _initialized = false;

  Future<bool> init() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onError: (_) {},
      onStatus: (_) {},
    );
    return _initialized;
  }

  bool get isListening => _speech.isListening;

  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    String localeId = 'ru_RU',
  }) async {
    final ok = await init();
    if (!ok) return;
    await _speech.listen(
      onResult: (result) => onResult(result.recognizedWords, result.finalResult),
      localeId: localeId,
      listenOptions: stt.SpeechListenOptions(partialResults: true, cancelOnError: true),
    );
  }

  Future<void> stop() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
  }
}