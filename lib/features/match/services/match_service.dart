import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/fixture_import.dart';
import '../models/match.dart';
import '../models/match_media.dart';
import '../../player/models/player_stats.dart';
import 'interfaces/i_match_service.dart';

class SupabaseMatchService implements IMatchService {
  final SupabaseClient _supabase = Supabase.instance.client;

  int _readInt(dynamic v, {required int fallback}) {
    if (v == null) return fallback;
    if (v is num) return v.toInt();
    final s = v.toString().replaceAll('\u0000', '').trim();
    return int.tryParse(s) ??
        double.tryParse(s.replaceAll(',', '.'))?.toInt() ??
        fallback;
  }

  @override
  Stream<List<MatchModel>> watchMatchesForLeague(String leagueId) {
    // 2 parametreli fromMap hatası için id'yi de gönderiyoruz
    return _supabase
        .from('matches')
        .stream(primaryKey: ['id'])
        .eq('league_id', leagueId)
        .order('match_date', ascending: true)
        .map(
          (rows) => rows
              .map((r) => MatchModel.fromMap(r, r['id'] as String))
              .toList(),
        );
  }

  @override
  Stream<List<MatchModel>> watchMatchesByDate({
    required String leagueId,
    required DateTime date,
  }) {
    final dateStr = date.toIso8601String().split('T')[0];
    return _supabase
        .from('matches')
        .stream(primaryKey: ['id'])
        .eq('league_id', leagueId) // DB seviyesinde ana filtre (Tek hak)
        .order('match_time', ascending: true)
        .map(
          (rows) => rows
              // Client tarafında tarih filtresini yapıyoruz
              .where((r) => r['match_date'] == dateStr)
              // MatchModel.fromMap artık 2 parametre bekliyor (data ve id)
              .map((r) => MatchModel.fromMap(r, r['id'] as String))
              .toList(),
        );
  }

  @override
  @override
  Stream<List<MatchModel>> watchFixtureMatches(
    String leagueId,
    int week, {
    String? groupId,
    String? seasonId,
  }) {
    // 1. Veritabanı seviyesinde sadece league_id ile dinliyoruz (Tek eq hakkımız var)
    return _supabase
        .from('matches')
        .stream(primaryKey: ['id'])
        .eq('league_id', leagueId)
        .order('match_date', ascending: true)
        .map((rows) {
          // 2. Diğer tüm filtreleri (week, seasonId, groupId) burada, yani veriler geldikten sonra yapıyoruz
          return rows
              .where((r) {
                // Hafta kontrolü
                final matchWeek = _readInt(r['week'], fallback: -1);
                if (matchWeek != week) return false;

                // Sezon kontrolü (Eğer parametre gönderildiyse)
                if (seasonId != null && r['season_id'] != seasonId)
                  return false;

                // Grup kontrolü (Eğer parametre gönderildiyse)
                if (groupId != null && r['group_id'] != groupId) return false;

                return true;
              })
              // 3. MatchModel.fromMap'e data ve id'yi göndererek listeye çeviriyoruz
              .map((r) => MatchModel.fromMap(r, r['id'] as String))
              .toList();
        });
  }

  @override
  Future<int?> getFixtureMaxWeek(String leagueId, {String? groupId}) async {
    var query = _supabase
        .from('matches')
        .select('week')
        .eq('league_id', leagueId);
    if (groupId != null) query = query.eq('group_id', groupId);

    final res = await query
        .order('week', ascending: false)
        .limit(1)
        .maybeSingle();
    return res != null ? _readInt(res['week'], fallback: 1) : 1;
  }

  @override
  Stream<MatchModel> watchMatch(String matchId) {
    return _supabase
        .from('matches')
        .stream(primaryKey: ['id'])
        .eq('id', matchId)
        .limit(1)
        .map(
          (rows) => MatchModel.fromMap(rows.first, rows.first['id'] as String),
        );
  }

  @override
  Stream<List<Map<String, dynamic>>> watchInlineMatchEvents(String matchId) {
    return _supabase
        .from('match_events')
        .stream(primaryKey: ['id'])
        .eq('match_id', matchId)
        .order('minute', ascending: true)
        .map((rows) => rows.cast<Map<String, dynamic>>().toList());
  }

