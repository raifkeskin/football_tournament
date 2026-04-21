import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/match.dart';
import '../models/player_stats.dart';
import 'database_service.dart';
import '../utils/string_utils.dart';

class MatchService {
  MatchService({DatabaseService? databaseService, FirebaseFirestore? firestore})
    : _db = databaseService ?? DatabaseService(firestore: firestore),
      _firestore = firestore ?? FirebaseFirestore.instance;

  final DatabaseService _db;
  final FirebaseFirestore _firestore;

  Stream<List<MatchModel>> watchMatchesForLeague(String leagueId) {
    return _db.watchMatchesForLeague(leagueId);
  }

  Stream<List<MatchModel>> watchMatchesByDate({
    required String leagueId,
    required DateTime date,
  }) {
    return _db.getMatchesByDate(leagueId: leagueId, date: date);
  }

  Stream<List<MatchModel>> watchFixtureMatches(
    String leagueId,
    int week, {
    String? groupId,
  }) {
    return _db.watchFixtureMatches(leagueId, week, groupId: groupId);
  }

  Future<int?> getFixtureMaxWeek(String leagueId, {String? groupId}) {
    return _db.getFixtureMaxWeek(leagueId, groupId: groupId);
  }

  Stream<MatchModel> watchMatch(String matchId) => _db.watchMatch(matchId);

  Stream<List<Map<String, dynamic>>> watchInlineMatchEvents(String matchId) {
    final id = matchId.trim();
    if (id.isEmpty) return const Stream<List<Map<String, dynamic>>>.empty();
    return _firestore
        .collection('matches')
        .doc(id)
        .collection('events')
        .orderBy('minute', descending: false)
        .snapshots()
        .map((snap) {
          return snap.docs.map((d) => Map<String, dynamic>.from(d.data())).toList();
        });
  }

  Future<void> updateMatchYoutubeUrl({
    required String matchId,
    required String? youtubeUrl,
  }) async {
    final id = matchId.trim();
    if (id.isEmpty) return;
    await _firestore.collection('matches').doc(id).update({'youtubeUrl': youtubeUrl});
  }

  Future<void> updateMatchPitchName({
    required String matchId,
    required String? pitchName,
  }) async {
    final id = matchId.trim();
    if (id.isEmpty) return;
    await _firestore.collection('matches').doc(id).update({'pitchName': pitchName});
  }

  Future<void> updateMatchSchedule({
    required String matchId,
    required String matchDateDb,
    required String matchTime,
    required String? pitchName,
  }) async {
    final id = matchId.trim();
    if (id.isEmpty) return;
    await _firestore.collection('matches').doc(id).update({
      'matchDate': matchDateDb,
      'matchTime': matchTime,
      'pitchName': pitchName,
    });
  }

  Future<void> completeMatchWithScoreAndDefaultEvents({
    required String matchId,
    required int homeScore,
    required int awayScore,
  }) async {
    final id = matchId.trim();
    if (id.isEmpty) return;

    final matchRef = _firestore.collection('matches').doc(id);
    await matchRef.update({
      'homeScore': homeScore,
      'awayScore': awayScore,
      'status': 'finished',
      'isCompleted': true,
    });

    final eventsRef = matchRef.collection('events');
    final now = FieldValue.serverTimestamp();
    await eventsRef.add({
      'minute': 0,
      'title': 'Maç Başladı',
      'type': 'status',
      'timestamp': now,
    });
    await eventsRef.add({
      'minute': 30,
      'title': 'İlk Yarı Sonucu',
      'type': 'status',
      'timestamp': now,
    });
    await eventsRef.add({
      'minute': 60,
      'title': 'Maç Sonucu',
      'type': 'status',
      'timestamp': now,
    });
  }

