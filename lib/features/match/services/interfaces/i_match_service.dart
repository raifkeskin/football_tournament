import '../../models/fixture_import.dart';
import '../../models/match.dart';
import '../../models/match_media.dart';
import '../../../player/models/player_stats.dart';

abstract class IMatchService {
  Stream<List<MatchModel>> watchMatchesForLeague(String leagueId);

  Stream<List<MatchModel>> watchMatchesByDate({
    required String leagueId,
    required DateTime date,
  });

  Stream<List<MatchModel>> watchFixtureMatches(
    String leagueId,
    int week, {
    String? groupId,
    String? seasonId,
  });

  Future<int?> getFixtureMaxWeek(String leagueId, {String? groupId});

  Stream<MatchModel> watchMatch(String matchId);

  Stream<List<Map<String, dynamic>>> watchInlineMatchEvents(String matchId);

  Future<String> addMatch(MatchModel match);

  Future<void> addMatchEvent(MatchEvent event);

  Future<void> updateMatchPitchName({
    required String matchId,
    required String? pitchName,
  });

  Future<void> addMatchMedia(MatchMediaModel media);

  Stream<List<MatchMediaModel>> watchMatchMedia(String matchId);

  Future<void> updateMatchSchedule({
    required String matchId,
    required String matchDateDb,
    required String matchTime,
    String? pitchId,
    String? pitchName,
  });

  Future<void> updateMatchLineup({
    required String matchId,
    required bool isHome,
    required MatchLineup lineup,
  });

  Future<void> updateMatchFormationState({
    required String matchId,
    String? homeFormation,
    String? awayFormation,
    List<String>? homeOrder,
    List<String>? awayOrder,
  });

  Future<void> completeMatchWithScoreAndDefaultEvents({
    required String matchId,
    required int homeScore,
    required int awayScore,
  });

  Future<void> insertDefaultMatchEvents(String matchId, int duration);

  Stream<List<MatchRosterModel>> watchMatchRosters(String matchId, String teamId);

  Future<void> updateMatchRoster({
    required String matchId,
    required String leagueId,
    required String seasonId,
    required String teamId,
    required bool isHome,
    required List<MatchRosterModel> rosters,
  });

  Stream<List<PlayerStats>> watchPlayerStats({required String tournamentId});

  Future<void> commitPlayerStatsForCompletedMatch({required String matchId});

  Future<void> importTeamsAndFixture({
    required String tournamentId,
    required List<FixtureImportTeam> teams,
    required List<FixtureImportMatch> matches,
  });

  Future<int> deleteAllMatchesAndEvents();

  Future<Map<String, int>> migrateMatchesTimeTimestampToMatchFields();

  Future<Map<String, int>> normalizeMatchesDocIdsByLeagueWeekHomeTeam();

  // i_match_service.dart içine ekle
  Future<void> deleteMatchMedia(String mediaId);

  Future<bool> hasBroadcast(String matchId);
  Future<String?> getBroadcastUrl(String matchId);
}
