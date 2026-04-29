import 'package:cloud_firestore/cloud_firestore.dart';

class Team {
  const Team({
    required this.id,
    required this.name,
    required this.logoUrl,
    String? seasonId,
    String? leagueId,
    this.groupId,
    this.groupName,
    this.colors,
    this.createdAt,
    this.updatedAt,
  }) : seasonId = seasonId ?? leagueId;

  final String id;
  final String name;
  final String logoUrl;
  final String? seasonId;
  String? get leagueId => seasonId;
  final String? groupId;
  final String? groupName;
  final Map<String, dynamic>? colors;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Team.fromMap(Map<String, dynamic> map) {
    final nestedTeamRaw = map['team'] ?? map['teams'];
    final nestedGroupRaw = map['group'] ?? map['groups'];
    final teamMap = nestedTeamRaw is Map
        ? Map<String, dynamic>.from(nestedTeamRaw as Map)
        : map;
    final groupMap = nestedGroupRaw is Map
        ? Map<String, dynamic>.from(nestedGroupRaw as Map)
        : const <String, dynamic>{};

    dynamic v(String camel, String snake) =>
        teamMap[camel] ?? teamMap[snake] ?? map[camel] ?? map[snake];
    String? readNullableString(dynamic value) {
      final s = (value ?? '').toString().trim();
      return s.isEmpty ? null : s;
    }

    final seasonId = readNullableString(map['seasonId'] ?? map['season_id']) ??
        readNullableString(teamMap['seasonId'] ?? teamMap['season_id']) ??
        readNullableString(map['leagueId'] ?? map['league_id']) ??
        readNullableString(teamMap['leagueId'] ?? teamMap['league_id']);

    final groupId = readNullableString(map['groupId'] ?? map['group_id']) ??
        readNullableString(teamMap['groupId'] ?? teamMap['group_id']);

    final groupNameFromGroup = readNullableString(
      groupMap['name'] ?? groupMap['group_name'] ?? groupMap['groupName'],
    );
    final groupName = readNullableString(map['groupName'] ?? map['group_name']) ??
        readNullableString(teamMap['groupName'] ?? teamMap['group_name']) ??
        groupNameFromGroup;

    return Team(
      id: (v('id', 'id') as String?) ?? '',
      name: (v('name', 'name') as String?) ?? '',
      logoUrl: (v('logoUrl', 'logo_url') ?? v('logo', 'logo')) as String? ?? '',
      seasonId: seasonId,
      groupId: groupId,
      groupName: groupName,
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
        'seasonId': seasonId,
        'groupId': groupId,
        'groupName': groupName,
        'colors': colors,
      };
    }
    return {
      'id': id,
      'name': name,
      'logo_url': logoUrl,
      'season_id': seasonId,
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
