import 'package:cloud_firestore/cloud_firestore.dart';

class Award {
  const Award({
    required this.id,
    required this.tournamentId,
    required this.awardName,
    this.description,
    this.createdAt,
  });

  final String id;
  final String tournamentId;
  final String awardName;
  final String? description;
  final DateTime? createdAt;

  factory Award.fromMap(Map<String, dynamic> map, String id) {
    dynamic v(String camel, String snake) => map[camel] ?? map[snake];
    final created = map['createdAt'];
    DateTime? createdAt;
    if (created is Timestamp) createdAt = created.toDate();
    if (created is String) createdAt = DateTime.tryParse(created);
    if (created is int) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(created);
    }
    final leagueId = (v('leagueId', 'league_id') ?? '').toString();
    final tournamentId =
        (v('tournamentId', 'tournament_id') ?? leagueId).toString();
    final name = (v('awardName', 'award_name') ?? map['name'] ?? '').toString();
    final description = (map['description'] as String?)?.toString();
    return Award(
      id: id,
      tournamentId: tournamentId,
      awardName: name,
      description: description,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap({bool snakeCase = false}) {
    if (!snakeCase) {
      return {
        'tournamentId': tournamentId,
        'leagueId': tournamentId,
        'awardName': awardName,
        'name': awardName,
        'description': description,
      };
    }
    return {
      'tournament_id': tournamentId,
      'league_id': tournamentId,
      'award_name': awardName,
      'name': awardName,
      'description': description,
    };
  }
}
