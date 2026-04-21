import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

import '../interfaces/i_league_service.dart';
import '../../models/league.dart';
import '../../models/league_extras.dart';
import '../../models/match.dart';
import '../../utils/string_utils.dart';

class SupabaseLeagueService implements ILeagueService {
  SupabaseLeagueService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  DateTime? _readDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  @override
  Stream<List<League>> watchLeagues() {
    return _client
        .from('leagues')
        .stream(primaryKey: ['id'])
        .order('name', ascending: true)
        .map((rows) => rows.map((r) => League.fromMap(r)).toList());
  }

  @override
  Stream<League?> watchLeagueById(String leagueId) {
    final id = leagueId.trim();
    if (id.isEmpty) return const Stream<League?>.empty();
    return _client
        .from('leagues')
        .stream(primaryKey: ['id'])
        .map((rows) {
          final row = rows.cast<Map<String, dynamic>>().firstWhere(
            (r) => (r['id'] ?? '').toString().trim() == id,
            orElse: () => const <String, dynamic>{},
          );
          return row.isEmpty ? null : League.fromMap(row);
        });
  }

  @override
  Stream<String> watchLeagueName(String leagueId) {
    return watchLeagueById(leagueId).map((l) => (l?.name ?? '').trim());
  }

  @override
  Future<String> addLeague(League league) async {
    try {
      final payload = league.toMap(snakeCase: true);
      final res = await _client.from('leagues').insert(payload).select('id').limit(1);
      if (res is List && res.isNotEmpty) {
        final row = (res.first as Map).cast<String, dynamic>();
        return (row['id'] ?? '').toString();
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  @override
  Future<void> updateLeague(League league) async {
    final id = league.id.trim();
    if (id.isEmpty) return;
    try {
      await _client
          .from('leagues')
          .upsert(league.toMap(snakeCase: true), onConflict: 'id');
    } catch (_) {}
  }

  @override
  Future<void> deleteLeagueCascade(String leagueId) async {
    final id = leagueId.trim();
    if (id.isEmpty) return;
    try {
      await _client.from('match_events').delete().eq('tournament_id', id);
    } catch (_) {}
    try {
      await _client.from('match_lineups').delete().eq('tournament_id', id);
    } catch (_) {}
    try {
      await _client.from('matches').delete().eq('tournament_id', id);
    } catch (_) {}
    try {
      await _client.from('rosters').delete().eq('tournament_id', id);
    } catch (_) {}
    try {
      await _client.from('transfers').delete().eq('tournament_id', id);
    } catch (_) {}
    try {
      await _client.from('groups').delete().eq('tournament_id', id);
    } catch (_) {}
    try {
      await _client.from('teams').delete().eq('league_id', id);
    } catch (_) {}
    try {
      await _client.from('leagues').delete().eq('id', id);
    } catch (_) {}
  }

  @override
  Future<void> setDefaultLeague({required String leagueId}) async {
    final id = leagueId.trim();
    if (id.isEmpty) return;
    try {
      await _client.from('leagues').update({'is_default': false}).neq('id', id);
      await _client.from('leagues').update({'is_default': true}).eq('id', id);
    } catch (_) {}
  }

  @override
  Future<void> setLeagueDefaultFlag({
    required String leagueId,
    required bool isDefault,
  }) async {
    final id = leagueId.trim();
    if (id.isEmpty) return;
    try {
      await _client.from('leagues').update({'is_default': isDefault}).eq('id', id);
    } catch (_) {}
  }

  @override
  Stream<List<GroupModel>> watchGroups(String leagueId) {
    final id = leagueId.trim();
    if (id.isEmpty) return const Stream<List<GroupModel>>.empty();
    return _client
        .from('groups')
        .stream(primaryKey: ['id'])
        .order('name', ascending: true)
        .map((rows) {
          final filtered = rows.where(
            (r) => (r['tournament_id'] ?? '').toString().trim() == id,
          );
          return filtered
              .map((r) => GroupModel.fromMap(r, (r['id'] ?? '').toString()))
              .toList();
        });
  }

  @override
  Future<void> addGroup(GroupModel group) async {
    try {
      final payload = group.toMap(snakeCase: true);
      await _client.from('groups').insert(payload);
    } catch (_) {}
  }

  @override
  Future<void> deleteGroupCascade(String groupId) async {
    final id = groupId.trim();
    if (id.isEmpty) return;
    try {
      await _client.from('matches').delete().eq('group_id', id);
    } catch (_) {}
    try {
      await _client
          .from('teams')
          .update({'group_id': null, 'group_name': null})
          .eq('group_id', id);
    } catch (_) {}
    try {
      await _client.from('groups').delete().eq('id', id);
    } catch (_) {}
  }

  @override
  Future<void> setGroupTeams({
    required String groupId,
    required List<String> teamIds,
  }) async {
    final id = groupId.trim();
    if (id.isEmpty) return;

    try {
      final groupRes = await _client.from('groups').select('name').eq('id', id).limit(1);
      String groupName = '';
      if (groupRes is List && groupRes.isNotEmpty) {
        groupName = ((groupRes.first as Map)['name'] ?? '').toString();
      }

      await _client.from('groups').update({'team_ids': teamIds}).eq('id', id);
      await _client
          .from('teams')
          .update({'group_id': null, 'group_name': null})
          .eq('group_id', id);
      if (teamIds.isNotEmpty) {
        await _client
            .from('teams')
            .update({'group_id': id, 'group_name': groupName})
            .inFilter('id', teamIds);
      }
    } catch (_) {}
  }

  @override
  Future<List<String>> listPitchesOnce() async {
    try {
      final res = await _client.from('pitches').select('name').order('name', ascending: true);
      if (res is! List) return const [];
      return res
          .map((e) => (e as Map)['name']?.toString() ?? '')
          .where((e) => e.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Stream<List<Pitch>> watchPitches() {
    try {
      return _client
          .from('pitches')
          .stream(primaryKey: ['id'])
          .order('name_key', ascending: true)
          .map((rows) {
            return rows.map((r) {
              final name = (r['name'] ?? '').toString();
              return Pitch(
                id: (r['id'] ?? '').toString(),
                name: name,
                nameKey: (r['name_key'] ?? StringUtils.normalizeTrKey(name)).toString(),
                location: (r['location'] ?? '').toString(),
              );
            }).toList();
          });
    } catch (_) {
      return const Stream<List<Pitch>>.empty();
    }
  }

  @override
  Future<void> addPitch({required String name, String? location}) async {
    final n = name.trim();
    if (n.isEmpty) return;
    try {
      await _client.from('pitches').insert({
        'name': n,
        'name_key': StringUtils.normalizeTrKey(n),
        'location': (location ?? '').trim().isEmpty ? null : (location ?? '').trim(),
      });
    } catch (_) {}
  }

  @override
  Future<void> deletePitch(String pitchId) async {
    final id = pitchId.trim();
    if (id.isEmpty) return;
    try {
      await _client.from('pitches').delete().eq('id', id);
    } catch (_) {}
  }

  @override
  Stream<List<NewsItem>> watchNews({
    required String tournamentId,
    bool includeUnpublished = false,
  }) {
    final id = tournamentId.trim();
    if (id.isEmpty) return const Stream<List<NewsItem>>.empty();
    try {
      return _client
          .from('news')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .map((rows) {
            return rows
                .where((r) {
                  final okLeague = (r['tournament_id'] ?? '').toString().trim() == id;
                  if (!okLeague) return false;
                  return includeUnpublished || (r['is_published'] == true);
                })
                .map((r) {
                  return NewsItem(
                    id: (r['id'] ?? '').toString(),
                    tournamentId: (r['tournament_id'] ?? '').toString(),
                    content: (r['content'] ?? '').toString(),
                    isPublished: r['is_published'] == true,
                    createdAt: _readDate(r['created_at']),
                  );
                })
                .toList();
          });
    } catch (_) {
      return const Stream<List<NewsItem>>.empty();
    }
  }

  @override
  Future<String> exportCollectionToJson(String collectionName) async {
    final name = collectionName.trim();
    if (name.isEmpty) return '[]';
    try {
      final res = await _client.from(name).select();
      if (res is! List) return '[]';
      return jsonEncode(res);
    } catch (_) {
      return '[]';
    }
  }

  @override
  Future<Map<String, dynamic>> buildFirestoreBackup({
    List<String>? collections,
  }) async {
    final cols = collections ?? const ['leagues', 'groups', 'teams', 'matches'];
    final out = <String, dynamic>{};
    for (final c in cols) {
      try {
        final res = await _client.from(c).select();
        out[c] = res is List ? res : const [];
      } catch (_) {
        out[c] = const [];
      }
    }
    return out;
  }
}
