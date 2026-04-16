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

class MatchScorePart {
  const MatchScorePart({required this.home, required this.away});

  final int home;
  final int away;

  factory MatchScorePart.fromMap(Map<String, dynamic> map) {
    int readInt(dynamic v, {int fallback = 0}) {
      if (v == null) return fallback;
      if (v is num) return v.toInt();
      final s = v.toString().replaceAll('\u0000', '').trim();
      return int.tryParse(s) ??
          double.tryParse(s.replaceAll(',', '.'))?.toInt() ??
          fallback;
    }

    return MatchScorePart(
      home: readInt(map['home']),
      away: readInt(map['away']),
    );
  }

  Map<String, dynamic> toMap() => {'home': home, 'away': away};
}

class MatchScore {
  const MatchScore({required this.halfTime, required this.fullTime});

  final MatchScorePart halfTime;
  final MatchScorePart fullTime;

  factory MatchScore.fromMap(Map<String, dynamic> map) {
    final htRaw = map['halfTime'];
    final ftRaw = map['fullTime'];
    final ht =
        (htRaw is Map) ? MatchScorePart.fromMap(Map<String, dynamic>.from(htRaw)) : const MatchScorePart(home: 0, away: 0);
    final ft =
        (ftRaw is Map) ? MatchScorePart.fromMap(Map<String, dynamic>.from(ftRaw)) : const MatchScorePart(home: 0, away: 0);
    return MatchScore(halfTime: ht, fullTime: ft);
  }

  Map<String, dynamic> toMap() {
    return {
      'halfTime': halfTime.toMap(),
      'fullTime': fullTime.toMap(),
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
  final String? matchDate; // YYYY-MM-DD
  final String? matchTime; // HH:mm
  final MatchStatus status;
  final int? minute;
  final String? groupId;
  final String? youtubeUrl;
  final String? homeHighlightPhotoUrl;
  final String? awayHighlightPhotoUrl;
  final int? week;
  final String? pitchId;
  final String? pitchName;
  final MatchScore? score;
  final List<String> homeLineup;
  final List<String> awayLineup;
  final MatchLineup? homeLineupDetail;
  final MatchLineup? awayLineupDetail;

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
    required this.status,
    this.matchDate,
    this.matchTime,
    this.week,
    this.pitchId,
    this.pitchName,
    this.minute,
    this.groupId,
    this.youtubeUrl,
    this.homeHighlightPhotoUrl,
    this.awayHighlightPhotoUrl,
    this.score,
    this.homeLineup = const <String>[],
    this.awayLineup = const <String>[],
    this.homeLineupDetail,
    this.awayLineupDetail,
  });

