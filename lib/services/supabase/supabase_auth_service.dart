import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

import '../interfaces/i_auth_service.dart';
import '../../config/app_config.dart';
import '../../models/auth_models.dart';

class SupabaseAuthService implements IAuthService {
  SupabaseAuthService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

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
  Future<ConfirmationResult> startPhoneAuthWeb({required String phoneNumber}) {
    if (!kIsWeb) {
      throw StateError('startPhoneAuthWeb sadece Web platformunda kullanılabilir.');
    }
    return FirebaseAuth.instance.signInWithPhoneNumber(phoneNumber);
  }

  @override
  Stream<UserDoc?> watchUserDoc(String uid) {
    final id = uid.trim();
    if (id.isEmpty) return const Stream<UserDoc?>.empty();
    try {
      _sbLog(
        table: 'users',
        query: 'STREAM primaryKey=id | clientFilter=id=$id',
        trace: StackTrace.current,
      );
      AppConfig.sqlLogStart(
        table: 'users',
        operation: 'STREAM',
        filters: 'primaryKey=id | clientFilter=id=$id',
      );
      return _client.from('users').stream(primaryKey: ['id']).map((rows) {
        final row = rows.cast<Map<String, dynamic>>().firstWhere(
          (r) => (r['id'] ?? '').toString().trim() == id,
          orElse: () => const <String, dynamic>{},
        );
        if (row.isEmpty) return null;
        return UserDoc(
          uid: (row['id'] ?? '').toString(),
          role: (row['access_role'] ?? row['role'])?.toString(),
          phone: (row['phone'] ?? '').toString(),
        );
      });
    } catch (e) {
      AppConfig.sqlLogResult(table: 'users', operation: 'STREAM', error: e);
      _sbResult(error: e);
      return const Stream<UserDoc?>.empty();
    }
  }

  @override
  Stream<List<RosterAssignment>> watchRosterAssignmentsByPhone(String phone) {
    final p = phone.trim();
    if (p.isEmpty) return const Stream<List<RosterAssignment>>.empty();
    try {
      _sbLog(
        table: 'rosters',
        query: 'STREAM primaryKey=id | clientFilter=player_phone=$p',
        trace: StackTrace.current,
      );
      AppConfig.sqlLogStart(
        table: 'rosters',
        operation: 'STREAM',
        filters: 'primaryKey=id | clientFilter=player_phone=$p',
      );
      return _client.from('rosters').stream(primaryKey: ['id']).map((rows) {
        final filtered = rows.where((r) => (r['player_phone'] ?? r['playerPhone'] ?? '').toString().trim() == p);
        return filtered.map((r) {
          final row = Map<String, dynamic>.from(r);
          return RosterAssignment(
            id: (row['id'] ?? '').toString(),
            tournamentId: (row['tournament_id'] ?? row['tournamentId'] ?? '').toString().trim(),
            teamId: (row['team_id'] ?? row['teamId'] ?? '').toString().trim(),
            role: (row['role'] ?? '').toString(),
          );
        }).toList();
      });
    } catch (e) {
      AppConfig.sqlLogResult(table: 'rosters', operation: 'STREAM', error: e);
      _sbResult(error: e);
      return const Stream<List<RosterAssignment>>.empty();
    }
  }

  @override
  Future<void> createOtpRequest({
    required String phoneRaw10,
    required String code,
    required DateTime expiresAt,
  }) async {
    final raw10 = phoneRaw10.trim();
    final c = code.trim();
    if (raw10.isEmpty || c.isEmpty) return;
    try {
      _sbLog(
        table: 'otp_codes',
        query: 'INSERT phone_raw10=$raw10',
        trace: StackTrace.current,
      );
      AppConfig.sqlLogStart(
        table: 'otp_codes',
        operation: 'INSERT',
        filters: 'phone_raw10=$raw10',
      );
      await _client.from('otp_codes').insert({
        'phone_raw10': raw10,
        'code': c,
        'status': 'pending',
        'expires_at': expiresAt.toIso8601String(),
      });
      AppConfig.sqlLogResult(table: 'otp_codes', operation: 'INSERT', count: 1);
      _sbResult(rows: 1);
    } catch (e) {
      AppConfig.sqlLogResult(table: 'otp_codes', operation: 'INSERT', error: e);
      _sbResult(rows: 0, error: e);
    }
  }

