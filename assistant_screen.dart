import 'package:flutter/material.dart';

import '../../widgets/assistant_chat_view.dart';

/// Полная вкладка "Помощник" — тот же чат, что и быстрый доступ с карты
/// (общая история сообщений через AssistantState), но во весь экран и
/// с переключателем "озвучивать ответы" в шапке.
class AssistantScreen extends StatelessWidget {
  const AssistantScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Помощник')),
      body: const AssistantChatView(),
    );
  }
}
