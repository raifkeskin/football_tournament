import 'dart:convert';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/league.dart';
import '../models/league_extras.dart';
import '../models/match.dart';
import 'database_service.dart';
import 'interfaces/i_league_service.dart';
import '../utils/string_utils.dart';

class FirebaseLeagueService implements ILeagueService {
  FirebaseLeagueService({DatabaseService? databaseService, FirebaseFirestore? firestore})
    : _db = databaseService ?? DatabaseService(firestore: firestore),
      _firestore = firestore ?? FirebaseFirestore.instance;

  final DatabaseService _db;
  final FirebaseFirestore _firestore;

  @override
  Stream<List<League>> watchLeagues() {
    return _db.getLeagues().map((snap) {
      final list =
          snap.docs
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
      final data = snap.data() as Map<String, dynamic>? ?? <String, dynamic>{};
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
  Future<void> setDefaultLeague({required String leagueId}) =>
      _db.setDefaultLeague(leagueId: leagueId);
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
  Future<void> setGroupTeams({
    required String groupId,
    required List<String> teamIds,
  }) async {
    final gid = groupId.trim();
    if (gid.isEmpty) return;

    await _firestore.collection('groups').doc(gid).update({
      'teamIds': teamIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
    });

    final groupSnap = await _firestore.collection('groups').doc(gid).get();
    final groupName = (groupSnap.data()?['name'] ?? '').toString().trim();

    final batch = _firestore.batch();
    final oldTeams = await _firestore
        .collection('teams')
        .where('groupId', isEqualTo: gid)
        .get();
    for (final doc in oldTeams.docs) {
      batch.update(doc.reference, {'groupId': null, 'groupName': null});
    }

    for (final tId in teamIds) {
      final id = tId.trim();
      if (id.isEmpty) continue;
      batch.update(_firestore.collection('teams').doc(id), {
        'groupId': gid,
        'groupName': groupName,
      });
    }
    await batch.commit();
  }

  @override
  Future<List<String>> listPitchesOnce() async {
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
    return _firestore.collection('pitches').orderBy('nameKey').snapshots().map((snap) {
      return snap.docs
          .map((d) {
            final data = d.data();
            return Pitch(
              id: d.id,
              name: (data['name'] ?? '').toString(),
              nameKey: (data['nameKey'] ?? '').toString(),
              location: (data['location'] ?? '').toString(),
            );
          })
          .toList();
    });
  }

  @override
  Future<void> addPitch({required String name, String? location}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _firestore.collection('pitches').add({
      'name': trimmed,
      'nameKey': StringUtils.normalizeTrKey(trimmed),
      'location': (location ?? '').trim().isEmpty ? null : (location ?? '').trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> deletePitch(String pitchId) async {
    final id = pitchId.trim();
    if (id.isEmpty) return;
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
        final isPublished =
            (data['isPublished'] is bool) ? data['isPublished'] as bool : true;
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
