import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb; // Supabase çakışmasını önlemek için alias

const _kRememberMeKey = 'auth_remember_me';

@immutable
class AppSessionState {
  const AppSessionState({
    required this.user,
    required this.isAdmin,
    required this.role,
    required this.teamId,
    required this.phone,
    required this.isLoading,
    this.displayName,
  });

  static const _unset = Object();

  // Artık Supabase'in User objesini taşıyoruz
  final sb.User? user; 
  final bool isAdmin;
  final String role; // admin, manager, player, user
  final String? teamId;
  final String phone;
  final bool isLoading;
  final String? displayName;

  bool get isManager => role == 'manager';

  AppSessionState copyWith({
    Object? user = _unset,
    bool? isAdmin,
    String? role,
    Object? teamId = _unset,
    String? phone,
    bool? isLoading,
    Object? displayName = _unset,
  }) {
    return AppSessionState(
      user: identical(user, _unset) ? this.user : user as sb.User?,
      isAdmin: isAdmin ?? this.isAdmin,
      role: role ?? this.role,
      teamId: identical(teamId, _unset) ? this.teamId : teamId as String?,
      phone: phone ?? this.phone,
      isLoading: isLoading ?? this.isLoading,
      displayName: identical(displayName, _unset)
          ? this.displayName
          : displayName as String?,
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

  /// Uygulama açılışında çağrılır: "Beni Hatırla" işaretlenmeden açılmış bir
  /// oturum varsa kapatılır; böylece uygulama giriş ekranıyla açılır.
  /// (Supabase oturumu cihazda kalıcı sakladığı için bu kontrol gerekli.)
  static Future<void> enforceRememberMe() async {
    final auth = sb.Supabase.instance.client.auth;
    if (auth.currentSession == null) return;
    var remember = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      remember = prefs.getBool(_kRememberMeKey) ?? false;
    } catch (_) {}
    if (remember) return;
    try {
      await auth.signOut();
    } catch (_) {}
  }

  static Future<void> _setRememberMe(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kRememberMeKey, value);
    } catch (_) {}
  }

  Future<void> signOut() async {
    await _setRememberMe(false);
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
    } else {
      await _supabase.auth.signInWithPassword(phone: raw, password: password);
    }
    await _setRememberMe(rememberMe);
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
          // Gizli admin girişi hatırlanmaz; uygulama tekrar açılınca kapanır.
          await _setRememberMe(false);
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
        displayName: null,
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

  static String _raw10(String input) {
    var d = input.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('90') && d.length >= 12) d = d.substring(2);
    if (d.startsWith('0')) d = d.substring(1);
    if (d.length > 10) d = d.substring(d.length - 10);
    return d;
  }

  /// Profil bilgisi: önce `app_users` (auth_uid), sonra telefonla `players`.
  /// (Önceden var olmayan `users` tablosu dinleniyordu; isim/rol hep boştu.)
  Future<void> _loadProfile(sb.User user, bool isAdmin) async {
    _profileSub?.cancel();

    // Giriş e-postası "5xxxxxxxxx@masterclass.com" biçiminde.
    final email = (user.email ?? '').trim();
    var phone = _raw10((user.phone ?? '').trim());
    if (phone.isEmpty && email.endsWith('@masterclass.com')) {
      phone = _raw10(email.split('@').first);
    }

    String? name;
    String? role;
    String? teamId;

    try {
      final res = await _supabase
          .from('app_users')
          .select('name, role, phone, team_id')
          .eq('auth_uid', user.id)
          .limit(1);
      if (res.isNotEmpty) {
        final r = res.first;
        name = (r['name'] ?? '').toString().trim();
        role = (r['role'] ?? '').toString().trim();
        teamId = r['team_id']?.toString();
        final p = _raw10((r['phone'] ?? '').toString());
        if (phone.isEmpty) phone = p;
      }
    } catch (_) {}

    if (phone.isNotEmpty) {
      try {
        final res = await _supabase
            .from('players')
            .select('name, surname, role')
            .eq('phone', phone)
            .limit(1);
        if (res.isNotEmpty) {
          final r = res.first;
          final full = [
            (r['name'] ?? '').toString().trim(),
            (r['surname'] ?? '').toString().trim(),
          ].where((e) => e.isNotEmpty).join(' ');
          if ((name ?? '').isEmpty && full.isNotEmpty) name = full;
          final pr = (r['role'] ?? '').toString().trim().toLowerCase();
          if ((role ?? '').isEmpty && pr.isNotEmpty) {
            role = (pr.contains('sorumlu') || pr.contains('her') ||
                    pr == 'manager' || pr == 'both')
                ? 'manager'
                : 'player';
          }
        }
      } catch (_) {}
    }

    // Uygulama içinde rol kodları: admin, manager, player.
    final r = (role ?? '').toLowerCase();
    final resolvedRole = isAdmin
        ? 'admin'
        : (r.contains('sorumlu') || r == 'manager' ? 'manager' : 'player');

    if (_supabase.auth.currentUser?.id != user.id) return; // bu arada çıkış
    value = value.copyWith(
      user: user,
      isAdmin: isAdmin,
      role: resolvedRole,
      teamId: teamId,
      phone: phone,
      displayName: (name ?? '').isEmpty ? null : name,
      isLoading: false,
    );
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
