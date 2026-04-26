import 'dart:math';
import 'dart:typed_data';

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

  Map<String, String?> _splitFullName(String fullName) {
    final s = fullName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (s.isEmpty) return const {'name': null, 'surname': null};
    final parts = s.split(' ');
    if (parts.length == 1) return {'name': parts.first, 'surname': null};
    return {'name': parts.first, 'surname': parts.sublist(1).join(' ')};
  }

  Map<String, dynamic> _withDisplayName(Map<String, dynamic> row) {
    final name = (row['name'] ?? '').toString().trim();
    final surname = (row['surname'] ?? '').toString().trim();
    final display = [name, surname].where((e) => e.trim().isNotEmpty).join(' ').trim();
    if (display.isEmpty) return row;
    return {...row, 'name': display};
  }

  Future<void> _bestEffortUpdatePlayerIdentityFields({
    required String playerId,
    String? jerseyNumber,
    String? role,
  }) async {
    final pid = playerId.trim();
    if (pid.isEmpty) return;
    final j = (jerseyNumber ?? '').replaceAll(RegExp(r'\D'), '').trim();
    final r = (role ?? '').trim();
    if (j.isEmpty && r.isEmpty) return;

    if (r.isNotEmpty) {
      try {
        await _client.from('players').update({
          'role': r,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', pid);
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST204') rethrow;
      }
    }

    if (j.isNotEmpty) {
      final n = int.tryParse(j);
      if (n == null) return;
      try {
        await _client.from('players').update({
          'default_jersey_number': n,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', pid);
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST204') rethrow;
      }
    }
  }

  bool _isUuid(String input) {
    final s = input.trim();
    return RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$')
        .hasMatch(s);
  }

  String _normalizePhoneToRaw10(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    var d = digits;
    if (d.startsWith('90') && d.length >= 12) {
      d = d.substring(2);
    }
    if (d.startsWith('0')) {
      d = d.substring(1);
    }
    if (d.length > 10) {
      d = d.substring(d.length - 10);
    }
    return d;
  }

  String _uuidV4() {
    final rnd = Random.secure();
    final bytes = Uint8List(16);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = rnd.nextInt(256);
    }
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String hexByte(int b) => b.toRadixString(16).padLeft(2, '0');
    final hex = bytes.map(hexByte).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

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
    final phone = _normalizePhoneToRaw10(playerPhone.trim());
    if (phone.isEmpty) return Future.value(null);
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'players',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'getPlayerByPhoneOnce',
          filters: 'phone|id=$phone | limit=1',
        );
        final clauses = <String>[
          'phone.eq.$phone',
          if (_isUuid(phone)) 'id.eq.$phone',
        ];
        final res = await _client
            .from('players')
            .select()
            .or(clauses.join(','))
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
        final row = _withDisplayName((res.first as Map).cast<String, dynamic>());
        final id = (row['id'] ?? row['phone'] ?? phone).toString();
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
    if (tId.isEmpty) return const Stream<List<PlayerModel>>.empty();
    try {
      AppConfig.sqlLogStart(
        table: 'league_team_players',
        operation: 'SELECT',
        caller: caller,
        service: _serviceName,
        method: 'watchPlayers',
        filters: 'team_id=$team, league_id=$tId | select=player_id',
      );
      return Stream.fromFuture(() async {
        final res = await _client
            .from('league_team_players')
            .select('player_id')
            .eq('team_id', team) 
            .eq('league_id', tId);
        if (res is! List) return const <PlayerModel>[];

        final rows = res.cast<Map<String, dynamic>>();
        final ids = <String>{};
        for (final r in rows) {
          final pid = (r['player_id'] ?? '').toString().trim();
          if (pid.isNotEmpty) ids.add(pid);
        }
        if (ids.isEmpty) return const <PlayerModel>[];

        final playersRes = await _client
            .from('players')
            .select()
            .inFilter('id', ids.toList());
        if (playersRes is! List) return const <PlayerModel>[];

        final list = <PlayerModel>[];
        for (final any in playersRes) {
          if (any is! Map) continue;
          final row = _withDisplayName(any.cast<String, dynamic>());
          final pid = (row['id'] ?? '').toString().trim();
          if (pid.isEmpty) continue;
          final merged = <String, dynamic>{
            ...row,
            'league_id': tId,
            'team_id': team,
          };
          list.add(PlayerModel.fromMap(merged, pid));
        }

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
      }());
    } catch (e) {
      AppConfig.sqlLogResult(
        table: 'league_team_players',
        operation: 'SELECT',
        caller: caller,
        service: _serviceName,
        method: 'watchPlayers',
        error: e,
      );
      return const Stream<List<PlayerModel>>.empty();
    }
  }

  Future<String?> _resolvePlayerId(String phoneOrId, {String? caller, String? method}) async {
    final key = phoneOrId.trim();
    if (key.isEmpty) return null;
    final raw10 = _normalizePhoneToRaw10(key);
    try {
      AppConfig.sqlLogStart(
        table: 'players',
        operation: 'SELECT',
        caller: caller,
        service: _serviceName,
        method: method ?? '_resolvePlayerId',
        filters: 'id|phone=$key | raw10=$raw10 | limit=1',
      );
      final clauses = <String>[
        'phone.eq.$key',
        if (_isUuid(key)) 'id.eq.$key',
        if (raw10.isNotEmpty && raw10 != key) 'phone.eq.$raw10',
        if (raw10.isNotEmpty && raw10 != key && _isUuid(raw10)) 'id.eq.$raw10',
      ];
      final res = await _client
          .from('players')
          .select('id')
          .or(clauses.join(','))
          .limit(1);
      if (res is! List || res.isEmpty) {
        AppConfig.sqlLogResult(
          table: 'players',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: method ?? '_resolvePlayerId',
          count: 0,
        );
        return null;
      }
      final row = (res.first as Map).cast<String, dynamic>();
      final resolvedId = (row['id'] ?? '').toString().trim();
      if (resolvedId.isEmpty) {
        AppConfig.sqlLogResult(
          table: 'players',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: method ?? '_resolvePlayerId',
          count: 0,
        );
        return null;
      }
      AppConfig.sqlLogResult(
        table: 'players',
        operation: 'SELECT',
        caller: caller,
        service: _serviceName,
        method: method ?? '_resolvePlayerId',
        count: 1,
      );
      return resolvedId;
    } catch (e) {
      AppConfig.sqlLogResult(
        table: 'players',
        operation: 'SELECT',
        caller: caller,
        service: _serviceName,
        method: method ?? '_resolvePlayerId',
        error: e,
      );
      return null;
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
              final row = _withDisplayName(Map<String, dynamic>.from(r));
              final id = (row['id'] ?? row['phone'] ?? '').toString();
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
    String? nationalId,
    String? birthDate,
    String? mainPosition,
    String? preferredFoot,
    int? height,
    int? weight,
    String? caller,
  }) {
    final p = _normalizePhoneToRaw10(phone.trim());
    final n = name.trim();
    if (p.isEmpty || n.isEmpty) return Future.value();
    final split = _splitFullName(n);
    final firstName = (split['name'] ?? '').trim();
    final surname = (split['surname'] ?? '').trim();
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'players',
          operation: 'INSERT',
          caller: caller,
          service: _serviceName,
          method: 'upsertPlayerIdentity',
          filters: 'phone=$p',
        );
        await _client.from('players').insert({
          'phone': p,
          'name': firstName,
          'surname': surname.isEmpty ? null : surname,
          'national_id': (nationalId ?? '').trim().isEmpty ? null : nationalId!.trim(),
          'birth_date': (birthDate ?? '').trim().isEmpty ? null : birthDate!.trim(),
          'main_position': (mainPosition ?? '').trim().isEmpty ? null : mainPosition!.trim(),
          'preferred_foot': (preferredFoot ?? '').trim().isEmpty ? null : preferredFoot!.trim(),
          'height': height,
          'weight': weight,
          'updated_at': DateTime.now().toIso8601String(),
        });
        AppConfig.sqlLogResult(
          table: 'players',
          operation: 'INSERT',
          caller: caller,
          service: _serviceName,
          method: 'upsertPlayerIdentity',
          count: 1,
        );
      } catch (e) {
        if (e is PostgrestException && e.code == '23505') return;
        AppConfig.sqlLogResult(
          table: 'players',
          operation: 'INSERT',
          caller: caller,
          service: _serviceName,
          method: 'upsertPlayerIdentity',
          error: e,
        );
        rethrow;
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
            case 'subPosition':
              return 'sub_position';
            case 'preferredFoot':
              return 'preferred_foot';
            case 'nationalId':
              return 'national_id';
            case 'defaultJerseyNumber':
              return 'default_jersey_number';
            case 'height':
              return 'height';
            case 'weight':
              return 'weight';
            case 'phoneRaw10':
              return 'phone';
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
          filters: 'id|phone=$id',
        );
        final raw10 = _normalizePhoneToRaw10(id);
        final clauses = <String>[
          'phone.eq.$id',
          if (raw10.isNotEmpty && raw10 != id) 'phone.eq.$raw10',
          if (_isUuid(id)) 'id.eq.$id',
          if (raw10.isNotEmpty && raw10 != id && _isUuid(raw10)) 'id.eq.$raw10',
        ];
        await _client
            .from('players')
            .update(payload)
            .or(clauses.join(','));
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
        rethrow;
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
    final phone = _normalizePhoneToRaw10(playerPhone.trim());
    final name = playerName.trim();
    if (t.isEmpty || team.isEmpty || phone.isEmpty) return Future.value();
    return Future(() async {
      var pid = (await _resolvePlayerId(phone, caller: caller, method: 'upsertRosterEntry'))?.trim() ?? '';
      if (pid.isEmpty) {
        try {
          final split = _splitFullName(name);
          final firstName = (split['name'] ?? '').trim();
          final surname = (split['surname'] ?? '').trim();
          AppConfig.sqlLogStart(
            table: 'players',
            operation: 'INSERT',
            caller: caller,
            service: _serviceName,
            method: 'upsertRosterEntry',
            filters: 'phone=$phone | select=id',
          );
          final inserted = await _client.from('players').insert({
            'phone': phone,
            'name': firstName.isEmpty ? name : firstName,
            'surname': surname.isEmpty ? null : surname,
            'updated_at': DateTime.now().toIso8601String(),
          }).select('id').limit(1);
          if (inserted is List && inserted.isNotEmpty && inserted.first is Map) {
            final row = (inserted.first as Map).cast<String, dynamic>();
            pid = (row['id'] ?? '').toString().trim();
          }
          AppConfig.sqlLogResult(
            table: 'players',
            operation: 'INSERT',
            caller: caller,
            service: _serviceName,
            method: 'upsertRosterEntry',
            count: pid.isEmpty ? 0 : 1,
          );
        } catch (e) {
          if (e is PostgrestException && e.code == '23505') {
            try {
              final raw10 = _normalizePhoneToRaw10(phone);
              final clauses = <String>[
                'phone.eq.$phone',
                if (raw10.isNotEmpty && raw10 != phone) 'phone.eq.$raw10',
                if (_isUuid(phone)) 'id.eq.$phone',
                if (raw10.isNotEmpty && raw10 != phone && _isUuid(raw10)) 'id.eq.$raw10',
              ];
              final res = await _client
                  .from('players')
                  .select('id')
                  .or(clauses.join(','))
                  .limit(1);
              if (res is List && res.isNotEmpty && res.first is Map) {
                final row = (res.first as Map).cast<String, dynamic>();
                pid = (row['id'] ?? '').toString().trim();
              }
              if (pid.isEmpty) {
                throw Exception(
                  'Oyuncu mevcut ama players SELECT sonucu 0 satır dönüyor. Bu genelde RLS policy (USING) filtrelediği için olur (phone=$phone).',
                );
              }
            } on PostgrestException catch (se) {
              throw Exception(
                'players SELECT engellendi. code=${se.code} message=${se.message} details=${se.details} hint=${se.hint}',
              );
            }
          } else {
            rethrow;
          }
        }
      }
      if (pid.isEmpty) {
        throw Exception('Oyuncu ID bulunamadı (phone=$phone).');
      }
      try {
        _sbLog(
          table: 'league_team_players',
          query: 'INSERT | league_id=$t, team_id=$team, player_id=$pid',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'league_team_players',
          operation: 'INSERT',
          caller: caller,
          service: _serviceName,
          method: 'upsertRosterEntry',
          filters: 'league_id=$t, team_id=$team, player_id=$pid',
        );
        final base = <String, dynamic>{
          'league_id': t,
          'team_id': team,
          'player_id': pid,
        };
        await _client.from('league_team_players').insert(base);
        await _bestEffortUpdatePlayerIdentityFields(
          playerId: pid,
          jerseyNumber: jerseyNumber,
          role: role.trim().isEmpty ? null : role.trim(),
        );
        AppConfig.sqlLogResult(
          table: 'league_team_players',
          operation: 'INSERT',
          caller: caller,
          service: _serviceName,
          method: 'upsertRosterEntry',
          count: 1,
        );
        _sbResult(rows: 1);
      } catch (e) {
        if (e is PostgrestException &&
            (e.code == '42501' ||
                (e.message ?? '').toLowerCase().contains('row-level security'))) {
          throw Exception(
            'league_team_players INSERT RLS tarafından engellendi (code=42501). '
            'Bu client tarafında kodla çözülemez; Supabase tarafında policy açılmalı. '
            'En basit test için:\n'
            'create policy "allow insert league_team_players" on public.league_team_players '
            'for insert to anon, authenticated with check (true);',
          );
        }
        AppConfig.sqlLogResult(
          table: 'league_team_players',
          operation: 'INSERT',
          caller: caller,
          service: _serviceName,
          method: 'upsertRosterEntry',
          error: e,
        );
        _sbResult(rows: 0, error: e);
        rethrow;
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
    return Future(() async {
      final pid = (await _resolvePlayerId(phone, caller: caller, method: 'deleteRosterEntry'))?.trim() ?? '';
      if (pid.isEmpty) return;
      try {
        _sbLog(
          table: 'league_team_players',
          query: 'DELETE league_id=$t, team_id=$team, player_id=$pid',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'league_team_players',
          operation: 'DELETE',
          caller: caller,
          service: _serviceName,
          method: 'deleteRosterEntry',
          filters: 'league_id=$t, team_id=$team, player_id=$pid',
        );
        await _client
            .from('league_team_players')
            .delete()
            .eq('league_id', t)
            .eq('team_id', team)
            .eq('player_id', pid);
        AppConfig.sqlLogResult(
          table: 'league_team_players',
          operation: 'DELETE',
          caller: caller,
          service: _serviceName,
          method: 'deleteRosterEntry',
          count: 1,
        );
        _sbResult(rows: 1);
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'league_team_players',
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
      final pid =
          (await _resolvePlayerId(phone, caller: caller, method: 'isTeamManagerForTournament'))
                  ?.trim() ??
              '';
      if (pid.isEmpty) return false;
      try {
        _sbLog(
          table: 'league_team_players',
          query: 'SELECT id | league_id=$t, team_id=$team, player_id=$pid | limit=1',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'league_team_players',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'isTeamManagerForTournament',
          filters: 'league_id=$t, team_id=$team, player_id=$pid | limit=1',
        );
        final linkRes = await _client
            .from('league_team_players')
            .select('id')
            .eq('league_id', t)
            .eq('team_id', team)
            .eq('player_id', pid)
            .limit(1);
        if (linkRes is! List || linkRes.isEmpty) {
          AppConfig.sqlLogResult(
            table: 'league_team_players',
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
          table: 'league_team_players',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'isTeamManagerForTournament',
          count: 1,
        );
        _sbResult(rows: 1);
        final pr = await _client
            .from('players')
            .select('role')
            .eq('id', pid)
            .limit(1);
        if (pr is! List || pr.isEmpty) return false;
        final role = ((pr.first as Map)['role'] ?? '').toString().trim();
        return role == 'Takım Sorumlusu' || role == 'Her İkisi';
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'league_team_players',
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
          table: 'league_team_players',
          query: 'SELECT player_id | league_id=$t, team_id=$team',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'league_team_players',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'managerExistsForTeamTournament',
          filters: 'league_id=$t, team_id=$team',
        );
        final res = await _client
            .from('league_team_players')
            .select('player_id')
            .eq('league_id', t)
            .eq('team_id', team);
        if (res is! List) {
          AppConfig.sqlLogResult(
            table: 'league_team_players',
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
          table: 'league_team_players',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'managerExistsForTeamTournament',
          count: res.length,
        );
        _sbResult(rows: res.length);
        final excludeId = (exclude == null || exclude.isEmpty)
            ? ''
            : ((await _resolvePlayerId(
                  exclude,
                  caller: caller,
                  method: 'managerExistsForTeamTournament',
                )) ??
                '')
                .trim();
        final ids = <String>{};
        for (final rowAny in res) {
          final row = (rowAny as Map).cast<String, dynamic>();
          final pid = (row['player_id'] ?? '').toString().trim();
          if (excludeId.isNotEmpty && pid == excludeId) continue;
          if (pid.isNotEmpty) ids.add(pid);
        }
        if (ids.isEmpty) return false;

        final pr = await _client
            .from('players')
            .select('id, role')
            .inFilter('id', ids.toList());
        if (pr is! List) return false;
        for (final any in pr) {
          if (any is! Map) continue;
          final role = (any['role'] ?? '').toString().trim();
          if (role == 'Takım Sorumlusu' || role == 'Her İkisi') return true;
        }
        return false;
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'league_team_players',
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
