import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb; // Supabase çakışmasını önlemek için alias
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

  // Artık Supabase'in User objesini taşıyoruz
  final sb.User? user; 
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
      user: identical(user, _unset) ? this.user : user as sb.User?,
      isAdmin: isAdmin ?? this.isAdmin,
      role: role ?? this.role,
      teamId: identical(teamId, _unset) ? this.teamId : teamId as String?,
      phone: phone ?? this.phone,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AppSessionController extends ValueNotifier<AppSessionState> {
  final sb.SupabaseClient _supabase;
  final FirebaseFirestore _firestore; // Admin kontrolü için şimdilik Firestore kalıyor

  StreamSubscription<sb.AuthState>? _sub;
  StreamSubscription<DocumentSnapshot>? _profileSub;

  AppSessionController({
    sb.SupabaseClient? supabase,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _supabase = supabase ?? sb.Supabase.instance.client,
        _firestore = firestore ?? FirebaseFirestore.instance,
        super(
          AppSessionState(
            user: (supabase ?? sb.Supabase.instance.client).auth.currentUser,
            isAdmin: false,
            role: 'user',
            teamId: null,
            phone: '',
            isLoading: true,
          ),
        ) {
    // Akışı Supabase Auth değişikliklerine kaydırdık
    _sub = _supabase.auth.onAuthStateChange.listen((data) {
      _onAuthChanged(data.session?.user);
    });
    
    // İlk açılışta mevcut kullanıcıyı kontrol et
    _onAuthChanged(_supabase.auth.currentUser);
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  String? _resolveEmailFromPhoneInput(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final compact = trimmed.replaceAll(RegExp(r'\s+'), '');
    if (compact.contains('@')) return compact;

    final digits = compact.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;

    if (digits.length == 10) {
      return '$digits@masterclass.com';
    }
    if (digits.length == 11 && digits.startsWith('0')) {
      return '${digits.substring(1)}@masterclass.com';
    }
    return null;
  }

  Future<void> signInWithPhonePassword({
    String? phoneInput,
    String? phone,
    required String password,
    bool rememberMe = false,
  }) async {
    final raw = (phoneInput ?? phone ?? '').trim();
    if (raw.isEmpty) {
      throw ArgumentError('phone boş olamaz');
    }

    final email = _resolveEmailFromPhoneInput(raw);
    if (email != null) {
      await _supabase.auth.signInWithPassword(email: email, password: password);
      return;
    }

    await _supabase.auth.signInWithPassword(phone: raw, password: password);
  }

  Future<bool> signInSuperAdminBackdoor({required String password}) async {
    final pwd = password.trim();
    if (pwd.isEmpty) return false;

    const adminEmails = <String>[
      'admin@masterclass.com',
      'masterclass@masterclass.com',
    ];

    for (final email in adminEmails) {
      try {
        await _supabase.auth.signInWithPassword(email: email, password: pwd);
        return _supabase.auth.currentUser != null;
      } catch (_) {}
    }

    final refs = <DocumentReference<Map<String, dynamic>>>[
      _firestore.collection('admins').doc('backdoor'),
      _firestore.collection('admins').doc('masterclass'),
      _firestore.collection('config').doc('admin_backdoor'),
      _firestore.collection('config').doc('backdoor'),
    ];

    for (final ref in refs) {
      try {
        final snap = await ref.get();
        final data = snap.data();
        if (data == null) continue;
        if (!matchesBackdoorPassword(data, pwd)) continue;

        value = value.copyWith(isAdmin: true, role: 'super_admin');
        return true;
      } catch (_) {}
    }

    return false;
  }

  Future<void> _onAuthChanged(sb.User? user) async {
    if (user == null) {
      _profileSub?.cancel();
      value = value.copyWith(
        user: null,
        isAdmin: false,
        role: 'user',
        teamId: null,
        phone: '',
        isLoading: false,
      );
      return;
    }

    // Admin kontrolünü hala Firestore üzerinden yapıyoruz (Kodlar silinmedi)
    final isAdmin = await _checkAdmin(user);
    
    // Master Class Lig profil verilerini yükle
    _loadProfile(user, isAdmin);
  }

  Future<bool> _checkAdmin(sb.User user) async {
    final admins = _firestore.collection('admins');

    // Supabase User ID'si ile Firestore'da adminlik sorguluyoruz
    try {
      final docByUid = await admins.doc(user.id).get();
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
      final q = await admins.where('uid', isEqualTo: user.id).limit(1).get();
      if (q.docs.isNotEmpty) return true;
    } catch (_) {}

    return false;
  }

  void _loadProfile(sb.User user, bool isAdmin) {
    _profileSub?.cancel();
    
    // Profil verileri Firestore'da olduğu sürece buradan okumaya devam eder
    _profileSub = _firestore
        .collection('users')
        .doc(user.id)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) {
        value = value.copyWith(
          user: user,
          isAdmin: isAdmin,
          role: isAdmin ? 'admin' : 'user',
          isLoading: false,
        );
        return;
      }

      final data = snap.data() ?? <String, dynamic>{};
      value = value.copyWith(
        user: user,
        isAdmin: isAdmin,
        role: (data['role'] ?? (isAdmin ? 'admin' : 'user')).toString(),
        teamId: data['teamId']?.toString(),
        phone: data['phone']?.toString() ?? '',
        isLoading: false,
      );
    });
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
    final controller = context
        .dependOnInheritedWidgetOfExactType<AppSession>()
        ?.notifier;
    if (controller == null) {
      throw StateError('AppSession bulunamadı');
    }
    return controller;
  }
}
