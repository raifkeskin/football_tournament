import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb; // Supabase çakışmasını önlemek için alias

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

  StreamSubscription<sb.AuthState>? _sub;
  StreamSubscription<List<Map<String, dynamic>>>? _profileSub;

  AppSessionController({
    sb.SupabaseClient? supabase,
  })  : _supabase = supabase ?? sb.Supabase.instance.client,
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
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      // ignore
    } finally {
      _onAuthChanged(null);
    }
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
        if (_supabase.auth.currentUser != null) {
          value = value.copyWith(isAdmin: true, role: 'super_admin');
          return true;
        }
      } catch (_) {}
    }

    // Firestore fallback was removed. Supabase Auth MUST succeed.
    return false;
  }

  void setAdmin(bool isAdmin) {
    value = value.copyWith(isAdmin: isAdmin);
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
    final emailAddress = user.email?.trim() ?? '';
    if (emailAddress == 'admin@masterclass.com' || emailAddress == 'masterclass@masterclass.com') {
      return true;
    }

    try {
      final res = await _supabase.from('admins').select().eq('id', user.id).limit(1);
      if (res.isNotEmpty) return true;
    } catch (_) {}

    if (emailAddress.isNotEmpty) {
      try {
        final res = await _supabase.from('admins').select().eq('email', emailAddress).limit(1);
        if (res.isNotEmpty) return true;
      } catch (_) {}
    }

    return false;
  }

  void _loadProfile(sb.User user, bool isAdmin) {
    _profileSub?.cancel();
    
    _profileSub = _supabase
        .from('users')
        .stream(primaryKey: ['id'])
        .eq('id', user.id)
        .listen((rows) {
      if (rows.isEmpty) {
        value = value.copyWith(
          user: user,
          isAdmin: isAdmin,
          role: isAdmin ? 'admin' : 'user',
          isLoading: false,
        );
        return;
      }

      final data = rows.first;
      value = value.copyWith(
        user: user,
        isAdmin: isAdmin,
        role: (data['role'] ?? data['access_role'] ?? (isAdmin ? 'admin' : 'user')).toString(),
        teamId: data['team_id']?.toString(),
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