  Stream<List<PlayerStats>> watchPlayerStats({required String tournamentId}) {
    final tId = tournamentId.trim();
    if (tId.isEmpty) return const Stream<List<PlayerStats>>.empty();
    return _firestore
        .collection('player_stats')
        .where('tournamentId', isEqualTo: tId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => PlayerStats.fromMap(d.data(), d.id)).toList());
  }

  Future<void> commitPlayerStatsForCompletedMatch({required String matchId}) {
    return _db.commitPlayerStatsForCompletedMatch(matchId: matchId);
  }

  Future<void> importTeamsAndFixture({
    required String tournamentId,
    required List<FixtureImportTeam> teams,
    required List<FixtureImportMatch> matches,
  }) async {
    final tId = tournamentId.trim();
    if (tId.isEmpty) return;

    final teamByKey = <String, FixtureImportTeam>{};
    for (final t in teams) {
      final name = t.name.trim();
      if (name.isEmpty) continue;
      teamByKey[StringUtils.normalizeTrKey(name)] = t;
    }
    if (teamByKey.isEmpty) return;

    final existingTeamsSnap = await _firestore.collection('teams').get();
    final existingTeamIdsByNameKey = <String, String>{};
    for (final doc in existingTeamsSnap.docs) {
      final name = (doc.data()['name'] ?? '').toString();
      final key = StringUtils.normalizeTrKey(name);
      if (key.isNotEmpty) existingTeamIdsByNameKey[key] = doc.id;
    }

    var batch = _firestore.batch();
    var ops = 0;
    Future<void> commitIfNeeded() async {
      if (ops >= 450) {
        await batch.commit();
        batch = _firestore.batch();
        ops = 0;
      }
    }

    for (final entry in teamByKey.entries) {
      final key = entry.key;
      final t = entry.value;
      if (existingTeamIdsByNameKey.containsKey(key)) continue;
      final teamRef = _firestore.collection('teams').doc();
      existingTeamIdsByNameKey[key] = teamRef.id;
      batch.set(teamRef, {
        'name': t.name.trim(),
        'logoUrl': '',
        'colors': null,
        'createdAt': FieldValue.serverTimestamp(),
      });
      ops++;
      await commitIfNeeded();
    }

    for (final m in matches) {
      final hKey = StringUtils.normalizeTrKey(m.homeTeamName);
      final aKey = StringUtils.normalizeTrKey(m.awayTeamName);
      final homeId = existingTeamIdsByNameKey[hKey];
      final awayId = existingTeamIdsByNameKey[aKey];
      if (homeId == null || awayId == null) continue;

      final ref = _firestore.collection('matches').doc();
      batch.set(ref, {
        'leagueId': tId,
        'tournamentId': tId,
        'groupId': m.groupId.trim(),
        'homeTeamId': homeId,
        'homeTeamName': m.homeTeamName.trim(),
        'awayTeamId': awayId,
        'awayTeamName': m.awayTeamName.trim(),
        'score': {
          'halfTime': {'home': 0, 'away': 0},
          'fullTime': {'home': 0, 'away': 0},
        },
        'homeScore': 0,
        'awayScore': 0,
        'dateString': m.matchDateYyyyMmDd,
        'matchDate': m.matchDateYyyyMmDd,
        'status': 'notStarted',
        'week': m.week,
        'time': m.matchTime,
        'matchTime': m.matchTime,
        'pitchName': m.pitchName?.trim().isEmpty ?? true ? null : m.pitchName?.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      ops++;
      await commitIfNeeded();
    }

    if (ops > 0) await batch.commit();
  }
}

class FixtureImportTeam {
  const FixtureImportTeam({
    required this.name,
    required this.groupName,
  });

  final String name;
  final String groupName;
}

class FixtureImportMatch {
  const FixtureImportMatch({
    required this.week,
    required this.groupId,
    required this.homeTeamName,
    required this.awayTeamName,
    required this.matchDateYyyyMmDd,
    required this.matchTime,
    required this.pitchName,
  });

  final int week;
  final String groupId;
  final String homeTeamName;
  final String awayTeamName;
  final String? matchDateYyyyMmDd;
  final String? matchTime;
  final String? pitchName;
}
