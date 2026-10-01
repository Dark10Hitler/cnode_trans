import 'power_unit.dart' show HazmatClass, HazmatClassX;

/// Вид прицепной техники: лёгкий прицеп (за легковую, до 750 кг) или
/// полуприцеп (за тягач, через седельно-сцепное устройство).
enum TrailerKind { lightTrailer, semiTrailer }

extension TrailerKindX on TrailerKind {
  String get label =>
      this == TrailerKind.lightTrailer ? 'Лёгкий прицеп (легковая)' : 'Полуприцеп (тягач)';
}

/// Тип кузова полуприцепа.
enum SemiTrailerType { curtainSided, flatbed, reefer, tipper, lowLoader, tanker, containerChassis, other }

extension SemiTrailerTypeX on SemiTrailerType {
  String get label => switch (this) {
        SemiTrailerType.curtainSided => 'Тентованный',
        SemiTrailerType.flatbed => 'Бортовой',
        SemiTrailerType.reefer => 'Рефрижератор',
        SemiTrailerType.tipper => 'Самосвальный',
        SemiTrailerType.lowLoader => 'Низкорамный',
        SemiTrailerType.tanker => 'Цистерна',
        SemiTrailerType.containerChassis => 'Контейнеровоз (шасси)',
        SemiTrailerType.other => 'Прочее (нестандартная конструкция)',
      };
}

/// Прицеп или полуприцеп — самостоятельная единица, которую можно
/// присоединять к разным тягачам/машинам и переприсоединять (связки).
class Trailer {
  final int? id;
  final TrailerKind kind;
  final SemiTrailerType? semiTrailerType; // только для kind == semiTrailer
  final String? lightTrailerType; // свободный текст, только для лёгкого прицепа
  final String? brand;
  final String? model;
  final String? vin; // необязательно
  final int? axleCount;
  final String? axleType;
  final double? maxAxleLoad; // т
  final double? payloadCapacity; // т
  final double? emptyWeight; // т
  final double height; // м
  final double width; // м
  final double length; // м

  /// Опасный груз сертифицирован именно на этой единице (частый случай:
  /// ADR-свидетельство выдаётся на цистерну/прицеп, а не на тягач).
  final bool hazmat;
  final HazmatClass? hazmatClass;
  final DateTime createdAt;

  const Trailer({
    this.id,
    required this.kind,
    this.semiTrailerType,
    this.lightTrailerType,
    this.brand,
    this.model,
    this.vin,
    this.axleCount,
    this.axleType,
    this.maxAxleLoad,
    this.payloadCapacity,
    this.emptyWeight,
    required this.height,
    required this.width,
    required this.length,
    this.hazmat = false,
    this.hazmatClass,
    required this.createdAt,
  });

  String get displayName {
    final b = brand?.isNotEmpty == true ? brand! : (kind == TrailerKind.semiTrailer ? 'Полуприцеп' : 'Прицеп');
    final typeLabel = kind == TrailerKind.semiTrailer ? semiTrailerType?.label : lightTrailerType;
    return typeLabel != null && typeLabel.isNotEmpty ? '$b · $typeLabel' : b;
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'kind': kind.name,
        'semiTrailerType': semiTrailerType?.name,
        'lightTrailerType': lightTrailerType,
        'brand': brand,
        'model': model,
        'vin': vin,
        'axleCount': axleCount,
        'axleType': axleType,
        'maxAxleLoad': maxAxleLoad,
        'payloadCapacity': payloadCapacity,
        'emptyWeight': emptyWeight,
        'height': height,
        'width': width,
        'length': length,
        'hazmat': hazmat ? 1 : 0,
        'hazmatClass': hazmatClass?.name,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Trailer.fromMap(Map<String, Object?> map) => Trailer(
        id: map['id'] as int?,
        kind: TrailerKind.values.byName(map['kind'] as String),
        semiTrailerType: map['semiTrailerType'] != null
            ? SemiTrailerType.values.byName(map['semiTrailerType'] as String)
            : null,
        lightTrailerType: map['lightTrailerType'] as String?,
        brand: map['brand'] as String?,
        model: map['model'] as String?,
        vin: map['vin'] as String?,
        axleCount: map['axleCount'] as int?,
        axleType: map['axleType'] as String?,
        maxAxleLoad: (map['maxAxleLoad'] as num?)?.toDouble(),
        payloadCapacity: (map['payloadCapacity'] as num?)?.toDouble(),
        emptyWeight: (map['emptyWeight'] as num?)?.toDouble(),
        height: (map['height'] as num).toDouble(),
        width: (map['width'] as num).toDouble(),
        length: (map['length'] as num).toDouble(),
        hazmat: (map['hazmat'] as int? ?? 0) == 1,
        hazmatClass:
            map['hazmatClass'] != null ? HazmatClass.values.byName(map['hazmatClass'] as String) : null,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );
}
