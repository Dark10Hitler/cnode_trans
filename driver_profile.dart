/// Профиль водителя — в MVP один на приложение (личный инструмент
/// водителя, не мультипарковая система). id всегда [singletonId].
class DriverProfile {
  static const int singletonId = 1;

  final int id;
  final String fullName;
  final String? licenseNumber;
  final String? licenseCategories; // напр. "B, C, CE"
  final DateTime? licenseExpiry;

  const DriverProfile({
    this.id = singletonId,
    required this.fullName,
    this.licenseNumber,
    this.licenseCategories,
    this.licenseExpiry,
  });

  DriverProfile copyWith({
    String? fullName,
    String? licenseNumber,
    String? licenseCategories,
    DateTime? licenseExpiry,
    bool clearLicenseNumber = false,
    bool clearLicenseCategories = false,
    bool clearLicenseExpiry = false,
  }) {
    return DriverProfile(
      id: id,
      fullName: fullName ?? this.fullName,
      licenseNumber: clearLicenseNumber ? null : (licenseNumber ?? this.licenseNumber),
      licenseCategories:
          clearLicenseCategories ? null : (licenseCategories ?? this.licenseCategories),
      licenseExpiry: clearLicenseExpiry ? null : (licenseExpiry ?? this.licenseExpiry),
    );
  }

  bool get licenseExpired => licenseExpiry != null && licenseExpiry!.isBefore(DateTime.now());

  bool get licenseExpiringSoon =>
      licenseExpiry != null && !licenseExpired && licenseExpiry!.difference(DateTime.now()).inDays <= 30;

  Map<String, Object?> toMap() => {
        'id': id,
        'fullName': fullName,
        'licenseNumber': licenseNumber,
        'licenseCategories': licenseCategories,
        'licenseExpiry': licenseExpiry?.toIso8601String(),
      };

  factory DriverProfile.fromMap(Map<String, Object?> map) => DriverProfile(
        id: map['id'] as int? ?? singletonId,
        fullName: map['fullName'] as String? ?? '',
        licenseNumber: map['licenseNumber'] as String?,
        licenseCategories: map['licenseCategories'] as String?,
        licenseExpiry:
            map['licenseExpiry'] != null ? DateTime.parse(map['licenseExpiry'] as String) : null,
      );
}
