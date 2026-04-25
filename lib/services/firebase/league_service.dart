import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_config.dart';
import '../../models/award.dart';
import '../../models/league.dart';
import '../../models/league_extras.dart';
import '../../models/match.dart';
import '../../utils/string_utils.dart';
import '../interfaces/i_league_service.dart';
import 'database_service.dart';

class FirebaseLeagueService implements ILeagueService {
  FirebaseLeagueService({
    DatabaseService? databaseService,
    FirebaseFirestore? firestore,
    SupabaseClient? supabaseClient,
    Future<List<Map<String, dynamic>>> Function()? supabaseSelectPitches,
  })  : _db = databaseService ?? DatabaseService(firestore: firestore),
        _firestore = firestore ?? FirebaseFirestore.instance,
        _supabase =
            supabaseClient ?? (supabaseSelectPitches != null ? null : Supabase.instance.client),
        _supabaseSelectPitches = supabaseSelectPitches;

  final DatabaseService _db;
  final FirebaseFirestore _firestore;
  final SupabaseClient? _supabase;
  final Future<List<Map<String, dynamic>>> Function()? _supabaseSelectPitches;

  @override
  Stream<List<League>> watchLeagues() {
    return _db.getLeagues().map((snap) {
      final list = snap.docs
          .map((d) => League.fromMap({...d.data() as Map<String, dynamic>, 'id': d.id}))
          .toList();
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    });
  }

  @override
  Stream<League?> watchLeagueById(String leagueId) {
    final id = leagueId.trim();
    if (id.isEmpty) return const Stream<League?>.empty();
    return _firestore.collection('leagues').doc(id).snapshots().map((snap) {
      if (!snap.exists) return null;
      final data = snap.data() ?? <String, dynamic>{};
      return League.fromMap({...data, 'id': snap.id});
    });
  }

  @override
  Stream<String> watchLeagueName(String leagueId) {
    return watchLeagueById(leagueId).map((l) => (l?.name ?? leagueId).trim());
  }

  @override
  Future<String> addLeague(League league) => _db.addLeague(league);
  @override
  Future<void> updateLeague(League league) => _db.updateLeague(league);
  @override
  Future<void> deleteLeagueCascade(String leagueId) => _db.deleteLeagueCascade(leagueId);
  @override
  Future<void> setDefaultLeague({required String leagueId}) => _db.setDefaultLeague(leagueId: leagueId);
  @override
  Future<void> setLeagueDefaultFlag({required String leagueId, required bool isDefault}) =>
      _db.setLeagueDefaultFlag(leagueId: leagueId, isDefault: isDefault);

  @override
  Stream<List<GroupModel>> watchGroups(String leagueId) => _db.getGroups(leagueId);
  @override
  Future<void> addGroup(GroupModel group) => _db.addGroup(group);
  @override
  Future<void> deleteGroupCascade(String groupId) => _db.deleteGroupCascade(groupId);

