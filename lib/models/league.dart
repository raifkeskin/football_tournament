/// Çoklu lig desteği için temel League modeli.
class League {
  const League({
    required this.id,
    required this.name,
    required this.logo,
    required this.country,
    this.season,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String logo;
  final String country;
  final String? season;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory League.fromMap(Map<String, dynamic> map) {
    return League(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      logo: map['logo'] as String? ?? '',
      country: map['country'] as String? ?? '',
      season: map['season'] as String?,
      isActive: map['isActive'] as bool? ?? true,
      createdAt: _readDate(map['createdAt']),
      updatedAt: _readDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'logo': logo,
      'country': country,
      'season': season,
      'isActive': isActive,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  static DateTime? _readDate(dynamic value) {
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
