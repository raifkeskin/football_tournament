import '../../../../core/utils/table_feed.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

import '../interfaces/i_auth_service.dart';
import '../../../../core/config/app_config.dart';
import '../../models/auth_models.dart';

class SupabaseAuthService implements IAuthService {
  SupabaseAuthService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

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
      return watchTableRows(
        _client,
        table: 'users',
        column: 'id',
        value: id,
      ).map((rows) {
        final row = rows.cast<Map<String, dynamic>>().firstWhere(
          (r) => (r['id'] ?? '').toString().trim() == id,
          orElse: () => const <String, dynamic>{},
        );
        if (row.isEmpty) return null;
        final name = (row['name'] ?? '').toString().trim();
        final surname = (row['surname'] ?? '').toString().trim();
        final fullName = (row['full_name'] ?? '').toString().trim();
        final displayName = fullName.isNotEmpty
            ? fullName
            : (name.isNotEmpty || surname.isNotEmpty
                  ? '$name $surname'.trim()
                  : null);
        return UserDoc(
          uid: (row['id'] ?? '').toString(),
          role: (row['access_role'] ?? row['role'])?.toString(),
          phone: (row['phone'] ?? '').toString(),
          displayName: displayName,
          isAdmin:
              (row['access_role']?.toString() == 'admin' ||
              row['access_role']?.toString() == 'super_admin'),
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
      return watchTableRows(_client, table: 'rosters').map((rows) {
        final filtered = rows.where(
          (r) =>
              (r['player_phone'] ?? r['playerPhone'] ?? '').toString().trim() ==
              p,
        );
        return filtered.map((r) {
          final row = Map<String, dynamic>.from(r);
          return RosterAssignment(
            id: (row['id'] ?? '').toString(),
            tournamentId: (row['tournament_id'] ?? row['tournamentId'] ?? '')
                .toString()
                .trim(),
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
  Future<AccountRequestOutcome> requestAccountPassword({
    required String phoneRaw10,
    String? fullName,
    bool isReset = false,
  }) async {
    final raw10 = phoneRaw10.trim();
    _sbLog(
      table: 'account_requests',
      query: 'RPC request_account_password phone=$raw10 | reset=$isReset',
      trace: StackTrace.current,
    );
    final String result;
    try {
      result = (await _client.rpc(
        'request_account_password',
        params: {
          'p_phone': raw10,
          'p_full_name': (fullName ?? '').trim().isEmpty
              ? null
              : fullName!.trim(),
          'p_reset': isReset,
        },
      )).toString();
      _sbResult(rows: 1);
    } catch (e) {
      _sbResult(rows: 0, error: e);
      rethrow;
    }
    return switch (result) {
      'requested' => AccountRequestOutcome.requested,
      'reset_requested' => AccountRequestOutcome.resetRequested,
      'already_pending' => AccountRequestOutcome.alreadyPending,
      'not_registered' => AccountRequestOutcome.notRegistered,
      _ => AccountRequestOutcome.invalidPhone,
    };
  }

  @override
  Stream<List<AccountRequestEntry>> watchAccountRequests({
    bool includeClosed = false,
  }) {
    String? text(dynamic v) {
      final s = (v ?? '').toString().trim();
      return s.isEmpty ? null : s;
    }

    Future<List<AccountRequestEntry>> fetch() async {
      _sbLog(
        table: 'account_requests_view',
        query: 'SELECT order=created_at desc | includeClosed=$includeClosed',
        trace: StackTrace.current,
      );
      var query = _client.from('account_requests_view').select();
      if (!includeClosed) query = query.eq('status', 'pending');
      final res = await query.order('created_at', ascending: false).limit(200);
      final rows = (res as List).cast<Map<String, dynamic>>();
      _sbResult(rows: rows.length);
      return rows
          .map(
            (r) => AccountRequestEntry(
              id: (r['id'] ?? '').toString(),
              phoneRaw10: (r['phone_raw10'] ?? '').toString().trim(),
              isReset: r['kind'] == 'reset',
              status: (r['status'] ?? '').toString().trim(),
              fullName: text(r['full_name']),
              playerName: text(r['player_name']),
              createdAt: _readDate(r['created_at']),
              reviewedAt: _readDate(r['reviewed_at']),
            ),
          )
          .toList();
    }

    // Yeni talepler birkaç saniyede bir yoklanır (tablo realtime yayınında
    // değil; liste küçük).
    final controller = StreamController<List<AccountRequestEntry>>.broadcast();
    Timer? timer;

    Future<void> emit() async {
      try {
        controller.add(await fetch());
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      }
    }

    controller.onListen = () {
      emit();
      timer = Timer.periodic(const Duration(seconds: 5), (_) => emit());
    };
    controller.onCancel = () async {
      timer?.cancel();
      await controller.close();
    };
    return controller.stream;
  }

  @override
  Future<TempPasswordGrant> approveAccountRequest(String id) async {
    _sbLog(
      table: 'account_requests',
      query: 'RPC approve_account_request id=$id',
      trace: StackTrace.current,
    );
    try {
      final res = await _client.rpc(
        'approve_account_request',
        params: {'p_id': id},
      );
      _sbResult(rows: 1);
      final m = Map<String, dynamic>.from(res as Map);
      final name = (m['full_name'] ?? '').toString().trim();
      return TempPasswordGrant(
        phoneRaw10: (m['phone'] ?? '').toString(),
        password: (m['password'] ?? '').toString(),
        isReset: m['kind'] == 'reset',
        fullName: name.isEmpty ? null : name,
      );
    } catch (e) {
      _sbResult(rows: 0, error: e);
      rethrow;
    }
  }

  @override
  Future<void> rejectAccountRequest(String id) async {
    _sbLog(
      table: 'account_requests',
      query: 'UPDATE status=rejected | id=$id',
      trace: StackTrace.current,
    );
    try {
      await _client
          .from('account_requests')
          .update({
            'status': 'rejected',
            'reviewed_by': _client.auth.currentUser?.id,
            'reviewed_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id);
      _sbResult(rows: 1);
    } catch (e) {
      _sbResult(rows: 0, error: e);
      rethrow;
    }
  }

  @override
  Future<void> changeOwnPassword(String newPassword) async {
    await _client.auth.updateUser(
      UserAttributes(
        password: newPassword,
        data: {'must_change_password': false},
      ),
    );
  }
}
