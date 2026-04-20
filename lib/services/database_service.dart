import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/award.dart';
import '../models/league.dart';
import '../models/match.dart';
import '../models/player_stats.dart';
import '../models/team.dart';
import '../utils/string_utils.dart';

class DatabaseService {
  DatabaseService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  Future<bool> isLeagueUnique({
    required String name,
    required String subtitle,
    String? excludeLeagueId,
  }) async {
    final nameKey = StringUtils.normalizeTrKey(name);
    final subtitleKey = StringUtils.normalizeTrKey(subtitle);

    final byNameKey = await _db
        .collection('leagues')
        .where('nameKey', isEqualTo: nameKey)
        .get();
    for (final d in byNameKey.docs) {
      if (excludeLeagueId != null && d.id == excludeLeagueId) continue;
      final data = d.data();
      final existingSubtitleKey = (data['subtitleKey'] as String?) ??
          StringUtils.normalizeTrKey((data['subtitle'] ?? '').toString());
      if (existingSubtitleKey == subtitleKey) return false;
    }

    final byName = await _db
        .collection('leagues')
        .where('name', isEqualTo: name.trim())
        .get();
    for (final d in byName.docs) {
      if (excludeLeagueId != null && d.id == excludeLeagueId) continue;
      final data = d.data();
      final existingSubtitle = (data['subtitle'] ?? '').toString();
      if (StringUtils.normalizeTrKey(existingSubtitle) == subtitleKey) {
        return false;
      }
    }
    return true;
  }

  Future<List<PlayerModel>> _getPlayersOnce(String teamId) async {
    return const <PlayerModel>[];
  }

  Future<void> _ensureDummyPlayersForTeam({
    required Random random,
    required String teamId,
    required int minCount,
  }) async {
    return;

  }

  List<List<Team?>> _roundRobinRounds(List<Team> teams) {
    final list = <Team?>[...teams];
    if (list.length.isOdd) list.add(null);
    final n = list.length;
    if (n < 2) return const [];

    final rounds = <List<Team?>>[];
    var arr = <Team?>[...list];
    final roundCount = n - 1;
    for (var r = 0; r < roundCount; r++) {
      final pairs = <Team?>[];
      for (var i = 0; i < n ~/ 2; i++) {
        final a = arr[i];
        final b = arr[n - 1 - i];
        pairs.add(a);
        pairs.add(b);
      }
      rounds.add(pairs);

      final fixed = arr.first;
      final rest = arr.sublist(1);
      rest.insert(0, rest.removeLast());
      arr = [fixed, ...rest];
    }
    return rounds;
  }

  Future<int> _deleteQueryInBatches(Query<Map<String, dynamic>> query) async {
    var deleted = 0;
    while (true) {
      final snap = await query.limit(450).get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      deleted += snap.docs.length;
    }
    return deleted;
  }

