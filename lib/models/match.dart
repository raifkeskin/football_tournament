import 'package:cloud_firestore/cloud_firestore.dart';

enum MatchStatus { notStarted, live, finished }

class LineupPlayer {
  const LineupPlayer({required this.playerId, required this.name, this.number});

  final String playerId;
  final String name;
  final String? number;

  factory LineupPlayer.fromMap(Map<String, dynamic> map) {
    return LineupPlayer(
      playerId: map['playerId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      number: map['number']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {'playerId': playerId, 'name': name, 'number': number};
  }
}

class MatchLineup {
  const MatchLineup({required this.starting, required this.subs});

  final List<LineupPlayer> starting;
  final List<LineupPlayer> subs;

  factory MatchLineup.fromMap(Map<String, dynamic> map) {
    final startingRaw = map['starting'];
    final subsRaw = map['subs'];
    final starting = (startingRaw is List)
        ? startingRaw
              .whereType<Map>()
              .map((e) => LineupPlayer.fromMap(Map<String, dynamic>.from(e)))
              .toList()
        : const <LineupPlayer>[];
    final subs = (subsRaw is List)
        ? subsRaw
              .whereType<Map>()
              .map((e) => LineupPlayer.fromMap(Map<String, dynamic>.from(e)))
              .toList()
        : const <LineupPlayer>[];
    return MatchLineup(starting: starting, subs: subs);
  }

  Map<String, dynamic> toMap() {
    return {
      'starting': starting.map((p) => p.toMap()).toList(),
      'subs': subs.map((p) => p.toMap()).toList(),
    };
  }
}

class MatchModel {
  final String id;
  final String leagueId;
  final String homeTeamId;
  final String homeTeamName;
  final String homeTeamLogoUrl;
  final String awayTeamId;
  final String awayTeamName;
  final String awayTeamLogoUrl;
  final int homeScore;
  final int awayScore;
  final DateTime matchDate;
  final MatchStatus status;
  final int? minute;
  final String? groupId;
  final String? youtubeUrl;
  final String dateString; // YYYY-MM-DD formatında
  final int? halfTimeHomeScore;
  final int? halfTimeAwayScore;
  final MatchLineup? homeLineup;
  final MatchLineup? awayLineup;

  MatchModel({
    required this.id,
    required this.leagueId,
    required this.homeTeamId,
    required this.homeTeamName,
    required this.homeTeamLogoUrl,
    required this.awayTeamId,
    required this.awayTeamName,
    required this.awayTeamLogoUrl,
    required this.homeScore,
    required this.awayScore,
    required this.matchDate,
    required this.status,
    required this.dateString,
    this.minute,
    this.groupId,
    this.youtubeUrl,
    this.halfTimeHomeScore,
    this.halfTimeAwayScore,
    this.homeLineup,
    this.awayLineup,
  });

  factory MatchModel.fromMap(Map<String, dynamic> map, String id) {
    final rawMatchDate = map['matchDate'];
    final matchDate = rawMatchDate is Timestamp
        ? rawMatchDate.toDate()
        : DateTime.tryParse(rawMatchDate?.toString() ?? '') ?? DateTime.now();
    int? readScore(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim());
      return null;
    }

    int readInt(dynamic v, {int fallback = 0}) {
      if (v == null) return fallback;
      if (v is num) return v.toInt();
      final s = v.toString().replaceAll('\u0000', '').trim();
      return int.tryParse(s) ?? double.tryParse(s.replaceAll(',', '.'))?.toInt() ?? fallback;
    }

    MatchLineup? readLineup(dynamic v) {
      if (v is Map) {
        return MatchLineup.fromMap(Map<String, dynamic>.from(v));
      }
      return null;
    }

    return MatchModel(
      id: id,
      leagueId: map['leagueId'] ?? '',
      homeTeamId: map['homeTeamId'] ?? '',
      homeTeamName: map['homeTeamName'] ?? '',
      homeTeamLogoUrl:
          (map['homeTeamLogoUrl'] ??
                  map['homeTeamLogo'] ??
                  map['homeLogoUrl'] ??
                  map['homeLogo'] ??
                  '')
              .toString(),
      awayTeamId: map['awayTeamId'] ?? '',
      awayTeamName: map['awayTeamName'] ?? '',
      awayTeamLogoUrl:
          (map['awayTeamLogoUrl'] ??
                  map['awayTeamLogo'] ??
                  map['awayLogoUrl'] ??
                  map['awayLogo'] ??
                  '')
              .toString(),
      homeScore: readInt(map['homeScore']),
      awayScore: readInt(map['awayScore']),
      matchDate: matchDate,
      dateString:
          map['dateString'] ??
          "${matchDate.year}-${matchDate.month.toString().padLeft(2, '0')}-${matchDate.day.toString().padLeft(2, '0')}",
      status: MatchStatus.values.firstWhere(
        (e) => e.name == (map['status'] ?? 'notStarted'),
        orElse: () => MatchStatus.notStarted,
      ),
      minute: readScore(map['minute']),
      groupId: map['groupId'],
      youtubeUrl: (map['youtubeUrl'] ?? '').toString().trim().isEmpty
          ? null
          : (map['youtubeUrl'] ?? '').toString().trim(),
      halfTimeHomeScore: readScore(map['halfTimeHomeScore']),
      halfTimeAwayScore: readScore(map['halfTimeAwayScore']),
      homeLineup: readLineup(map['homeLineup']),
      awayLineup: readLineup(map['awayLineup']),
    );
  }

  Map<String, dynamic> toMap() {
    final base = <String, dynamic>{
      'leagueId': leagueId,
      'homeTeamId': homeTeamId,
      'homeTeamName': homeTeamName,
      'homeTeamLogoUrl': homeTeamLogoUrl,
      'awayTeamId': awayTeamId,
      'awayTeamName': awayTeamName,
      'awayTeamLogoUrl': awayTeamLogoUrl,
      'homeScore': homeScore,
      'awayScore': awayScore,
      'matchDate': Timestamp.fromDate(matchDate),
      'dateString': dateString,
      'status': status.name,
      'minute': minute,
      'groupId': groupId,
      'youtubeUrl': youtubeUrl,
    };
    if (halfTimeHomeScore != null)
      base['halfTimeHomeScore'] = halfTimeHomeScore;
    if (halfTimeAwayScore != null)
      base['halfTimeAwayScore'] = halfTimeAwayScore;
    if (homeLineup != null) base['homeLineup'] = homeLineup!.toMap();
    if (awayLineup != null) base['awayLineup'] = awayLineup!.toMap();
    return base;
  }
}

class MatchEvent {
  final String id;
  final String matchId;
  final String playerName;
  final String? assistPlayerName;
  final String? subInPlayerName;
  final String type; // 'goal', 'yellow_card', 'red_card'
  final int minute;
  final String teamId;
  final bool isOwnGoal;

