import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

import '../interfaces/i_match_service.dart';
import '../../../../core/config/app_config.dart';
import '../../models/fixture_import.dart';
import '../../models/match.dart';
import '../../models/match_media.dart';
import '../../../../core/utils/resilient_stream.dart';
import '../../../../core/utils/realtime_signal.dart';
import '../../../../core/utils/table_feed.dart';
import '../../../player/models/player_stats.dart';

class SupabaseMatchService implements IMatchService {
  SupabaseMatchService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  int _readInt(dynamic v, {required int fallback}) {
    if (v == null) return fallback;
    if (v is num) return v.toInt();
    final s = v.toString().replaceAll('\u0000', '').trim();
    return int.tryParse(s) ??
        double.tryParse(s.replaceAll(',', '.'))?.toInt() ??
        fallback;
  }

  String? _normalizeMatchTimeForDb(String? matchTime) {
    final raw = (matchTime ?? '').trim();
    if (raw.isEmpty) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(raw);
    if (m == null) return raw;
    final hh = int.tryParse(m.group(1) ?? '');
    final mm = int.tryParse(m.group(2) ?? '');
    if (hh == null || mm == null) return raw;
    if (hh < 0 || hh > 23 || mm < 0 || mm > 59) return raw;
    return '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
  }

  @override
  Stream<List<MatchModel>> watchMatchesForLeague(String leagueId) {
    final id = leagueId.trim();
    if (id.isEmpty) return const Stream<List<MatchModel>>.empty();
    try {
      AppConfig.sqlLogStart(
        table: 'matches',
        operation: 'STREAM',
        filters:
            'primaryKey=id | clientFilter=league_id=$id | order=match_date asc',
      );
      return watchTableRows(
        _client,
        table: 'matches',
        column: 'league_id',
        value: id,
        orderBy: 'match_date',
      ).map((rows) {
        final filtered = rows.where((r) {
          return (r['league_id'] ?? '').toString().trim() == id;
        });
        return filtered
            .map(
              (r) => MatchModel.fromMap(
                Map<String, dynamic>.from(r),
                (r['id'] ?? '').toString(),
              ),
            )
            .toList();
      });
    } catch (e) {
      AppConfig.sqlLogResult(table: 'matches', operation: 'STREAM', error: e);
      return const Stream<List<MatchModel>>.empty();
    }
  }

  @override
  Stream<List<MatchModel>> watchMatchesByDate({
    required String leagueId,
    required DateTime date,
  }) {
    final id = leagueId.trim();
    if (id.isEmpty) return const Stream<List<MatchModel>>.empty();
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    final dateStr = '$y-$m-$d';
    return watchMatchesForLeague(id).map((list) {
      return list.where((e) => (e.matchDate ?? '').trim() == dateStr).toList();
    });
  }

  /// Fikstür haftası önbelleği ("league|season|group|week" → maçlar).
  final Map<String, List<MatchModel>> _fixtureCache = {};

  @override
  Stream<List<MatchModel>> watchFixtureMatches(
    String leagueId,
    int week, {
    String? groupId,
    String? seasonId,
  }) {
    final id = leagueId.trim();
    if (id.isEmpty) return const Stream<List<MatchModel>>.empty();
    final sId = (seasonId ?? '').trim();
    final gId = (groupId ?? '').trim() == 'Tümü' ? '' : (groupId ?? '').trim();
    final key = '$id|$sId|$gId|$week';

    Future<List<MatchModel>> fetch() async {
      var query = _client.from('matches').select().eq('league_id', id);
      if (sId.isNotEmpty) query = query.eq('season_id', sId);
      if (gId.isNotEmpty) query = query.eq('group_id', gId);
      query = query.eq('week', week);
      final rows = await query.order('created_at', ascending: false);
      final list = rows
          .map(
            (r) => MatchModel.fromMap(
              Map<String, dynamic>.from(r),
              (r['id'] ?? '').toString(),
            ),
          )
          .toList();
      _fixtureCache[key] = list;
      return list;
    }

    // Önce önbellekteki hafta gösterilir, taze liste arkadan gelir.
    Stream<List<MatchModel>> feed() async* {
      final cached = _fixtureCache[key];
      if (cached != null) yield cached;
      try {
        yield await fetch();
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'matches',
          operation: 'SELECT_STREAM',
          error: e,
        );
        if (cached == null) rethrow;
      }
    }

