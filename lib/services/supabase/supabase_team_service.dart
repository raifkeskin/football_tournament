import 'package:supabase_flutter/supabase_flutter.dart';

import '../interfaces/i_team_service.dart';
import '../../config/app_config.dart';
import '../../models/league.dart';
import '../../models/match.dart';
import '../../models/team.dart';

class SupabaseTeamService implements ITeamService {
  SupabaseTeamService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  static const String _serviceName = 'SupabaseTeamService';

  final SupabaseClient _client;

  DateTime? _readDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  static Map<String, String> _traceInfo(StackTrace trace) {
    final lines = trace.toString().split('\n');
    final line = lines.length > 1 ? lines[1] : (lines.isNotEmpty ? lines.first : '');

    final method =
        RegExp(r'#\d+\s+(.+?)\s+\(').firstMatch(line)?.group(1)?.trim() ?? '-';

    final location =
        RegExp(r'\((.+?):\d+:\d+\)').firstMatch(line)?.group(1)?.trim() ?? '';

    var file = '-';
    if (location.isNotEmpty) {
      final normalized = location.replaceAll('\\', '/');
      file = normalized.split('/').last;
    }

    return {'file': file, 'method': method};
  }

  static void _sbLog({
    required String table,
    required String query,
    required StackTrace trace,
  }) {
    final info = _traceInfo(trace);
    AppConfig.logDb(
      '[SUPABASE] File: ${info['file']} | Method: ${info['method']} | Table: $table | Query: $query',
    );
  }

  static void _sbResult({int? rows, Object? error}) {
    AppConfig.logDb(
      '[SUPABASE_RESULT] Rows: ${rows ?? '-'} | Error: ${error == null ? '-' : error.toString()}',
    );
  }

  @override
  Stream<List<Team>> watchAllTeams({String? caller}) {
    try {
      _sbLog(
        table: 'teams',
        query: 'STREAM order=name asc',
        trace: StackTrace.current,
      );
      AppConfig.sqlLogStart(
        table: 'teams',
        operation: 'STREAM',
        caller: caller,
        service: _serviceName,
        method: 'watchAllTeams',
        filters: 'order=name asc',
      );
      return _client
          .from('teams')
          .stream(primaryKey: ['id'])
          .order('name', ascending: true)
          .map((rows) => rows.map((r) => Team.fromMap(r)).toList());
    } catch (e) {
      AppConfig.sqlLogResult(
        table: 'teams',
        operation: 'STREAM',
        caller: caller,
        service: _serviceName,
        method: 'watchAllTeams',
        error: e,
      );
      _sbResult(error: e);
      return const Stream<List<Team>>.empty();
    }
  }

  @override
  Stream<List<Map<String, dynamic>>> watchAllTeamsRaw({String? caller}) {
    try {
      _sbLog(
        table: 'teams',
        query: 'STREAM order=name asc',
        trace: StackTrace.current,
      );
      AppConfig.sqlLogStart(
        table: 'teams',
        operation: 'STREAM',
        caller: caller,
        service: _serviceName,
        method: 'watchAllTeamsRaw',
        filters: 'order=name asc',
      );
      return _client
          .from('teams')
          .stream(primaryKey: ['id'])
          .order('name', ascending: true)
          .map((rows) => rows.map((r) => Map<String, dynamic>.from(r)).toList());
    } catch (e) {
      AppConfig.sqlLogResult(
        table: 'teams',
        operation: 'STREAM',
        caller: caller,
        service: _serviceName,
        method: 'watchAllTeamsRaw',
        error: e,
      );
      _sbResult(error: e);
      return const Stream<List<Map<String, dynamic>>>.empty();
    }
  }

  @override
  Future<String> getTeamName(String teamId, {String? caller}) {
    return watchTeamName(teamId, caller: caller).first;
  }

