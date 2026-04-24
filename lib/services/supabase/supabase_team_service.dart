import 'package:supabase_flutter/supabase_flutter.dart';

import '../interfaces/i_team_service.dart';
import '../../config/app_config.dart';
import '../../models/league.dart';
import '../../models/match.dart';
import '../../models/team.dart';

class SupabaseTeamService implements ITeamService {
  SupabaseTeamService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  DateTime? _readDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  @override
  Stream<List<Team>> watchAllTeams() {
    try {
      AppConfig.sqlLogStart(
        table: 'teams',
        operation: 'STREAM',
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
        error: e,
      );
      return const Stream<List<Team>>.empty();
    }
  }

  @override
  Stream<List<Map<String, dynamic>>> watchAllTeamsRaw() {
    try {
      AppConfig.sqlLogStart(
        table: 'teams',
        operation: 'STREAM',
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
        error: e,
      );
      return const Stream<List<Map<String, dynamic>>>.empty();
    }
  }

  @override
  Future<String> getTeamName(String teamId) {
    return watchTeamName(teamId).first;
  }

  @override
  Future<Team?> getTeamOnce(String teamId) {
    final id = teamId.trim();
    if (id.isEmpty) return Future.value(null);
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'teams',
          operation: 'SELECT',
          filters: 'id=$id | limit=1',
        );
        final res = await _client.from('teams').select().eq('id', id).limit(1);
        if (res is! List || res.isEmpty) {
          AppConfig.sqlLogResult(table: 'teams', operation: 'SELECT', count: 0);
          return null;
        }
        AppConfig.sqlLogResult(table: 'teams', operation: 'SELECT', count: 1);
        return Team.fromMap((res.first as Map).cast<String, dynamic>());
      } catch (e) {
        AppConfig.sqlLogResult(table: 'teams', operation: 'SELECT', error: e);
        return null;
      }
    });
  }

  @override
  Future<PlayerModel?> getPlayerByPhoneOnce(String playerPhone) {
    final phone = playerPhone.trim();
    if (phone.isEmpty) return Future.value(null);
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'players',
          operation: 'SELECT',
          filters: 'phone|phone_raw10|id=$phone | limit=1',
        );
        final res = await _client
            .from('players')
            .select()
            .or('phone.eq.$phone,phone_raw10.eq.$phone,id.eq.$phone')
            .limit(1);
        if (res is! List || res.isEmpty) {
          AppConfig.sqlLogResult(table: 'players', operation: 'SELECT', count: 0);
          return null;
        }
        AppConfig.sqlLogResult(table: 'players', operation: 'SELECT', count: 1);
        final row = (res.first as Map).cast<String, dynamic>();
        final id = (row['id'] ?? row['phone'] ?? row['phone_raw10'] ?? phone).toString();
        return PlayerModel.fromMap(row, id);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'players', operation: 'SELECT', error: e);
        return null;
      }
    });
  }

  @override
  Stream<String> watchTeamName(String teamId) {
    final id = teamId.trim();
    if (id.isEmpty) return const Stream<String>.empty();
    try {
      AppConfig.sqlLogStart(
        table: 'teams',
        operation: 'STREAM',
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
      AppConfig.sqlLogResult(table: 'teams', operation: 'STREAM', error: e);
      return Stream<String>.value(id);
    }
  }

  @override
  Stream<List<Team>> watchTeamsByGroup(String groupId) {
    final gid = groupId.trim();
    if (gid.isEmpty) return const Stream<List<Team>>.empty();
    try {
      AppConfig.sqlLogStart(
        table: 'teams',
        operation: 'STREAM',
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
      AppConfig.sqlLogResult(table: 'teams', operation: 'STREAM', error: e);
      return const Stream<List<Team>>.empty();
    }
  }

  @override
  Stream<List<PlayerModel>> watchPlayers({
    required String teamId,
    String? tournamentId,
  }) {
    final team = teamId.trim();
    final tId = (tournamentId ?? '').trim();
    if (team.isEmpty) return const Stream<List<PlayerModel>>.empty();
    try {
      AppConfig.sqlLogStart(
        table: 'rosters',
        operation: 'STREAM',
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
      AppConfig.sqlLogResult(table: 'rosters', operation: 'STREAM', error: e);
      return const Stream<List<PlayerModel>>.empty();
    }
  }

  @override
  Stream<List<PlayerModel>> watchAllPlayers() {
    try {
      AppConfig.sqlLogStart(
        table: 'players',
        operation: 'STREAM',
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
      AppConfig.sqlLogResult(table: 'players', operation: 'STREAM', error: e);
      return const Stream<List<PlayerModel>>.empty();
    }
  }

  @override
  Future<void> upsertPlayerIdentity({
    required String phone,
    required String name,
    String? birthDate,
    String? mainPosition,
  }) {
    final p = phone.trim();
    final n = name.trim();
    if (p.isEmpty || n.isEmpty) return Future.value();
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'players',
          operation: 'UPSERT',
          filters: 'onConflict=phone | phone=$p',
        );
        await _client.from('players').upsert({
          'phone': p,
          'name': n,
          'birth_date': (birthDate ?? '').trim().isEmpty ? null : birthDate!.trim(),
          'main_position': (mainPosition ?? '').trim().isEmpty ? null : mainPosition!.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'phone');
        AppConfig.sqlLogResult(table: 'players', operation: 'UPSERT', count: 1);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'players', operation: 'UPSERT', error: e);
      }
    });
  }

  @override
  Future<void> updatePlayer({
    required String playerId,
    required Map<String, dynamic> data,
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
          filters: 'id=$id',
        );
        await _client.from('players').update(payload).eq('id', id);
        AppConfig.sqlLogResult(table: 'players', operation: 'UPDATE', count: 1);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'players', operation: 'UPDATE', error: e);
      }
    });
  }

  @override
  Future<Map<String, dynamic>?> getPenaltyForPlayer(String playerId) {
    final id = playerId.trim();
    if (id.isEmpty) return Future.value(null);
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'penalties',
          operation: 'SELECT',
          filters: 'id|player_id=$id | limit=1',
        );
        final res = await _client
            .from('penalties')
            .select()
            .or('id.eq.$id,player_id.eq.$id')
            .limit(1);
        if (res is! List || res.isEmpty) {
          AppConfig.sqlLogResult(table: 'penalties', operation: 'SELECT', count: 0);
          return null;
        }
        AppConfig.sqlLogResult(table: 'penalties', operation: 'SELECT', count: 1);
        return (res.first as Map).cast<String, dynamic>();
      } catch (e) {
        AppConfig.sqlLogResult(table: 'penalties', operation: 'SELECT', error: e);
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
      return clearPenaltyForPlayer(playerId: pId);
    }
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'penalties',
          operation: 'UPSERT',
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
        AppConfig.sqlLogResult(table: 'penalties', operation: 'UPSERT', count: 1);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'penalties', operation: 'UPSERT', error: e);
      }

      try {
        AppConfig.sqlLogStart(
          table: 'players',
          operation: 'UPDATE',
          filters: 'id=$pId | suspended_matches=$matchCount',
        );
        await _client
            .from('players')
            .update({'suspended_matches': matchCount, 'updated_at': DateTime.now().toIso8601String()})
            .eq('id', pId);
        AppConfig.sqlLogResult(table: 'players', operation: 'UPDATE', count: 1);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'players', operation: 'UPDATE', error: e);
      }
    });
  }

  @override
  Future<void> clearPenaltyForPlayer({required String playerId}) {
    final pId = playerId.trim();
    if (pId.isEmpty) return Future.value();
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'penalties',
          operation: 'DELETE',
          filters: 'id|player_id=$pId',
        );
        await _client.from('penalties').delete().or('id.eq.$pId,player_id.eq.$pId');
        AppConfig.sqlLogResult(table: 'penalties', operation: 'DELETE');
      } catch (e) {
        AppConfig.sqlLogResult(table: 'penalties', operation: 'DELETE', error: e);
      }

      try {
        AppConfig.sqlLogStart(
          table: 'players',
          operation: 'UPDATE',
          filters: 'id=$pId | suspended_matches=0',
        );
        await _client
            .from('players')
            .update({'suspended_matches': 0, 'updated_at': DateTime.now().toIso8601String()})
            .eq('id', pId);
        AppConfig.sqlLogResult(table: 'players', operation: 'UPDATE', count: 1);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'players', operation: 'UPDATE', error: e);
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
  }) {
    final t = tournamentId.trim();
    final team = teamId.trim();
    final phone = playerPhone.trim();
    final name = playerName.trim();
    if (t.isEmpty || team.isEmpty || phone.isEmpty) return Future.value();

    final docId = '${phone}_${t}_$team';
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'rosters',
          operation: 'UPSERT',
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
        AppConfig.sqlLogResult(table: 'rosters', operation: 'UPSERT', count: 1);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'rosters', operation: 'UPSERT', error: e);
      }

      try {
        AppConfig.sqlLogStart(
          table: 'transfers',
          operation: 'INSERT',
          filters: 'action=roster_upsert',
        );
        await _client.from('transfers').insert({
          'tournament_id': t,
          'team_id': team,
          'player_phone': phone,
          'action': 'roster_upsert',
          'created_at': DateTime.now().toIso8601String(),
        });
        AppConfig.sqlLogResult(table: 'transfers', operation: 'INSERT', count: 1);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'transfers', operation: 'INSERT', error: e);
      }
    });
  }

  @override
  Future<void> deleteRosterEntry({
    required String tournamentId,
    required String teamId,
    required String playerPhone,
  }) {
    final t = tournamentId.trim();
    final team = teamId.trim();
    final phone = playerPhone.trim();
    if (t.isEmpty || team.isEmpty || phone.isEmpty) return Future.value();
    final id = '${phone}_${t}_$team';
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'rosters',
          operation: 'DELETE',
          filters: 'id=$id',
        );
        await _client.from('rosters').delete().eq('id', id);
        AppConfig.sqlLogResult(table: 'rosters', operation: 'DELETE', count: 1);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'rosters', operation: 'DELETE', error: e);
      }

      try {
        AppConfig.sqlLogStart(
          table: 'transfers',
          operation: 'INSERT',
          filters: 'action=roster_delete',
        );
        await _client.from('transfers').insert({
          'tournament_id': t,
          'team_id': team,
          'player_phone': phone,
          'action': 'roster_delete',
          'created_at': DateTime.now().toIso8601String(),
        });
        AppConfig.sqlLogResult(table: 'transfers', operation: 'INSERT', count: 1);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'transfers', operation: 'INSERT', error: e);
      }
    });
  }

  @override
  Future<bool> isTeamManagerForTournament({
    required String tournamentId,
    required String teamId,
    required String playerPhone,
  }) {
    final t = tournamentId.trim();
    final team = teamId.trim();
    final phone = playerPhone.trim();
    if (t.isEmpty || team.isEmpty || phone.isEmpty) return Future.value(false);
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'rosters',
          operation: 'SELECT',
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
          AppConfig.sqlLogResult(table: 'rosters', operation: 'SELECT', count: 0);
          return false;
        }
        AppConfig.sqlLogResult(table: 'rosters', operation: 'SELECT', count: 1);
        final role = ((res.first as Map)['role'] ?? '').toString().trim();
        return role == 'Takım Sorumlusu' || role == 'Her İkisi';
      } catch (e) {
        AppConfig.sqlLogResult(table: 'rosters', operation: 'SELECT', error: e);
        return false;
      }
    });
  }

  @override
  Future<bool> managerExistsForTeamTournament({
    required String tournamentId,
    required String teamId,
    String? excludePlayerPhone,
  }) {
    final t = tournamentId.trim();
    final team = teamId.trim();
    if (t.isEmpty || team.isEmpty) return Future.value(false);
    final exclude = excludePlayerPhone?.trim();
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'rosters',
          operation: 'SELECT',
          filters: 'tournament_id=$t, team_id=$team',
        );
        final res = await _client
            .from('rosters')
            .select('player_phone, role')
            .eq('tournament_id', t)
            .eq('team_id', team);
        if (res is! List) {
          AppConfig.sqlLogResult(table: 'rosters', operation: 'SELECT', count: 0);
          return false;
        }
        AppConfig.sqlLogResult(table: 'rosters', operation: 'SELECT', count: res.length);
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
        AppConfig.sqlLogResult(table: 'rosters', operation: 'SELECT', error: e);
        return false;
      }
    });
  }

  @override
  Future<List<League>> getTeamActiveTournaments(String teamId) {
    final tId = teamId.trim();
    if (tId.isEmpty) return Future.value(const []);
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'groups',
          operation: 'SELECT',
          filters: 'team_ids contains [$tId]',
        );
        final groupRes = (await _client
                .from('groups')
                .select('league_id, tournament_id')
                .contains('team_ids', [tId]))
            .cast<Map<String, dynamic>>();
        AppConfig.sqlLogResult(table: 'groups', operation: 'SELECT', count: groupRes.length);
        if (groupRes.isEmpty) return const <League>[];

        final leagueIds = <String>{};
        for (final row in groupRes) {
          final id = (row['league_id'] ?? row['tournament_id'] ?? '').toString().trim();
          if (id.isNotEmpty) leagueIds.add(id);
        }
        if (leagueIds.isEmpty) return const <League>[];

        AppConfig.sqlLogStart(
          table: 'leagues',
          operation: 'SELECT',
          filters: 'id IN (${leagueIds.length})',
        );
        final leaguesRes = (await _client
                .from('leagues')
                .select()
                .inFilter('id', leagueIds.toList()))
            .cast<Map<String, dynamic>>();
        AppConfig.sqlLogResult(table: 'leagues', operation: 'SELECT', count: leaguesRes.length);

        final leagues = leaguesRes.map((e) => League.fromMap(e)).toList();
        final active = leagues.where((l) => l.isActive).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return active;
      } catch (e) {
        AppConfig.sqlLogResult(table: 'leagues', operation: 'SELECT', error: e);
        return const <League>[];
      }
    });
  }

  @override
  Future<void> updateTeam(String teamId, Map<String, dynamic> data) {
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

        AppConfig.sqlLogStart(table: 'teams', operation: 'UPDATE', filters: 'id=$id');
        await _client.from('teams').update(payload).eq('id', id);
        AppConfig.sqlLogResult(table: 'teams', operation: 'UPDATE', count: 1);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'teams', operation: 'UPDATE', error: e);
      }
    });
  }

  @override
  Future<void> deleteTeamCascade(String teamId) {
    final id = teamId.trim();
    if (id.isEmpty) return Future.value();
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'groups',
          operation: 'SELECT',
          filters: 'team_ids contains [$id] | columns=id,team_ids',
        );
        final groupsRes =
            (await _client.from('groups').select('id, team_ids').contains('team_ids', [id]))
                .cast<Map<String, dynamic>>();
        AppConfig.sqlLogResult(table: 'groups', operation: 'SELECT', count: groupsRes.length);
        for (final g in groupsRes) {
          final gid = (g['id'] ?? '').toString().trim();
          if (gid.isEmpty) continue;
          final raw = g['team_ids'];
          final list = (raw is List) ? raw.map((e) => e.toString()).toList() : <String>[];
          final next = list.map((e) => e.trim()).where((e) => e.isNotEmpty && e != id).toList();
          AppConfig.sqlLogStart(
            table: 'groups',
            operation: 'UPDATE',
            filters: 'id=$gid | team_ids=[${next.length}]',
          );
          await _client.from('groups').update({'team_ids': next}).eq('id', gid);
          AppConfig.sqlLogResult(table: 'groups', operation: 'UPDATE', count: 1);
        }
      } catch (e) {
        AppConfig.sqlLogResult(table: 'groups', operation: 'UPDATE', error: e);
      }

      List<String> matchIds = const [];
      try {
        AppConfig.sqlLogStart(
          table: 'matches',
          operation: 'SELECT',
          filters: 'home_team_id|away_team_id=$id | columns=id',
        );
        final res = await _client
            .from('matches')
            .select('id, home_team_id, away_team_id')
            .or('home_team_id.eq.$id,away_team_id.eq.$id');
        if (res is List) {
          matchIds = res.map((e) => (e as Map)['id']?.toString() ?? '').where((e) => e.trim().isNotEmpty).toList();
        }
        AppConfig.sqlLogResult(table: 'matches', operation: 'SELECT', count: matchIds.length);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'matches', operation: 'SELECT', error: e);
      }

      if (matchIds.isNotEmpty) {
        try {
          AppConfig.sqlLogStart(
            table: 'match_events',
            operation: 'DELETE',
            filters: 'match_id IN (${matchIds.length})',
          );
          await _client.from('match_events').delete().inFilter('match_id', matchIds);
          AppConfig.sqlLogResult(table: 'match_events', operation: 'DELETE');
        } catch (e) {
          AppConfig.sqlLogResult(table: 'match_events', operation: 'DELETE', error: e);
        }

        try {
          AppConfig.sqlLogStart(
            table: 'match_lineups',
            operation: 'DELETE',
            filters: 'match_id IN (${matchIds.length})',
          );
          await _client.from('match_lineups').delete().inFilter('match_id', matchIds);
          AppConfig.sqlLogResult(table: 'match_lineups', operation: 'DELETE');
        } catch (e) {
          AppConfig.sqlLogResult(table: 'match_lineups', operation: 'DELETE', error: e);
        }

        try {
          AppConfig.sqlLogStart(
            table: 'matches',
            operation: 'DELETE',
            filters: 'id IN (${matchIds.length})',
          );
          await _client.from('matches').delete().inFilter('id', matchIds);
          AppConfig.sqlLogResult(table: 'matches', operation: 'DELETE');
        } catch (e) {
          AppConfig.sqlLogResult(table: 'matches', operation: 'DELETE', error: e);
        }
      }

      try {
        AppConfig.sqlLogStart(table: 'rosters', operation: 'DELETE', filters: 'team_id=$id');
        await _client.from('rosters').delete().eq('team_id', id);
        AppConfig.sqlLogResult(table: 'rosters', operation: 'DELETE');
      } catch (e) {
        AppConfig.sqlLogResult(table: 'rosters', operation: 'DELETE', error: e);
      }

      try {
        AppConfig.sqlLogStart(table: 'teams', operation: 'DELETE', filters: 'id=$id');
        await _client.from('teams').delete().eq('id', id);
        AppConfig.sqlLogResult(table: 'teams', operation: 'DELETE');
      } catch (e) {
        AppConfig.sqlLogResult(table: 'teams', operation: 'DELETE', error: e);
      }
    });
  }

  @override
  Future<List<Team>> getTeamsCached(String leagueId) {
    final id = leagueId.trim();
    if (id.isEmpty) return Future.value(const []);
    return Future(() async {
      try {
        AppConfig.sqlLogStart(
          table: 'teams',
          operation: 'SELECT',
          filters: 'league_id=$id OR tournament_id=$id | order=name asc',
        );
        final res = await _client
            .from('teams')
            .select()
            .or('league_id.eq.$id,tournament_id.eq.$id')
            .order('name', ascending: true);
        if (res is! List) {
          AppConfig.sqlLogResult(table: 'teams', operation: 'SELECT', count: 0);
          return const <Team>[];
        }
        AppConfig.sqlLogResult(table: 'teams', operation: 'SELECT', count: res.length);
        final list = res.map((e) => Team.fromMap((e as Map).cast<String, dynamic>())).toList();
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return list;
      } catch (e) {
        AppConfig.sqlLogResult(table: 'teams', operation: 'SELECT', error: e);
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
        AppConfig.sqlLogStart(
          table: 'teams',
          operation: 'INSERT',
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
          AppConfig.sqlLogResult(table: 'teams', operation: 'INSERT', count: 1);
          return Team.fromMap((res.first as Map).cast<String, dynamic>());
        }
        AppConfig.sqlLogResult(table: 'teams', operation: 'INSERT', count: 0);
        return Team(id: '', name: name, logoUrl: logoUrl, leagueId: l, groupId: groupId, groupName: groupName);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'teams', operation: 'INSERT', error: e);
        return Team(id: '', name: name, logoUrl: logoUrl, leagueId: l, groupId: groupId, groupName: groupName);
      }
    });
  }

  @override
  Future<int> deleteAllTeams() async {
    try {
      AppConfig.sqlLogStart(table: 'teams', operation: 'SELECT', filters: 'columns=id | all_rows');
      final res = await _client.from('teams').select('id').neq('id', '');
      final count = res is List ? res.length : 0;
      AppConfig.sqlLogResult(table: 'teams', operation: 'SELECT', count: count);

      AppConfig.sqlLogStart(table: 'teams', operation: 'DELETE', filters: 'all_rows');
      await _client.from('teams').delete().neq('id', '');
      AppConfig.sqlLogResult(table: 'teams', operation: 'DELETE', count: count);
      return count;
    } catch (e) {
      AppConfig.sqlLogResult(table: 'teams', operation: 'DELETE', error: e);
      return 0;
    }
  }

  @override
  Future<int> deleteAllPlayers() async {
    try {
      AppConfig.sqlLogStart(table: 'players', operation: 'SELECT', filters: 'columns=id | all_rows');
      final res = await _client.from('players').select('id').neq('id', '');
      final count = res is List ? res.length : 0;
      AppConfig.sqlLogResult(table: 'players', operation: 'SELECT', count: count);

      AppConfig.sqlLogStart(table: 'players', operation: 'DELETE', filters: 'all_rows');
      await _client.from('players').delete().neq('id', '');
      AppConfig.sqlLogResult(table: 'players', operation: 'DELETE', count: count);
      return count;
    } catch (e) {
      AppConfig.sqlLogResult(table: 'players', operation: 'DELETE', error: e);
      return 0;
    }
  }

  @override
  Future<void> invalidateTeams(String leagueId) {
    return Future.value();
  }
}
