enum DocumentFileType { pdf, jpg, png }

extension DocumentFileTypeX on DocumentFileType {
  String get label => switch (this) {
        DocumentFileType.pdf => 'PDF',
        DocumentFileType.jpg => 'JPG',
        DocumentFileType.png => 'PNG',
      };

  static DocumentFileType fromExtension(String ext) {
    final normalized = ext.toLowerCase().replaceAll('.', '');
    return switch (normalized) {
      'jpg' || 'jpeg' => DocumentFileType.jpg,
      'png' => DocumentFileType.png,
      _ => DocumentFileType.pdf,
    };
  }
}

/// К кому привязан документ. Отдельно от "какого он типа" — так документы
/// на водителя, на конкретное ТС/прицеп, на связку и на организацию
/// хранятся в одной таблице, но чётко разведены по владельцу.
enum DocumentOwnerType { driver, powerUnit, trailer, combination, organization }

extension DocumentOwnerTypeX on DocumentOwnerType {
  String get label => switch (this) {
        DocumentOwnerType.driver => 'Водитель',
        DocumentOwnerType.powerUnit => 'Тягач / грузовик / легковая',
        DocumentOwnerType.trailer => 'Прицеп / полуприцеп',
        DocumentOwnerType.combination => 'Связка',
        DocumentOwnerType.organization => 'Организация перевозки',
      };
}

enum DocumentCategory {
  driverLicense,
  medicalCertificate,
  adrCertificate,
  registrationCertificate,
  insurance,
  technicalInspection,
  wayBill,
  transportContract,
  customsDocument,
  other,
}

extension DocumentCategoryX on DocumentCategory {
  String get label => switch (this) {
        DocumentCategory.driverLicense => 'Водительское удостоверение',
        DocumentCategory.medicalCertificate => 'Медицинская справка',
        DocumentCategory.adrCertificate => 'Свидетельство ADR (опасные грузы)',
        DocumentCategory.registrationCertificate => 'Свидетельство о регистрации / техпаспорт',
        DocumentCategory.insurance => 'Страховка (ОСАГО / КАСКО / Green Card)',
        DocumentCategory.technicalInspection => 'Техосмотр',
        DocumentCategory.wayBill => 'ТТН / CMR / накладная',
        DocumentCategory.transportContract => 'Договор перевозки',
        DocumentCategory.customsDocument => 'Таможенный документ',
        DocumentCategory.other => 'Прочее',
      };

  /// Подходящие категории для конкретного типа владельца — используется
  /// для сужения выпадающего списка при добавлении документа.
  static List<DocumentCategory> forOwner(DocumentOwnerType owner) {
    return switch (owner) {
      DocumentOwnerType.driver => [
          DocumentCategory.driverLicense,
          DocumentCategory.medicalCertificate,
          DocumentCategory.adrCertificate,
          DocumentCategory.other,
        ],
      DocumentOwnerType.organization => [
          DocumentCategory.transportContract,
          DocumentCategory.wayBill,
          DocumentCategory.customsDocument,
          DocumentCategory.other,
        ],
      _ => [
          DocumentCategory.registrationCertificate,
          DocumentCategory.insurance,
          DocumentCategory.technicalInspection,
          DocumentCategory.adrCertificate,
          DocumentCategory.other,
        ],
    };
  }
}

/// Документ, привязанный к владельцу (водитель / силовое ТС / прицеп /
/// связка / организация) через [ownerType] + [ownerId]. Для водителя
/// ownerId совпадает с [DriverProfile.singletonId] (= 1).
class AppDocument {
  final int? id;
  final DocumentOwnerType ownerType;
  final int ownerId;
  final DocumentCategory category;
  final String name;
  final DocumentFileType fileType;
  final DateTime? expiryDate;
  final String filePath;
  final DateTime createdAt;

  const AppDocument({
    this.id,
    required this.ownerType,
    required this.ownerId,
    required this.category,
    required this.name,
    required this.fileType,
    this.expiryDate,
    required this.filePath,
    required this.createdAt,
  });

  bool get isExpired => expiryDate != null && expiryDate!.isBefore(DateTime.now());

  bool get isExpiringSoon =>
      expiryDate != null && !isExpired && expiryDate!.difference(DateTime.now()).inDays <= 30;

  AppDocument copyWith({
    int? id,
    DocumentOwnerType? ownerType,
    int? ownerId,
    DocumentCategory? category,
    String? name,
    DocumentFileType? fileType,
    DateTime? expiryDate,
    String? filePath,
    DateTime? createdAt,
    bool clearExpiryDate = false,
  }) {
    return AppDocument(
      id: id ?? this.id,
      ownerType: ownerType ?? this.ownerType,
      ownerId: ownerId ?? this.ownerId,
      category: category ?? this.category,
      name: name ?? this.name,
      fileType: fileType ?? this.fileType,
      expiryDate: clearExpiryDate ? null : (expiryDate ?? this.expiryDate),
      filePath: filePath ?? this.filePath,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'ownerType': ownerType.name,
        'ownerId': ownerId,
        'category': category.name,
        'name': name,
        'fileType': fileType.name,
        'expiryDate': expiryDate?.toIso8601String(),
        'filePath': filePath,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AppDocument.fromMap(Map<String, Object?> map) => AppDocument(
        id: map['id'] as int?,
        ownerType: DocumentOwnerType.values.byName(map['ownerType'] as String),
        ownerId: map['ownerId'] as int,
        category: DocumentCategory.values.byName(map['category'] as String),
        name: map['name'] as String,
        fileType: DocumentFileType.values.byName(map['fileType'] as String),
        expiryDate: map['expiryDate'] != null ? DateTime.parse(map['expiryDate'] as String) : null,
        filePath: map['filePath'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );
}