  factory MatchModel.fromMap(Map<String, dynamic> map, String id) {
    final rawMatchDate = map['matchDate'];
    DateTime? legacyTs;
    String? matchDateStr;
    if (rawMatchDate is Timestamp) {
      legacyTs = rawMatchDate.toDate();
      matchDateStr =
          "${legacyTs.year}-${legacyTs.month.toString().padLeft(2, '0')}-${legacyTs.day.toString().padLeft(2, '0')}";
    } else if (rawMatchDate is DateTime) {
      legacyTs = rawMatchDate;
      matchDateStr =
          "${legacyTs.year}-${legacyTs.month.toString().padLeft(2, '0')}-${legacyTs.day.toString().padLeft(2, '0')}";
    } else if (rawMatchDate is String) {
      final s = rawMatchDate.trim();
      matchDateStr = s.isEmpty ? null : s;
    } else if (rawMatchDate != null) {
      final s = rawMatchDate.toString().trim();
      matchDateStr = s.isEmpty ? null : s;
    }
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

    List<String> readLineupPhones(dynamic v) {
      if (v is List) {
        return v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      }
      if (v is Map) {
        final lineup = MatchLineup.fromMap(Map<String, dynamic>.from(v));
        final ids = <String>[
          ...lineup.starting.map((p) => p.playerId.trim()),
          ...lineup.subs.map((p) => p.playerId.trim()),
        ];
        return ids.where((e) => e.isNotEmpty).toList();
      }
      return const <String>[];
    }

    MatchScore? readScoreObject() {
      final sRaw = map['score'];
      if (sRaw is Map) {
        return MatchScore.fromMap(Map<String, dynamic>.from(sRaw));
      }
      final htHome = readInt(map['halfTimeHomeScore']);
      final htAway = readInt(map['halfTimeAwayScore']);
      return MatchScore(
        halfTime: MatchScorePart(home: htHome, away: htAway),
        fullTime: MatchScorePart(
          home: readInt(map['homeScore']),
          away: readInt(map['awayScore']),
        ),
      );
    }

    final legacyDateString = (map['dateString'] ?? '').toString().trim();
    if ((matchDateStr ?? '').isEmpty && legacyDateString.isNotEmpty) {
      matchDateStr = legacyDateString;
    }

    String? matchTimeStr;
    final rawMatchTime = (map['matchTime'] ?? '').toString().trim();
    if (rawMatchTime.isNotEmpty) {
      matchTimeStr = rawMatchTime;
    } else {
      final legacyTime = (map['time'] ?? '').toString().trim();
      if (legacyTime.isNotEmpty) {
        matchTimeStr = legacyTime;
      } else if (legacyTs != null) {
        matchTimeStr =
            "${legacyTs.hour.toString().padLeft(2, '0')}:${legacyTs.minute.toString().padLeft(2, '0')}";
      }
    }

    final pitchIdRaw = (map['pitchId'] ?? '').toString().trim();
    final pitchNameRaw = (map['pitchName'] ?? '').toString().trim();
    final homePhotoRaw = (map['homeHighlightPhotoUrl'] ?? '').toString().trim();
    final awayPhotoRaw = (map['awayHighlightPhotoUrl'] ?? '').toString().trim();

    final rawTournamentId = (map['tournamentId'] ?? map['leagueId'] ?? '').toString();
    final rawHomeLineup = map['homeLineup'];
    final rawAwayLineup = map['awayLineup'];
    final rawHomeDetail = map['homeLineupDetail'];
    final rawAwayDetail = map['awayLineupDetail'];
    final homeLineupDetail = readLineup(rawHomeDetail) ?? readLineup(rawHomeLineup);
    final awayLineupDetail = readLineup(rawAwayDetail) ?? readLineup(rawAwayLineup);

    return MatchModel(
      id: id,
      leagueId: rawTournamentId,
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
      matchDate: (matchDateStr ?? '').trim().isEmpty ? null : matchDateStr,
      matchTime: (matchTimeStr ?? '').trim().isEmpty ? null : matchTimeStr,
      week: readScore(map['week']),
      pitchId: pitchIdRaw.isEmpty ? null : pitchIdRaw,
      pitchName: pitchNameRaw.isEmpty ? null : pitchNameRaw,
      status: MatchStatus.values.firstWhere(
        (e) => e.name == (map['status'] ?? 'notStarted'),
        orElse: () => MatchStatus.notStarted,
      ),
      minute: readScore(map['minute']),
      groupId: map['groupId'],
      youtubeUrl: (map['youtubeUrl'] ?? '').toString().trim().isEmpty
          ? null
          : (map['youtubeUrl'] ?? '').toString().trim(),
      homeHighlightPhotoUrl: homePhotoRaw.isEmpty ? null : homePhotoRaw,
      awayHighlightPhotoUrl: awayPhotoRaw.isEmpty ? null : awayPhotoRaw,
      score: readScoreObject(),
      homeLineup: readLineupPhones(rawHomeLineup),
      awayLineup: readLineupPhones(rawAwayLineup),
      homeLineupDetail: homeLineupDetail,
      awayLineupDetail: awayLineupDetail,
    );
  }

