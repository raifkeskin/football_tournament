import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/admin_backdoor_utils.dart';
@immutable
class AppSessionState {
  const AppSessionState({
    required this.user,
    required this.isAdmin,
    required this.role,
    required this.teamId,
    required this.phone,
    required this.isLoading,
  });

  static const _unset = Object();

  final User? user;
  final bool isAdmin;
  final String role; // admin, manager, player, user
  final String? teamId;
  final String phone;
  final bool isLoading;

  AppSessionState copyWith({
    Object? user = _unset,
    bool? isAdmin,
    String? role,
    Object? teamId = _unset,
    String? phone,
    bool? isLoading,
  }) {
    return AppSessionState(
      user: identical(user, _unset) ? this.user : user as User?,
      isAdmin: isAdmin ?? this.isAdmin,
      role: role ?? this.role,
      teamId: identical(teamId, _unset) ? this.teamId : teamId as String?,
      phone: phone ?? this.phone,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AppSessionController extends ValueNotifier<AppSessionState> {
  AppSessionController({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        super(
          AppSessionState(
            user: (auth ?? FirebaseAuth.instance).currentUser,
            isAdmin: false,
            role: 'user',
            teamId: null,
            phone: '',
            isLoading: true,
          ),
        ) {
    _sub = _auth.authStateChanges().listen(_onAuthChanged);
    _onAuthChanged(_auth.currentUser);
  }

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  StreamSubscription<User?>? _sub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;
  String? _overrideRole;

  static const _rememberMeKey = 'auth_remember_me';
  static const _rememberUntilMsKey = 'auth_remember_until_ms';
  static const _rememberDays = 30;

  Future<bool> _shouldForceSignOut() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_rememberMeKey) ?? false;
    final untilMs = prefs.getInt(_rememberUntilMsKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final expired = untilMs != 0 && now > untilMs;
    return !remember || expired;
  }

  String _normalizePhoneToRaw10(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    var d = digits;
    if (d.startsWith('90') && d.length >= 12) {
      d = d.substring(2);
    }
    if (d.startsWith('0')) {
      d = d.substring(1);
    }
    if (d.length > 10) {
      d = d.substring(d.length - 10);
    }
    return d;
  }

  Future<void> signInWithPhonePassword({
    required String phoneInput,
    required String password,
    required bool rememberMe,
  }) async {
    final raw10 = _normalizePhoneToRaw10(phoneInput);
    if (raw10.length != 10) {
      throw Exception('Telefon numarası geçerli olmalı.');
    }
    final email = '$raw10@masterclass.com';
    await _auth.signInWithEmailAndPassword(email: email, password: password);
    final prefs = await SharedPreferences.getInstance();
    if (rememberMe) {
      final until = DateTime.now()
          .add(const Duration(days: _rememberDays))
          .millisecondsSinceEpoch;
      await prefs.setBool(_rememberMeKey, true);
      await prefs.setInt(_rememberUntilMsKey, until);
    } else {
      await prefs.setBool(_rememberMeKey, false);
      await prefs.setInt(_rememberUntilMsKey, 0);
    }
  }

  Future<void> signInWithUsername({
    required String username,
    required String password,
  }) async {
    final u = username.trim();
    final localPart = (u.contains('@') ? u.split('@').first : u).trim();
    final email = '$localPart@masterclass.com';
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    await _profileSub?.cancel();
    _profileSub = null;
    _overrideRole = null;
    value = value.copyWith(
      user: null,
      isLoading: false,
      isAdmin: false,
      role: 'user',
      teamId: null,
      phone: '',
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberMeKey, false);
    await prefs.setInt(_rememberUntilMsKey, 0);
    await _auth.signOut();
  }

  Future<bool> signInSuperAdminBackdoor({required String password}) async {
    final p = password.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '').trim();
    if (p.isEmpty) return false;

    final admins = _firestore.collection('admins');
    debugPrint('DEBUG BACKDOOR: start');

    Future<void> signInAsEmail(String? email) async {
      final e = (email ?? 'masterclass@masterclass.com').trim();
      if (e.isEmpty) {
        throw Exception('Backdoor email bulunamadı.');
      }
      await _auth.signInWithEmailAndPassword(email: e, password: p);
    }

    Future<void> syncAfterSignIn() async {
      final u = _auth.currentUser;
      if (u == null) return;
      await _onAuthChanged(u);
    }

    Future<Map<String, dynamic>?> tryDoc(String id) async {
      try {
        final s = await admins.doc(id).get();
        return s.data();
      } catch (_) {
        return null;
      }
    }

    final docCandidates = <String>[
      'backdoor',
      'super_admin',
      'app_owner',
    ];
    for (final id in docCandidates) {
      final data = await tryDoc(id);
      if (data != null && matchesBackdoorPassword(data, p)) {
        debugPrint('DEBUG BACKDOOR: matched doc($id)');
        _overrideRole = 'super_admin';
        await signInAsEmail(data['email'] as String?);
        await syncAfterSignIn();
        return true;
      }
    }

    try {
      final q = await admins.where('backdoorPassword', isEqualTo: p).limit(1).get();
      if (q.docs.isNotEmpty) {
        debugPrint('DEBUG BACKDOOR: matched where(backdoorPassword)');
        final data = q.docs.first.data();
        _overrideRole = 'super_admin';
        await signInAsEmail(data['email'] as String?);
        await syncAfterSignIn();
        return true;
      }
      debugPrint('DEBUG BACKDOOR: where(backdoorPassword) empty');
    } catch (e) {
      debugPrint('DEBUG BACKDOOR: where(backdoorPassword) failed: $e');
    }

    try {
      final q = await admins.where('email', isEqualTo: 'masterclass@masterclass.com').limit(1).get();
      if (q.docs.isNotEmpty) {
        final doc = q.docs.first;
        final data = doc.data();
        final candidates = <String, String>{
          'backdoorPassword': (data['backdoorPassword'] ?? '').toString(),
          'password': (data['password'] ?? '').toString(),
          'sifre': (data['sifre'] ?? '').toString(),
          'secret': (data['secret'] ?? '').toString(),
          'pin': (data['pin'] ?? '').toString(),
        };
        final keys = candidates.entries
            .where((e) => e.value.trim().isNotEmpty)
            .map((e) => e.key)
            .toList();
        debugPrint('DEBUG BACKDOOR: masterclass doc=${doc.id} candidateKeys=$keys');
        for (final e in candidates.entries) {
          if (e.value.trim().isEmpty) continue;
          final ok = e.value.trim() == p;
          debugPrint(
            'DEBUG BACKDOOR: compare field=${e.key} len=${e.value.trim().length} ok=$ok',
          );
        }
        if (matchesBackdoorPassword(data, p)) {
          debugPrint('DEBUG BACKDOOR: matched masterclass doc by compare');
          _overrideRole = 'super_admin';
          await signInAsEmail(data['email'] as String?);
          await syncAfterSignIn();
          return true;
        }
      } else {
        debugPrint('DEBUG BACKDOOR: masterclass email doc not found');
      }
    } catch (e) {
      debugPrint('DEBUG BACKDOOR: masterclass email lookup failed: $e');
    }

    try {
      final q = await admins.where('password', isEqualTo: p).limit(1).get();
      if (q.docs.isNotEmpty) {
        debugPrint('DEBUG BACKDOOR: matched where(password)');
        final data = q.docs.first.data();
        _overrideRole = 'super_admin';
        await signInAsEmail(data['email'] as String?);
        await syncAfterSignIn();
        return true;
      }
    } catch (e) {
      debugPrint('DEBUG BACKDOOR: where(password) failed: $e');
    }

    try {
      final sample = await admins.limit(10).get();
      debugPrint('DEBUG BACKDOOR: sample count=${sample.docs.length}');
      for (final d in sample.docs) {
        final data = d.data();
        debugPrint('DEBUG BACKDOOR: doc=${d.id} keys=${data.keys.toList()}');
        if (matchesBackdoorPassword(data, p)) {
          debugPrint('DEBUG BACKDOOR: matched by scan doc=${d.id}');
          _overrideRole = 'super_admin';
          await signInAsEmail(data['email'] as String?);
          await syncAfterSignIn();
          return true;
        }
      }
    } catch (e) {
      debugPrint('DEBUG BACKDOOR: sample scan failed: $e');
    }

    debugPrint('DEBUG BACKDOOR: no match');
    return false;
  }

  Future<void> _onAuthChanged(User? user) async {
    await _profileSub?.cancel();
    _profileSub = null;
    value = value.copyWith(
      user: user,
      isLoading: true,
      isAdmin: false,
      role: 'user',
      teamId: null,
      phone: '',
    );
    if (user == null) {
      value = value.copyWith(isLoading: false, isAdmin: false);
      return;
    }

    final override = _overrideRole;
    if (override != null && override.isNotEmpty) {
      value = value.copyWith(
        user: user,
        isLoading: false,
        role: override,
        teamId: null,
        phone: '',
        isAdmin: override == 'super_admin' || override == 'admin',
      );
      return;
    }

    if (await _shouldForceSignOut()) {
      await _auth.signOut();
      value = value.copyWith(
        user: null,
        isLoading: false,
        isAdmin: false,
        role: 'user',
        teamId: null,
        phone: '',
      );
      return;
    }

    final profile = await _loadUserProfile(user);
    final role = (profile['role'] as String?) ?? 'user';
    final teamId = profile['teamId'] as String?;
    final phone = (profile['phone'] as String?) ?? '';
    value = value.copyWith(
      isLoading: false,
      role: role,
      teamId: teamId,
      phone: phone,
      isAdmin: role == 'admin' || role == 'super_admin',
    );

    _profileSub = _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snap) {
      final data = snap.data();
      if (data == null) return;
      final liveRole =
          (data['accessRole'] ?? data['role'] ?? '').toString().trim();
      final liveTeamId = (data['teamId'] as String?)?.trim();
      final livePhone = (data['phone'] ?? '').toString().trim();
      final normalizedRole = liveRole.isEmpty ? 'user' : liveRole;
      final normalizedPhone = _normalizePhoneToRaw10(livePhone);
      value = value.copyWith(
        role: normalizedRole,
        teamId: liveTeamId?.isEmpty == true ? null : liveTeamId,
        phone: normalizedPhone,
        isAdmin: normalizedRole == 'admin' || normalizedRole == 'super_admin',
      );
    });
  }

  Future<Map<String, dynamic>> _loadUserProfile(User user) async {
    final users = _firestore.collection('users');
    final uid = user.uid;
    final ref = users.doc(uid);

    String inferPhone() {
      final p = (user.phoneNumber ?? '').trim();
      if (p.isNotEmpty) {
        final raw = _normalizePhoneToRaw10(p);
        return raw.isEmpty ? p : raw;
      }
      final email = (user.email ?? '').trim();
      if (email.isEmpty) return '';
      final local = email.contains('@') ? email.split('@').first : email;
      final raw = _normalizePhoneToRaw10(local.trim());
      return raw.isEmpty ? local.trim() : raw;
    }

    final snap = await ref.get();
    if (snap.exists) {
      final data = snap.data() ?? <String, dynamic>{};
      final role = (data['accessRole'] ?? data['role'] ?? '').toString().trim();
      final teamId = (data['teamId'] as String?)?.trim();
      final phone = (data['phone'] ?? '').toString().trim();
      final normalizedRole = role.isEmpty ? 'user' : role;
      final normalizedTeamId = teamId?.isEmpty == true ? null : teamId;
      final normalizedPhone =
          _normalizePhoneToRaw10(phone.isEmpty ? inferPhone() : phone);
      return <String, dynamic>{
        'role': normalizedRole,
        'teamId': normalizedTeamId,
        'phone': normalizedPhone,
      };
    }

    final inferred = inferPhone();
    final isAdminBootstrap = await _checkAdmin(user);
    return <String, dynamic>{
      'role': isAdminBootstrap ? 'admin' : 'user',
      'teamId': null,
      'phone': _normalizePhoneToRaw10(inferred),
    };
  }

  Future<bool> _checkAdmin(User user) async {
    final admins = _firestore.collection('admins');

    try {
      final docByUid = await admins.doc(user.uid).get();
      if (docByUid.exists) return true;
    } catch (_) {}

    final email = user.email?.trim() ?? '';
    if (email.isNotEmpty) {
      try {
        final docByEmail = await admins.doc(email).get();
        if (docByEmail.exists) return true;
      } catch (_) {}

      try {
        final q = await admins.where('email', isEqualTo: email).limit(1).get();
        if (q.docs.isNotEmpty) return true;
      } catch (_) {}
    }

    try {
      final q = await admins.where('uid', isEqualTo: user.uid).limit(1).get();
      if (q.docs.isNotEmpty) return true;
    } catch (_) {}

    return false;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }
}

class AppSession extends InheritedNotifier<AppSessionController> {
  const AppSession({
    super.key,
    required AppSessionController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppSessionController of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<AppSession>();
    if (w == null) {
      throw StateError('AppSession not found in widget tree.');
    }
    return w.notifier!;
  }
}
