import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/league.dart';
import '../../models/match.dart';
import '../../models/team.dart';
import 'database_service.dart';
import '../../repositories/teams_repository.dart';
import '../interfaces/i_team_service.dart';

class FirebaseTeamService implements ITeamService {
  FirebaseTeamService({
    DatabaseService? databaseService,
    TeamsRepository? teamsRepository,
    FirebaseFirestore? firestore,
  }) : _db = databaseService ?? DatabaseService(firestore: firestore),
       _teamsRepo = teamsRepository ?? TeamsRepository(firestore: firestore),
       _firestore = firestore ?? FirebaseFirestore.instance;

  final DatabaseService _db;
  final TeamsRepository _teamsRepo;
  final FirebaseFirestore _firestore;

  @override
  Stream<List<Team>> watchAllTeams({String? caller}) {
    return _firestore.collection('teams').orderBy('name').snapshots().map((snap) {
      final list =
          snap.docs
              .map((d) => Team.fromMap({...d.data(), 'id': d.id}))
              .toList();
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    });
  }

  @override
  Stream<List<Map<String, dynamic>>> watchAllTeamsRaw({String? caller}) {
    return _firestore.collection('teams').orderBy('name').snapshots().map((snap) {
      return snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
    });
  }

  @override
  Future<String> getTeamName(String teamId, {String? caller}) async {
    final id = teamId.trim();
    if (id.isEmpty) return '-';
    final snap = await _firestore.collection('teams').doc(id).get();
    final data = snap.data();
    return (data?['name'] as String?) ?? id;
  }

  @override
  Future<Team?> getTeamOnce(String teamId, {String? caller}) async {
    final id = teamId.trim();
    if (id.isEmpty) return null;
    final snap = await _firestore.collection('teams').doc(id).get();
    final data = snap.data();
    if (data == null) return null;
    return Team.fromMap({...data, 'id': snap.id});
  }

  @override
  Future<PlayerModel?> getPlayerByPhoneOnce(String playerPhone, {String? caller}) async {
    final phone = playerPhone.trim();
    if (phone.isEmpty) return null;
    final snap = await _firestore.collection('players').doc(phone).get();
    final data = snap.data();
    if (data == null) return null;
    return PlayerModel.fromMap(data, snap.id);
  }

  @override
  Stream<String> watchTeamName(String teamId, {String? caller}) {
    final id = teamId.trim();
    if (id.isEmpty) return const Stream<String>.empty();
    return _firestore.collection('teams').doc(id).snapshots().map((snap) {
      final data = snap.data();
      final name = (data?['name'] ?? '').toString().trim();
      return name.isEmpty ? id : name;
    });
  }

  @override
  Stream<List<Team>> watchTeamsByGroup(String groupId, {String? caller}) {
    return _db.getTeamsByGroup(groupId);
  }

  @override
  Stream<List<PlayerModel>> watchPlayers({
    required String teamId,
    String? tournamentId,
    String? caller,
  }) {
    return _db.getPlayers(teamId, tournamentId: tournamentId);
  }

  @override
  Stream<List<PlayerModel>> watchAllPlayers({String? caller}) {
    return _db.watchAllPlayers();
  }

  @override
  Future<void> upsertPlayerIdentity({
    required String phone,
    required String name,
    String? birthDate,
    String? mainPosition,
    String? caller,
  }) {
    return _db.upsertPlayerIdentity(
      phone: phone,
      name: name,
      birthDate: birthDate,
      mainPosition: mainPosition,
    );
  }

  @override
  Future<void> updatePlayer({
    required String playerId,
    required Map<String, dynamic> data,
    String? caller,
  }) {
    return _db.updatePlayer(playerId: playerId, data: data);
  }

  @override
  Future<Map<String, dynamic>?> getPenaltyForPlayer(String playerId, {String? caller}) {
    return _db.getPenaltyForPlayer(playerId);
  }

  @override
  Future<void> upsertPenaltyForPlayer({
    required String playerId,
    required String teamId,
    required String penaltyReason,
    required int matchCount,
    String? caller,
  }) {
    return _db.upsertPenaltyForPlayer(
      playerId: playerId,
      teamId: teamId,
      penaltyReason: penaltyReason,
      matchCount: matchCount,
    );
  }