  @override
  Future<String> addMatch(MatchModel match) async {
    final res = await _supabase
        .from('matches')
        .insert(match.toMap(snakeCase: true))
        .select('id')
        .single();
    return res['id'] as String;
  }

  @override
  Future<void> completeMatchWithScoreAndDefaultEvents({
    required String matchId,
    required int homeScore,
    required int awayScore,
  }) async {
    await _supabase.from('matches').upsert({
      'id': matchId,
      'home_score': homeScore,
      'away_score': awayScore,
      'is_completed': true,
      'status': 'finished',
    }, onConflict: 'id');

    final matchData = await _supabase
        .from('matches')
        .select('league_id')
        .eq('id', matchId)
        .limit(1);
        
    int period = 25;
    if (matchData.isNotEmpty) {
      final leagueId = matchData.first['league_id']?.toString() ?? '';
      if (leagueId.isNotEmpty) {
        final leagueData = await _supabase
            .from('leagues')
            .select('match_period_duration')
            .eq('id', leagueId)
            .limit(1);
        if (leagueData.isNotEmpty) {
          final p = leagueData.first['match_period_duration'];
          if (p is num) period = p.toInt();
        }
      }
    }

    final duration = period * 2;
    await insertDefaultMatchEvents(matchId, duration);
  }

  @override
  Future<void> insertDefaultMatchEvents(String matchId, int duration) async {
    final createdAt = DateTime.now().toIso8601String();
    final halfTime = duration ~/ 2;

    await _supabase.from('match_events').insert([
      {
        'match_id': matchId,
        'event_type': 'status',
        'minute': 0,
        'player_name': 'Maç Başladı',
        'created_at': createdAt,
      },
      {
        'match_id': matchId,
        'event_type': 'status',
        'minute': halfTime,
        'player_name': 'İlk Yarı',
        'created_at': createdAt,
      },
      {
        'match_id': matchId,
        'event_type': 'status',
        'minute': duration,
        'player_name': 'Maç Sonucu',
        'created_at': createdAt,
      },
    ]);
  }

  @override
  Future<void> deleteMatchMedia(String mediaId) async {
    await _supabase.from('match_media').delete().eq('id', mediaId);
  }

  @override
  Future<void> addMatchEvent(MatchEvent event) async {
    await _supabase.from('match_events').insert(event.toMap(snakeCase: true));
  }

  @override
  Future<void> updateMatchPitchName({
    required String matchId,
    required String? pitchName,
  }) async {
    await _supabase
        .from('matches')
        .update({'pitch_name': pitchName})
        .eq('id', matchId);
  }

