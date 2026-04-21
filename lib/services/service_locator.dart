import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

import '../config/app_config.dart';
import '../models/auth_models.dart';
import '../models/fixture_import.dart';
import '../models/league.dart';
import '../models/league_extras.dart';
import '../models/match.dart';
import '../models/player_stats.dart';
import '../models/team.dart';
import 'auth_service.dart';
import 'interfaces/i_auth_service.dart';
import 'interfaces/i_league_service.dart';
import 'interfaces/i_match_service.dart';
import 'interfaces/i_team_service.dart';
import 'league_service.dart';
import 'match_service.dart';
import 'supabase/supabase_auth_service.dart';
import 'supabase/supabase_league_service.dart';
import 'supabase/supabase_match_service.dart';
import 'supabase/supabase_team_service.dart';
import 'team_service.dart';

class ServiceLocator {
  static final IAuthService authService = _DualWriteAuthService(
    firebase: FirebaseAuthService(),
    supabase: SupabaseAuthService(),
  );

  static final ILeagueService leagueService = _DualWriteLeagueService(
    firebase: FirebaseLeagueService(),
    supabase: SupabaseLeagueService(),
    readDatabase: AppConfig.activeDatabase,
  );

  static final IMatchService matchService = _DualWriteMatchService(
    firebase: FirebaseMatchService(),
    supabase: SupabaseMatchService(),
    supabaseTeamService: SupabaseTeamService(),
    readDatabase: AppConfig.activeDatabase,
  );

  static final ITeamService teamService = _DualWriteTeamService(
    firebase: FirebaseTeamService(),
    supabase: SupabaseTeamService(),
    readDatabase: AppConfig.activeDatabase,
  );
}

class _DualWriteLeagueService implements ILeagueService {
  _DualWriteLeagueService({
    required this.firebase,
    required this.supabase,
    required this.readDatabase,
  });

  final ILeagueService firebase;
  final ILeagueService supabase;
  final DatabaseType readDatabase;

  ILeagueService get _reader => readDatabase == DatabaseType.supabase ? supabase : firebase;

  @override
  Stream<List<League>> watchLeagues() => _reader.watchLeagues();

  @override
  Stream<League?> watchLeagueById(String leagueId) => _reader.watchLeagueById(leagueId);

  @override
  Stream<String> watchLeagueName(String leagueId) => _reader.watchLeagueName(leagueId);

  @override
  Future<String> addLeague(League league) async {
    final id = await firebase.addLeague(league);
    await supabase.updateLeague(league.copyWith(id: id));
    return id;
  }

  @override
  Future<void> updateLeague(League league) async {
    await firebase.updateLeague(league);
    await supabase.updateLeague(league);
  }

  @override
  Future<void> deleteLeagueCascade(String leagueId) async {
    await firebase.deleteLeagueCascade(leagueId);
    await supabase.deleteLeagueCascade(leagueId);
  }

  @override
  Future<void> setDefaultLeague({required String leagueId}) async {
    await firebase.setDefaultLeague(leagueId: leagueId);
    await supabase.setDefaultLeague(leagueId: leagueId);
  }

  @override
  Future<void> setLeagueDefaultFlag({
    required String leagueId,
    required bool isDefault,
  }) async {
    await firebase.setLeagueDefaultFlag(leagueId: leagueId, isDefault: isDefault);
    await supabase.setLeagueDefaultFlag(leagueId: leagueId, isDefault: isDefault);
  }

  @override
  Stream<List<GroupModel>> watchGroups(String leagueId) => _reader.watchGroups(leagueId);

  @override
  Future<void> addGroup(GroupModel group) async {
    await firebase.addGroup(group);
    await supabase.addGroup(group);
  }

  @override
  Future<void> deleteGroupCascade(String groupId) async {
    await firebase.deleteGroupCascade(groupId);
    await supabase.deleteGroupCascade(groupId);
  }

  @override
  Future<void> setGroupTeams({
    required String groupId,
    required List<String> teamIds,
  }) async {
    await firebase.setGroupTeams(groupId: groupId, teamIds: teamIds);
    await supabase.setGroupTeams(groupId: groupId, teamIds: teamIds);
  }

  @override
  Future<List<String>> listPitchesOnce() => _reader.listPitchesOnce();

  @override
  Stream<List<Pitch>> watchPitches() => _reader.watchPitches();

  @override
  Future<void> addPitch({required String name, String? location}) async {
    await firebase.addPitch(name: name, location: location);
    await supabase.addPitch(name: name, location: location);
  }

  @override
  Future<void> deletePitch(String pitchId) async {
    await firebase.deletePitch(pitchId);
    await supabase.deletePitch(pitchId);
  }