  Map<String, dynamic> toMap() {
    final dateStr = (matchDate ?? '').trim();
    final timeStr = (matchTime ?? '').trim();
    final base = <String, dynamic>{
      'tournamentId': leagueId,
      'homeTeamId': homeTeamId,
      'homeTeamName': homeTeamName,
      'homeTeamLogoUrl': homeTeamLogoUrl,
      'awayTeamId': awayTeamId,
      'awayTeamName': awayTeamName,
      'awayTeamLogoUrl': awayTeamLogoUrl,
      'homeScore': homeScore,
      'awayScore': awayScore,
      'score': (score ??
              MatchScore(
                halfTime: MatchScorePart(
                  home: 0,
                  away: 0,
                ),
                fullTime: MatchScorePart(home: homeScore, away: awayScore),
              ))
          .toMap(),
      'matchDate': dateStr.isEmpty ? null : dateStr,
      'matchTime': timeStr.isEmpty ? null : timeStr,
      'week': week,
      'pitchId': pitchId,
      'pitchName': pitchName,
      'status': status.name,
      'minute': minute,
      'groupId': groupId,
      'youtubeUrl': youtubeUrl,
      'homeHighlightPhotoUrl': homeHighlightPhotoUrl,
      'awayHighlightPhotoUrl': awayHighlightPhotoUrl,
      'homeLineup': homeLineup,
      'awayLineup': awayLineup,
    };
    if (homeLineupDetail != null) {
      base['homeLineupDetail'] = homeLineupDetail!.toMap();
    }
    if (awayLineupDetail != null) {
      base['awayLineupDetail'] = awayLineupDetail!.toMap();
    }
    return base;
  }
}

class MatchEvent {
  final String id;
  final String matchId;
  final String tournamentId;
  final String teamId;
  final String eventType;
  final int minute;
  final String playerName;
  final String? playerPhone;
  final String? assistPlayerPhone;
  final String? assistPlayerName;
  final String? subInPlayerPhone;
  final String? subInPlayerName;
  final String type;
  final bool isOwnGoal;