  @override
  Future<List<String>> listPitchesOnce() async {
    if (AppConfig.activeDatabase == DatabaseType.supabase) {
      try {
        AppConfig.logDb('SUPABASE SELECT pitches(name) ORDER name');
        final List<Map<String, dynamic>> rows;
        final fn = _supabaseSelectPitches;
        if (fn != null) {
          rows = await fn();
        } else {
          final c = _supabase;
          if (c == null) return const [];
          final res = await c.from('pitches').select('name').order('name', ascending: true);
          rows = res.cast<Map<String, dynamic>>();
        }
        return rows.map((r) => (r['name'] ?? '').toString()).where((e) => e.trim().isNotEmpty).toList();
      } catch (_) {
        return const [];
      }
    }
    AppConfig.logDb('FIREBASE GET pitches');
    final snap = await _firestore.collection('pitches').get();
    final names = <String>[];
    for (final d in snap.docs) {
      final data = d.data();
      final name = (data['name'] ?? '').toString().trim();
      if (name.isNotEmpty) names.add(name);
    }
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  @override
  Stream<List<Pitch>> watchPitches() {
    if (AppConfig.activeDatabase == DatabaseType.supabase) {
      try {
        AppConfig.logDb('SUPABASE STREAM pitches ORDER name');
        final c = _supabase;
        if (c == null) return const Stream<List<Pitch>>.empty();
        return c.from('pitches').stream(primaryKey: ['id']).order('name', ascending: true).map((rows) {
          return rows.map((r) {
            return Pitch(
              id: (r['id'] ?? '').toString(),
              name: (r['name'] ?? '').toString(),
              city: (r['city'] ?? '').toString(),
              country: (r['country'] ?? '').toString(),
              location: (r['location'] ?? '').toString(),
            );
          }).toList();
        });
      } catch (_) {
        return const Stream<List<Pitch>>.empty();
      }
    }
    AppConfig.logDb('FIREBASE STREAM pitches ORDER nameKey');
    return _firestore.collection('pitches').orderBy('nameKey').snapshots().map((snap) {
      return snap.docs
          .map((d) {
            final data = d.data();
            return Pitch(
              id: d.id,
              name: (data['name'] ?? '').toString(),
              city: (data['city'] ?? '').toString(),
              country: (data['country'] ?? '').toString(),
              location: (data['location'] ?? '').toString(),
            );
          })
          .toList();
    });
  }

  @override
  Future<void> addPitch({
    required String name,
    String? city,
    String? country,
    String? location,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final cityTrim = (city ?? '').trim();
    final co = (country ?? '').trim();
    final loc = (location ?? '').trim();
    if (AppConfig.activeDatabase == DatabaseType.supabase) {
      try {
        AppConfig.logDb('SUPABASE INSERT pitches');
        final client = _supabase;
        if (client == null) return;
        await client.from('pitches').insert({
          'name': trimmed,
          'city': cityTrim.isEmpty ? null : cityTrim,
          'country': co.isEmpty ? null : co,
          'location': loc.isEmpty ? null : loc,
        });
      } catch (_) {}
      return;
    }
    AppConfig.logDb('FIREBASE ADD pitches');
    await _firestore.collection('pitches').add({
      'name': trimmed,
      'nameKey': StringUtils.normalizeTrKey(trimmed),
      'city': cityTrim.isEmpty ? null : cityTrim,
      'country': co.isEmpty ? null : co,
      'location': loc.isEmpty ? null : loc,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> deletePitch(String pitchId) async {
    final id = pitchId.trim();
    if (id.isEmpty) return;
    if (AppConfig.activeDatabase == DatabaseType.supabase) {
      try {
        AppConfig.logDb('SUPABASE DELETE pitches WHERE id=$id');
        final c = _supabase;
        if (c == null) return;
        await c.from('pitches').delete().eq('id', id);
      } catch (_) {}
      return;
    }
    AppConfig.logDb('FIREBASE DELETE pitches doc=$id');
    await _firestore.collection('pitches').doc(id).delete();
  }

  @override
  Stream<List<NewsItem>> watchNews({
    required String tournamentId,
    bool includeUnpublished = false,
  }) {
    final tId = tournamentId.trim();
    if (tId.isEmpty) return const Stream<List<NewsItem>>.empty();
    final q = _firestore
        .collection('news')
        .where('tournamentId', isEqualTo: tId)
        .orderBy('createdAt', descending: true);
    return q.snapshots().map((snap) {
      return snap.docs.map((d) {
        final data = d.data();
        final createdAt = data['createdAt'];
        DateTime? created;
        if (createdAt is Timestamp) created = createdAt.toDate();
        final isPublished = (data['isPublished'] is bool) ? data['isPublished'] as bool : true;
        return NewsItem(
          id: d.id,
          tournamentId: tId,
          content: (data['content'] ?? '').toString(),
          isPublished: isPublished,
          createdAt: created,
        );
      }).toList();
    });
  }

  @override
  Future<void> addNews({required String tournamentId, required String content}) {
    return _db.addNews(tournamentId: tournamentId, content: content);
  }

  @override
  Future<void> setNewsPublished({
    required String newsId,
    required bool isPublished,
  }) {
    return _db.setNewsPublished(newsId: newsId, isPublished: isPublished);
  }

  @override
  Future<void> updateNewsContent({
    required String newsId,
    required String content,
  }) {
    return _db.updateNewsContent(newsId: newsId, content: content);
  }

  @override
  Future<void> deleteNews({required String newsId}) {
    return _db.deleteNews(newsId: newsId);
  }

  @override
  Stream<List<Award>> watchAwardsForLeague(String leagueId) {
    return _db.getAwardsForLeague(leagueId);
  }

  @override
  Future<void> addAward({
    required String leagueId,
    required String name,
    String? description,
  }) {
    return _db.addAward(leagueId: leagueId, name: name, description: description);
  }

  @override
  Future<void> deleteAward(String awardId) {
    return _db.deleteAward(awardId);
  }

  @override
  Future<String> exportCollectionToJson(String collectionName) async {
    final name = collectionName.trim();
    if (name.isEmpty) return '[]';
    final snap = await _firestore.collection(name).get();
    final list = snap.docs.map((d) => _jsonify({...d.data(), 'id': d.id})).toList();
    return _encodeJson(list);
  }

  @override
  Future<Map<String, dynamic>> buildFirestoreBackup({
    List<String>? collections,
  }) async {
    final cols = collections ??
        <String>[
          'admins',
          'users',
          'players',
          'teams',
          'leagues',
          'groups',
          'matches',
          'news',
          'penalties',
          'pending_actions',
          'pitches',
          'otp_requests',
        ];
    final backup = <String, dynamic>{
      'exportedAt': DateTime.now().toIso8601String(),
      'collections': <String, dynamic>{},
    };

    for (final name in cols) {
      final snap = await _firestore.collection(name).get();
      final docs = <Map<String, dynamic>>[];
      for (final d in snap.docs) {
        final data = d.data();
        final json = _jsonify(data);
        docs.add({'id': d.id, ...json as Map<String, dynamic>});
      }
      (backup['collections'] as Map<String, dynamic>)[name] = docs;
    }

    return backup;
  }

  static String _encodeJson(Object? value) {
    return const JsonEncoder.withIndent('  ').convert(value);
  }

  static dynamic _jsonify(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate().toIso8601String();
    if (v is DateTime) return v.toIso8601String();
    if (v is GeoPoint) {
      return {
        '_geo': [v.latitude, v.longitude],
      };
    }
    if (v is DocumentReference) return {'_ref': v.path};
    if (v is List) return v.map(_jsonify).toList();
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), _jsonify(val)));
    }
    return v;
  }
}
