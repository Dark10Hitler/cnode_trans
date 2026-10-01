import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Держит навигацию живой, когда экран выключен / приложение свёрнуто /
/// телефон заблокирован — через foreground-service Android (пакет
/// flutter_foreground_task) + удержание экрана включённым во время
/// активной навигации (wakelock_plus).
///
/// ⚠️ ЭТО САМАЯ ВЕРСИОННО-ЧУВСТВИТЕЛЬНАЯ ЧАСТЬ ПРОЕКТА. API
/// flutter_foreground_task менялся между мажорными версиями. Первое,
/// что стоит собрать и проверить на реальном Android-устройстве после
/// `flutter pub get` — именно этот файл. Если `flutter analyze` покажет
/// несовпадение сигнатур (onStart/onRepeatEvent/onDestroy у
/// TaskHandler), сверься с example.dart в текущей версии пакета на
/// pub.dev — там всегда актуальная сигнатура.
class BackgroundNavTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Здесь (при подключении Valhalla/MapLibre) можно дёргать пересчёт
    // ближайшего манёвра и озвучку через VoiceOutputService.
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

@pragma('vm:entry-point')
void backgroundNavCallback() {
  FlutterForegroundTask.setTaskHandler(BackgroundNavTaskHandler());
}

class BackgroundNavService {
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'cargonode_navigation',
        channelName: 'CargoNode — навигация',
        channelDescription: 'Навигация и голосовые подсказки активны в фоне',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    _initialized = true;
  }

  static Future<void> start() async {
    init();
    await WakelockPlus.enable();
    final running = await FlutterForegroundTask.isRunningService;
    if (!running) {
      await FlutterForegroundTask.startService(
        notificationTitle: 'CargoNode — навигация активна',
        notificationText: 'Маршрут и голосовые подсказки продолжаются в фоне',
        callback: backgroundNavCallback,
      );
    }
  }

  static Future<void> stop() async {
    await WakelockPlus.disable();
    await FlutterForegroundTask.stopService();
  }
}