  MatchEvent({
    required this.id,
    required this.matchId,
    required this.tournamentId,
    required this.teamId,
    required this.eventType,
    required this.minute,
    required this.playerName,
    this.playerPhone,
    this.assistPlayerPhone,
    this.assistPlayerName,
    this.subInPlayerPhone,
    this.subInPlayerName,
    String? type,
    this.isOwnGoal = false,
  }) : type = (type ?? eventType);

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
      tournamentId:
          (map['tournamentId'] ?? map['leagueId'] ?? '').toString().trim(),
      playerName: map['playerName'] ?? '',
      playerPhone: (map['playerPhone'] ?? map['playerId'])?.toString().trim().isEmpty ??
              true
          ? null
          : (map['playerPhone'] ?? map['playerId']).toString().trim(),
      assistPlayerPhone: (map['assistPlayerPhone'] ?? map['assistPlayerId'])
                  ?.toString()
                  .trim()
                  .isEmpty ??
              true
          ? null
          : (map['assistPlayerPhone'] ?? map['assistPlayerId']).toString().trim(),
      assistPlayerName: map['assistPlayerName'] as String?,
      subInPlayerPhone: (map['subInPlayerPhone'] ?? map['subInPlayerId'])
                  ?.toString()
                  .trim()
                  .isEmpty ??
              true
          ? null
          : (map['subInPlayerPhone'] ?? map['subInPlayerId']).toString().trim(),
      subInPlayerName: map['subInPlayerName'] as String?,
      eventType: (map['eventType'] ?? map['type'] ?? 'goal').toString(),
      type: (map['type'] ?? map['eventType'] ?? 'goal').toString(),
      minute: minute,
      teamId: map['teamId'] ?? '',
      isOwnGoal: (map['isOwnGoal'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'matchId': matchId,
      'tournamentId': tournamentId,
      'teamId': teamId,
      'eventType': eventType,
      'playerName': playerName,
      'playerPhone': playerPhone,
      'assistPlayerPhone': assistPlayerPhone,
      'assistPlayerName': assistPlayerName,
      'subInPlayerPhone': subInPlayerPhone,
      'subInPlayerName': subInPlayerName,
      'type': type,
      'minute': minute,
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
      leagueId: (map['tournamentId'] ?? map['leagueId'] ?? '').toString(),
      name: map['name'] ?? '',
      teamIds: List<String>.from(map['teamIds'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {'tournamentId': leagueId, 'name': name, 'teamIds': teamIds};
  }
}

class PlayerModel {
  const PlayerModel({
    required this.id,
    required this.name,
    this.phone,
    this.birthDate,
    this.mainPosition,
    this.position,
    this.preferredFoot,
    this.photoUrl,
    this.number,
    this.role = 'Futbolcu',
    this.teamId,
    this.tournamentId,
    this.suspendedMatches = 0,
  });

  final String id;
  final String name;
  final String? phone;
  final String? birthDate;
  final String? mainPosition;
  final String? position;
  final String? preferredFoot;
  final String? photoUrl;
  final String? number;
  final String role;
  final String? teamId;
  final String? tournamentId;
  final int suspendedMatches;

  factory PlayerModel.fromMap(Map<String, dynamic> map, String id) {
    String? normalizeBirthDate(dynamic value) {
      if (value == null) return null;
      if (value is Timestamp) value = value.toDate();
      if (value is DateTime) {
        final dd = value.day.toString().padLeft(2, '0');
        final mm = value.month.toString().padLeft(2, '0');
        final yyyy = value.year.toString().padLeft(4, '0');
        return '$dd/$mm/$yyyy';
      }
      final s = value.toString().replaceAll('\u0000', '').trim();
      if (s.isEmpty) return null;
      final m = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$').firstMatch(s);
      if (m != null) {
        final dd = m.group(1)!.padLeft(2, '0');
        final mm = m.group(2)!.padLeft(2, '0');
        final yyyy = m.group(3)!.padLeft(4, '0');
        return '$dd/$mm/$yyyy';
      }
      return null;
    }

    final isRoster = (map['tournamentId'] ?? map['leagueId'] ?? map['playerPhone'] ?? map['teamId']) != null;
    final phoneRaw = (map['playerPhone'] ?? map['phone'] ?? map['playerId'] ?? id).toString().trim();
    final phone = phoneRaw.isEmpty ? null : phoneRaw;
    final name = (map['playerName'] ?? map['name'] ?? '').toString().trim();
    final roleRaw = (map['role'] ?? '').toString().trim();
    final role = roleRaw.isEmpty ? 'Futbolcu' : roleRaw;
    final numberRaw = (map['jerseyNumber'] ?? map['number'])?.toString().trim();
    final number = (numberRaw ?? '').isEmpty ? null : numberRaw;
    final birthDate = normalizeBirthDate(map['birthDate']);
    final mainPosition = (map['mainPosition'] as String?)?.trim();
    final position = (map['position'] as String?)?.trim();
    final preferredFoot = (map['preferredFoot'] as String?)?.trim();
    final photoUrl = (map['photoUrl'] as String?)?.trim();
    int readInt(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      final s = v.toString().replaceAll('\u0000', '').trim();
      return int.tryParse(s) ??
          double.tryParse(s.replaceAll(',', '.'))?.toInt() ??
          0;
    }
    final suspendedMatches = readInt(map['suspendedMatches']);

    if (isRoster) {
      final tournamentId = (map['tournamentId'] ?? map['leagueId'] ?? '').toString().trim();
      final teamId = (map['teamId'] ?? '').toString().trim();
      return PlayerModel(
        id: id,
        name: name,
        phone: phone,
        number: number,
        role: role,
        teamId: teamId.isEmpty ? null : teamId,
        tournamentId: tournamentId.isEmpty ? null : tournamentId,
        suspendedMatches: suspendedMatches,
      );
    }

    return PlayerModel(
      id: id,
      name: name,
      phone: phone,
      birthDate: birthDate,
      mainPosition: mainPosition,
      position: position,
      preferredFoot: preferredFoot,
      photoUrl: photoUrl,
      role: role,
      suspendedMatches: suspendedMatches,
    );
  }

  Map<String, dynamic> toPlayerIdentityMap() {
    return {
      'name': name,
      'birthDate': birthDate,
      'mainPosition': mainPosition,
    };
  }

  Map<String, dynamic> toRosterMap() {
    return {
      'tournamentId': tournamentId,
      'teamId': teamId,
      'playerPhone': phone,
      'playerName': name,
      'jerseyNumber': number,
      'role': role,
    };
  }
}
