import 'dart:convert';

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
  final String? firebaseId;
  final String homeTeamId;
  final String awayTeamId;
  final int homeScore;
  final int awayScore;
  final String? matchDate; // YYYY-MM-DD
  final String? matchTime; // HH:mm
  final int? week;
  final String? pitchId;
  final String? pitchName;
  final MatchStatus status;
  final int? minute;
  final String? groupId;
  final String? youtubeUrl;
  final String? homeHighlightPhotoUrl;
  final String? awayHighlightPhotoUrl;
  final MatchScore? score;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  MatchModel({
    required this.id,
    required this.leagueId,
    required this.status,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.homeScore,
    required this.awayScore,
    this.matchDate,
    this.matchTime,
    this.week,
    this.pitchId,
    this.pitchName,
    this.minute,
    this.groupId,
    this.firebaseId,
    this.youtubeUrl,
    this.homeHighlightPhotoUrl,
    this.awayHighlightPhotoUrl,
    this.score,
    this.createdAt,
    this.updatedAt,
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
      if (s.isEmpty) {
        matchDateStr = null;
      } else {
        final dt = DateTime.tryParse(s);
        if (dt != null) {
          matchDateStr =
              "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
          legacyTs = legacyTs ?? dt;
        } else {
          matchDateStr = s;
        }
      }
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

    MatchScore? readScoreObject() {
      final sRaw = map['score_json'] ?? map['scoreJson'] ?? map['score'];
      if (sRaw is Map) {
        return MatchScore.fromMap(Map<String, dynamic>.from(sRaw));
      }
      if (sRaw is String) {
        final str = sRaw.trim();
        if (str.isNotEmpty) {
          try {
            final decoded = jsonDecode(str);
            if (decoded is Map) {
              return MatchScore.fromMap(Map<String, dynamic>.from(decoded));
            }
          } catch (_) {}
        }
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

    final rawStatus = (v('status', 'status') ?? '').toString().trim();
    final resolvedStatus = MatchStatus.values.firstWhere(
      (e) => e.name == (rawStatus.isEmpty ? 'notStarted' : rawStatus),
      orElse: () => MatchStatus.notStarted,
    );

    DateTime? readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return MatchModel(
      id: id,
      leagueId: (map['leagueId'] ?? map['league_id'] ?? '').toString(),
      firebaseId: (v('firebaseId', 'firebase_id') ?? '').toString().trim().isEmpty
          ? null
          : (v('firebaseId', 'firebase_id') ?? '').toString().trim(),
      homeTeamId: (v('homeTeamId', 'home_team_id') ?? '').toString(),
      awayTeamId: (v('awayTeamId', 'away_team_id') ?? '').toString(),
      homeScore: readInt(v('homeScore', 'home_score')),
      awayScore: readInt(v('awayScore', 'away_score')),
      matchDate: (matchDateStr ?? '').trim().isEmpty ? null : matchDateStr,
      matchTime: (matchTimeStr ?? '').trim().isEmpty ? null : matchTimeStr,
      week: readScore(v('week', 'week')),
      pitchId: pitchIdRaw.isEmpty ? null : pitchIdRaw,
      pitchName: pitchNameRaw.isEmpty ? null : pitchNameRaw,
      status: resolvedStatus,
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
      createdAt: readDate(v('createdAt', 'created_at')),
      updatedAt: readDate(v('updatedAt', 'updated_at')),
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
        'leagueId': leagueId,
        'firebaseId': firebaseId,
        'homeTeamId': homeTeamId,
        'awayTeamId': awayTeamId,
        'homeScore': homeScore,
        'awayScore': awayScore,
        'scoreJson': computedScore,
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
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      });
    } else {
      base.addAll({
        if (id.trim().isNotEmpty) 'id': id.trim(),
        'firebase_id': (firebaseId ?? '').trim().isEmpty ? null : firebaseId!.trim(),
        'league_id': leagueId.trim().isEmpty ? null : leagueId.trim(),
        'home_team_id': homeTeamId,
        'away_team_id': awayTeamId,
        'group_id': (groupId ?? '').trim().isEmpty ? null : groupId!.trim(),
        'pitch_id': (pitchId ?? '').trim().isEmpty ? null : pitchId!.trim(),
        'pitch_name': (pitchName ?? '').trim().isEmpty ? null : pitchName!.trim(),
        'week': week,
        'match_date': dateStr.isEmpty ? null : dateStr,
        'match_time': timeStr.isEmpty ? null : timeStr,
        'status': status.name,
        'minute': minute,
        'home_score': homeScore,
        'away_score': awayScore,
        'youtube_url': (youtubeUrl ?? '').trim().isEmpty ? null : youtubeUrl!.trim(),
        'home_highlight_photo_url':
            (homeHighlightPhotoUrl ?? '').trim().isEmpty ? null : homeHighlightPhotoUrl!.trim(),
        'away_highlight_photo_url':
            (awayHighlightPhotoUrl ?? '').trim().isEmpty ? null : awayHighlightPhotoUrl!.trim(),
        'score_json': computedScore,
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      });
    }
    return base;
  }
}

