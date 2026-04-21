import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/match.dart';
import '../models/team.dart';
import 'database_service.dart';
import '../repositories/teams_repository.dart';

class TeamService {
  TeamService({
    DatabaseService? databaseService,
    TeamsRepository? teamsRepository,
    FirebaseFirestore? firestore,
  }) : _db = databaseService ?? DatabaseService(firestore: firestore),
       _teamsRepo = teamsRepository ?? TeamsRepository(firestore: firestore),
       _firestore = firestore ?? FirebaseFirestore.instance;

  final DatabaseService _db;
  final TeamsRepository _teamsRepo;
  final FirebaseFirestore _firestore;

  Stream<List<Team>> watchAllTeams() {
    return _firestore.collection('teams').orderBy('name').snapshots().map((snap) {
      final list =
          snap.docs
              .map((d) => Team.fromMap({...d.data(), 'id': d.id}))
              .toList();
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    });
  }

  Stream<List<Map<String, dynamic>>> watchAllTeamsRaw() {
    return _firestore.collection('teams').orderBy('name').snapshots().map((snap) {
      return snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
    });
  }

  Future<String> getTeamName(String teamId) async {
    final id = teamId.trim();
    if (id.isEmpty) return '-';
    final snap = await _firestore.collection('teams').doc(id).get();
    final data = snap.data();
    return (data?['name'] as String?) ?? id;
  }

  Future<Team?> getTeamOnce(String teamId) async {
    final id = teamId.trim();
    if (id.isEmpty) return null;
    final snap = await _firestore.collection('teams').doc(id).get();
    final data = snap.data();
    if (data == null) return null;
    return Team.fromMap({...data, 'id': snap.id});
  }

  Future<PlayerModel?> getPlayerByPhoneOnce(String playerPhone) async {
    final phone = playerPhone.trim();
    if (phone.isEmpty) return null;
    final snap = await _firestore.collection('players').doc(phone).get();
    final data = snap.data();
    if (data == null) return null;
    return PlayerModel.fromMap(data, snap.id);
  }

  Stream<String> watchTeamName(String teamId) {
    final id = teamId.trim();
    if (id.isEmpty) return const Stream<String>.empty();
    return _firestore.collection('teams').doc(id).snapshots().map((snap) {
      final data = snap.data();
      final name = (data?['name'] ?? '').toString().trim();
      return name.isEmpty ? id : name;
    });
  }

  Stream<List<PlayerModel>> watchPlayers({
    required String teamId,
    String? tournamentId,
  }) {
    return _db.getPlayers(teamId, tournamentId: tournamentId);
  }

  Future<void> upsertPlayerIdentity({
    required String phone,
    required String name,
    String? birthDate,
    String? mainPosition,
  }) {
    return _db.upsertPlayerIdentity(
      phone: phone,
      name: name,
      birthDate: birthDate,
      mainPosition: mainPosition,
    );
  }

  Future<void> upsertRosterEntry({
    required String tournamentId,
    required String teamId,
    required String playerPhone,
    required String playerName,
    String? jerseyNumber,
    required String role,
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

  Future<bool> isTeamManagerForTournament({
    required String tournamentId,
    required String teamId,
    required String playerPhone,
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

  Future<bool> managerExistsForTeamTournament({
    required String tournamentId,
    required String teamId,
    String? excludePlayerPhone,
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

  Future<List<Team>> getTeamsCached(String leagueId) => _teamsRepo.getTeamsCached(leagueId);
  Future<Team> addTeamAndUpsertCache({
    required String leagueId,
    required String teamName,
    required String logoUrl,
    String? groupId,
    String? groupName,
  }) => _teamsRepo.addTeamAndUpsertCache(
    leagueId: leagueId,
    teamName: teamName,
    logoUrl: logoUrl,
    groupId: groupId,
    groupName: groupName,
  );
  Future<void> invalidateTeams(String leagueId) => _teamsRepo.invalidateTeams(leagueId);
}
