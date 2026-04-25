import 'package:cloud_firestore/cloud_firestore.dart';

class Team {
  const Team({
    required this.id,
    required this.name,
    required this.logoUrl,
    this.leagueId,
    this.groupId,
    this.groupName,
    this.colors,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String logoUrl;
  final String? leagueId;
  final String? groupId;
  final String? groupName;
  final Map<String, dynamic>? colors;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Team.fromMap(Map<String, dynamic> map) {
    dynamic v(String camel, String snake) => map[camel] ?? map[snake];
    String? readNullableString(dynamic value) {
      final s = (value ?? '').toString().trim();
      return s.isEmpty ? null : s;
    }

    return Team(
      id: (v('id', 'id') as String?) ?? '',
      name: (v('name', 'name') as String?) ?? '',
      logoUrl: (v('logoUrl', 'logo_url') ?? v('logo', 'logo')) as String? ?? '',
      leagueId: readNullableString(v('leagueId', 'league_id')),
      groupId: readNullableString(v('groupId', 'group_id')),
      groupName: readNullableString(v('groupName', 'group_name')),
      colors: v('colors', 'colors') as Map<String, dynamic>?,
      createdAt: _readDate(v('createdAt', 'created_at')),
      updatedAt: _readDate(v('updatedAt', 'updated_at')),
    );
  }

  Map<String, dynamic> toMap({bool snakeCase = false}) {
    if (!snakeCase) {
      return {
        'id': id,
        'name': name,
        'logoUrl': logoUrl,
        'leagueId': leagueId,
        'groupId': groupId,
        'groupName': groupName,
        'colors': colors,
      };
    }
    return {
      'id': id,
      'name': name,
      'logo_url': logoUrl,
      'league_id': leagueId,
      'group_id': groupId,
      'group_name': groupName,
      'colors': colors,
    };
  }

  static DateTime? _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
