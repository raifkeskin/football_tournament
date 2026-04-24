import 'package:cloud_firestore/cloud_firestore.dart';

enum MatchStatus { notStarted, live, finished, postponed, cancelled, halftime }

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
    final ht = (htRaw is Map)
        ? MatchScorePart.fromMap(Map<String, dynamic>.from(htRaw))
        : const MatchScorePart(home: 0, away: 0);
    final ft = (ftRaw is Map)
        ? MatchScorePart.fromMap(Map<String, dynamic>.from(ftRaw))
        : const MatchScorePart(home: 0, away: 0);
    return MatchScore(halfTime: ht, fullTime: ft);
  }

  Map<String, dynamic> toMap() {
    return {'halfTime': halfTime.toMap(), 'fullTime': fullTime.toMap()};
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
  final String? homeFormation;
  final String? awayFormation;
  final List<String> homeFormationOrder;
  final List<String> awayFormationOrder;
  final List<MatchEvent> events;

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
    this.homeFormation,
    this.awayFormation,
    this.homeFormationOrder = const <String>[],
    this.awayFormationOrder = const <String>[],
    this.events = const <MatchEvent>[],
  });

  factory MatchModel.fromMap(Map<String, dynamic> map, String id) {
    dynamic v(String camel, String snake) => map[camel] ?? map[snake];

    final rawMatchDate = v('matchDate', 'match_date') ?? v('dateString', 'date_string');
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
      return int.tryParse(s) ??
          double.tryParse(s.replaceAll(',', '.'))?.toInt() ??
          fallback;
    }

    MatchLineup? readLineup(dynamic v) {
      if (v is Map) {
        return MatchLineup.fromMap(Map<String, dynamic>.from(v));
      }
      return null;
    }

    List<String> readLineupPhones(dynamic v) {
      if (v is List) {
        return v
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
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
    final rawMatchTime = (v('matchTime', 'match_time') ?? '').toString().trim();
    if (rawMatchTime.isNotEmpty) {
      matchTimeStr = rawMatchTime;
    } else {
      final legacyTime = (v('time', 'time') ?? '').toString().trim();
      if (legacyTime.isNotEmpty) {
        matchTimeStr = legacyTime;
      } else if (legacyTs != null) {
        matchTimeStr =
            "${legacyTs.hour.toString().padLeft(2, '0')}:${legacyTs.minute.toString().padLeft(2, '0')}";
      }
    }

    final pitchIdRaw = (v('pitchId', 'pitch_id') ?? '').toString().trim();
    final pitchNameRaw = (v('pitchName', 'pitch_name') ?? '').toString().trim();
    final homePhotoRaw =
        (v('homeHighlightPhotoUrl', 'home_highlight_photo_url') ?? '').toString().trim();
    final awayPhotoRaw =
        (v('awayHighlightPhotoUrl', 'away_highlight_photo_url') ?? '').toString().trim();

    final rawTournamentId =
        (v('tournamentId', 'tournament_id') ?? v('leagueId', 'league_id') ?? '').toString();
    final rawHomeLineup = v('homeLineup', 'home_lineup');
    final rawAwayLineup = v('awayLineup', 'away_lineup');
    final rawHomeDetail = v('homeLineupDetail', 'home_lineup_detail');
    final rawAwayDetail = v('awayLineupDetail', 'away_lineup_detail');
    final homeLineupDetail =
        readLineup(rawHomeDetail) ?? readLineup(rawHomeLineup);
    final awayLineupDetail =
        readLineup(rawAwayDetail) ?? readLineup(rawAwayLineup);

    List<MatchEvent> readEvents(dynamic raw) {
      if (raw is List) {
        return raw.whereType<Map>().map((e) {
          final m = Map<String, dynamic>.from(e);
          final eid =
              (m['id'] ?? m['eventId'] ?? m['event_id'] ?? m['matchEventId'] ?? '').toString();
          return MatchEvent.fromMap(m, eid);
        }).toList();
      }
      return const <MatchEvent>[];
    }

    final eventsRaw = v('events', 'match_events') ?? v('matchEvents', 'match_events');

    List<String> readStringList(dynamic v) {
      if (v is List) {
        return v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      }
      return const <String>[];
    }

    final homeFormationRaw = (v('homeFormation', 'home_formation') ?? '').toString().trim();
    final awayFormationRaw = (v('awayFormation', 'away_formation') ?? '').toString().trim();
    final homeFormationOrderRaw = v('homeFormationOrder', 'home_formation_order');
    final awayFormationOrderRaw = v('awayFormationOrder', 'away_formation_order');

    return MatchModel(
      id: id,
      leagueId: rawTournamentId,
      homeTeamId: (v('homeTeamId', 'home_team_id') ?? '').toString(),
      homeTeamName: (v('homeTeamName', 'home_team_name') ?? '').toString(),
      homeTeamLogoUrl:
          (v('homeTeamLogoUrl', 'home_team_logo_url') ??
                  v('homeTeamLogo', 'home_team_logo') ??
                  v('homeLogoUrl', 'home_logo_url') ??
                  v('homeLogo', 'home_logo') ??
                  '')
              .toString(),
      awayTeamId: (v('awayTeamId', 'away_team_id') ?? '').toString(),
      awayTeamName: (v('awayTeamName', 'away_team_name') ?? '').toString(),
      awayTeamLogoUrl:
          (v('awayTeamLogoUrl', 'away_team_logo_url') ??
                  v('awayTeamLogo', 'away_team_logo') ??
                  v('awayLogoUrl', 'away_logo_url') ??
                  v('awayLogo', 'away_logo') ??
                  '')
              .toString(),
      homeScore: readInt(v('homeScore', 'home_score')),
      awayScore: readInt(v('awayScore', 'away_score')),
      matchDate: (matchDateStr ?? '').trim().isEmpty ? null : matchDateStr,
      matchTime: (matchTimeStr ?? '').trim().isEmpty ? null : matchTimeStr,
      week: readScore(v('week', 'week')),
      pitchId: pitchIdRaw.isEmpty ? null : pitchIdRaw,
      pitchName: pitchNameRaw.isEmpty ? null : pitchNameRaw,
      status: MatchStatus.values.firstWhere(
        (e) => e.name == (v('status', 'status') ?? 'notStarted'),
        orElse: () => MatchStatus.notStarted,
      ),
      minute: readScore(v('minute', 'minute')),
      groupId: (v('groupId', 'group_id') ?? '').toString().trim().isEmpty
          ? null
          : (v('groupId', 'group_id') ?? '').toString().trim(),
      youtubeUrl: (v('youtubeUrl', 'youtube_url') ?? '').toString().trim().isEmpty
          ? null
          : (v('youtubeUrl', 'youtube_url') ?? '').toString().trim(),
      homeHighlightPhotoUrl: homePhotoRaw.isEmpty ? null : homePhotoRaw,
      awayHighlightPhotoUrl: awayPhotoRaw.isEmpty ? null : awayPhotoRaw,
      score: readScoreObject(),
      homeLineup: readLineupPhones(rawHomeLineup),
      awayLineup: readLineupPhones(rawAwayLineup),
      homeLineupDetail: homeLineupDetail,
      awayLineupDetail: awayLineupDetail,
      homeFormation: homeFormationRaw.isEmpty ? null : homeFormationRaw,
      awayFormation: awayFormationRaw.isEmpty ? null : awayFormationRaw,
      homeFormationOrder: readStringList(homeFormationOrderRaw),
      awayFormationOrder: readStringList(awayFormationOrderRaw),
      events: readEvents(eventsRaw),
    );
  }

  Map<String, dynamic> toMap({bool snakeCase = false}) {
    final dateStr = (matchDate ?? '').trim();
    final timeStr = (matchTime ?? '').trim();
    final computedScore =
        (score ??
                MatchScore(
                  halfTime: const MatchScorePart(home: 0, away: 0),
                  fullTime: MatchScorePart(home: homeScore, away: awayScore),
                ))
            .toMap();

    final base = <String, dynamic>{};
    if (!snakeCase) {
      base.addAll({
        'tournamentId': leagueId,
        'homeTeamId': homeTeamId,
        'homeTeamName': homeTeamName,
        'homeTeamLogoUrl': homeTeamLogoUrl,
        'awayTeamId': awayTeamId,
        'awayTeamName': awayTeamName,
        'awayTeamLogoUrl': awayTeamLogoUrl,
        'homeScore': homeScore,
        'awayScore': awayScore,
        'score': computedScore,
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
        'homeFormation': (homeFormation ?? '').trim().isEmpty ? null : homeFormation!.trim(),
        'awayFormation': (awayFormation ?? '').trim().isEmpty ? null : awayFormation!.trim(),
        'homeFormationOrder': homeFormationOrder,
        'awayFormationOrder': awayFormationOrder,
      });
    } else {
      base.addAll({
        'tournament_id': leagueId,
        'home_team_id': homeTeamId,
        'home_team_name': homeTeamName,
        'home_team_logo_url': homeTeamLogoUrl,
        'away_team_id': awayTeamId,
        'away_team_name': awayTeamName,
        'away_team_logo_url': awayTeamLogoUrl,
        'home_score': homeScore,
        'away_score': awayScore,
        'score': computedScore,
        'match_date': dateStr.isEmpty ? null : dateStr,
        'match_time': timeStr.isEmpty ? null : timeStr,
        'week': week,
        'pitch_id': pitchId,
        'pitch_name': pitchName,
        'status': status.name,
        'minute': minute,
        'group_id': groupId,
        'youtube_url': youtubeUrl,
        'home_highlight_photo_url': homeHighlightPhotoUrl,
        'away_highlight_photo_url': awayHighlightPhotoUrl,
        'home_lineup': homeLineup,
        'away_lineup': awayLineup,
        'home_formation': (homeFormation ?? '').trim().isEmpty ? null : homeFormation!.trim(),
        'away_formation': (awayFormation ?? '').trim().isEmpty ? null : awayFormation!.trim(),
        'home_formation_order': homeFormationOrder,
        'away_formation_order': awayFormationOrder,
      });
    }
    if (homeLineupDetail != null) {
      base[snakeCase ? 'home_lineup_detail' : 'homeLineupDetail'] =
          homeLineupDetail!.toMap();
    }
    if (awayLineupDetail != null) {
      base[snakeCase ? 'away_lineup_detail' : 'awayLineupDetail'] =
          awayLineupDetail!.toMap();
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
    dynamic v(String camel, String snake) => map[camel] ?? map[snake];

    final rawMinute = v('minute', 'minute');
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
      matchId: (v('matchId', 'match_id') ?? '').toString(),
      tournamentId: (v('tournamentId', 'tournament_id') ?? v('leagueId', 'league_id') ?? '')
          .toString()
          .trim(),
      playerName: (v('playerName', 'player_name') ?? '').toString(),
      playerPhone:
          (v('playerPhone', 'player_phone') ?? v('playerId', 'player_id'))?.toString().trim().isEmpty ??
              true
          ? null
          : (v('playerPhone', 'player_phone') ?? v('playerId', 'player_id')).toString().trim(),
      assistPlayerPhone:
          (v('assistPlayerPhone', 'assist_player_phone') ?? v('assistPlayerId', 'assist_player_id'))
                  ?.toString()
                  .trim()
                  .isEmpty ??
              true
          ? null
          : (v('assistPlayerPhone', 'assist_player_phone') ?? v('assistPlayerId', 'assist_player_id'))
                .toString()
                .trim(),
      assistPlayerName: (v('assistPlayerName', 'assist_player_name') as String?)?.trim(),
      subInPlayerPhone:
          (v('subInPlayerPhone', 'sub_in_player_phone') ?? v('subInPlayerId', 'sub_in_player_id'))
                  ?.toString()
                  .trim()
                  .isEmpty ??
              true
          ? null
          : (v('subInPlayerPhone', 'sub_in_player_phone') ?? v('subInPlayerId', 'sub_in_player_id'))
              .toString()
              .trim(),
      subInPlayerName: (v('subInPlayerName', 'sub_in_player_name') as String?)?.trim(),
      eventType: (v('eventType', 'event_type') ?? v('type', 'type') ?? 'goal').toString(),
      type: (v('type', 'type') ?? v('eventType', 'event_type') ?? 'goal').toString(),
      minute: minute,
      teamId: (v('teamId', 'team_id') ?? '').toString(),
      isOwnGoal: (v('isOwnGoal', 'is_own_goal') as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap({bool snakeCase = false}) {
    if (!snakeCase) {
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
    return {
      'match_id': matchId,
      'tournament_id': tournamentId,
      'team_id': teamId,
      'event_type': eventType,
      'player_name': playerName,
      'player_phone': playerPhone,
      'assist_player_phone': assistPlayerPhone,
      'assist_player_name': assistPlayerName,
      'sub_in_player_phone': subInPlayerPhone,
      'sub_in_player_name': subInPlayerName,
      'type': type,
      'minute': minute,
      'is_own_goal': isOwnGoal,
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
    dynamic v(String camel, String snake) => map[camel] ?? map[snake];
    return GroupModel(
      id: id,
      leagueId:
          (v('leagueId', 'league_id') ??
                  v('tournamentId', 'tournament_id') ??
                  '')
              .toString(),
      name: (v('name', 'name') ?? '').toString(),
      teamIds: List<String>.from(v('teamIds', 'team_ids') ?? const <String>[]),
    );
  }

  Map<String, dynamic> toMap({bool snakeCase = false}) {
    if (!snakeCase) {
      return {'leagueId': leagueId, 'name': name, 'teamIds': teamIds};
    }
    return {'league_id': leagueId, 'name': name, 'team_ids': teamIds};
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
    dynamic v(String camel, String snake) => map[camel] ?? map[snake];

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

    final isRoster =
        (v('tournamentId', 'tournament_id') ??
            v('leagueId', 'league_id') ??
            v('playerPhone', 'player_phone') ??
            v('teamId', 'team_id')) !=
        null;
    final phoneRaw =
        (v('playerPhone', 'player_phone') ??
                v('phone', 'phone') ??
                v('playerId', 'player_id') ??
                id)
            .toString()
            .trim();
    final phone = phoneRaw.isEmpty ? null : phoneRaw;
    final name = (v('playerName', 'player_name') ?? v('name', 'name') ?? '').toString().trim();
    final roleRaw = (v('role', 'role') ?? '').toString().trim();
    final role = roleRaw.isEmpty ? 'Futbolcu' : roleRaw;
    final numberRaw = (v('jerseyNumber', 'jersey_number') ?? v('number', 'number'))
        ?.toString()
        .trim();
    final number = (numberRaw ?? '').isEmpty ? null : numberRaw;
    final birthDate = normalizeBirthDate(v('birthDate', 'birth_date'));
    final mainPosition = (v('mainPosition', 'main_position') as String?)?.trim();
    final position = (v('position', 'position') as String?)?.trim();
    final preferredFoot = (v('preferredFoot', 'preferred_foot') as String?)?.trim();
    final photoUrl = (v('photoUrl', 'photo_url') as String?)?.trim();
    int readInt(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      final s = v.toString().replaceAll('\u0000', '').trim();
      return int.tryParse(s) ??
          double.tryParse(s.replaceAll(',', '.'))?.toInt() ??
          0;
    }

    final suspendedMatches = readInt(v('suspendedMatches', 'suspended_matches'));

    if (isRoster) {
      final tournamentId = (v('tournamentId', 'tournament_id') ?? v('leagueId', 'league_id') ?? '')
          .toString()
          .trim();
      final teamId = (v('teamId', 'team_id') ?? '').toString().trim();
      return PlayerModel(
        id: id,
        name: name,
        phone: phone,
        number: number,
        birthDate: birthDate,
        mainPosition: mainPosition,
        position: position,
        preferredFoot: preferredFoot,
        photoUrl: photoUrl,
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
    return {'name': name, 'birthDate': birthDate, 'mainPosition': mainPosition};
  }

  Map<String, dynamic> toPlayerIdentityMapDb({bool snakeCase = false}) {
    if (!snakeCase) return toPlayerIdentityMap();
    return {'name': name, 'birth_date': birthDate, 'main_position': mainPosition};
  }

  Map<String, dynamic> toRosterMap({bool snakeCase = false}) {
    if (!snakeCase) {
      return {
        'tournamentId': tournamentId,
        'teamId': teamId,
        'playerPhone': phone,
        'playerName': name,
        'jerseyNumber': number,
        'role': role,
      };
    }
    return {
      'tournament_id': tournamentId,
      'team_id': teamId,
      'player_phone': phone,
      'player_name': name,
      'jersey_number': number,
      'role': role,
    };
  }
}
