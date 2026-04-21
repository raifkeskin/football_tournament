import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Future<ConfirmationResult> startPhoneAuthWeb({
    required String phoneNumber,
  }) async {
    if (!kIsWeb) {
      throw StateError('startPhoneAuthWeb sadece Web platformunda kullanılabilir.');
    }
    return _auth.signInWithPhoneNumber(phoneNumber);
  }

  Stream<UserDoc?> watchUserDoc(String uid) {
    final id = uid.trim();
    if (id.isEmpty) return const Stream<UserDoc?>.empty();
    return _firestore.collection('users').doc(id).snapshots().map((snap) {
      if (!snap.exists) return null;
      final data = snap.data() as Map<String, dynamic>? ?? <String, dynamic>{};
      return UserDoc(
        uid: snap.id,
        role: (data['accessRole'] ?? data['role'])?.toString(),
        phone: (data['phone'] ?? '').toString(),
      );
    });
  }

  Stream<List<RosterAssignment>> watchRosterAssignmentsByPhone(String phone) {
    final p = phone.trim();
    if (p.isEmpty) return const Stream<List<RosterAssignment>>.empty();
    return _firestore
        .collection('rosters')
        .where('playerPhone', isEqualTo: p)
        .snapshots()
        .map((snap) {
          return snap.docs.map((d) {
            final r = d.data();
            return RosterAssignment(
              id: d.id,
              tournamentId: (r['tournamentId'] ?? '').toString().trim(),
              teamId: (r['teamId'] ?? '').toString().trim(),
              role: (r['role'] ?? '').toString(),
            );
          }).toList();
        });
  }

  Future<void> createOtpRequest({
    required String phoneRaw10,
    required String code,
    required DateTime expiresAt,
  }) async {
    final raw10 = phoneRaw10.trim();
    final c = code.trim();
    if (raw10.isEmpty || c.isEmpty) return;
    await _firestore.collection('otp_requests').doc(raw10).set({
      'phone': raw10,
      'code': c,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<OtpRequest?> getOtpRequest(String phoneRaw10) async {
    final raw10 = phoneRaw10.trim();
    if (raw10.isEmpty) return null;
    final snap = await _firestore.collection('otp_requests').doc(raw10).get();
    final data = snap.data();
    if (data == null) return null;
    final storedCode = (data['code'] ?? '').toString().trim();
    final expiresAt = data['expiresAt'];
    final exp = expiresAt is Timestamp ? expiresAt.toDate() : null;
    if (storedCode.isEmpty || exp == null) return null;
    return OtpRequest(phoneRaw10: raw10, code: storedCode, expiresAt: exp);
  }

  Future<void> deleteOtpRequest(String phoneRaw10) async {
    final raw10 = phoneRaw10.trim();
    if (raw10.isEmpty) return;
    await _firestore.collection('otp_requests').doc(raw10).delete();
  }

  Future<ProfileLookupResult> lookupProfileByPhoneRaw10(String phoneRaw10) async {
    final raw10 = phoneRaw10.trim();
    if (raw10.length != 10) {
      return const ProfileLookupResult.notFound();
    }

    Future<List<Map<String, dynamic>>> leaguesBy(String field, String value) async {
      final snap =
          await _firestore.collection('leagues').where(field, isEqualTo: value).limit(10).get();
      return snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
    }

    var leagues = await leaguesBy('managerPhoneRaw10', raw10);
    if (leagues.isEmpty) {
      leagues = await leaguesBy('managerPhone', raw10);
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
      final snap =
          await _firestore.collection('players').where(field, isEqualTo: value).limit(1).get();
      if (snap.docs.isEmpty) return null;
      final d = snap.docs.first;
      return {...d.data(), 'id': d.id};
    }

    Map<String, dynamic>? player =
        await firstPlayerBy('phoneRaw10', raw10) ?? await firstPlayerBy('phone', raw10);
    player ??= await firstPlayerBy('phone', '0$raw10');
    player ??= await firstPlayerBy('phone', '+90$raw10');
    player ??= await firstPlayerBy('phone', '90$raw10');

    if (player == null) {
      return const ProfileLookupResult.notFound();
    }

    final playerId = (player['id'] ?? '').toString().trim();
    final name = (player['name'] ?? '').toString().trim();
    final teamId = (player['teamId'] ?? '').toString().trim();
    final pr = (player['role'] ?? '').toString().trim();
    final resolvedRole =
        (pr == 'Takım Sorumlusu' || pr == 'Her İkisi') ? 'manager' : 'player';

    String? teamName;
    String? tournamentId;
    if (teamId.isNotEmpty && teamId != 'free_agent_pool') {
      final tSnap = await _firestore.collection('teams').doc(teamId).get();
      final t = tSnap.data();
      teamName = (t?['name'] as String?)?.trim();
      tournamentId = (t?['leagueId'] as String?)?.trim();
    }

    return ProfileLookupResult.playerProfile(
      matchedPlayerId: playerId.isEmpty ? null : playerId,
      playerName: name.isEmpty ? null : name,
      resolvedRole: resolvedRole,
      resolvedTeamId: teamId.isEmpty ? null : teamId,
      resolvedTournamentId: tournamentId?.isEmpty ?? true ? null : tournamentId,
      resolvedTeamName: teamName?.isEmpty ?? true ? null : teamName,
    );
  }

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
      userCred = await _auth.createUserWithEmailAndPassword(
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

    final batch = _firestore.batch();
    final users = _firestore.collection('users');

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

    batch.set(
      users.doc(user.uid),
      {
        'accessRole': accessRole,
        'phone': raw10,
        if (fullName != null) 'fullName': fullName,
        if (trimmedName.isNotEmpty) 'name': trimmedName,
        if (trimmedSurname.isNotEmpty) 'surname': trimmedSurname,
        'roles': FieldValue.arrayUnion([roleEntry]),
        if (resolvedRole == 'tournament_admin') 'tournamentIds': matchedTournamentIds,
        if (resolvedRole == 'tournament_admin')
          'activeTournamentId': (selectedTournamentId ?? '').trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    if (resolvedRole == 'tournament_admin') {
    } else if (profileFound) {
      final pid = (matchedPlayerId ?? '').trim();
      if (pid.isNotEmpty) {
        batch.update(_firestore.collection('players').doc(pid), {
          'authUid': user.uid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } else {
      batch.set(
        _firestore.collection('players').doc(),
        {
          'teamId': (resolvedTeamId ?? 'free_agent_pool').trim().isEmpty
              ? 'free_agent_pool'
              : (resolvedTeamId ?? 'free_agent_pool').trim(),
          if (fullName != null) 'name': fullName,
          'role': 'Futbolcu',
          'phone': raw10,
          'authUid': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
    }

    await batch.commit();

    final tid = (selectedTournamentId ?? '').trim();
    final isTournamentAdmin = resolvedRole == 'tournament_admin' && tid.isNotEmpty;
    return OnlineRegistrationResult(
      uid: user.uid,
      isTournamentAdmin: isTournamentAdmin,
      tournamentId: isTournamentAdmin ? tid : null,
    );
  }
}

class UserDoc {
  const UserDoc({required this.uid, required this.role, required this.phone});

  final String uid;
  final String? role;
  final String phone;
}

class RosterAssignment {
  const RosterAssignment({
    required this.id,
    required this.tournamentId,
    required this.teamId,
    required this.role,
  });

  final String id;
  final String tournamentId;
  final String teamId;
  final String role;
}

class OtpRequest {
  const OtpRequest({
    required this.phoneRaw10,
    required this.code,
    required this.expiresAt,
  });

  final String phoneRaw10;
  final String code;
  final DateTime expiresAt;
}

class ProfileLookupResult {
  const ProfileLookupResult._({
    required this.profileFound,
    required this.resolvedRole,
    required this.matchedPlayerId,
    required this.playerName,
    required this.resolvedTeamId,
    required this.resolvedTeamName,
    required this.resolvedTournamentId,
    required this.matchedLeagueIds,
    required this.leagues,
  });

  const ProfileLookupResult.notFound()
    : this._(
        profileFound: false,
        resolvedRole: 'player',
        matchedPlayerId: null,
        playerName: null,
        resolvedTeamId: 'free_agent_pool',
        resolvedTeamName: null,
        resolvedTournamentId: null,
        matchedLeagueIds: const [],
        leagues: const [],
      );

  ProfileLookupResult.tournamentAdmin({
    required List<String> matchedLeagueIds,
    required List<Map<String, dynamic>> leagues,
  }) : this._(
         profileFound: true,
         resolvedRole: 'tournament_admin',
         matchedPlayerId: null,
         playerName: null,
         resolvedTeamId: null,
         resolvedTeamName: null,
         resolvedTournamentId: null,
         matchedLeagueIds: matchedLeagueIds,
         leagues: leagues,
       );

  ProfileLookupResult.playerProfile({
    required String? matchedPlayerId,
    required String? playerName,
    required String resolvedRole,
    required String? resolvedTeamId,
    required String? resolvedTournamentId,
    required String? resolvedTeamName,
  }) : this._(
         profileFound: true,
         resolvedRole: resolvedRole,
         matchedPlayerId: matchedPlayerId,
         playerName: playerName,
         resolvedTeamId: resolvedTeamId,
         resolvedTeamName: resolvedTeamName,
         resolvedTournamentId: resolvedTournamentId,
         matchedLeagueIds: const [],
         leagues: const [],
       );

  final bool profileFound;
  final String resolvedRole;
  final String? matchedPlayerId;
  final String? playerName;
  final String? resolvedTeamId;
  final String? resolvedTeamName;
  final String? resolvedTournamentId;
  final List<String> matchedLeagueIds;
  final List<Map<String, dynamic>> leagues;
}

class OnlineRegistrationResult {
  const OnlineRegistrationResult({
    required this.uid,
    required this.isTournamentAdmin,
    required this.tournamentId,
  });

  final String uid;
  final bool isTournamentAdmin;
  final String? tournamentId;
}