  @override
  Future<OtpRequest?> getOtpRequest(String phoneRaw10) async {
    final raw10 = phoneRaw10.trim();
    if (raw10.isEmpty) return null;
    try {
      _sbLog(
        table: 'otp_codes',
        query: 'SELECT phone_raw10=$raw10, status=pending | order=created_at desc | limit=1',
        trace: StackTrace.current,
      );
      AppConfig.sqlLogStart(
        table: 'otp_codes',
        operation: 'SELECT',
        filters: 'phone_raw10=$raw10, status=pending | order=created_at desc | limit=1',
      );
      final res = await _client
          .from('otp_codes')
          .select('phone_raw10, code, expires_at, status, created_at')
          .eq('phone_raw10', raw10)
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(1);
      final rows = (res as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) {
        AppConfig.sqlLogResult(table: 'otp_codes', operation: 'SELECT', count: 0);
        _sbResult(rows: 0);
        return null;
      }
      AppConfig.sqlLogResult(table: 'otp_codes', operation: 'SELECT', count: 1);
      _sbResult(rows: 1);
      final row = rows.first;
      final code = (row['code'] ?? '').toString().trim();
      final expiresAt = _readDate(row['expires_at']);
      if (code.isEmpty || expiresAt == null) return null;
      return OtpRequest(phoneRaw10: raw10, code: code, expiresAt: expiresAt);
    } catch (e) {
      AppConfig.sqlLogResult(table: 'otp_codes', operation: 'SELECT', error: e);
      _sbResult(rows: 0, error: e);
      return null;
    }
  }

  @override
  Future<void> deleteOtpRequest(String phoneRaw10) async {
    final raw10 = phoneRaw10.trim();
    if (raw10.isEmpty) return;
    try {
      _sbLog(
        table: 'otp_codes',
        query: 'UPDATE phone_raw10=$raw10, status=pending',
        trace: StackTrace.current,
      );
      AppConfig.sqlLogStart(
        table: 'otp_codes',
        operation: 'UPDATE',
        filters: 'phone_raw10=$raw10, status=pending',
      );
      await _client
          .from('otp_codes')
          .update({'status': 'verified', 'verified_at': DateTime.now().toIso8601String()})
          .eq('phone_raw10', raw10)
          .eq('status', 'pending');
      AppConfig.sqlLogResult(table: 'otp_codes', operation: 'UPDATE');
      _sbResult(rows: 1);
    } catch (e) {
      AppConfig.sqlLogResult(table: 'otp_codes', operation: 'UPDATE', error: e);
      _sbResult(rows: 0, error: e);
    }
  }

