import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'active_tournament.dart';
import 'app_settings.dart';
import 'league_access.dart';
import 'league_scope.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    as sb; // Supabase çakışmasını önlemek için alias
import '../push/push_service.dart';

const _kRememberMeKey = 'auth_remember_me';

/// Kullanıcının sorumlu olduğu takım (sezon bazında, `team_managers`).
@immutable
class ManagedTeam {
  const ManagedTeam({required this.seasonId, required this.teamId});

  final String seasonId;
  final String teamId;
}

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
    this.playerId,
    this.ownedLeagueIds = const <String>{},
    this.managedTeams = const <ManagedTeam>[],
    this.ownedRegions = const <OwnedRegion>[],
    this.photoUrl,
  });

  static const _unset = Object();

  // Artık Supabase'in User objesini taşıyoruz
  final sb.User? user;
  final bool isAdmin;
  final String role; // admin, owner, region, manager, player, user
  final String? teamId;
  final String phone;
  final bool isLoading;
  final String? displayName;

  /// Kullanıcıya bağlı oyuncu kaydı (`players.auth_uid`).
  final String? playerId;

  /// Sahibi olduğu turnuvalar (`league_owners`).
  final Set<String> ownedLeagueIds;

  /// Sorumlu olduğu takımlar (`team_managers`).
  final List<ManagedTeam> managedTeams;

  /// Sorumlu olduğu bölgeler (`region_owners`).
  final List<OwnedRegion> ownedRegions;

  /// Profil fotoğrafı (`app_users.photo_url`; yönetici kartında).
  final String? photoUrl;

  bool get isManager => role == 'manager';
  bool get isLeagueOwner => ownedLeagueIds.isNotEmpty;
  bool get isRegionOwner => ownedRegions.isNotEmpty;

  /// Profilde yönetim paneli: admin, kurucu başkan, bölge sorumlusu.
  bool get hasManagementPanel => isAdmin || isLeagueOwner || isRegionOwner;

  /// Onay ekranını görebilir mi? (Talepler RLS ile zaten süzülür.)
  bool get canReviewApprovals => isAdmin || isLeagueOwner || isRegionOwner;

  /// Panelde görünen turnuvalar: sahibi olduğu + bölgesi olan turnuvalar.
  /// Admin için null (hepsi).
  Set<String>? get panelLeagueIds => isAdmin
      ? null
      : {...ownedLeagueIds, for (final r in ownedRegions) r.leagueId};

  /// Bu sezonda sorumlu olduğu bölgeler (kurucu/admin için boş).
  List<OwnedRegion> regionsInSeason(String seasonId) => [
    for (final r in ownedRegions)
      if (r.seasonId == seasonId) r,
  ];

  /// Bölgeyi yönetebilir mi?
  bool canManageRegion(String? leagueId, String? regionId) =>
      canManageLeague(leagueId) ||
      (regionId != null && ownedRegions.any((r) => r.id == regionId));

  /// Turnuvayı yönetebilir mi? Admin her turnuvayı, sahibi kendisininkini.
  bool canManageLeague(String? leagueId) =>
      isAdmin || (leagueId != null && ownedLeagueIds.contains(leagueId));

  bool managesTeam(String? seasonId, String? teamId) =>
      managedTeams.any((t) => t.seasonId == seasonId && t.teamId == teamId);

  AppSessionState copyWith({
    Object? user = _unset,
    bool? isAdmin,
    String? role,
    Object? teamId = _unset,
    String? phone,
    bool? isLoading,
    Object? displayName = _unset,
    Object? playerId = _unset,
    Set<String>? ownedLeagueIds,
    List<ManagedTeam>? managedTeams,
    List<OwnedRegion>? ownedRegions,
    Object? photoUrl = _unset,
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
      playerId: identical(playerId, _unset)
          ? this.playerId
          : playerId as String?,
      ownedLeagueIds: ownedLeagueIds ?? this.ownedLeagueIds,
      managedTeams: managedTeams ?? this.managedTeams,
      ownedRegions: ownedRegions ?? this.ownedRegions,
      photoUrl: identical(photoUrl, _unset)
          ? this.photoUrl
          : photoUrl as String?,
    );
  }
}

/// Bölge sorumluluğu: bölge + sezonu + turnuvası.
@immutable
class OwnedRegion {
  const OwnedRegion({
    required this.id,
    required this.name,
    required this.seasonId,
    required this.leagueId,
  });

  final String id;
  final String name;
  final String seasonId;
  final String leagueId;
}

class AppSessionController extends ValueNotifier<AppSessionState> {
  final sb.SupabaseClient _supabase;

  StreamSubscription<sb.AuthState>? _sub;
  StreamSubscription<List<Map<String, dynamic>>>? _profileSub;

