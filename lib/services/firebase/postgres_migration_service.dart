import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:postgres/postgres.dart';

typedef LogFn = void Function(String message);

class PostgresMigrationService {
  PostgresMigrationService({
    required FirebaseFirestore firestore,
    required Connection pg,
    LogFn? log,
    this.pageSize = 500,
    this.strict = true,
  })  : _firestore = firestore,
        _pg = pg,
        _log = log ?? ((_) {});

  final FirebaseFirestore _firestore;
  final Connection _pg;
  final LogFn _log;

  final int pageSize;
  final bool strict;

  final Map<String, String> adminFirebaseToPostgresId = {};
  final Map<String, String> appUserFirebaseToPostgresId = {};
  final Map<String, String> pitchFirebaseToPostgresId = {};
  final Map<String, String> playerFirebaseToPostgresId = {};
  final Map<String, String> leagueFirebaseToPostgresId = {};
  final Map<String, String> groupFirebaseToPostgresId = {};
  final Map<String, String> groupNameByLeaguePostgresId = {};
  final Map<String, String> teamFirebaseToPostgresId = {};
  final Map<String, String> matchFirebaseToPostgresId = {};

  Future<void> migrateAll() async {
    _log('🚀 Migration başlıyor (tek transaction)...');
    await _pg.runTx((tx) async {
      await _step1BaseTables(tx);
      await _step2Level2Tables(tx);
      await _step3PivotsFromPlayers(tx);
      await _step4AppUsers(tx);
      await _step5Matches(tx);
      await _step6MatchRosters(tx);
      await _step7Events(tx);
    });
    _log('✅ Migration tamamlandı.');
  }

  Future<void> _step1BaseTables(Session tx) async {
    _log('➡️ Step 1: admins, pitches, players(core), leagues');
    await _migrateAdmins(tx);
    await _migratePitches(tx);
    await _migratePlayersCore(tx);
    await _migrateLeagues(tx);
  }

  Future<void> _step2Level2Tables(Session tx) async {
    _log('➡️ Step 2: groups(league_id), teams(manager_id)');
    await _migrateGroups(tx);
    await _migrateTeams(tx);
  }

  Future<void> _step3PivotsFromPlayers(Session tx) async {
    _log('➡️ Step 3: league_registrations, league_team_players, player_league_stats');
    await _migratePlayerRelationalData(tx);
  }

  Future<void> _step4AppUsers(Session tx) async {
    _log('➡️ Step 4: app_users (team_id resolve)');
    await _migrateAppUsers(tx);
  }

  Future<void> _step5Matches(Session tx) async {
    _log('➡️ Step 5: matches (league_id, home/away_team_id, pitch_id resolve)');
    await _migrateMatches(tx);
  }

  Future<void> _step6MatchRosters(Session tx) async {
    _log('➡️ Step 6: match_rosters (matches içindeki lineup/roster alanlarından)');
    await _migrateMatchRostersFromMatches(tx);
  }

  Future<void> _step7Events(Session tx) async {
    _log('➡️ Step 7: match_events (events / match_events koleksiyonlarından)');
    await _migrateMatchEvents(tx);
  }

  // -------------------------
  // Firestore yardımcıları
  // -------------------------

  Stream<QueryDocumentSnapshot<Map<String, dynamic>>> _streamAllDocs(String collectionName) async* {
    final col = _firestore.collection(collectionName);
    DocumentSnapshot<Map<String, dynamic>>? last;

    while (true) {
      Query<Map<String, dynamic>> q = col.orderBy(FieldPath.documentId).limit(pageSize);
      if (last != null) q = q.startAfterDocument(last);

      final snap = await q.get();
      if (snap.docs.isEmpty) break;

      for (final d in snap.docs) {
        yield d;
      }
      last = snap.docs.last;
    }
  }

  Future<bool> _hasAnyDoc(String collectionName) async {
    try {
      final snap = await _firestore.collection(collectionName).limit(1).get();
      return snap.docs.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // -------------------------
  // Genel parse yardımcıları
  // -------------------------

  String _s(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  String? _sN(Map<String, dynamic> m, List<String> keys) {
    final v = _s(m, keys);
    return v.isEmpty ? null : v;
  }

  bool _b(Map<String, dynamic> m, List<String> keys, {bool fallback = false}) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is bool) return v;
      if (v is num) return v != 0;
      final s = v.toString().trim().toLowerCase();
      if (s == 'true' || s == '1' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'no') return false;
    }
    return fallback;
  }

  String _groupNameKey(String leagueId, String groupName) {
    return '${leagueId.trim()}|${groupName.trim().toLowerCase()}';
  }

