import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

import '../interfaces/i_league_service.dart';
import '../../../../core/config/app_config.dart';
import '../../../player/models/award.dart';
import '../../models/league.dart';
import '../../models/league_extras.dart';
import '../../../match/models/match.dart';

class SupabaseLeagueService implements ILeagueService {
  SupabaseLeagueService({
    SupabaseClient? client,
    Future<List<Map<String, dynamic>>> Function(Map<String, dynamic> payload)? insertLeagueSelectId,
    Future<void> Function(Map<String, dynamic> payload)? upsertLeague,
    Stream<List<Map<String, dynamic>>> Function()? streamLeagues,
    Future<void> Function({
      required String table,
      required String column,
      required String value,
    })? deleteWhereEq,
  }) :
        _client = client ?? Supabase.instance.client,
        _insertLeagueSelectId = insertLeagueSelectId,
        _upsertLeague = upsertLeague,
        _streamLeagues = streamLeagues,
        _deleteWhereEq = deleteWhereEq;

  final SupabaseClient _client;
  final Future<List<Map<String, dynamic>>> Function(Map<String, dynamic> payload)? _insertLeagueSelectId;
  final Future<void> Function(Map<String, dynamic> payload)? _upsertLeague;
  final Stream<List<Map<String, dynamic>>> Function()? _streamLeagues;
  final Future<void> Function({
    required String table,
    required String column,
    required String value,
  })? _deleteWhereEq;

