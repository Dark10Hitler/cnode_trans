import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';

/// Таймер режима труда и отдыха (РТиО / AETR / ЕС 561/2006).
/// Работает как справочный помощник водителя, легко отключается в настройках.
class HosTimerState extends ChangeNotifier {
  // Нормы ЕСТР (AETR) / ЕС:
  // 1. Непрерывное управление до перерыва — 4ч 30мин.
  // 2. Стандартный суточный лимит вождения — 9ч.
  static const Duration drivingBreakThreshold = Duration(hours: 4, minutes: 30);
  static const Duration dailyDrivingThreshold = Duration(hours: 9);

  static const int _breakNotificationId = 9001;
  static const int _dailyNotificationId = 9002;

  final DatabaseService _db = DatabaseService.instance;
  Timer? _ticker;

  bool enabled = true;
  DateTime? shiftStartedAt;

  Duration get elapsed =>
      shiftStartedAt == null ? Duration.zero : DateTime.now().difference(shiftStartedAt!);

  bool get isRunning => shiftStartedAt != null;

  /// Оставшееся время до обязательного 45-минутного перерыва
  Duration get timeUntilBreak {
    final remaining = drivingBreakThreshold - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Оставшееся время до исчерпания 9-часовой суточной нормы вождения
  Duration get timeUntilDailyLimit {
    final remaining = dailyDrivingThreshold - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Future<void> init() async {
    final state = await _db.getHosState();
    enabled = state.enabled;
    shiftStartedAt = state.shiftStartedAt;
    if (isRunning) _startTicker();
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => notifyListeners());
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    await _db.saveHosState(enabled: enabled, shiftStartedAt: shiftStartedAt);
    if (!enabled) {
      await _cancelAlerts();
    } else if (isRunning) {
      await _scheduleAlerts(shiftStartedAt!);
    }
    notifyListeners();
  }

  Future<void> startShift() async {
    shiftStartedAt = DateTime.now();
    await _db.saveHosState(enabled: enabled, shiftStartedAt: shiftStartedAt);
    _startTicker();
    if (enabled) await _scheduleAlerts(shiftStartedAt!);
    notifyListeners();
  }

  Future<void> stopShift() async {
    shiftStartedAt = null;
    _ticker?.cancel();
    await _db.saveHosState(enabled: enabled, shiftStartedAt: null);
    await _cancelAlerts();
    notifyListeners();
  }

  Future<void> _cancelAlerts() async {
    await NotificationService.instance.cancel(_breakNotificationId);
    await NotificationService.instance.cancel(_dailyNotificationId);
  }

  Future<void> _scheduleAlerts(DateTime start) async {
    await NotificationService.instance.scheduleAt(
      id: _breakNotificationId,
      title: 'CargoNode — Перерыв 45 мин',
      body: 'В пути 4 ч 30 мин. По регламенту ЕСТР требуется остановка на отдых.',
      when: start.add(drivingBreakThreshold),
    );
    await NotificationService.instance.scheduleAt(
      id: _dailyNotificationId,
      title: 'CargoNode — Лимит 9 часов',
      body: 'Время вождения достигло 9 часов. Суточная норма исчерпана.',
      when: start.add(dailyDrivingThreshold),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}