import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/local_ai_service.dart';
import '../services/voice_input_service.dart';
import '../state/app_state.dart';
import '../state/assistant_state.dart';
import '../theme/app_theme.dart';

/// Переиспользуемый чат ассистента — голос в приоритете (большая кнопка
/// микрофона), текст как запасной вариант.
class AssistantChatView extends StatefulWidget {
  final bool compact;
  const AssistantChatView({super.key, this.compact = false});

  @override
  State<AssistantChatView> createState() => _AssistantChatViewState();
}

class _AssistantChatViewState extends State<AssistantChatView> {
  final _voiceIn = VoiceInputService.instance;

  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _listening = false;
  bool _speakReplies = true;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _voiceIn.stop();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _voiceIn.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final ok = await _voiceIn.init();
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Голосовой ввод недоступен на этом устройстве')),
      );
      return;
    }
    setState(() => _listening = true);
    await _voiceIn.listen(
      onResult: (text, isFinal) {
        _inputCtrl.text = text;
        if (isFinal) {
          if (mounted) setState(() => _listening = false);
          _send();
        }
      },
    );
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    final assistant = context.read<AssistantState>();

    if (assistant.modelStatus != ModelStatus.ready) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(assistant.statusMessage)),
      );
      return;
    }

    _inputCtrl.clear();

    // Считываем всё единое состояние приложения
    final appState = context.read<AppState>();

    await assistant.send(
      text,
      AssistantContext(
        driver: appState.driverProfile,
        rig: appState.activeRig,
        rigDocuments: appState.documents,
        currentSpeedKmh: appState.currentSpeedKmh,
        currentLocationName: appState.currentLocationName,
        destinationName: appState.destinationName,
        routeDistanceKm: appState.routeDistanceKm,
        estimatedTimeHours: appState.estimatedTimeHours,
        roadContext: appState.roadContext,
      ),
    );

    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final assistant = context.watch<AssistantState>();

    return Column(
      children: [
        // Панель статуса загрузки модели ИИ
        if (assistant.modelStatus != ModelStatus.ready)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: assistant.modelStatus == ModelStatus.error
                ? AppColors.danger.withOpacity(0.2)
                : AppColors.primary.withOpacity(0.15),
            child: Column(
              children: [
                Row(
                  children: [
                    if (assistant.modelStatus == ModelStatus.downloading ||
                        assistant.modelStatus == ModelStatus.initializing)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    if (assistant.modelStatus == ModelStatus.error)
                      const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        assistant.statusMessage,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                if (assistant.modelStatus == ModelStatus.downloading) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: assistant.downloadProgress,
                    backgroundColor: Colors.white24,
                  ),
                ],
              ],
            ),
          ),

        if (!widget.compact)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.volume_up, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                const Text(
                  'Озвучивать ответы',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const Spacer(),
                Switch(
                  value: _speakReplies,
                  onChanged: (v) => setState(() => _speakReplies = v),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(16),
            itemCount: assistant.messages.length,
            itemBuilder: (context, index) => _Bubble(message: assistant.messages[index]),
          ),
        ),
        if (assistant.isThinking)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Думаю…', style: TextStyle(color: AppColors.textSecondary)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              GestureDetector(
                onTap: _toggleListening,
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: _listening ? AppColors.danger : AppColors.primary,
                  child: Icon(_listening ? Icons.stop : Icons.mic, color: AppColors.onPrimary),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  decoration: const InputDecoration(hintText: 'Или напиши сообщение…'),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: assistant.modelStatus == ModelStatus.ready ? _send : null,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.fromUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          message.text,
          style: TextStyle(color: isUser ? AppColors.onPrimary : AppColors.textPrimary),
        ),
      ),
    );
  }
}