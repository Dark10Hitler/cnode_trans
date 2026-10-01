import '../models/trip.dart';

/// Один фактический участок маршрута между двумя точками смены
/// статуса (или между стартом/финишем и ближайшей точкой) — единица
/// расчёта расхода топлива в модели Fuel = F₀ + k × M.
class TripRouteSegment {
  final double startOdometerKm;
  final double endOdometerKm;
  final double distanceKm;
  final CargoState cargoState;
  final double cargoWeightTons; // 0, если порожняком
  final double consumptionPer100km;
  final double fuelLiters;
  final TripEndpointType? endpointType;
  final double? endpointDistanceKm;

  const TripRouteSegment({
    required this.startOdometerKm,
    required this.endOdometerKm,
    required this.distanceKm,
    required this.cargoState,
    required this.cargoWeightTons,
    required this.consumptionPer100km,
    required this.fuelLiters,
    this.endpointType,
    this.endpointDistanceKm,
  });
}

/// Итог расчёта рейса — используется и на экране отчёта, и в PDF.
class TripCalculationResult {
  // Дистанция
  final double totalDistanceKm;
  final double loadedDistanceKm;
  final double emptyDistanceKm;
  final double deadheadDistanceKm;
  final double idlePercent;

  // Топливо: факт (по чекам/баку) и расчёт (по модели массы)
  final double fuelBurnedLiters; // фактически сожжено (баланс бака)
  final double avgConsumptionPer100km; // фактический средний расход
  final double calculatedFuelLiters; // расчётный расход по модели F0+kM
  final double fuelDeviationLiters; // факт - расчёт

  // Расход по загрузке
  final double emptyConsumptionPer100km;
  final double loadedConsumptionPer100km;
  final double consumptionIncreasePer100km;
  final double consumptionIncreasePercent;
  final double emptyFuelLiters;
  final double loadedFuelLiters;

  // Доходы
  final double incomePerKmTotal;
  final double incomePerKmLoaded;

  // Расходы
  final double fuelCost;
  final double otherDirectExpenses;
  final double directExpensesTotal;
  final double driverPay;
  final double perDiemTotal;
  final double depreciationTotal;
  final double indirectExpensesTotal;
  final double totalExpenses;
  final double costPerKm;
  final double netProfit;
  final double marginPercent;

  // Маршрут и конечный пункт
  final List<TripRouteSegment> segments;
  final TripEndpointType? endpointType;
  final double? endpointDistanceKm;

  const TripCalculationResult({
    required this.totalDistanceKm,
    required this.loadedDistanceKm,
    required this.emptyDistanceKm,
    required this.deadheadDistanceKm,
    required this.idlePercent,
    required this.fuelBurnedLiters,
    required this.avgConsumptionPer100km,
    required this.calculatedFuelLiters,
    required this.fuelDeviationLiters,
    required this.emptyConsumptionPer100km,
    required this.loadedConsumptionPer100km,
    required this.consumptionIncreasePer100km,
    required this.consumptionIncreasePercent,
    required this.emptyFuelLiters,
    required this.loadedFuelLiters,
    required this.incomePerKmTotal,
    required this.incomePerKmLoaded,
    required this.fuelCost,
    required this.otherDirectExpenses,
    required this.directExpensesTotal,
    required this.driverPay,
    required this.perDiemTotal,
    required this.depreciationTotal,
    required this.indirectExpensesTotal,
    required this.totalExpenses,
    required this.costPerKm,
    required this.netProfit,
    required this.marginPercent,
    required this.segments,
    this.endpointType,
    this.endpointDistanceKm,
  });
}

class _Breakpoint {
  final double odometerKm;
  final CargoState cargoState;
  final double cargoWeightTons;
  final TripEndpointType? endpointType;
  final double? endpointDistanceKm;

  const _Breakpoint({
    required this.odometerKm,
    required this.cargoState,
    required this.cargoWeightTons,
    this.endpointType,
    this.endpointDistanceKm,
  });
}

