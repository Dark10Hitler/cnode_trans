enum TripStatus { inProgress, finished }

enum CargoState { loaded, empty }

extension CargoStateX on CargoState {
  String get label => this == CargoState.loaded ? 'С грузом' : 'Порожняком';
}

/// Куда едет машина после разгрузки — нужно для порожнего возврата
/// (Deadhead) и блока "Конечный пункт рейса" в отчёте.
enum TripEndpointType { base, home, nextLoad, other, unknown }

extension TripEndpointTypeX on TripEndpointType {
  String get label => switch (this) {
        TripEndpointType.base => 'База',
        TripEndpointType.home => 'Дом',
        TripEndpointType.nextLoad => 'Следующая загрузка',
        TripEndpointType.other => 'Другая точка',
        TripEndpointType.unknown => 'Пока неизвестно',
      };
}

/// Рейс — верхнеуровневая запись расчёта (раздел "Расчёты").
/// Заполняется в 3 шага (старт / в дороге / финиш), отчёт — 4-й шаг,
/// считается из этих данных, а не хранится отдельно.
///
/// [baseFuelConsumption] (F₀) и [fuelConsumptionPerTon] (k) — модель
/// расхода топлива в зависимости от массы груза: Fuel = F₀ + k × M
/// (M — масса груза в тоннах на конкретном гружёном участке).
class TripRecord {
  final int? id;
  final String label;
  final String currency;
  final TripStatus status;
  final double startOdometerKm;
  final double startFuelLiters;
  final double cargoWeightTons;
  final double agreedRate;
  final double driverPayPerKm;
  final double perDiemPerDay;
  final double perDiemDays;
  final double depreciationPerKm;
  final double baseFuelConsumption;
  final double fuelConsumptionPerTon;
  final double? finishOdometerKm;
  final double? finishFuelLiters;
  final DateTime startedAt;
  final DateTime? finishedAt;

  const TripRecord({
    this.id,
    required this.label,
    this.currency = 'MDL',
    this.status = TripStatus.inProgress,
    required this.startOdometerKm,
    required this.startFuelLiters,
    this.cargoWeightTons = 0,
    required this.agreedRate,
    this.driverPayPerKm = 0,
    this.perDiemPerDay = 0,
    this.perDiemDays = 0,
    this.depreciationPerKm = 0,
    this.baseFuelConsumption = 18,
    this.fuelConsumptionPerTon = 0.47,
    this.finishOdometerKm,
    this.finishFuelLiters,
    required this.startedAt,
    this.finishedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'label': label,
        'currency': currency,
        'status': status.name,
        'startOdometerKm': startOdometerKm,
        'startFuelLiters': startFuelLiters,
        'cargoWeightTons': cargoWeightTons,
        'agreedRate': agreedRate,
        'driverPayPerKm': driverPayPerKm,
        'perDiemPerDay': perDiemPerDay,
        'perDiemDays': perDiemDays,
        'depreciationPerKm': depreciationPerKm,
        'baseFuelConsumption': baseFuelConsumption,
        'fuelConsumptionPerTon': fuelConsumptionPerTon,
        'finishOdometerKm': finishOdometerKm,
        'finishFuelLiters': finishFuelLiters,
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
      };

  factory TripRecord.fromMap(Map<String, Object?> map) => TripRecord(
        id: map['id'] as int?,
        label: map['label'] as String,
        currency: map['currency'] as String? ?? 'MDL',
        status: TripStatus.values.byName(map['status'] as String),
        startOdometerKm: (map['startOdometerKm'] as num).toDouble(),
        startFuelLiters: (map['startFuelLiters'] as num).toDouble(),
        cargoWeightTons: (map['cargoWeightTons'] as num?)?.toDouble() ?? 0,
        agreedRate: (map['agreedRate'] as num).toDouble(),
        driverPayPerKm: (map['driverPayPerKm'] as num?)?.toDouble() ?? 0,
        perDiemPerDay: (map['perDiemPerDay'] as num?)?.toDouble() ?? 0,
        perDiemDays: (map['perDiemDays'] as num?)?.toDouble() ?? 0,
        depreciationPerKm: (map['depreciationPerKm'] as num?)?.toDouble() ?? 0,
        baseFuelConsumption: (map['baseFuelConsumption'] as num?)?.toDouble() ?? 18,
        fuelConsumptionPerTon: (map['fuelConsumptionPerTon'] as num?)?.toDouble() ?? 0.47,
        finishOdometerKm: (map['finishOdometerKm'] as num?)?.toDouble(),
        finishFuelLiters: (map['finishFuelLiters'] as num?)?.toDouble(),
        startedAt: DateTime.parse(map['startedAt'] as String),
        finishedAt: map['finishedAt'] != null ? DateTime.parse(map['finishedAt'] as String) : null,
      );

  TripRecord copyWith({
    double? finishOdometerKm,
    double? finishFuelLiters,
    TripStatus? status,
    DateTime? finishedAt,
  }) {
    return TripRecord(
      id: id,
      label: label,
      currency: currency,
      status: status ?? this.status,
      startOdometerKm: startOdometerKm,
      startFuelLiters: startFuelLiters,
      cargoWeightTons: cargoWeightTons,
      agreedRate: agreedRate,
      driverPayPerKm: driverPayPerKm,
      perDiemPerDay: perDiemPerDay,
      perDiemDays: perDiemDays,
      depreciationPerKm: depreciationPerKm,
      baseFuelConsumption: baseFuelConsumption,
      fuelConsumptionPerTon: fuelConsumptionPerTon,
      finishOdometerKm: finishOdometerKm ?? this.finishOdometerKm,
      finishFuelLiters: finishFuelLiters ?? this.finishFuelLiters,
      startedAt: startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
    );
  }
}

/// Заправка в пути (кнопка "+ Заправка").
class TripRefuel {
  final int? id;
  final int tripId;
  final double liters;
  final double amount;
  final String? photoPath;
  final String? note;
  final DateTime createdAt;

