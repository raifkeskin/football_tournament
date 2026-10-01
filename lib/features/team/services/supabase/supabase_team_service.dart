import '../../../../core/utils/table_feed.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../interfaces/i_team_service.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/utils/resilient_stream.dart';
import '../../../tournament/models/league.dart';
import '../../../match/models/match.dart';
import '../../models/team.dart';

class SupabaseTeamService implements ITeamService {
  SupabaseTeamService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

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
    final display = [
      name,
      surname,
    ].where((e) => e.trim().isNotEmpty).join(' ').trim();
    if (display.isEmpty) return row;
    return {...row, 'name': display};
  }

  Future<void> _bestEffortUpdatePlayerIdentityFields({
    required String playerId,
    String? role,
  }) async {
    final pid = playerId.trim();
    if (pid.isEmpty) return;
    final r = (role ?? '').trim();
    if (r.isEmpty) return;

    if (r.isNotEmpty) {
      try {
        await _client
            .from('players')
            .update({'role': r})
            .eq('id', pid);
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST204') rethrow;
      }
    }
  }

  /// Postgres her 8-4-4-4-12 onaltılık değeri uuid kabul eder; sürüm/varyant
  /// hanesi kontrol edilmez (ör. 66666666-aaaa-0000-0000-000000000001).
  bool _isUuid(String input) {
    final s = input.trim();
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(s);
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

  static Map<String, String> _traceInfo(StackTrace trace) {
    final lines = trace.toString().split('\n');
    final line = lines.length > 1
        ? lines[1]
        : (lines.isNotEmpty ? lines.first : '');

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

  /// Tüm takımlar için uygulama genelinde tek, paylaşılan akış. Birden fazla
  /// ekran (ve Puan Durumu'ndaki her grup tablosu) aynı kanalı kullanır;
  /// son liste önbellekte tutulur, ekran açılınca hemen gösterilir.
  List<Team>? _allTeamsCache;
  Stream<List<Team>>? _allTeamsFeed;

  @override
  Stream<List<Team>> watchAllTeams({String? caller}) {
    return _allTeamsFeed ??= resilientStream(() async* {
      final cached = _allTeamsCache;
      if (cached != null) yield cached;
      await for (final list in _watchAllTeamsSource(caller: caller)) {
        _allTeamsCache = list;
        yield list;
      }
    });
  }

  Stream<List<Team>> _watchAllTeamsSource({String? caller}) {
    try {
      _sbLog(
        table: 'season_teams',
        query: 'STREAM order=team_id asc (join teams + groups)',
        trace: StackTrace.current,
      );
      AppConfig.sqlLogStart(
        table: 'season_teams',
        operation: 'STREAM',
        caller: caller,
        service: _serviceName,
        method: 'watchAllTeams',
        filters: 'order=team_id asc',
      );
      return resilientStream(
      () => _client
          .from('season_teams')
          .stream(primaryKey: ['id'])
          .order('team_id', ascending: true)
          .asyncMap((rows) async {
            final links = rows.cast<Map<String, dynamic>>();
            final teamIds = <String>{};
            final groupIds = <String>{};
            for (final r in links) {
              final tid = (r['team_id'] ?? '').toString().trim();
              if (tid.isNotEmpty) teamIds.add(tid);
              final gid = (r['group_id'] ?? '').toString().trim();
              if (gid.isNotEmpty) groupIds.add(gid);
            }

            final teamById = <String, Map<String, dynamic>>{};
            if (teamIds.isNotEmpty) {
              final res = await _client
                  .from('teams')
                  .select()
                  .inFilter('id', teamIds.toList());
              for (final any in res) {
                final row = (any as Map).cast<String, dynamic>();
                final id = (row['id'] ?? '').toString().trim();
                if (id.isNotEmpty) teamById[id] = row;
              }
            }

            final groupNameById = <String, String>{};
            if (groupIds.isNotEmpty) {
              final res = await _client
                  .from('groups')
                  .select('id, name')
                  .inFilter('id', groupIds.toList());
              for (final any in res) {
                final row = (any as Map).cast<String, dynamic>();
                final id = (row['id'] ?? '').toString().trim();
                if (id.isEmpty) continue;
                final name = (row['name'] ?? '').toString().trim();
                if (name.isNotEmpty) groupNameById[id] = name;
              }
            }

            final list = <Team>[];
            for (final link in links) {
              final tid = (link['team_id'] ?? '').toString().trim();
              final team = teamById[tid];
              if (team == null) continue;
              final gid = (link['group_id'] ?? '').toString().trim();
              final merged = <String, dynamic>{
                ...link,
                'team': team,
                if ((link['group_name'] ?? '').toString().trim().isEmpty &&
                    gid.isNotEmpty &&
                    (groupNameById[gid] ?? '').trim().isNotEmpty)
                  'group_name': groupNameById[gid],
                if (gid.isNotEmpty &&
                    (groupNameById[gid] ?? '').trim().isNotEmpty)
                  'group': {'id': gid, 'name': groupNameById[gid]},
              };
              list.add(Team.fromMap(merged));
            }
            list.sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
            return list;
          }),
    );
    } catch (e) {
      AppConfig.sqlLogResult(
        table: 'season_teams',
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
        table: 'season_teams',
        query: 'STREAM order=team_id asc (join teams + groups)',
        trace: StackTrace.current,
      );
      AppConfig.sqlLogStart(
        table: 'season_teams',
        operation: 'STREAM',
        caller: caller,
        service: _serviceName,
        method: 'watchAllTeamsRaw',
        filters: 'order=team_id asc',
      );
      return resilientStream(
      () => _client
          .from('season_teams')
          .stream(primaryKey: ['id'])
          .order('team_id', ascending: true)
          .asyncMap((rows) async {
            final links = rows.cast<Map<String, dynamic>>();
            final teamIds = <String>{};
            final groupIds = <String>{};
            for (final r in links) {
              final tid = (r['team_id'] ?? '').toString().trim();
              if (tid.isNotEmpty) teamIds.add(tid);
              final gid = (r['group_id'] ?? '').toString().trim();
              if (gid.isNotEmpty) groupIds.add(gid);
            }

            final teamById = <String, Map<String, dynamic>>{};
            if (teamIds.isNotEmpty) {
              final res = await _client
                  .from('teams')
                  .select()
                  .inFilter('id', teamIds.toList());
              for (final any in res) {
                final row = (any as Map).cast<String, dynamic>();
                final id = (row['id'] ?? '').toString().trim();
                if (id.isNotEmpty) teamById[id] = row;
              }
            }

            final groupNameById = <String, String>{};
            if (groupIds.isNotEmpty) {
              final res = await _client
                  .from('groups')
                  .select('id, name')
                  .inFilter('id', groupIds.toList());
              for (final any in res) {
                final row = (any as Map).cast<String, dynamic>();
                final id = (row['id'] ?? '').toString().trim();
                if (id.isEmpty) continue;
                final name = (row['name'] ?? '').toString().trim();
                if (name.isNotEmpty) groupNameById[id] = name;
              }
            }

            final out = <Map<String, dynamic>>[];
            for (final link in links) {
              final tid = (link['team_id'] ?? '').toString().trim();
              final team = teamById[tid];
              if (team == null) continue;
              final gid = (link['group_id'] ?? '').toString().trim();
              out.add({
                ...link,
                'team': team,
                if ((link['group_name'] ?? '').toString().trim().isEmpty &&
                    gid.isNotEmpty &&
                    (groupNameById[gid] ?? '').trim().isNotEmpty)
                  'group_name': groupNameById[gid],
                if (gid.isNotEmpty &&
                    (groupNameById[gid] ?? '').trim().isNotEmpty)
                  'group': {'id': gid, 'name': groupNameById[gid]},
              });
            }
            return out;
          }),
    );
    } catch (e) {
      AppConfig.sqlLogResult(
        table: 'season_teams',
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
        if (res.isEmpty) {
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
  Future<PlayerModel?> getPlayerByPhoneOnce(
    String playerPhone, {
    String? caller,
  }) {
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
        if (res.isEmpty) {
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
        final row = _withDisplayName(
          (res.first as Map).cast<String, dynamic>(),
        );
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
      return watchTableRows(
        _client,
        table: 'teams',
        column: 'id',
        value: id,
      ).map((rows) {
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
        table: 'season_teams',
        operation: 'STREAM',
        caller: caller,
        service: _serviceName,
        method: 'watchTeamsByGroup',
        filters:
            'primaryKey=id | clientFilter=group_id=$gid | order=team_id asc',
      );
      return resilientStream(
      () => _client
          .from('season_teams')
          .stream(primaryKey: ['id'])
          .eq('group_id', gid)
          .order('team_id', ascending: true)
          .asyncMap((rows) async {
            final links = rows.cast<Map<String, dynamic>>();
            final teamIds = <String>{};
            for (final r in links) {
              final tid = (r['team_id'] ?? '').toString().trim();
              if (tid.isNotEmpty) teamIds.add(tid);
            }
            final teamById = <String, Map<String, dynamic>>{};
            if (teamIds.isNotEmpty) {
              final res = await _client
                  .from('teams')
                  .select()
                  .inFilter('id', teamIds.toList());
              for (final any in res) {
                final row = (any as Map).cast<String, dynamic>();
                final id = (row['id'] ?? '').toString().trim();
                if (id.isNotEmpty) teamById[id] = row;
              }
            }
            final list = <Team>[];
            for (final link in links) {
              final tid = (link['team_id'] ?? '').toString().trim();
              final team = teamById[tid];
              if (team == null) continue;
              list.add(Team.fromMap({...link, 'team': team}));
            }
            list.sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
            return list;
          }),
    );
    } catch (e) {
      AppConfig.sqlLogResult(
        table: 'season_teams',
        operation: 'STREAM',
        caller: caller,
        service: _serviceName,
        method: 'watchTeamsByGroup',
        error: e,
      );
      return const Stream<List<Team>>.empty();
    }
  }

  /// Takım+sezon oyuncu listesi önbelleği ("teamId|seasonId" → liste).
  /// Ekran açılınca önce buradaki liste gösterilir, taze veri arkadan gelir.
  final Map<String, List<PlayerModel>> _playersCache = {};

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
    final cacheKey = '$team|$tId';

    Future<List<PlayerModel>> fetch() async {
      AppConfig.sqlLogStart(
        table: 'season_team_players',
        operation: 'SELECT',
        caller: caller,
        service: _serviceName,
        method: 'watchPlayers',
        filters:
            'team_id=$team, season_id=$tId | select=jersey_number,players(*)',
      );
      try {
        // Tek sorgu: sezon kaydı + oyuncu bilgisi (players FK join).
        final res = await _client
            .from('season_team_players')
            .select('jersey_number, players!inner(*)')
            .eq('team_id', team)
            .eq('season_id', tId)
            .eq('is_active', true);

        final list = <PlayerModel>[];
        for (final r in res.cast<Map<String, dynamic>>()) {
          final p = r['players'];
          if (p is! Map) continue;
          final row = _withDisplayName(Map<String, dynamic>.from(p));
          final pid = (row['id'] ?? '').toString().trim();
          if (pid.isEmpty) continue;
          final merged = <String, dynamic>{
            ...row,
            'season_id': tId,
            'team_id': team,
            if (r['jersey_number'] != null) 'jersey_number': r['jersey_number'],
          };
          list.add(PlayerModel.fromMap(merged, pid));
        }

        list.sort((a, b) {
          bool isManager(PlayerModel p) =>
              p.role == 'Takım Sorumlusu' || p.role == 'Her İkisi';
          final aM = isManager(a);
          final bM = isManager(b);
          if (aM != bM) return aM ? -1 : 1;
          final an = int.tryParse((a.number ?? '').trim()) ?? 9999;
          final bn = int.tryParse((b.number ?? '').trim()) ?? 9999;
          final cmp = an.compareTo(bn);
          if (cmp != 0) return cmp;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        _playersCache[cacheKey] = list;
        return list;
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'season_team_players',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'watchPlayers',
          error: e,
        );
        rethrow;
      }
    }

    Stream<List<PlayerModel>> feed() async* {
      final cached = _playersCache[cacheKey];
      if (cached != null) yield cached;
      try {
        yield await fetch();
      } catch (e) {
        // Önbellekte veri varsa onu göstermeye devam et.
        if (cached == null) rethrow;
      }
    }

    return feed().asBroadcastStream();
  }

  Future<List<PlayerModel>> getAvailablePlayersForLeague(
    String leagueId,
  ) async {
    final lid = leagueId.trim();
    if (lid.isEmpty) return const <PlayerModel>[];

    final linked = await _client
        .from('season_team_players')
        .select('player_id')
        .eq('season_id', lid)
        .eq('is_active', true);
    final excludeIds = <String>{};
    for (final any in linked) {
      final pid = (any['player_id'] ?? '').toString().trim();
      if (pid.isNotEmpty) excludeIds.add(pid);
    }

    final playersRes = await _client
        .from('players')
        .select()
        .order('name', ascending: true)
        .limit(500);
    final list = <PlayerModel>[];
    for (final any in playersRes) {
      final row = _withDisplayName(any.cast<String, dynamic>());
      final id = (row['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      if (excludeIds.contains(id)) continue;
      list.add(PlayerModel.fromMap(row, id));
    }
    return list;
  }

  /// Kadroya eklemek için futbolcu arar. Sezonda bir takıma kayıtlı olanlar
  /// listede kalır ama `teamId`/`teamName` ile döner; ekran bunları seçilemez
  /// gösterir.
  Future<List<({PlayerModel player, String? teamId, String? teamName})>>
  searchPlayersForSeason(String seasonId, String query) async {
    final sid = seasonId.trim();
    final words = query
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (sid.isEmpty || words.isEmpty) return const [];

    // PostgREST `or` filtresini bozabilecek karakterleri at.
    final cleaned = words.first.replaceAll(RegExp(r'[,()%*_\\]'), '');
    if (cleaned.isEmpty) return const [];
    // i / ı / İ / I tek karakter joker: "icardi" ve "ıcardı" aynı sonucu verir;
    // kesin eşleşmeyi aşağıdaki istemci filtresi yapar.
    final first = cleaned.replaceAll(RegExp('[iıİI]'), '_');
    final playersRes = await _client
        .from('players')
        .select()
        .or('name.ilike.%$first%,surname.ilike.%$first%')
        .order('name', ascending: true)
        .limit(60);

    final lowerWords = words.map(_lowerTr).toList();
    final players = <PlayerModel>[];
    for (final any in playersRes) {
      final row = _withDisplayName(any.cast<String, dynamic>());
      final id = (row['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      final display = _lowerTr((row['name'] ?? '').toString());
      if (!lowerWords.every(display.contains)) continue;
      players.add(PlayerModel.fromMap(row, id));
    }
    if (players.isEmpty) return const [];

    final linked = await _client
        .from('season_team_players')
        .select('player_id, team_id')
        .eq('season_id', sid)
        .eq('is_active', true)
        .inFilter('player_id', players.map((p) => p.id).toList());
    final teamByPlayer = <String, String>{};
    for (final any in linked) {
      final pid = (any['player_id'] ?? '').toString().trim();
      final tid = (any['team_id'] ?? '').toString().trim();
      if (pid.isNotEmpty && tid.isNotEmpty) teamByPlayer[pid] = tid;
    }

    final teamNames = <String, String>{};
    if (teamByPlayer.isNotEmpty) {
      final teamsRes = await _client
          .from('teams')
          .select('id, name')
          .inFilter('id', teamByPlayer.values.toSet().toList());
      for (final any in teamsRes) {
        final id = (any['id'] ?? '').toString();
        teamNames[id] = (any['name'] ?? '').toString().trim();
      }
    }

    return [
      for (final p in players)
        (
          player: p,
          teamId: teamByPlayer[p.id],
          teamName: teamNames[teamByPlayer[p.id]],
        ),
    ];
  }

  /// Aramada i / ı / İ / I eşdeğer sayılır (Türkçe ve yabancı isimler).
  static String _lowerTr(String s) =>
      s.replaceAll('İ', 'i').toLowerCase().replaceAll('ı', 'i');

  Future<void> addMultiplePlayersToTeam(
    List<String> playerIds,
    String teamId,
    String leagueId,
  ) async {
    final team = teamId.trim();
    final league = leagueId.trim();
    final ids = playerIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (team.isEmpty || league.isEmpty || ids.isEmpty) return;

    await _client
        .from('season_team_players')
        .update({'team_id': team, 'jersey_number': null, 'is_active': true})
        .eq('season_id', league)
        .inFilter('player_id', ids)
        .or('is_active.is.false,is_active.is.null');

    final existing = await _client
        .from('season_team_players')
        .select('player_id')
        .eq('season_id', league)
        .inFilter('player_id', ids);
    final existingIds = <String>{};
    for (final any in existing) {
      final pid = (any['player_id'] ?? '').toString().trim();
      if (pid.isNotEmpty) existingIds.add(pid);
    }
    final missing = ids.where((id) => !existingIds.contains(id)).toList();
    if (missing.isEmpty) return;

    final rows = missing
        .map(
          (pid) => <String, dynamic>{
            'season_id': league,
            'team_id': team,
            'player_id': pid,
            'jersey_number': null,
            'is_active': true,
          },
        )
        .toList();
    await _client.from('season_team_players').insert(rows);
  }

  Future<void> updateJerseyNumber(
    String playerId,
    String teamId,
    String leagueId,
    int newNumber,
  ) async {
    final pid = playerId.trim();
    final team = teamId.trim();
    final league = leagueId.trim();
    if (pid.isEmpty || team.isEmpty || league.isEmpty) return;
    if (newNumber <= 0 || newNumber > 999) {
      throw Exception('Forma numarası 1 ile 999 arasında olmalı.');
    }

    final dup = await _client
        .from('season_team_players')
        .select('player_id')
        .eq('season_id', league)
        .eq('team_id', team)
        .eq('jersey_number', newNumber)
        .eq('is_active', true)
        .limit(1);
    if (dup.isNotEmpty) {
      final row = (dup.first as Map).cast<String, dynamic>();
      final otherPid = (row['player_id'] ?? '').toString().trim();
      if (otherPid.isNotEmpty && otherPid != pid) {
        throw Exception('Bu forma numarası bu takımda zaten kullanılıyor.');
      }
    }

    try {
      await _client
          .from('season_team_players')
          .update({'jersey_number': newNumber})
          .eq('season_id', league)
          .eq('team_id', team)
          .eq('player_id', pid)
          .eq('is_active', true);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST204') {
        throw Exception(
          "season_team_players.jersey_number kolonu bulunamadı (PGRST204). "
          "Önce şunu çalıştır:\n"
          "alter table public.season_team_players add column if not exists jersey_number smallint;",
        );
      }
      rethrow;
    }
  }

  Future<void> setJerseyNumber(
    String playerId,
    String teamId,
    String leagueId,
    int? newNumber,
  ) async {
    final pid = playerId.trim();
    final team = teamId.trim();
    final league = leagueId.trim();
    if (pid.isEmpty || team.isEmpty || league.isEmpty) return;

    if (newNumber == null) {
      await _client
          .from('season_team_players')
          .update({'jersey_number': null})
          .eq('season_id', league)
          .eq('team_id', team)
          .eq('player_id', pid)
          .eq('is_active', true);
      return;
    }

    await updateJerseyNumber(pid, team, league, newNumber);
  }

  Future<String?> _resolvePlayerId(
    String phoneOrId, {
    String? caller,
    String? method,
  }) async {
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
      if (res.isEmpty) {
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
  Future<List<PlayerModel>> getEligiblePlayers(
    String teamId,
    String seasonId, {
    String? caller,
  }) async {
    final team = teamId.trim();
    final tId = seasonId.trim();
    if (team.isEmpty || tId.isEmpty) return const <PlayerModel>[];
    print('--- DEBUG: getEligiblePlayers BAŞLADI ---');
    print('Gelen teamId: "$team"');
    print('Gelen seasonId: "$tId"');

    try {
      final res = await _client
          .from('season_team_players')
          // players içindeki gerçek UUID olan 'id'yi mutlaka çekiyoruz[cite: 2]
          .select(
            'player_id, jersey_number, players!inner(id, name, surname, main_position, role)',
          )
          .eq('team_id', team)
          .eq('season_id', tId)
          .eq('is_active', true);

      print(
        'Sorgudan dönen ham satır sayısı: ${res.length}',
      ); // Eğer 0 ise ID'ler yanlıştır.

      final rows = res.cast<Map<String, dynamic>>();
      if (rows.isEmpty) return const <PlayerModel>[];

      final list = <PlayerModel>[];
      for (final r in rows) {
        final pData = r['players'] as Map<String, dynamic>?;
        if (pData == null) continue;

        final row = _withDisplayName(pData);

        // BURASI KRİTİK: Telefonu boşver, sadece UUID (id) kullan[cite: 2]
        final pid = (row['id'] ?? '').toString().trim();

        final merged = <String, dynamic>{
          ...row,
          'season_id': tId,
          'team_id': team,
          if (r['jersey_number'] != null) 'jersey_number': r['jersey_number'],
        };
        list.add(PlayerModel.fromMap(merged, pid));
      }

      list.sort((a, b) {
        bool isManager(PlayerModel p) =>
            p.role == 'Takım Sorumlusu' || p.role == 'Her İkisi';
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
    } catch (e) {
      AppConfig.sqlLogResult(
        table: 'season_team_players',
        operation: 'SELECT',
        caller: caller,
        service: _serviceName,
        method: 'getEligiblePlayers',
        error: e,
      );
      return const <PlayerModel>[];
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
      return watchTableRows(_client, table: 'players', orderBy: 'name').map((
        rows,
      ) {
        final list = rows.map((r) {
          final row = _withDisplayName(Map<String, dynamic>.from(r));
          final id = (row['id'] ?? row['phone'] ?? '').toString();
          return PlayerModel.fromMap(row, id);
        }).toList();
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
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
          'national_id': (nationalId ?? '').trim().isEmpty
              ? null
              : nationalId!.trim(),
          'birth_date': (birthDate ?? '').trim().isEmpty
              ? null
              : birthDate!.trim(),
          'main_position': (mainPosition ?? '').trim().isEmpty
              ? null
              : mainPosition!.trim(),
          'preferred_foot': (preferredFoot ?? '').trim().isEmpty
              ? null
              : preferredFoot!.trim(),
          'height': height,
          'weight': weight,
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
        const fullKeys = <String>[
          'name',
          'surname',
          'birth_date',
          'preferred_foot',
          'main_position',
          'sub_position',
          'photo_url',
          'phone',
          'height',
          'weight',
          'national_id',
          'role',
        ];
        final hasFullPayload = fullKeys.every(data.containsKey);

        Map<String, dynamic> payload;
        if (hasFullPayload) {
          String? cleanStr(dynamic v) {
            final s = (v ?? '').toString().trim();
            return s.isEmpty ? null : s;
          }

          int? cleanInt(dynamic v) {
            if (v == null) return null;
            if (v is int) return v;
            if (v is num) return v.toInt();
            final s = v.toString().trim();
            return s.isEmpty ? null : int.tryParse(s);
          }

          final phoneInput = cleanStr(data['phone']);
          final normalizedPhone = phoneInput == null
              ? null
              : phoneInput.startsWith('no_phone_')
              ? phoneInput
              : _normalizePhoneToRaw10(phoneInput);

          payload = <String, dynamic>{
            'name': cleanStr(data['name']),
            'surname': cleanStr(data['surname']),
            'birth_date': cleanStr(data['birth_date']),
            'preferred_foot': cleanStr(data['preferred_foot']),
            'main_position': cleanStr(data['main_position']),
            'sub_position': cleanStr(data['sub_position']),
            'photo_url': cleanStr(data['photo_url']),
            'phone': normalizedPhone,
            'height': cleanInt(data['height']),
            'weight': cleanInt(data['weight']),
            'national_id': cleanStr(data['national_id']),
            'role': cleanStr(data['role']),
          };
        } else {
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

          payload = <String, dynamic>{};
          for (final e in data.entries) {
            payload[mapKey(e.key)] = e.value;
          }
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
        // Oyuncu bulunamazsa ya da RLS engellerse Supabase hata vermez, 0 satır
        // günceller; aksi halde form "kaydedildi" deyip fotoğraf vb. kaybolurdu.
        final updated = await _client
            .from('players')
            .update(payload)
            .or(clauses.join(','))
            .select('id');
        if (updated.isEmpty) {
          throw Exception(
            'Oyuncu güncellenemedi: kayıt bulunamadı ya da güncelleme yetkisi '
            'yok ($id).',
          );
        }
        AppConfig.sqlLogResult(
          table: 'players',
          operation: 'UPDATE',
          caller: caller,
          service: _serviceName,
          method: 'updatePlayer',
          count: updated.length,
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
  Future<Map<String, dynamic>?> getPenaltyForPlayer(
    String playerId, {
    String? caller,
  }) {
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
        if (res.isEmpty) {
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
            .update({
              'suspended_matches': matchCount,
              'updated_at': DateTime.now().toIso8601String(),
            })
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
  Future<void> clearPenaltyForPlayer({
    required String playerId,
    String? caller,
  }) {
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
        await _client
            .from('penalties')
            .delete()
            .or('id.eq.$pId,player_id.eq.$pId');
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
            .update({
              'suspended_matches': 0,
              'updated_at': DateTime.now().toIso8601String(),
            })
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
      var pid =
          (await _resolvePlayerId(
            phone,
            caller: caller,
            method: 'upsertRosterEntry',
          ))?.trim() ??
          '';
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
          final inserted = await _client
              .from('players')
              .insert({
                'phone': phone,
                'name': firstName.isEmpty ? name : firstName,
                'surname': surname.isEmpty ? null : surname,
              })
              .select('id')
              .limit(1);
          if (inserted.isNotEmpty) {
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
                if (raw10.isNotEmpty && raw10 != phone && _isUuid(raw10))
                  'id.eq.$raw10',
              ];
              final res = await _client
                  .from('players')
                  .select('id')
                  .or(clauses.join(','))
                  .limit(1);
              if (res.isNotEmpty) {
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

      final jerseyStr = (jerseyNumber ?? '')
          .replaceAll(RegExp(r'\D'), '')
          .trim();
      final jersey = jerseyStr.isEmpty ? null : int.tryParse(jerseyStr);
      if (jerseyStr.isNotEmpty && jersey == null) {
        throw Exception('Forma numarası geçersiz.');
      }
      if (jersey != null && (jersey <= 0 || jersey > 999)) {
        throw Exception('Forma numarası 1 ile 999 arasında olmalı.');
      }

      if (jersey != null) {
        final dup = await _client
            .from('season_team_players')
            .select('player_id')
            .eq('season_id', t)
            .eq('team_id', team)
            .eq('jersey_number', jersey)
            .eq('is_active', true);
        for (final any in dup) {
          final otherPid = (any['player_id'] ?? '').toString().trim();
          if (otherPid.isNotEmpty && otherPid != pid) {
            throw Exception('Bu forma numarası bu takımda zaten kullanılıyor.');
          }
        }
      }

      try {
        _sbLog(
          table: 'season_team_players',
          query: 'INSERT | season_id=$t, team_id=$team, player_id=$pid',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'season_team_players',
          operation: 'INSERT',
          caller: caller,
          service: _serviceName,
          method: 'upsertRosterEntry',
          filters: 'season_id=$t, team_id=$team, player_id=$pid',
        );
        final base = <String, dynamic>{
          'season_id': t,
          'team_id': team,
          'player_id': pid,
          'jersey_number': ?jersey,
          'is_active': true,
        };
        final updated = await _client
            .from('season_team_players')
            .update({'jersey_number': ?jersey, 'is_active': true})
            .eq('season_id', t)
            .eq('team_id', team)
            .eq('player_id', pid)
            .select('id');
        final didUpdate = updated.isNotEmpty;
        if (!didUpdate) {
          await _client.from('season_team_players').insert(base);
        }
        await _bestEffortUpdatePlayerIdentityFields(
          playerId: pid,
          role: role.trim().isEmpty ? null : role.trim(),
        );
        AppConfig.sqlLogResult(
          table: 'season_team_players',
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
                (e.message).toLowerCase().contains('row-level security'))) {
          throw Exception(
            'season_team_players INSERT RLS tarafından engellendi (code=42501). '
            'Bu client tarafında kodla çözülemez; Supabase tarafında policy açılmalı. '
            'En basit test için:\n'
            'create policy "allow insert season_team_players" on public.season_team_players '
            'for insert to anon, authenticated with check (true);',
          );
        }
        AppConfig.sqlLogResult(
          table: 'season_team_players',
          operation: 'INSERT',
          caller: caller,
          service: _serviceName,
          method: 'upsertRosterEntry',
          error: e,
        );
        _sbResult(rows: 0, error: e);
        rethrow;
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
      final pid =
          (await _resolvePlayerId(
            phone,
            caller: caller,
            method: 'deleteRosterEntry',
          ))?.trim() ??
          '';
      if (pid.isEmpty) {
        throw Exception('Kadrodan çıkarılamadı: oyuncu bulunamadı ($phone).');
      }
      try {
        _sbLog(
          table: 'season_team_players',
          query:
              'UPDATE is_active=false | season_id=$t, team_id=$team, player_id=$pid',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'season_team_players',
          operation: 'UPDATE',
          caller: caller,
          service: _serviceName,
          method: 'deleteRosterEntry',
          filters: 'season_id=$t, team_id=$team, player_id=$pid',
        );
        // RLS bir UPDATE'i engellediğinde veya filtre eşleşmediğinde Supabase
        // hata vermez, 0 satır günceller; bu yüzden etkilenen satırlar kontrol
        // edilir. Aksi halde ekran "kaldırıldı" der ama oyuncu listede kalır.
        final updated = await _client
            .from('season_team_players')
            .update({'is_active': false})
            .eq('season_id', t)
            .eq('team_id', team)
            .eq('player_id', pid)
            .select('id');
        if (updated.isEmpty) {
          throw Exception(
            'Kadrodan çıkarılamadı: season_team_players satırı güncellenmedi '
            '(0 satır). Kayıt bulunamadı ya da RLS UPDATE yetkisi yok.',
          );
        }
        AppConfig.sqlLogResult(
          table: 'season_team_players',
          operation: 'UPDATE',
          caller: caller,
          service: _serviceName,
          method: 'deleteRosterEntry',
          count: updated.length,
        );
        _sbResult(rows: updated.length);
      } catch (e) {
        if (e is PostgrestException &&
            (e.code == '42501' ||
                (e.message).toLowerCase().contains('row-level security'))) {
          throw Exception(
            'season_team_players UPDATE RLS tarafından engellendi (code=42501). '
            'is_active güncellemesi için update policy açılmalı.',
          );
        }
        if (e is PostgrestException && e.code == 'PGRST204') {
          throw Exception(
            "season_team_players.is_active kolonu bulunamadı (PGRST204). "
            "Önce şunu çalıştır:\n"
            "alter table public.season_team_players add column if not exists is_active boolean not null default true;",
          );
        }
        AppConfig.sqlLogResult(
          table: 'season_team_players',
          operation: 'UPDATE',
          caller: caller,
          service: _serviceName,
          method: 'deleteRosterEntry',
          error: e,
        );
        _sbResult(rows: 0, error: e);
        rethrow;
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
          (await _resolvePlayerId(
            phone,
            caller: caller,
            method: 'isTeamManagerForTournament',
          ))?.trim() ??
          '';
      if (pid.isEmpty) return false;
      try {
        _sbLog(
          table: 'season_team_players',
          query:
              'SELECT id | season_id=$t, team_id=$team, player_id=$pid | limit=1',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'season_team_players',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'isTeamManagerForTournament',
          filters: 'season_id=$t, team_id=$team, player_id=$pid | limit=1',
        );
        final linkRes = await _client
            .from('season_team_players')
            .select('id')
            .eq('season_id', t)
            .eq('team_id', team)
            .eq('player_id', pid)
            .eq('is_active', true)
            .limit(1);
        if (linkRes.isEmpty) {
          AppConfig.sqlLogResult(
            table: 'season_team_players',
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
          table: 'season_team_players',
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
        if (pr.isEmpty) return false;
        final role = ((pr.first as Map)['role'] ?? '').toString().trim();
        return role == 'Takım Sorumlusu' || role == 'Her İkisi';
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'season_team_players',
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
          table: 'season_team_players',
          query: 'SELECT player_id | season_id=$t, team_id=$team',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'season_team_players',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'managerExistsForTeamTournament',
          filters: 'season_id=$t, team_id=$team',
        );
        final res = await _client
            .from('season_team_players')
            .select('player_id')
            .eq('season_id', t)
            .eq('team_id', team)
            .eq('is_active', true);
        AppConfig.sqlLogResult(
          table: 'season_team_players',
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
        for (final any in pr) {
          final role = (any['role'] ?? '').toString().trim();
          if (role == 'Takım Sorumlusu' || role == 'Her İkisi') return true;
        }
        return false;
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'season_team_players',
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
  Future<List<League>> getTeamActiveTournaments(
    String teamId, {
    String? caller,
  }) {
    final tId = teamId.trim();
    if (tId.isEmpty) return Future.value(const []);
    return Future(() async {
      try {
        _sbLog(
          table: 'season_teams',
          query: 'SELECT season_id | team_id=$tId',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'season_teams',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'getTeamActiveTournaments',
          filters: 'team_id=$tId | columns=season_id',
        );
        final regRes =
            (await _client
                    .from('season_teams')
                    .select('season_id')
                    .eq('team_id', tId))
                .cast<Map<String, dynamic>>();
        AppConfig.sqlLogResult(
          table: 'season_teams',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'getTeamActiveTournaments',
          count: regRes.length,
        );
        _sbResult(rows: regRes.length);
        if (regRes.isEmpty) return const <League>[];

        final seasonIds = <String>{};
        for (final row in regRes) {
          final id = (row['season_id'] ?? '').toString().trim();
          if (id.isNotEmpty) seasonIds.add(id);
        }
        if (seasonIds.isEmpty) return const <League>[];

        _sbLog(
          table: 'seasons',
          query: 'SELECT *, leagues(name, is_active) | id IN (${seasonIds.length})',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'seasons',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'getTeamActiveTournaments',
          filters: 'id IN (${seasonIds.length})',
        );
        final seasonsRes =
            (await _client
                    .from('seasons')
                    .select('*, leagues(name, is_active)')
                    .inFilter('id', seasonIds.toList()))
                .cast<Map<String, dynamic>>();
        AppConfig.sqlLogResult(
          table: 'seasons',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'getTeamActiveTournaments',
          count: seasonsRes.length,
        );
        _sbResult(rows: seasonsRes.length);

        // Kadro ekranı sezon id'si bekliyor; listede "Turnuva • Sezon" görünür.
        final leagues = seasonsRes
            .where((row) {
              final league = row['leagues'];
              return league is! Map || league['is_active'] != false;
            })
            .map((row) {
              final league = row['leagues'];
              final leagueName = league is Map
                  ? (league['name'] ?? '').toString().trim()
                  : '';
              final seasonName = (row['name'] ?? '').toString().trim();
              return League.fromMap({
                ...row,
                'name': [
                  leagueName,
                  seasonName,
                ].where((s) => s.isNotEmpty).join(' • '),
              });
            })
            .toList();
        final active = leagues.where((l) => l.isActive).toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        return active;
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'seasons',
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
  Future<void> updateTeam(
    String teamId,
    Map<String, dynamic> data, {
    String? caller,
  }) {
    final id = teamId.trim();
    if (id.isEmpty) return Future.value();
    return Future(() async {
      try {
        String mapTeamKey(String k) {
          switch (k) {
            case 'logoUrl':
              return 'logo_url';
            case 'foundedYear':
              return 'founded_year';
            default:
              return k;
          }
        }

        String? readStr(dynamic v) {
          final s = (v ?? '').toString().trim();
          return s.isEmpty ? null : s;
        }

        final seasonIdFromData = readStr(
          data['seasonId'] ??
              data['season_id'] ??
              data['leagueId'] ??
              data['league_id'] ??
              data['tournamentId'] ??
              data['tournament_id'],
        );
        final groupIdFromData = readStr(data['groupId'] ?? data['group_id']);

        final wantsLinkUpdate =
            data.containsKey('groupId') ||
            data.containsKey('group_id') ||
            data.containsKey('groupName') ||
            data.containsKey('group_name') ||
            data.containsKey('seasonId') ||
            data.containsKey('season_id') ||
            data.containsKey('leagueId') ||
            data.containsKey('league_id') ||
            data.containsKey('tournamentId') ||
            data.containsKey('tournament_id');

        final teamPayload = <String, dynamic>{};
        for (final e in data.entries) {
          final k = e.key;
          if (k == 'groupId' ||
              k == 'group_id' ||
              k == 'groupName' ||
              k == 'group_name' ||
              k == 'seasonId' ||
              k == 'season_id' ||
              k == 'leagueId' ||
              k == 'league_id' ||
              k == 'tournamentId' ||
              k == 'tournament_id' ||
              k == 'managerName') {
            // managerName: teams'te kolon yok (sorumlu manager_id ile tutulur).
            continue;
          }
          teamPayload[mapTeamKey(k)] = e.value;
        }
        if (teamPayload.isNotEmpty) {
          teamPayload['updated_at'] = DateTime.now().toIso8601String();
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
          await _client.from('teams').update(teamPayload).eq('id', id);
          AppConfig.sqlLogResult(
            table: 'teams',
            operation: 'UPDATE',
            caller: caller,
            service: _serviceName,
            method: 'updateTeam',
            count: 1,
          );
          _sbResult(rows: 1);
        }

        if (wantsLinkUpdate) {
          var seasonId = (seasonIdFromData ?? '').trim();
          if (seasonId.isEmpty) {
            final res = await _client
                .from('season_teams')
                .select('season_id')
                .eq('team_id', id)
                .limit(2);
            if (res.length == 1) {
              seasonId = (res.first['season_id'] ?? '').toString().trim();
            }
          }

          if (seasonId.isNotEmpty) {
            // season_teams'te grup adı tutulmaz; sadece group_id.
            final linkPayload = <String, dynamic>{
              if (data.containsKey('groupId') || data.containsKey('group_id'))
                'group_id': groupIdFromData,
            };

            if (linkPayload.isNotEmpty) {
              _sbLog(
                table: 'season_teams',
                query: 'UPSERT season_id=$seasonId, team_id=$id',
                trace: StackTrace.current,
              );
              final updated = await _client
                  .from('season_teams')
                  .update(linkPayload)
                  .eq('season_id', seasonId)
                  .eq('team_id', id)
                  .select('id');
              if (updated.isEmpty) {
                await _client.from('season_teams').insert({
                  'season_id': seasonId,
                  'team_id': id,
                  if (linkPayload.containsKey('group_id'))
                    'group_id': linkPayload['group_id'],
                });
              }
            }
          }
        }
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
        rethrow; // ekran "güncellendi" dememeli
      }
    });
  }

  @override
  Future<void> deleteTeamCascade(String teamId, {String? caller}) {
    final id = teamId.trim();
    if (id.isEmpty) return Future.value();
    return Future(() async {
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
        matchIds = res
            .map((e) => (e as Map)['id']?.toString() ?? '')
            .where((e) => e.trim().isNotEmpty)
            .toList();
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
          await _client
              .from('match_events')
              .delete()
              .inFilter('match_id', matchIds);
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
            table: 'match_rosters',
            query: 'DELETE match_id IN (${matchIds.length})',
            trace: StackTrace.current,
          );
          AppConfig.sqlLogStart(
            table: 'match_rosters',
            operation: 'DELETE',
            caller: caller,
            service: _serviceName,
            method: 'deleteTeamCascade',
            filters: 'match_id IN (${matchIds.length})',
          );
          await _client
              .from('match_rosters')
              .delete()
              .inFilter('match_id', matchIds);
          AppConfig.sqlLogResult(
            table: 'match_rosters',
            operation: 'DELETE',
            caller: caller,
            service: _serviceName,
            method: 'deleteTeamCascade',
          );
        } catch (e) {
          AppConfig.sqlLogResult(
            table: 'match_rosters',
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
          table: 'season_team_players',
          query: 'DELETE team_id=$id',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'season_team_players',
          operation: 'DELETE',
          caller: caller,
          service: _serviceName,
          method: 'deleteTeamCascade',
          filters: 'team_id=$id',
        );
        await _client.from('season_team_players').delete().eq('team_id', id);
        AppConfig.sqlLogResult(
          table: 'season_team_players',
          operation: 'DELETE',
          caller: caller,
          service: _serviceName,
          method: 'deleteTeamCascade',
        );
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'season_team_players',
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
          table: 'season_teams',
          query: 'DELETE team_id=$id',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'season_teams',
          operation: 'DELETE',
          caller: caller,
          service: _serviceName,
          method: 'deleteTeamCascade',
          filters: 'team_id=$id',
        );
        await _client.from('season_teams').delete().eq('team_id', id);
        AppConfig.sqlLogResult(
          table: 'season_teams',
          operation: 'DELETE',
          caller: caller,
          service: _serviceName,
          method: 'deleteTeamCascade',
        );
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'season_teams',
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
          table: 'season_teams',
          query: 'SELECT season_id=$id (join teams + groups)',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'season_teams',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'getTeamsCached',
          filters: 'season_id=$id',
        );
        final linksRes = await _client
            .from('season_teams')
            .select()
            .eq('season_id', id);
        AppConfig.sqlLogResult(
          table: 'season_teams',
          operation: 'SELECT',
          caller: caller,
          service: _serviceName,
          method: 'getTeamsCached',
          count: linksRes.length,
        );
        _sbResult(rows: linksRes.length);

        final links = linksRes.cast<Map<String, dynamic>>();
        final teamIds = <String>{};
        final groupIds = <String>{};
        for (final r in links) {
          final tid = (r['team_id'] ?? '').toString().trim();
          if (tid.isNotEmpty) teamIds.add(tid);
          final gid = (r['group_id'] ?? '').toString().trim();
          if (gid.isNotEmpty) groupIds.add(gid);
        }

        final teamById = <String, Map<String, dynamic>>{};
        if (teamIds.isNotEmpty) {
          final res = await _client
              .from('teams')
              .select()
              .inFilter('id', teamIds.toList());
          for (final any in res) {
            final row = (any as Map).cast<String, dynamic>();
            final tid = (row['id'] ?? '').toString().trim();
            if (tid.isNotEmpty) teamById[tid] = row;
          }
        }

        final groupNameById = <String, String>{};
        if (groupIds.isNotEmpty) {
          final res = await _client
              .from('groups')
              .select('id, name')
              .inFilter('id', groupIds.toList());
          for (final any in res) {
            final row = (any as Map).cast<String, dynamic>();
            final gid = (row['id'] ?? '').toString().trim();
            if (gid.isEmpty) continue;
            final name = (row['name'] ?? '').toString().trim();
            if (name.isNotEmpty) groupNameById[gid] = name;
          }
        }

        final list = <Team>[];
        for (final link in links) {
          final tid = (link['team_id'] ?? '').toString().trim();
          final team = teamById[tid];
          if (team == null) continue;
          final gid = (link['group_id'] ?? '').toString().trim();
          final merged = <String, dynamic>{
            ...link,
            'team': team,
            if ((link['group_name'] ?? '').toString().trim().isEmpty &&
                gid.isNotEmpty &&
                (groupNameById[gid] ?? '').trim().isNotEmpty)
              'group_name': groupNameById[gid],
            if (gid.isNotEmpty && (groupNameById[gid] ?? '').trim().isNotEmpty)
              'group': {'id': gid, 'name': groupNameById[gid]},
          };
          list.add(Team.fromMap(merged));
        }
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        return list;
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'season_teams',
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
        Team(
          id: '',
          name: name,
          logoUrl: logoUrl,
          leagueId: l,
          groupId: groupId,
          groupName: groupName,
        ),
      );
    }
    return Future(() async {
      try {
        _sbLog(
          table: 'teams',
          query: 'UPSERT base + INSERT season_teams season_id=$l',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'teams',
          operation: 'UPSERT',
          caller: caller,
          service: _serviceName,
          method: 'addTeamAndUpsertCache',
          filters: 'season_id=$l (via season_teams)',
        );
        String teamId = '';
        try {
          final existing = await _client
              .from('teams')
              .select('id')
              .eq('name', name)
              .limit(1);
          if (existing.isNotEmpty) {
            teamId = (existing.first['id'] ?? '').toString().trim();
          }
        } catch (_) {}

        if (teamId.isEmpty) {
          final inserted = await _client
              .from('teams')
              .insert({
                'name': name,
                'logo_url': logoUrl.trim(),
              })
              .select('id')
              .single();
          teamId = (inserted['id'] ?? '').toString().trim();
        }

        if (teamId.isEmpty) {
          throw Exception('Takım kaydı oluşturulamadı.');
        }

        final linkBase = <String, dynamic>{
          'season_id': l,
          'team_id': teamId,
          'group_id': groupId?.trim().isEmpty ?? true ? null : groupId!.trim(),
        };
        final updated = await _client
            .from('season_teams')
            .update(linkBase)
            .eq('season_id', l)
            .eq('team_id', teamId)
            .select('id');
        if (updated.isEmpty) {
          await _client.from('season_teams').insert(linkBase);
        }

        final teamRow = await _client
            .from('teams')
            .select()
            .eq('id', teamId)
            .limit(1);
        final merged = <String, dynamic>{
          ...linkBase,
          'team': teamRow.isEmpty
              ? <String, dynamic>{
                  'id': teamId,
                  'name': name,
                  'logo_url': logoUrl,
                }
              : (teamRow.first as Map).cast<String, dynamic>(),
        };

        AppConfig.sqlLogResult(
          table: 'season_teams',
          operation: 'UPSERT',
          caller: caller,
          service: _serviceName,
          method: 'addTeamAndUpsertCache',
          count: 1,
        );
        _sbResult(rows: 1);
        return Team.fromMap(merged);
      } catch (e) {
        AppConfig.sqlLogResult(
          table: 'season_teams',
          operation: 'UPSERT',
          caller: caller,
          service: _serviceName,
          method: 'addTeamAndUpsertCache',
          error: e,
        );
        _sbResult(rows: 0, error: e);
        return Team(
          id: '',
          name: name,
          logoUrl: logoUrl,
          leagueId: l,
          groupId: groupId,
          groupName: groupName,
        );
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
      final count = res.length;
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
      final count = res.length;
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