  Future<void> _clearGroupFromTeams(String groupId) async {
    while (true) {
      final snap = await _db
          .collection('teams')
          .where('groupId', isEqualTo: groupId)
          .limit(450)
          .get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'groupId': null, 'groupName': null});
      }
      await batch.commit();
    }
  }

  Future<void> _deleteMatchEventsForMatchId(String matchId) async {
    await _deleteQueryInBatches(
      _db.collection('match_events').where('matchId', isEqualTo: matchId),
    );
  }

  Future<void> _deleteMatchesAndEventsForQuery(
    Query<Map<String, dynamic>> matchQuery,
  ) async {
    while (true) {
      final matchesSnap = await matchQuery.limit(200).get();
      if (matchesSnap.docs.isEmpty) break;
      for (final m in matchesSnap.docs) {
        await _deleteMatchEventsForMatchId(m.id);
        await m.reference.delete();
      }
    }
  }

  // --- LEAGUE (TURNUVA) ---
  Future<String> addLeague(League league) async {
    final subtitle = (league.subtitle ?? '').trim();
    final unique = await isLeagueUnique(name: league.name, subtitle: subtitle);
    if (!unique) {
      throw Exception('Bu isim ve alt bilgi kombinasyonuna sahip bir turnuva zaten var!');
    }

    DocumentReference ref = await _db.collection('leagues').add({
      ...league.toMap(),
      'nameKey': StringUtils.normalizeTrKey(league.name),
      'subtitleKey': StringUtils.normalizeTrKey(subtitle),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateLeague(League league) async {
    final subtitle = (league.subtitle ?? '').trim();
    final unique = await isLeagueUnique(
      name: league.name,
      subtitle: subtitle,
      excludeLeagueId: league.id,
    );
    if (!unique) {
      throw Exception('Bu isim ve alt bilgi kombinasyonuna sahip bir turnuva zaten var!');
    }
    await _db.collection('leagues').doc(league.id).update({
      ...league.toMap(),
      'nameKey': StringUtils.normalizeTrKey(league.name),
      'subtitleKey': StringUtils.normalizeTrKey(subtitle),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> getLeagues() {
    return _db.collection('leagues').orderBy('name').snapshots();
  }

  Future<void> setDefaultLeague({required String leagueId}) async {
    final prevDefaults = await _db
        .collection('leagues')
        .where('isDefault', isEqualTo: true)
        .get();

    final batch = _db.batch();
    for (final doc in prevDefaults.docs) {
      if (doc.id == leagueId) continue;
      batch.update(doc.reference, {
        'isDefault': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    batch.update(_db.collection('leagues').doc(leagueId), {
      'isDefault': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> setLeagueDefaultFlag({
    required String leagueId,
    required bool isDefault,
  }) async {
    await _db.collection('leagues').doc(leagueId).update({
      'isDefault': isDefault,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteLeagueCascade(String leagueId) async {
    final groupsSnap = await _db
        .collection('groups')
        .where('tournamentId', isEqualTo: leagueId)
        .get();
    for (final g in groupsSnap.docs) {
      await deleteGroupCascade(g.id);
    }

    await _deleteMatchesAndEventsForQuery(
      _db.collection('matches').where('tournamentId', isEqualTo: leagueId),
    );
    await _db.collection('leagues').doc(leagueId).delete();
  }

  // --- GROUP (GRUP) ---
  Future<void> addGroup(GroupModel group) async {
    await _db.collection('groups').add(group.toMap());
  }

  Stream<List<GroupModel>> getGroups(String leagueId) {
    return _db
        .collection('groups')
        .where('tournamentId', isEqualTo: leagueId)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => GroupModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Stream<List<GroupModel>> getAllGroups() {
    return _db
        .collection('groups')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => GroupModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<List<League>> getTeamActiveTournaments(String teamId) async {
    final tId = teamId.trim();
    if (tId.isEmpty) return [];

    final groupSnap = await _db
        .collection('groups')
        .where('teamIds', arrayContains: tId)
        .get();

    final tournamentIds = <String>{};
    for (final doc in groupSnap.docs) {
      final data = doc.data();
      final tournamentId =
          (data['tournamentId'] ?? data['leagueId'] ?? '').toString().trim();
      if (tournamentId.isNotEmpty) tournamentIds.add(tournamentId);
    }

    if (tournamentIds.isEmpty) return [];

    final leagues = <League>[];
    final ids = tournamentIds.toList();
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, min(i + 10, ids.length));
      final tournamentSnap = await _db
          .collection('leagues')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in tournamentSnap.docs) {
        leagues.add(League.fromMap({...doc.data(), 'id': doc.id}));
      }
    }

    final active = leagues.where((l) => l.isActive).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return active;
  }

  Future<void> deleteGroupCascade(String groupId) async {
    await _clearGroupFromTeams(groupId);
    await _deleteMatchesAndEventsForQuery(
      _db.collection('matches').where('groupId', isEqualTo: groupId),
    );
    await _db.collection('groups').doc(groupId).delete();
  }

  // --- TEAM (TAKIM) ---
  Future<void> addTeam(String leagueId, String teamName, String logoUrl) async {
    await _db.collection('teams').add({
      'leagueId': leagueId,
      'name': teamName,
      'logoUrl': logoUrl,
      'stats': {
        'P': 0,
        'G': 0,
        'B': 0,
        'M': 0,
        'AG': 0,
        'YG': 0,
        'AV': 0,
        'Puan': 0,
      },
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateTeam(String teamId, Map<String, dynamic> data) async {
    await _db.collection('teams').doc(teamId).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> getTeams() {
    return _db.collection('teams').orderBy('name').snapshots();
  }

  // --- AWARD (ÖDÜL / KUPA) ---
  Stream<List<Award>> getAwardsForLeague(String leagueId) {
    return _db
        .collection('awards')
        .where('leagueId', isEqualTo: leagueId)
        .orderBy('name')
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) => Award.fromMap(d.data(), d.id)).toList(),
        );
  }

  Future<void> addAward({
    required String leagueId,
    required String name,
    String? description,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _db.collection('awards').add({
      'leagueId': leagueId,
      'tournamentId': leagueId,
      'name': trimmed,
      'awardName': trimmed,
      'description': (description ?? '').trim().isEmpty ? null : description!.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteAward(String awardId) async {
    await _db.collection('awards').doc(awardId).delete();
  }

  Stream<List<Team>> getTeamsByGroup(String groupId) {
    return _db
        .collection('teams')
        .where('groupId', isEqualTo: groupId)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => Team.fromMap({...doc.data(), 'id': doc.id}))
              .toList(),
        );
  }

  Future<void> deleteTeamCascade(String teamId) async {
    final teamDoc = await _db.collection('teams').doc(teamId).get();
    final teamData = teamDoc.data();
    final groupId = (teamData?['groupId'] as String?)?.trim();
    if (groupId != null && groupId.isNotEmpty) {
      await _db.collection('groups').doc(groupId).update({
        'teamIds': FieldValue.arrayRemove([teamId]),
      });
    }

    await _deleteQueryInBatches(
      _db.collection('players').where('teamId', isEqualTo: teamId),
    );

    final homeMatches = await _db
        .collection('matches')
        .where('homeTeamId', isEqualTo: teamId)
        .get();
    for (final m in homeMatches.docs) {
      await _deleteMatchEventsForMatchId(m.id);
      await m.reference.delete();
    }

    final awayMatches = await _db
        .collection('matches')
        .where('awayTeamId', isEqualTo: teamId)
        .get();
    for (final m in awayMatches.docs) {
      await _deleteMatchEventsForMatchId(m.id);
      await m.reference.delete();
    }

    await _db.collection('teams').doc(teamId).delete();
  }

  // --- PLAYER (OYUNCU) ---
  Future<void> _assertPlayerUnique({
    required String name,
    required String? birthDate,
    String? excludePlayerId,
  }) async {
    final normalizedBirthDate = (birthDate ?? '').trim();
    if (normalizedBirthDate.isEmpty) return;
    final key = StringUtils.normalizeTrKey(name);
    final seen = <String>{};

    Future<void> scan(QuerySnapshot<Map<String, dynamic>> snap) async {
      for (final d in snap.docs) {
        if (!seen.add(d.id)) continue;
        if (excludePlayerId != null && d.id == excludePlayerId) continue;
        final existingName = (d.data()['name'] ?? '').toString();
        if (StringUtils.normalizeTrKey(existingName) == key) {
          throw Exception(
            'Bu futbolcu zaten sistemde kayıtlı!',
          );
        }
      }
    }

    final byBirthDate = await _db
        .collection('players')
        .where('birthDate', isEqualTo: normalizedBirthDate)
        .get();
    await scan(byBirthDate);

    final year = int.tryParse(
      RegExp(r'(19\d{2}|20\d{2}|2100)$').firstMatch(normalizedBirthDate)?.group(0) ??
          '',
    );
    if (year != null) {
      final byInt = await _db
          .collection('players')
          .where('birthYear', isEqualTo: year)
          .get();
      await scan(byInt);

      final byStr = await _db
          .collection('players')
          .where('birthYear', isEqualTo: year.toString())
          .get();
      await scan(byStr);

      final byYearStringAsBirthDate = await _db
          .collection('players')
          .where('birthDate', isEqualTo: year.toString())
          .get();
      await scan(byYearStringAsBirthDate);
    }
  }

  Future<void> addPlayer(PlayerModel player) async {
    final phone = (player.phone ?? '').trim();
    await upsertPlayerIdentity(
      phone: phone,
      name: player.name,
      birthDate: player.birthDate,
      mainPosition: player.mainPosition,
    );
  }

  Future<void> updatePlayer({
    required String playerId,
    required Map<String, dynamic> data,
  }) async {
    await _db.collection('players').doc(playerId).set({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setPlayerSuspendedMatches({
    required String playerId,
    required int suspendedMatches,
  }) async {
    await _db.collection('players').doc(playerId).update({
      'suspendedMatches': suspendedMatches,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, dynamic>?> getPenaltyForPlayer(String playerId) async {
    final snap = await _db.collection('penalties').doc(playerId).get();
    return snap.data();
  }

  Future<void> clearPenaltyForPlayer({required String playerId}) async {
    final pId = playerId.trim();
    if (pId.isEmpty) return;
    final batch = _db.batch();
    batch.delete(_db.collection('penalties').doc(pId));
    batch.update(_db.collection('players').doc(pId), {
      'suspendedMatches': 0,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> upsertPenaltyForPlayer({
    required String playerId,
    required String teamId,
    required String penaltyReason,
    required int matchCount,
  }) async {
    final pId = playerId.trim();
    final tId = teamId.trim();
    final reason = penaltyReason.trim();
    if (pId.isEmpty || tId.isEmpty) {
      throw Exception('Ceza alanları eksik.');
    }
    if (matchCount < 0) {
      throw Exception('Maç sayısı geçerli olmalı.');
    }

    if (matchCount == 0) {
      await clearPenaltyForPlayer(playerId: pId);
      return;
    }

    final batch = _db.batch();
    final playerRef = _db.collection('players').doc(pId);
    final penaltyRef = _db.collection('penalties').doc(pId);

    batch.set(
      penaltyRef,
      {
        'playerId': pId,
        'teamId': tId,
        'penaltyReason': reason,
        'matchCount': matchCount,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    batch.update(playerRef, {
      'suspendedMatches': matchCount,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Stream<List<PlayerModel>> getPlayers(String teamId, {String? tournamentId}) {
    Query<Map<String, dynamic>> q = _db.collection('rosters').where(
      'teamId',
      isEqualTo: teamId,
    );
    final tId = (tournamentId ?? '').trim();
    if (tId.isNotEmpty) {
      q = q.where('tournamentId', isEqualTo: tId);
    }
    return q.snapshots().map((snap) {
      final list =
          snap.docs.map((doc) => PlayerModel.fromMap(doc.data(), doc.id)).toList();
      list.sort((a, b) {
        bool isManager(PlayerModel p) =>
            p.role == 'Takım Sorumlusu' || p.role == 'Her İkisi';
        final aM = isManager(a);
        final bM = isManager(b);
        if (aM != bM) return aM ? -1 : 1;
        final an = int.tryParse((a.number ?? '').trim()) ?? 9999;
        final bn = int.tryParse((b.number ?? '').trim()) ?? 9999;
        final cmp = an.compareTo(bn);
        if (cmp != 0) return cmp;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return list;
    });
  }

  Future<void> upsertPlayerIdentity({
    required String phone,
    required String name,
    String? birthDate,
    String? mainPosition,
  }) async {
    final p = phone.trim();
    if (p.isEmpty) throw Exception('Telefon boş olamaz.');
    final n = name.trim();
    if (n.isEmpty) throw Exception('İsim boş olamaz.');
    await _db.collection('players').doc(p).set(
      {
        'phone': p,
        'name': n,
        'birthDate': (birthDate ?? '').trim().isEmpty ? null : birthDate!.trim(),
        'mainPosition':
            (mainPosition ?? '').trim().isEmpty ? null : mainPosition!.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> upsertRosterEntry({
    required String tournamentId,
    required String teamId,
    required String playerPhone,
    required String playerName,
    String? jerseyNumber,
    required String role,
  }) async {
    final t = tournamentId.trim();
    final team = teamId.trim();
    final phone = playerPhone.trim();
    final name = playerName.trim();
    if (t.isEmpty || team.isEmpty || phone.isEmpty) {
      throw Exception('Kadro alanları eksik.');
    }
    final docId = '${phone}_${t}_$team';
    await _db.collection('rosters').doc(docId).set(
      {
        'tournamentId': t,
        'teamId': team,
        'playerPhone': phone,
        'playerName': name,
        'jerseyNumber': (jerseyNumber ?? '').trim().isEmpty ? null : jerseyNumber!.trim(),
        'role': role.trim().isEmpty ? 'Futbolcu' : role.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchRostersByPlayerPhone(
    String playerPhone,
  ) {
    final p = playerPhone.trim();
    return _db
        .collection('rosters')
        .where('playerPhone', isEqualTo: p)
        .snapshots();
  }

  Future<int> migratePlayersDefaultRoleAndBirthDate() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'migration_players_role_birthdate_v1';
    if (prefs.getBool(key) == true) return 0;

    final snap = await _db.collection('players').get();
    var updated = 0;
    var batch = _db.batch();
    var ops = 0;

    String? normalizeBirthDateFrom(dynamic value) {
      if (value == null) return null;
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
      final year = int.tryParse(s);
      if (year != null && year >= 1900 && year <= 2100) {
        return '01/01/${year.toString().padLeft(4, '0')}';
      }
      final yr = int.tryParse(
        RegExp(r'(19\d{2}|20\d{2}|2100)').firstMatch(s)?.group(0) ?? '',
      );
      if (yr != null && yr >= 1900 && yr <= 2100) {
        return '01/01/${yr.toString().padLeft(4, '0')}';
      }
      return null;
    }

    int? yearFromBirthDate(String? birthDate) {
      if (birthDate == null) return null;
      final m = RegExp(r'(\d{4})$').firstMatch(birthDate);
      final y = m == null ? null : int.tryParse(m.group(1)!);
      if (y == null) return null;
      if (y < 1900 || y > 2100) return null;
      return y;
    }

    Future<void> flush() async {
      if (ops == 0) return;
      await batch.commit();
      batch = _db.batch();
      ops = 0;
    }

    for (final d in snap.docs) {
      final data = d.data();
      final updates = <String, dynamic>{};

      final role = (data['role'] ?? '').toString().trim();
      if (role.isEmpty) {
        updates['role'] = 'Futbolcu';
      }

      final bd = normalizeBirthDateFrom(data['birthDate']);
      if (bd == null) {
        final legacy = normalizeBirthDateFrom(data['birthYear']);
        if (legacy != null) {
          updates['birthDate'] = legacy;
          final y = yearFromBirthDate(legacy);
          if (y != null) updates['birthYear'] = y;
        }
      } else {
        final y = yearFromBirthDate(bd);
        if (y != null && data['birthYear'] != y) {
          updates['birthYear'] = y;
        }
        if (data['birthDate'] != bd) updates['birthDate'] = bd;
      }

      if (updates.isEmpty) continue;
      batch.update(d.reference, updates);
      ops++;
      updated++;
      if (ops >= 450) {
        await flush();
      }
    }
    await flush();

    await prefs.setBool(key, true);
    return updated;
  }

  Future<int> migratePlayersPhoneRaw10() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'migration_players_phone_raw10_v1';
    if (prefs.getBool(key) == true) return 0;

    String normalizePhoneToRaw10(dynamic value) {
      if (value == null) return '';
      final digits = value.toString().replaceAll(RegExp(r'\D'), '');
      if (digits.isEmpty) return '';
      var d = digits;
      if (d.startsWith('90') && d.length >= 12) d = d.substring(2);
      if (d.startsWith('0')) d = d.substring(1);
      if (d.length > 10) d = d.substring(d.length - 10);
      return d;
    }

    final snap = await _db.collection('players').get();
    var updated = 0;
    var batch = _db.batch();
    var ops = 0;

    Future<void> flush() async {
      if (ops == 0) return;
      await batch.commit();
      batch = _db.batch();
      ops = 0;
    }

    for (final doc in snap.docs) {
      final data = doc.data();
      final phoneRaw10 = normalizePhoneToRaw10(data['phone']);
      final current = normalizePhoneToRaw10(data['phoneRaw10']);
      if (phoneRaw10.isEmpty) continue;
      if (current == phoneRaw10) continue;
      batch.update(doc.reference, {
        'phoneRaw10': phoneRaw10,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      ops++;
      updated++;
      if (ops >= 450) {
        await flush();
      }
    }
    await flush();
    await prefs.setBool(key, true);
    return updated;
  }

  Stream<List<PlayerModel>> watchAllPlayers() {
    return _db.collection('players').snapshots().map((snap) {
      return snap.docs.map((d) => PlayerModel.fromMap(d.data(), d.id)).toList();
    });
  }

  // --- MATCH (MAÇ) ---
  Stream<List<MatchModel>> getMatches(String leagueId, DateTime date) {
    return getMatchesByDate(leagueId: leagueId, date: date);
  }

  Stream<List<MatchModel>> watchMatchesForLeague(String leagueId) {
    return _db
        .collection('matches')
        .where('leagueId', isEqualTo: leagueId)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => MatchModel.fromMap(d.data(), d.id)).toList(),
        );
  }

  Stream<List<MatchModel>> watchFixtureMatches(
    String leagueId,
    int week, {
    String? groupId,
  }) {
    Query<Map<String, dynamic>> q = _db
        .collection('matches')
        .where('leagueId', isEqualTo: leagueId)
        .where('week', isEqualTo: week);
    final gid = (groupId ?? '').trim();
    if (gid.isNotEmpty) {
      q = q.where('groupId', isEqualTo: gid);
    }
    return q.snapshots().map(
          (snap) =>
              snap.docs.map((d) => MatchModel.fromMap(d.data(), d.id)).toList(),
        );
  }

  Future<int?> getFixtureMaxWeek(
    String leagueId, {
    String? groupId,
  }) async {
    Query<Map<String, dynamic>> q =
        _db.collection('matches').where('leagueId', isEqualTo: leagueId);
    final gid = (groupId ?? '').trim();
    if (gid.isNotEmpty) {
      q = q.where('groupId', isEqualTo: gid);
    }
    final snap = await q.get();
    if (snap.docs.isEmpty) return null;
    int? maxWeek;
    for (final doc in snap.docs) {
      final raw = doc.data()['week'];
      final w = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
      if (w == null) continue;
      maxWeek = maxWeek == null ? w : (w > maxWeek ? w : maxWeek);
    }
    return maxWeek;
  }

  Stream<MatchModel> watchMatch(String matchId) {
    return _db.collection('matches').doc(matchId).snapshots().map((snap) {
      final data = snap.data() ?? <String, dynamic>{};
      return MatchModel.fromMap(data, snap.id);
    });
  }

  Future<void> updateMatchLineups({
    required String matchId,
    required MatchLineup homeLineup,
    required MatchLineup awayLineup,
  }) async {
    final homePhones = [
      ...homeLineup.starting.map((p) => p.playerId.trim()),
      ...homeLineup.subs.map((p) => p.playerId.trim()),
    ].where((e) => e.isNotEmpty).toList();
    final awayPhones = [
      ...awayLineup.starting.map((p) => p.playerId.trim()),
      ...awayLineup.subs.map((p) => p.playerId.trim()),
    ].where((e) => e.isNotEmpty).toList();
    await _db.collection('matches').doc(matchId).update({
      'homeLineup': homePhones,
      'awayLineup': awayPhones,
      'homeLineupDetail': homeLineup.toMap(),
      'awayLineupDetail': awayLineup.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateMatchLineup({
    required String matchId,
    required bool isHome,
    required MatchLineup lineup,
  }) async {
    final phones = [
      ...lineup.starting.map((p) => p.playerId.trim()),
      ...lineup.subs.map((p) => p.playerId.trim()),
    ].where((e) => e.isNotEmpty).toList();
    await _db.collection('matches').doc(matchId).update({
      isHome ? 'homeLineup' : 'awayLineup': phones,
      isHome ? 'homeLineupDetail' : 'awayLineupDetail': lineup.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<MatchModel>> getMatchesByDate({
    String? leagueId,
    required DateTime date,
  }) {
    final dStr =
        "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

    Query<Map<String, dynamic>> qNew = _db
        .collection('matches')
        .where('matchDate', isEqualTo: dStr);
    Query<Map<String, dynamic>> qAllForNew = _db.collection('matches');
    Query<Map<String, dynamic>> qLegacyString = _db
        .collection('matches')
        .where('dateString', isEqualTo: dStr);

    if (leagueId != null) {
      qNew = qNew.where('leagueId', isEqualTo: leagueId);
      qAllForNew = qAllForNew.where('leagueId', isEqualTo: leagueId);
      qLegacyString = qLegacyString.where('leagueId', isEqualTo: leagueId);
    }

    final controller = StreamController<List<MatchModel>>.broadcast();
    List<MatchModel> latestNew = const [];
    List<MatchModel> latestLegacyString = const [];

    void emit() {
      final merged = <String, MatchModel>{};
      for (final m in latestNew) {
        merged[m.id] = m;
      }
      for (final m in latestLegacyString) {
        merged[m.id] = m;
      }
      final list = merged.values.toList()
        ..sort((a, b) {
          final at = (a.matchTime ?? '').trim();
          final bt = (b.matchTime ?? '').trim();
          if (at.isEmpty && bt.isEmpty) {
            return a.homeTeamName
                .toLowerCase()
                .compareTo(b.homeTeamName.toLowerCase());
          }
          if (at.isEmpty) return 1;
          if (bt.isEmpty) return -1;
          final cmp = at.compareTo(bt);
          if (cmp != 0) return cmp;
          return a.homeTeamName
              .toLowerCase()
              .compareTo(b.homeTeamName.toLowerCase());
        });
      controller.add(list);
    }

    late final StreamSubscription subNew;
    late final StreamSubscription subLegacyString;
    StreamSubscription? subNewFallback;

    controller.onListen = () {
      Future<void> migrateIfNeeded(
        QueryDocumentSnapshot<Map<String, dynamic>> doc,
        Map<String, dynamic> data,
      ) async {
        final hasNewDate = (data['matchDate'] is String) &&
            (data['matchDate'] as String).trim().isNotEmpty;
        final hasNewTime = (data['matchTime'] is String) &&
            (data['matchTime'] as String).trim().isNotEmpty;
        final hasLegacyDateString = (data['dateString'] is String) &&
            (data['dateString'] as String).trim().isNotEmpty;
        final hasLegacyTime =
            (data['time'] is String) && (data['time'] as String).trim().isNotEmpty;
        final raw = data['matchDate'];
        final hasLegacyTimestamp = raw is Timestamp;

        if (hasNewDate && (hasNewTime || !hasLegacyTime) && !hasLegacyDateString && !hasLegacyTime && !hasLegacyTimestamp) {
          return;
        }

        String? newDate = hasNewDate ? (data['matchDate'] as String).trim() : null;
        String? newTime = hasNewTime ? (data['matchTime'] as String).trim() : null;

        if ((newDate ?? '').isEmpty && hasLegacyDateString) {
          newDate = (data['dateString'] as String).trim();
        }
        if (((newDate ?? '').isEmpty || (newTime ?? '').isEmpty) && raw is Timestamp) {
          final dt = raw.toDate();
          newDate =
              "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
          if ((newTime ?? '').isEmpty) {
            newTime =
                "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
          }
        }
        if ((newTime ?? '').isEmpty && hasLegacyTime) {
          newTime = (data['time'] as String).trim();
        }

        await doc.reference.update({
          'matchDate': (newDate ?? '').trim().isEmpty ? null : newDate,
          'matchTime': (newTime ?? '').trim().isEmpty ? null : newTime,
          'dateString': FieldValue.delete(),
          'time': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      subNew = qNew.snapshots().listen(
        (snap) {
          latestNew = snap.docs
              .map((doc) => MatchModel.fromMap(doc.data(), doc.id))
              .toList();
          emit();
        },
        onError: (_) {
          if (subNewFallback != null) return;
          subNewFallback = qAllForNew.snapshots().listen((snap) {
            latestNew = snap.docs
                .where((d) => (d.data()['matchDate'] ?? '').toString().trim() == dStr)
                .map((doc) => MatchModel.fromMap(doc.data(), doc.id))
                .toList();
            emit();
          });
        },
      );

      subLegacyString = qLegacyString.snapshots().listen((snap) async {
        final list = <MatchModel>[];
        for (final doc in snap.docs) {
          final data = doc.data();
          list.add(MatchModel.fromMap(data, doc.id));
          await migrateIfNeeded(doc, data);
        }
        latestLegacyString = list;
        emit();
      });
    };

    controller.onCancel = () async {
      await subNew.cancel();
      await subNewFallback?.cancel();
      await subLegacyString.cancel();
      await controller.close();
    };

    return controller.stream;
  }

  Future<String> addMatch(MatchModel match) async {
    final ref = await _db.collection('matches').add(match.toMap());
    return ref.id;
  }

  Future<void> updateMatch(MatchModel match) async {
    await _db.collection('matches').doc(match.id).update({
      ...match.toMap(),
      'dateString': FieldValue.delete(),
      'time': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (match.status == MatchStatus.finished && match.groupId != null) {
      await calculateStandings(match.groupId!);
    }
    if (match.status == MatchStatus.finished) {
      await commitPlayerStatsForCompletedMatch(matchId: match.id);
    }
  }

  Future<void> updateMatchYoutubeUrl({
    required String matchId,
    required String? youtubeUrl,
  }) async {
    final url = (youtubeUrl ?? '').trim();
    await _db.collection('matches').doc(matchId).update({
      'youtubeUrl': url.isEmpty ? null : url,
    });
  }

  Future<void> updateMatchHighlightPhotoUrl({
    required String matchId,
    required bool isHome,
    required String? photoUrl,
  }) async {
    final url = (photoUrl ?? '').trim();
    await _db.collection('matches').doc(matchId).update({
      isHome ? 'homeHighlightPhotoUrl' : 'awayHighlightPhotoUrl':
          url.isEmpty ? null : url,
    });
  }

  Future<Map<String, int>> migrateMatchesTimeTimestampToMatchFields() async {
    int scanned = 0;
    int updated = 0;
    DocumentSnapshot<Map<String, dynamic>>? lastDoc;

    while (true) {
      Query<Map<String, dynamic>> q = _db
          .collection('matches')
          .orderBy(FieldPath.documentId)
          .limit(400);
      if (lastDoc != null) {
        q = q.startAfterDocument(lastDoc);
      }

      final snap = await q.get();
      if (snap.docs.isEmpty) break;
      lastDoc = snap.docs.last;

      WriteBatch batch = _db.batch();
      var ops = 0;

      for (final doc in snap.docs) {
        scanned++;
        final data = doc.data();
        final raw = data['time'];
        if (raw is! Timestamp) continue;

        final dt = raw.toDate();
        final matchDate =
            "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
        final matchTime =
            "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";

        batch.update(doc.reference, {
          'matchDate': matchDate,
          'matchTime': matchTime,
          'time': FieldValue.delete(),
          'dateString': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        ops++;
        updated++;
        if (ops >= 450) {
          await batch.commit();
          batch = _db.batch();
          ops = 0;
        }
      }

      if (ops > 0) {
        await batch.commit();
      }
    }

    return {'scanned': scanned, 'updated': updated};
  }

  // --- MATCH EVENTS (OLAYLAR) ---
  Stream<List<MatchEvent>> getMatchEvents(String matchId) {
    return _db
        .collection('match_events')
        .where('matchId', isEqualTo: matchId)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((doc) => MatchEvent.fromMap(doc.data(), doc.id))
              .toList();
          list.sort((a, b) => a.minute.compareTo(b.minute));
          return list;
        });
  }

  Future<void> addMatchEvent(MatchEvent event) async {
    await _db.collection('match_events').add(event.toMap());

    // 1. Maç skorunu güncelle (Eğer gol ise)
    if (event.type == 'goal') {
      await _db.runTransaction((txn) async {
        final matchRef = _db.collection('matches').doc(event.matchId);
        final matchDoc = await txn.get(matchRef);
        if (!matchDoc.exists) return;
        final data = matchDoc.data() ?? const <String, dynamic>{};
        final homeTeamId = (data['homeTeamId'] ?? '').toString();
        final awayTeamId = (data['awayTeamId'] ?? '').toString();
        final scoringTeamId = event.isOwnGoal
            ? (event.teamId == homeTeamId ? awayTeamId : homeTeamId)
            : event.teamId;
        final isHome = scoringTeamId == homeTeamId;
        final isAway = scoringTeamId == awayTeamId;
        if (!isHome && !isAway) return;

        final scoreRaw = data['score'];
        final scoreMap =
            (scoreRaw is Map) ? Map<String, dynamic>.from(scoreRaw) : <String, dynamic>{};
        final ftRaw = scoreMap['fullTime'];
        final ft =
            (ftRaw is Map) ? Map<String, dynamic>.from(ftRaw) : <String, dynamic>{};
        final currentHome = (ft['home'] is num) ? (ft['home'] as num).toInt() : int.tryParse((ft['home'] ?? '0').toString()) ?? 0;
        final currentAway = (ft['away'] is num) ? (ft['away'] as num).toInt() : int.tryParse((ft['away'] ?? '0').toString()) ?? 0;
        final nextHome = isHome ? currentHome + 1 : currentHome;
        final nextAway = isAway ? currentAway + 1 : currentAway;
        txn.update(matchRef, {
          'score': {
            ...scoreMap,
            'fullTime': {'home': nextHome, 'away': nextAway},
          },
          'homeScore': nextHome,
          'awayScore': nextAway,
        });
      });
    }
  }

  Future<void> commitPlayerStatsForCompletedMatch({required String matchId}) async {
    final matchRef = _db.collection('matches').doc(matchId);
    final matchSnap = await matchRef.get();
    final match = matchSnap.data();
    if (match == null) return;

    final status = (match['status'] ?? '').toString().trim();
    if (status != MatchStatus.finished.name && status.toLowerCase() != 'completed') {
      return;
    }
    if (match['statsCommittedAt'] != null || match['statsCommitted'] == true) {
      return;
    }

    final tournamentId = (match['tournamentId'] ?? match['leagueId'] ?? '').toString().trim();
    if (tournamentId.isEmpty) return;

    List<String> asPhones(dynamic v) {
      if (v is! List) return const <String>[];
      return v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }

    final homeTeamId = (match['homeTeamId'] ?? '').toString().trim();
    final awayTeamId = (match['awayTeamId'] ?? '').toString().trim();
    final homeLineup = asPhones(match['homeLineup']);
    final awayLineup = asPhones(match['awayLineup']);
    if (homeTeamId.isEmpty || awayTeamId.isEmpty) return;

    final deltas = <String, Map<String, int>>{};
    final teamByPhone = <String, String>{};

    void ensurePhone(String phone, {required String teamId}) {
      final p = phone.trim();
      if (p.isEmpty) return;
      deltas.putIfAbsent(p, () => <String, int>{});
      teamByPhone.putIfAbsent(p, () => teamId);
    }

    for (final p in homeLineup) {
      ensurePhone(p, teamId: homeTeamId);
      deltas[p]!['matchesPlayed'] = (deltas[p]!['matchesPlayed'] ?? 0) + 1;
    }
    for (final p in awayLineup) {
      ensurePhone(p, teamId: awayTeamId);
      deltas[p]!['matchesPlayed'] = (deltas[p]!['matchesPlayed'] ?? 0) + 1;
    }

    final eventsSnap = await _db
        .collection('match_events')
        .where('matchId', isEqualTo: matchId)
        .get();

    for (final doc in eventsSnap.docs) {
      final e = doc.data();
      final eventType = (e['eventType'] ?? e['type'] ?? '').toString().trim();
      final teamId = (e['teamId'] ?? '').toString().trim();
      final playerPhone = (e['playerPhone'] ?? '').toString().trim();
      final assistPhone = (e['assistPlayerPhone'] ?? '').toString().trim();

      void bump(String phone, String field, {int by = 1, String? teamIdOverride}) {
        final p = phone.trim();
        if (p.isEmpty) return;
        ensurePhone(p, teamId: (teamIdOverride ?? teamId).trim().isEmpty ? (teamByPhone[p] ?? '') : (teamIdOverride ?? teamId));
        deltas[p]![field] = (deltas[p]![field] ?? 0) + by;
      }

      switch (eventType) {
        case 'goal':
          bump(playerPhone, 'goals');
          if (assistPhone.isNotEmpty) bump(assistPhone, 'assists');
          break;
        case 'assist':
          bump(playerPhone, 'assists');
          break;
        case 'yellow_card':
          bump(playerPhone, 'yellowCards');
          break;
        case 'red_card':
          bump(playerPhone, 'redCards');
          break;
        case 'man_of_the_match':
          bump(playerPhone, 'manOfTheMatch');
          break;
      }
    }

    final batch = _db.batch();
    for (final entry in deltas.entries) {
      final phone = entry.key;
      final fields = entry.value;
      final teamId = (teamByPhone[phone] ?? '').trim();
      final statsId = PlayerStats.docId(playerPhone: phone, tournamentId: tournamentId);
      final statsRef = _db.collection('player_stats').doc(statsId);

      final payload = <String, dynamic>{
        'playerPhone': phone,
        'tournamentId': tournamentId,
        'teamId': teamId,
        'updatedAt': FieldValue.serverTimestamp(),
        if (match['statsCommittedAt'] == null) 'createdAt': FieldValue.serverTimestamp(),
      };

      for (final f in fields.entries) {
        payload[f.key] = FieldValue.increment(f.value);
      }

      batch.set(statsRef, payload, SetOptions(merge: true));
    }

    batch.update(matchRef, {
      'statsCommittedAt': FieldValue.serverTimestamp(),
      'statsCommitted': true,
    });

    await batch.commit();
  }

  Future<void> deleteMatchEvent(MatchEvent event) async {
    await _db.runTransaction((txn) async {
      final eventRef = _db.collection('match_events').doc(event.id);
      final matchRef = _db.collection('matches').doc(event.matchId);

      if (event.type == 'goal') {
        final matchDoc = await txn.get(matchRef);
        if (matchDoc.exists) {
          final data = matchDoc.data() ?? const <String, dynamic>{};
          final homeTeamId = (data['homeTeamId'] ?? '').toString();
          final awayTeamId = (data['awayTeamId'] ?? '').toString();
          final scoringTeamId = event.isOwnGoal
              ? (event.teamId == homeTeamId ? awayTeamId : homeTeamId)
              : event.teamId;
          final scoreField = scoringTeamId == homeTeamId
              ? 'homeScore'
              : scoringTeamId == awayTeamId
              ? 'awayScore'
              : null;
          if (scoreField != null) {
            final current = data[scoreField];
            int currentScore;
            if (current is num) {
              currentScore = current.toInt();
            } else if (current is String) {
              currentScore = int.tryParse(current.trim()) ?? 0;
            } else {
              currentScore = 0;
            }
            final next = (currentScore - 1).clamp(0, 9999);
            txn.update(matchRef, {scoreField: next});
          }
        }
      }

      txn.delete(eventRef);
    });
  }

  Future<int> deleteAllMatchesAndEvents() async {
    final deletedEvents = await _deleteCollectionInBatches('match_events');
    final deletedMatches = await _deleteCollectionInBatches('matches');
    return deletedEvents + deletedMatches;
  }

  Future<int> deleteAllTeams() async {
    return _deleteCollectionInBatches('teams');
  }

  Future<int> deleteAllPlayers() async {
    return _deleteCollectionInBatches('players');
  }

  Future<int> _deleteCollectionInBatches(String collectionName) async {
    var deleted = 0;
    while (true) {
      final snap = await _db.collection(collectionName).limit(450).get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      deleted += snap.docs.length;
    }
    return deleted;
  }

  Future<int> seedDummyFixtureOneWeek({int? randomSeed}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final groupsSnap = await _db.collection('groups').get();
    if (groupsSnap.docs.isEmpty) return 0;

    final random = Random(randomSeed);
    var createdMatches = 0;
    final groupsToRecalc = <String>{};
    final ensuredTeams = <String>{};
    final playerCache = <String, List<PlayerModel>>{};

    final flags = <String, bool>{
      'assistGoal': false,
      'yellow': false,
      'secondYellow': false,
      'red': false,
    };

    final allTeamsSnap = await _db.collection('teams').get();
    for (final doc in allTeamsSnap.docs) {
      await _ensureDummyPlayersForTeam(
        random: random,
        teamId: doc.id,
        minCount: 15,
      );
      ensuredTeams.add(doc.id);
    }

    for (final groupDoc in groupsSnap.docs) {
      final groupData = groupDoc.data();
      final leagueId = (groupData['leagueId'] as String?) ?? '';
      if (leagueId.isEmpty) continue;

      final teamsSnap = await _db
          .collection('teams')
          .where('groupId', isEqualTo: groupDoc.id)
          .get();
      if (teamsSnap.docs.length < 2) continue;

      final teams = teamsSnap.docs
          .map((d) => Team.fromMap({...d.data(), 'id': d.id}))
          .where((t) => t.id.isNotEmpty)
          .toList();

      if (teams.length < 2) continue;

      for (final t in teams) {
        playerCache[t.id] ??= await _getPlayersOnce(t.id);
      }

      final rounds = _roundRobinRounds(teams);
      if (rounds.isEmpty) continue;

      final matchCountByTeam = <String, int>{for (final t in teams) t.id: 0};

      final timeSlots = <List<int>>[
        [19, 0],
        [20, 30],
        [22, 0],
      ];
      var matchIndex = 0;
      var roundIndex = 0;

      bool allEnough() {
        for (final t in teams) {
          if ((matchCountByTeam[t.id] ?? 0) < 3) return false;
        }
        return true;
      }

      while (!allEnough() && roundIndex < rounds.length * 3) {
        final round = rounds[roundIndex % rounds.length];
        for (var i = 0; i < round.length; i += 2) {
          final a = round[i];
          final b = round[i + 1];
          if (a == null || b == null) continue;
          if ((matchCountByTeam[a.id] ?? 0) >= 3 &&
              (matchCountByTeam[b.id] ?? 0) >= 3) {
            continue;
          }

          final slot = timeSlots[matchIndex % timeSlots.length];
          final dayBack = (matchIndex ~/ timeSlots.length) + 1;
          final matchDate = DateTime(
            today.year,
            today.month,
            today.day - dayBack,
            slot[0],
            slot[1],
          );
          final matchDateStr =
              "${matchDate.year}-${matchDate.month.toString().padLeft(2, '0')}-${matchDate.day.toString().padLeft(2, '0')}";
          final matchTimeStr =
              "${matchDate.hour.toString().padLeft(2, '0')}:${matchDate.minute.toString().padLeft(2, '0')}";
          matchIndex++;

          final homeIsA = random.nextBool();
          final home = homeIsA ? a : b;
          final away = homeIsA ? b : a;

          final match = MatchModel(
            id: '',
            leagueId: leagueId,
            groupId: groupDoc.id,
            homeTeamId: home.id,
            homeTeamName: home.name,
            homeTeamLogoUrl: home.logoUrl,
            awayTeamId: away.id,
            awayTeamName: away.name,
            awayTeamLogoUrl: away.logoUrl,
            homeScore: 0,
            awayScore: 0,
            matchDate: matchDateStr,
            matchTime: matchTimeStr,
            status: MatchStatus.finished,
            minute: null,
          );

          final matchId = await addMatch(match);
          createdMatches++;

          final homePlayers = (playerCache[home.id] ?? [])
              .where((p) => p.name.trim().isNotEmpty)
              .toList();
          final awayPlayers = (playerCache[away.id] ?? [])
              .where((p) => p.name.trim().isNotEmpty)
              .toList();

          PlayerModel pickScorer(List<PlayerModel> list) {
            if (list.isEmpty) {
              return PlayerModel(id: '', teamId: '', name: 'Oyuncu');
            }
            final nonGk = list.where((p) => p.position != 'Kaleci').toList();
            final pool = nonGk.isEmpty ? list : nonGk;
            return pool[random.nextInt(pool.length)];
          }

          PlayerModel? pickAssist(List<PlayerModel> list, PlayerModel scorer) {
            if (list.length < 2) return null;
            final candidates = list
                .where((p) => p.name != scorer.name)
                .toList();
            if (candidates.isEmpty) return null;
            return candidates[random.nextInt(candidates.length)];
          }

          var homeGoals = random.nextInt(6);
          var awayGoals = random.nextInt(6);
          if (homeGoals == 0 && awayGoals == 0) {
            if (random.nextBool()) {
              homeGoals = 1;
            } else {
              awayGoals = 1;
            }
          }

          for (var g = 0; g < homeGoals; g++) {
            final scorer = pickScorer(homePlayers);
            final withAssist = flags['assistGoal'] == false
                ? true
                : random.nextBool();
            final assist = withAssist ? pickAssist(homePlayers, scorer) : null;
            if (assist != null) flags['assistGoal'] = true;
            await addMatchEvent(
              MatchEvent(
                id: '',
                matchId: matchId,
                tournamentId: leagueId,
                eventType: 'goal',
                teamId: home.id,
                minute: random.nextInt(89) + 1,
                playerName: scorer.name,
                assistPlayerName: assist?.name,
                type: 'goal',
              ),
            );
          }

          for (var g = 0; g < awayGoals; g++) {
            final scorer = pickScorer(awayPlayers);
            final withAssist = flags['assistGoal'] == false
                ? true
                : random.nextBool();
            final assist = withAssist ? pickAssist(awayPlayers, scorer) : null;
            if (assist != null) flags['assistGoal'] = true;
            await addMatchEvent(
              MatchEvent(
                id: '',
                matchId: matchId,
                tournamentId: leagueId,
                eventType: 'goal',
                teamId: away.id,
                minute: random.nextInt(89) + 1,
                playerName: scorer.name,
                assistPlayerName: assist?.name,
                type: 'goal',
              ),
            );
          }

          Future<void> addYellow(String teamId, List<PlayerModel> list) async {
            if (list.isEmpty) return;
            flags['yellow'] = true;
            final p = list[random.nextInt(list.length)];
            await addMatchEvent(
              MatchEvent(
                id: '',
                matchId: matchId,
                tournamentId: leagueId,
                eventType: 'yellow_card',
                teamId: teamId,
                minute: random.nextInt(89) + 1,
                playerName: p.name,
                type: 'yellow_card',
              ),
            );
          }

          Future<void> addSecondYellow(
            String teamId,
            List<PlayerModel> list,
          ) async {
            if (list.isEmpty) return;
            flags['secondYellow'] = true;
            final p = list[random.nextInt(list.length)];
            final m1 = 15 + random.nextInt(30);
            final m2 = 55 + random.nextInt(30);
            await addMatchEvent(
              MatchEvent(
                id: '',
                matchId: matchId,
                tournamentId: leagueId,
                eventType: 'yellow_card',
                teamId: teamId,
                minute: m1,
                playerName: p.name,
                type: 'yellow_card',
              ),
            );
            await addMatchEvent(
              MatchEvent(
                id: '',
                matchId: matchId,
                tournamentId: leagueId,
                eventType: 'yellow_card',
                teamId: teamId,
                minute: m2,
                playerName: p.name,
                type: 'yellow_card',
              ),
            );
          }

          Future<void> addRed(String teamId, List<PlayerModel> list) async {
            if (list.isEmpty) return;
            flags['red'] = true;
            final p = list[random.nextInt(list.length)];
            await addMatchEvent(
              MatchEvent(
                id: '',
                matchId: matchId,
                tournamentId: leagueId,
                eventType: 'red_card',
                teamId: teamId,
                minute: 10 + random.nextInt(80),
                playerName: p.name,
                type: 'red_card',
              ),
            );
          }

          final shouldForce = flags.values.any((v) => v == false);
          if (shouldForce) {
            if (flags['yellow'] == false) {
              await addSecondYellow(home.id, homePlayers);
            }
            if (flags['red'] == false) {
              await addRed(away.id, awayPlayers);
            }
          } else {
            if (random.nextBool()) {
              final useHome = random.nextBool();
              await addYellow(
                useHome ? home.id : away.id,
                useHome ? homePlayers : awayPlayers,
              );
            }
            if (random.nextInt(6) == 0) {
              final useHome = random.nextBool();
              await addSecondYellow(
                useHome ? home.id : away.id,
                useHome ? homePlayers : awayPlayers,
              );
            }
            if (random.nextInt(10) == 0) {
              await addRed(
                random.nextBool() ? home.id : away.id,
                random.nextBool() ? homePlayers : awayPlayers,
              );
            }
          }

          matchCountByTeam[home.id] = (matchCountByTeam[home.id] ?? 0) + 1;
          matchCountByTeam[away.id] = (matchCountByTeam[away.id] ?? 0) + 1;
          groupsToRecalc.add(groupDoc.id);

          if (allEnough()) break;
        }
        roundIndex++;
      }
    }

    for (final gId in groupsToRecalc) {
      await calculateStandings(gId);
    }

    return createdMatches;
  }

  // --- STANDINGS CALCULATION (PUAN DURUMU HESAPLAMA) ---
  Future<void> calculateStandings(String groupId) async {
    // 1. Gruptaki takımları ve bitmiş maçları çek
    final teamsSnap = await _db
        .collection('teams')
        .where('groupId', isEqualTo: groupId)
        .get();
    final matchesSnap = await _db
        .collection('matches')
        .where('groupId', isEqualTo: groupId)
        .where('status', isEqualTo: MatchStatus.finished.name)
        .get();

    final teamStats = <String, Map<String, int>>{};

    for (var doc in teamsSnap.docs) {
      teamStats[doc.id] = {
        'P': 0,
        'G': 0,
        'B': 0,
        'M': 0,
        'AG': 0,
        'YG': 0,
        'AV': 0,
        'Puan': 0,
      };
    }

    for (var doc in matchesSnap.docs) {
      final m = doc.data();
      final hId = (m['homeTeamId'] ?? '').toString();
      final aId = (m['awayTeamId'] ?? '').toString();

      int readScore(dynamic v) {
        if (v == null) return 0;
        if (v is num) return v.toInt();
        final s = v.toString().replaceAll('\u0000', '').trim();
        return int.tryParse(s) ??
            double.tryParse(s.replaceAll(',', '.'))?.toInt() ??
            0;
      }

      final hS = readScore(m['homeScore']);
      final aS = readScore(m['awayScore']);

      if (teamStats[hId] == null || teamStats[aId] == null) continue;

      teamStats[hId]!['P'] = teamStats[hId]!['P']! + 1;
      teamStats[aId]!['P'] = teamStats[aId]!['P']! + 1;
      teamStats[hId]!['AG'] = teamStats[hId]!['AG']! + hS;
      teamStats[hId]!['YG'] = teamStats[hId]!['YG']! + aS;
      teamStats[aId]!['AG'] = teamStats[aId]!['AG']! + aS;
      teamStats[aId]!['YG'] = teamStats[aId]!['YG']! + hS;

      if (hS > aS) {
        teamStats[hId]!['G'] = teamStats[hId]!['G']! + 1;
        teamStats[hId]!['Puan'] = teamStats[hId]!['Puan']! + 3;
        teamStats[aId]!['M'] = teamStats[aId]!['M']! + 1;
      } else if (aS > hS) {
        teamStats[aId]!['G'] = teamStats[aId]!['G']! + 1;
        teamStats[aId]!['Puan'] = teamStats[aId]!['Puan']! + 3;
        teamStats[hId]!['M'] = teamStats[hId]!['M']! + 1;
      } else {
        teamStats[hId]!['B'] = teamStats[hId]!['B']! + 1;
        teamStats[aId]!['B'] = teamStats[aId]!['B']! + 1;
        teamStats[hId]!['Puan'] = teamStats[hId]!['Puan']! + 1;
        teamStats[aId]!['Puan'] = teamStats[aId]!['Puan']! + 1;
      }
    }

    // 2. Veritabanını güncelle
    final batch = _db.batch();
    teamStats.forEach((tId, stats) {
      stats['AV'] = stats['AG']! - stats['YG']!;
      batch.update(_db.collection('teams').doc(tId), {'stats': stats});
    });
    await batch.commit();
  }

  // --- NEWS (HABERLER) ---
  Future<void> addNews({required String tournamentId, required String content}) async {
    final tId = tournamentId.trim();
    if (tId.isEmpty) throw Exception('Turnuva seçilmeden haber eklenemez.');
    await _db.collection('news').add({
      'tournamentId': tId,
      'content': content,
      'isPublished': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setNewsPublished({
    required String newsId,
    required bool isPublished,
  }) async {
    await _db.collection('news').doc(newsId).update({
      'isPublished': isPublished,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateNewsContent({
    required String newsId,
    required String content,
  }) async {
    await _db.collection('news').doc(newsId).update({
      'content': content,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteNews({required String newsId}) async {
    await _db.collection('news').doc(newsId).delete();
  }

  Stream<QuerySnapshot> getNews({
    required String tournamentId,
    bool includeUnpublished = false,
  }) {
    final query = _db
        .collection('news')
        .where('tournamentId', isEqualTo: tournamentId)
        .orderBy('createdAt', descending: true);
    if (includeUnpublished) {
      return query.snapshots();
    }
    return query.snapshots();
  }
}