  DateTime? _readDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  @override
  Stream<List<League>> watchLeagues() {
    AppConfig.sqlLogStart(
      table: 'leagues',
      operation: 'STREAM',
      filters: 'order=name asc',
    );

    final injected = _streamLeagues;
    if (injected != null) {
      return injected().map((rows) => rows.map((r) => League.fromMap(r)).toList());
    }

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
    AppConfig.sqlLogStart(
      table: 'leagues',
      operation: 'STREAM',
      filters: 'primaryKey=id | clientFilter=id=$id',
    );
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
      AppConfig.sqlLogStart(table: 'leagues', operation: 'INSERT');
      final payload = Map<String, dynamic>.from(league.toMap(snakeCase: true));

      final id = (payload['id'] ?? '').toString().trim();
      if (id.isEmpty) payload.remove('id');

      String? toNullIfBlank(dynamic v) {
        final s = (v ?? '').toString().trim();
        return s.isEmpty ? null : s;
      }

      String? dateOnly(dynamic v) {
        final s = (v ?? '').toString().trim();
        if (s.isEmpty) return null;
        final t = s.split('T').first.trim();
        return t.isEmpty ? null : t;
      }

      payload['logo_url'] = toNullIfBlank(payload['logo_url']);
      payload['youtube_url'] = toNullIfBlank(payload['youtube_url']);
      payload['instagram_url'] = toNullIfBlank(payload['instagram_url']);
      payload['access_code'] = toNullIfBlank(payload['access_code']);

      payload['start_date'] = dateOnly(payload['start_date']);
      payload['end_date'] = dateOnly(payload['end_date']);
      payload['transfer_start_date'] = dateOnly(payload['transfer_start_date']);
      payload['transfer_end_date'] = dateOnly(payload['transfer_end_date']);

      payload.putIfAbsent('starting_player_count', () => 11);
      payload.putIfAbsent('sub_player_count', () => 7);

      payload.remove('groups');

      final injected = _insertLeagueSelectId;
      final List<Map<String, dynamic>> rows;
      if (injected != null) {
        rows = await injected(payload);
      } else {
        final res = await _client.from('leagues').insert(payload).select('id').limit(1);
        rows = (res as List).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
      }

      if (rows.isNotEmpty) {
        final row = rows.first;
        AppConfig.sqlLogResult(table: 'leagues', operation: 'INSERT', count: 1);
        final newId = (row['id'] ?? '').toString().trim();
        if (newId.isEmpty) {
          throw Exception('Supabase INSERT başarılı görünüyor ama id dönmedi.');
        }
        return newId;
      }

      AppConfig.sqlLogResult(table: 'leagues', operation: 'INSERT', count: 0);
      throw Exception('Supabase INSERT sonucu boş döndü.');
    } catch (e) {
      AppConfig.sqlLogResult(table: 'leagues', operation: 'INSERT', error: e);
      print('[SQL LOG] leagues INSERT hata: $e');
      final keys = Map<String, dynamic>.from(league.toMap(snakeCase: true))..remove('groups');
      print('[SQL LOG] leagues INSERT alanlar: ${keys.keys.toList()}');
      throw Exception('Supabase leagues INSERT hatası: $e');
    }
  }

  @override
  Future<void> updateLeague(League league) async {
    final id = league.id.trim();
    if (id.isEmpty) return;
    try {
      AppConfig.sqlLogStart(table: 'leagues', operation: 'UPSERT', filters: 'onConflict=id | id=$id');
      final payload = Map<String, dynamic>.from(league.toMap(snakeCase: true));

      String? toNullIfBlank(dynamic v) {
        final s = (v ?? '').toString().trim();
        return s.isEmpty ? null : s;
      }

      String? dateOnly(dynamic v) {
        final s = (v ?? '').toString().trim();
        if (s.isEmpty) return null;
        final t = s.split('T').first.trim();
        return t.isEmpty ? null : t;
      }

      payload['logo_url'] = toNullIfBlank(payload['logo_url']);
      payload['youtube_url'] = toNullIfBlank(payload['youtube_url']);
      payload['instagram_url'] = toNullIfBlank(payload['instagram_url']);
      payload['access_code'] = toNullIfBlank(payload['access_code']);

      payload['start_date'] = dateOnly(payload['start_date']);
      payload['end_date'] = dateOnly(payload['end_date']);
      payload['transfer_start_date'] = dateOnly(payload['transfer_start_date']);
      payload['transfer_end_date'] = dateOnly(payload['transfer_end_date']);

      payload.putIfAbsent('starting_player_count', () => 11);
      payload.putIfAbsent('sub_player_count', () => 7);
      payload.remove('groups');

      final injected = _upsertLeague;
      if (injected != null) {
        await injected(payload);
      } else {
        await _client.from('leagues').upsert(payload, onConflict: 'id');
      }
      AppConfig.sqlLogResult(table: 'leagues', operation: 'UPSERT', count: 1);
    } catch (e) {
      AppConfig.sqlLogResult(table: 'leagues', operation: 'UPSERT', error: e);
      print('[SQL LOG] leagues UPSERT hata: $e');
      print('[SQL LOG] leagues UPSERT id=$id');
      throw Exception('Supabase leagues UPSERT hatası: $e');
    }
  }

  Future<void> _deleteEq({
    required String table,
    required String column,
    required String value,
  }) async {
    final injected = _deleteWhereEq;
    if (injected != null) {
      await injected(table: table, column: column, value: value);
      return;
    }
    await _client.from(table).delete().eq(column, value);
  }

  @override
  Future<void> deleteLeagueCascade(String leagueId) async {
    final id = leagueId.trim();
    if (id.isEmpty) return;
    Object? firstError;
    try {
      AppConfig.sqlLogStart(table: 'match_events', operation: 'DELETE', filters: 'league_id=$id');
      await _deleteEq(table: 'match_events', column: 'league_id', value: id);
      AppConfig.sqlLogResult(table: 'match_events', operation: 'DELETE');
    } catch (e) {
      firstError ??= e;
      AppConfig.sqlLogResult(table: 'match_events', operation: 'DELETE', error: e);
    }
    try {
      AppConfig.sqlLogStart(table: 'match_lineups', operation: 'DELETE', filters: 'league_id=$id');
      await _deleteEq(table: 'match_lineups', column: 'league_id', value: id);
      AppConfig.sqlLogResult(table: 'match_lineups', operation: 'DELETE');
    } catch (e) {
      firstError ??= e;
      AppConfig.sqlLogResult(table: 'match_lineups', operation: 'DELETE', error: e);
    }
    try {
      AppConfig.sqlLogStart(table: 'matches', operation: 'DELETE', filters: 'league_id=$id');
      await _deleteEq(table: 'matches', column: 'league_id', value: id);
      AppConfig.sqlLogResult(table: 'matches', operation: 'DELETE');
    } catch (e) {
      firstError ??= e;
      AppConfig.sqlLogResult(table: 'matches', operation: 'DELETE', error: e);
    }
    try {
      AppConfig.sqlLogStart(table: 'rosters', operation: 'DELETE', filters: 'league_id=$id');
      await _deleteEq(table: 'rosters', column: 'league_id', value: id);
      AppConfig.sqlLogResult(table: 'rosters', operation: 'DELETE');
    } catch (e) {
      firstError ??= e;
      AppConfig.sqlLogResult(table: 'rosters', operation: 'DELETE', error: e);
    }
    try {
      AppConfig.sqlLogStart(table: 'transfers', operation: 'DELETE', filters: 'league_id=$id');
      await _deleteEq(table: 'transfers', column: 'league_id', value: id);
      AppConfig.sqlLogResult(table: 'transfers', operation: 'DELETE');
    } catch (e) {
      firstError ??= e;
      AppConfig.sqlLogResult(table: 'transfers', operation: 'DELETE', error: e);
    }
    try {
      AppConfig.sqlLogStart(table: 'groups', operation: 'DELETE', filters: 'league_id=$id');
      await _deleteEq(table: 'groups', column: 'league_id', value: id);
      AppConfig.sqlLogResult(table: 'groups', operation: 'DELETE');
    } catch (e) {
      firstError ??= e;
      AppConfig.sqlLogResult(table: 'groups', operation: 'DELETE', error: e);
    }
    try {
      AppConfig.sqlLogStart(table: 'teams', operation: 'DELETE', filters: 'league_id=$id');
      await _deleteEq(table: 'teams', column: 'league_id', value: id);
      AppConfig.sqlLogResult(table: 'teams', operation: 'DELETE');
    } catch (e) {
      firstError ??= e;
      AppConfig.sqlLogResult(table: 'teams', operation: 'DELETE', error: e);
    }
    try {
      AppConfig.sqlLogStart(table: 'leagues', operation: 'DELETE', filters: 'id=$id');
      await _deleteEq(table: 'leagues', column: 'id', value: id);
      AppConfig.sqlLogResult(table: 'leagues', operation: 'DELETE');
    } catch (e) {
      firstError ??= e;
      AppConfig.sqlLogResult(table: 'leagues', operation: 'DELETE', error: e);
    }
    if (firstError != null) {
      throw firstError;
    }
  }

  @override
  Future<void> setDefaultLeague({required String leagueId}) async {
    final id = leagueId.trim();
    if (id.isEmpty) return;
    try {
      AppConfig.sqlLogStart(table: 'leagues', operation: 'UPDATE', filters: 'is_default=false WHERE id<>$id');
      await _client.from('leagues').update({'is_default': false}).neq('id', id);
      AppConfig.sqlLogStart(table: 'leagues', operation: 'UPDATE', filters: 'is_default=true WHERE id=$id');
      await _client.from('leagues').update({'is_default': true}).eq('id', id);
      AppConfig.sqlLogResult(table: 'leagues', operation: 'UPDATE');
    } catch (e) {
      AppConfig.sqlLogResult(table: 'leagues', operation: 'UPDATE', error: e);
    }
  }

  @override
  Future<void> setLeagueDefaultFlag({
    required String leagueId,
    required bool isDefault,
  }) async {
    final id = leagueId.trim();
    if (id.isEmpty) return;
    try {
      AppConfig.sqlLogStart(table: 'leagues', operation: 'UPDATE', filters: 'id=$id');
      await _client.from('leagues').update({'is_default': isDefault}).eq('id', id);
      AppConfig.sqlLogResult(table: 'leagues', operation: 'UPDATE', count: 1);
    } catch (e) {
      AppConfig.sqlLogResult(table: 'leagues', operation: 'UPDATE', error: e);
    }
  }

  @override
  Stream<List<GroupModel>> watchGroups(String leagueId) {
    final id = leagueId.trim();
    if (id.isEmpty) return const Stream<List<GroupModel>>.empty();
    AppConfig.sqlLogStart(
      table: 'groups',
      operation: 'STREAM',
      filters: 'primaryKey=id | clientFilter=league_id=$id',
    );
    return _client
        .from('groups')
        .stream(primaryKey: ['id'])
        .order('name', ascending: true)
        .map((rows) {
          final filtered = rows.where(
            (r) => (r['league_id'] ?? '').toString().trim() == id,
          );
          return filtered
              .map((r) => GroupModel.fromMap(r, (r['id'] ?? '').toString()))
              .toList();
        });
  }

  @override
  Future<void> addGroup(GroupModel group) async {
    try {
      AppConfig.sqlLogStart(table: 'groups', operation: 'INSERT', filters: 'league_id=${group.leagueId}');
      final payload = group.toMap(snakeCase: true);
      await _client.from('groups').insert(payload);
      AppConfig.sqlLogResult(table: 'groups', operation: 'INSERT', count: 1);
    } catch (e) {
      AppConfig.sqlLogResult(table: 'groups', operation: 'INSERT', error: e);
    }
  }

  @override
  Future<void> deleteGroupCascade(String groupId) async {
    final id = groupId.trim();
    if (id.isEmpty) return;
    try {
      AppConfig.sqlLogStart(table: 'matches', operation: 'DELETE', filters: 'group_id=$id');
      await _client.from('matches').delete().eq('group_id', id);
      AppConfig.sqlLogResult(table: 'matches', operation: 'DELETE');
    } catch (e) {
      AppConfig.sqlLogResult(table: 'matches', operation: 'DELETE', error: e);
    }
    try {
      AppConfig.sqlLogStart(table: 'teams', operation: 'UPDATE', filters: 'group_id=null WHERE group_id=$id');
      await _client
          .from('teams')
          .update({'group_id': null, 'group_name': null})
          .eq('group_id', id);
      AppConfig.sqlLogResult(table: 'teams', operation: 'UPDATE');
    } catch (e) {
      AppConfig.sqlLogResult(table: 'teams', operation: 'UPDATE', error: e);
    }
    try {
      AppConfig.sqlLogStart(table: 'groups', operation: 'DELETE', filters: 'id=$id');
      await _client.from('groups').delete().eq('id', id);
      AppConfig.sqlLogResult(table: 'groups', operation: 'DELETE');
    } catch (e) {
      AppConfig.sqlLogResult(table: 'groups', operation: 'DELETE', error: e);
    }
  }

  @override
  Future<List<String>> listPitchesOnce() async {
    try {
      AppConfig.sqlLogStart(table: 'pitches', operation: 'SELECT', filters: 'columns=name | order=name asc');
      final res = await _client.from('pitches').select('name').order('name', ascending: true);
      AppConfig.sqlLogResult(table: 'pitches', operation: 'SELECT', count: res.length);
      return res
          .map((e) => (e as Map)['name']?.toString() ?? '')
          .where((e) => e.trim().isNotEmpty)
          .toList();
    } catch (e) {
      AppConfig.sqlLogResult(table: 'pitches', operation: 'SELECT', error: e);
      return const [];
    }
  }

  @override
  Stream<List<Pitch>> watchPitches() {
    try {
      AppConfig.sqlLogStart(
        table: 'pitches',
        operation: 'STREAM',
        filters: 'primaryKey=id | order=name asc',
      );
      return _client
          .from('pitches')
          .stream(primaryKey: ['id'])
          .order('name', ascending: true)
          .map((rows) {
            return rows.map((r) {
              final name = (r['name'] ?? '').toString();
              return Pitch(
                id: (r['id'] ?? '').toString(),
                name: name,
                city: (r['city'] ?? '').toString(),
                country: (r['country'] ?? '').toString(),
                location: (r['location'] ?? '').toString(),
              );
            }).toList();
          });
    } catch (e) {
      AppConfig.sqlLogResult(table: 'pitches', operation: 'STREAM', error: e);
      return const Stream<List<Pitch>>.empty();
    }
  }

  @override
  Future<void> addPitch({
    required String name,
    String? city,
    String? country,
    String? location,
  }) async {
    final n = name.trim();
    if (n.isEmpty) return;
    final c = (city ?? '').trim();
    final co = (country ?? '').trim();
    final loc = (location ?? '').trim();
    try {
      AppConfig.sqlLogStart(table: 'pitches', operation: 'INSERT', filters: 'name=$n | city=$c | country=$co');
      await _client.from('pitches').insert({
        'name': n,
        'city': c.isEmpty ? null : c,
        'country': co.isEmpty ? null : co,
        'location': loc.isEmpty ? null : loc,
      });
      AppConfig.sqlLogResult(table: 'pitches', operation: 'INSERT', count: 1);
    } catch (e) {
      AppConfig.sqlLogResult(table: 'pitches', operation: 'INSERT', error: e);
    }
  }

  @override
  Future<void> deletePitch(String pitchId) async {
    final id = pitchId.trim();
    if (id.isEmpty) return;
    try {
      AppConfig.sqlLogStart(table: 'pitches', operation: 'DELETE', filters: 'id=$id');
      await _client.from('pitches').delete().eq('id', id);
      AppConfig.sqlLogResult(table: 'pitches', operation: 'DELETE');
    } catch (e) {
      AppConfig.sqlLogResult(table: 'pitches', operation: 'DELETE', error: e);
    }
  }

  @override
  Stream<List<NewsItem>> watchNews({
    required String tournamentId,
    bool includeUnpublished = false,
  }) {
    final id = tournamentId.trim();
    if (id.isEmpty) return const Stream<List<NewsItem>>.empty();
    try {
      AppConfig.sqlLogStart(
        table: 'news',
        operation: 'STREAM',
        filters: 'primaryKey=id | clientFilter=league_id=$id, is_published=${includeUnpublished ? 'any' : 'true'}',
      );
      return _client
          .from('news')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .map((rows) {
            return rows
                .where((r) {
                  final okLeague = (r['league_id'] ?? '').toString().trim() == id;
                  if (!okLeague) return false;
                  return includeUnpublished || (r['is_published'] == true);
                })
                .map((r) {
                  return NewsItem(
                    id: (r['id'] ?? '').toString(),
                    tournamentId: (r['league_id'] ?? '').toString(),
                    content: (r['content'] ?? '').toString(),
                    isPublished: r['is_published'] == true,
                    createdAt: _readDate(r['created_at']),
                  );
                })
                .toList();
          });
    } catch (e) {
      AppConfig.sqlLogResult(table: 'news', operation: 'STREAM', error: e);
      return const Stream<List<NewsItem>>.empty();
    }
  }

  @override
  Future<void> addNews({required String tournamentId, required String content}) async {
    final tId = tournamentId.trim();
    final text = content.trim();
    if (tId.isEmpty) {
      throw Exception('Turnuva seçilmeden haber eklenemez.');
    }
    if (text.isEmpty) return;
    try {
      AppConfig.sqlLogStart(
        table: 'news',
        operation: 'INSERT',
        filters: 'league_id=$tId',
      );
      await _client.from('news').insert({
        'league_id': tId,
        'content': text,
        'is_published': true,
        'created_at': DateTime.now().toIso8601String(),
      });
      AppConfig.sqlLogResult(table: 'news', operation: 'INSERT', count: 1);
    } catch (e) {
      AppConfig.sqlLogResult(table: 'news', operation: 'INSERT', error: e);
      rethrow;
    }
  }

  @override
  Future<void> setNewsPublished({
    required String newsId,
    required bool isPublished,
  }) async {
    final id = newsId.trim();
    if (id.isEmpty) return;
    try {
      AppConfig.sqlLogStart(
        table: 'news',
        operation: 'UPDATE',
        filters: 'id=$id | is_published=$isPublished',
      );
      await _client.from('news').update({
        'is_published': isPublished,
      }).eq('id', id);
      AppConfig.sqlLogResult(table: 'news', operation: 'UPDATE', count: 1);
    } catch (e) {
      AppConfig.sqlLogResult(table: 'news', operation: 'UPDATE', error: e);
      rethrow;
    }
  }

  @override
  Future<void> updateNewsContent({
    required String newsId,
    required String content,
  }) async {
    final id = newsId.trim();
    if (id.isEmpty) return;
    final text = content.trim();
    try {
      AppConfig.sqlLogStart(table: 'news', operation: 'UPDATE', filters: 'id=$id');
      await _client.from('news').update({
        'content': text,
      }).eq('id', id);
      AppConfig.sqlLogResult(table: 'news', operation: 'UPDATE', count: 1);
    } catch (e) {
      AppConfig.sqlLogResult(table: 'news', operation: 'UPDATE', error: e);
      rethrow;
    }
  }

  @override
  Future<void> deleteNews({required String newsId}) async {
    final id = newsId.trim();
    if (id.isEmpty) return;
    try {
      AppConfig.sqlLogStart(table: 'news', operation: 'DELETE', filters: 'id=$id');
      await _client.from('news').delete().eq('id', id);
      AppConfig.sqlLogResult(table: 'news', operation: 'DELETE', count: 1);
    } catch (e) {
      AppConfig.sqlLogResult(table: 'news', operation: 'DELETE', error: e);
      rethrow;
    }
  }

  @override
  Stream<List<Award>> watchAwardsForLeague(String leagueId) {
    final id = leagueId.trim();
    if (id.isEmpty) return const Stream<List<Award>>.empty();
    try {
      AppConfig.sqlLogStart(
        table: 'awards',
        operation: 'STREAM',
        filters: 'primaryKey=id | clientFilter=league_id=$id | order=name asc',
      );
      return _client
          .from('awards')
          .stream(primaryKey: ['id'])
          .order('name', ascending: true)
          .map((rows) {
            return rows
                .where((r) {
                  return (r['league_id'] ?? '').toString().trim() == id;
                })
                .map((r) => Award.fromMap(Map<String, dynamic>.from(r), (r['id'] ?? '').toString()))
                .toList();
          });
    } catch (e) {
      AppConfig.sqlLogResult(table: 'awards', operation: 'STREAM', error: e);
      return const Stream<List<Award>>.empty();
    }
  }

  @override
  Future<void> addAward({
    required String leagueId,
    required String name,
    String? description,
  }) async {
    final id = leagueId.trim();
    final trimmed = name.trim();
    if (id.isEmpty) return;
    if (trimmed.isEmpty) return;
    try {
      AppConfig.sqlLogStart(
        table: 'awards',
        operation: 'INSERT',
        filters: 'league_id=$id',
      );
      await _client.from('awards').insert({
        'league_id': id,
        'name': trimmed,
        'description': (description ?? '').trim().isEmpty ? null : description!.trim(),
        'created_at': DateTime.now().toIso8601String(),
      });
      AppConfig.sqlLogResult(table: 'awards', operation: 'INSERT', count: 1);
    } catch (e) {
      AppConfig.sqlLogResult(table: 'awards', operation: 'INSERT', error: e);
      rethrow;
    }
  }

  @override
  Future<void> deleteAward(String awardId) async {
    final id = awardId.trim();
    if (id.isEmpty) return;
    try {
      AppConfig.sqlLogStart(table: 'awards', operation: 'DELETE', filters: 'id=$id');
      await _client.from('awards').delete().eq('id', id);
      AppConfig.sqlLogResult(table: 'awards', operation: 'DELETE', count: 1);
    } catch (e) {
      AppConfig.sqlLogResult(table: 'awards', operation: 'DELETE', error: e);
      rethrow;
    }
  }

  @override
  Future<String> exportCollectionToJson(String collectionName) async {
    final name = collectionName.trim();
    if (name.isEmpty) return '[]';
    try {
      AppConfig.sqlLogStart(table: name, operation: 'SELECT');
      final res = await _client.from(name).select();
      AppConfig.sqlLogResult(table: name, operation: 'SELECT', count: res.length);
      return jsonEncode(res);
    } catch (e) {
      AppConfig.sqlLogResult(table: name, operation: 'SELECT', error: e);
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
        AppConfig.sqlLogStart(table: c, operation: 'SELECT');
        final res = await _client.from(c).select();
        out[c] = res;
        AppConfig.sqlLogResult(table: c, operation: 'SELECT', count: out[c] is List ? (out[c] as List).length : 0);
      } catch (_) {
        out[c] = const [];
      }
    }
    return out;
  }
}
