import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

import '../interfaces/i_match_service.dart';
import '../../config/app_config.dart';
import '../../models/fixture_import.dart';
import '../../models/match.dart';
import '../../models/player_stats.dart';

class SupabaseMatchService implements IMatchService {
  SupabaseMatchService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  int _readInt(dynamic v, {required int fallback}) {
    if (v == null) return fallback;
    if (v is num) return v.toInt();
    final s = v.toString().replaceAll('\u0000', '').trim();
    return int.tryParse(s) ?? double.tryParse(s.replaceAll(',', '.'))?.toInt() ?? fallback;
  }

  Future<int> _readMatchPeriodDurationMinutes(String tournamentId) async {
    final id = tournamentId.trim();
    if (id.isEmpty) return 25;
    try {
      AppConfig.sqlLogStart(
        table: 'leagues',
        operation: 'SELECT',
        filters: 'id=$id | columns=match_period_duration | limit=1',
      );
      final res = await _client
          .from('leagues')
          .select('match_period_duration, id')
          .eq('id', id)
          .limit(1);
      if (res is List && res.isNotEmpty) {
        AppConfig.sqlLogResult(table: 'leagues', operation: 'SELECT', count: 1);
        final row = (res.first as Map).cast<String, dynamic>();
        final minutes = _readInt(row['match_period_duration'], fallback: 25);
        return minutes <= 0 ? 25 : minutes;
      }
      AppConfig.sqlLogResult(table: 'leagues', operation: 'SELECT', count: 0);
      return 25;
    } catch (e) {
      AppConfig.sqlLogResult(table: 'leagues', operation: 'SELECT', error: e);
      return 25;
    }
  }

  DateTime? _readDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  @override
  Stream<List<MatchModel>> watchMatchesForLeague(String leagueId) {
    final id = leagueId.trim();
    if (id.isEmpty) return const Stream<List<MatchModel>>.empty();
    try {
      AppConfig.sqlLogStart(
        table: 'matches',
        operation: 'STREAM',
        filters: 'primaryKey=id | clientFilter=tournament_id|league_id=$id | order=match_date asc',
      );
      return _client
          .from('matches')
          .stream(primaryKey: ['id'])
          .order('match_date', ascending: true)
          .map((rows) {
            final filtered = rows.where((r) {
              final tid = (r['tournament_id'] ?? r['league_id'] ?? '').toString().trim();
              return tid == id;
            });
            return filtered
                .map((r) => MatchModel.fromMap(Map<String, dynamic>.from(r), (r['id'] ?? '').toString()))
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

  @override
  Stream<List<MatchModel>> watchFixtureMatches(
    String leagueId,
    int week, {
    String? groupId,
  }) {
    final id = leagueId.trim();
    final gId = (groupId ?? '').trim();
    if (id.isEmpty) return const Stream<List<MatchModel>>.empty();
    return watchMatchesForLeague(id).map((list) {
      return list.where((m) {
        final okWeek = (m.week ?? -1) == week;
        if (!okWeek) return false;
        if (gId.isEmpty) return true;
        return (m.groupId ?? '').trim() == gId;
      }).toList();
    });
  }

  @override
  Future<int?> getFixtureMaxWeek(String leagueId, {String? groupId}) {
    final id = leagueId.trim();
    final gId = (groupId ?? '').trim();
    if (id.isEmpty) return Future.value(null);
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'matches',
          operation: 'SELECT',
          filters: 'columns=week,tournament_id,group_id',
        );
        final res = await _client.from('matches').select('week, tournament_id, group_id');
        if (res is! List) {
          AppConfig.sqlLogResult(table: 'matches', operation: 'SELECT', count: 0);
          return null;
        }
        AppConfig.sqlLogResult(table: 'matches', operation: 'SELECT', count: res.length);
        int? maxWeek;
        for (final rowAny in res) {
          final row = (rowAny as Map).cast<String, dynamic>();
          final tid = (row['tournament_id'] ?? '').toString().trim();
          if (tid != id) continue;
          if (gId.isNotEmpty && (row['group_id'] ?? '').toString().trim() != gId) continue;
          final w = row['week'];
          final ww = w is num ? w.toInt() : int.tryParse(w?.toString() ?? '');
          if (ww == null) continue;
          maxWeek = maxWeek == null ? ww : (ww > maxWeek! ? ww : maxWeek);
        }
        return maxWeek;
      } catch (e) {
        AppConfig.sqlLogResult(table: 'matches', operation: 'SELECT', error: e);
        return null;
      }
    });
  }

