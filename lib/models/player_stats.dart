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
    dynamic v(String camel, String snake) => map[camel] ?? map[snake];
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

    final tournamentId = (v('tournamentId', 'league_id') ?? v('leagueId', 'league_id') ?? '').toString();

    return PlayerStats(
      id: id,
      playerPhone: (v('playerPhone', 'player_phone') ?? '').toString(),
      tournamentId: tournamentId,
      teamId: (v('teamId', 'team_id') ?? '').toString(),
      matchesPlayed: readInt(v('matchesPlayed', 'matches_played')),
      goals: readInt(v('goals', 'goals')),
      assists: readInt(v('assists', 'assists')),
      yellowCards: readInt(v('yellowCards', 'yellow_cards')),
      redCards: readInt(v('redCards', 'red_cards')),
      manOfTheMatch: readInt(v('manOfTheMatch', 'man_of_the_match')),
      createdAt: readDate(v('createdAt', 'created_at')),
      updatedAt: readDate(v('updatedAt', 'updated_at')),
    );
  }

  Map<String, dynamic> toMap({bool snakeCase = false}) {
    if (!snakeCase) {
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
    return {
      'player_phone': playerPhone,
      'league_id': tournamentId,
      'team_id': teamId,
      'matches_played': matchesPlayed,
      'goals': goals,
      'assists': assists,
      'yellow_cards': yellowCards,
      'red_cards': redCards,
      'man_of_the_match': manOfTheMatch,
    };
  }
}
