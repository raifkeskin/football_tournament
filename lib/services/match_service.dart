import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/fixture_import.dart';
import '../models/match.dart';
import '../models/player_stats.dart';
import 'database_service.dart';
import 'interfaces/i_match_service.dart';
import '../utils/string_utils.dart';

class FirebaseMatchService implements IMatchService {
  FirebaseMatchService({DatabaseService? databaseService, FirebaseFirestore? firestore})
    : _db = databaseService ?? DatabaseService(firestore: firestore),
      _firestore = firestore ?? FirebaseFirestore.instance;

  final DatabaseService _db;
  final FirebaseFirestore _firestore;

  int _readInt(dynamic v, {required int fallback}) {
    if (v == null) return fallback;
    if (v is num) return v.toInt();
    final s = v.toString().replaceAll('\u0000', '').trim();
    return int.tryParse(s) ?? double.tryParse(s.replaceAll(',', '.'))?.toInt() ?? fallback;
  }

  Future<int> _readMatchPeriodDurationMinutes(String tournamentId) async {
    final id = tournamentId.trim();
    if (id.isEmpty) return 25;
    try {
      final snap = await _firestore.collection('leagues').doc(id).get();
      final data = snap.data();
      if (data == null) return 25;
      final raw = data['matchPeriodDuration'] ?? data['match_period_duration'];
      final minutes = _readInt(raw, fallback: 25);
      return minutes <= 0 ? 25 : minutes;
    } catch (_) {
      return 25;
    }
  }

  @override
  Stream<List<MatchModel>> watchMatchesForLeague(String leagueId) {
    return _db.watchMatchesForLeague(leagueId);
  }

  @override
  Stream<List<MatchModel>> watchMatchesByDate({
    required String leagueId,
    required DateTime date,
  }) {
    return _db.getMatchesByDate(leagueId: leagueId, date: date);
  }

  @override
  Stream<List<MatchModel>> watchFixtureMatches(
    String leagueId,
    int week, {
    String? groupId,
  }) {
    return _db.watchFixtureMatches(leagueId, week, groupId: groupId);
  }

  @override
  Future<int?> getFixtureMaxWeek(String leagueId, {String? groupId}) {
    return _db.getFixtureMaxWeek(leagueId, groupId: groupId);
  }

  @override
  Stream<MatchModel> watchMatch(String matchId) => _db.watchMatch(matchId);

  @override
  Stream<List<Map<String, dynamic>>> watchInlineMatchEvents(String matchId) {
    final id = matchId.trim();
    if (id.isEmpty) return const Stream<List<Map<String, dynamic>>>.empty();
    return _firestore
        .collection('match_events')
        .where('matchId', isEqualTo: id)
        .snapshots()
        .map((snap) {
          int readInt(dynamic v) {
            if (v == null) return 0;
            if (v is num) return v.toInt();
            final s = v.toString().replaceAll('\u0000', '').trim();
            return int.tryParse(s) ?? double.tryParse(s.replaceAll(',', '.'))?.toInt() ?? 0;
          }

          final list = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
          list.sort((a, b) => readInt(a['minute']).compareTo(readInt(b['minute'])));
          return list.map((m) => Map<String, dynamic>.from(m)).toList();
        });
  }

  @override
  Future<void> updateMatchYoutubeUrl({
    required String matchId,
    required String? youtubeUrl,
  }) async {
    final id = matchId.trim();
    if (id.isEmpty) return;
    await _firestore.collection('matches').doc(id).update({'youtubeUrl': youtubeUrl});
  }

  @override
  Future<void> updateMatchPitchName({
    required String matchId,
    required String? pitchName,
  }) async {
    final id = matchId.trim();
    if (id.isEmpty) return;
    await _firestore.collection('matches').doc(id).update({'pitchName': pitchName});
  }

  @override
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

  @override
  Future<void> completeMatchWithScoreAndDefaultEvents({
    required String matchId,
    required int homeScore,
    required int awayScore,
  }) async {
    final id = matchId.trim();
    if (id.isEmpty) return;

    final matchRef = _firestore.collection('matches').doc(id);
    final matchSnap = await matchRef.get();
    final matchData = matchSnap.data() ?? const <String, dynamic>{};
    final tournamentId =
        (matchData['tournamentId'] ?? matchData['leagueId'] ?? '').toString().trim();
    final homeTeamId = (matchData['homeTeamId'] ?? '').toString().trim();

    await matchRef.update({
      'homeScore': homeScore,
      'awayScore': awayScore,
      'status': 'finished',
      'isCompleted': true,
    });

    final matchPeriodDuration = await _readMatchPeriodDurationMinutes(tournamentId);
    final now = FieldValue.serverTimestamp();
    final existingStatusSnap = await _firestore
        .collection('match_events')
        .where('matchId', isEqualTo: id)
        .where('type', isEqualTo: 'status')
        .get();
    final existingTitles = <String>{};
    for (final d in existingStatusSnap.docs) {
      final data = d.data();
      final title = (data['playerName'] ?? data['title'] ?? '').toString().trim();
      if (title.isNotEmpty) existingTitles.add(title);
    }

    Future<void> addStatus(int minute, String title) async {
      final t = title.trim();
      if (t.isEmpty) return;
      if (existingTitles.contains(t)) return;
      await _firestore.collection('match_events').add({
        'matchId': id,
        'tournamentId': tournamentId,
        'teamId': homeTeamId,
        'eventType': 'status',
        'type': 'status',
        'minute': minute,
        'playerName': t,
        'createdAt': now,
      });
      existingTitles.add(t);
    }

    await addStatus(0, 'Maç Başladı');
    await addStatus(matchPeriodDuration, 'İlk Yarı Bitti');
    await addStatus(matchPeriodDuration * 2, 'Maç Bitti');
  }

  @override
  Stream<List<PlayerStats>> watchPlayerStats({required String tournamentId}) {
    final tId = tournamentId.trim();
    if (tId.isEmpty) return const Stream<List<PlayerStats>>.empty();
    return _firestore
        .collection('player_stats')
        .where('tournamentId', isEqualTo: tId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => PlayerStats.fromMap(d.data(), d.id)).toList());
  }

  @override
  Future<void> commitPlayerStatsForCompletedMatch({required String matchId}) {
    return _db.commitPlayerStatsForCompletedMatch(matchId: matchId);
  }

  @override
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
