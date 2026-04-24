import '../../models/award.dart';
import '../../models/league.dart';
import '../../models/league_extras.dart';
import '../../models/match.dart';

abstract class ILeagueService {
  Stream<List<League>> watchLeagues();

  Stream<League?> watchLeagueById(String leagueId);

  Stream<String> watchLeagueName(String leagueId);

  Future<String> addLeague(League league);

  Future<void> updateLeague(League league);

  Future<void> deleteLeagueCascade(String leagueId);

  Future<void> setDefaultLeague({required String leagueId});

  Future<void> setLeagueDefaultFlag({
    required String leagueId,
    required bool isDefault,
  });

  Stream<List<GroupModel>> watchGroups(String leagueId);

  Future<void> addGroup(GroupModel group);

  Future<void> deleteGroupCascade(String groupId);

  Future<void> setGroupTeams({
    required String groupId,
    required List<String> teamIds,
  });

  Future<List<String>> listPitchesOnce();

  Stream<List<Pitch>> watchPitches();

  Future<void> addPitch({
    required String name,
    String? city,
    String? country,
    String? location,
  });

  Future<void> deletePitch(String pitchId);

  Stream<List<NewsItem>> watchNews({
    required String tournamentId,
    bool includeUnpublished = false,
  });

  Future<void> addNews({required String tournamentId, required String content});

  Future<void> setNewsPublished({
    required String newsId,
    required bool isPublished,
  });

  Future<void> updateNewsContent({
    required String newsId,
    required String content,
  });

  Future<void> deleteNews({required String newsId});

  Stream<List<Award>> watchAwardsForLeague(String leagueId);

  Future<void> addAward({
    required String leagueId,
    required String name,
    String? description,
  });

  Future<void> deleteAward(String awardId);

  Future<String> exportCollectionToJson(String collectionName);

  Future<Map<String, dynamic>> buildFirestoreBackup({
    List<String>? collections,
  });
}