  @override
  Future<void> clearPenaltyForPlayer({required String playerId, String? caller}) {
    return _db.clearPenaltyForPlayer(playerId: playerId);
  }

  @override
  Future<void> upsertRosterEntry({
    required String tournamentId,
    required String teamId,
    required String playerPhone,
    required String playerName,
    String? jerseyNumber,
    required String role,
    String? caller,
  }) {
    return _db.upsertRosterEntry(
      tournamentId: tournamentId,
      teamId: teamId,
      playerPhone: playerPhone,
      playerName: playerName,
      jerseyNumber: jerseyNumber,
      role: role,
    );
  }

  @override
  Future<void> deleteRosterEntry({
    required String tournamentId,
    required String teamId,
    required String playerPhone,
    String? caller,
  }) async {
    final t = tournamentId.trim();
    final team = teamId.trim();
    final phone = playerPhone.trim();
    if (t.isEmpty || team.isEmpty || phone.isEmpty) return;
    final id = '${phone}_${t}_$team';
    try {
      await _firestore.collection('rosters').doc(id).delete();
    } catch (_) {}
  }

  @override
  Future<bool> isTeamManagerForTournament({
    required String tournamentId,
    required String teamId,
    required String playerPhone,
    String? caller,
  }) async {
    final t = tournamentId.trim();
    final team = teamId.trim();
    final phone = playerPhone.trim();
    if (t.isEmpty || team.isEmpty || phone.isEmpty) return false;

    final snap = await _firestore
        .collection('rosters')
        .where('tournamentId', isEqualTo: t)
        .where('teamId', isEqualTo: team)
        .where('playerPhone', isEqualTo: phone)
        .get();
    return snap.docs.any((doc) {
      final role = (doc.data()['role'] ?? '').toString().trim();
      return role == 'Takım Sorumlusu' || role == 'Her İkisi';
    });
  }

  @override
  Future<bool> managerExistsForTeamTournament({
    required String tournamentId,
    required String teamId,
    String? excludePlayerPhone,
    String? caller,
  }) async {
    final t = tournamentId.trim();
    final team = teamId.trim();
    if (t.isEmpty || team.isEmpty) return false;
    final snap = await _firestore
        .collection('rosters')
        .where('tournamentId', isEqualTo: t)
        .where('teamId', isEqualTo: team)
        .get();

    final exclude = excludePlayerPhone?.trim();
    for (final d in snap.docs) {
      final phone = (d.data()['playerPhone'] ?? '').toString().trim();
      if (exclude != null && exclude.isNotEmpty && phone == exclude) continue;
      final role = (d.data()['role'] ?? '').toString().trim();
      final resolvedRole = role.isEmpty ? 'Futbolcu' : role;
      if (_isManagerRole(resolvedRole)) return true;
    }
    return false;
  }

  bool _isManagerRole(String role) {
    final r = role.trim();
    return r == 'Takım Sorumlusu' || r == 'Her İkisi';
  }

  @override
  Future<List<League>> getTeamActiveTournaments(String teamId, {String? caller}) {
    return _db.getTeamActiveTournaments(teamId);
  }

  @override
  Future<void> updateTeam(String teamId, Map<String, dynamic> data, {String? caller}) {
    return _db.updateTeam(teamId, data);
  }

  @override
  Future<void> deleteTeamCascade(String teamId, {String? caller}) {
    return _db.deleteTeamCascade(teamId);
  }

  @override
  Future<List<Team>> getTeamsCached(String leagueId, {String? caller}) =>
      _teamsRepo.getTeamsCached(leagueId);

  @override
  Future<Team> addTeamAndUpsertCache({
    required String leagueId,
    required String teamName,
    required String logoUrl,
    String? groupId,
    String? groupName,
    String? caller,
  }) => _teamsRepo.addTeamAndUpsertCache(
        leagueId: leagueId,
        teamName: teamName,
        logoUrl: logoUrl,
        groupId: groupId,
        groupName: groupName,
      );

  @override
  Future<int> deleteAllTeams({String? caller}) => _db.deleteAllTeams();

  @override
  Future<int> deleteAllPlayers({String? caller}) => _db.deleteAllPlayers();

  @override
  Future<void> invalidateTeams(String leagueId, {String? caller}) =>
      _teamsRepo.invalidateTeams(leagueId);
}