  int? _iN(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is int) return v;
      if (v is num) return v.toInt();
      final s = v.toString().trim();
      final parsed = int.tryParse(s) ?? double.tryParse(s.replaceAll(',', '.'))?.toInt();
      if (parsed != null) return parsed;
    }
    return null;
  }

  DateTime? _dt(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      if (v is String) {
        final t = DateTime.tryParse(v.trim());
        if (t != null) return t;
      }
    }
    return null;
  }

  int? _birthYearFromBirthDate(String? birthDate) {
    final s = (birthDate ?? '').trim();
    if (s.isEmpty) return null;
    final m = RegExp(r'(19\d{2}|20\d{2}|2100)$').firstMatch(s);
    if (m != null) return int.tryParse(m.group(1)!);
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso.year;
    return null;
  }

  Future<String> _insertReturningUuid(
    Session tx, {
    required String sqlNamed,
    required Map<String, dynamic> params,
  }) async {
    final res = await tx.execute(Sql.named(sqlNamed), parameters: params);
    if (res.isEmpty) {
      throw Exception('INSERT RETURNING id boş döndü. SQL=$sqlNamed');
    }
    return res.first[0].toString();
  }

  String _requireMapped(
    Map<String, String> map,
    String firebaseId, {
    required String entityName,
    required String fieldName,
  }) {
    final key = firebaseId.trim();
    final v = map[key];
    if (v != null && v.trim().isNotEmpty) return v;
    final msg = 'FK çözülemedi: $entityName.$fieldName firebase="$firebaseId"';
    if (strict) throw Exception(msg);
    _log('⚠️ $msg (skip)');
    return '';
  }

  // -------------------------
  // Step 1: admins
  // -------------------------

  Future<void> _migrateAdmins(Session tx) async {
    if (!await _hasAnyDoc('admins')) {
      _log('ℹ️ admins koleksiyonu boş/erişilemedi, atlanıyor.');
      return;
    }

    var n = 0;
    await for (final doc in _streamAllDocs('admins')) {
      final data = doc.data();
      final firebaseId = doc.id.trim();

      final uid = _sN(data, const ['uid', 'authUid']);
      final email = _sN(data, const ['email']);
      final phone = _sN(data, const ['phone', 'phoneRaw10', 'phone_raw10']);
      final name = _sN(data, const ['name', 'fullName', 'managerFullName']);

      final id = await _insertReturningUuid(
        tx,
        sqlNamed: r'''
INSERT INTO admins (firebase_id, uid, email, phone, name)
VALUES (@firebase_id, @uid, @email, @phone, @name)
RETURNING id
''',
        params: {
          'firebase_id': firebaseId,
          'uid': uid,
          'email': email,
          'phone': phone,
          'name': name,
        },
      );

      adminFirebaseToPostgresId[firebaseId] = id;
      n++;
    }
    _log('✅ admins taşındı: $n');
  }

  // -------------------------
  // Step 1: pitches
  // -------------------------

  Future<void> _migratePitches(Session tx) async {
    if (!await _hasAnyDoc('pitches')) {
      _log('ℹ️ pitches koleksiyonu boş/erişilemedi, atlanıyor.');
      return;
    }

    var n = 0;
    await for (final doc in _streamAllDocs('pitches')) {
      final data = doc.data();
      final firebaseId = doc.id.trim();

      final name = _s(data, const ['name']);
      final nameKey = _sN(data, const ['nameKey', 'name_key']);
      final location = _sN(data, const ['location']);

      final createdAt = _dt(data, const ['createdAt', 'created_at']);
      final updatedAt = _dt(data, const ['updatedAt', 'updated_at']);

      final id = await _insertReturningUuid(
        tx,
        sqlNamed: r'''
INSERT INTO pitches (firebase_id, name, name_key, location, created_at, updated_at)
VALUES (@firebase_id, @name, @name_key, @location, @created_at, @updated_at)
RETURNING id
''',
        params: {
          'firebase_id': firebaseId,
          'name': name,
          'name_key': nameKey,
          'location': location,
          'created_at': createdAt,
          'updated_at': updatedAt,
        },
      );

      pitchFirebaseToPostgresId[firebaseId] = id;
      n++;
    }
    _log('✅ pitches taşındı: $n');
  }

  // -------------------------
  // Step 1: players (core)
  // -------------------------

  Future<void> _migratePlayersCore(Session tx) async {
    if (!await _hasAnyDoc('players')) {
      _log('ℹ️ players koleksiyonu boş/erişilemedi, atlanıyor.');
      return;
    }

    var n = 0;
    await for (final doc in _streamAllDocs('players')) {
      final data = doc.data();
      final firebaseId = doc.id.trim();

      final phone = _sN(data, const ['phone', 'phoneRaw10', 'phone_raw10']);
      final name = _s(data, const ['name', 'playerName', 'player_name']);
      final birthDate = _sN(data, const ['birthDate', 'birth_date']);
      final birthYear = _iN(data, const ['birthYear', 'birth_year']) ?? _birthYearFromBirthDate(birthDate);
      final mainPosition = _sN(data, const ['mainPosition', 'main_position']);
      final position = _sN(data, const ['position']);
      final preferredFoot = _sN(data, const ['preferredFoot', 'preferred_foot']);
      final photoUrl = _sN(data, const ['photoUrl', 'photo_url']);
      final authUid = _sN(data, const ['authUid', 'auth_uid', 'uid']);

      final createdAt = _dt(data, const ['createdAt', 'created_at']);
      final updatedAt = _dt(data, const ['updatedAt', 'updated_at']);

      final id = await _insertReturningUuid(
        tx,
        sqlNamed: r'''
INSERT INTO players (
  firebase_id, phone, name, birth_date, birth_year,
  main_position, position, preferred_foot, photo_url, auth_uid,
  created_at, updated_at
)
VALUES (
  @firebase_id, @phone, @name, @birth_date, @birth_year,
  @main_position, @position, @preferred_foot, @photo_url, @auth_uid,
  @created_at, @updated_at
)
RETURNING id
''',
        params: {
          'firebase_id': firebaseId,
          'phone': phone,
          'name': name,
          'birth_date': birthDate,
          'birth_year': birthYear,
          'main_position': mainPosition,
          'position': position,
          'preferred_foot': preferredFoot,
          'photo_url': photoUrl,
          'auth_uid': authUid,
          'created_at': createdAt,
          'updated_at': updatedAt,
        },
      );

      playerFirebaseToPostgresId[firebaseId] = id;

      // Firestore’da player docId genelde telefon olduğu için alias map’leme:
      final phoneKey = (phone ?? '').trim();
      if (phoneKey.isNotEmpty) {
        playerFirebaseToPostgresId.putIfAbsent(phoneKey, () => id);
      }

      n++;
    }
    _log('✅ players(core) taşındı: $n');
  }

  // -------------------------
  // Step 1: leagues
  // -------------------------

  Future<void> _migrateLeagues(Session tx) async {
    if (!await _hasAnyDoc('leagues')) {
      _log('ℹ️ leagues koleksiyonu boş/erişilemedi, atlanıyor.');
      return;
    }

    var n = 0;
    await for (final doc in _streamAllDocs('leagues')) {
      final data = doc.data();
      final firebaseId = doc.id.trim();

      final name = _s(data, const ['name']);
      final subtitle = _sN(data, const ['subtitle']);
      final logoUrl = _sN(data, const ['logoUrl', 'logo_url', 'logo']);
      final country = _sN(data, const ['country']);

      final managerFullName = _sN(data, const ['managerFullName', 'manager_full_name', 'managerName']);
      final managerPhoneRaw10 = _sN(data, const ['managerPhoneRaw10', 'manager_phone_raw10', 'managerPhone']);

      final startDate = _dt(data, const ['startDate', 'start_date']);
      final endDate = _dt(data, const ['endDate', 'end_date']);
      final season = _sN(data, const ['season']);

      final isActive = _b(data, const ['isActive', 'is_active'], fallback: true);
      final isDefault = _b(data, const ['isDefault', 'is_default'], fallback: false);
      final isPrivate = _b(data, const ['isPrivate', 'is_private'], fallback: false);
      final accessCode = _sN(data, const ['accessCode', 'access_code']);

      final transferStartDate = _dt(data, const ['transferStartDate', 'transfer_start_date']);
      final transferEndDate = _dt(data, const ['transferEndDate', 'transfer_end_date']);

      final youtubeUrl = _sN(data, const ['youtubeUrl', 'youtube_url']);
      final instagramUrl = _sN(data, const ['instagramUrl', 'instagram_url']);

      final matchPeriodDuration = _iN(data, const ['matchPeriodDuration', 'match_period_duration']) ?? 25;
      final numberOfGroups = _iN(data, const ['numberOfGroups', 'number_of_groups']) ?? 1;
      final teamsPerGroup = _iN(data, const ['teamsPerGroup', 'teams_per_group']) ?? 4;

      final createdAt = _dt(data, const ['createdAt', 'created_at']);
      final updatedAt = _dt(data, const ['updatedAt', 'updated_at']);

      final id = await _insertReturningUuid(
        tx,
        sqlNamed: r'''
INSERT INTO leagues (
  firebase_id, name, subtitle, logo_url, country,
  manager_full_name, manager_phone_raw10,
  start_date, end_date, season,
  is_active, is_default, is_private, access_code,
  transfer_start_date, transfer_end_date,
  youtube_url, instagram_url,
  match_period_duration, number_of_groups, teams_per_group,
  created_at, updated_at
)
VALUES (
  @firebase_id, @name, @subtitle, @logo_url, @country,
  @manager_full_name, @manager_phone_raw10,
  @start_date, @end_date, @season,
  @is_active, @is_default, @is_private, @access_code,
  @transfer_start_date, @transfer_end_date,
  @youtube_url, @instagram_url,
  @match_period_duration, @number_of_groups, @teams_per_group,
  @created_at, @updated_at
)
RETURNING id
''',
        params: {
          'firebase_id': firebaseId,
          'name': name,
          'subtitle': subtitle,
          'logo_url': logoUrl,
          'country': country,
          'manager_full_name': managerFullName,
          'manager_phone_raw10': managerPhoneRaw10,
          'start_date': startDate,
          'end_date': endDate,
          'season': season,
          'is_active': isActive,
          'is_default': isDefault,
          'is_private': isPrivate,
          'access_code': accessCode,
          'transfer_start_date': transferStartDate,
          'transfer_end_date': transferEndDate,
          'youtube_url': youtubeUrl,
          'instagram_url': instagramUrl,
          'match_period_duration': matchPeriodDuration,
          'number_of_groups': numberOfGroups,
          'teams_per_group': teamsPerGroup,
          'created_at': createdAt,
          'updated_at': updatedAt,
        },
      );

      leagueFirebaseToPostgresId[firebaseId] = id;
      n++;
    }

    _log('✅ leagues taşındı: $n');
  }

  // -------------------------
  // Step 2: groups
  // -------------------------

  Future<void> _migrateGroups(Session tx) async {
    if (!await _hasAnyDoc('groups')) {
      _log('ℹ️ groups koleksiyonu boş/erişilemedi, atlanıyor.');
      return;
    }

    var n = 0;
    await for (final doc in _streamAllDocs('groups')) {
      final data = doc.data();
      final firebaseId = doc.id.trim();

      final leagueFirebaseId = _s(data, const ['leagueId', 'league_id', 'tournamentId', 'tournament_id']);
      final leagueId = _requireMapped(
        leagueFirebaseToPostgresId,
        leagueFirebaseId,
        entityName: 'groups',
        fieldName: 'league_id',
      );
      if (leagueId.isEmpty) continue;

      final name = _s(data, const ['name']);

      final createdAt = _dt(data, const ['createdAt', 'created_at']);
      final updatedAt = _dt(data, const ['updatedAt', 'updated_at']);

      final id = await _insertReturningUuid(
        tx,
        sqlNamed: r'''
INSERT INTO groups (firebase_id, league_id, name, created_at, updated_at)
VALUES (@firebase_id, @league_id, @name, @created_at, @updated_at)
RETURNING id
''',
        params: {
          'firebase_id': firebaseId,
          'league_id': leagueId,
          'name': name,
          'created_at': createdAt,
          'updated_at': updatedAt,
        },
      );

      groupFirebaseToPostgresId[firebaseId] = id;
      n++;
    }

    _log('✅ groups taşındı: $n');
  }

  // -------------------------
  // Step 2: teams
  // -------------------------

  Future<void> _migrateTeams(Session tx) async {
    if (!await _hasAnyDoc('teams')) {
      _log('ℹ️ teams koleksiyonu boş/erişilemedi, atlanıyor.');
      return;
    }

    var n = 0;
    await for (final doc in _streamAllDocs('teams')) {
      final data = doc.data();
      final firebaseId = doc.id.trim();

      final leagueFirebaseId = _s(data, const ['leagueId', 'league_id', 'tournamentId', 'tournament_id']);
      final leagueId = leagueFirebaseId.isEmpty
          ? null
          : _requireMapped(
              leagueFirebaseToPostgresId,
              leagueFirebaseId,
              entityName: 'teams',
              fieldName: 'league_id',
            );
      if ((leagueFirebaseId.isNotEmpty) && (leagueId ?? '').isEmpty) {
        if (strict) throw Exception('teams.league_id çözülemedi: $firebaseId -> $leagueFirebaseId');
        continue;
      }

      final groupFirebaseId = _sN(data, const ['groupId', 'group_id']);
      final groupId = (groupFirebaseId ?? '').trim().isEmpty
          ? null
          : _requireMapped(
              groupFirebaseToPostgresId,
              groupFirebaseId!,
              entityName: 'teams',
              fieldName: 'group_id',
            );

      final name = _s(data, const ['name']);
      final logoUrl = _sN(data, const ['logoUrl', 'logo_url', 'logo']);
      final groupName = _sN(data, const ['groupName', 'group_name']);

      final colors = data['colors'];
      final colorsJson = (colors is Map || colors is List) ? jsonEncode(colors) : null;

      // manager_id çözümü: Takım sorumlusu roster kaydından türet (en sağlam kaynak)
      String? managerId;
      try {
        final resolvedLeagueIdForRoster = (leagueFirebaseId.isNotEmpty) ? leagueFirebaseId : null;
        if (resolvedLeagueIdForRoster != null) {
          final rosterSnap = await _firestore
              .collection('rosters')
              .where('teamId', isEqualTo: firebaseId)
              .where('tournamentId', isEqualTo: resolvedLeagueIdForRoster)
              .get();

          for (final r in rosterSnap.docs) {
            final rd = r.data();
            final role = (rd['role'] ?? '').toString().trim();
            final isManager = role == 'Takım Sorumlusu' || role == 'Her İkisi';
            if (!isManager) continue;
            final phone = (rd['playerPhone'] ?? '').toString().trim();
            if (phone.isEmpty) continue;
            final pid = playerFirebaseToPostgresId[phone] ?? playerFirebaseToPostgresId[r.id];
            if (pid != null && pid.trim().isNotEmpty) {
              managerId = pid;
              break;
            }
          }
        }
      } catch (_) {}

      final createdAt = _dt(data, const ['createdAt', 'created_at']);
      final updatedAt = _dt(data, const ['updatedAt', 'updated_at']);

      final id = await _insertReturningUuid(
        tx,
        sqlNamed: r'''
INSERT INTO teams (
  firebase_id, league_id, group_id, name, logo_url, group_name, colors_json, manager_id, created_at, updated_at
)
VALUES (
  @firebase_id, @league_id, @group_id, @name, @logo_url, @group_name, @colors_json, @manager_id, @created_at, @updated_at
)
RETURNING id
''',
        params: {
          'firebase_id': firebaseId,
          'league_id': leagueId,
          'group_id': (groupId ?? '').trim().isEmpty ? null : groupId,
          'name': name,
          'logo_url': logoUrl,
          'group_name': groupName,
          'colors_json': colorsJson,
          'manager_id': managerId,
          'created_at': createdAt,
          'updated_at': updatedAt,
        },
      );

      teamFirebaseToPostgresId[firebaseId] = id;
      n++;
    }

    _log('✅ teams taşındı: $n');
  }

  // -------------------------
  // Step 3: player pivot verileri
  // -------------------------

  Future<void> _migratePlayerRelationalData(Session tx) async {
    if (!await _hasAnyDoc('players')) return;

    var nReg = 0;
    var nLink = 0;
    var nStats = 0;

    await for (final doc in _streamAllDocs('players')) {
      final data = doc.data();
      final playerFirebaseId = doc.id.trim();
      final playerId = _requireMapped(
        playerFirebaseToPostgresId,
        playerFirebaseId,
        entityName: 'players',
        fieldName: 'id',
      );
      if (playerId.isEmpty) continue;

      final memberships = <Map<String, dynamic>>[];

      // Olası tekil üyelik alanları (legacy)
      final singleTeamId = _sN(data, const ['teamId', 'team_id']);
      final singleLeagueId = _sN(data, const ['leagueId', 'league_id', 'tournamentId', 'tournament_id']);
      if ((singleTeamId ?? '').trim().isNotEmpty || (singleLeagueId ?? '').trim().isNotEmpty) {
        memberships.add({
          'leagueId': (singleLeagueId ?? '').trim(),
          'teamId': (singleTeamId ?? '').trim(),
          'role': _sN(data, const ['role']),
        });
      }

      // Olası çoklu üyelik listeleri
      final teamsRaw = data['teams'];
      if (teamsRaw is List) {
        for (final e in teamsRaw) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          memberships.add({
            'leagueId': _s(m, const ['leagueId', 'league_id', 'tournamentId', 'tournament_id']),
            'teamId': _s(m, const ['teamId', 'team_id']),
            'role': _sN(m, const ['role']),
          });
        }
      }

      final leaguesRaw = data['leagues'];
      if (leaguesRaw is List) {
        for (final e in leaguesRaw) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          memberships.add({
            'leagueId': _s(m, const ['leagueId', 'league_id', 'tournamentId', 'tournament_id', 'id']),
            'teamId': _s(m, const ['teamId', 'team_id']),
            'role': _sN(m, const ['role']),
          });
        }
      }

      // Kayıt/registration
      for (final mem in memberships) {
        final leagueFirebaseId = (mem['leagueId'] ?? '').toString().trim();
        if (leagueFirebaseId.isEmpty) continue;

        final leagueId = _requireMapped(
          leagueFirebaseToPostgresId,
          leagueFirebaseId,
          entityName: 'league_registrations',
          fieldName: 'league_id',
        );
        if (leagueId.isEmpty) continue;

        final role = (mem['role'] ?? '').toString().trim();
        final resolvedRole = role.isEmpty ? null : role;

        await tx.execute(
          Sql.named(r'''
INSERT INTO league_registrations (league_id, player_id, role)
VALUES (@league_id, @player_id, @role)
'''),
          parameters: {
            'league_id': leagueId,
            'player_id': playerId,
            'role': resolvedRole,
          },
        );
        nReg++;

        final teamFirebaseId = (mem['teamId'] ?? '').toString().trim();
        if (teamFirebaseId.isNotEmpty) {
          final teamId = _requireMapped(
            teamFirebaseToPostgresId,
            teamFirebaseId,
            entityName: 'league_team_players',
            fieldName: 'team_id',
          );
          if (teamId.isNotEmpty) {
            await tx.execute(
              Sql.named(r'''
INSERT INTO league_team_players (league_id, team_id, player_id, role)
VALUES (@league_id, @team_id, @player_id, @role)
'''),
              parameters: {
                'league_id': leagueId,
                'team_id': teamId,
                'player_id': playerId,
                'role': resolvedRole,
              },
            );
            nLink++;
          }
        }
      }

      // Stats: farklı şekiller için toleranslı okuma
      final leagueStatsRaw = data['leagueStats'] ?? data['playerStats'] ?? data['stats'];
      if (leagueStatsRaw is Map) {
        for (final entry in leagueStatsRaw.entries) {
          final leagueFirebaseId = entry.key.toString().trim();
          if (leagueFirebaseId.isEmpty) continue;

          final leagueId = leagueFirebaseToPostgresId[leagueFirebaseId];
          if ((leagueId ?? '').trim().isEmpty) {
            if (strict) throw Exception('player_league_stats league_id çözülemedi: $leagueFirebaseId');
            continue;
          }

          final statsVal = entry.value;
          final statsJson = (statsVal is Map || statsVal is List) ? jsonEncode(statsVal) : jsonEncode({'value': statsVal});

          await tx.execute(
            Sql.named(r'''
INSERT INTO player_league_stats (league_id, player_id, stats_json)
VALUES (@league_id, @player_id, @stats_json)
'''),
            parameters: {
              'league_id': leagueId,
              'player_id': playerId,
              'stats_json': statsJson,
            },
          );
          nStats++;
        }
      }
    }

    _log('✅ league_registrations: $nReg, league_team_players: $nLink, player_league_stats: $nStats');
  }

  // -------------------------
  // Step 4: app_users
  // -------------------------

  Future<void> _migrateAppUsers(Session tx) async {
    final hasAppUsers = await _hasAnyDoc('app_users');
    final hasUsers = await _hasAnyDoc('users');

    final collection = hasAppUsers ? 'app_users' : (hasUsers ? 'users' : null);
    if (collection == null) {
      _log('ℹ️ app_users/users koleksiyonu bulunamadı, atlanıyor.');
      return;
    }

    var n = 0;
    await for (final doc in _streamAllDocs(collection)) {
      final data = doc.data();
      final firebaseId = doc.id.trim();

      final authUid = _sN(data, const ['uid', 'authUid', 'auth_uid', 'firebaseUid']);
      final phone = _sN(data, const ['phone', 'phoneRaw10', 'phone_raw10']);
      final name = _sN(data, const ['name', 'fullName']);
      final email = _sN(data, const ['email']);

      final teamFirebaseId = _sN(data, const ['teamId', 'team_id']);
      final teamId = (teamFirebaseId ?? '').trim().isEmpty
          ? null
          : _requireMapped(teamFirebaseToPostgresId, teamFirebaseId!, entityName: 'app_users', fieldName: 'team_id');

      final createdAt = _dt(data, const ['createdAt', 'created_at']);
      final updatedAt = _dt(data, const ['updatedAt', 'updated_at']);

      final id = await _insertReturningUuid(
        tx,
        sqlNamed: r'''
INSERT INTO app_users (firebase_id, auth_uid, phone, name, email, team_id, created_at, updated_at)
VALUES (@firebase_id, @auth_uid, @phone, @name, @email, @team_id, @created_at, @updated_at)
RETURNING id
''',
        params: {
          'firebase_id': firebaseId,
          'auth_uid': authUid,
          'phone': phone,
          'name': name,
          'email': email,
          'team_id': (teamId ?? '').trim().isEmpty ? null : teamId,
          'created_at': createdAt,
          'updated_at': updatedAt,
        },
      );

      appUserFirebaseToPostgresId[firebaseId] = id;
      n++;
    }

    _log('✅ app_users taşındı: $n (koleksiyon: $collection)');
  }

  // -------------------------
  // Step 5: matches
  // -------------------------

  Future<void> _migrateMatches(Session tx) async {
    if (!await _hasAnyDoc('matches')) {
      _log('ℹ️ matches koleksiyonu boş/erişilemedi, atlanıyor.');
      return;
    }

    var n = 0;
    await for (final doc in _streamAllDocs('matches')) {
      final data = doc.data();
      final firebaseId = doc.id.trim();

      final leagueFirebaseId = _s(data, const ['leagueId', 'league_id', 'tournamentId', 'tournament_id']);
      final leagueId = _requireMapped(
        leagueFirebaseToPostgresId,
        leagueFirebaseId,
        entityName: 'matches',
        fieldName: 'league_id',
      );
      if (leagueId.isEmpty) continue;

      final homeTeamFirebaseId = _s(data, const ['homeTeamId', 'home_team_id']);
      final awayTeamFirebaseId = _s(data, const ['awayTeamId', 'away_team_id']);
      final homeTeamId = _requireMapped(teamFirebaseToPostgresId, homeTeamFirebaseId, entityName: 'matches', fieldName: 'home_team_id');
      final awayTeamId = _requireMapped(teamFirebaseToPostgresId, awayTeamFirebaseId, entityName: 'matches', fieldName: 'away_team_id');
      if (homeTeamId.isEmpty || awayTeamId.isEmpty) continue;

      final pitchFirebaseId = _sN(data, const ['pitchId', 'pitch_id']);
      final pitchId = (pitchFirebaseId ?? '').trim().isEmpty
          ? null
          : _requireMapped(pitchFirebaseToPostgresId, pitchFirebaseId!, entityName: 'matches', fieldName: 'pitch_id');

      final groupFirebaseOrName = _sN(data, const ['groupId', 'group_id']);
      String? groupId;
      if ((groupFirebaseOrName ?? '').trim().isNotEmpty) {
        final raw = groupFirebaseOrName!.trim();
        groupId = groupFirebaseToPostgresId[raw];
        groupId ??= groupNameByLeaguePostgresId[_groupNameKey(leagueId, raw)];
        if ((groupId ?? '').trim().isEmpty) {
          final res = await tx.execute(
            Sql.named(r'''
SELECT id
FROM groups
WHERE league_id = @league_id
  AND lower(name) = lower(@name)
LIMIT 1
'''),
            parameters: {
              'league_id': leagueId,
              'name': raw,
            },
          );
          if (res.isNotEmpty) {
            groupId = (res.first[0] ?? '').toString().trim();
            final found = groupId;
            if (found.isNotEmpty) {
              groupNameByLeaguePostgresId[_groupNameKey(leagueId, raw)] = found;
            }
          }
        }
        if ((groupId ?? '').trim().isEmpty) {
          final msg = 'FK çözülemedi: matches.group_id firebase="$raw"';
          if (strict) throw Exception(msg);
          _log('⚠️ $msg (group_id null yazılacak)');
          groupId = null;
        }
      }

      final week = _iN(data, const ['week']);
      final status = _sN(data, const ['status']);
      final minute = _iN(data, const ['minute']);

      final matchDate = _sN(data, const ['matchDate', 'match_date', 'dateString', 'date_string']);
      final matchTime = _sN(data, const ['matchTime', 'match_time', 'time']);

      final homeScore = _iN(data, const ['homeScore', 'home_score']) ?? 0;
      final awayScore = _iN(data, const ['awayScore', 'away_score']) ?? 0;

      final pitchName = _sN(data, const ['pitchName', 'pitch_name']);
      final youtubeUrl = _sN(data, const ['youtubeUrl', 'youtube_url']);
      final homeHighlightPhotoUrl = _sN(data, const ['homeHighlightPhotoUrl', 'home_highlight_photo_url']);
      final awayHighlightPhotoUrl = _sN(data, const ['awayHighlightPhotoUrl', 'away_highlight_photo_url']);

      final scoreRaw = data['score'];
      final scoreJson = (scoreRaw is Map || scoreRaw is List) ? jsonEncode(scoreRaw) : null;

      final createdAt = _dt(data, const ['createdAt', 'created_at']);
      final updatedAt = _dt(data, const ['updatedAt', 'updated_at']);

      final id = await _insertReturningUuid(
        tx,
        sqlNamed: r'''
INSERT INTO matches (
  firebase_id, league_id, group_id,
  home_team_id, away_team_id,
  pitch_id, pitch_name,
  week, match_date, match_time,
  status, minute,
  home_score, away_score,
  youtube_url, home_highlight_photo_url, away_highlight_photo_url,
  score_json,
  created_at, updated_at
)
VALUES (
  @firebase_id, @league_id, @group_id,
  @home_team_id, @away_team_id,
  @pitch_id, @pitch_name,
  @week, @match_date, @match_time,
  @status, @minute,
  @home_score, @away_score,
  @youtube_url, @home_highlight_photo_url, @away_highlight_photo_url,
  @score_json,
  @created_at, @updated_at
)
RETURNING id
''',
        params: {
          'firebase_id': firebaseId,
          'league_id': leagueId,
          'group_id': (groupId ?? '').trim().isEmpty ? null : groupId,
          'home_team_id': homeTeamId,
          'away_team_id': awayTeamId,
          'pitch_id': (pitchId ?? '').trim().isEmpty ? null : pitchId,
          'pitch_name': pitchName,
          'week': week,
          'match_date': matchDate,
          'match_time': matchTime,
          'status': status,
          'minute': minute,
          'home_score': homeScore,
          'away_score': awayScore,
          'youtube_url': youtubeUrl,
          'home_highlight_photo_url': homeHighlightPhotoUrl,
          'away_highlight_photo_url': awayHighlightPhotoUrl,
          'score_json': scoreJson,
          'created_at': createdAt,
          'updated_at': updatedAt,
        },
      );

      matchFirebaseToPostgresId[firebaseId] = id;
      n++;
    }

    _log('✅ matches taşındı: $n');
  }

  // -------------------------
  // Step 6: match_rosters
  // -------------------------

  Future<void> _migrateMatchRostersFromMatches(Session tx) async {
    if (!await _hasAnyDoc('matches')) return;

    var n = 0;
    await for (final doc in _streamAllDocs('matches')) {
      final data = doc.data();
      final matchFirebaseId = doc.id.trim();
      final matchId = _requireMapped(matchFirebaseToPostgresId, matchFirebaseId, entityName: 'match_rosters', fieldName: 'match_id');
      if (matchId.isEmpty) continue;

      final leagueFirebaseId = _s(data, const ['leagueId', 'league_id', 'tournamentId', 'tournament_id']);
      final leagueId = _requireMapped(leagueFirebaseToPostgresId, leagueFirebaseId, entityName: 'match_rosters', fieldName: 'league_id');
      if (leagueId.isEmpty) continue;

      final homeTeamFirebaseId = _s(data, const ['homeTeamId', 'home_team_id']);
      final awayTeamFirebaseId = _s(data, const ['awayTeamId', 'away_team_id']);
      final homeTeamId = _requireMapped(teamFirebaseToPostgresId, homeTeamFirebaseId, entityName: 'match_rosters', fieldName: 'team_id');
      final awayTeamId = _requireMapped(teamFirebaseToPostgresId, awayTeamFirebaseId, entityName: 'match_rosters', fieldName: 'team_id');
      if (homeTeamId.isEmpty || awayTeamId.isEmpty) continue;

      Future<void> insertSide({
        required bool isHome,
        required String teamId,
        required dynamic lineupDetail,
        required dynamic lineupFlat,
      }) async {
        // 1) Detaylı lineup: { starting: [{playerId,name,number}], subs:[...] }
        if (lineupDetail is Map) {
          final m = Map<String, dynamic>.from(lineupDetail);
          final starting = (m['starting'] is List) ? (m['starting'] as List) : const [];
          final subs = (m['subs'] is List) ? (m['subs'] as List) : const [];

          for (final e in starting) {
            if (e is! Map) continue;
            final row = Map<String, dynamic>.from(e);
            final playerKey = (row['playerId'] ?? row['player_phone'] ?? row['phone'] ?? '').toString().trim();
            if (playerKey.isEmpty) continue;

            final playerId = playerFirebaseToPostgresId[playerKey];
            if ((playerId ?? '').trim().isEmpty) {
              if (strict) throw Exception('match_rosters player_id çözülemedi: $playerKey');
              continue;
            }

            final jerseyNumber = (row['number'] ?? '').toString().trim();
            await tx.execute(
              Sql.named(r'''
INSERT INTO match_rosters (
  match_id, league_id, team_id, player_id,
  is_home, is_starting, jersey_number,
  pos_x, pos_y
)
VALUES (
  @match_id, @league_id, @team_id, @player_id,
  @is_home, @is_starting, @jersey_number,
  @pos_x, @pos_y
)
'''),
              parameters: {
                'match_id': matchId,
                'league_id': leagueId,
                'team_id': teamId,
                'player_id': playerId,
                'is_home': isHome,
                'is_starting': true,
                'jersey_number': jerseyNumber.isEmpty ? null : jerseyNumber,
                'pos_x': row['pos_x'] ?? row['posX'],
                'pos_y': row['pos_y'] ?? row['posY'],
              },
            );
            n++;
          }

          for (final e in subs) {
            if (e is! Map) continue;
            final row = Map<String, dynamic>.from(e);
            final playerKey = (row['playerId'] ?? row['player_phone'] ?? row['phone'] ?? '').toString().trim();
            if (playerKey.isEmpty) continue;

            final playerId = playerFirebaseToPostgresId[playerKey];
            if ((playerId ?? '').trim().isEmpty) {
              if (strict) throw Exception('match_rosters player_id çözülemedi: $playerKey');
              continue;
            }

            final jerseyNumber = (row['number'] ?? '').toString().trim();
            await tx.execute(
              Sql.named(r'''
INSERT INTO match_rosters (
  match_id, league_id, team_id, player_id,
  is_home, is_starting, jersey_number,
  pos_x, pos_y
)
VALUES (
  @match_id, @league_id, @team_id, @player_id,
  @is_home, @is_starting, @jersey_number,
  @pos_x, @pos_y
)
'''),
              parameters: {
                'match_id': matchId,
                'league_id': leagueId,
                'team_id': teamId,
                'player_id': playerId,
                'is_home': isHome,
                'is_starting': false,
                'jersey_number': jerseyNumber.isEmpty ? null : jerseyNumber,
                'pos_x': row['pos_x'] ?? row['posX'],
                'pos_y': row['pos_y'] ?? row['posY'],
              },
            );
            n++;
          }

          return;
        }

        // 2) Düz lineup listesi: ["phone1","phone2",...]
        if (lineupFlat is List) {
          for (final e in lineupFlat) {
            final playerKey = e.toString().trim();
            if (playerKey.isEmpty) continue;
            final playerId = playerFirebaseToPostgresId[playerKey];
            if ((playerId ?? '').trim().isEmpty) {
              if (strict) throw Exception('match_rosters player_id çözülemedi: $playerKey');
              continue;
            }

            await tx.execute(
              Sql.named(r'''
INSERT INTO match_rosters (
  match_id, league_id, team_id, player_id,
  is_home, is_starting
)
VALUES (
  @match_id, @league_id, @team_id, @player_id,
  @is_home, @is_starting
)
'''),
              parameters: {
                'match_id': matchId,
                'league_id': leagueId,
                'team_id': teamId,
                'player_id': playerId,
                'is_home': isHome,
                'is_starting': null, // düz listede başlangıç/yedek ayrımı yoksa null
              },
            );
            n++;
          }
        }
      }

      await insertSide(
        isHome: true,
        teamId: homeTeamId,
        lineupDetail: data['homeLineupDetail'] ?? data['home_lineup_detail'],
        lineupFlat: data['homeLineup'] ?? data['home_lineup'],
      );

      await insertSide(
        isHome: false,
        teamId: awayTeamId,
        lineupDetail: data['awayLineupDetail'] ?? data['away_lineup_detail'],
        lineupFlat: data['awayLineup'] ?? data['away_lineup'],
      );
    }

    _log('✅ match_rosters taşındı: $n');
  }

  // -------------------------
  // Step 7: match_events
  // -------------------------

  Future<void> _migrateMatchEvents(Session tx) async {
    final hasEvents = await _hasAnyDoc('events');
    final hasMatchEvents = await _hasAnyDoc('match_events');

    final collections = <String>[
      if (hasEvents) 'events',
      if (hasMatchEvents) 'match_events',
    ];

    if (collections.isEmpty) {
      _log('ℹ️ events/match_events koleksiyonu bulunamadı, atlanıyor.');
      return;
    }

    var n = 0;

    for (final colName in collections) {
      await for (final doc in _streamAllDocs(colName)) {
        final data = doc.data();
        final firebaseId = doc.id.trim();

        final matchFirebaseId = _s(data, const ['matchId', 'match_id']);
        final matchId = _requireMapped(matchFirebaseToPostgresId, matchFirebaseId, entityName: 'match_events', fieldName: 'match_id');
        if (matchId.isEmpty) continue;

        final leagueFirebaseId = _s(data, const ['tournamentId', 'tournament_id', 'leagueId', 'league_id']);
        final leagueId = _requireMapped(leagueFirebaseToPostgresId, leagueFirebaseId, entityName: 'match_events', fieldName: 'league_id');
        if (leagueId.isEmpty) continue;

        final teamFirebaseId = _s(data, const ['teamId', 'team_id']);
        final teamId = teamFirebaseId.isEmpty
            ? null
            : _requireMapped(teamFirebaseToPostgresId, teamFirebaseId, entityName: 'match_events', fieldName: 'team_id');

        final eventType = _s(data, const ['eventType', 'event_type', 'type']);
        final minute = _iN(data, const ['minute']) ?? 0;
        final playerName = _sN(data, const ['playerName', 'player_name', 'title']);
        final isOwnGoal = _b(data, const ['isOwnGoal', 'is_own_goal'], fallback: false);

        String? resolvePlayerId(String? phoneOrId) {
          final k = (phoneOrId ?? '').trim();
          if (k.isEmpty) return null;
          return playerFirebaseToPostgresId[k];
        }

        final playerPhone = _sN(data, const ['playerPhone', 'player_phone', 'playerId', 'player_id']);
        final assistPhone = _sN(data, const ['assistPlayerPhone', 'assist_player_phone', 'assistPlayerId', 'assist_player_id']);
        final subInPhone = _sN(data, const ['subInPlayerPhone', 'sub_in_player_phone', 'subInPlayerId', 'sub_in_player_id']);

        final playerId = resolvePlayerId(playerPhone);
        final assistPlayerId = resolvePlayerId(assistPhone);
        final subInPlayerId = resolvePlayerId(subInPhone);

        final createdAt = _dt(data, const ['createdAt', 'created_at']);

        await _insertReturningUuid(
          tx,
          sqlNamed: r'''
INSERT INTO match_events (
  firebase_id,
  match_id, league_id, team_id,
  event_type, minute,
  player_name,
  player_id, assist_player_id, sub_in_player_id,
  is_own_goal,
  created_at
)
VALUES (
  @firebase_id,
  @match_id, @league_id, @team_id,
  @event_type, @minute,
  @player_name,
  @player_id, @assist_player_id, @sub_in_player_id,
  @is_own_goal,
  @created_at
)
RETURNING id
''',
          params: {
            'firebase_id': firebaseId,
            'match_id': matchId,
            'league_id': leagueId,
            'team_id': (teamId ?? '').trim().isEmpty ? null : teamId,
            'event_type': eventType,
            'minute': minute,
            'player_name': playerName,
            'player_id': (playerId ?? '').trim().isEmpty ? null : playerId,
            'assist_player_id': (assistPlayerId ?? '').trim().isEmpty ? null : assistPlayerId,
            'sub_in_player_id': (subInPlayerId ?? '').trim().isEmpty ? null : subInPlayerId,
            'is_own_goal': isOwnGoal,
            'created_at': createdAt,
          },
        );

        // İsterseniz burada ayrıca matchEventFirebaseToPostgresId map’i de tutulabilir.
        n++;
      }
      _log('✅ $colName -> match_events taşındı (kümülatif): $n');
    }
  }
}
