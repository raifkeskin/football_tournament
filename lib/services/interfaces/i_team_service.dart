import '../../models/match.dart';
import '../../models/team.dart';

abstract class ITeamService {
  Stream<List<Team>> watchAllTeams();

  Stream<List<Map<String, dynamic>>> watchAllTeamsRaw();

  Future<String> getTeamName(String teamId);

  Future<Team?> getTeamOnce(String teamId);

  Future<PlayerModel?> getPlayerByPhoneOnce(String playerPhone);

  Stream<String> watchTeamName(String teamId);

  Stream<List<PlayerModel>> watchPlayers({
    required String teamId,
    String? tournamentId,
  });

  Future<void> upsertPlayerIdentity({
    required String phone,
    required String name,
    String? birthDate,
    String? mainPosition,
  });

  Future<void> upsertRosterEntry({
    required String tournamentId,
    required String teamId,
    required String playerPhone,
    required String playerName,
    String? jerseyNumber,
    required String role,
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

  Future<List<Team>> getTeamsCached(String leagueId);

  Future<Team> addTeamAndUpsertCache({
    required String leagueId,
    required String teamName,
    required String logoUrl,
    String? groupId,
    String? groupName,
  });

  Future<void> invalidateTeams(String leagueId);
}