/// Чистая бизнес-логика бухгалтерии рейса — без UI и без БД.
///
/// Главный принцип (см. ТЗ): весь пробег режется на участки по точкам
/// смены статуса ("плечам"). Каждый участок считается ОТДЕЛЬНО, с
/// расходом топлива по модели `Fuel = F0 + k × M`, где M — масса груза
/// именно на этом участке (а не общая масса рейса и не пропорция от
/// общего пробега). Порожние участки всегда считаются по F0.
class TripCalculator {
  static TripCalculationResult calculate({
    required TripRecord trip,
    required List<TripRefuel> refuels,
    required List<TripLeg> legs,
    required List<TripExpense> expenses,
  }) {
    final finishOdometer = trip.finishOdometerKm ?? trip.startOdometerKm;
    final finishFuel = trip.finishFuelLiters ?? trip.startFuelLiters;
    final totalDistance = (finishOdometer - trip.startOdometerKm).clamp(0, double.infinity).toDouble();

    final sortedLegs = [...legs]..sort((a, b) => a.odometerKm.compareTo(b.odometerKm));

    // Точки состояния: старт рейса (статус/масса — из TripRecord) +
    // каждое плечо (статус/масса/конечный пункт — из TripLeg).
    final breakpoints = <_Breakpoint>[
      _Breakpoint(
        odometerKm: trip.startOdometerKm,
        cargoState: trip.cargoWeightTons > 0 ? CargoState.loaded : CargoState.empty,
        cargoWeightTons: trip.cargoWeightTons,
      ),
      for (final leg in sortedLegs)
        _Breakpoint(
          odometerKm: leg.odometerKm,
          cargoState: leg.cargoState,
          cargoWeightTons: leg.cargoState == CargoState.loaded ? (leg.cargoWeightTons ?? 0) : 0,
          endpointType: leg.endpointType,
          endpointDistanceKm: leg.endpointDistanceKm,
        ),
    ];

    final segments = <TripRouteSegment>[];
    double loadedDistance = 0;
    double emptyDistance = 0;
    double loadedFuel = 0;
    double emptyFuel = 0;

    for (var i = 0; i < breakpoints.length; i++) {
      final start = breakpoints[i].odometerKm;
      final end = i + 1 < breakpoints.length ? breakpoints[i + 1].odometerKm : finishOdometer;
      final distance = (end - start).clamp(0, double.infinity).toDouble();
      if (distance <= 0) continue;

      final state = breakpoints[i].cargoState;
      final mass = breakpoints[i].cargoWeightTons;
      // Fuel = F0 + k * M — увеличенный расход применяется только на
      // гружёных участках, у каждого своя масса.
      final rate =
          state == CargoState.loaded ? trip.baseFuelConsumption + trip.fuelConsumptionPerTon * mass : trip.baseFuelConsumption;
      final fuel = distance / 100 * rate;

      if (state == CargoState.loaded) {
        loadedDistance += distance;
        loadedFuel += fuel;
      } else {
        emptyDistance += distance;
        emptyFuel += fuel;
      }

      segments.add(TripRouteSegment(
        startOdometerKm: start,
        endOdometerKm: end,
        distanceKm: distance,
        cargoState: state,
        cargoWeightTons: mass,
        consumptionPer100km: rate,
        fuelLiters: fuel,
        endpointType: breakpoints[i].endpointType,
        endpointDistanceKm: breakpoints[i].endpointDistanceKm,
      ));
    }

    final idlePercent = totalDistance > 0 ? (emptyDistance / totalDistance) * 100 : 0.0;
    // В этой модели весь порожний пробег — коммерческие/логистические
    // перегоны (база↔погрузка, разгрузка↔следующая загрузка/база/дом),
    // поэтому Deadhead KM = Empty KM.
    final deadheadDistance = emptyDistance;

    final calculatedFuel = loadedFuel + emptyFuel;
    final emptyConsumption = emptyDistance > 0 ? emptyFuel / emptyDistance * 100 : trip.baseFuelConsumption;
    final loadedConsumption = loadedDistance > 0 ? loadedFuel / loadedDistance * 100 : 0.0;
    final consumptionIncrease = loadedDistance > 0 ? (loadedConsumption - emptyConsumption) : 0.0;
    final consumptionIncreasePercent = emptyConsumption > 0 ? (consumptionIncrease / emptyConsumption) * 100 : 0.0;

    final refuelLiters = refuels.fold<double>(0, (sum, r) => sum + r.liters);
    final fuelBurned = (trip.startFuelLiters + refuelLiters - finishFuel).clamp(0, double.infinity).toDouble();
    final avgConsumption = totalDistance > 0 ? (fuelBurned / totalDistance) * 100 : 0.0;
    final fuelDeviation = fuelBurned - calculatedFuel;

    final incomePerKmTotal = totalDistance > 0 ? trip.agreedRate / totalDistance : 0.0;
    final incomePerKmLoaded = loadedDistance > 0 ? trip.agreedRate / loadedDistance : 0.0;

    final fuelCost = refuels.fold<double>(0, (sum, r) => sum + r.amount);
    final otherDirect = expenses.fold<double>(0, (sum, e) => sum + e.amount);
    final directTotal = fuelCost + otherDirect;

    final driverPay = trip.driverPayPerKm * totalDistance;
    final perDiemTotal = trip.perDiemPerDay * trip.perDiemDays;
    final depreciationTotal = trip.depreciationPerKm * totalDistance;
    final indirectTotal = driverPay + perDiemTotal + depreciationTotal;

    final totalExpenses = directTotal + indirectTotal;
    final costPerKm = totalDistance > 0 ? totalExpenses / totalDistance : 0.0;
    final netProfit = trip.agreedRate - totalExpenses;
    final marginPercent = trip.agreedRate > 0 ? (netProfit / trip.agreedRate) * 100 : 0.0;

    // Последняя точка с указанным конечным пунктом — это и есть блок
    // "Конечный пункт рейса" в отчёте (порожний возврат после разгрузки).
    _Breakpoint? endpointBreakpoint;
    for (final b in breakpoints.reversed) {
      if (b.endpointType != null) {
        endpointBreakpoint = b;
        break;
      }
    }

    return TripCalculationResult(
      totalDistanceKm: totalDistance,
      loadedDistanceKm: loadedDistance,
      emptyDistanceKm: emptyDistance,
      deadheadDistanceKm: deadheadDistance,
      idlePercent: idlePercent,
      fuelBurnedLiters: fuelBurned,
      avgConsumptionPer100km: avgConsumption,
      calculatedFuelLiters: calculatedFuel,
      fuelDeviationLiters: fuelDeviation,
      emptyConsumptionPer100km: emptyConsumption,
      loadedConsumptionPer100km: loadedConsumption,
      consumptionIncreasePer100km: consumptionIncrease,
      consumptionIncreasePercent: consumptionIncreasePercent,
      emptyFuelLiters: emptyFuel,
      loadedFuelLiters: loadedFuel,
      incomePerKmTotal: incomePerKmTotal,
      incomePerKmLoaded: incomePerKmLoaded,
      fuelCost: fuelCost,
      otherDirectExpenses: otherDirect,
      directExpensesTotal: directTotal,
      driverPay: driverPay,
      perDiemTotal: perDiemTotal,
      depreciationTotal: depreciationTotal,
      indirectExpensesTotal: indirectTotal,
      totalExpenses: totalExpenses,
      costPerKm: costPerKm,
      netProfit: netProfit,
      marginPercent: marginPercent,
      segments: segments,
      endpointType: endpointBreakpoint?.endpointType,
      endpointDistanceKm: endpointBreakpoint?.endpointDistanceKm,
    );
  }
}