  MatchEvent({
    required this.id,
    required this.matchId,
    required this.playerName,
    this.assistPlayerName,
    this.subInPlayerName,
    required this.type,
    required this.minute,
    required this.teamId,
    this.isOwnGoal = false,
  });

  factory MatchEvent.fromMap(Map<String, dynamic> map, String id) {
    final rawMinute = map['minute'];
    int minute = 0;
    if (rawMinute is num) {
      minute = rawMinute.toInt();
    } else if (rawMinute is String) {
      minute =
          int.tryParse(rawMinute.trim()) ??
          double.tryParse(rawMinute.replaceAll(',', '.'))?.toInt() ??
          0;
    }
    return MatchEvent(
      id: id,
      matchId: map['matchId'] ?? '',
      playerName: map['playerName'] ?? '',
      assistPlayerName: map['assistPlayerName'] as String?,
      subInPlayerName: map['subInPlayerName'] as String?,
      type: map['type'] ?? 'goal',
      minute: minute,
      teamId: map['teamId'] ?? '',
      isOwnGoal: (map['isOwnGoal'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'matchId': matchId,
      'playerName': playerName,
      'assistPlayerName': assistPlayerName,
      'subInPlayerName': subInPlayerName,
      'type': type,
      'minute': minute,
      'teamId': teamId,
      'isOwnGoal': isOwnGoal,
    };
  }
}

class GroupModel {
  final String id;
  final String leagueId;
  final String name;
  final List<String> teamIds;

  GroupModel({
    required this.id,
    required this.leagueId,
    required this.name,
    required this.teamIds,
  });

  factory GroupModel.fromMap(Map<String, dynamic> map, String id) {
    return GroupModel(
      id: id,
      leagueId: map['leagueId'] ?? '',
      name: map['name'] ?? '',
      teamIds: List<String>.from(map['teamIds'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {'leagueId': leagueId, 'name': name, 'teamIds': teamIds};
  }
}

class PlayerModel {
  final String id;
  final String teamId;
  final String name;
  final String? number; // Forma No
  final int? birthYear; // Doğum Yılı
  final String? position; // Kaleci, Defans, Ortasaha, Forvet
  final String? preferredFoot; // Sağ, Sol, Çift
  final String? photoUrl; // Fotoğraf
  final int goals;
  final int assists;
  final int yellowCards;
  final int redCards;
  final int matchesPlayed;
  final int suspendedMatches;

  PlayerModel({
    required this.id,
    required this.teamId,
    required this.name,
    this.number,
    this.birthYear,
    this.position,
    this.preferredFoot,
    this.photoUrl,
    this.goals = 0,
    this.assists = 0,
    this.yellowCards = 0,
    this.redCards = 0,
    this.matchesPlayed = 0,
    this.suspendedMatches = 0,
  });

  factory PlayerModel.fromMap(Map<String, dynamic> map, String id) {
    final rawNumber = map['number'];
    final number = rawNumber == null ? null : rawNumber.toString();

    final rawBirthYear = map['birthYear'];
    int? birthYear;
    if (rawBirthYear is num) {
      birthYear = rawBirthYear.toInt();
    } else if (rawBirthYear is String) {
      final s = rawBirthYear.replaceAll('\u0000', '').trim();
      birthYear =
          int.tryParse(s) ?? double.tryParse(s.replaceAll(',', '.'))?.toInt();
      birthYear ??= int.tryParse(
        RegExp(r'(19\d{2}|20\d{2}|2100)').firstMatch(s)?.group(0) ?? '',
      );
    }
    if (birthYear != null && (birthYear! < 1900 || birthYear! > 2100)) {
      birthYear = null;
    }

    int intFrom(dynamic value, {int fallback = 0}) {
      if (value == null) return fallback;
      if (value is num) return value.toInt();
      final s = value.toString().replaceAll('\u0000', '').trim();
      return int.tryParse(s) ?? double.tryParse(s.replaceAll(',', '.'))?.toInt() ?? fallback;
    }

    int suspendedFrom(dynamic value) {
      if (value == null) return 0;
      if (value is num) return value.toInt();
      final s = value.toString().replaceAll('\u0000', '').trim();
      return int.tryParse(s) ?? double.tryParse(s.replaceAll(',', '.'))?.toInt() ?? 0;
    }

    return PlayerModel(
      id: id,
      teamId: map['teamId'] ?? '',
      name: map['name'] ?? '',
      number: number,
      birthYear: birthYear,
      position: map['position'],
      preferredFoot: map['preferredFoot'],
      photoUrl: map['photoUrl'],
      goals: intFrom(map['goals']),
      assists: intFrom(map['assists']),
      yellowCards: intFrom(map['yellowCards']),
      redCards: intFrom(map['redCards']),
      matchesPlayed: intFrom(map['matchesPlayed']),
      suspendedMatches: suspendedFrom(map['suspendedMatches']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'teamId': teamId,
      'name': name,
      'number': number,
      'birthYear': birthYear,
      'position': position,
      'preferredFoot': preferredFoot,
      'photoUrl': photoUrl,
      'goals': goals,
      'assists': assists,
      'yellowCards': yellowCards,
      'redCards': redCards,
      'matchesPlayed': matchesPlayed,
      'suspendedMatches': suspendedMatches,
    };
  }
}
