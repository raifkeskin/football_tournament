import '../../models/match.dart';
import '../../models/league.dart';
import '../../models/team.dart';

abstract class ITeamService {
  Stream<List<Team>> watchAllTeams();

  Stream<List<Map<String, dynamic>>> watchAllTeamsRaw();

  Future<String> getTeamName(String teamId);

  Future<Team?> getTeamOnce(String teamId);

  Future<PlayerModel?> getPlayerByPhoneOnce(String playerPhone);

  Stream<String> watchTeamName(String teamId);

  Stream<List<Team>> watchTeamsByGroup(String groupId);

  Stream<List<PlayerModel>> watchPlayers({
    required String teamId,
    String? tournamentId,
  });

  Stream<List<PlayerModel>> watchAllPlayers();

  Future<void> upsertPlayerIdentity({
    required String phone,
    required String name,
    String? birthDate,
    String? mainPosition,
  });

  Future<void> updatePlayer({
    required String playerId,
    required Map<String, dynamic> data,
  });

  Future<Map<String, dynamic>?> getPenaltyForPlayer(String playerId);

  Future<void> upsertPenaltyForPlayer({
    required String playerId,
    required String teamId,
    required String penaltyReason,
    required int matchCount,
  });

  Future<void> clearPenaltyForPlayer({required String playerId});

  Future<void> upsertRosterEntry({
    required String tournamentId,
    required String teamId,
    required String playerPhone,
    required String playerName,
    String? jerseyNumber,
    required String role,
  });

  Future<void> deleteRosterEntry({
    required String tournamentId,
    required String teamId,
    required String playerPhone,
  });

  Future<bool> isTeamManagerForTournament({
    required String tournamentId,
    required String teamId,
    required String playerPhone,
  });

  Future<bool> managerExistsForTeamTournament({
    required String tournamentId,
    required String teamId,
    String? excludePlayerPhone,
  });

  Future<List<League>> getTeamActiveTournaments(String teamId);

  Future<void> updateTeam(String teamId, Map<String, dynamic> data);

  Future<void> deleteTeamCascade(String teamId);

  Future<List<Team>> getTeamsCached(String leagueId);

  Future<Team> addTeamAndUpsertCache({
    required String leagueId,
    required String teamName,
    required String logoUrl,
    String? groupId,
    String? groupName,
  });

  Future<int> deleteAllTeams();

  Future<int> deleteAllPlayers();

  Future<void> invalidateTeams(String leagueId);
}