  @override
  Stream<List<OtpCodeEntry>> watchOtpCodes({bool includeVerified = false}) {
    Future<List<OtpCodeEntry>> fetch() async {
      _sbLog(
        table: 'otp_codes',
        query: 'SELECT order=created_at desc | limit=200 | includeVerified=$includeVerified',
        trace: StackTrace.current,
      );
      AppConfig.sqlLogStart(
        table: 'otp_codes',
        operation: 'SELECT',
        filters: 'order=created_at desc | limit=200 | includeVerified=$includeVerified',
      );
      final res = await _client
          .from('otp_codes')
          .select('id, phone_raw10, code, status, expires_at, created_at')
          .order('created_at', ascending: false)
          .limit(200);
      final rows = (res as List).cast<Map<String, dynamic>>();
      final filtered = includeVerified
          ? rows
          : rows.where((r) => (r['status'] ?? '').toString().trim() == 'pending');
      AppConfig.sqlLogResult(table: 'otp_codes', operation: 'SELECT', count: filtered.length);
      _sbResult(rows: filtered.length);
      return filtered.map((row) {
        final id = (row['id'] ?? '').toString();
        final phoneRaw10 = (row['phone_raw10'] ?? '').toString().trim();
        final code = (row['code'] ?? '').toString().trim();
        final status = (row['status'] ?? '').toString().trim();
        final expiresAt = _readDate(row['expires_at']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final createdAt = _readDate(row['created_at']);
        return OtpCodeEntry(
          id: id,
          phoneRaw10: phoneRaw10,
          code: code,
          status: status,
          expiresAt: expiresAt,
          createdAt: createdAt,
        );
      }).toList();
    }

    final controller = StreamController<List<OtpCodeEntry>>.broadcast();
    Timer? timer;

    Future<void> emit() async {
      try {
        controller.add(await fetch());
      } catch (_) {}
    }

    controller.onListen = () {
      emit();
      timer = Timer.periodic(const Duration(seconds: 2), (_) => emit());
    };
    controller.onCancel = () async {
      timer?.cancel();
      await controller.close();
    };
    return controller.stream;
  }

  @override
  Future<ProfileLookupResult> lookupProfileByPhoneRaw10(String phoneRaw10) {
    final raw10 = phoneRaw10.trim();
    if (raw10.length != 10) {
      return Future.value(const ProfileLookupResult.notFound());
    }

    return Future(() async {
      Future<List<Map<String, dynamic>>> leaguesBy(String field, String value) async {
        _sbLog(
          table: 'leagues',
          query: 'SELECT $field=$value | limit=10',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'leagues',
          operation: 'SELECT',
          filters: '$field=$value | limit=10',
        );
        final res = await _client.from('leagues').select().eq(field, value).limit(10);
        final rows = (res as List).cast<Map<String, dynamic>>();
        AppConfig.sqlLogResult(table: 'leagues', operation: 'SELECT', count: rows.length);
        _sbResult(rows: rows.length);
        return rows;
      }

      var leagues = await leaguesBy('manager_phone_raw10', raw10);
      if (leagues.isEmpty) {
        leagues = await leaguesBy('manager_phone', raw10);
      }
      if (leagues.isNotEmpty) {
        final ids = leagues
            .map((e) => (e['id'] ?? '').toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
        return ProfileLookupResult.tournamentAdmin(
          matchedLeagueIds: ids,
          leagues: leagues,
        );
      }

      Future<Map<String, dynamic>?> firstPlayerBy(String field, String value) async {
        _sbLog(
          table: 'players',
          query: 'SELECT $field=$value | limit=1',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'players',
          operation: 'SELECT',
          filters: '$field=$value | limit=1',
        );
        final res = await _client.from('players').select().eq(field, value).limit(1);
        final rows = (res as List).cast<Map<String, dynamic>>();
        if (rows.isEmpty) {
          AppConfig.sqlLogResult(table: 'players', operation: 'SELECT', count: 0);
          _sbResult(rows: 0);
          return null;
        }
        AppConfig.sqlLogResult(table: 'players', operation: 'SELECT', count: 1);
        _sbResult(rows: 1);
        return rows.first;
      }

      Map<String, dynamic>? player =
          await firstPlayerBy('phone_raw10', raw10) ?? await firstPlayerBy('phone', raw10);
      player ??= await firstPlayerBy('phone', '0$raw10');
      player ??= await firstPlayerBy('phone', '+90$raw10');
      player ??= await firstPlayerBy('phone', '90$raw10');

      if (player == null) {
        return const ProfileLookupResult.notFound();
      }

      final playerId = (player['id'] ?? '').toString().trim();
      final name = (player['name'] ?? '').toString().trim();
      final teamId = (player['team_id'] ?? player['teamId'] ?? '').toString().trim();
      final pr = (player['role'] ?? '').toString().trim();
      final resolvedRole = (pr == 'Takım Sorumlusu' || pr == 'Her İkisi') ? 'manager' : 'player';

      String? teamName;
      String? tournamentId;
      if (teamId.isNotEmpty && teamId != 'free_agent_pool') {
        try {
          _sbLog(
            table: 'teams',
            query: 'SELECT id=$teamId | limit=1',
            trace: StackTrace.current,
          );
          AppConfig.sqlLogStart(
            table: 'teams',
            operation: 'SELECT',
            filters: 'id=$teamId | limit=1',
          );
          final tRes = await _client.from('teams').select().eq('id', teamId).limit(1);
          final rows = (tRes as List).cast<Map<String, dynamic>>();
          if (rows.isNotEmpty) {
            AppConfig.sqlLogResult(table: 'teams', operation: 'SELECT', count: 1);
            _sbResult(rows: 1);
            final t = rows.first;
            teamName = (t['name'] ?? '').toString().trim();
            tournamentId = (t['league_id'] ?? t['tournament_id'] ?? '').toString().trim();
          } else {
            AppConfig.sqlLogResult(table: 'teams', operation: 'SELECT', count: 0);
            _sbResult(rows: 0);
          }
        } catch (e) {
          AppConfig.sqlLogResult(table: 'teams', operation: 'SELECT', error: e);
          _sbResult(rows: 0, error: e);
        }
      }

      return ProfileLookupResult.playerProfile(
        matchedPlayerId: playerId.isEmpty ? null : playerId,
        playerName: name.isEmpty ? null : name,
        resolvedRole: resolvedRole,
        resolvedTeamId: teamId.isEmpty ? null : teamId,
        resolvedTournamentId: tournamentId?.isEmpty ?? true ? null : tournamentId,
        resolvedTeamName: teamName?.isEmpty ?? true ? null : teamName,
      );
    }).catchError((_) => const ProfileLookupResult.notFound());
  }

  @override
  Future<OnlineRegistrationResult> registerOnlineUser({
    required String phoneRaw10,
    required String password,
    required bool profileFound,
    required String resolvedRole,
    required String? resolvedTeamId,
    required String? resolvedTournamentId,
    required String? matchedPlayerId,
    required List<String> matchedTournamentIds,
    required String? selectedTournamentId,
    required String? name,
    required String? surname,
  }) async {
    final raw10 = phoneRaw10.trim();
    final email = '$raw10@masterclass.com';

    UserCredential userCred;
    try {
      userCred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw Exception('Bu telefon numarası ile zaten kayıt var. Lütfen giriş yapın.');
      }
      rethrow;
    }

    final user = userCred.user;
    if (user == null) throw Exception('Kullanıcı oluşturulamadı.');

    final trimmedName = (name ?? '').trim();
    final trimmedSurname = (surname ?? '').trim();
    final fullName = profileFound
        ? null
        : ('$trimmedName $trimmedSurname').trim().isEmpty
        ? null
        : ('$trimmedName $trimmedSurname').trim();

    Map<String, dynamic> roleEntry;
    String? accessRole;
    if (resolvedRole == 'tournament_admin') {
      accessRole = 'tournament_admin';
      roleEntry = {
        'tournamentId': (selectedTournamentId ?? '').trim(),
        'teamId': null,
        'role': 'turnuva yöneticisi',
      };
    } else {
      accessRole = null;
      final roleTr = resolvedRole == 'manager' ? 'takım sorumlusu' : 'futbolcu';
      roleEntry = {
        'tournamentId': (resolvedTournamentId ?? '').trim().isEmpty
            ? null
            : (resolvedTournamentId ?? '').trim(),
        'teamId': (resolvedTeamId ?? '').trim().isEmpty ? null : (resolvedTeamId ?? '').trim(),
        'role': roleTr,
      };
    }

    final nowIso = DateTime.now().toIso8601String();
    try {
      _sbLog(
        table: 'users',
        query: 'UPSERT onConflict=id | id=${user.uid}',
        trace: StackTrace.current,
      );
      AppConfig.sqlLogStart(
        table: 'users',
        operation: 'UPSERT',
        filters: 'onConflict=id | id=${user.uid}',
      );
      await _client.from('users').upsert({
        'id': user.uid,
        'access_role': accessRole,
        'phone': raw10,
        if (fullName != null) 'full_name': fullName,
        if (trimmedName.isNotEmpty) 'name': trimmedName,
        if (trimmedSurname.isNotEmpty) 'surname': trimmedSurname,
        'roles': [roleEntry],
        if (resolvedRole == 'tournament_admin') 'tournament_ids': matchedTournamentIds,
        if (resolvedRole == 'tournament_admin') 'active_tournament_id': (selectedTournamentId ?? '').trim(),
        'updated_at': nowIso,
        'created_at': nowIso,
      }, onConflict: 'id');
      AppConfig.sqlLogResult(table: 'users', operation: 'UPSERT', count: 1);
      _sbResult(rows: 1);
    } catch (e) {
      AppConfig.sqlLogResult(table: 'users', operation: 'UPSERT', error: e);
      _sbResult(rows: 0, error: e);
    }

    if (resolvedRole == 'tournament_admin') {
    } else if (profileFound) {
      final pid = (matchedPlayerId ?? '').trim();
      if (pid.isNotEmpty) {
        try {
          _sbLog(
            table: 'players',
            query: 'UPDATE id=$pid',
            trace: StackTrace.current,
          );
          AppConfig.sqlLogStart(
            table: 'players',
            operation: 'UPDATE',
            filters: 'id=$pid',
          );
          await _client.from('players').update({'auth_uid': user.uid, 'updated_at': nowIso}).eq('id', pid);
          AppConfig.sqlLogResult(table: 'players', operation: 'UPDATE', count: 1);
          _sbResult(rows: 1);
        } catch (e) {
          AppConfig.sqlLogResult(table: 'players', operation: 'UPDATE', error: e);
          _sbResult(rows: 0, error: e);
        }
      }
    } else {
      try {
        _sbLog(
          table: 'players',
          query: 'INSERT phone=$raw10',
          trace: StackTrace.current,
        );
        AppConfig.sqlLogStart(
          table: 'players',
          operation: 'INSERT',
          filters: 'phone=$raw10',
        );
        await _client.from('players').insert({
          'team_id': (resolvedTeamId ?? 'free_agent_pool').trim().isEmpty
              ? 'free_agent_pool'
              : (resolvedTeamId ?? 'free_agent_pool').trim(),
          if (fullName != null) 'name': fullName,
          'role': 'Futbolcu',
          'phone': raw10,
          'phone_raw10': raw10,
          'auth_uid': user.uid,
          'created_at': nowIso,
          'updated_at': nowIso,
        });
        AppConfig.sqlLogResult(table: 'players', operation: 'INSERT', count: 1);
        _sbResult(rows: 1);
      } catch (e) {
        AppConfig.sqlLogResult(table: 'players', operation: 'INSERT', error: e);
        _sbResult(rows: 0, error: e);
      }
    }

    final tid = (selectedTournamentId ?? '').trim();
    final isTournamentAdmin = resolvedRole == 'tournament_admin' && tid.isNotEmpty;
    return OnlineRegistrationResult(
      uid: user.uid,
      isTournamentAdmin: isTournamentAdmin,
      tournamentId: isTournamentAdmin ? tid : null,
    );
  }
}
