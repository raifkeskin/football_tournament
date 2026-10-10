import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bildirim tercihleri (notification_prefs satırı). Kapatılan tür telefona
/// gitmez; uygulama içi bildirimlerde yine görünür.
@immutable
class NotificationPrefs {
  const NotificationPrefs({
    this.scopeMyTeam = true,
    this.scopeFollowed = true,
    this.scopeGroup = false,
    this.scopeLeague = false,
    this.schedule = true,
    this.live = true,
    this.goal = true,
    this.result = true,
    this.news = 'region',
    this.penalty = true,
    this.adminPenalty = true,
  });

  /// Misafirin varsayılanı: takip ettiği turnuvalarda yalnızca sonuçlar.
  static const guest = NotificationPrefs(
    schedule: false,
    live: false,
    goal: false,
    news: 'off',
  );

  final bool scopeMyTeam;
  final bool scopeFollowed;
  final bool scopeGroup;
  final bool scopeLeague;
  final bool schedule;
  final bool live;
  final bool goal;
  final bool result;

  /// 'off' | 'region' | 'league'
  final String news;
  final bool penalty;
  final bool adminPenalty;

  factory NotificationPrefs.fromRow(Map<String, dynamic> r) {
    bool b(String k, bool d) => r[k] is bool ? r[k] as bool : d;
    return NotificationPrefs(
      scopeMyTeam: b('scope_my_team', true),
      scopeFollowed: b('scope_followed', true),
      scopeGroup: b('scope_group', false),
      scopeLeague: b('scope_league', false),
      schedule: b('k_schedule', true),
      live: b('k_live', true),
      goal: b('k_goal', true),
      result: b('k_result', true),
      news: (r['k_news'] ?? 'region').toString(),
      penalty: b('k_penalty', true),
      adminPenalty: b('k_admin_penalty', true),
    );
  }

  Map<String, dynamic> toRow() => {
    'scope_my_team': scopeMyTeam,
    'scope_followed': scopeFollowed,
    'scope_group': scopeGroup,
    'scope_league': scopeLeague,
    'k_schedule': schedule,
    'k_live': live,
    'k_goal': goal,
    'k_result': result,
    'k_news': news,
    'k_penalty': penalty,
    'k_admin_penalty': adminPenalty,
  };

  NotificationPrefs copyWith({
    bool? scopeMyTeam,
    bool? scopeFollowed,
    bool? scopeGroup,
    bool? scopeLeague,
    bool? schedule,
    bool? live,
    bool? goal,
    bool? result,
    String? news,
    bool? penalty,
    bool? adminPenalty,
  }) => NotificationPrefs(
    scopeMyTeam: scopeMyTeam ?? this.scopeMyTeam,
    scopeFollowed: scopeFollowed ?? this.scopeFollowed,
    scopeGroup: scopeGroup ?? this.scopeGroup,
    scopeLeague: scopeLeague ?? this.scopeLeague,
    schedule: schedule ?? this.schedule,
    live: live ?? this.live,
    goal: goal ?? this.goal,
    result: result ?? this.result,
    news: news ?? this.news,
    penalty: penalty ?? this.penalty,
    adminPenalty: adminPenalty ?? this.adminPenalty,
  );
}

/// Tercihler, takip edilen takımlar ve takip edilen turnuvalar.
class NotificationPrefsService {
  NotificationPrefsService._();

  static SupabaseClient get _sb => Supabase.instance.client;

  /// Giriş yapmamış (misafir) kişi için cihaza bağlı isimsiz oturum açar;
  /// tercihler ve bildirim aboneliği bu kimliğe bağlanır.
  static Future<String?> ensureUser() async {
    final current = _sb.auth.currentUser;
    if (current != null) return current.id;
    try {
      final res = await _sb.auth.signInAnonymously();
      return res.user?.id;
    } catch (e) {
      debugPrint('İsimsiz oturum açılamadı: $e');
      return null;
    }
  }

  static bool get isGuest {
    final u = _sb.auth.currentUser;
    return u == null || u.isAnonymous;
  }

  static Future<NotificationPrefs> load() async {
    final uid = _sb.auth.currentUser?.id;
    final fallback = isGuest
        ? NotificationPrefs.guest
        : const NotificationPrefs();
    if (uid == null) return fallback;
    final row = await _sb
        .from('notification_prefs')
        .select()
        .eq('user_id', uid)
        .maybeSingle();
    return row == null ? fallback : NotificationPrefs.fromRow(row);
  }

  static Future<void> save(NotificationPrefs prefs) async {
    final uid = await ensureUser();
    if (uid == null) throw Exception('Oturum açılamadı.');
    await _sb.from('notification_prefs').upsert({
      'user_id': uid,
      ...prefs.toRow(),
    }, onConflict: 'user_id');
  }

  /// Takip edilen takımlar: turnuva adı ve takım adıyla.
  static Future<List<({String leagueId, String league, String team})>>
  followedTeams() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return const [];
    final rows = await _sb
        .from('followed_teams')
        .select('league_id, teams(name), leagues(name)')
        .eq('user_id', uid);
    return [
      for (final r in rows)
        (
          leagueId: r['league_id'].toString(),
          league: ((r['leagues'] as Map?)?['name'] ?? '').toString(),
          team: ((r['teams'] as Map?)?['name'] ?? '').toString(),
        ),
    ];
  }

  /// Turnuvada takip edilen takımı kaydeder (null: takibi bırakır). Oturum
  /// yoksa açmaz ([ensureSession] true değilse); takip cihazda da durur.
  static Future<void> setFollowedTeam(
    String leagueId,
    String? teamId, {
    bool ensureSession = false,
  }) async {
    final uid = ensureSession ? await ensureUser() : _sb.auth.currentUser?.id;
    if (uid == null) return;
    if (teamId == null) {
      await _sb
          .from('followed_teams')
          .delete()
          .eq('user_id', uid)
          .eq('league_id', leagueId);
      return;
    }
    await _sb.from('followed_teams').upsert({
      'user_id': uid,
      'league_id': leagueId,
      'team_id': teamId,
    }, onConflict: 'user_id,league_id');
  }

  static Future<Set<String>> followedLeagues() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return const {};
    final rows = await _sb
        .from('followed_leagues')
        .select('league_id')
        .eq('user_id', uid);
    return {for (final r in rows) r['league_id'].toString()};
  }

  static Future<void> setFollowedLeague(String leagueId, bool follow) async {
    final uid = await ensureUser();
    if (uid == null) throw Exception('Oturum açılamadı.');
    if (follow) {
      await _sb.from('followed_leagues').upsert({
        'user_id': uid,
        'league_id': leagueId,
      }, onConflict: 'user_id,league_id');
    } else {
      await _sb
          .from('followed_leagues')
          .delete()
          .eq('user_id', uid)
          .eq('league_id', leagueId);
    }
  }
}
