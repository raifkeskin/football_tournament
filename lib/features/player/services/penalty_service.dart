import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';

class PlayerPenalty {
  const PlayerPenalty({
    required this.id,
    required this.playerId,
    required this.seasonId,
    required this.matchCount,
    required this.isActive,
    required this.reason,
  });

  final String id;
  final String playerId;
  final String seasonId;
  final int matchCount;
  final bool isActive;
  final String reason;

  factory PlayerPenalty.fromMap(Map<String, dynamic> map) {
    int readInt(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString().replaceAll('\u0000', '').trim()) ?? 0;
    }

    bool readBool(dynamic v) {
      if (v == null) return false;
      if (v is bool) return v;
      if (v is num) return v != 0;
      final s = v.toString().trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes' || s == 'y';
    }

    String readString(dynamic v) => (v ?? '').toString().replaceAll('\u0000', '').trim();

    return PlayerPenalty(
      id: readString(map['id']),
      playerId: readString(map['player_id'] ?? map['playerId']),
      seasonId: readString(map['season_id'] ?? map['seasonId']),
      matchCount: readInt(map['match_count'] ?? map['matchCount']),
      isActive: readBool(map['is_active'] ?? map['isActive']),
      reason: readString(map['description'] ?? map['penalty_reason'] ?? map['reason']),
    );
  }
}

class PenaltyService {
  PenaltyService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Stream<Map<String, PlayerPenalty>> watchPenaltiesByPlayerId(
    String seasonId, {
    bool? isActive,
  }) {
    if (AppConfig.activeDatabase != DatabaseType.supabase) {
      return const Stream<Map<String, PlayerPenalty>>.empty();
    }
    final sid = seasonId.trim();
    if (sid.isEmpty) return const Stream<Map<String, PlayerPenalty>>.empty();
    try {
      return _client
          .from('player_penalties')
          .stream(primaryKey: ['id'])
          .map((rows) {
            final out = <String, PlayerPenalty>{};
            for (final r in rows) {
              final row = Map<String, dynamic>.from(r);
              final p = PlayerPenalty.fromMap(row);
              if (p.seasonId.trim() != sid) continue;
              if (isActive != null && p.isActive != isActive) continue;
              final pid = p.playerId.trim();
              if (pid.isEmpty) continue;
              final existing = out[pid];
              if (existing == null) {
                out[pid] = p;
                continue;
              }
              if (!existing.isActive && p.isActive) {
                out[pid] = p;
                continue;
              }
              out[pid] = p;
            }
            return out;
          });
    } catch (_) {
      return const Stream<Map<String, PlayerPenalty>>.empty();
    }
  }

