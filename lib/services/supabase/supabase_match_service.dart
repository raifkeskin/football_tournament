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
        filters: 'primaryKey=id | clientFilter=league_id=$id | order=match_date asc',
      );
      return _client
          .from('matches')
          .stream(primaryKey: ['id'])
          .order('match_date', ascending: true)
          .map((rows) {
            final filtered = rows.where((r) {
              return (r['league_id'] ?? '').toString().trim() == id;
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
    if (id.isEmpty) return const Stream<List<MatchModel>>.empty();
    return watchMatchesForLeague(id).map((list) {
      return list.where((m) {
        final okWeek = (m.week ?? -1) == week;
        if (!okWeek) return false;
        return true;
      }).toList();
    });
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
        if (res is! List) {
          AppConfig.sqlLogResult(table: 'matches', operation: 'SELECT', count: 0);
          return null;
        }
        AppConfig.sqlLogResult(table: 'matches', operation: 'SELECT', count: res.length);
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
          filters: 'id=${event.matchId} | columns=home_team_id,away_team_id,home_score,away_score | limit=1',
        );
        final res = await _client
            .from('matches')
            .select('home_team_id, away_team_id, home_score, away_score')
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

        final currentHome = _readInt(row['home_score'], fallback: 0);
        final currentAway = _readInt(row['away_score'], fallback: 0);
        final nextHome = isHome ? currentHome + 1 : currentHome;
        final nextAway = isAway ? currentAway + 1 : currentAway;

        AppConfig.sqlLogStart(
          table: 'matches',
          operation: 'UPDATE',
          filters: 'id=${event.matchId} | home_score=$nextHome, away_score=$nextAway',
        );
        await _client.from('matches').update({
          'home_score': nextHome,
          'away_score': nextAway,
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
    return Future.value();
  }

  @override
  Future<void> updateMatchPitchName({
    required String matchId,
    required String? pitchName,
  }) {
    final id = matchId.trim();
    if (id.isEmpty) return Future.value();
    return Future.value();
  }

  @override
  Future<void> updateMatchHighlightPhotoUrl({
    required String matchId,
    required bool isHome,
    required String? photoUrl,
  }) {
    final id = matchId.trim();
    if (id.isEmpty) return Future.value();
    return Future.value();
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
    return Future(() async {
      try {
        AppConfig.sqlLogStart(table: 'matches', operation: 'UPSERT', filters: 'onConflict=id | id=$id');
        await _client.from('matches').upsert({
          'id': id,
          'match_date': matchDateDb.trim().isEmpty ? null : matchDateDb.trim(),
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
    return Future.value();
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
    return Future.value();
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
      String leagueId = '';
      String homeTeamId = '';
      try {
        AppConfig.sqlLogStart(
          table: 'matches',
          operation: 'SELECT',
          filters: 'id=$id | columns=league_id,home_team_id | limit=1',
        );
        final res = await _client
            .from('matches')
            .select('league_id, home_team_id')
            .eq('id', id)
            .limit(1);
        if (res is List && res.isNotEmpty) {
          AppConfig.sqlLogResult(table: 'matches', operation: 'SELECT', count: 1);
          final row = (res.first as Map).cast<String, dynamic>();
          leagueId = (row['league_id'] ?? '').toString().trim();
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
          'is_completed': true,
        }, onConflict: 'id');
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPSERT', count: 1);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'matches', operation: 'UPSERT', error: e);
      }

      final period = await _readMatchPeriodDurationMinutes(leagueId);
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
            'league_id': leagueId.isEmpty ? null : leagueId,
            'team_id': homeTeamId.isEmpty ? null : homeTeamId,
            'event_type': 'status',
            'minute': 0,
            'player_name': 'Maç Başladı',
            'is_own_goal': false,
            'created_at': createdAt,
          },
          {
            'match_id': id,
            'league_id': leagueId.isEmpty ? null : leagueId,
            'team_id': homeTeamId.isEmpty ? null : homeTeamId,
            'event_type': 'status',
            'minute': period,
            'player_name': 'İlk Yarı Bitti',
            'is_own_goal': false,
            'created_at': createdAt,
          },
          {
            'match_id': id,
            'league_id': leagueId.isEmpty ? null : leagueId,
            'team_id': homeTeamId.isEmpty ? null : homeTeamId,
            'event_type': 'status',
            'minute': period * 2,
            'player_name': 'Maç Bitti',
            'is_own_goal': false,
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
        filters: 'primaryKey=id | clientFilter=league_id=$id',
      );
      return _client.from('player_stats').stream(primaryKey: ['id']).map((rows) {
        final filtered = rows.where((r) {
          return (r['league_id'] ?? '').toString().trim() == id;
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

      final status = (match['status'] ?? '').toString().trim();
      final finished =
          match['is_completed'] == true ||
          status == MatchStatus.finished.name ||
          status.toLowerCase() == 'completed' ||
          status.toLowerCase() == 'finished';
      if (!finished) return;
      if (match['stats_committed_at'] != null || match['stats_committed'] == true) return;

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
        AppConfig.sqlLogStart(table: 'match_events', operation: 'SELECT', filters: 'match_id=$id');
        final eventsRes = await _client
            .from('match_events')
            .select('event_type, team_id, player_id, assist_player_id')
            .eq('match_id', id);
        if (eventsRes is List) {
          AppConfig.sqlLogResult(table: 'match_events', operation: 'SELECT', count: eventsRes.length);
          for (final rowAny in eventsRes) {
            final e = (rowAny as Map).cast<String, dynamic>();
            final eventType = (e['event_type'] ?? '').toString().trim();
            final teamId = (e['team_id'] ?? '').toString().trim();
            final playerPhone = (e['player_id'] ?? '').toString().trim();
            final assistPhone = (e['assist_player_id'] ?? '').toString().trim();

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
          'league_id': tournamentId,
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
        AppConfig.sqlLogStart(table: 'teams', operation: 'INSERT', filters: 'rows=${teams.length} | league_id=$tId');
        for (final team in teams) {
          final name = team.name.trim();
          if (name.isEmpty) continue;
          await _client.from('teams').insert({
            'league_id': tId,
            'name': name,
            'group_name': team.groupName.trim(),
          });
        }

        final teamsRes = await _client.from('teams').select('id, name').eq('league_id', tId);
        final teamIdByName = <String, String>{};
        if (teamsRes is List) {
          for (final rowAny in teamsRes) {
            final row = (rowAny as Map).cast<String, dynamic>();
            final id = (row['id'] ?? '').toString().trim();
            final name = (row['name'] ?? '').toString().trim().toLowerCase();
            if (id.isNotEmpty && name.isNotEmpty) {
              teamIdByName[name] = id;
            }
          }
        }

        AppConfig.sqlLogStart(table: 'matches', operation: 'INSERT', filters: 'rows=${matches.length} | league_id=$tId');
        for (final m in matches) {
          final homeId = teamIdByName[m.homeTeamName.trim().toLowerCase()];
          final awayId = teamIdByName[m.awayTeamName.trim().toLowerCase()];
          DateTime? matchDateTime;
          final dateStr = (m.matchDateYyyyMmDd ?? '').trim();
          final timeStr = (m.matchTime ?? '').trim();
          if (dateStr.isNotEmpty && timeStr.isNotEmpty) {
            matchDateTime = DateTime.tryParse('${dateStr}T$timeStr:00');
          }
          matchDateTime ??= (dateStr.isEmpty ? null : DateTime.tryParse(dateStr));
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