class MatchEvent {
  final String id;
  final String matchId;
  final String seasonId;
  String get leagueId => seasonId;
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
    String? seasonId,
    String? leagueId,
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
  })  : seasonId = (seasonId ?? leagueId ?? '').trim(),
        type = (type ?? eventType);

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
      seasonId: (v('seasonId', 'season_id') ?? v('tournamentId', 'season_id') ?? '')
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
        'seasonId': seasonId,
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
      'season_id': seasonId,
      'team_id': teamId,
      'player_id': playerPhone,
      'assist_player_id': assistPlayerPhone,
      'sub_in_player_id': subInPlayerPhone,
      'event_type': eventType,
      'player_name': playerName,
      'minute': minute,
      'is_own_goal': isOwnGoal,
    };
  }
}

class GroupModel {
  final String id;
  final String seasonId;
  final String name;

  GroupModel({
    required this.id,
    required this.seasonId,
    required this.name,
  });

  factory GroupModel.fromMap(Map<String, dynamic> map, String id) {
    dynamic v(String camel, String snake) => map[camel] ?? map[snake];
    return GroupModel(
      id: id,
      seasonId: (v('seasonId', 'season_id') ?? '').toString(),
      name: (v('name', 'name') ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap({bool snakeCase = false}) {
    if (!snakeCase) {
      return {'seasonId': seasonId, 'name': name};
    }
    return {'season_id': seasonId, 'name': name};
  }
}

class PlayerModel {
  const PlayerModel({
    required this.id,
    required this.name,
    this.phone,
    this.nationalId,
    this.birthDate,
    this.mainPosition,
    this.position,
    this.preferredFoot,
    this.height,
    this.weight,
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
  final String? nationalId;
  final String? birthDate;
  final String? mainPosition;
  final String? position;
  final String? preferredFoot;
  final int? height;
  final int? weight;
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
      final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
      if (iso != null) {
        final yyyy = iso.group(1)!;
        final mm = iso.group(2)!;
        final dd = iso.group(3)!;
        return '$dd/$mm/$yyyy';
      }
      return null;
    }

    final isRoster =
        (v('leagueId', 'league_id') ??
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
    final birthDate = normalizeBirthDate(v('birthDate', 'birth_date'));
    final mainPosition = (v('mainPosition', 'main_position') as String?)?.trim();
    final position = (v('subPosition', 'sub_position') ?? v('position', 'position'))
        ?.toString()
        .trim();
    final preferredFoot = (v('preferredFoot', 'preferred_foot') as String?)?.trim();
    final nationalId = (v('nationalId', 'national_id'))?.toString().trim();
    final photoUrl = (v('photoUrl', 'photo_url') as String?)?.trim();
    int readInt(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      final s = v.toString().replaceAll('\u0000', '').trim();
      return int.tryParse(s) ??
          double.tryParse(s.replaceAll(',', '.'))?.toInt() ??
          0;
    }

    int? readNullableInt(dynamic v) {
      if (v == null) return null;
      final n = readInt(v);
      return n == 0 ? null : n;
    }

    final height = readNullableInt(v('height', 'height'));
    final weight= readNullableInt(v('weight', 'weight'));

    final suspendedMatches = readInt(v('suspendedMatches', 'suspended_matches'));

    final numberRaw = (v('jerseyNumber', 'jersey_number') ?? v('number', 'number'))
        ?.toString()
        .trim();
    final number = (numberRaw ?? '').isEmpty ? null : numberRaw;

    if (isRoster) {
      final tournamentId = (v('leagueId', 'league_id') ?? '').toString().trim();
      final teamId = (v('teamId', 'team_id') ?? '').toString().trim();
      return PlayerModel(
        id: id,
        name: name,
        phone: phone,
        nationalId: (nationalId ?? '').isEmpty ? null : nationalId,
        number: number,
        birthDate: birthDate,
        mainPosition: mainPosition,
        position: (position ?? '').isEmpty ? null : position,
        preferredFoot: preferredFoot,
        height: height,
        weight: weight,
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
      nationalId: (nationalId ?? '').isEmpty ? null : nationalId,
      birthDate: birthDate,
      mainPosition: mainPosition,
      position: (position ?? '').isEmpty ? null : position,
      preferredFoot: preferredFoot,
      height: height,
      weight: weight,
      photoUrl: photoUrl,
      role: role,
      suspendedMatches: suspendedMatches,
    );
  }

  Map<String, dynamic> toPlayerIdentityMap() {
    return {
      'name': name,
      'nationalId': nationalId,
      'birthDate': birthDate,
      'mainPosition': mainPosition,
      'preferredFoot': preferredFoot,
      'height': height,
      'weight': weight,
    };
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
      'league_id': tournamentId,
      'team_id': teamId,
      'player_phone': phone,
      'player_name': name,
      'jersey_number': number,
      'role': role,
    };
  }
}
