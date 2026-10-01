import 'package:flutter/foundation.dart';

import '../models/combination.dart';
import '../models/document.dart';
import '../models/driver_profile.dart';
import '../models/power_unit.dart';
import '../models/rig_profile.dart';
import '../models/trailer.dart';
import '../services/database_service.dart';

/// Центральное состояние приложения: транспорт (тягачи/грузовики,
/// прицепы/полуприцепы, связки), профиль водителя, документы текущего
/// владельца, "живой" контекст (скорость, маршрут, навигация) — для ассистента.
class AppState extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;

  List<PowerUnit> powerUnits = [];
  List<Trailer> trailers = [];
  List<VehicleCombination> combinations = [];
  DriverProfile? driverProfile;
  List<AppDocument> documents = [];
  bool isLoading = false;

  // ---------- Живой контекст движения и навигации ----------
  double? currentSpeedKmh;
  String? currentLocationName;
  String? destinationName;
  double? routeDistanceKm;
  double? estimatedTimeHours;
  String? roadContext;

  /// Активный борт (выбирает из не удалённых комбинаций или тягачей)
  RigProfile? get activeRig {
    for (final combo in combinations) {
      if (!combo.isActive) continue;
      final unit = _findPowerUnit(combo.powerUnitId);
      final trailer = _findTrailer(combo.trailerId);
      if (unit != null && trailer != null) {
        return RigProfile.combo(unit, trailer, combo);
      }
    }
    for (final unit in powerUnits) {
      if (unit.isActive) return RigProfile.solo(unit);
    }
    return null;
  }

  /// Список всех доступных (не удалённых) сцепок и одиночных тягачей
  List<RigProfile> get rigs {
    final List<RigProfile> list = [];

    for (final combo in combinations) {
      final unit = _findPowerUnit(combo.powerUnitId);
      final trailer = _findTrailer(combo.trailerId);
      if (unit != null && trailer != null) {
        list.add(RigProfile.combo(unit, trailer, combo));
      }
    }

    for (final unit in powerUnits) {
      list.add(RigProfile.solo(unit));
    }

    return list;
  }

  PowerUnit? _findPowerUnit(int id) {
    for (final u in powerUnits) {
      if (u.id == id) return u;
    }
    return null;
  }

  Trailer? _findTrailer(int id) {
    for (final t in trailers) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Загружает из базы данных ТОЛЬКО записи, где is_deleted = 0
  Future<void> loadAll() async {
    isLoading = true;
    notifyListeners();

    powerUnits = await _db.getPowerUnits();
    trailers = await _db.getTrailers();
    combinations = await _db.getCombinations();
    driverProfile = await _db.getDriverProfile();
    documents = await _db.getAllDocuments();

    isLoading = false;
    notifyListeners();
  }

  /// Активирует указанный RigProfile по его id
  Future<void> setActiveRig(String rigId) async {
    for (final combo in combinations) {
      if ('combo_${combo.id}' == rigId && combo.id != null) {
        await setActiveCombination(combo.id!);
        return;
      }
    }

    for (final unit in powerUnits) {
      if ('power_${unit.id}' == rigId && unit.id != null) {
        await setActivePowerUnit(unit.id!);
        return;
      }
    }
  }

  // ---------- Power units ----------
  Future<void> addPowerUnit(PowerUnit unit) async {
    final shouldActivate = powerUnits.isEmpty && combinations.isEmpty;
    final id = await _db.insertPowerUnit(unit);
    if (shouldActivate) await _db.setActivePowerUnit(id);
    await loadAll();
  }

  Future<void> updatePowerUnit(PowerUnit unit) async {
    await _db.updatePowerUnit(unit);
    await loadAll();
  }

  /// Мягкое удаление тягача:
  /// 1. Помечает тягач как is_deleted = 1 в БД.
  /// 2. Автоматически скрывает все его комбинации (каскадный Soft Delete).
  /// 3. Если был активен — автоматически назначает следующий активный борт.
  Future<void> deletePowerUnit(int id) async {
    final wasActive = _findPowerUnit(id)?.isActive ?? false;

    await _db.softDeletePowerUnit(id);
    await loadAll();

    if (wasActive || activeRig == null) {
      await _fallbackActiveRig();
    }
  }

  Future<void> setActivePowerUnit(int id) async {
    await _db.setActivePowerUnit(id);
    await loadAll();
  }

  // ---------- Trailers ----------
  Future<void> addTrailer(Trailer trailer) async {
    await _db.insertTrailer(trailer);
    await loadAll();
  }

  Future<void> updateTrailer(Trailer trailer) async {
    await _db.updateTrailer(trailer);
    await loadAll();
  }

  /// Мягкое удаление прицепа:
  /// 1. Помечает прицеп как is_deleted = 1 в БД.
  /// 2. Скрывает связанные комбинации с этим прицепом.
  /// 3. Если прицеп входил в активную комбинацию — переключает активный борт.
  Future<void> deleteTrailer(int id) async {
    final wasActiveInCombo = combinations.any((c) => c.trailerId == id && c.isActive);

    await _db.softDeleteTrailer(id);
    await loadAll();

    if (wasActiveInCombo || activeRig == null) {
      await _fallbackActiveRig();
    }
  }

  // ---------- Combinations ----------
  Future<void> addCombination(VehicleCombination combo) async {
    await _db.insertCombination(combo);
    await loadAll();
  }

  Future<void> updateCombination(VehicleCombination combo) async {
    await _db.updateCombination(combo);
    await loadAll();
  }

  /// Мягкое удаление комбинации (расцепление/скрытие)
  Future<void> deleteCombination(int id) async {
    final wasActive = combinations.any((c) => c.id == id && c.isActive);

    await _db.softDeleteCombination(id);
    await loadAll();

    if (wasActive || activeRig == null) {
      await _fallbackActiveRig();
    }
  }

  Future<void> setActiveCombination(int id) async {
    await _db.setActiveCombination(id);
    await loadAll();
  }

  /// Переназначает активный борт, если прошлый активный был мягко удалён
  Future<void> _fallbackActiveRig() async {
    if (combinations.isNotEmpty && combinations.first.id != null) {
      await _db.setActiveCombination(combinations.first.id!);
    } else if (powerUnits.isNotEmpty && powerUnits.first.id != null) {
      await _db.setActivePowerUnit(powerUnits.first.id!);
    }
    await loadAll();
  }

  // ---------- Driver ----------
  Future<void> saveDriverProfile(DriverProfile profile) async {
    await _db.saveDriverProfile(profile);
    driverProfile = profile;
    notifyListeners();
  }

  // ---------- Documents ----------
  Future<void> loadDocuments([DocumentOwnerType? ownerType, int? ownerId]) async {
    if (ownerType != null && ownerId != null) {
      documents = await _db.getDocuments(ownerType, ownerId);
    } else {
      documents = await _db.getAllDocuments();
    }
    notifyListeners();
  }

  Future<void> addDocument(AppDocument doc) async {
    await _db.insertDocument(doc);
    documents = await _db.getAllDocuments();
    notifyListeners();
  }

  Future<void> updateDocument(AppDocument doc) async {
    await _db.updateDocument(doc);
    documents = await _db.getAllDocuments();
    notifyListeners();
  }

  Future<void> deleteDocument(AppDocument doc) async {
    if (doc.id != null) await _db.deleteDocument(doc.id!);
    documents = await _db.getAllDocuments();
    notifyListeners();
  }

  // ---------- Live context & Navigation ----------

  /// Обновление текущей скорости по GPS
  void updateSpeed(double? kmh) {
    currentSpeedKmh = kmh;
    notifyListeners();
  }

  /// Обновление текстовой информации о трассе/дороге
  void updateRoadContext(String? context) {
    roadContext = context;
    notifyListeners();
  }

  /// Обновление всех данных активной навигации
  void updateNavigation({
    String? currentLocation,
    String? destination,
    double? distanceKm,
    double? timeHours,
  }) {
    currentLocationName = currentLocation;
    destinationName = destination;
    routeDistanceKm = distanceKm;
    estimatedTimeHours = timeHours;
    notifyListeners();
  }

  /// Сброс данных навигации при завершении или отмене маршрута
  void clearNavigation() {
    currentLocationName = null;
    destinationName = null;
    routeDistanceKm = null;
    estimatedTimeHours = null;
    notifyListeners();
  }
}