    return feed();
  }

  @override
  Future<int?> getFixtureMaxWeek(String leagueId, {String? groupId}) {
    final id = leagueId.trim();
    if (id.isEmpty) return Future.value(null);
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'matches',
          operation: 'SELECT',
          filters: 'columns=week,league_id',
        );
        final res = await _client.from('matches').select('week, league_id');
        AppConfig.sqlLogResult(
          table: 'matches',
          operation: 'SELECT',
          count: res.length,
        );
        int? maxWeek;
        for (final rowAny in res) {
          final row = (rowAny as Map).cast<String, dynamic>();
          final tid = (row['league_id'] ?? '').toString().trim();
          if (tid != id) continue;
          final w = row['week'];
          final ww = w is num ? w.toInt() : int.tryParse(w?.toString() ?? '');
          if (ww == null) continue;
          maxWeek = maxWeek == null ? ww : (ww > maxWeek ? ww : maxWeek);
        }
        return maxWeek;
      } catch (e) {
        AppConfig.sqlLogResult(table: 'matches', operation: 'SELECT', error: e);
        return null;
      }
    });
  }

  /// Maç önbelleği (matchId → son bilinen maç).
  final Map<String, MatchModel> _matchCache = {};

  @override
  Stream<MatchModel> watchMatch(String matchId) {
    final id = matchId.trim();
    if (id.isEmpty) return const Stream<MatchModel>.empty();
    AppConfig.sqlLogStart(
      table: 'matches',
      operation: 'STREAM',
      filters: 'primaryKey=id | filter=id=$id',
    );

    Stream<MatchModel> feed() async* {
      final cached = _matchCache[id];
      if (cached != null) yield cached;
      // Yalnızca bu maçın satırı dinlenir (önceden tüm tablo indiriliyordu).
      await for (final rows in watchTableRows(
        _client,
        table: 'matches',
        column: 'id',
        value: id,
      )) {
        final row = rows.isEmpty
            ? const <String, dynamic>{}
            : rows.first.cast<String, dynamic>();
        final m = MatchModel.fromMap(row, id);
        if (row.isNotEmpty) _matchCache[id] = m;
        yield m;
      }
    }

    return resilientStream(feed);
  }

  /// Maç olayları önbelleği (matchId → olay listesi, oyuncu adları ekli).
  final Map<String, List<Map<String, dynamic>>> _eventsCache = {};

  Future<List<Map<String, dynamic>>> _fetchInlineMatchEvents(String id) async {
    final rows = await _client
        .from('match_events')
        .select()
        .eq('match_id', id)
        .order('minute', ascending: true);
    final list = rows.map((r) => Map<String, dynamic>.from(r)).toList();
    // match_events'te player_name kolonu yok; ekranlar adı player_name
    // alanından okuduğu için players tablosundan eklenir.
    final names = await _playerNamesById({
      for (final e in list) ...[
        (e['player_id'] ?? '').toString().trim(),
        (e['assist_player_id'] ?? '').toString().trim(),
        (e['sub_in_player_id'] ?? '').toString().trim(),
      ],
    });
    for (final e in list) {
      final pid = (e['player_id'] ?? '').toString().trim();
      final aid = (e['assist_player_id'] ?? '').toString().trim();
      final sid = (e['sub_in_player_id'] ?? '').toString().trim();
      if (names[pid] != null) e['player_name'] = names[pid];
      if (names[aid] != null) e['assist_player_name'] = names[aid];
      if (names[sid] != null) e['sub_in_player_name'] = names[sid];
    }
    _eventsCache[id] = list;
    return list;
  }

  @override
  Stream<List<Map<String, dynamic>>> watchInlineMatchEvents(String matchId) {
    final id = matchId.trim();
    if (id.isEmpty) return const Stream<List<Map<String, dynamic>>>.empty();
    AppConfig.sqlLogStart(
      table: 'match_events',
      operation: 'STREAM',
      filters: 'filter=match_id=$id | order=minute asc',
    );

    // Önce önbellek, sonra tek filtreli sorgu; realtime yalnızca "değişti"
    // sinyali verir (önceden tüm match_events tablosu indiriliyordu).
    Stream<List<Map<String, dynamic>>> feed() async* {
      final cached = _eventsCache[id];
      if (cached != null) yield cached;
      yield await _fetchInlineMatchEvents(id);
      await for (final _ in realtimeChangeSignal(
        _client,
        table: 'match_events',
        column: 'match_id',
        value: id,
      )) {
        yield await _fetchInlineMatchEvents(id);
      }
    }

    return resilientStream(feed);
  }

  @override
  Future<String> addMatch(MatchModel match) {
    return Future(() async {
      try {
        AppConfig.sqlLogStart(table: 'matches', operation: 'INSERT');
        final payload = match.toMap(snakeCase: true);
        payload['match_time'] = _normalizeMatchTimeForDb(
          payload['match_time']?.toString(),
        );
        payload['created_at'] = DateTime.now().toIso8601String();
        final res = await _client
            .from('matches')
            .insert(payload)
            .select('id')
            .limit(1);
        if (res.isNotEmpty) {
          final row = (res.first as Map).cast<String, dynamic>();
          AppConfig.sqlLogResult(
            table: 'matches',
            operation: 'INSERT',
            count: 1,
          );
          return (row['id'] ?? '').toString();
        }
        AppConfig.sqlLogResult(table: 'matches', operation: 'INSERT', count: 0);
        throw Exception('Maç kaydedilemedi (matches INSERT 0 satır).');
      } catch (e) {
        AppConfig.sqlLogResult(table: 'matches', operation: 'INSERT', error: e);
        // Hata yutulmaz: aksi halde ekran "başarılı" der ama kayıt oluşmaz.
        rethrow;
      }
    });
  }

  @override
  Future<void> addMatchEvent(MatchEvent event) {
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'match_events',
          operation: 'INSERT',
          filters: 'match_id=${event.matchId}',
        );
        final payload = event.toMap(snakeCase: true);
        payload['created_at'] = DateTime.now().toIso8601String();
        await _client.from('match_events').insert(payload);
        AppConfig.sqlLogResult(
          table: 'match_events',
          operation: 'INSERT',
          count: 1,
        );
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'match_events',
          operation: 'INSERT',
          error: e,
        );
        // Hata yutulmaz: aksi halde ekran "kaydedildi" der ama olay oluşmaz.
        rethrow;
      }

      if (event.eventType != 'goal') return;

      try {
        AppConfig.sqlLogStart(
          table: 'matches',
          operation: 'SELECT',
          filters:
              'id=${event.matchId} | columns=home_team_id,away_team_id,home_score,away_score | limit=1',
        );
        final res = await _client
            .from('matches')
            .select(
              'home_team_id, away_team_id, home_score, away_score, status',
            )
            .eq('id', event.matchId)
            .limit(1);
        if (res.isEmpty) {
          AppConfig.sqlLogResult(
            table: 'matches',
            operation: 'SELECT',
            count: 0,
          );
          return;
        }
        AppConfig.sqlLogResult(table: 'matches', operation: 'SELECT', count: 1);
        final row = (res.first as Map).cast<String, dynamic>();
        // Bitmiş maçın skoru zaten girilmiştir (ör. Hızlı Skor Girişi);
        // sonradan gol atanları eklemek skoru ikinci kez artırmamalı.
        if ((row['status'] ?? '').toString().trim() ==
            MatchStatus.finished.name) {
          return;
        }
        final homeTeamId = (row['home_team_id'] ?? '').toString().trim();
        final awayTeamId = (row['away_team_id'] ?? '').toString().trim();
        final scoringTeamId = event.isOwnGoal
            ? (event.teamId == homeTeamId ? awayTeamId : homeTeamId)
            : event.teamId;
        final isHome = scoringTeamId == homeTeamId;
        final isAway = scoringTeamId == awayTeamId;
        if (!isHome && !isAway) return;

        final currentHome = _readInt(row['home_score'], fallback: 0);
        final currentAway = _readInt(row['away_score'], fallback: 0);
        final nextHome = isHome ? currentHome + 1 : currentHome;
        final nextAway = isAway ? currentAway + 1 : currentAway;

        AppConfig.sqlLogStart(
          table: 'matches',
          operation: 'UPDATE',
          filters:
              'id=${event.matchId} | home_score=$nextHome, away_score=$nextAway',
        );
        await _client
            .from('matches')
            .update({'home_score': nextHome, 'away_score': nextAway})
            .eq('id', event.matchId);
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPDATE', count: 1);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPDATE', error: e);
      }
    });
  }

  @override
  Future<void> advanceMatchPhase({
    required String matchId,
    required String action,
  }) async {
    AppConfig.sqlLogStart(
      table: 'matches',
      operation: 'RPC',
      filters: 'advance_match_phase | id=$matchId | $action',
    );
    await _client.rpc(
      'advance_match_phase',
      params: {'p_match_id': matchId, 'p_action': action},
    );
    AppConfig.sqlLogResult(table: 'matches', operation: 'RPC', count: 1);
  }

  @override
  Future<void> setMatchObserver({
    required String matchId,
    required String? userId,
  }) async {
    await _client
        .from('matches')
        .update({'observer_id': userId})
        .eq('id', matchId);
  }

  @override
  Future<List<({String userId, String label})>> listObserverCandidates() async {
    final rows = await _client.rpc('list_observer_candidates') as List;
    return [
      for (final r in rows)
        (userId: r['user_id'].toString(), label: (r['label'] ?? '').toString()),
    ];
  }

  @override
  Future<void> updateMatchPitchName({
    required String matchId,
    required String? pitchName,
  }) {
    final id = matchId.trim();
    if (id.isEmpty) return Future.value();
    return _updateMatchPitch(id, (pitchName ?? '').trim());
  }

  /// matches tablosunda saha adı değil `pitch_id` tutulur; ad ile bulunur.
  Future<void> _updateMatchPitch(String matchId, String pitchName) async {
    String? pitchId;
    if (pitchName.isNotEmpty) {
      final row = await _client
          .from('pitches')
          .select('id')
          .eq('name', pitchName)
          .limit(1)
          .maybeSingle();
      pitchId = row?['id']?.toString();
      if (pitchId == null) throw Exception('Saha bulunamadı: $pitchName');
    }
    AppConfig.sqlLogStart(
      table: 'matches',
      operation: 'UPDATE',
      filters: 'id=$matchId | pitch_id',
    );
    await _client
        .from('matches')
        .update({'pitch_id': pitchId})
        .eq('id', matchId);
    AppConfig.sqlLogResult(table: 'matches', operation: 'UPDATE', count: 1);
  }

  @override
  Future<void> addMatchMedia(MatchMediaModel media) async {
    try {
      AppConfig.sqlLogStart(table: 'match_media', operation: 'INSERT');
      await _client.from('match_media').insert(media.toMap(snakeCase: true));
      AppConfig.sqlLogResult(
        table: 'match_media',
        operation: 'INSERT',
        count: 1,
      );
    } catch (e) {
      AppConfig.sqlLogResult(
        table: 'match_media',
        operation: 'INSERT',
        error: e,
      );
    }
  }

  /// Maç medyası önbelleği ve maç başına ortak akış (yayın paneli ile
  /// Önemli Anlar sekmesi aynı kanalı paylaşır).
  final Map<String, List<MatchMediaModel>> _mediaCache = {};
  final Map<String, Stream<List<MatchMediaModel>>> _mediaFeeds = {};

  Future<List<MatchMediaModel>> _fetchMatchMedia(String id) async {
    final rows = await _client
        .from('match_media')
        .select()
        .eq('match_id', id)
        .order('created_at', ascending: false);
    final list = rows
        .map(
          (r) => MatchMediaModel.fromMap(
            Map<String, dynamic>.from(r),
            (r['id'] ?? '').toString(),
          ),
        )
        .toList();
    _mediaCache[id] = list;
    return list;
  }

  @override
  Stream<List<MatchMediaModel>> watchMatchMedia(String matchId) {
    final id = matchId.trim();
    if (id.isEmpty) return Stream.value([]);
    AppConfig.sqlLogStart(
      table: 'match_media',
      operation: 'STREAM',
      filters: 'filter=match_id=$id | order=created_at desc',
    );

    // Önce önbellek, sonra tek filtreli sorgu; realtime yalnızca "değişti"
    // sinyali verir (önceden tüm match_media tablosu indiriliyordu).
    Stream<List<MatchMediaModel>> feed() async* {
      final cached = _mediaCache[id];
      if (cached != null) yield cached;
      yield await _fetchMatchMedia(id);
      await for (final _ in realtimeChangeSignal(
        _client,
        table: 'match_media',
        column: 'match_id',
        value: id,
      )) {
        yield await _fetchMatchMedia(id);
      }
    }

    return _mediaFeeds.putIfAbsent(id, () => resilientStream(feed));
  }

  @override
  Future<void> updateMatchSchedule({
    required String matchId,
    required String matchDateDb,
    required String matchTime,
    String? pitchId,
    String? pitchName,
  }) {
    final id = matchId.trim();
    if (id.isEmpty) return Future.value();
    return Future(() async {
      try {
        final payload = <String, dynamic>{
          'match_date': matchDateDb.trim().isEmpty ? null : matchDateDb.trim(),
          'match_time': _normalizeMatchTimeForDb(matchTime),
          'pitch_id': (pitchId ?? '').trim().isEmpty ? null : pitchId!.trim(),
          'pitch_name': (pitchName ?? '').trim().isEmpty
              ? null
              : pitchName!.trim(),
        };
        AppConfig.sqlLogStart(
          table: 'matches',
          operation: 'UPDATE',
          filters: 'id=$id',
        );
        final res = await _client
            .from('matches')
            .update(payload)
            .eq('id', id)
            .select('id')
            .limit(1);
        if (res.isEmpty) {
          throw Exception('matches UPDATE: 0 satır etkilendi (id=$id)');
        }
        AppConfig.sqlLogResult(
          table: 'matches',
          operation: 'UPDATE',
          count: res.length,
        );
      } catch (e) {
        try {
          final fallbackPayload = <String, dynamic>{
            'match_date': matchDateDb.trim().isEmpty
                ? null
                : matchDateDb.trim(),
            'match_time': _normalizeMatchTimeForDb(matchTime),
            'pitch_id': (pitchId ?? '').trim().isEmpty ? null : pitchId!.trim(),
          };
          AppConfig.sqlLogStart(
            table: 'matches',
            operation: 'UPDATE',
            filters: 'id=$id | fallback=no pitch_name',
          );
          final res2 = await _client
              .from('matches')
              .update(fallbackPayload)
              .eq('id', id)
              .select('id')
              .limit(1);
          if (res2.isEmpty) {
            throw Exception('matches UPDATE: 0 satır etkilendi (id=$id)');
          }
          AppConfig.sqlLogResult(
            table: 'matches',
            operation: 'UPDATE',
            count: res2.length,
          );
        } catch (e2) {
          AppConfig.sqlLogResult(
            table: 'matches',
            operation: 'UPDATE',
            error: e2,
          );
          rethrow;
        }
      }
    });
  }

  @override
  Future<void> updateMatchLineup({
    required String matchId,
    required bool isHome,
    required MatchLineup lineup,
  }) {
    final id = matchId.trim();
    if (id.isEmpty) return Future.value();
    return Future.value();
  }

  @override
  Future<void> updateMatchFormationState({
    required String matchId,
    String? homeFormation,
    String? awayFormation,
    List<String>? homeOrder,
    List<String>? awayOrder,
  }) async {
    final id = matchId.trim();
    if (id.isEmpty) return;

    final updates = <String, dynamic>{};
    if (homeFormation != null) updates['home_formation'] = homeFormation;
    if (awayFormation != null) updates['away_formation'] = awayFormation;
    // home_order / away_order kolonları yok; yerleşim dizilişten hesaplanır.

    if (updates.isEmpty) return;

    try {
      AppConfig.sqlLogStart(
        table: 'matches',
        operation: 'UPDATE',
        filters: 'id=$id | keys=${updates.keys.join(',')}',
      );
      await _client.from('matches').update(updates).eq('id', id);
      AppConfig.sqlLogResult(table: 'matches', operation: 'UPDATE', count: 1);
    } catch (e) {
      AppConfig.sqlLogResult(table: 'matches', operation: 'UPDATE', error: e);
      // Hata yutulmaz: diziliş kaydedilemediyse ekran kullanıcıyı uyarır.
      rethrow;
    }
  }

  @override
  Future<void> completeMatchWithScoreAndDefaultEvents({
    required String matchId,
    required int homeScore,
    required int awayScore,
  }) {
    final id = matchId.trim();
    if (id.isEmpty) return Future.value();
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'matches',
          operation: 'UPDATE',
          filters: 'id=$id',
        );
        // upsert değil update: upsert'in ekleme kontrolü (RLS) turnuva
        // sahibini reddeder. Hiç satır güncellenmezse yetki yok demektir.
        final rows = await _client
            .from('matches')
            .update({
              'home_score': homeScore,
              'away_score': awayScore,
              'is_completed': true,
              'status': 'finished',
            })
            .eq('id', id)
            .select('id');
        if (rows.isEmpty) {
          throw Exception(
            'Skor kaydedilemedi: bu maçı düzenleme yetkiniz yok.',
          );
        }
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPDATE', count: 1);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPDATE', error: e);
        rethrow;
      }

      // "Maç Başladı / İlk Yarı / Maç Bitti" satırları veritabanına yazılmaz;
      // maç detayı bunları maç durumundan ve sezonun devre süresinden
      // (seasons.match_period_duration) üretir.
    });
  }

  @override
  Future<void> insertDefaultMatchEvents(String matchId, int duration) async {
    final id = matchId.trim();
    if (id.isEmpty) return;

    try {
      AppConfig.sqlLogStart(
        table: 'match_events',
        operation: 'INSERT',
        filters: 'match_id=$id | 3 status events',
      );

      final halfTime = duration ~/ 2;

      await _client.from('match_events').insert([
        {
          'match_id': id,
          'event_type': 'status',
          'minute': 0,
          'player_name': 'Maç Başladı',
        },
        {
          'match_id': id,
          'event_type': 'status',
          'minute': halfTime,
          'player_name': 'İlk Yarı',
        },
        {
          'match_id': id,
          'event_type': 'status',
          'minute': duration,
          'player_name': 'Maç Sonucu',
        },
      ]);
      AppConfig.sqlLogResult(
        table: 'match_events',
        operation: 'INSERT',
        count: 3,
      );
    } catch (e) {
      AppConfig.sqlLogResult(
        table: 'match_events',
        operation: 'INSERT',
        error: e,
      );
    }
  }

  /// Maç kadroları önbelleği (matchId → iki takımın kadrosu).
  final Map<String, List<MatchRosterModel>> _rosterCache = {};

  /// Maç başına tek ortak akış; iki takımın ekranı da aynı kanalı paylaşır.
  final Map<String, Stream<List<MatchRosterModel>>> _rosterFeeds = {};

  Future<List<MatchRosterModel>> _fetchMatchRosters(String matchId) async {
    final rows = await _client
        .from('match_rosters')
        .select()
        .eq('match_id', matchId);
    final list = rows
        .map((r) => MatchRosterModel.fromMap(r, (r['id'] ?? '').toString()))
        .toList();
    _rosterCache[matchId] = list;
    return list;
  }

  /// Önce önbellek, sonra tek filtreli sorgu, en son yalnızca bu maça ait
  /// realtime kanalı. Realtime olayları yalnızca "değişti" sinyali olarak
  /// kullanılır; liste her seferinde veritabanından taze okunur (kaydetme
  /// eski satırları silip yenilerini eklediği için silme olayları akışa
  /// ulaşmadığında esame çiftleniyordu).
  Stream<List<MatchRosterModel>> _matchRosterChanges(String matchId) async* {
    final cached = _rosterCache[matchId];
    if (cached != null) yield cached;
    yield await _fetchMatchRosters(matchId);
    await for (final _ in realtimeChangeSignal(
      _client,
      table: 'match_rosters',
      column: 'match_id',
      value: matchId,
    )) {
      yield await _fetchMatchRosters(matchId);
    }
  }

  @override
  Stream<List<MatchRosterModel>> watchMatchRosters(
    String matchId,
    String teamId,
  ) {
    // Uygulama arka plandan dönünce kopan bağlantı otomatik yenilenir.
    final feed = _rosterFeeds.putIfAbsent(
      matchId,
      () => resilientStream(() => _matchRosterChanges(matchId)),
    );
    return feed.map((all) => all.where((r) => r.teamId == teamId).toList());
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
    await _client
        .from('match_rosters')
        .delete()
        .eq('match_id', matchId)
        .eq('team_id', teamId);

    // 2. Insert new ones
    if (rosters.isEmpty) return;

    // is_captain yalnızca kaptan seçildiyse gönderilir; böylece kolon henüz
    // eklenmemiş veritabanında kaptansız kayıt çalışmaya devam eder.
    final hasCaptain = rosters.any((r) => r.isCaptain);
    List<Map<String, dynamic>> rows({required bool withCaptain}) {
      return rosters.map((r) {
        return {
          'match_id': matchId,
          'league_id': leagueId,
          if (seasonId.trim().isNotEmpty) 'season_id': seasonId,
          'team_id': teamId,
          'player_id': r.playerId,
          'is_home': isHome,
          'is_starting': r.isStarting,
          'jersey_number': r.jerseyNumber,
          if (withCaptain) 'is_captain': r.isCaptain,
        };
      }).toList();
    }

    try {
      await _client.from('match_rosters').insert(rows(withCaptain: hasCaptain));
    } on PostgrestException catch (e) {
      // Eski kayıtlar yukarıda silindi; kaptan kolonu yoksa kadroyu kaptansız
      // yine de kaydet ki kadro kaybolmasın, sonra kullanıcıyı bilgilendir.
      if (hasCaptain && e.code == 'PGRST204') {
        await _client.from('match_rosters').insert(rows(withCaptain: false));
        throw Exception(
          'Kadro kaydedildi ancak kaptan kaydedilemedi: match_rosters '
          'tablosunda is_captain kolonu yok.',
        );
      }
      rethrow;
    }
  }

  /// id → "Ad Soyad" eşlemesi (players tablosundan).
  /// Oyuncu adı önbelleği; olay listesi her yenilendiğinde yalnızca
  /// bilinmeyen oyuncular sorgulanır.
  final Map<String, String> _playerNameCache = {};

  Future<Map<String, String>> _playerNamesById(Set<String> ids) async {
    final clean = ids.where((e) => e.isNotEmpty).toSet();
    if (clean.isEmpty) return const <String, String>{};
    final missing = clean.where((e) => !_playerNameCache.containsKey(e));
    if (missing.isNotEmpty) {
      try {
        final res = await _client
            .from('players')
            .select('id, name, surname')
            .inFilter('id', missing.toList());
        for (final any in res) {
          final r = (any as Map).cast<String, dynamic>();
          final full = [
            (r['name'] ?? '').toString().trim(),
            (r['surname'] ?? '').toString().trim(),
          ].where((e) => e.isNotEmpty).join(' ');
          if (full.isNotEmpty) {
            _playerNameCache[(r['id'] ?? '').toString()] = full;
          }
        }
      } catch (_) {}
    }
    return {
      for (final id in clean)
        if (_playerNameCache[id] != null) id: _playerNameCache[id]!,
    };
  }

  /// Sezon istatistikleri doğrudan `match_events` üzerinden hesaplanır.
  /// Önceden var olmayan `player_stats` tablosu dinleniyordu ve bu tabloyu
  /// dolduran fonksiyon Supabase modunda hiç çağrılmıyordu.
  /// [tournamentId] burada SEZON id'sidir (player_card da sezon id gönderir).
  /// Sezonda hiç olay yoksa `player_season_stats` tablosundaki kayıtlar
  /// kullanılır (ör. önceden yüklenmiş veriler).
  @override
  Stream<List<PlayerStats>> watchPlayerStats({required String tournamentId}) {
    final seasonId = tournamentId.trim();
    if (seasonId.isEmpty) return const Stream<List<PlayerStats>>.empty();
    AppConfig.sqlLogStart(
      table: 'match_events',
      operation: 'STREAM',
      filters: 'season_id=$seasonId (aggregate player stats)',
    );

    // Önce önbellek, sonra yalnızca bu sezonun olayları (önceden tüm
    // match_events tablosu indiriliyordu). Olay değişince yeniden hesaplanır.
    Stream<List<PlayerStats>> feed() async* {
      final cached = _statsCache[seasonId];
      if (cached != null) yield cached;
      yield await _loadSeasonStats(seasonId);
      await for (final _ in realtimeChangeSignal(
        _client,
        table: 'match_events',
      )) {
        yield await _loadSeasonStats(seasonId);
      }
    }

    return _statsFeeds.putIfAbsent(seasonId, () => resilientStream(feed));
  }

  /// Sezon istatistikleri önbelleği ve sezon başına ortak akış.
  final Map<String, List<PlayerStats>> _statsCache = {};
  final Map<String, Stream<List<PlayerStats>>> _statsFeeds = {};

  Future<List<PlayerStats>> _loadSeasonStats(String seasonId) async {
    final matchesRes = await _client
        .from('matches')
        .select('id')
        .eq('season_id', seasonId);
    final matchIds = [
      for (final any in matchesRes)
        ((any as Map)['id'] ?? '').toString().trim(),
    ]..removeWhere((e) => e.isEmpty);

    final events = matchIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : (await _client
                  .from('match_events')
                  .select()
                  .inFilter('match_id', matchIds))
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
    final stats = await _aggregateSeasonStats(seasonId, events);
    _statsCache[seasonId] = stats;
    return stats;
  }

  /// [events] yalnızca bu sezonun maç olaylarıdır.
  Future<List<PlayerStats>> _aggregateSeasonStats(
    String seasonId,
    List<Map<String, dynamic>> events,
  ) async {
    // key: player_id
    final goals = <String, int>{};
    final assists = <String, int>{};
    final yellows = <String, int>{};
    final reds = <String, int>{};
    final motm = <String, int>{};
    final matchesByPlayer = <String, Set<String>>{};
    final teamByPlayer = <String, String>{};

    void bump(Map<String, int> m, String pid) {
      if (pid.isEmpty) return;
      m[pid] = (m[pid] ?? 0) + 1;
    }

    for (final e in events) {
      final type = (e['event_type'] ?? '').toString().trim();
      final pid = (e['player_id'] ?? '').toString().trim();
      final aid = (e['assist_player_id'] ?? '').toString().trim();
      final mid = (e['match_id'] ?? '').toString().trim();
      final tid = (e['team_id'] ?? '').toString().trim();
      final ownGoal = e['is_own_goal'] == true;
      if (pid.isNotEmpty) {
        matchesByPlayer.putIfAbsent(pid, () => <String>{}).add(mid);
        if (tid.isNotEmpty) teamByPlayer.putIfAbsent(pid, () => tid);
      }
      switch (type) {
        case 'goal':
          if (!ownGoal) bump(goals, pid);
          if (aid.isNotEmpty) {
            bump(assists, aid);
            matchesByPlayer.putIfAbsent(aid, () => <String>{}).add(mid);
            if (tid.isNotEmpty) teamByPlayer.putIfAbsent(aid, () => tid);
          }
          break;
        case 'assist':
          bump(assists, pid);
          break;
        case 'yellow_card':
          bump(yellows, pid);
          break;
        case 'red_card':
          bump(reds, pid);
          break;
        case 'man_of_the_match':
          bump(motm, pid);
          break;
      }
    }

    // Sezonda hiç olay yoksa kayıtlı sezon istatistiklerine düş.
    final fallbackRows = <Map<String, dynamic>>[];
    if (events.isEmpty) {
      try {
        final res = await _client
            .from('player_season_stats')
            .select()
            .eq('season_id', seasonId);
        for (final any in res) {
          fallbackRows.add((any as Map).cast<String, dynamic>());
        }
      } catch (_) {}
    }

    final playerIds = events.isEmpty
        ? {for (final r in fallbackRows) (r['player_id'] ?? '').toString()}
        : matchesByPlayer.keys.toSet();
    playerIds.remove('');
    if (playerIds.isEmpty) return const <PlayerStats>[];

    // Ekranlar oyuncuyu "playerPhone" ile arar; telefon yoksa id kullanılır
    // (getPlayerByPhoneOnce ikisini de çözer).
    final keyById = <String, String>{};
    try {
      final res = await _client
          .from('players')
          .select('id, phone')
          .inFilter('id', playerIds.toList());
      for (final any in res) {
        final r = (any as Map).cast<String, dynamic>();
        final id = (r['id'] ?? '').toString();
        final phone = (r['phone'] ?? '').toString().trim();
        keyById[id] = phone.isEmpty ? id : phone;
      }
    } catch (_) {}

    int readInt(dynamic v) =>
        v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

    final list = <PlayerStats>[];
    for (final pid in playerIds) {
      final key = keyById[pid] ?? pid;
      if (events.isEmpty) {
        final r = fallbackRows.firstWhere(
          (row) => (row['player_id'] ?? '').toString() == pid,
        );
        list.add(
          PlayerStats(
            id: PlayerStats.docId(playerPhone: key, tournamentId: seasonId),
            playerPhone: key,
            tournamentId: seasonId,
            teamId: '',
            matchesPlayed: readInt(r['matches_played']),
            goals: readInt(r['goals']),
            assists: readInt(r['assists']),
            yellowCards: readInt(r['yellow_cards']),
            redCards: readInt(r['red_cards']),
          ),
        );
        continue;
      }
      list.add(
        PlayerStats(
          id: PlayerStats.docId(playerPhone: key, tournamentId: seasonId),
          playerPhone: key,
          tournamentId: seasonId,
          teamId: teamByPlayer[pid] ?? '',
          matchesPlayed: matchesByPlayer[pid]?.length ?? 0,
          goals: goals[pid] ?? 0,
          assists: assists[pid] ?? 0,
          yellowCards: yellows[pid] ?? 0,
          redCards: reds[pid] ?? 0,
          manOfTheMatch: motm[pid] ?? 0,
        ),
      );
    }
    list.sort((a, b) => b.goals.compareTo(a.goals));
    return list;
  }

  @override
  Future<void> commitPlayerStatsForCompletedMatch({required String matchId}) {
    final id = matchId.trim();
    if (id.isEmpty) return Future.value();

    int readInt(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      final s = v.toString().replaceAll('\u0000', '').trim();
      return int.tryParse(s) ??
          double.tryParse(s.replaceAll(',', '.'))?.toInt() ??
          0;
    }

    List<String> asPhones(dynamic v) {
      if (v is! List) return const <String>[];
      return v
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return Future(() async {
      Map<String, dynamic>? match;
      try {
        AppConfig.sqlLogStart(
          table: 'matches',
          operation: 'SELECT',
          filters: 'id=$id | limit=1',
        );
        final res = await _client
            .from('matches')
            .select()
            .eq('id', id)
            .limit(1);
        if (res.isEmpty) {
          AppConfig.sqlLogResult(
            table: 'matches',
            operation: 'SELECT',
            count: 0,
          );
          return;
        }
        AppConfig.sqlLogResult(table: 'matches', operation: 'SELECT', count: 1);
        match = (res.first as Map).cast<String, dynamic>();
      } catch (e) {
        AppConfig.sqlLogResult(table: 'matches', operation: 'SELECT', error: e);
        return;
      }

      final status = (match['status'] ?? '').toString().trim();
      final finished =
          match['is_completed'] == true ||
          status == MatchStatus.finished.name ||
          status.toLowerCase() == 'completed' ||
          status.toLowerCase() == 'finished';
      if (!finished) return;
      if (match['stats_committed_at'] != null ||
          match['stats_committed'] == true) {
        return;
      }

      final tournamentId = (match['league_id'] ?? '').toString().trim();
      if (tournamentId.isEmpty) return;

      final homeTeamId = (match['home_team_id'] ?? '').toString().trim();
      final awayTeamId = (match['away_team_id'] ?? '').toString().trim();
      final homeLineup = asPhones(match['home_lineup']);
      final awayLineup = asPhones(match['away_lineup']);
      if (homeTeamId.isEmpty || awayTeamId.isEmpty) return;

      final deltas = <String, Map<String, int>>{};
      final teamByPhone = <String, String>{};

      void ensurePhone(String phone, {required String teamId}) {
        final p = phone.trim();
        if (p.isEmpty) return;
        deltas.putIfAbsent(p, () => <String, int>{});
        teamByPhone.putIfAbsent(p, () => teamId);
      }

      for (final p in homeLineup) {
        ensurePhone(p, teamId: homeTeamId);
        deltas[p]!['matches_played'] = (deltas[p]!['matches_played'] ?? 0) + 1;
      }
      for (final p in awayLineup) {
        ensurePhone(p, teamId: awayTeamId);
        deltas[p]!['matches_played'] = (deltas[p]!['matches_played'] ?? 0) + 1;
      }

      try {
        AppConfig.sqlLogStart(
          table: 'match_events',
          operation: 'SELECT',
          filters: 'match_id=$id',
        );
        final eventsRes = await _client
            .from('match_events')
            .select('event_type, team_id, player_id, assist_player_id')
            .eq('match_id', id);
        AppConfig.sqlLogResult(
          table: 'match_events',
          operation: 'SELECT',
          count: eventsRes.length,
        );
        for (final rowAny in eventsRes) {
          final e = (rowAny as Map).cast<String, dynamic>();
          final eventType = (e['event_type'] ?? '').toString().trim();
          final teamId = (e['team_id'] ?? '').toString().trim();
          final playerPhone = (e['player_id'] ?? '').toString().trim();
          final assistPhone = (e['assist_player_id'] ?? '').toString().trim();

          void bump(
            String phone,
            String field, {
            int by = 1,
            String? teamIdOverride,
          }) {
            final p = phone.trim();
            if (p.isEmpty) return;
            ensurePhone(
              p,
              teamId: (teamIdOverride ?? teamId).trim().isEmpty
                  ? (teamByPhone[p] ?? '')
                  : (teamIdOverride ?? teamId),
            );
            deltas[p]![field] = (deltas[p]![field] ?? 0) + by;
          }

          switch (eventType) {
            case 'goal':
              bump(playerPhone, 'goals');
              if (assistPhone.isNotEmpty) bump(assistPhone, 'assists');
              break;
            case 'assist':
              bump(playerPhone, 'assists');
              break;
            case 'yellow_card':
              bump(playerPhone, 'yellow_cards');
              break;
            case 'red_card':
              bump(playerPhone, 'red_cards');
              break;
            case 'man_of_the_match':
              bump(playerPhone, 'man_of_the_match');
              break;
          }
        }
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'match_events',
          operation: 'SELECT',
          error: e,
        );
      }

      final phones = deltas.keys.toList();
      if (phones.isEmpty) return;
      final statIds = phones
          .map(
            (p) =>
                PlayerStats.docId(playerPhone: p, tournamentId: tournamentId),
          )
          .toList();

      final existingById = <String, Map<String, dynamic>>{};
      try {
        AppConfig.sqlLogStart(
          table: 'player_stats',
          operation: 'SELECT',
          filters: 'id IN (${statIds.length})',
        );
        final res = await _client
            .from('player_stats')
            .select()
            .inFilter('id', statIds);
        AppConfig.sqlLogResult(
          table: 'player_stats',
          operation: 'SELECT',
          count: res.length,
        );
        for (final rowAny in res) {
          final row = (rowAny as Map).cast<String, dynamic>();
          final rid = (row['id'] ?? '').toString();
          if (rid.isNotEmpty) existingById[rid] = row;
        }
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'player_stats',
          operation: 'SELECT',
          error: e,
        );
      }

      final nowIso = DateTime.now().toIso8601String();
      final upserts = <Map<String, dynamic>>[];
      for (final phone in phones) {
        final statsId = PlayerStats.docId(
          playerPhone: phone,
          tournamentId: tournamentId,
        );
        final teamId = (teamByPhone[phone] ?? '').trim();
        final existing = existingById[statsId] ?? const <String, dynamic>{};
        final next = <String, dynamic>{
          'id': statsId,
          'player_phone': phone,
          'league_id': tournamentId,
          'team_id': teamId,
          'matches_played':
              readInt(existing['matches_played']) +
              (deltas[phone]!['matches_played'] ?? 0),
          'goals': readInt(existing['goals']) + (deltas[phone]!['goals'] ?? 0),
          'assists':
              readInt(existing['assists']) + (deltas[phone]!['assists'] ?? 0),
          'yellow_cards':
              readInt(existing['yellow_cards']) +
              (deltas[phone]!['yellow_cards'] ?? 0),
          'red_cards':
              readInt(existing['red_cards']) +
              (deltas[phone]!['red_cards'] ?? 0),
          'man_of_the_match':
              readInt(existing['man_of_the_match']) +
              (deltas[phone]!['man_of_the_match'] ?? 0),
          'updated_at': nowIso,
          if (existing.isEmpty) 'created_at': nowIso,
        };
        upserts.add(next);
      }

      try {
        AppConfig.sqlLogStart(
          table: 'player_stats',
          operation: 'UPSERT',
          filters: 'onConflict=id | rows=${upserts.length}',
        );
        await _client.from('player_stats').upsert(upserts, onConflict: 'id');
        AppConfig.sqlLogResult(
          table: 'player_stats',
          operation: 'UPSERT',
          count: upserts.length,
        );
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'player_stats',
          operation: 'UPSERT',
          error: e,
        );
      }

      try {
        AppConfig.sqlLogStart(
          table: 'matches',
          operation: 'UPDATE',
          filters: 'id=$id | stats_committed=true',
        );
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPDATE', count: 0);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPDATE', error: e);
      }
    });
  }

  @override
  Future<void> importTeamsAndFixture({
    required String tournamentId,
    required List<FixtureImportTeam> teams,
    required List<FixtureImportMatch> matches,
  }) {
    final tId = tournamentId.trim();
    if (tId.isEmpty) return Future.value();

    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'teams',
          operation: 'INSERT',
          filters: 'rows=${teams.length} | league_id=$tId',
        );
        for (final team in teams) {
          final name = team.name.trim();
          if (name.isEmpty) continue;
          await _client.from('teams').insert({
            'league_id': tId,
            'name': name,
            'group_name': team.groupName.trim(),
          });
        }

        final teamsRes = await _client
            .from('teams')
            .select('id, name')
            .eq('league_id', tId);
        final teamIdByName = <String, String>{};
        for (final rowAny in teamsRes) {
          final row = (rowAny as Map).cast<String, dynamic>();
          final id = (row['id'] ?? '').toString().trim();
          final name = (row['name'] ?? '').toString().trim().toLowerCase();
          if (id.isNotEmpty && name.isNotEmpty) {
            teamIdByName[name] = id;
          }
        }

        AppConfig.sqlLogStart(
          table: 'matches',
          operation: 'INSERT',
          filters: 'rows=${matches.length} | league_id=$tId',
        );
        for (final m in matches) {
          final homeId = teamIdByName[m.homeTeamName.trim().toLowerCase()];
          final awayId = teamIdByName[m.awayTeamName.trim().toLowerCase()];
          DateTime? matchDateTime;
          final dateStr = (m.matchDateYyyyMmDd ?? '').trim();
          final timeStr = (m.matchTime ?? '').trim();
          if (dateStr.isNotEmpty && timeStr.isNotEmpty) {
            matchDateTime = DateTime.tryParse('${dateStr}T$timeStr:00');
          }
          matchDateTime ??= (dateStr.isEmpty
              ? null
              : DateTime.tryParse(dateStr));
          await _client.from('matches').insert({
            'league_id': tId,
            'week': m.week,
            'home_team_id': homeId,
            'away_team_id': awayId,
            'match_date': matchDateTime?.toIso8601String(),
            'is_completed': false,
            'home_score': 0,
            'away_score': 0,
          });
        }
        AppConfig.sqlLogResult(
          table: 'matches',
          operation: 'INSERT',
          count: matches.length,
        );
      } catch (e) {
        AppConfig.sqlLogResult(table: 'matches', operation: 'INSERT', error: e);
      }
    });
  }

  @override
  Future<int> deleteAllMatchesAndEvents() async {
    var total = 0;
    try {
      AppConfig.sqlLogStart(
        table: 'match_events',
        operation: 'DELETE',
        filters: 'all_rows',
      );
      final res = await _client.from('match_events').delete().neq('id', '');
      final deleted = res is List ? res.length : 0;
      total += deleted;
      AppConfig.sqlLogResult(
        table: 'match_events',
        operation: 'DELETE',
        count: deleted,
      );
    } catch (e) {
      AppConfig.sqlLogResult(
        table: 'match_events',
        operation: 'DELETE',
        error: e,
      );
    }

    try {
      AppConfig.sqlLogStart(
        table: 'matches',
        operation: 'DELETE',
        filters: 'all_rows',
      );
      final res = await _client.from('matches').delete().neq('id', '');
      final deleted = res is List ? res.length : 0;
      total += deleted;
      AppConfig.sqlLogResult(
        table: 'matches',
        operation: 'DELETE',
        count: deleted,
      );
    } catch (e) {
      AppConfig.sqlLogResult(table: 'matches', operation: 'DELETE', error: e);
    }

    return total;
  }

  @override
  Future<Map<String, int>> migrateMatchesTimeTimestampToMatchFields() async {
    return {'scanned': 0, 'updated': 0};
  }

  @override
  Future<Map<String, int>> normalizeMatchesDocIdsByLeagueWeekHomeTeam() async {
    return {
      'scanned': 0,
      'skipped': 0,
      'rewritten': 0,
      'deleted': 0,
      'merged': 0,
      'eventsMoved': 0,
      'matchEventsUpdated': 0,
    };
  }

  @override
  Future<void> deleteMatchMedia(String mediaId) async {
    await _client.from('match_media').delete().eq('id', mediaId);
  }

  @override
  Future<bool> hasBroadcast(String matchId) async {
    final id = matchId.trim();
    if (id.isEmpty) return false;
    try {
      AppConfig.sqlLogStart(
        table: 'match_media',
        operation: 'SELECT',
        filters: 'match_id=$id | media_type=Maç Yayın Linki',
      );
      final res = await _client
          .from('match_media')
          .select('id')
          .eq('match_id', id)
          .eq('media_type', 'Maç Yayın Linki')
          .limit(1);
      AppConfig.sqlLogResult(
        table: 'match_media',
        operation: 'SELECT',
        count: res.length,
      );
      return res.isNotEmpty;
    } catch (e) {
      AppConfig.sqlLogResult(
        table: 'match_media',
        operation: 'SELECT',
        error: e,
      );
      return false;
    }
  }

  @override
  Future<String?> getBroadcastUrl(String matchId) async {
    final id = matchId.trim();
    if (id.isEmpty) return null;
    try {
      AppConfig.sqlLogStart(
        table: 'match_media',
        operation: 'SELECT',
        filters: 'match_id=$id | media_type=Maç Yayın Linki | url',
      );
      final res = await _client
          .from('match_media')
          .select('url')
          .eq('match_id', id)
          .eq('media_type', 'Maç Yayın Linki')
          .limit(1);
      AppConfig.sqlLogResult(
        table: 'match_media',
        operation: 'SELECT',
        count: res.length,
      );
      if (res.isNotEmpty) {
        final row = (res.first as Map).cast<String, dynamic>();
        return row['url']?.toString();
      }
      return null;
    } catch (e) {
      AppConfig.sqlLogResult(
        table: 'match_media',
        operation: 'SELECT',
        error: e,
      );
      return null;
    }
  }
}