  @override
  Stream<MatchModel> watchMatch(String matchId) {
    final id = matchId.trim();
    if (id.isEmpty) return const Stream<MatchModel>.empty();
    try {
      AppConfig.sqlLogStart(
        table: 'matches',
        operation: 'STREAM',
        filters: 'primaryKey=id | clientFilter=id=$id',
      );
      return _client.from('matches').stream(primaryKey: ['id']).map((rows) {
        final row = rows.cast<Map<String, dynamic>>().firstWhere(
          (r) => (r['id'] ?? '').toString().trim() == id,
          orElse: () => const <String, dynamic>{},
        );
        return MatchModel.fromMap(row, id);
      });
    } catch (e) {
      AppConfig.sqlLogResult(table: 'matches', operation: 'STREAM', error: e);
      return const Stream<MatchModel>.empty();
    }
  }

  @override
  Stream<List<Map<String, dynamic>>> watchInlineMatchEvents(String matchId) {
    final id = matchId.trim();
    if (id.isEmpty) return const Stream<List<Map<String, dynamic>>>.empty();
    try {
      AppConfig.sqlLogStart(
        table: 'match_events',
        operation: 'STREAM',
        filters: 'primaryKey=id | clientFilter=match_id=$id | order=minute asc',
      );
      return _client
          .from('match_events')
          .stream(primaryKey: ['id'])
          .order('minute', ascending: true)
          .map((rows) {
            final filtered = rows.where((r) => (r['match_id'] ?? '').toString().trim() == id);
            return filtered.map((r) => Map<String, dynamic>.from(r)).toList();
          });
    } catch (e) {
      AppConfig.sqlLogResult(table: 'match_events', operation: 'STREAM', error: e);
      return const Stream<List<Map<String, dynamic>>>.empty();
    }
  }

  @override
  Future<String> addMatch(MatchModel match) {
    return Future(() async {
      try {
        AppConfig.sqlLogStart(table: 'matches', operation: 'INSERT');
        final payload = match.toMap(snakeCase: true);
        payload['created_at'] = DateTime.now().toIso8601String();
        final res = await _client.from('matches').insert(payload).select('id').limit(1);
        if (res is List && res.isNotEmpty) {
          final row = (res.first as Map).cast<String, dynamic>();
          AppConfig.sqlLogResult(table: 'matches', operation: 'INSERT', count: 1);
          return (row['id'] ?? '').toString();
        }
        AppConfig.sqlLogResult(table: 'matches', operation: 'INSERT', count: 0);
        return '';
      } catch (e) {
        AppConfig.sqlLogResult(table: 'matches', operation: 'INSERT', error: e);
        return '';
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
        AppConfig.sqlLogResult(table: 'match_events', operation: 'INSERT', count: 1);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'match_events', operation: 'INSERT', error: e);
      }

      if (event.type != 'goal') return;

      try {
        AppConfig.sqlLogStart(
          table: 'matches',
          operation: 'SELECT',
          filters: 'id=${event.matchId} | columns=home_team_id,away_team_id,score,home_score,away_score | limit=1',
        );
        final res = await _client
            .from('matches')
            .select('home_team_id, away_team_id, score, home_score, away_score')
            .eq('id', event.matchId)
            .limit(1);
        if (res is! List || res.isEmpty) {
          AppConfig.sqlLogResult(table: 'matches', operation: 'SELECT', count: 0);
          return;
        }
        AppConfig.sqlLogResult(table: 'matches', operation: 'SELECT', count: 1);
        final row = (res.first as Map).cast<String, dynamic>();
        final homeTeamId = (row['home_team_id'] ?? '').toString().trim();
        final awayTeamId = (row['away_team_id'] ?? '').toString().trim();
        final scoringTeamId = event.isOwnGoal
            ? (event.teamId == homeTeamId ? awayTeamId : homeTeamId)
            : event.teamId;
        final isHome = scoringTeamId == homeTeamId;
        final isAway = scoringTeamId == awayTeamId;
        if (!isHome && !isAway) return;

        final scoreRaw = row['score'];
        final scoreMap =
            (scoreRaw is Map) ? Map<String, dynamic>.from(scoreRaw) : <String, dynamic>{};
        final ftRaw = scoreMap['fullTime'] ?? scoreMap['full_time'];
        final ft = (ftRaw is Map) ? Map<String, dynamic>.from(ftRaw) : <String, dynamic>{};
        final currentHome = _readInt(ft['home'] ?? row['home_score'], fallback: 0);
        final currentAway = _readInt(ft['away'] ?? row['away_score'], fallback: 0);
        final nextHome = isHome ? currentHome + 1 : currentHome;
        final nextAway = isAway ? currentAway + 1 : currentAway;

        scoreMap['fullTime'] = {'home': nextHome, 'away': nextAway};

        AppConfig.sqlLogStart(
          table: 'matches',
          operation: 'UPDATE',
          filters: 'id=${event.matchId} | home_score=$nextHome, away_score=$nextAway',
        );
        await _client.from('matches').update({
          'score': scoreMap,
          'home_score': nextHome,
          'away_score': nextAway,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', event.matchId);
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPDATE', count: 1);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPDATE', error: e);
      }
    });
  }

