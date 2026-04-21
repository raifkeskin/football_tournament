import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

import '../interfaces/i_auth_service.dart';
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

  @override
  Future<ConfirmationResult> startPhoneAuthWeb({required String phoneNumber}) {
    throw UnimplementedError();
  }

  @override
  Stream<UserDoc?> watchUserDoc(String uid) {
    throw UnimplementedError();
  }

  @override
  Stream<List<RosterAssignment>> watchRosterAssignmentsByPhone(String phone) {
    throw UnimplementedError();
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
    await _client.from('otp_codes').insert({
      'phone_raw10': raw10,
      'code': c,
      'status': 'pending',
      'expires_at': expiresAt.toIso8601String(),
    });
  }

  @override
  Future<OtpRequest?> getOtpRequest(String phoneRaw10) async {
    final raw10 = phoneRaw10.trim();
    if (raw10.isEmpty) return null;
    final res = await _client
        .from('otp_codes')
        .select('phone_raw10, code, expires_at, status, created_at')
        .eq('phone_raw10', raw10)
        .eq('status', 'pending')
        .order('created_at', ascending: false)
        .limit(1);
    if (res is! List || res.isEmpty) return null;
    final row = (res.first as Map).cast<String, dynamic>();
    final code = (row['code'] ?? '').toString().trim();
    final expiresAt = _readDate(row['expires_at']);
    if (code.isEmpty || expiresAt == null) return null;
    return OtpRequest(phoneRaw10: raw10, code: code, expiresAt: expiresAt);
  }

  @override
  Future<void> deleteOtpRequest(String phoneRaw10) async {
    final raw10 = phoneRaw10.trim();
    if (raw10.isEmpty) return;
    await _client
        .from('otp_codes')
        .update({'status': 'verified', 'verified_at': DateTime.now().toIso8601String()})
        .eq('phone_raw10', raw10)
        .eq('status', 'pending');
  }

  @override
  Stream<List<OtpCodeEntry>> watchOtpCodes({bool includeVerified = false}) {
    Future<List<OtpCodeEntry>> fetch() async {
      final res = await _client
          .from('otp_codes')
          .select('id, phone_raw10, code, status, expires_at, created_at')
          .order('created_at', ascending: false)
          .limit(200);
      if (res is! List) return const [];
      final rows = res.cast<Map<String, dynamic>>();
      final filtered = includeVerified
          ? rows
          : rows.where((r) => (r['status'] ?? '').toString().trim() == 'pending');
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
    throw UnimplementedError();
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
    return OnlineRegistrationResult(
      uid: '',
      isTournamentAdmin: resolvedRole == 'tournament_admin',
      tournamentId: selectedTournamentId ?? resolvedTournamentId,
    );
  }
}
