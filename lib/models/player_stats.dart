import 'package:cloud_firestore/cloud_firestore.dart';

class PlayerStats {
  const PlayerStats({
    required this.id,
    required this.playerPhone,
    required this.tournamentId,
    required this.teamId,
    this.matchesPlayed = 0,
    this.goals = 0,
    this.assists = 0,
    this.yellowCards = 0,
    this.redCards = 0,
    this.manOfTheMatch = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String playerPhone;
  final String tournamentId;
  final String teamId;
  final int matchesPlayed;
  final int goals;
  final int assists;
  final int yellowCards;
  final int redCards;
  final int manOfTheMatch;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static String docId({required String playerPhone, required String tournamentId}) {
    return '${playerPhone.trim()}_${tournamentId.trim()}';
  }

  factory PlayerStats.fromMap(Map<String, dynamic> map, String id) {
    int readInt(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      final s = v.toString().replaceAll('\u0000', '').trim();
      return int.tryParse(s) ?? double.tryParse(s.replaceAll(',', '.'))?.toInt() ?? 0;
    }

    DateTime? readDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    final tournamentId = (map['tournamentId'] ?? map['leagueId'] ?? '').toString();

    return PlayerStats(
      id: id,
      playerPhone: (map['playerPhone'] ?? '').toString(),
      tournamentId: tournamentId,
      teamId: (map['teamId'] ?? '').toString(),
      matchesPlayed: readInt(map['matchesPlayed']),
      goals: readInt(map['goals']),
      assists: readInt(map['assists']),
      yellowCards: readInt(map['yellowCards']),
      redCards: readInt(map['redCards']),
      manOfTheMatch: readInt(map['manOfTheMatch']),
      createdAt: readDate(map['createdAt']),
      updatedAt: readDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'playerPhone': playerPhone,
      'tournamentId': tournamentId,
      'teamId': teamId,
      'matchesPlayed': matchesPlayed,
      'goals': goals,
      'assists': assists,
      'yellowCards': yellowCards,
      'redCards': redCards,
      'manOfTheMatch': manOfTheMatch,
    };
  }
}