  Future<bool> checkPlayerPenalty(String playerId, String seasonId) async {
    if (AppConfig.activeDatabase != DatabaseType.supabase) return false;
    final pid = playerId.trim();
    final sid = seasonId.trim();
    if (pid.isEmpty || sid.isEmpty) return false;
    try {
      final res = await _client
          .from('player_penalties')
          .select('id')
          .eq('player_id', pid)
          .eq('season_id', sid)
          .eq('is_active', true)
          .limit(1);
      return res.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Stream<Map<String, PlayerPenalty>> watchActivePenaltiesByPlayerId(String seasonId) {
    return watchPenaltiesByPlayerId(seasonId, isActive: true);
  }

  Stream<Set<String>> watchActivePenalizedPlayerIds(String seasonId) {
    return watchActivePenaltiesByPlayerId(seasonId).map((m) => m.keys.toSet());
  }

  Future<PlayerPenalty?> getActivePenaltyOnce({
    required String playerId,
    required String seasonId,
  }) async {
    if (AppConfig.activeDatabase != DatabaseType.supabase) return null;
    final pid = playerId.trim();
    final sid = seasonId.trim();
    if (pid.isEmpty || sid.isEmpty) return null;
    try {
      final res = await _client
          .from('player_penalties')
          .select()
          .eq('player_id', pid)
          .eq('season_id', sid)
          .eq('is_active', true)
          .limit(1);
      if (res.isEmpty) return null;
      return PlayerPenalty.fromMap((res.first as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<PlayerPenalty?> getPenaltyOnce({
    required String playerId,
    required String seasonId,
  }) async {
    if (AppConfig.activeDatabase != DatabaseType.supabase) return null;
    final pid = playerId.trim();
    final sid = seasonId.trim();
    if (pid.isEmpty || sid.isEmpty) return null;
    try {
      final res = await _client
          .from('player_penalties')
          .select()
          .eq('player_id', pid)
          .eq('season_id', sid)
          .order('updated_at', ascending: false)
          .limit(1);
      if (res.isEmpty) return null;
      return PlayerPenalty.fromMap((res.first as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<PlayerPenalty?> getPenaltyById(String penaltyId) async {
    if (AppConfig.activeDatabase != DatabaseType.supabase) return null;
    final id = penaltyId.trim();
    if (id.isEmpty) return null;
    try {
      final res = await _client.from('player_penalties').select().eq('id', id).limit(1);
      if (res.isEmpty) return null;
      return PlayerPenalty.fromMap((res.first as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<void> updatePenaltyById({
    required String penaltyId,
    required int matchCount,
    required String description,
  }) async {
    if (AppConfig.activeDatabase != DatabaseType.supabase) {
      throw Exception('Bu işlem bu veritabanı modunda desteklenmiyor.');
    }
    final id = penaltyId.trim();
    if (id.isEmpty) throw Exception('Ceza id boş olamaz.');
    if (matchCount < 0) throw Exception('Maç sayısı geçerli olmalı.');

    final nowIso = DateTime.now().toIso8601String();
    final desc = description.trim();
    final payload = <String, dynamic>{
      'match_count': matchCount,
      'is_active': matchCount > 0,
      'updated_at': nowIso,
      'description': desc.isEmpty ? null : desc,
    };

    try {
      await _client.from('player_penalties').update(payload).eq('id', id);
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST204') rethrow;
      final payload2 = <String, dynamic>{
        'match_count': matchCount,
        'is_active': matchCount > 0,
        'updated_at': nowIso,
        'penalty_reason': desc.isEmpty ? null : desc,
      };
      try {
        await _client.from('player_penalties').update(payload2).eq('id', id);
      } on PostgrestException catch (e2) {
        if (e2.code != 'PGRST204') rethrow;
        await _client.from('player_penalties').update({
          'match_count': matchCount,
          'is_active': matchCount > 0,
          'updated_at': nowIso,
        }).eq('id', id);
      }
    }
  }

  Future<void> deletePenaltyById(String penaltyId) async {
    if (AppConfig.activeDatabase != DatabaseType.supabase) {
      throw Exception('Bu işlem bu veritabanı modunda desteklenmiyor.');
    }
    final id = penaltyId.trim();
    if (id.isEmpty) throw Exception('Ceza id boş olamaz.');
    await _client.from('player_penalties').delete().eq('id', id);
  }

  Future<void> upsertPlayerPenalty({
    required String playerId,
    required String seasonId,
    required int matchCount,
    required String description,
  }) async {
    if (AppConfig.activeDatabase != DatabaseType.supabase) {
      throw Exception('Bu işlem bu veritabanı modunda desteklenmiyor.');
    }
    final pid = playerId.trim();
    final sid = seasonId.trim();
    if (pid.isEmpty || sid.isEmpty) throw Exception('Ceza alanları eksik.');
    if (matchCount < 0) throw Exception('Maç sayısı geçerli olmalı.');

    final nowIso = DateTime.now().toIso8601String();
    final desc = description.trim();

    final existing = await _client
        .from('player_penalties')
        .select('id')
        .eq('player_id', pid)
        .eq('season_id', sid)
        .limit(1);
    final existingId =
        existing.isEmpty ? '' : ((existing.first as Map)['id'] ?? '').toString().trim();

    if (matchCount == 0) {
      if (existingId.isEmpty) return;
      await _client.from('player_penalties').update({
        'is_active': false,
        'match_count': 0,
        'updated_at': nowIso,
      }).eq('id', existingId);
      return;
    }

    Future<void> insertOrUpdate(Map<String, dynamic> payload) async {
      if (existingId.isEmpty) {
        await _client.from('player_penalties').insert(payload);
      } else {
        await _client.from('player_penalties').update(payload).eq('id', existingId);
      }
    }

    final base = <String, dynamic>{
      'player_id': pid,
      'season_id': sid,
      'is_active': true,
      'match_count': matchCount,
      'updated_at': nowIso,
      if (existingId.isEmpty) 'created_at': nowIso,
    };

    try {
      await insertOrUpdate({...base, 'description': desc.isEmpty ? null : desc});
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST204') rethrow;
      try {
        await insertOrUpdate({...base, 'penalty_reason': desc.isEmpty ? null : desc});
      } on PostgrestException catch (e2) {
        if (e2.code != 'PGRST204') rethrow;
        await insertOrUpdate(base);
      }
    }
  }
}
