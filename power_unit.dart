/// Категория силового ТС. Разделена так, как реально устроен парк:
/// тягач отдельно от полуприцепа, грузовики-солобортовики — по тоннажу.
enum PowerUnitCategory { bicycle, car, bus, rigidTruck5t, rigidTruck8t, tractorUnit }

extension PowerUnitCategoryX on PowerUnitCategory {
  String get label => switch (this) {
    PowerUnitCategory.bicycle => 'Велосипед',
    PowerUnitCategory.car => 'Легковая',
    PowerUnitCategory.bus => 'Автобус',
    PowerUnitCategory.rigidTruck5t => 'Грузовик 5т',
    PowerUnitCategory.rigidTruck8t => 'Грузовик 8т',
    PowerUnitCategory.tractorUnit => 'Тягач (под полуприцеп)',
  };

  String get icon => switch (this) {
    PowerUnitCategory.bicycle => '🚲',
    PowerUnitCategory.car => '🚗',
    PowerUnitCategory.bus => '🚌',
    PowerUnitCategory.rigidTruck5t => '🚚',
    PowerUnitCategory.rigidTruck8t => '🚛',
    PowerUnitCategory.tractorUnit => '🚛',
  };

  /// Costing-профиль Valhalla. У Valhalla нет отдельных профилей под
  /// 5т/8т/тягач — все три используют `truck`, различие даётся через
  /// costing_options (height/width/length/weight/axle_load).
  /// ВАЖНО: сами дорожные ограничения по габаритам Valhalla применяет
  /// только к costing=truck — для auto/bus/bicycle/pedestrian
  /// height/width/length на выбор пути не влияют (это ограничение самого
  /// Valhalla, не наше). Поэтому для car/bus/bicycle эти поля хранятся
  /// для полноты профиля и на будущее, но маршрут они пока не сужают.
  String get valhallaCosting => switch (this) {
    PowerUnitCategory.bicycle => 'bicycle',
    PowerUnitCategory.car => 'auto',
    PowerUnitCategory.bus => 'bus',
    PowerUnitCategory.rigidTruck5t => 'truck',
    PowerUnitCategory.rigidTruck8t => 'truck',
    PowerUnitCategory.tractorUnit => 'truck',
  };

  /// Может ли этот ТС буксировать лёгкий прицеп (актуально по факту
  /// только для легковой — категория B, до 750 кг без тормозов прицепа).
  bool get canTowLightTrailer => this == PowerUnitCategory.car;

  /// Может ли этот ТС работать в связке с полуприцепом (пятое колесо).
  bool get canCoupleSemiTrailer => this == PowerUnitCategory.tractorUnit;

  /// Упрощённая форма (только базовые поля) — сейчас только велосипед,
  /// у которого нет VIN/массы-нетто/экокласса и т.д.
  bool get isSimpleProfile => this == PowerUnitCategory.bicycle;
}

/// Классы опасных грузов ADR (1–9, с подклассами, как в самой конвенции ADR).
enum HazmatClass {
  c1, c2, c3, c41, c42, c43, c51, c52, c61, c62, c7, c8, c9,
}

extension HazmatClassX on HazmatClass {
  String get code => switch (this) {
    HazmatClass.c1 => '1',
    HazmatClass.c2 => '2',
    HazmatClass.c3 => '3',
    HazmatClass.c41 => '4.1',
    HazmatClass.c42 => '4.2',
    HazmatClass.c43 => '4.3',
    HazmatClass.c51 => '5.1',
    HazmatClass.c52 => '5.2',
    HazmatClass.c61 => '6.1',
    HazmatClass.c62 => '6.2',
    HazmatClass.c7 => '7',
    HazmatClass.c8 => '8',
    HazmatClass.c9 => '9',
  };

  String get label => switch (this) {
    HazmatClass.c1 => '1 — Взрывчатые вещества и изделия',
    HazmatClass.c2 => '2 — Газы',
    HazmatClass.c3 => '3 — Легковоспламеняющиеся жидкости',
    HazmatClass.c41 => '4.1 — Легковоспламеняющиеся твёрдые вещества',
    HazmatClass.c42 => '4.2 — Самовозгорающиеся вещества',
    HazmatClass.c43 => '4.3 — Вещества, выделяющие газы при контакте с водой',
    HazmatClass.c51 => '5.1 — Окисляющие вещества',
    HazmatClass.c52 => '5.2 — Органические пероксиды',
    HazmatClass.c61 => '6.1 — Токсичные вещества',
    HazmatClass.c62 => '6.2 — Инфекционные вещества',
    HazmatClass.c7 => '7 — Радиоактивные материалы',
    HazmatClass.c8 => '8 — Коррозионные вещества',
    HazmatClass.c9 => '9 — Прочие опасные вещества и изделия',
  };
}

