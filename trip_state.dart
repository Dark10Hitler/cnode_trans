import 'package:flutter/foundation.dart';

import '../models/trip.dart';
import '../services/database_service.dart';

/// Состояние раздела "Расчёты": список рейсов + данные текущего
/// открытого рейса (заправки/плечи/расходы), которые считает
/// TripCalculator на экране отчёта.
class TripState extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;

  List<TripRecord> trips = [];
  bool isLoading = false;

  TripRecord? openTrip;
  List<TripRefuel> openRefuels = [];
  List<TripLeg> openLegs = [];
  List<TripExpense> openExpenses = [];

  Future<void> loadTrips() async {
    isLoading = true;
    notifyListeners();
    trips = await _db.getTrips();
    isLoading = false;
    notifyListeners();
  }

  Future<void> startTrip(TripRecord trip) async {
    final id = await _db.insertTrip(trip);
    await openTripById(id);
    await loadTrips();
  }

  Future<void> openTripById(int id) async {
    final all = await _db.getTrips();
    openTrip = all.firstWhere((t) => t.id == id);
    openRefuels = await _db.getRefuels(id);
    openLegs = await _db.getLegs(id);
    openExpenses = await _db.getExpenses(id);
    notifyListeners();
  }

  Future<void> addRefuel(TripRefuel refuel) async {
    await _db.insertRefuel(refuel);
    if (openTrip?.id == refuel.tripId) {
      openRefuels = await _db.getRefuels(refuel.tripId);
      notifyListeners();
    }
  }

  Future<void> addLeg(TripLeg leg) async {
    await _db.insertLeg(leg);
    if (openTrip?.id == leg.tripId) {
      openLegs = await _db.getLegs(leg.tripId);
      notifyListeners();
    }
  }

  Future<void> addExpense(TripExpense expense) async {
    await _db.insertExpense(expense);
    if (openTrip?.id == expense.tripId) {
      openExpenses = await _db.getExpenses(expense.tripId);
      notifyListeners();
    }
  }

  Future<void> finishTrip({required double finishOdometerKm, required double finishFuelLiters}) async {
    if (openTrip == null) return;
    final updated = openTrip!.copyWith(
      finishOdometerKm: finishOdometerKm,
      finishFuelLiters: finishFuelLiters,
      status: TripStatus.finished,
      finishedAt: DateTime.now(),
    );
    await _db.updateTrip(updated);
    openTrip = updated;
    await loadTrips();
    notifyListeners();
  }

  Future<void> deleteTrip(int id) async {
    await _db.deleteTrip(id);
    if (openTrip?.id == id) {
      openTrip = null;
      openRefuels = [];
      openLegs = [];
      openExpenses = [];
    }
    await loadTrips();
  }

  void closeOpenTrip() {
    openTrip = null;
    openRefuels = [];
    openLegs = [];
    openExpenses = [];
    notifyListeners();
  }
}
