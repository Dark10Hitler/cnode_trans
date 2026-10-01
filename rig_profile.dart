import 'combination.dart';
import 'power_unit.dart';
import 'trailer.dart';

/// Итоговый "профиль борта", который реально участвует в маршрутизации,
/// в подсказках ассистента и в шапке экрана "Карта". Считается либо из
/// одного силового ТС (соло), либо из связки (силовое ТС + прицеп).
class RigProfile {
  final String label;
  final String valhallaCosting;
  final double height;
  final double width;
  final double length;
  final double weight; // т, суммарно
  final double axleLoad; // т, максимум/связка
  final bool hazmat;
  final String? hazmatClass;
  final PowerUnit powerUnit;
  final Trailer? trailer;
  final VehicleCombination? combination;

  const RigProfile({
    required this.label,
    required this.valhallaCosting,
    required this.height,
    required this.width,
    required this.length,
    required this.weight,
    required this.axleLoad,
    required this.hazmat,
    required this.hazmatClass,
    required this.powerUnit,
    this.trailer,
    this.combination,
  });

  /// Уникальный строковый идентификатор борта (для выбора в UI и активации в AppState)
  String get id {
    if (combination != null) {
      return 'combo_${combination!.id}';
    }
    return 'power_${powerUnit.id}';
  }

  factory RigProfile.solo(PowerUnit unit) {
    final weight = unit.category.isSimpleProfile
        ? (unit.weightKg ?? 0) / 1000
        : (unit.grossWeight ?? unit.curbWeight ?? 0);
    return RigProfile(
      label: unit.displayName,
      valhallaCosting: unit.category.valhallaCosting,
      height: unit.height,
      width: unit.width,
      length: unit.length,
      weight: weight,
      axleLoad: weight, // нет отдельных данных по осям у соло-ТС
      hazmat: unit.hazmat,
      hazmatClass: unit.hazmatClass?.label,
      powerUnit: unit,
    );
  }

  factory RigProfile.combo(PowerUnit unit, Trailer trailer, VehicleCombination combo) {
    final autoWeight = (unit.curbWeight ?? 0) + (trailer.payloadCapacity ?? 0) + (trailer.emptyWeight ?? 0);
    final weight = combo.combinedGrossWeightOverride ?? (autoWeight > 0 ? autoWeight : (unit.grossWeight ?? 0));
    final autoAxleLoad = [unit.grossWeight ?? 0, trailer.maxAxleLoad ?? 0].reduce((a, b) => a > b ? a : b);
    final axleLoad = combo.combinedAxleLoadOverride ?? (autoAxleLoad > 0 ? autoAxleLoad : weight);

    // Опасный груз может быть сертифицирован на любой из двух единиц —
    // на тягаче ИЛИ на самом прицепе/цистерне (частый случай на практике).
    final hazmat = unit.hazmat || trailer.hazmat;
    final hazmatClass = trailer.hazmat ? trailer.hazmatClass?.label : unit.hazmatClass?.label;

    return RigProfile(
      label: combo.label?.isNotEmpty == true
          ? combo.label!
          : '${unit.displayName} + ${trailer.displayName}',
      valhallaCosting: unit.category.valhallaCosting,
      height: _max(unit.height, trailer.height),
      width: _max(unit.width, trailer.width),
      length: unit.length + trailer.length,
      weight: weight,
      axleLoad: axleLoad,
      hazmat: hazmat,
      hazmatClass: hazmatClass,
      powerUnit: unit,
      trailer: trailer,
      combination: combo,
    );
  }

  static double _max(double a, double b) => a > b ? a : b;

  // Геттеры для совместимости и удобства вызова
  double get heightM => height;
  double get widthM => width;
  double get lengthM => length;
  double get weightTons => weight;

  /// Динамический расчёт суммарного количества осей автопоезда
  int get axles {
    final powerAxles = powerUnit.axleCount ?? 2;
    final trailerAxles = trailer?.axleCount ?? 0;
    return powerAxles + trailerAxles;
  }

  /// Формирование параметров costing_options для C++ движка Valhalla
  Map<String, dynamic> toValhallaJson() {
    final costing = valhallaCosting.isNotEmpty ? valhallaCosting : 'truck';

    return {
      'costing': costing,
      'costing_options': {
        costing: {
          'height': height,
          'width': width,
          'length': length,
          'weight': weight,
          'axle_load': axleLoad,
          'axle_count': axles,
          'hazmat': hazmat,
        }
      }
    };
  }
}