  @override
  Stream<List<NewsItem>> watchNews({
    required String tournamentId,
    bool includeUnpublished = false,
  }) => _reader.watchNews(tournamentId: tournamentId, includeUnpublished: includeUnpublished);

  @override
  Future<String> exportCollectionToJson(String collectionName) =>
      _reader.exportCollectionToJson(collectionName);

  @override
  Future<Map<String, dynamic>> buildFirestoreBackup({List<String>? collections}) =>
      _reader.buildFirestoreBackup(collections: collections);
}

class _DualWriteMatchService implements IMatchService {
  _DualWriteMatchService({
    required this.firebase,
    required this.supabase,
    required ITeamService supabaseTeamService,
    required this.readDatabase,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _supabaseTeamService = supabaseTeamService;

  final IMatchService firebase;
  final IMatchService supabase;
  final DatabaseType readDatabase;
  final FirebaseFirestore _firestore;
  final ITeamService _supabaseTeamService;

  IMatchService get _reader => readDatabase == DatabaseType.supabase ? supabase : firebase;

  @override
  Stream<List<MatchModel>> watchMatchesForLeague(String leagueId) =>
      _reader.watchMatchesForLeague(leagueId);

  @override
  Stream<List<MatchModel>> watchMatchesByDate({
    required String leagueId,
    required DateTime date,
  }) => _reader.watchMatchesByDate(leagueId: leagueId, date: date);

  @override
  Stream<List<MatchModel>> watchFixtureMatches(String leagueId, int week, {String? groupId}) =>
      _reader.watchFixtureMatches(leagueId, week, groupId: groupId);

  @override
  Future<int?> getFixtureMaxWeek(String leagueId, {String? groupId}) =>
      _reader.getFixtureMaxWeek(leagueId, groupId: groupId);

  @override
  Stream<MatchModel> watchMatch(String matchId) => _reader.watchMatch(matchId);

  @override
  Stream<List<Map<String, dynamic>>> watchInlineMatchEvents(String matchId) =>
      _reader.watchInlineMatchEvents(matchId);

  @override
  Future<void> updateMatchYoutubeUrl({required String matchId, required String? youtubeUrl}) async {
    await firebase.updateMatchYoutubeUrl(matchId: matchId, youtubeUrl: youtubeUrl);
    await supabase.updateMatchYoutubeUrl(matchId: matchId, youtubeUrl: youtubeUrl);
  }

  @override
  Future<void> updateMatchPitchName({required String matchId, required String? pitchName}) async {
    await firebase.updateMatchPitchName(matchId: matchId, pitchName: pitchName);
    await supabase.updateMatchPitchName(matchId: matchId, pitchName: pitchName);
  }

  @override
  Future<void> updateMatchSchedule({
    required String matchId,
    required String matchDateDb,
    required String matchTime,
    required String? pitchName,
  }) async {
    await firebase.updateMatchSchedule(
      matchId: matchId,
      matchDateDb: matchDateDb,
      matchTime: matchTime,
      pitchName: pitchName,
    );
    await supabase.updateMatchSchedule(
      matchId: matchId,
      matchDateDb: matchDateDb,
      matchTime: matchTime,
      pitchName: pitchName,
    );
  }

  @override
  Future<void> completeMatchWithScoreAndDefaultEvents({
    required String matchId,
    required int homeScore,
    required int awayScore,
  }) async {
    await firebase.completeMatchWithScoreAndDefaultEvents(
      matchId: matchId,
      homeScore: homeScore,
      awayScore: awayScore,
    );
    await supabase.completeMatchWithScoreAndDefaultEvents(
      matchId: matchId,
      homeScore: homeScore,
      awayScore: awayScore,
    );
  }

  @override
  Stream<List<PlayerStats>> watchPlayerStats({required String tournamentId}) =>
      _reader.watchPlayerStats(tournamentId: tournamentId);

  @override
  Future<void> commitPlayerStatsForCompletedMatch({required String matchId}) async {
    await firebase.commitPlayerStatsForCompletedMatch(matchId: matchId);
    await supabase.commitPlayerStatsForCompletedMatch(matchId: matchId);
  }

  @override
  Future<void> importTeamsAndFixture({
    required String tournamentId,
    required List<FixtureImportTeam> teams,
    required List<FixtureImportMatch> matches,
  }) async {
    await firebase.importTeamsAndFixture(
      tournamentId: tournamentId,
      teams: teams,
      matches: matches,
    );
    await _syncTournamentMatchesAndTeamsFromFirebaseToSupabase(tournamentId: tournamentId);
  }

  Future<void> _syncTournamentMatchesAndTeamsFromFirebaseToSupabase({
    required String tournamentId,
  }) async {
    final tId = tournamentId.trim();
    if (tId.isEmpty) return;

    final matchesSnap =
        await _firestore.collection('matches').where('tournamentId', isEqualTo: tId).get();
    final matchDocs = matchesSnap.docs;
    if (matchDocs.isEmpty) return;

    final matchModels = matchDocs.map((d) => MatchModel.fromMap(d.data(), d.id)).toList();
    for (final m in matchModels) {
      await supabase.updateMatchSchedule(
        matchId: m.id,
        matchDateDb: (m.matchDate ?? '').trim(),
        matchTime: (m.matchTime ?? '').trim(),
        pitchName: m.pitchName,
      );
    }

    final teamIds = <String>{};
    for (final m in matchModels) {
      final h = m.homeTeamId.trim();
      final a = m.awayTeamId.trim();
      if (h.isNotEmpty) teamIds.add(h);
      if (a.isNotEmpty) teamIds.add(a);
    }
    if (teamIds.isEmpty) return;

    for (final teamId in teamIds) {
      final snap = await _firestore.collection('teams').doc(teamId).get();
      final data = snap.data();
      if (data == null) continue;
      final team = Team.fromMap({...data, 'id': snap.id, 'tournamentId': tId});
      await _supabaseTeamService.addTeamAndUpsertCache(
        leagueId: tId,
        teamName: team.name,
        logoUrl: team.logoUrl,
      );
    }
  }
}

class _DualWriteTeamService implements ITeamService {
  _DualWriteTeamService({
    required this.firebase,
    required this.supabase,
    required this.readDatabase,
  });

  final ITeamService firebase;
  final ITeamService supabase;
  final DatabaseType readDatabase;

  ITeamService get _reader => readDatabase == DatabaseType.supabase ? supabase : firebase;

  @override
  Stream<List<Team>> watchAllTeams() => _reader.watchAllTeams();

  @override
  Stream<List<Map<String, dynamic>>> watchAllTeamsRaw() => _reader.watchAllTeamsRaw();

  @override
  Future<String> getTeamName(String teamId) => _reader.getTeamName(teamId);

  @override
  Future<Team?> getTeamOnce(String teamId) => _reader.getTeamOnce(teamId);

  @override
  Future<PlayerModel?> getPlayerByPhoneOnce(String playerPhone) =>
      _reader.getPlayerByPhoneOnce(playerPhone);

  @override
  Stream<String> watchTeamName(String teamId) => _reader.watchTeamName(teamId);

  @override
  Stream<List<PlayerModel>> watchPlayers({required String teamId, String? tournamentId}) =>
      _reader.watchPlayers(teamId: teamId, tournamentId: tournamentId);

  @override
  Future<void> upsertPlayerIdentity({
    required String phone,
    required String name,
    String? birthDate,
    String? mainPosition,
  }) async {
    await firebase.upsertPlayerIdentity(
      phone: phone,
      name: name,
      birthDate: birthDate,
      mainPosition: mainPosition,
    );
    await supabase.upsertPlayerIdentity(
      phone: phone,
      name: name,
      birthDate: birthDate,
      mainPosition: mainPosition,
    );
  }

  @override
  Future<void> upsertRosterEntry({
    required String tournamentId,
    required String teamId,
    required String playerPhone,
    required String playerName,
    String? jerseyNumber,
    required String role,
  }) async {
    await firebase.upsertRosterEntry(
      tournamentId: tournamentId,
      teamId: teamId,
      playerPhone: playerPhone,
      playerName: playerName,
      jerseyNumber: jerseyNumber,
      role: role,
    );
    await supabase.upsertRosterEntry(
      tournamentId: tournamentId,
      teamId: teamId,
      playerPhone: playerPhone,
      playerName: playerName,
      jerseyNumber: jerseyNumber,
      role: role,
    );
  }

  @override
  Future<bool> isTeamManagerForTournament({
    required String tournamentId,
    required String teamId,
    required String playerPhone,
  }) => _reader.isTeamManagerForTournament(
    tournamentId: tournamentId,
    teamId: teamId,
    playerPhone: playerPhone,
  );

  @override
  Future<bool> managerExistsForTeamTournament({
    required String tournamentId,
    required String teamId,
    String? excludePlayerPhone,
  }) => _reader.managerExistsForTeamTournament(
    tournamentId: tournamentId,
    teamId: teamId,
    excludePlayerPhone: excludePlayerPhone,
  );

  @override
  Future<List<Team>> getTeamsCached(String leagueId) => _reader.getTeamsCached(leagueId);

  @override
  Future<Team> addTeamAndUpsertCache({
    required String leagueId,
    required String teamName,
    required String logoUrl,
    String? groupId,
    String? groupName,
  }) async {
    final team = await firebase.addTeamAndUpsertCache(
      leagueId: leagueId,
      teamName: teamName,
      logoUrl: logoUrl,
      groupId: groupId,
      groupName: groupName,
    );
    await supabase.addTeamAndUpsertCache(
      leagueId: leagueId,
      teamName: teamName,
      logoUrl: logoUrl,
      groupId: groupId,
      groupName: groupName,
    );
    return team;
  }

  @override
  Future<void> invalidateTeams(String leagueId) => _reader.invalidateTeams(leagueId);
}

class _DualWriteAuthService implements IAuthService {
  _DualWriteAuthService({required this.firebase, required this.supabase});

  final IAuthService firebase;
  final IAuthService supabase;

  @override
  Future<ConfirmationResult> startPhoneAuthWeb({required String phoneNumber}) =>
      firebase.startPhoneAuthWeb(phoneNumber: phoneNumber);

  @override
  Stream<UserDoc?> watchUserDoc(String uid) => firebase.watchUserDoc(uid);

  @override
  Stream<List<RosterAssignment>> watchRosterAssignmentsByPhone(String phone) =>
      firebase.watchRosterAssignmentsByPhone(phone);

  @override
  Future<void> createOtpRequest({
    required String phoneRaw10,
    required String code,
    required DateTime expiresAt,
  }) async {
    await firebase.createOtpRequest(phoneRaw10: phoneRaw10, code: code, expiresAt: expiresAt);
    await supabase.createOtpRequest(phoneRaw10: phoneRaw10, code: code, expiresAt: expiresAt);
  }

  @override
  Future<OtpRequest?> getOtpRequest(String phoneRaw10) => firebase.getOtpRequest(phoneRaw10);

  @override
  Future<void> deleteOtpRequest(String phoneRaw10) async {
    await firebase.deleteOtpRequest(phoneRaw10);
    await supabase.deleteOtpRequest(phoneRaw10);
  }

  @override
  Stream<List<OtpCodeEntry>> watchOtpCodes({bool includeVerified = false}) {
    final controller = StreamController<List<OtpCodeEntry>>.broadcast();
    List<OtpCodeEntry> f = const [];
    List<OtpCodeEntry> s = const [];

    void emit() {
      final merged = <String, OtpCodeEntry>{};
      for (final e in f) {
        merged['f_${e.id}'] = e;
      }
      for (final e in s) {
        merged['s_${e.id}'] = e;
      }
      final list = merged.values.toList()
        ..sort((a, b) {
          final aa = a.createdAt?.millisecondsSinceEpoch ?? 0;
          final bb = b.createdAt?.millisecondsSinceEpoch ?? 0;
          return bb.compareTo(aa);
        });
      controller.add(list);
    }

    late final StreamSubscription subF;
    late final StreamSubscription subS;

    controller.onListen = () {
      subF = firebase.watchOtpCodes(includeVerified: includeVerified).listen((list) {
        f = list;
        emit();
      });
      subS = supabase.watchOtpCodes(includeVerified: includeVerified).listen((list) {
        s = list;
        emit();
      });
    };
    controller.onCancel = () async {
      await subF.cancel();
      await subS.cancel();
      await controller.close();
    };
    return controller.stream;
  }

  @override
  Future<ProfileLookupResult> lookupProfileByPhoneRaw10(String phoneRaw10) =>
      firebase.lookupProfileByPhoneRaw10(phoneRaw10);

  @override
  Future<OnlineRegistrationResult> registerOnlineUser({
    required String phoneRaw10,
    required String password,
    required bool profileFound,
    required String resolvedRole,
    required String? resolvedTeamId,
    required String? resolvedTournamentId,
    required String? matchedPlayerId,
    required List<String> matchedTournamentIds,
    required String? selectedTournamentId,
    required String? name,
    required String? surname,
  }) async {
    final result = await firebase.registerOnlineUser(
      phoneRaw10: phoneRaw10,
      password: password,
      profileFound: profileFound,
      resolvedRole: resolvedRole,
      resolvedTeamId: resolvedTeamId,
      resolvedTournamentId: resolvedTournamentId,
      matchedPlayerId: matchedPlayerId,
      matchedTournamentIds: matchedTournamentIds,
      selectedTournamentId: selectedTournamentId,
      name: name,
      surname: surname,
    );
    await supabase.registerOnlineUser(
      phoneRaw10: phoneRaw10,
      password: password,
      profileFound: profileFound,
      resolvedRole: resolvedRole,
      resolvedTeamId: resolvedTeamId,
      resolvedTournamentId: resolvedTournamentId,
      matchedPlayerId: matchedPlayerId,
      matchedTournamentIds: matchedTournamentIds,
      selectedTournamentId: selectedTournamentId,
      name: name,
      surname: surname,
    );
    return result;
  }
}
