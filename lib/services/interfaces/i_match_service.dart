import '../../models/fixture_import.dart';
import '../../models/match.dart';
import '../../models/player_stats.dart';

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
  });

  Future<int?> getFixtureMaxWeek(String leagueId, {String? groupId});

  Stream<MatchModel> watchMatch(String matchId);

  Stream<List<Map<String, dynamic>>> watchInlineMatchEvents(String matchId);

  Future<void> updateMatchYoutubeUrl({
    required String matchId,
    required String? youtubeUrl,
  });

  Future<void> updateMatchPitchName({
    required String matchId,
    required String? pitchName,
  });

  Future<void> updateMatchSchedule({
    required String matchId,
    required String matchDateDb,
    required String matchTime,
    required String? pitchName,
  });

  Future<void> completeMatchWithScoreAndDefaultEvents({
    required String matchId,
    required int homeScore,
    required int awayScore,
  });

  Stream<List<PlayerStats>> watchPlayerStats({required String tournamentId});

  Future<void> commitPlayerStatsForCompletedMatch({required String matchId});

  Future<void> importTeamsAndFixture({
    required String tournamentId,
    required List<FixtureImportTeam> teams,
    required List<FixtureImportMatch> matches,
  });
}
