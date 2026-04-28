import '../../../match/models/match.dart';
import '../../../tournament/models/league.dart';
import '../../models/team.dart';

abstract class ITeamService {
  Stream<List<Team>> watchAllTeams({String? caller});

  Stream<List<Map<String, dynamic>>> watchAllTeamsRaw({String? caller});

  Future<String> getTeamName(String teamId, {String? caller});

  Future<Team?> getTeamOnce(String teamId, {String? caller});

  Future<PlayerModel?> getPlayerByPhoneOnce(String playerPhone, {String? caller});

  Stream<String> watchTeamName(String teamId, {String? caller});

  Stream<List<Team>> watchTeamsByGroup(String groupId, {String? caller});

  Stream<List<PlayerModel>> watchPlayers({
    required String teamId,
    String? tournamentId,
    String? caller,
  });

  Stream<List<PlayerModel>> watchAllPlayers({String? caller});

  Future<void> upsertPlayerIdentity({
    required String phone,
    required String name,
    String? nationalId,
    String? birthDate,
    String? mainPosition,
    String? preferredFoot,
    int? height,
    int? weight,
    String? caller,
  });

  Future<void> updatePlayer({
    required String playerId,
    required Map<String, dynamic> data,
    String? caller,
  });

  Future<Map<String, dynamic>?> getPenaltyForPlayer(String playerId, {String? caller});

  Future<void> upsertPenaltyForPlayer({
    required String playerId,
    required String teamId,
    required String penaltyReason,
    required int matchCount,
    String? caller,
  });

  Future<void> clearPenaltyForPlayer({required String playerId, String? caller});

  Future<void> upsertRosterEntry({
    required String tournamentId,
    required String teamId,
    required String playerPhone,
    required String playerName,
    String? jerseyNumber,
    required String role,
    String? caller,
  });

  Future<void> deleteRosterEntry({
    required String tournamentId,
    required String teamId,
    required String playerPhone,
    String? caller,
  });

  Future<bool> isTeamManagerForTournament({
    required String tournamentId,
    required String teamId,
    required String playerPhone,
    String? caller,
  });

  Future<bool> managerExistsForTeamTournament({
    required String tournamentId,
    required String teamId,
    String? excludePlayerPhone,
    String? caller,
  });

  Future<List<League>> getTeamActiveTournaments(String teamId, {String? caller});

  Future<void> updateTeam(String teamId, Map<String, dynamic> data, {String? caller});

  Future<void> deleteTeamCascade(String teamId, {String? caller});

  Future<List<Team>> getTeamsCached(String leagueId, {String? caller});

  Future<Team> addTeamAndUpsertCache({
    required String leagueId,
    required String teamName,
    required String logoUrl,
    String? groupId,
    String? groupName,
    String? caller,
  });

  Future<int> deleteAllTeams({String? caller});

  Future<int> deleteAllPlayers({String? caller});

  Future<void> invalidateTeams(String leagueId, {String? caller});
}
