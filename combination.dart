/// Связка: конкретный тягач + конкретный полуприцеп (или легковая +
/// лёгкий прицеп). Одна и та же машина в течение недели может состоять
/// в разных связках — поэтому связка хранится отдельно и её можно
/// создать/расцепить, не трогая сами карточки тягача и прицепа.
class VehicleCombination {
  final int? id;
  final int powerUnitId;
  final int trailerId;
  final String? label;

  /// Если задано — используется как итоговая масса связки для маршрута
  /// (реальное разрешённое ОГМ связки). Если null — берётся приближённая
  /// сумма (масса тягача без нагрузки + грузоподъёмность прицепа).
  final double? combinedGrossWeightOverride;

  /// Если задано — используется как максимальная осевая нагрузка связки.
  /// Если null — берётся максимум из осевых нагрузок компонентов.
  final double? combinedAxleLoadOverride;

  final bool isActive;
  final DateTime createdAt;

  const VehicleCombination({
    this.id,
    required this.powerUnitId,
    required this.trailerId,
    this.label,
    this.combinedGrossWeightOverride,
    this.combinedAxleLoadOverride,
    this.isActive = false,
    required this.createdAt,
  });

  VehicleCombination copyWith({
    int? id,
    int? powerUnitId,
    int? trailerId,
    String? label,
    double? combinedGrossWeightOverride,
    double? combinedAxleLoadOverride,
    bool? isActive,
    DateTime? createdAt,
    bool clearLabel = false,
    bool clearGrossOverride = false,
    bool clearAxleOverride = false,
  }) {
    return VehicleCombination(
      id: id ?? this.id,
      powerUnitId: powerUnitId ?? this.powerUnitId,
      trailerId: trailerId ?? this.trailerId,
      label: clearLabel ? null : (label ?? this.label),
      combinedGrossWeightOverride: clearGrossOverride
          ? null
          : (combinedGrossWeightOverride ?? this.combinedGrossWeightOverride),
      combinedAxleLoadOverride: clearAxleOverride
          ? null
          : (combinedAxleLoadOverride ?? this.combinedAxleLoadOverride),
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'powerUnitId': powerUnitId,
        'trailerId': trailerId,
        'label': label,
        'combinedGrossWeightOverride': combinedGrossWeightOverride,
        'combinedAxleLoadOverride': combinedAxleLoadOverride,
        'isActive': isActive ? 1 : 0,
        'createdAt': createdAt.toIso8601String(),
      };

  factory VehicleCombination.fromMap(Map<String, Object?> map) => VehicleCombination(
        id: map['id'] as int?,
        powerUnitId: map['powerUnitId'] as int,
        trailerId: map['trailerId'] as int,
        label: map['label'] as String?,
        combinedGrossWeightOverride: (map['combinedGrossWeightOverride'] as num?)?.toDouble(),
        combinedAxleLoadOverride: (map['combinedAxleLoadOverride'] as num?)?.toDouble(),
        isActive: (map['isActive'] as int) == 1,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );
}
