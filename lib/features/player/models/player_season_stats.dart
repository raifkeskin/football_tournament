import 'package:cloud_firestore/cloud_firestore.dart';

class PlayerSeasonStat {
  const PlayerSeasonStat({
    required this.id,
    required this.playerPhone,
    required this.seasonId,
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
  final String seasonId;
  final String teamId;
  final int matchesPlayed;
  final int goals;
  final int assists;
  final int yellowCards;
  final int redCards;
  final int manOfTheMatch;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static String docId({required String playerPhone, required String seasonId}) {
    return '${playerPhone.trim()}_${seasonId.trim()}';
  }

  factory PlayerSeasonStat.fromMap(Map<String, dynamic> map, String id) {
    dynamic v(String camel, String snake) => map[camel] ?? map[snake];
    int readInt(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      final s = v.toString().replaceAll('\u0000', '').trim();
      return int.tryParse(s) ??
          double.tryParse(s.replaceAll(',', '.'))?.toInt() ??
          0;
    }

    DateTime? readDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    final seasonId =
        (v('seasonId', 'season_id') ?? v('tournamentId', 'season_id') ?? '')
            .toString();

    return PlayerSeasonStat(
      id: id,
      playerPhone: (v('playerPhone', 'player_phone') ?? '').toString(),
      seasonId: seasonId,
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
        'seasonId': seasonId,
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
      'season_id': seasonId,
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
