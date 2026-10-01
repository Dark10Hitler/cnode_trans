import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'screens/home_shell.dart';
import 'services/background_nav_service.dart';
import 'services/notification_service.dart';
import 'state/app_state.dart';
import 'state/assistant_state.dart';
import 'state/hos_timer_state.dart';
import 'state/trip_state.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Инициализация SQLite через FFI для поддержки R*Tree (модуля гео-индексов)
  if (Platform.isAndroid || Platform.isIOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Быстрые системные инициализации (без await)
  FlutterForegroundTask.initCommunicationPort();
  BackgroundNavService.init();
  NotificationService.instance.init();

  // Запуск UI происходим МГНОВЕННО
  runApp(const CargoNodeApp());
}

class CargoNodeApp extends StatelessWidget {
  const CargoNodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()..loadAll()),
        ChangeNotifierProvider(create: (_) => HosTimerState()..init()),
        ChangeNotifierProvider(create: (_) => TripState()),

        // ProxyProvider передает актуальный AppState в AssistantState
        ChangeNotifierProxyProvider<AppState, AssistantState>(
          create: (_) => AssistantState(),
          update: (_, appState, assistantState) =>
          (assistantState ?? AssistantState())..updateAppState(appState),
        ),
      ],
      child: MaterialApp(
        title: 'CargoNode',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        home: const HomeShell(),
      ),
    );
  }
}