import 'package:supabase_flutter/supabase_flutter.dart';

import '../interfaces/i_team_service.dart';
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
      return _client
          .from('teams')
          .stream(primaryKey: ['id'])
          .order('name', ascending: true)
          .map((rows) => rows.map((r) => Team.fromMap(r)).toList());
    } catch (_) {
      return const Stream<List<Team>>.empty();
    }
  }

  @override
  Stream<List<Map<String, dynamic>>> watchAllTeamsRaw() {
    try {
      return _client
          .from('teams')
          .stream(primaryKey: ['id'])
          .order('name', ascending: true)
          .map((rows) => rows.map((r) => Map<String, dynamic>.from(r)).toList());
    } catch (_) {
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
    return _client.from('teams').select().eq('id', id).limit(1).then((res) {
      if (res is! List || res.isEmpty) return null;
      return Team.fromMap((res.first as Map).cast<String, dynamic>());
    }).catchError((_) => null);
  }

  @override
  Future<PlayerModel?> getPlayerByPhoneOnce(String playerPhone) {
    final phone = playerPhone.trim();
    if (phone.isEmpty) return Future.value(null);
    return _client
        .from('players')
        .select()
        .or('phone.eq.$phone,phone_raw10.eq.$phone,id.eq.$phone')
        .limit(1)
        .then((res) {
          if (res is! List || res.isEmpty) return null;
          final row = (res.first as Map).cast<String, dynamic>();
          final id = (row['id'] ?? row['phone'] ?? row['phone_raw10'] ?? phone).toString();
          return PlayerModel.fromMap(row, id);
        })
        .catchError((_) => null);
  }

  @override
  Stream<String> watchTeamName(String teamId) {
    final id = teamId.trim();
    if (id.isEmpty) return const Stream<String>.empty();
    try {
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
    } catch (_) {
      return Stream<String>.value(id);
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
    } catch (_) {
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
    return _client
        .from('players')
        .upsert({
          'phone': p,
          'name': n,
          'birth_date': (birthDate ?? '').trim().isEmpty ? null : birthDate!.trim(),
          'main_position': (mainPosition ?? '').trim().isEmpty ? null : mainPosition!.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'phone')
        .catchError((_) {});
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
    return _client
        .from('rosters')
        .upsert({
          'id': docId,
          'tournament_id': t,
          'team_id': team,
          'player_phone': phone,
          'player_name': name,
          'jersey_number': (jerseyNumber ?? '').trim().isEmpty ? null : jerseyNumber!.trim(),
          'role': role.trim().isEmpty ? 'Futbolcu' : role.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'id')
        .then((_) async {
          try {
            await _client.from('transfers').insert({
              'tournament_id': t,
              'team_id': team,
              'player_phone': phone,
              'action': 'roster_upsert',
              'created_at': DateTime.now().toIso8601String(),
            });
          } catch (_) {}
        })
        .catchError((_) {});
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
    return _client
        .from('rosters')
        .select('role')
        .eq('tournament_id', t)
        .eq('team_id', team)
        .eq('player_phone', phone)
        .limit(1)
        .then((res) {
          if (res is! List || res.isEmpty) return false;
          final role = ((res.first as Map)['role'] ?? '').toString().trim();
          return role == 'Takım Sorumlusu' || role == 'Her İkisi';
        })
        .catchError((_) => false);
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
    return _client
        .from('rosters')
        .select('player_phone, role')
        .eq('tournament_id', t)
        .eq('team_id', team)
        .then((res) {
          if (res is! List) return false;
          for (final rowAny in res) {
            final row = (rowAny as Map).cast<String, dynamic>();
            final phone = (row['player_phone'] ?? '').toString().trim();
            if (exclude != null && exclude.isNotEmpty && phone == exclude) continue;
            final role = (row['role'] ?? '').toString().trim();
            final resolvedRole = role.isEmpty ? 'Futbolcu' : role;
            if (resolvedRole == 'Takım Sorumlusu' || resolvedRole == 'Her İkisi') return true;
          }
          return false;
        })
        .catchError((_) => false);
  }

  @override
  Future<List<Team>> getTeamsCached(String leagueId) {
    final id = leagueId.trim();
    if (id.isEmpty) return Future.value(const []);
    return _client
        .from('teams')
        .select()
        .or('league_id.eq.$id,tournament_id.eq.$id')
        .order('name', ascending: true)
        .then((res) {
          if (res is! List) return const <Team>[];
          final list = res.map((e) => Team.fromMap((e as Map).cast<String, dynamic>())).toList();
          list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          return list;
        })
        .catchError((_) => const <Team>[]);
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
    return _client
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
        .limit(1)
        .then((res) {
          if (res is List && res.isNotEmpty) {
            return Team.fromMap((res.first as Map).cast<String, dynamic>());
          }
          return Team(id: '', name: name, logoUrl: logoUrl, leagueId: l, groupId: groupId, groupName: groupName);
        })
        .catchError((_) => Team(id: '', name: name, logoUrl: logoUrl, leagueId: l, groupId: groupId, groupName: groupName));
  }

  @override
  Future<void> invalidateTeams(String leagueId) {
    return Future.value();
  }
}