  @override
  Future<Team?> getTeamOnce(String teamId, {String? caller}) {
    final id = teamId.trim();
    if (id.isEmpty) return Future.value(null);
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'teams',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'getTeamOnce',
          filters: 'id=$id | limit=1',
        );
        final res = await _client.from('teams').select().eq('id', id).limit(1);
        if (res is! List || res.isEmpty) {
          AppConfig.sqlLogResult(
            table: 'teams',
            operation: 'SELECT',
            caller: caller,
            service: _serviceName,
            method: 'getTeamOnce',
            count: 0,
          );
          return null;
        }
        AppConfig.sqlLogResult(
          table: 'teams',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'getTeamOnce',
          count: 1,
        );
        return Team.fromMap((res.first as Map).cast<String, dynamic>());
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'teams',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'getTeamOnce',
          error: e,
        );
        return null;
      }
    });
  }

  @override
  Future<PlayerModel?> getPlayerByPhoneOnce(String playerPhone, {String? caller}) {
    final phone = playerPhone.trim();
    if (phone.isEmpty) return Future.value(null);
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'players',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'getPlayerByPhoneOnce',
          filters: 'phone|phone_raw10|id=$phone | limit=1',
        );
        final res = await _client
            .from('players')
            .select()
            .or('phone.eq.$phone,phone_raw10.eq.$phone,id.eq.$phone')
            .limit(1);
        if (res is! List || res.isEmpty) {
          AppConfig.sqlLogResult(
            table: 'players',
            operation: 'SELECT',
            caller: caller,
            service: _serviceName,
            method: 'getPlayerByPhoneOnce',
            count: 0,
          );
          return null;
        }
        AppConfig.sqlLogResult(
          table: 'players',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'getPlayerByPhoneOnce',
          count: 1,
        );
        final row = (res.first as Map).cast<String, dynamic>();
        final id = (row['id'] ?? row['phone'] ?? row['phone_raw10'] ?? phone).toString();
        return PlayerModel.fromMap(row, id);
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'players',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'getPlayerByPhoneOnce',
          error: e,
        );
        return null;
      }
    });
  }

  @override
  Stream<String> watchTeamName(String teamId, {String? caller}) {
    final id = teamId.trim();
    if (id.isEmpty) return const Stream<String>.empty();
    try {
      AppConfig.sqlLogStart(
        table: 'teams',
        operation: 'STREAM',
        caller: caller,
        service: _serviceName,
        method: 'watchTeamName',
        filters: 'primaryKey=id | clientFilter=id=$id',
      );
      return _client
          .from('teams')
          .stream(primaryKey: ['id'])
          .map((rows) {
            final row = rows.cast<Map<String, dynamic>>().firstWhere(
              (r) => (r['id'] ?? '').toString().trim() == id,
              orElse: () => const <String, dynamic>{},
            );
            if (row.isEmpty) return id;
            final name = (row['name'] ?? '').toString().trim();
            return name.isEmpty ? id : name;
          });
    } catch (e) {
      AppConfig.sqlLogResult(
        table: 'teams',
        operation: 'STREAM',
        caller: caller,
        service: _serviceName,
        method: 'watchTeamName',
        error: e,
      );
      return Stream<String>.value(id);
    }
  }

  @override
  Stream<List<Team>> watchTeamsByGroup(String groupId, {String? caller}) {
    final gid = groupId.trim();
    if (gid.isEmpty) return const Stream<List<Team>>.empty();
    try {
      AppConfig.sqlLogStart(
        table: 'teams',
        operation: 'STREAM',
        caller: caller,
        service: _serviceName,
        method: 'watchTeamsByGroup',
        filters: 'primaryKey=id | clientFilter=group_id=$gid | order=name asc',
      );
      return _client
          .from('teams')
          .stream(primaryKey: ['id'])
          .order('name', ascending: true)
          .map((rows) {
            final list = rows
                .where((r) => (r['group_id'] ?? '').toString().trim() == gid)
                .map((r) => Team.fromMap(Map<String, dynamic>.from(r)))
                .toList();
            list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
            return list;
          });
    } catch (e) {
      AppConfig.sqlLogResult(
        table: 'teams',
        operation: 'STREAM',
        caller: caller,
        service: _serviceName,
        method: 'watchTeamsByGroup',
        error: e,
      );
      return const Stream<List<Team>>.empty();
    }
  }

  @override
  Stream<List<PlayerModel>> watchPlayers({
    required String teamId,
    String? tournamentId,
    String? caller,
  }) {
    final team = teamId.trim();
    final tId = (tournamentId ?? '').trim();
    if (team.isEmpty) return const Stream<List<PlayerModel>>.empty();
    try {
      AppConfig.sqlLogStart(
        table: 'rosters',
        operation: 'STREAM',
        caller: caller,
        service: _serviceName,
        method: 'watchPlayers',
        filters: 'primaryKey=id | clientFilter=team_id=$team${tId.isEmpty ? '' : ', tournament_id=$tId'}',
      );
      final q = _client.from('rosters').stream(primaryKey: ['id']);
      return q.map((rows) {
        final filtered = rows.where((r) {
          final okTeam = (r['team_id'] ?? '').toString().trim() == team;
          if (!okTeam) return false;
          if (tId.isEmpty) return true;
          return (r['tournament_id'] ?? '').toString().trim() == tId;
        });
        final list = filtered.map((r) {
          final id = (r['id'] ?? '').toString().trim();
          final resolvedId = id.isEmpty
              ? '${(r['player_phone'] ?? '').toString().trim()}_${(r['tournament_id'] ?? '').toString().trim()}_${(r['team_id'] ?? '').toString().trim()}'
              : id;
          return PlayerModel.fromMap(Map<String, dynamic>.from(r), resolvedId);
        }).toList();
        list.sort((a, b) {
          bool isManager(PlayerModel p) => p.role == 'Takım Sorumlusu' || p.role == 'Her İkisi';
          final aM = isManager(a);
          final bM = isManager(b);
          if (aM != bM) return aM ? -1 : 1;
          final an = int.tryParse((a.number ?? '').trim()) ?? 9999;
          final bn = int.tryParse((b.number ?? '').trim()) ?? 9999;
          final cmp = an.compareTo(bn);
          if (cmp != 0) return cmp;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        return list;
      });
    } catch (e) {
      AppConfig.sqlLogResult(
        table: 'rosters',
        operation: 'STREAM',
        caller: caller,
        service: _serviceName,
        method: 'watchPlayers',
        error: e,
      );
      return const Stream<List<PlayerModel>>.empty();
    }
  }

  @override
  Stream<List<PlayerModel>> watchAllPlayers({String? caller}) {
    try {
      AppConfig.sqlLogStart(
        table: 'players',
        operation: 'STREAM',
        caller: caller,
        service: _serviceName,
        method: 'watchAllPlayers',
        filters: 'primaryKey=id | order=name asc',
      );
      return _client
          .from('players')
          .stream(primaryKey: ['id'])
          .order('name', ascending: true)
          .map((rows) {
            final list = rows.map((r) {
              final row = Map<String, dynamic>.from(r);
              final id = (row['id'] ?? row['phone'] ?? row['phone_raw10'] ?? '').toString();
              return PlayerModel.fromMap(row, id);
            }).toList();
            list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
            return list;
          });
    } catch (e) {
      AppConfig.sqlLogResult(
        table: 'players',
        operation: 'STREAM',
        caller: caller,
        service: _serviceName,
        method: 'watchAllPlayers',
        error: e,
      );
      return const Stream<List<PlayerModel>>.empty();
    }
  }

  @override
  Future<void> upsertPlayerIdentity({
    required String phone,
    required String name,
    String? birthDate,
    String? mainPosition,
    String? caller,
  }) {
    final p = phone.trim();
    final n = name.trim();
    if (p.isEmpty || n.isEmpty) return Future.value();
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'players',
          operation: 'UPSERT',
          caller: caller,
          service: _serviceName,
          method: 'upsertPlayerIdentity',
          filters: 'onConflict=phone | phone=$p',
        );
        await _client.from('players').upsert({
          'phone': p,
          'name': n,
          'birth_date': (birthDate ?? '').trim().isEmpty ? null : birthDate!.trim(),
          'main_position': (mainPosition ?? '').trim().isEmpty ? null : mainPosition!.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'phone');
        AppConfig.sqlLogResult(
          table: 'players',
          operation: 'UPSERT',
          caller: caller,
          service: _serviceName,
          method: 'upsertPlayerIdentity',
          count: 1,
        );
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'players',
          operation: 'UPSERT',
          caller: caller,
          service: _serviceName,
          method: 'upsertPlayerIdentity',
          error: e,
        );
      }
    });
  }

  @override
  Future<void> updatePlayer({
    required String playerId,
    required Map<String, dynamic> data,
    String? caller,
  }) {
    final id = playerId.trim();
    if (id.isEmpty) return Future.value();
    return Future(() async {
      try {
        String mapKey(String k) {
          switch (k) {
            case 'photoUrl':
              return 'photo_url';
            case 'birthDate':
              return 'birth_date';
            case 'mainPosition':
              return 'main_position';
            case 'preferredFoot':
              return 'preferred_foot';
            case 'phoneRaw10':
              return 'phone_raw10';
            case 'suspendedMatches':
              return 'suspended_matches';
            default:
              return k;
          }
        }

        final payload = <String, dynamic>{};
        for (final e in data.entries) {
          payload[mapKey(e.key)] = e.value;
        }
        payload['updated_at'] = DateTime.now().toIso8601String();

        AppConfig.sqlLogStart(
          table: 'players',
          operation: 'UPDATE',
          caller: caller,
          service: _serviceName,
          method: 'updatePlayer',
          filters: 'id=$id',
        );
        await _client.from('players').update(payload).eq('id', id);
        AppConfig.sqlLogResult(
          table: 'players',
          operation: 'UPDATE',
          caller: caller,
          service: _serviceName,
          method: 'updatePlayer',
          count: 1,
        );
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'players',
          operation: 'UPDATE',
          caller: caller,
          service: _serviceName,
          method: 'updatePlayer',
          error: e,
        );
      }
    });
  }

  @override
  Future<Map<String, dynamic>?> getPenaltyForPlayer(String playerId, {String? caller}) {
    final id = playerId.trim();
    if (id.isEmpty) return Future.value(null);
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'penalties',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'getPenaltyForPlayer',
          filters: 'id|player_id=$id | limit=1',
        );
        final res = await _client
            .from('penalties')
            .select()
            .or('id.eq.$id,player_id.eq.$id')
            .limit(1);
        if (res is! List || res.isEmpty) {
          AppConfig.sqlLogResult(
            table: 'penalties',
            operation: 'SELECT',
            caller: caller,
            service: _serviceName,
            method: 'getPenaltyForPlayer',
            count: 0,
          );
          return null;
        }
        AppConfig.sqlLogResult(
          table: 'penalties',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'getPenaltyForPlayer',
          count: 1,
        );
        return (res.first as Map).cast<String, dynamic>();
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'penalties',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'getPenaltyForPlayer',
          error: e,
        );
        return null;
      }
    });
  }

  @override
  Future<void> upsertPenaltyForPlayer({
    required String playerId,
    required String teamId,
    required String penaltyReason,
    required int matchCount,
    String? caller,
  }) {
    final pId = playerId.trim();
    final tId = teamId.trim();
    final reason = penaltyReason.trim();
    if (pId.isEmpty || tId.isEmpty) {
      return Future.error(Exception('Ceza alanları eksik.'));
    }
    if (matchCount < 0) {
      return Future.error(Exception('Maç sayısı geçerli olmalı.'));
    }
    if (matchCount == 0) {
      return clearPenaltyForPlayer(playerId: pId, caller: caller);
    }
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'penalties',
          operation: 'UPSERT',
          caller: caller,
          service: _serviceName,
          method: 'upsertPenaltyForPlayer',
          filters: 'onConflict=id | id=$pId',
        );
        await _client.from('penalties').upsert({
          'id': pId,
          'player_id': pId,
          'team_id': tId,
          'penalty_reason': reason,
          'match_count': matchCount,
          'updated_at': DateTime.now().toIso8601String(),
          'created_at': DateTime.now().toIso8601String(),
        }, onConflict: 'id');
        AppConfig.sqlLogResult(
          table: 'penalties',
          operation: 'UPSERT',
          caller: caller,
          service: _serviceName,
          method: 'upsertPenaltyForPlayer',
          count: 1,
        );
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'penalties',
          operation: 'UPSERT',
          caller: caller,
          service: _serviceName,
          method: 'upsertPenaltyForPlayer',
          error: e,
        );
      }

      try {
        AppConfig.sqlLogStart(
          table: 'players',
          operation: 'UPDATE',
          caller: caller,
          service: _serviceName,
          method: 'upsertPenaltyForPlayer',
          filters: 'id=$pId | suspended_matches=$matchCount',
        );
        await _client
            .from('players')
            .update({'suspended_matches': matchCount, 'updated_at': DateTime.now().toIso8601String()})
            .eq('id', pId);
        AppConfig.sqlLogResult(
          table: 'players',
          operation: 'UPDATE',
          caller: caller,
          service: _serviceName,
          method: 'upsertPenaltyForPlayer',
          count: 1,
        );
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'players',
          operation: 'UPDATE',
          caller: caller,
          service: _serviceName,
          method: 'upsertPenaltyForPlayer',
          error: e,
        );
      }
    });
  }

  @override
  Future<void> clearPenaltyForPlayer({required String playerId, String? caller}) {
    final pId = playerId.trim();
    if (pId.isEmpty) return Future.value();
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'penalties',
          operation: 'DELETE',
          caller: caller,
          service: _serviceName,
          method: 'clearPenaltyForPlayer',
          filters: 'id|player_id=$pId',
        );
        await _client.from('penalties').delete().or('id.eq.$pId,player_id.eq.$pId');
        AppConfig.sqlLogResult(
          table: 'penalties',
          operation: 'DELETE',
          caller: caller,
          service: _serviceName,
          method: 'clearPenaltyForPlayer',
        );
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'penalties',
          operation: 'DELETE',
          caller: caller,
          service: _serviceName,
          method: 'clearPenaltyForPlayer',
          error: e,
        );
      }

      try {
        AppConfig.sqlLogStart(
          table: 'players',
          operation: 'UPDATE',
          caller: caller,
          service: _serviceName,
          method: 'clearPenaltyForPlayer',
          filters: 'id=$pId | suspended_matches=0',
        );
        await _client
            .from('players')
            .update({'suspended_matches': 0, 'updated_at': DateTime.now().toIso8601String()})
            .eq('id', pId);
        AppConfig.sqlLogResult(
          table: 'players',
          operation: 'UPDATE',
          caller: caller,
          service: _serviceName,
          method: 'clearPenaltyForPlayer',
          count: 1,
        );
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'players',
          operation: 'UPDATE',
          caller: caller,
          service: _serviceName,
          method: 'clearPenaltyForPlayer',
          error: e,
        );
      }
    });
  }

  @override
  Future<void> upsertRosterEntry({
    required String tournamentId,
    required String teamId,
    required String playerPhone,
    required String playerName,
    String? jerseyNumber,
    required String role,
    String? caller,
  }) {
    final t = tournamentId.trim();
    final team = teamId.trim();
    final phone = playerPhone.trim();
    final name = playerName.trim();
    if (t.isEmpty || team.isEmpty || phone.isEmpty) return Future.value();

    final docId = '${phone}_${t}_$team';
    return Future(() async {
      try {
        _sbLog(
          table: 'rosters',
          query: 'UPSERT onConflict=id | id=$docId',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'rosters',
          operation: 'UPSERT',
          caller: caller,
          service: _serviceName,
          method: 'upsertRosterEntry',
          filters: 'onConflict=id | id=$docId',
        );
        await _client.from('rosters').upsert({
          'id': docId,
          'tournament_id': t,
          'team_id': team,
          'player_phone': phone,
          'player_name': name,
          'jersey_number': (jerseyNumber ?? '').trim().isEmpty ? null : jerseyNumber!.trim(),
          'role': role.trim().isEmpty ? 'Futbolcu' : role.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'id');
        AppConfig.sqlLogResult(
          table: 'rosters',
          operation: 'UPSERT',
          caller: caller,
          service: _serviceName,
          method: 'upsertRosterEntry',
          count: 1,
        );
        _sbResult(rows: 1);
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'rosters',
          operation: 'UPSERT',
          caller: caller,
          service: _serviceName,
          method: 'upsertRosterEntry',
          error: e,
        );
        _sbResult(rows: 0, error: e);
      }

      try {
        _sbLog(
          table: 'transfers',
          query: 'INSERT action=roster_upsert',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'transfers',
          operation: 'INSERT',
          caller: caller,
          service: _serviceName,
          method: 'upsertRosterEntry',
          filters: 'action=roster_upsert',
        );
        await _client.from('transfers').insert({
          'tournament_id': t,
          'team_id': team,
          'player_phone': phone,
          'action': 'roster_upsert',
          'created_at': DateTime.now().toIso8601String(),
        });
        AppConfig.sqlLogResult(
          table: 'transfers',
          operation: 'INSERT',
          caller: caller,
          service: _serviceName,
          method: 'upsertRosterEntry',
          count: 1,
        );
        _sbResult(rows: 1);
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'transfers',
          operation: 'INSERT',
          caller: caller,
          service: _serviceName,
          method: 'upsertRosterEntry',
          error: e,
        );
        _sbResult(rows: 0, error: e);
      }
    });
  }

  @override
  Future<void> deleteRosterEntry({
    required String tournamentId,
    required String teamId,
    required String playerPhone,
    String? caller,
  }) {
    final t = tournamentId.trim();
    final team = teamId.trim();
    final phone = playerPhone.trim();
    if (t.isEmpty || team.isEmpty || phone.isEmpty) return Future.value();
    final id = '${phone}_${t}_$team';
    return Future(() async {
      try {
        _sbLog(
          table: 'rosters',
          query: 'DELETE id=$id',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'rosters',
          operation: 'DELETE',
          caller: caller,
          service: _serviceName,
          method: 'deleteRosterEntry',
          filters: 'id=$id',
        );
        await _client.from('rosters').delete().eq('id', id);
        AppConfig.sqlLogResult(
          table: 'rosters',
          operation: 'DELETE',
          caller: caller,
          service: _serviceName,
          method: 'deleteRosterEntry',
          count: 1,
        );
        _sbResult(rows: 1);
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'rosters',
          operation: 'DELETE',
          caller: caller,
          service: _serviceName,
          method: 'deleteRosterEntry',
          error: e,
        );
        _sbResult(rows: 0, error: e);
      }

      try {
        _sbLog(
          table: 'transfers',
          query: 'INSERT action=roster_delete',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'transfers',
          operation: 'INSERT',
          caller: caller,
          service: _serviceName,
          method: 'deleteRosterEntry',
          filters: 'action=roster_delete',
        );
        await _client.from('transfers').insert({
          'tournament_id': t,
          'team_id': team,
          'player_phone': phone,
          'action': 'roster_delete',
          'created_at': DateTime.now().toIso8601String(),
        });
        AppConfig.sqlLogResult(
          table: 'transfers',
          operation: 'INSERT',
          caller: caller,
          service: _serviceName,
          method: 'deleteRosterEntry',
          count: 1,
        );
        _sbResult(rows: 1);
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'transfers',
          operation: 'INSERT',
          caller: caller,
          service: _serviceName,
          method: 'deleteRosterEntry',
          error: e,
        );
        _sbResult(rows: 0, error: e);
      }
    });
  }

  @override
  Future<bool> isTeamManagerForTournament({
    required String tournamentId,
    required String teamId,
    required String playerPhone,
    String? caller,
  }) {
    final t = tournamentId.trim();
    final team = teamId.trim();
    final phone = playerPhone.trim();
    if (t.isEmpty || team.isEmpty || phone.isEmpty) return Future.value(false);
    return Future(() async {
      try {
        _sbLog(
          table: 'rosters',
          query: 'SELECT role | tournament_id=$t, team_id=$team, player_phone=$phone | limit=1',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'rosters',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'isTeamManagerForTournament',
          filters: 'tournament_id=$t, team_id=$team, player_phone=$phone | limit=1',
        );
        final res = await _client
            .from('rosters')
            .select('role')
            .eq('tournament_id', t)
            .eq('team_id', team)
            .eq('player_phone', phone)
            .limit(1);
        if (res is! List || res.isEmpty) {
          AppConfig.sqlLogResult(
            table: 'rosters',
            operation: 'SELECT',
            caller: caller,
            service: _serviceName,
            method: 'isTeamManagerForTournament',
            count: 0,
          );
          _sbResult(rows: 0);
          return false;
        }
        AppConfig.sqlLogResult(
          table: 'rosters',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'isTeamManagerForTournament',
          count: 1,
        );
        _sbResult(rows: 1);
        final role = ((res.first as Map)['role'] ?? '').toString().trim();
        return role == 'Takım Sorumlusu' || role == 'Her İkisi';
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'rosters',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'isTeamManagerForTournament',
          error: e,
        );
        _sbResult(rows: 0, error: e);
        return false;
      }
    });
  }

  @override
  Future<bool> managerExistsForTeamTournament({
    required String tournamentId,
    required String teamId,
    String? excludePlayerPhone,
    String? caller,
  }) {
    final t = tournamentId.trim();
    final team = teamId.trim();
    if (t.isEmpty || team.isEmpty) return Future.value(false);
    final exclude = excludePlayerPhone?.trim();
    return Future(() async {
      try {
        _sbLog(
          table: 'rosters',
          query: 'SELECT player_phone,role | tournament_id=$t, team_id=$team',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'rosters',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'managerExistsForTeamTournament',
          filters: 'tournament_id=$t, team_id=$team',
        );
        final res = await _client
            .from('rosters')
            .select('player_phone, role')
            .eq('tournament_id', t)
            .eq('team_id', team);
        if (res is! List) {
          AppConfig.sqlLogResult(
            table: 'rosters',
            operation: 'SELECT',
            caller: caller,
            service: _serviceName,
            method: 'managerExistsForTeamTournament',
            count: 0,
          );
          _sbResult(rows: 0);
          return false;
        }
        AppConfig.sqlLogResult(
          table: 'rosters',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'managerExistsForTeamTournament',
          count: res.length,
        );
        _sbResult(rows: res.length);
        for (final rowAny in res) {
          final row = (rowAny as Map).cast<String, dynamic>();
          final phone = (row['player_phone'] ?? '').toString().trim();
          if (exclude != null && exclude.isNotEmpty && phone == exclude) continue;
          final role = (row['role'] ?? '').toString().trim();
          final resolvedRole = role.isEmpty ? 'Futbolcu' : role;
          if (resolvedRole == 'Takım Sorumlusu' || resolvedRole == 'Her İkisi') return true;
        }
        return false;
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'rosters',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'managerExistsForTeamTournament',
          error: e,
        );
        _sbResult(rows: 0, error: e);
        return false;
      }
    });
  }

  @override
  Future<List<League>> getTeamActiveTournaments(String teamId, {String? caller}) {
    final tId = teamId.trim();
    if (tId.isEmpty) return Future.value(const []);
    return Future(() async {
      try {
        _sbLog(
          table: 'league_registrations',
          query: 'SELECT league_id | team_id=$tId',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'league_registrations',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'getTeamActiveTournaments',
          filters: 'team_id=$tId | columns=league_id',
        );
        final regRes = (await _client
                .from('league_registrations')
                .select('league_id')
                .eq('team_id', tId))
            .cast<Map<String, dynamic>>();
        AppConfig.sqlLogResult(
          table: 'league_registrations',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'getTeamActiveTournaments',
          count: regRes.length,
        );
        _sbResult(rows: regRes.length);
        if (regRes.isEmpty) return const <League>[];

        final leagueIds = <String>{};
        for (final row in regRes) {
          final id = (row['league_id'] ?? '').toString().trim();
          if (id.isNotEmpty) leagueIds.add(id);
        }
        if (leagueIds.isEmpty) return const <League>[];

        _sbLog(
          table: 'leagues',
          query: 'SELECT * | id IN (${leagueIds.length})',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'leagues',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'getTeamActiveTournaments',
          filters: 'id IN (${leagueIds.length})',
        );
        final leaguesRes = (await _client
                .from('leagues')
                .select()
                .inFilter('id', leagueIds.toList()))
            .cast<Map<String, dynamic>>();
        AppConfig.sqlLogResult(
          table: 'leagues',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'getTeamActiveTournaments',
          count: leaguesRes.length,
        );
        _sbResult(rows: leaguesRes.length);

        final leagues = leaguesRes.map((e) => League.fromMap(e)).toList();
        final active = leagues.where((l) => l.isActive).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return active;
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'leagues',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'getTeamActiveTournaments',
          error: e,
        );
        _sbResult(rows: 0, error: e);
        return const <League>[];
      }
    });
  }

  @override
  Future<void> updateTeam(String teamId, Map<String, dynamic> data, {String? caller}) {
    final id = teamId.trim();
    if (id.isEmpty) return Future.value();
    return Future(() async {
      try {
        String mapKey(String k) {
          switch (k) {
            case 'logoUrl':
              return 'logo_url';
            case 'groupId':
              return 'group_id';
            case 'groupName':
              return 'group_name';
            case 'leagueId':
              return 'league_id';
            default:
              return k;
          }
        }

        final payload = <String, dynamic>{};
        for (final e in data.entries) {
          payload[mapKey(e.key)] = e.value;
        }
        payload['updated_at'] = DateTime.now().toIso8601String();

        _sbLog(
          table: 'teams',
          query: 'UPDATE id=$id',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'teams',
          operation: 'UPDATE',
          caller: caller,
          service: _serviceName,
          method: 'updateTeam',
          filters: 'id=$id',
        );
        await _client.from('teams').update(payload).eq('id', id);
        AppConfig.sqlLogResult(
          table: 'teams',
          operation: 'UPDATE',
          caller: caller,
          service: _serviceName,
          method: 'updateTeam',
          count: 1,
        );
        _sbResult(rows: 1);
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'teams',
          operation: 'UPDATE',
          caller: caller,
          service: _serviceName,
          method: 'updateTeam',
          error: e,
        );
        _sbResult(rows: 0, error: e);
      }
    });
  }

  @override
  Future<void> deleteTeamCascade(String teamId, {String? caller}) {
    final id = teamId.trim();
    if (id.isEmpty) return Future.value();
    return Future(() async {
      try {
        _sbLog(
          table: 'league_registrations',
          query: 'DELETE team_id=$id',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'league_registrations',
          operation: 'DELETE',
          caller: caller,
          service: _serviceName,
          method: 'deleteTeamCascade',
          filters: 'team_id=$id',
        );
        await _client.from('league_registrations').delete().eq('team_id', id);
        AppConfig.sqlLogResult(
          table: 'league_registrations',
          operation: 'DELETE',
          caller: caller,
          service: _serviceName,
          method: 'deleteTeamCascade',
        );
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'league_registrations',
          operation: 'DELETE',
          caller: caller,
          service: _serviceName,
          method: 'deleteTeamCascade',
          error: e,
        );
        _sbResult(rows: 0, error: e);
      }

      List<String> matchIds = const [];
      try {
        _sbLog(
          table: 'matches',
          query: 'SELECT id | home_team_id|away_team_id=$id',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'matches',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'deleteTeamCascade',
          filters: 'home_team_id|away_team_id=$id | columns=id',
        );
        final res = await _client
            .from('matches')
            .select('id, home_team_id, away_team_id')
            .or('home_team_id.eq.$id,away_team_id.eq.$id');
        if (res is List) {
          matchIds = res.map((e) => (e as Map)['id']?.toString() ?? '').where((e) => e.trim().isNotEmpty).toList();
        }
        AppConfig.sqlLogResult(
          table: 'matches',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'deleteTeamCascade',
          count: matchIds.length,
        );
        _sbResult(rows: matchIds.length);
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'matches',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'deleteTeamCascade',
          error: e,
        );
        _sbResult(rows: 0, error: e);
      }

      if (matchIds.isNotEmpty) {
        try {
          _sbLog(
            table: 'match_events',
            query: 'DELETE match_id IN (${matchIds.length})',
            trace: StackTrace.current,
          );
          AppConfig.sqlLogStart(
            table: 'match_events',
            operation: 'DELETE',
            caller: caller,
            service: _serviceName,
            method: 'deleteTeamCascade',
            filters: 'match_id IN (${matchIds.length})',
          );
          await _client.from('match_events').delete().inFilter('match_id', matchIds);
          AppConfig.sqlLogResult(
            table: 'match_events',
            operation: 'DELETE',
            caller: caller,
            service: _serviceName,
            method: 'deleteTeamCascade',
          );
        } catch (e) {
          AppConfig.sqlLogResult(
            table: 'match_events',
            operation: 'DELETE',
            caller: caller,
            service: _serviceName,
            method: 'deleteTeamCascade',
            error: e,
          );
          _sbResult(rows: 0, error: e);
        }

        try {
          _sbLog(
            table: 'match_lineups',
            query: 'DELETE match_id IN (${matchIds.length})',
            trace: StackTrace.current,
          );
          AppConfig.sqlLogStart(
            table: 'match_lineups',
            operation: 'DELETE',
            caller: caller,
            service: _serviceName,
            method: 'deleteTeamCascade',
            filters: 'match_id IN (${matchIds.length})',
          );
          await _client.from('match_lineups').delete().inFilter('match_id', matchIds);
          AppConfig.sqlLogResult(
            table: 'match_lineups',
            operation: 'DELETE',
            caller: caller,
            service: _serviceName,
            method: 'deleteTeamCascade',
          );
        } catch (e) {
          AppConfig.sqlLogResult(
            table: 'match_lineups',
            operation: 'DELETE',
            caller: caller,
            service: _serviceName,
            method: 'deleteTeamCascade',
            error: e,
          );
          _sbResult(rows: 0, error: e);
        }

        try {
          _sbLog(
            table: 'matches',
            query: 'DELETE id IN (${matchIds.length})',
            trace: StackTrace.current,
          );
          AppConfig.sqlLogStart(
            table: 'matches',
            operation: 'DELETE',
            caller: caller,
            service: _serviceName,
            method: 'deleteTeamCascade',
            filters: 'id IN (${matchIds.length})',
          );
          await _client.from('matches').delete().inFilter('id', matchIds);
          AppConfig.sqlLogResult(
            table: 'matches',
            operation: 'DELETE',
            caller: caller,
            service: _serviceName,
            method: 'deleteTeamCascade',
          );
        } catch (e) {
          AppConfig.sqlLogResult(
            table: 'matches',
            operation: 'DELETE',
            caller: caller,
            service: _serviceName,
            method: 'deleteTeamCascade',
            error: e,
          );
          _sbResult(rows: 0, error: e);
        }
      }

      try {
        _sbLog(
          table: 'rosters',
          query: 'DELETE team_id=$id',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'rosters',
          operation: 'DELETE',
          caller: caller,
          service: _serviceName,
          method: 'deleteTeamCascade',
          filters: 'team_id=$id',
        );
        await _client.from('rosters').delete().eq('team_id', id);
        AppConfig.sqlLogResult(
          table: 'rosters',
          operation: 'DELETE',
          caller: caller,
          service: _serviceName,
          method: 'deleteTeamCascade',
        );
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'rosters',
          operation: 'DELETE',
          caller: caller,
          service: _serviceName,
          method: 'deleteTeamCascade',
          error: e,
        );
        _sbResult(rows: 0, error: e);
      }

      try {
        _sbLog(
          table: 'teams',
          query: 'DELETE id=$id',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'teams',
          operation: 'DELETE',
          caller: caller,
          service: _serviceName,
          method: 'deleteTeamCascade',
          filters: 'id=$id',
        );
        await _client.from('teams').delete().eq('id', id);
        AppConfig.sqlLogResult(
          table: 'teams',
          operation: 'DELETE',
          caller: caller,
          service: _serviceName,
          method: 'deleteTeamCascade',
        );
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'teams',
          operation: 'DELETE',
          caller: caller,
          service: _serviceName,
          method: 'deleteTeamCascade',
          error: e,
        );
        _sbResult(rows: 0, error: e);
      }
    });
  }

  @override
  Future<List<Team>> getTeamsCached(String leagueId, {String? caller}) {
    final id = leagueId.trim();
    if (id.isEmpty) return Future.value(const []);
    return Future(() async {
      try {
        _sbLog(
          table: 'teams',
          query: 'SELECT league_id=$id | order=name asc',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'teams',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'getTeamsCached',
          filters: 'league_id=$id | order=name asc',
        );
        final res = await _client
            .from('teams')
            .select()
            .eq('league_id', id)
            .order('name', ascending: true);
        if (res is! List) {
          AppConfig.sqlLogResult(
            table: 'teams',
            operation: 'SELECT',
            caller: caller,
            service: _serviceName,
            method: 'getTeamsCached',
            count: 0,
          );
          _sbResult(rows: 0);
          return const <Team>[];
        }
        AppConfig.sqlLogResult(
          table: 'teams',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'getTeamsCached',
          count: res.length,
        );
        _sbResult(rows: res.length);
        final list = res.map((e) => Team.fromMap((e as Map).cast<String, dynamic>())).toList();
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return list;
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'teams',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'getTeamsCached',
          error: e,
        );
        _sbResult(rows: 0, error: e);
        return const <Team>[];
      }
    });
  }

  @override
  Future<Team> addTeamAndUpsertCache({
    required String leagueId,
    required String teamName,
    required String logoUrl,
    String? groupId,
    String? groupName,
    String? caller,
  }) {
    final l = leagueId.trim();
    final name = teamName.trim();
    if (l.isEmpty || name.isEmpty) {
      return Future.value(
        Team(id: '', name: name, logoUrl: logoUrl, leagueId: l, groupId: groupId, groupName: groupName),
      );
    }
    return Future(() async {
      try {
        _sbLog(
          table: 'teams',
          query: 'INSERT league_id=$l',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'teams',
          operation: 'INSERT',
          caller: caller,
          service: _serviceName,
          method: 'addTeamAndUpsertCache',
          filters: 'league_id=$l',
        );
        final res = await _client
            .from('teams')
            .insert({
              'league_id': l,
              'name': name,
              'logo_url': logoUrl.trim(),
              'group_id': groupId?.trim(),
              'group_name': groupName?.trim(),
              'created_at': DateTime.now().toIso8601String(),
            })
            .select()
            .limit(1);
        if (res is List && res.isNotEmpty) {
          AppConfig.sqlLogResult(
            table: 'teams',
            operation: 'INSERT',
            caller: caller,
            service: _serviceName,
            method: 'addTeamAndUpsertCache',
            count: 1,
          );
          _sbResult(rows: 1);
          return Team.fromMap((res.first as Map).cast<String, dynamic>());
        }
        AppConfig.sqlLogResult(
          table: 'teams',
          operation: 'INSERT',
          caller: caller,
          service: _serviceName,
          method: 'addTeamAndUpsertCache',
          count: 0,
        );
        _sbResult(rows: 0);
        return Team(id: '', name: name, logoUrl: logoUrl, leagueId: l, groupId: groupId, groupName: groupName);
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'teams',
          operation: 'INSERT',
          caller: caller,
          service: _serviceName,
          method: 'addTeamAndUpsertCache',
          error: e,
        );
        _sbResult(rows: 0, error: e);
        return Team(id: '', name: name, logoUrl: logoUrl, leagueId: l, groupId: groupId, groupName: groupName);
      }
    });
  }

  @override
  Future<int> deleteAllTeams({String? caller}) async {
    try {
      _sbLog(
        table: 'teams',
        query: 'SELECT id | all_rows',
        trace: StackTrace.current,
      );
      AppConfig.sqlLogStart(
        table: 'teams',
        operation: 'SELECT',
        caller: caller,
        service: _serviceName,
        method: 'deleteAllTeams',
        filters: 'columns=id | all_rows',
      );
      final res = await _client.from('teams').select('id').neq('id', '');
      final count = res is List ? res.length : 0;
      AppConfig.sqlLogResult(
        table: 'teams',
        operation: 'SELECT',
        caller: caller,
        service: _serviceName,
        method: 'deleteAllTeams',
        count: count,
      );
      _sbResult(rows: count);

      _sbLog(
        table: 'teams',
        query: 'DELETE all_rows',
        trace: StackTrace.current,
      );
      AppConfig.sqlLogStart(
        table: 'teams',
        operation: 'DELETE',
        caller: caller,
        service: _serviceName,
        method: 'deleteAllTeams',
        filters: 'all_rows',
      );
      await _client.from('teams').delete().neq('id', '');
      AppConfig.sqlLogResult(
        table: 'teams',
        operation: 'DELETE',
        caller: caller,
        service: _serviceName,
        method: 'deleteAllTeams',
        count: count,
      );
      _sbResult(rows: count);
      return count;
    } catch (e) {
      AppConfig.sqlLogResult(
        table: 'teams',
        operation: 'DELETE',
        caller: caller,
        service: _serviceName,
        method: 'deleteAllTeams',
        error: e,
      );
      _sbResult(rows: 0, error: e);
      return 0;
    }
  }

  @override
  Future<int> deleteAllPlayers({String? caller}) async {
    try {
      _sbLog(
        table: 'players',
        query: 'SELECT id | all_rows',
        trace: StackTrace.current,
      );
      AppConfig.sqlLogStart(
        table: 'players',
        operation: 'SELECT',
        caller: caller,
        service: _serviceName,
        method: 'deleteAllPlayers',
        filters: 'columns=id | all_rows',
      );
      final res = await _client.from('players').select('id').neq('id', '');
      final count = res is List ? res.length : 0;
      AppConfig.sqlLogResult(
        table: 'players',
        operation: 'SELECT',
        caller: caller,
        service: _serviceName,
        method: 'deleteAllPlayers',
        count: count,
      );
      _sbResult(rows: count);

      _sbLog(
        table: 'players',
        query: 'DELETE all_rows',
        trace: StackTrace.current,
      );
      AppConfig.sqlLogStart(
        table: 'players',
        operation: 'DELETE',
        caller: caller,
        service: _serviceName,
        method: 'deleteAllPlayers',
        filters: 'all_rows',
      );
      await _client.from('players').delete().neq('id', '');
      AppConfig.sqlLogResult(
        table: 'players',
        operation: 'DELETE',
        caller: caller,
        service: _serviceName,
        method: 'deleteAllPlayers',
        count: count,
      );
      _sbResult(rows: count);
      return count;
    } catch (e) {
      AppConfig.sqlLogResult(
        table: 'players',
        operation: 'DELETE',
        caller: caller,
        service: _serviceName,
        method: 'deleteAllPlayers',
        error: e,
      );
      _sbResult(rows: 0, error: e);
      return 0;
    }
  }

  @override
  Future<void> invalidateTeams(String leagueId, {String? caller}) {
    return Future.value();
  }
}