  const TripRefuel({
    this.id,
    required this.tripId,
    required this.liters,
    required this.amount,
    this.photoPath,
    this.note,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'tripId': tripId,
        'liters': liters,
        'amount': amount,
        'photoPath': photoPath,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
      };

  factory TripRefuel.fromMap(Map<String, Object?> map) => TripRefuel(
        id: map['id'] as int?,
        tripId: map['tripId'] as int,
        liters: (map['liters'] as num).toDouble(),
        amount: (map['amount'] as num).toDouble(),
        photoPath: map['photoPath'] as String?,
        note: map['note'] as String?,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );
}

/// Точка смены статуса ("переключение плеча") — одометр, с которого
/// начинается новое состояние (гружёный/порожний).
///
/// [cargoWeightTons] — масса груза, если [cargoState] == loaded (у
/// разных плеч в одном рейсе масса может отличаться — раздельная
/// погрузка/довоз).
///
/// [endpointType]/[endpointDistanceKm] заполняются, когда это плечо —
/// переход в "порожняком" СРАЗУ ПОСЛЕ разгрузки: описывают, куда едет
/// машина дальше (база/дом/следующая загрузка/другое/пока неизвестно)
/// и ожидаемое расстояние порожнего возврата (Deadhead). Это разметка
/// конкретно этого порожнего участка, а не отдельная добавка к
/// пробегу — сам километраж участка всё равно считается по одометру.
class TripLeg {
  final int? id;
  final int tripId;
  final double odometerKm;
  final CargoState cargoState;
  final double? cargoWeightTons;
  final TripEndpointType? endpointType;
  final double? endpointDistanceKm;
  final String? note;
  final DateTime createdAt;

  const TripLeg({
    this.id,
    required this.tripId,
    required this.odometerKm,
    required this.cargoState,
    this.cargoWeightTons,
    this.endpointType,
    this.endpointDistanceKm,
    this.note,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'tripId': tripId,
        'odometerKm': odometerKm,
        'cargoState': cargoState.name,
        'cargoWeightTons': cargoWeightTons,
        'endpointType': endpointType?.name,
        'endpointDistanceKm': endpointDistanceKm,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
      };

  factory TripLeg.fromMap(Map<String, Object?> map) => TripLeg(
        id: map['id'] as int?,
        tripId: map['tripId'] as int,
        odometerKm: (map['odometerKm'] as num).toDouble(),
        cargoState: CargoState.values.byName(map['cargoState'] as String),
        cargoWeightTons: (map['cargoWeightTons'] as num?)?.toDouble(),
        endpointType:
            map['endpointType'] != null ? TripEndpointType.values.byName(map['endpointType'] as String) : null,
        endpointDistanceKm: (map['endpointDistanceKm'] as num?)?.toDouble(),
        note: map['note'] as String?,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );
}

/// Прочий прямой расход в пути (платные дороги, стоянка, мойка, ремонт…).
class TripExpense {
  final int? id;
  final int tripId;
  final String label;
  final double amount;
  final DateTime createdAt;

  const TripExpense({
    this.id,
    required this.tripId,
    required this.label,
    required this.amount,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'tripId': tripId,
        'label': label,
        'amount': amount,
        'createdAt': createdAt.toIso8601String(),
      };

  factory TripExpense.fromMap(Map<String, Object?> map) => TripExpense(
        id: map['id'] as int?,
        tripId: map['tripId'] as int,
        label: map['label'] as String,
        amount: (map['amount'] as num).toDouble(),
        createdAt: DateTime.parse(map['createdAt'] as String),
      );
}
