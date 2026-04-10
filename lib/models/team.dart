/// Takım modeli.
import 'package:cloud_firestore/cloud_firestore.dart';

class Team {
  const Team({
    required this.id,
    required this.name,
    required this.leagueId,
    required this.logoUrl,
    this.groupId,
    this.groupName,
    this.stats,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String leagueId;
  final String logoUrl;
  final String? groupId;
  final String? groupName;
  final Map<String, dynamic>? stats; // P, G, B, M, AG, YG, AV, Puan
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Team.fromMap(Map<String, dynamic> map) {
    return Team(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      leagueId: map['leagueId'] as String? ?? '',
      logoUrl: (map['logoUrl'] ?? map['logo']) as String? ?? '',
      groupId: map['groupId'] as String?,
      groupName: map['groupName'] as String?,
      stats: map['stats'] as Map<String, dynamic>?,
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
      'groupId': groupId,
      'groupName': groupName,
      'stats': stats,
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