  @override
  Future<void> updateMatchYoutubeUrl({
    required String matchId,
    required String? youtubeUrl,
  }) {
    final id = matchId.trim();
    if (id.isEmpty) return Future.value();
    return Future(() async {
      try {
        AppConfig.sqlLogStart(table: 'matches', operation: 'UPSERT', filters: 'onConflict=id | id=$id');
        await _client.from('matches').upsert({
          'id': id,
          'youtube_url': (youtubeUrl ?? '').trim().isEmpty ? null : youtubeUrl!.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'id');
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPSERT', count: 1);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPSERT', error: e);
      }
    });
  }

  @override
  Future<void> updateMatchPitchName({
    required String matchId,
    required String? pitchName,
  }) {
    final id = matchId.trim();
    if (id.isEmpty) return Future.value();
    return Future(() async {
      try {
        AppConfig.sqlLogStart(table: 'matches', operation: 'UPSERT', filters: 'onConflict=id | id=$id');
        await _client.from('matches').upsert({
          'id': id,
          'pitch_name': (pitchName ?? '').trim().isEmpty ? null : pitchName!.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'id');
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPSERT', count: 1);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPSERT', error: e);
      }
    });
  }

  @override
  Future<void> updateMatchHighlightPhotoUrl({
    required String matchId,
    required bool isHome,
    required String? photoUrl,
  }) {
    final id = matchId.trim();
    if (id.isEmpty) return Future.value();
    final url = (photoUrl ?? '').trim();
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'matches',
          operation: 'UPSERT',
          filters: 'onConflict=id | id=$id',
        );
        await _client.from('matches').upsert({
          'id': id,
          isHome ? 'home_highlight_photo_url' : 'away_highlight_photo_url': url.isEmpty ? null : url,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'id');
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPSERT', count: 1);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPSERT', error: e);
      }
    });
  }

  @override
  Future<void> updateMatchSchedule({
    required String matchId,
    required String matchDateDb,
    required String matchTime,
    required String? pitchName,
  }) {
    final id = matchId.trim();
    if (id.isEmpty) return Future.value();
    final dateStr = matchDateDb.trim();
    final timeStr = matchTime.trim();
    return Future(() async {
      try {
        AppConfig.sqlLogStart(table: 'matches', operation: 'UPSERT', filters: 'onConflict=id | id=$id');
        await _client.from('matches').upsert({
          'id': id,
          'match_date': dateStr.isEmpty ? null : dateStr,
          'match_time': timeStr.isEmpty ? null : timeStr,
          'pitch_name': (pitchName ?? '').trim().isEmpty ? null : pitchName!.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'id');
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPSERT', count: 1);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPSERT', error: e);
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
    final phones = [
      ...lineup.starting.map((p) => p.playerId.trim()),
      ...lineup.subs.map((p) => p.playerId.trim()),
    ].where((e) => e.isNotEmpty).toList();
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'matches',
          operation: 'UPSERT',
          filters: 'onConflict=id | id=$id',
        );
        await _client.from('matches').upsert({
          'id': id,
          isHome ? 'home_lineup' : 'away_lineup': phones,
          isHome ? 'home_lineup_detail' : 'away_lineup_detail': lineup.toMap(),
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'id');
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPSERT', count: 1);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPSERT', error: e);
      }
    });
  }

  @override
  Future<void> updateMatchFormationState({
    required String matchId,
    String? homeFormation,
    String? awayFormation,
    List<String>? homeOrder,
    List<String>? awayOrder,
  }) {
    final id = matchId.trim();
    if (id.isEmpty) return Future.value();
    final data = <String, dynamic>{'id': id};
    if (homeFormation != null) {
      final f = homeFormation.trim();
      data['home_formation'] = f.isEmpty ? null : f;
    }
    if (awayFormation != null) {
      final f = awayFormation.trim();
      data['away_formation'] = f.isEmpty ? null : f;
    }
    if (homeOrder != null) {
      data['home_formation_order'] =
          homeOrder.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }
    if (awayOrder != null) {
      data['away_formation_order'] =
          awayOrder.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }
    if (data.length <= 1) return Future.value();
    data['updated_at'] = DateTime.now().toIso8601String();
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'matches',
          operation: 'UPSERT',
          filters: 'onConflict=id | id=$id',
        );
        await _client.from('matches').upsert(data, onConflict: 'id');
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPSERT', count: 1);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPSERT', error: e);
      }
    });
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
      String tournamentId = '';
      String homeTeamId = '';
      try {
        AppConfig.sqlLogStart(
          table: 'matches',
          operation: 'SELECT',
          filters: 'id=$id | columns=tournament_id,league_id,home_team_id | limit=1',
        );
        final res = await _client
            .from('matches')
            .select('tournament_id, league_id, home_team_id')
            .eq('id', id)
            .limit(1);
        if (res is List && res.isNotEmpty) {
          AppConfig.sqlLogResult(table: 'matches', operation: 'SELECT', count: 1);
          final row = (res.first as Map).cast<String, dynamic>();
          tournamentId = (row['tournament_id'] ?? row['league_id'] ?? '').toString().trim();
          homeTeamId = (row['home_team_id'] ?? '').toString().trim();
        }
      } catch (e) {
        AppConfig.sqlLogResult(table: 'matches', operation: 'SELECT', error: e);
      }

      try {
        AppConfig.sqlLogStart(
          table: 'matches',
          operation: 'UPSERT',
          filters: 'onConflict=id | id=$id',
        );
        await _client.from('matches').upsert({
          'id': id,
          'home_score': homeScore,
          'away_score': awayScore,
          'status': 'finished',
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'id');
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPSERT', count: 1);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPSERT', error: e);
      }

      final period = await _readMatchPeriodDurationMinutes(tournamentId);
      final createdAt = DateTime.now().toIso8601String();
      try {
        AppConfig.sqlLogStart(
          table: 'match_events',
          operation: 'INSERT',
          filters: 'match_id=$id | 3 status events',
        );
        await _client.from('match_events').insert([
          {
            'match_id': id,
            'tournament_id': tournamentId.isEmpty ? null : tournamentId,
            'team_id': homeTeamId.isEmpty ? null : homeTeamId,
            'event_type': 'status',
            'type': 'status',
            'minute': 0,
            'player_name': 'Maç Başladı',
            'created_at': createdAt,
          },
          {
            'match_id': id,
            'tournament_id': tournamentId.isEmpty ? null : tournamentId,
            'team_id': homeTeamId.isEmpty ? null : homeTeamId,
            'event_type': 'status',
            'type': 'status',
            'minute': period,
            'player_name': 'İlk Yarı Bitti',
            'created_at': createdAt,
          },
          {
            'match_id': id,
            'tournament_id': tournamentId.isEmpty ? null : tournamentId,
            'team_id': homeTeamId.isEmpty ? null : homeTeamId,
            'event_type': 'status',
            'type': 'status',
            'minute': period * 2,
            'player_name': 'Maç Bitti',
            'created_at': createdAt,
          },
        ]);
        AppConfig.sqlLogResult(table: 'match_events', operation: 'INSERT', count: 3);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'match_events', operation: 'INSERT', error: e);
      }
    });
  }

  @override
  Stream<List<PlayerStats>> watchPlayerStats({required String tournamentId}) {
    final id = tournamentId.trim();
    if (id.isEmpty) return const Stream<List<PlayerStats>>.empty();
    try {
      AppConfig.sqlLogStart(
        table: 'player_stats',
        operation: 'STREAM',
        filters: 'primaryKey=id | clientFilter=tournament_id=$id',
      );
      return _client.from('player_stats').stream(primaryKey: ['id']).map((rows) {
        final filtered = rows.where((r) {
          final tid = (r['tournament_id'] ?? r['league_id'] ?? '').toString().trim();
          return tid == id;
        });
        final list = filtered
            .map((r) => PlayerStats.fromMap(Map<String, dynamic>.from(r), (r['id'] ?? '').toString()))
            .toList();
        list.sort((a, b) => b.goals.compareTo(a.goals));
        return list;
      });
    } catch (e) {
      AppConfig.sqlLogResult(table: 'player_stats', operation: 'STREAM', error: e);
      return const Stream<List<PlayerStats>>.empty();
    }
  }

  @override
  Future<void> commitPlayerStatsForCompletedMatch({required String matchId}) {
    final id = matchId.trim();
    if (id.isEmpty) return Future.value();

    int readInt(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      final s = v.toString().replaceAll('\u0000', '').trim();
      return int.tryParse(s) ?? double.tryParse(s.replaceAll(',', '.'))?.toInt() ?? 0;
    }

    List<String> asPhones(dynamic v) {
      if (v is! List) return const <String>[];
      return v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }

    return Future(() async {
      Map<String, dynamic>? match;
      try {
        AppConfig.sqlLogStart(
          table: 'matches',
          operation: 'SELECT',
          filters: 'id=$id | limit=1',
        );
        final res = await _client.from('matches').select().eq('id', id).limit(1);
        if (res is! List || res.isEmpty) {
          AppConfig.sqlLogResult(table: 'matches', operation: 'SELECT', count: 0);
          return;
        }
        AppConfig.sqlLogResult(table: 'matches', operation: 'SELECT', count: 1);
        match = (res.first as Map).cast<String, dynamic>();
      } catch (e) {
        AppConfig.sqlLogResult(table: 'matches', operation: 'SELECT', error: e);
        return;
      }

      final status = (match?['status'] ?? '').toString().trim();
      final finished = status == MatchStatus.finished.name || status.toLowerCase() == 'completed' || status.toLowerCase() == 'finished';
      if (!finished) return;
      if (match?['stats_committed_at'] != null || match?['stats_committed'] == true) return;

      final tournamentId =
          (match?['tournament_id'] ?? match?['league_id'] ?? '').toString().trim();
      if (tournamentId.isEmpty) return;

      final homeTeamId = (match?['home_team_id'] ?? '').toString().trim();
      final awayTeamId = (match?['away_team_id'] ?? '').toString().trim();
      final homeLineup = asPhones(match?['home_lineup']);
      final awayLineup = asPhones(match?['away_lineup']);
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
        AppConfig.sqlLogStart(table: 'match_events', operation: 'SELECT', filters: 'match_id=$id');
        final eventsRes = await _client
            .from('match_events')
            .select('event_type, type, team_id, player_phone, assist_player_phone')
            .eq('match_id', id);
        if (eventsRes is List) {
          AppConfig.sqlLogResult(table: 'match_events', operation: 'SELECT', count: eventsRes.length);
          for (final rowAny in eventsRes) {
            final e = (rowAny as Map).cast<String, dynamic>();
            final eventType = (e['event_type'] ?? e['type'] ?? '').toString().trim();
            final teamId = (e['team_id'] ?? '').toString().trim();
            final playerPhone = (e['player_phone'] ?? '').toString().trim();
            final assistPhone = (e['assist_player_phone'] ?? '').toString().trim();

            void bump(String phone, String field, {int by = 1, String? teamIdOverride}) {
              final p = phone.trim();
              if (p.isEmpty) return;
              ensurePhone(p, teamId: (teamIdOverride ?? teamId).trim().isEmpty ? (teamByPhone[p] ?? '') : (teamIdOverride ?? teamId));
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
        } else {
          AppConfig.sqlLogResult(table: 'match_events', operation: 'SELECT', count: 0);
        }
      } catch (e) {
        AppConfig.sqlLogResult(table: 'match_events', operation: 'SELECT', error: e);
      }

      final phones = deltas.keys.toList();
      if (phones.isEmpty) return;
      final statIds = phones.map((p) => PlayerStats.docId(playerPhone: p, tournamentId: tournamentId)).toList();

      final existingById = <String, Map<String, dynamic>>{};
      try {
        AppConfig.sqlLogStart(table: 'player_stats', operation: 'SELECT', filters: 'id IN (${statIds.length})');
        final res = await _client
            .from('player_stats')
            .select()
            .inFilter('id', statIds);
        if (res is List) {
          AppConfig.sqlLogResult(table: 'player_stats', operation: 'SELECT', count: res.length);
          for (final rowAny in res) {
            final row = (rowAny as Map).cast<String, dynamic>();
            final rid = (row['id'] ?? '').toString();
            if (rid.isNotEmpty) existingById[rid] = row;
          }
        } else {
          AppConfig.sqlLogResult(table: 'player_stats', operation: 'SELECT', count: 0);
        }
      } catch (e) {
        AppConfig.sqlLogResult(table: 'player_stats', operation: 'SELECT', error: e);
      }

      final nowIso = DateTime.now().toIso8601String();
      final upserts = <Map<String, dynamic>>[];
      for (final phone in phones) {
        final statsId = PlayerStats.docId(playerPhone: phone, tournamentId: tournamentId);
        final teamId = (teamByPhone[phone] ?? '').trim();
        final existing = existingById[statsId] ?? const <String, dynamic>{};
        final next = <String, dynamic>{
          'id': statsId,
          'player_phone': phone,
          'tournament_id': tournamentId,
          'team_id': teamId,
          'matches_played': readInt(existing['matches_played']) + (deltas[phone]!['matches_played'] ?? 0),
          'goals': readInt(existing['goals']) + (deltas[phone]!['goals'] ?? 0),
          'assists': readInt(existing['assists']) + (deltas[phone]!['assists'] ?? 0),
          'yellow_cards': readInt(existing['yellow_cards']) + (deltas[phone]!['yellow_cards'] ?? 0),
          'red_cards': readInt(existing['red_cards']) + (deltas[phone]!['red_cards'] ?? 0),
          'man_of_the_match': readInt(existing['man_of_the_match']) + (deltas[phone]!['man_of_the_match'] ?? 0),
          'updated_at': nowIso,
          if (existing.isEmpty) 'created_at': nowIso,
        };
        upserts.add(next);
      }

      try {
        AppConfig.sqlLogStart(table: 'player_stats', operation: 'UPSERT', filters: 'onConflict=id | rows=${upserts.length}');
        await _client.from('player_stats').upsert(upserts, onConflict: 'id');
        AppConfig.sqlLogResult(table: 'player_stats', operation: 'UPSERT', count: upserts.length);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'player_stats', operation: 'UPSERT', error: e);
      }

      try {
        AppConfig.sqlLogStart(table: 'matches', operation: 'UPDATE', filters: 'id=$id | stats_committed=true');
        await _client.from('matches').update({
          'stats_committed_at': nowIso,
          'stats_committed': true,
          'updated_at': nowIso,
        }).eq('id', id);
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPDATE', count: 1);
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
        AppConfig.sqlLogStart(table: 'teams', operation: 'INSERT', filters: 'rows=${teams.length} | league_id=$tId');
        for (final team in teams) {
          final name = team.name.trim();
          if (name.isEmpty) continue;
          await _client.from('teams').insert({
            'league_id': tId,
            'name': name,
            'group_name': team.groupName.trim(),
            'created_at': DateTime.now().toIso8601String(),
          });
        }

        AppConfig.sqlLogStart(table: 'matches', operation: 'INSERT', filters: 'rows=${matches.length} | tournament_id=$tId');
        for (final m in matches) {
          await _client.from('matches').insert({
            'tournament_id': tId,
            'week': m.week,
            'group_id': m.groupId.trim().isEmpty ? null : m.groupId.trim(),
            'home_team_name': m.homeTeamName.trim(),
            'away_team_name': m.awayTeamName.trim(),
            'match_date': (m.matchDateYyyyMmDd ?? '').trim().isEmpty
                ? null
                : m.matchDateYyyyMmDd!.trim(),
            'match_time':
                (m.matchTime ?? '').trim().isEmpty ? null : m.matchTime!.trim(),
            'pitch_name':
                (m.pitchName ?? '').trim().isEmpty ? null : m.pitchName!.trim(),
            'status': 'scheduled',
            'created_at': DateTime.now().toIso8601String(),
          });
        }
        AppConfig.sqlLogResult(table: 'matches', operation: 'INSERT', count: matches.length);
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
      AppConfig.sqlLogResult(table: 'match_events', operation: 'DELETE', count: deleted);
    } catch (e) {
      AppConfig.sqlLogResult(table: 'match_events', operation: 'DELETE', error: e);
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
      AppConfig.sqlLogResult(table: 'matches', operation: 'DELETE', count: deleted);
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
}
