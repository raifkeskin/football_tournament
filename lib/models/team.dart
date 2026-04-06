/// Takım modeli.
class Team {
  const Team({
    required this.id,
    required this.name,
    required this.leagueId,
    required this.logoUrl,
    this.groupName,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String leagueId;
  final String logoUrl;
  final String? groupName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Team.fromMap(Map<String, dynamic> map) {
    return Team(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      leagueId: map['leagueId'] as String? ?? '',
      logoUrl: (map['logoUrl'] ?? map['logo']) as String? ?? '',
      groupName: map['groupName'] as String?,
      createdAt: _readDate(map['createdAt']),
      updatedAt: _readDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'leagueId': leagueId,
      'logoUrl': logoUrl,
      'groupName': groupName,
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
