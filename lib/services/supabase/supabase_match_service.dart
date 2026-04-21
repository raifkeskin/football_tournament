import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

import '../interfaces/i_match_service.dart';
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
      final res = await _client
          .from('leagues')
          .select('match_period_duration, id')
          .eq('id', id)
          .limit(1);
      if (res is List && res.isNotEmpty) {
        final row = (res.first as Map).cast<String, dynamic>();
        final minutes = _readInt(row['match_period_duration'], fallback: 25);
        return minutes <= 0 ? 25 : minutes;
      }
      return 25;
    } catch (_) {
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
    } catch (_) {
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
    return _client
        .from('matches')
        .select('week, tournament_id, group_id')
        .then((res) {
          if (res is! List) return null;
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
        })
        .catchError((_) => null);
  }

  @override
  Stream<MatchModel> watchMatch(String matchId) {
    final id = matchId.trim();
    if (id.isEmpty) return const Stream<MatchModel>.empty();
    try {
      return _client.from('matches').stream(primaryKey: ['id']).map((rows) {
        final row = rows.cast<Map<String, dynamic>>().firstWhere(
          (r) => (r['id'] ?? '').toString().trim() == id,
          orElse: () => const <String, dynamic>{},
        );
        return MatchModel.fromMap(row, id);
      });
    } catch (_) {
      return const Stream<MatchModel>.empty();
    }
  }

  @override
  Stream<List<Map<String, dynamic>>> watchInlineMatchEvents(String matchId) {
    final id = matchId.trim();
    if (id.isEmpty) return const Stream<List<Map<String, dynamic>>>.empty();
    try {
      return _client
          .from('match_events')
          .stream(primaryKey: ['id'])
          .order('minute', ascending: true)
          .map((rows) {
            final filtered = rows.where((r) => (r['match_id'] ?? '').toString().trim() == id);
            return filtered.map((r) => Map<String, dynamic>.from(r)).toList();
          });
    } catch (_) {
      return const Stream<List<Map<String, dynamic>>>.empty();
    }
  }

  @override
  Future<void> updateMatchYoutubeUrl({
    required String matchId,
    required String? youtubeUrl,
  }) {
    final id = matchId.trim();
    if (id.isEmpty) return Future.value();
    return _client
        .from('matches')
        .upsert({'id': id, 'youtube_url': (youtubeUrl ?? '').trim().isEmpty ? null : youtubeUrl!.trim()}, onConflict: 'id')
        .catchError((_) {});
  }

  @override
  Future<void> updateMatchPitchName({
    required String matchId,
    required String? pitchName,
  }) {
    final id = matchId.trim();
    if (id.isEmpty) return Future.value();
    return _client
        .from('matches')
        .upsert({'id': id, 'pitch_name': (pitchName ?? '').trim().isEmpty ? null : pitchName!.trim()}, onConflict: 'id')
        .catchError((_) {});
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
    return _client
        .from('matches')
        .upsert({
          'id': id,
          'match_date': dateStr.isEmpty ? null : dateStr,
          'match_time': timeStr.isEmpty ? null : timeStr,
          'pitch_name': (pitchName ?? '').trim().isEmpty ? null : pitchName!.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'id')
        .catchError((_) {});
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
        final res = await _client
            .from('matches')
            .select('tournament_id, league_id, home_team_id')
            .eq('id', id)
            .limit(1);
        if (res is List && res.isNotEmpty) {
          final row = (res.first as Map).cast<String, dynamic>();
          tournamentId = (row['tournament_id'] ?? row['league_id'] ?? '').toString().trim();
          homeTeamId = (row['home_team_id'] ?? '').toString().trim();
        }
      } catch (_) {}

      await _client
          .from('matches')
          .upsert({
            'id': id,
            'home_score': homeScore,
            'away_score': awayScore,
            'status': 'finished',
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'id')
          .catchError((_) {});

      final period = await _readMatchPeriodDurationMinutes(tournamentId);
      final createdAt = DateTime.now().toIso8601String();
      try {
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
      } catch (_) {}
    });
  }

  @override
  Stream<List<PlayerStats>> watchPlayerStats({required String tournamentId}) {
    return const Stream<List<PlayerStats>>.empty();
  }

  @override
  Future<void> commitPlayerStatsForCompletedMatch({required String matchId}) {
    return Future.value();
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
      } catch (_) {}
    });
  }
}