/// Силовое транспортное средство (тягач / соло-грузовик / легковая /
/// автобус / велосипед). Поля соответствуют типовому набору из
/// техпаспорта: часть обязательна, часть — явно необязательна (VIN,
/// VIN шасси, тип двигателя — как в реальном документе).
class PowerUnit {
  final int? id;
  final PowerUnitCategory category;
  final String brand;
  final String? model;
  final int? year;
  final String? vin; // необязательно
  final String? chassisVin; // необязательно
  final String? engineType; // необязательно
  final double? grossWeight; // т, разрешённая максимальная масса
  final double? curbWeight; // т, масса без нагрузки
  final double? payloadCapacity; // т, грузоподъёмность
  final String? wheelFormula; // напр. "4x2", "6x4"
  final int? axleCount; // кол-во осей (необязательно, можно рассчитать по wheelFormula)
  final String? cabinType;
  final String? environmentalClass; // напр. "Euro 6"
  final double? weightKg; // только для велосипеда, кг
  final double height; // м
  final double width; // м
  final double length; // м
  final bool hazmat;
  final HazmatClass? hazmatClass;
  final bool isActive;
  final DateTime createdAt;

  const PowerUnit({
    this.id,
    required this.category,
    required this.brand,
    this.model,
    this.year,
    this.vin,
    this.chassisVin,
    this.engineType,
    this.grossWeight,
    this.curbWeight,
    this.payloadCapacity,
    this.wheelFormula,
    this.axleCount,
    this.cabinType,
    this.environmentalClass,
    this.weightKg,
    required this.height,
    required this.width,
    required this.length,
    this.hazmat = false,
    this.hazmatClass,
    this.isActive = false,
    required this.createdAt,
  });

  String get displayName => model != null && model!.isNotEmpty ? '$brand$model' : brand;

  /// Автоматический расчет количества осей по колесной формуле (если не задано явно)
  int get axleCountCalculated {
    if (axleCount != null) return axleCount!;
    if (wheelFormula != null && wheelFormula!.contains('x')) {
      final parts = wheelFormula!.toLowerCase().split('x');
      final totalWheels = int.tryParse(parts.first.trim());
      if (totalWheels != null) {
        return (totalWheels / 2).round();
      }
    }
    return 2; // Базовое значение для большинства ТС
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'category': category.name,
    'brand': brand,
    'model': model,
    'year': year,
    'vin': vin,
    'chassisVin': chassisVin,
    'engineType': engineType,
    'grossWeight': grossWeight,
    'curbWeight': curbWeight,
    'payloadCapacity': payloadCapacity,
    'wheelFormula': wheelFormula,
    'axleCount': axleCount,
    'cabinType': cabinType,
    'environmentalClass': environmentalClass,
    'weightKg': weightKg,
    'height': height,
    'width': width,
    'length': length,
    'hazmat': hazmat ? 1 : 0,
    'hazmatClass': hazmatClass?.name,
    'isActive': isActive ? 1 : 0,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PowerUnit.fromMap(Map<String, Object?> map) => PowerUnit(
    id: map['id'] as int?,
    category: PowerUnitCategory.values.byName(map['category'] as String),
    brand: map['brand'] as String,
    model: map['model'] as String?,
    year: map['year'] as int?,
    vin: map['vin'] as String?,
    chassisVin: map['chassisVin'] as String?,
    engineType: map['engineType'] as String?,
    grossWeight: (map['grossWeight'] as num?)?.toDouble(),
    curbWeight: (map['curbWeight'] as num?)?.toDouble(),
    payloadCapacity: (map['payloadCapacity'] as num?)?.toDouble(),
    wheelFormula: map['wheelFormula'] as String?,
    axleCount: map['axleCount'] as int?,
    cabinType: map['cabinType'] as String?,
    environmentalClass: map['environmentalClass'] as String?,
    weightKg: (map['weightKg'] as num?)?.toDouble(),
    height: (map['height'] as num).toDouble(),
    width: (map['width'] as num).toDouble(),
    length: (map['length'] as num).toDouble(),
    hazmat: (map['hazmat'] as int) == 1,
    hazmatClass: map['hazmatClass'] != null
        ? HazmatClass.values.byName(map['hazmatClass'] as String)
        : null,
    isActive: (map['isActive'] as int) == 1,
    createdAt: DateTime.parse(map['createdAt'] as String),
  );
}