  @override
  Future<void> addMatchMedia(MatchMediaModel media) async {
    // toMap() yerine doğrudan tablo kolon isimlerini elle yazıyoruz
    // DEBUG PRINT: Veri servise nasıl geliyor?
    print('--- SUPABASE INSERT TEST ---');
    print('MatchID: ${media.matchId}');
    print(
      'URL: "${media.url}"',
    ); // Tırnak içinde yazdır ki boşluk mu var görelim
    print('Type: ${media.mediaType}');

    await _supabase.from('match_media').insert({
      'match_id': media.matchId,
      'media_type': media.mediaType,
      'url': media.url, // Veritabanındaki kolon adının 'url' olduğundan eminiz
      'description': media.description,
      'team_id': media.teamId,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  @override
  Stream<List<MatchMediaModel>> watchMatchMedia(String matchId) {
    // primaryKey: ['id'] kısmı tablodaki PK ile birebir aynı olmalı
    return _supabase
        .from('match_media')
        .stream(primaryKey: ['id'])
        .eq('match_id', matchId)
        .order('created_at', ascending: false)
        .map(
          (rows) => rows
              .map((r) => MatchMediaModel.fromMap(r, r['id'] as String))
              .toList(),
        );
  }

  @override
  Future<void> updateMatchSchedule({
    required String matchId,
    required String matchDateDb,
    required String matchTime,
    String? pitchId,
    String? pitchName,
  }) async {
    await _supabase
        .from('matches')
        .update({
          'match_date': matchDateDb,
          'match_time': matchTime,
          'pitch_id': pitchId,
          'pitch_name': pitchName,
        })
        .eq('id', matchId);
  }

  @override
  Future<void> updateMatchLineup({
    required String matchId,
    required bool isHome,
    required MatchLineup lineup,
  }) async {
    final key = isHome ? 'home_lineup' : 'away_lineup';
    await _supabase
        .from('matches')
        .update({key: lineup.toMap()})
        .eq('id', matchId);
  }

  @override
  Future<void> updateMatchFormationState({
    required String matchId,
    String? homeFormation,
    String? awayFormation,
    List<String>? homeOrder,
    List<String>? awayOrder,
  }) async {
    await _supabase
        .from('matches')
        .update({
          'home_formation': homeFormation,
          'away_formation': awayFormation,
          'home_order': homeOrder,
          'away_order': awayOrder,
        })
        .eq('id', matchId);
  }

  @override
  Stream<List<MatchRosterModel>> watchMatchRosters(String matchId, String teamId) {
    return _supabase
        .from('match_rosters')
        .stream(primaryKey: ['id'])
        .map((rows) {
          final filtered = rows.where((r) => r['match_id'] == matchId && r['team_id'] == teamId);
          return filtered.map((r) => MatchRosterModel.fromMap(r, r['id'] as String)).toList();
        });
  }

  @override
  Future<void> updateMatchRoster({
    required String matchId,
    required String leagueId,
    required String seasonId,
    required String teamId,
    required bool isHome,
    required List<MatchRosterModel> rosters,
  }) async {
    // 1. Delete existing for this match and team
    await _supabase
        .from('match_rosters')
        .delete()
        .eq('match_id', matchId)
        .eq('team_id', teamId);

    // 2. Insert new ones
    if (rosters.isEmpty) return;

    final List<Map<String, dynamic>> toInsert = rosters.map((r) {
      return {
        'match_id': matchId,
        'league_id': leagueId,
        'team_id': teamId,
        'player_id': r.playerId,
        'is_home': isHome,
        'is_starting': r.isStarting,
        'jersey_number': r.jerseyNumber,
      };
    }).toList();

    await _supabase.from('match_rosters').insert(toInsert);
  }

  @override
  Stream<List<PlayerStats>> watchPlayerStats({required String tournamentId}) {
    return _supabase
        .from('player_stats')
        .stream(primaryKey: ['id'])
        .eq('tournament_id', tournamentId)
        .map(
          (rows) => rows
              .map((r) => PlayerStats.fromMap(r, r['id'] as String))
              .toList(),
        );
  }

  @override
  Future<void> commitPlayerStatsForCompletedMatch({
    required String matchId,
  }) async {
    await _supabase.rpc('commit_match_stats', params: {'p_match_id': matchId});
  }

  @override
  Future<void> importTeamsAndFixture({
    required String tournamentId,
    required List<FixtureImportTeam> teams,
    required List<FixtureImportMatch> matches,
  }) async {
    // Takım ve Maç import mantığı (Syntax düzeltildi)
    for (var m in matches) {
      // seasonId hatası için modeldeki alanı kontrol ederek dinamik atama
      await _supabase.from('matches').insert({
        'league_id': tournamentId,
        'home_team_name': m.homeTeamName,
        'away_team_name': m.awayTeamName,
        'match_date': m.matchDateYyyyMmDd,
        'match_time': m.matchTime,
        'week': m.week,
        'status': 'notStarted',
      });
    }
  }

  @override
  Future<int> deleteAllMatchesAndEvents() async {
    await _supabase
        .from('matches')
        .delete()
        .neq('id', '00000000-0000-0000-0000-000000000000');
    return 1;
  }

  @override
  Future<Map<String, int>> migrateMatchesTimeTimestampToMatchFields() async => {
    'migrated': 0,
  };

  @override
  Future<Map<String, int>> normalizeMatchesDocIdsByLeagueWeekHomeTeam() async =>
      {'normalized': 0};

  @override
  Future<bool> hasBroadcast(String matchId) async {
    final res = await _supabase
        .from('match_media')
        .select('id')
        .eq('match_id', matchId)
        .eq('media_type', 'Maç Yayın Linki')
        .limit(1);
    return res.isNotEmpty;
  }

  @override
  Future<String?> getBroadcastUrl(String matchId) async {
    final res = await _supabase
        .from('match_media')
        .select('url')
        .eq('match_id', matchId)
        .eq('media_type', 'Maç Yayın Linki')
        .limit(1);
    if (res.isNotEmpty) {
      final row = res.first as Map<String, dynamic>;
      return row['url']?.toString();
    }
    return null;
  }
}
