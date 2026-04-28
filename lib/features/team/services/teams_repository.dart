import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/team.dart';

class TeamsRepository {
  TeamsRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  final Map<String, List<Team>> _memByLeague = {};

  String _key(String leagueId) => 'teams_cache_v2_$leagueId';

  Future<List<Team>> getTeamsCached(String leagueId) async {
    final mem = _memByLeague[leagueId];
    if (mem != null) return mem;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(leagueId));
    if (raw != null && raw.isNotEmpty) {
      final list =
          (jsonDecode(raw) as List)
              .map((e) => Team.fromMap(e as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _memByLeague[leagueId] = list;
      return list;
    }

    final snap = await _db.collection('teams').get();
    final list =
        snap.docs
            .map((d) => Team.fromMap({...d.data(), 'id': d.id}))
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    _memByLeague[leagueId] = list;
    await prefs.setString(
      _key(leagueId),
      jsonEncode(list.map((t) => t.toMap()).toList()),
    );

    return list;
  }

  Future<Team> addTeamAndUpsertCache({
    required String leagueId,
    required String teamName,
    required String logoUrl,
    String? groupId,
    String? groupName,
  }) async {
    final trimmedName = teamName.trim();
    final trimmedLogo = logoUrl.trim();

    final ref = await _db.collection('teams').add({
      'name': trimmedName,
      'logoUrl': trimmedLogo,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final created = Team(
      id: ref.id,
      name: trimmedName,
      logoUrl: trimmedLogo,
    );

    final list = [...(_memByLeague[leagueId] ?? await getTeamsCached(leagueId))];
    final idx = list.indexWhere((t) => t.id == created.id);
    if (idx >= 0) {
      list[idx] = created;
    } else {
      list.add(created);
    }
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _memByLeague[leagueId] = list;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(leagueId),
      jsonEncode(list.map((t) => t.toMap()).toList()),
    );

    return created;
  }

  Future<void> invalidateTeams(String leagueId) async {
    _memByLeague.remove(leagueId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(leagueId));
  }
}