  AppSessionController({sb.SupabaseClient? supabase})
    : _supabase = supabase ?? sb.Supabase.instance.client,
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
    // Kodla turnuva takip eden misafirin isimsiz oturumu korunur.
    if (auth.currentUser?.isAnonymous ?? false) return;
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

  static Future<void> setRememberMe(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kRememberMeKey, value);
    } catch (_) {}
  }

  Future<void> signOut() async {
    await setRememberMe(false);
    // Oturum kapanmadan (yetki varken) bu cihazın bildirim kaydı silinir.
    await PushService.onSignOut();
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
    // Geçici şifreyle girişte "Beni Hatırla", kullanıcı kendi şifresini
    // belirleyince uygulanır (ResetPasswordScreen).
    await setRememberMe(rememberMe && !mustChangePassword);
  }

  /// Girişten sonra: kişinin profili (rol, oyuncu kaydı) yüklenene kadar
  /// bekler; ekranlar ara içerik göstermeden doğrudan açılsın.
  Future<void> waitForProfile(
    String uid, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    bool ready() => value.user?.id == uid && !value.isLoading;
    if (ready()) return Future.value();
    final done = Completer<void>();
    void check() {
      if (ready() && !done.isCompleted) done.complete();
    }

    addListener(check);
    return done.future
        .timeout(timeout, onTimeout: () {})
        .whenComplete(() => removeListener(check));
  }

  /// Admin onayıyla verilen geçici şifreyle giriş yapıldıysa true.
  bool get mustChangePassword =>
      _supabase.auth.currentUser?.userMetadata?['must_change_password'] == true;

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
          await setRememberMe(false);
          value = value.copyWith(isAdmin: true, role: 'super_admin');
          return true;
        }
      } catch (_) {}
    }

    // Firestore fallback was removed. Supabase Auth MUST succeed.
    return false;
  }

  void setPhotoUrl(String? url) {
    value = value.copyWith(photoUrl: url);
  }

  void setAdmin(bool isAdmin) {
    value = value.copyWith(isAdmin: isAdmin);
  }

  /// Son görülen oturum kimliği; değişince ekranlar verilerini baştan okur
  /// (gizli turnuvaların görünürlüğü kişiye göre değişir).
  String? _lastAuthId = '';

  Future<void> _onAuthChanged(sb.User? authUser) async {
    if (authUser?.id != _lastAuthId) {
      final first = _lastAuthId == '';
      _lastAuthId = authUser?.id;
      if (!first) LeagueAccess.bump();
      // Yeni giriş: profil yüklenene kadar ekranlar eski (misafir) bilgiyle
      // ara içerik göstermesin.
      if (!first && authUser != null && !authUser.isAnonymous) {
        value = value.copyWith(user: authUser, isLoading: true);
      }
      // Uygulama kişinin turnuvasının kimliğine bürünür (giriş/çıkışta).
      ActiveTournament.refresh();
      // Çıkışta cihazdaki kodlarla isimsiz takip; girişte hesaba taşınır.
      if ((authUser == null || !authUser.isAnonymous) &&
          AppSettings.privateLeaguesEnabled.value) {
        LeagueAccess.restoreFollows().then((changed) {
          if (changed && authUser != null) LeagueAccess.bump();
        });
      }
    }
    // İsimsiz (kodla takip eden) oturum arayüzde misafir sayılır.
    final user = (authUser?.isAnonymous ?? false) ? null : authUser;
    if (user == null) {
      _profileSub?.cancel();
      LeagueScope.ids.value = null; // misafir tüm turnuvaları görür
      value = value.copyWith(
        user: null,
        isAdmin: false,
        role: 'user',
        teamId: null,
        phone: '',
        isLoading: false,
        displayName: null,
        playerId: null,
        ownedLeagueIds: const <String>{},
        managedTeams: const <ManagedTeam>[],
        ownedRegions: const <OwnedRegion>[],
        photoUrl: null,
      );
      return;
    }

    final isAdmin = await _checkAdmin(user);
    _loadProfile(user, isAdmin);
  }

  /// Yetkinin tek kaynağı veritabanı: `admins.user_id`. Veritabanı kuralları
  /// (RLS) da aynı tabloya baktığı için arayüz ile yetki birbirini tutar.
  Future<bool> _checkAdmin(sb.User user) async {
    try {
      final res = await _supabase
          .from('admins')
          .select('id')
          .eq('user_id', user.id)
          .limit(1);
      return res.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<Set<String>> _loadOwnedLeagues(String uid) async {
    try {
      final res = await _supabase
          .from('league_owners')
          .select('league_id')
          .eq('user_id', uid);
      return res
          .map((r) => (r['league_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (_) {
      return const <String>{};
    }
  }

  Future<List<OwnedRegion>> _loadOwnedRegions(String uid) async {
    try {
      final res = await _supabase
          .from('region_owners')
          .select('season_regions(id, name, season_id, seasons(league_id))')
          .eq('user_id', uid);
      return [
        for (final r in res)
          if (r['season_regions'] is Map)
            OwnedRegion(
              id: (r['season_regions']['id'] ?? '').toString(),
              name: (r['season_regions']['name'] ?? '').toString(),
              seasonId: (r['season_regions']['season_id'] ?? '').toString(),
              leagueId:
                  (r['season_regions']['seasons'] is Map
                          ? r['season_regions']['seasons']['league_id'] ?? ''
                          : '')
                      .toString(),
            ),
      ];
    } catch (_) {
      return const <OwnedRegion>[];
    }
  }

  Future<List<ManagedTeam>> _loadManagedTeams(String uid) async {
    try {
      final res = await _supabase
          .from('team_managers')
          .select('season_id, team_id')
          .eq('user_id', uid);
      return res
          .map(
            (r) => ManagedTeam(
              seasonId: (r['season_id'] ?? '').toString(),
              teamId: (r['team_id'] ?? '').toString(),
            ),
          )
          .toList();
    } catch (_) {
      return const <ManagedTeam>[];
    }
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
    String? teamId;
    String? playerId;
    String? photoUrl;

    final ownedLeagueIds = await _loadOwnedLeagues(user.id);
    final managedTeams = await _loadManagedTeams(user.id);
    final ownedRegions = await _loadOwnedRegions(user.id);

    try {
      final res = await _supabase
          .from('app_users')
          .select('name, phone, team_id, photo_url')
          .eq('auth_uid', user.id)
          .limit(1);
      if (res.isNotEmpty) {
        final r = res.first;
        name = (r['name'] ?? '').toString().trim();
        teamId = r['team_id']?.toString();
        final ph = (r['photo_url'] ?? '').toString().trim();
        photoUrl = ph.isEmpty ? null : ph;
        final p = _raw10((r['phone'] ?? '').toString());
        if (phone.isEmpty) phone = p;
      }
    } catch (_) {}

    // Oyuncu kaydı: önce eşleşmiş kayıt (auth_uid), yoksa telefonla.
    try {
      var res = await _supabase
          .from('players')
          .select('id, name, surname, role')
          .eq('auth_uid', user.id)
          .limit(1);
      if (res.isEmpty && phone.isNotEmpty) {
        res = await _supabase
            .from('players')
            .select('id, name, surname, role')
            .eq('phone', phone)
            .limit(1);
      }
      if (res.isNotEmpty) {
        final r = res.first;
        playerId = (r['id'] ?? '').toString();
        final full = [
          (r['name'] ?? '').toString().trim(),
          (r['surname'] ?? '').toString().trim(),
        ].where((e) => e.isNotEmpty).join(' ');
        if ((name ?? '').isEmpty && full.isNotEmpty) name = full;
      }
    } catch (_) {}

    // Uygulama içinde rol kodları: admin, owner, manager, player.
    // Sorumluluk artık `team_managers`tan gelir; players.role metni
    // (Takım Sorumlusu / Her İkisi) yetki için kullanılmaz.
    final resolvedRole = isAdmin
        ? 'admin'
        : ownedLeagueIds.isNotEmpty
        ? 'owner'
        : ownedRegions.isNotEmpty
        ? 'region'
        : managedTeams.isNotEmpty
        ? 'manager'
        : 'player';

    if (_supabase.auth.currentUser?.id != user.id) return; // bu arada çıkış
    value = value.copyWith(
      user: user,
      isAdmin: isAdmin,
      role: resolvedRole,
      teamId: teamId,
      phone: phone,
      displayName: (name ?? '').isEmpty ? null : name,
      playerId: (playerId ?? '').isEmpty ? null : playerId,
      ownedLeagueIds: ownedLeagueIds,
      managedTeams: managedTeams,
      ownedRegions: ownedRegions,
      photoUrl: photoUrl,
      isLoading: false,
    );
    await _loadLeagueScope(isAdmin);
  }

  /// Giriş yapan kişi (admin hariç) yalnızca kendi turnuvalarını görür.
  /// Kapsam değişince ana sekmeler verilerini yeniden kurar.
  Future<void> _loadLeagueScope(bool isAdmin) async {
    Set<String>? next;
    if (!isAdmin) {
      try {
        final res = await _supabase.rpc('my_league_ids');
        final list = [for (final x in (res as List? ?? const [])) x.toString()];
        next = list.isEmpty ? null : list.toSet();
      } catch (_) {
        next = null;
      }
    }
    final prev = LeagueScope.ids.value;
    final same =
        (prev == null && next == null) ||
        (prev != null &&
            next != null &&
            prev.length == next.length &&
            prev.containsAll(next));
    if (same) return;
    LeagueScope.ids.value = next;
    LeagueAccess.bump();
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
