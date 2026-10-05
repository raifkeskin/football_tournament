import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/active_tournament.dart';
import '../../../core/services/app_session.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../match/models/match.dart';
import '../../match/screens/match_details_screen.dart';
import '../../player/widgets/player_card.dart';
import '../../team/models/team.dart';
import '../../team/utils/standings.dart';
import '../../tournament/models/league.dart';
import 'home_news_card.dart';

/// Yeni tasarımın renk sistemi: temel renkler sabit, turnuva yalnızca ana ve
/// vurgu rengini getirir, durum renkleri her turnuvada aynı.
class DashColors {
  DashColors._();

  static const ground = Color(0xFF0F172A);
  static const surface = Color(0xFF1E293B);
  static const raised = Color(0xFF273449);
  static const line = Color(0xFF2A3446);
  static const text = Color(0xFFF8FAFC);
  static const muted = Color(0xFF94A3B8);

  static const live = Color(0xFFEF4444);
  static const finished = Color(0xFF64748B);
  static const yellow = Color(0xFFFACC15);
  static const red = Color(0xFFDC2626);

  /// Turnuvanın vurgu rengi (tema yoksa yeşil).
  static Color accent() =>
      ActiveTournament.theme.value?.secondary ?? const Color(0xFF10B981);

  /// Turnuvanın ana rengi (tema yoksa koyu yeşil).
  static Color primary() =>
      ActiveTournament.theme.value?.primary ?? const Color(0xFF064E3B);

  /// Vurgu renginin üstündeki yazı rengi (açık vurguda koyu yazı).
  static Color onAccent() =>
      accent().computeLuminance() > 0.45 ? const Color(0xFF0B1220) : text;
}

TextStyle _barlow({
  double size = 14,
  FontWeight weight = FontWeight.w500,
  Color color = DashColors.text,
  double? spacing,
  double? height,
}) => TextStyle(
  fontFamily: 'Barlow',
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: spacing,
  height: height,
);

TextStyle _condensed({
  double size = 20,
  Color color = Colors.white,
  bool italic = false,
}) => TextStyle(
  fontFamily: 'BarlowCondensed',
  fontWeight: FontWeight.w800,
  fontStyle: italic ? FontStyle.italic : FontStyle.normal,
  fontSize: size,
  color: color,
  height: 1.1,
);

String _trUpper(String s) =>
    s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

/// Logosu olmayan takımın rozetindeki kısaltma (ilk kelimeden 3 harf).
String teamInitials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return '?';
  final first = _trUpper(words.first);
  return first.length <= 3 ? first : first.substring(0, 3);
}

/// Takım rozeti: logo varsa logo, yoksa takım renginde baş harfler.
class TeamBadge extends StatelessWidget {
  const TeamBadge({
    super.key,
    required this.name,
    this.logoUrl = '',
    this.color,
    this.size = 28,
  });

  final String name;
  final String logoUrl;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (logoUrl.trim().isNotEmpty) {
      return SizedBox(
        width: size,
        height: size,
        child: WebSafeImage(
          url: logoUrl,
          width: size,
          height: size,
          fit: BoxFit.contain,
          isCircle: true,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color ?? const Color(0xFF475569),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.25),
          width: 1.5,
        ),
      ),
      child: Text(
        teamInitials(name),
        style: _condensed(size: size * 0.36),
        maxLines: 1,
      ),
    );
  }
}

class _TeamInfo {
  const _TeamInfo({
    required this.id,
    required this.name,
    required this.logoUrl,
    this.color,
    this.groupId,
  });

  final String id;
  final String name;
  final String logoUrl;
  final Color? color;
  final String? groupId;

  static Color? _hex(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(s)) return null;
    return Color(int.parse('FF${s.substring(1)}', radix: 16));
  }
}

/// Gol / asist listesindeki oyuncu.
class _Scorer {
  _Scorer(this.playerId, this.name, this.teamId, this.photoUrl);
  final String playerId;
  final String name;
  final String teamId;
  final String photoUrl;
  int goals = 0;
}

/// Panonun tek seferde okunan verisi.
class _DashData {
  _DashData({
    required this.seasonId,
    required this.seasonName,
    required this.openHours,
    required this.teams,
    required this.groups,
    required this.groupRegion,
    required this.matches,
    required this.myTeamIds,
    required this.scorers,
    required this.assisters,
    required this.totalGoals,
    required this.activePenaltyMatches,
    required this.pendingPenalties,
  });

  final String seasonId;
  final String seasonName;
  final int openHours;
  final Map<String, _TeamInfo> teams;
  final Map<String, String> groups; // id -> ad
  final Map<String, String> groupRegion; // grup id -> bölge adı
  final List<MatchModel> matches;
  final Set<String> myTeamIds;
  final List<_Scorer> scorers;
  final List<_Scorer> assisters;
  final int totalGoals;

  /// Oyuncunun süren cezası (kalan maç); yoksa 0.
  final int activePenaltyMatches;

  /// Yöneticinin onayını bekleyen ceza sayısı.
  final int pendingPenalties;
}

/// Yeni ana sayfa panosu (önizleme kanalı). Oyuncu ve takım sorumlusu için
/// sıradaki maç + esame durumu; misafir ve takımı olmayanlar için turnuva
/// özeti ve "Takımımı takip et".
class HomeDashboard extends StatefulWidget {
  const HomeDashboard({
    super.key,
    required this.league,
    required this.onOpenNews,
    required this.onOpenTab,
    required this.onOpenMenu,
  });

  final League league;
  final VoidCallback onOpenNews;

  /// Ana gezinme sekmesine geçiş (2 Fikstür, 3 Puan Durumu, 4 İstatistik).
  final ValueChanged<int> onOpenTab;
  final VoidCallback onOpenMenu;

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  static SupabaseClient get _sb => Supabase.instance.client;

  /// Pano verisinin ham hali (sorgu sonuçları) bellekte ve cihazda
  /// saklanır: ekran açılınca önce saklanan hal anında görünür, taze veri
  /// arkadan gelip sessizce yerine geçer (bekleme ekranı / boş yazı yok).
  static final Map<String, Map<String, dynamic>> _memCache = {};

  _DashData? _data;
  bool _failed = false;

  /// Sunucudan en az bir kez yanıt geldi mi (boş durum yazısı ancak o zaman).
  bool _loadedOnce = false;
  String? _loadedFor;
  String? _followedTeamId;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Geri sayım ve canlı durum dakikada bir yenilensin.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String get _followKey => 'followed_team_${widget.league.id}';

  String _cacheKey(AppSessionState session) =>
      'dash_cache_${widget.league.id}_${session.user?.id ?? 'guest'}';

  void _ensureLoaded(AppSessionState session) {
    final key = _cacheKey(session);
    if (_loadedFor == key) return;
    _loadedFor = key;
    final mem = _memCache[key];
    _data = mem == null ? null : _build(mem, session);
    // Çizim bittikten sonra (build içinde setState olmasın).
    scheduleMicrotask(() => _revalidate(session, key, fromDisk: mem == null));
  }

  Future<void> _refresh() async {
    final session = AppSession.of(context).value;
    await _revalidate(session, _cacheKey(session), fromDisk: false);
  }

  Future<void> _revalidate(
    AppSessionState session,
    String key, {
    required bool fromDisk,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _followedTeamId = prefs.getString(_followKey);
    if (fromDisk && _data == null) {
      try {
        final raw = prefs.getString(key);
        if (raw != null) {
          final cached = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          _memCache[key] = cached;
          if (mounted && _loadedFor == key) {
            setState(() => _data = _build(cached, session));
          }
        }
      } catch (_) {}
    }
    try {
      final raw = await _fetchRaw(session);
      _memCache[key] = raw;
      if (mounted && _loadedFor == key) {
        setState(() {
          _data = _build(raw, session);
          _failed = false;
          _loadedOnce = true;
        });
      }
      try {
        await prefs.setString(key, jsonEncode(raw));
      } catch (_) {}
    } catch (e) {
      debugPrint('Pano yüklenemedi: $e');
      if (mounted) {
        setState(() {
          _failed = true;
          _loadedOnce = true;
        });
      }
    }
  }

  /// Sorgular: sezon (1 tur), ardından geri kalan her şey paralel (1 tur).
  Future<Map<String, dynamic>> _fetchRaw(AppSessionState session) async {
    final leagueId = widget.league.id;
    final seasons = await _sb
        .from('seasons')
        .select('id, name, is_active, start_date')
        .eq('league_id', leagueId)
        .order('is_active', ascending: false)
        .order('start_date', ascending: false)
        .limit(1);
    if (seasons.isEmpty) return {'season': null};
    final season = seasons.first;
    final seasonId = season['id'].toString();
    final playerId = session.playerId ?? '';
    final isOwner =
        session.isAdmin || session.ownedLeagueIds.contains(leagueId);

    Future<List<dynamic>> none() async => const [];
    final r = await Future.wait<dynamic>([
      _sb
          .from('season_teams')
          .select('team_id, group_id, teams(id, name, logo_url, first_color)')
          .eq('season_id', seasonId),
      _sb
          .from('groups')
          .select('id, name, season_regions(name)')
          .eq('season_id', seasonId),
      _sb.from('matches').select('*, pitches(name)').eq('season_id', seasonId),
      _sb
          .from('match_events')
          .select(
            'player_id, assist_player_id, team_id, is_own_goal, '
            'scorer:players!match_events_player_id_fkey(name, surname, photo_url), '
            'assister:players!match_events_assist_player_id_fkey(name, surname, photo_url)',
          )
          .eq('season_id', seasonId)
          .eq('event_type', 'goal'),
      _sb
          .from('leagues')
          .select('roster_open_hours')
          .eq('id', leagueId)
          .maybeSingle(),
      playerId.isEmpty
          ? none()
          : _sb
                .from('season_team_players')
                .select('team_id')
                .eq('season_id', seasonId)
                .eq('player_id', playerId)
                .eq('is_active', true),
      playerId.isEmpty
          ? none()
          : _sb
                .from('player_penalties')
                .select('remaining_matches, match_count')
                .eq('season_id', seasonId)
                .eq('player_id', playerId)
                .eq('status', 'approved')
                .eq('is_active', true),
      isOwner
          ? _sb
                .from('player_penalties')
                .select('id')
                .eq('season_id', seasonId)
                .eq('status', 'pending')
          : none(),
    ]);
    return {
      'season': season,
      'season_teams': r[0],
      'groups': r[1],
      'matches': r[2],
      'events': r[3],
      'open_hours': (r[4] as Map?)?['roster_open_hours'],
      'my_player_teams': r[5],
      'my_penalties': r[6],
      'pending': (r[7] as List).length,
    };
  }

  /// Ham veriden pano modeli (önbellekten de aynı yol).
  _DashData? _build(Map<String, dynamic> raw, AppSessionState session) {
    final season = raw['season'] as Map?;
    if (season == null) return null;
    final seasonId = season['id'].toString();

    final teams = <String, _TeamInfo>{};
    for (final r in (raw['season_teams'] as List? ?? const [])) {
      final t = (r['teams'] as Map?) ?? const {};
      final id = (r['team_id'] ?? '').toString();
      if (id.isEmpty) continue;
      teams[id] = _TeamInfo(
        id: id,
        name: (t['name'] ?? '').toString(),
        logoUrl: (t['logo_url'] ?? '').toString(),
        color: _TeamInfo._hex(t['first_color']),
        groupId: r['group_id']?.toString(),
      );
    }

    final groups = <String, String>{};
    final groupRegion = <String, String>{};
    for (final g in (raw['groups'] as List? ?? const [])) {
      final id = g['id'].toString();
      groups[id] = (g['name'] ?? '').toString();
      final region = (g['season_regions'] as Map?)?['name'];
      if (region != null) groupRegion[id] = region.toString();
    }

    final matches = <MatchModel>[
      for (final m in (raw['matches'] as List? ?? const []))
        MatchModel.fromMap(
          Map<String, dynamic>.from(m as Map)
            ..['pitch_name'] = (m['pitches'] as Map?)?['name'],
          m['id'].toString(),
        ),
    ];

    final scorerMap = <String, _Scorer>{};
    final assistMap = <String, _Scorer>{};
    var totalGoals = 0;
    void bump(Map<String, _Scorer> into, String pid, Map? p, String teamId) {
      if (pid.isEmpty) return;
      into
          .putIfAbsent(
            pid,
            () => _Scorer(
              pid,
              '${p?['name'] ?? ''} ${p?['surname'] ?? ''}'.trim(),
              teamId,
              (p?['photo_url'] ?? '').toString(),
            ),
          )
          .goals++;
    }

    for (final e in (raw['events'] as List? ?? const [])) {
      totalGoals++;
      if (e['is_own_goal'] == true) continue;
      final team = (e['team_id'] ?? '').toString();
      bump(scorerMap, (e['player_id'] ?? '').toString(), e['scorer'], team);
      bump(
        assistMap,
        (e['assist_player_id'] ?? '').toString(),
        e['assister'],
        team,
      );
    }
    List<_Scorer> ranked(Map<String, _Scorer> m) =>
        m.values.toList()..sort((a, b) {
          final c = b.goals.compareTo(a.goals);
          return c != 0 ? c : a.name.compareTo(b.name);
        });

    // Kişinin bu sezondaki takım(lar)ı: oyuncu kaydı + sorumlusu olduğu.
    final myTeams = <String>{
      for (final m in session.managedTeams)
        if (m.seasonId == seasonId) m.teamId,
      if (session.teamId != null && teams.containsKey(session.teamId))
        session.teamId!,
      for (final r in (raw['my_player_teams'] as List? ?? const []))
        r['team_id'].toString(),
    };
    var activePenalty = 0;
    for (final p in (raw['my_penalties'] as List? ?? const [])) {
      activePenalty +=
          ((p['remaining_matches'] ?? p['match_count']) as num?)?.toInt() ?? 0;
    }

    return _DashData(
      seasonId: seasonId,
      seasonName: (season['name'] ?? '').toString(),
      openHours: (raw['open_hours'] as num?)?.toInt() ?? 1,
      teams: teams,
      groups: groups,
      groupRegion: groupRegion,
      matches: matches,
      myTeamIds: myTeams,
      scorers: ranked(scorerMap),
      assisters: ranked(assistMap),
      totalGoals: totalGoals,
      activePenaltyMatches: activePenalty,
      pendingPenalties: (raw['pending'] as num?)?.toInt() ?? 0,
    );
  }

  // ---- Yardımcılar ----------------------------------------------------

  /// Maç başlangıcı (Türkiye saati, UTC+3) UTC olarak.
  static DateTime? _kickoff(MatchModel m) {
    final d = DateTime.tryParse((m.matchDate ?? '').trim());
    final t = RegExp(
      r'^(\d{1,2}):(\d{2})',
    ).firstMatch((m.matchTime ?? '').trim());
    if (d == null) return null;
    final h = t == null ? 0 : int.parse(t.group(1)!);
    final min = t == null ? 0 : int.parse(t.group(2)!);
    return DateTime.utc(
      d.year,
      d.month,
      d.day,
      h,
      min,
    ).subtract(const Duration(hours: 3));
  }

  static bool _isLive(MatchModel m) =>
      m.status == MatchStatus.live || m.status == MatchStatus.halftime;

  static const _days = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
  static const _daysLong = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];

  static DateTime _tr(DateTime utc) => utc.add(const Duration(hours: 3));

  String _countdown(DateTime kickoffUtc) {
    final d = kickoffUtc.difference(DateTime.now().toUtc());
    if (d.isNegative) return 'Başladı';
    if (d.inDays >= 1) return '${d.inDays}g ${d.inHours % 24}s kaldı';
    if (d.inHours >= 1) return '${d.inHours}s ${d.inMinutes % 60}dk kaldı';
    return '${d.inMinutes}dk kaldı';
  }

  void _openMatch(MatchModel m, {int tab = 0}) {
    final isAdmin = AppSession.of(context).value.isAdmin;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MatchDetailsScreen(
          match: m,
          isAdmin: isAdmin,
          initialTabIndex: tab,
        ),
      ),
    );
  }

  Future<void> _pickFollowedTeam(_DashData data) async {
    final list = data.teams.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: DashColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Takımını seç',
                  style: _barlow(size: 18, weight: FontWeight.w800),
                ),
              ),
              for (final t in list)
                ListTile(
                  leading: TeamBadge(
                    name: t.name,
                    logoUrl: t.logoUrl,
                    color: t.color,
                    size: 34,
                  ),
                  title: Text(t.name, style: _barlow(weight: FontWeight.w700)),
                  subtitle: t.groupId == null
                      ? null
                      : Text(
                          data.groups[t.groupId] ?? '',
                          style: _barlow(size: 12, color: DashColors.muted),
                        ),
                  trailing: t.id == _followedTeamId
                      ? Icon(Icons.check_rounded, color: DashColors.accent())
                      : null,
                  onTap: () => Navigator.pop(ctx, t.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_followKey, picked);
    } catch (_) {}
    if (mounted) setState(() => _followedTeamId = picked);
  }

  // ---- Görünüm --------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final session = AppSession.of(context).value;
    _ensureLoaded(session);
    final data = _data;
    final top = MediaQuery.paddingOf(context).top;
    final Widget content;
    if (data != null) {
      content = Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
        child: _body(session, data),
      );
    } else if (!_loadedOnce) {
      // İlk yükleme: yazı yerine iskelet (sonradan değişen metin yok).
      content = _skeleton();
    } else if (_failed) {
      content = _message('Veriler yüklenemedi. Aşağı çekip yenileyin.');
    } else {
      content = _message('Bu turnuvada henüz sezon yok.');
    }
    return RefreshIndicator(
      color: DashColors.accent(),
      onRefresh: _refresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(0, top, 0, 24),
        children: [_greeting(session, data), content],
      ),
    );
  }

  Widget _skeleton() {
    Widget block(double h) => Container(
      height: h,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: DashColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
      child: Column(
        children: [block(190), block(84), block(56), block(56), block(150)],
      ),
    );
  }

  Widget _message(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 60, 24, 0),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: _barlow(color: DashColors.muted),
    ),
  );

  Widget _greeting(AppSessionState session, _DashData? data) {
    final loggedIn = session.user != null && !session.user!.isAnonymous;
    final first = (session.displayName ?? '').trim().split(' ').first;
    final myGroup = data == null ? null : _myGroupId(data);
    final sub = !loggedIn
        ? 'Misafir girişi'
        : [
            if (data != null && data.seasonName.isNotEmpty) data.seasonName,
            if (myGroup != null)
              data!.groupRegion[myGroup] ?? data.groups[myGroup] ?? '',
          ].where((s) => s.isNotEmpty).join(' · ');
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 10, 8, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            DashColors.primary(),
            DashColors.ground.withValues(alpha: 0),
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Menü',
            onPressed: widget.onOpenMenu,
            icon: const Icon(Icons.menu_rounded, color: Colors.white),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loggedIn && first.isNotEmpty
                      ? 'Merhaba, $first'
                      : 'Hoş geldin',
                  style: _barlow(size: 18, weight: FontWeight.w800),
                ),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _barlow(size: 12, color: Colors.white70),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Kişinin (ya da takip ettiği takımın) grubu.
  String? _myGroupId(_DashData d) {
    for (final id in [...d.myTeamIds, ?_followedTeamId]) {
      final g = d.teams[id]?.groupId;
      if (g != null) return g;
    }
    return null;
  }

  Widget _body(AppSessionState session, _DashData d) {
    final focusTeams = d.myTeamIds.isNotEmpty
        ? d.myTeamIds
        : {?_followedTeamId}.where(d.teams.containsKey).toSet();
    final myGroup = _myGroupId(d);
    final groupFilter =
        myGroup ?? (d.groups.length == 1 ? d.groups.keys.first : null);

    final sorted = [...d.matches]
      ..sort((a, b) {
        final ka = _kickoff(a), kb = _kickoff(b);
        if (ka == null || kb == null) {
          return (a.week ?? 0).compareTo(b.week ?? 0);
        }
        return ka.compareTo(kb);
      });
    bool inGroup(MatchModel m) =>
        groupFilter == null || m.groupId == groupFilter;

    // Sıradaki maç: odak takımın bitmemiş ilk maçı.
    MatchModel? next;
    for (final m in sorted) {
      if (m.status == MatchStatus.finished ||
          m.status == MatchStatus.cancelled) {
        continue;
      }
      if (focusTeams.contains(m.homeTeamId) ||
          focusTeams.contains(m.awayTeamId)) {
        next = m;
        break;
      }
    }

    // Bu hafta: canlı ya da oynanmamış maçı olan ilk hafta.
    final openWeeks = sorted
        .where((m) => m.status != MatchStatus.finished && inGroup(m))
        .map((m) => m.week ?? 0)
        .toList();
    final thisWeek = openWeeks.isEmpty
        ? null
        : openWeeks.reduce((a, b) => a < b ? a : b);
    final thisWeekMatches = thisWeek == null
        ? const <MatchModel>[]
        : sorted.where((m) => m.week == thisWeek && inGroup(m)).toList();

    final finishedWeeks = sorted
        .where((m) => m.status == MatchStatus.finished && inGroup(m))
        .map((m) => m.week ?? 0)
        .toList();
    final lastWeek = finishedWeeks.isEmpty
        ? null
        : finishedWeeks.reduce((a, b) => a > b ? a : b);
    final lastWeekMatches = lastWeek == null
        ? const <MatchModel>[]
        : sorted
              .where((m) => m.week == lastWeek && inGroup(m))
              .toList()
              .reversed
              .toList();

    final hasOwnTeam = d.myTeamIds.isNotEmpty;
    final isOwner =
        session.isAdmin || session.ownedLeagueIds.contains(widget.league.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!hasOwnTeam) ...[
          _summaryCard(d, thisWeek, showFollow: true),
          const SizedBox(height: 12),
        ],
        if (next != null) ...[
          _nextMatchCard(session, d, next),
          const SizedBox(height: 12),
        ],
        if (d.activePenaltyMatches > 0) ...[
          _alert('Cezalısın: ${d.activePenaltyMatches} maç daha oynayamazsın.'),
          const SizedBox(height: 12),
        ],
        if (isOwner && d.pendingPenalties > 0) ...[
          _alert(
            '${d.pendingPenalties} kart cezası onayını bekliyor '
            '(Yönetim › Cezalar).',
          ),
          const SizedBox(height: 12),
        ],
        // Son dakika haber kartı (mevcut bileşen).
        HomeNewsCard(onOpenNews: widget.onOpenNews),
        if (thisWeekMatches.isNotEmpty) ...[
          _sectionHeader(
            'BU HAFTA · $thisWeek. HAFTA',
            'Fikstür',
            () => widget.onOpenTab(2),
          ),
          for (final m in thisWeekMatches) _matchRow(d, m, focusTeams),
        ],
        if (groupFilter != null || d.groups.isNotEmpty) ...[
          _sectionHeader('PUAN DURUMU', 'Tamamı', () => widget.onOpenTab(3)),
          _miniStandings(d, groupFilter ?? d.groups.keys.first, focusTeams),
        ],
        if (d.scorers.isNotEmpty) ...[
          _sectionHeader(
            'GOL KRALLIĞI',
            'İstatistik',
            () => widget.onOpenTab(4),
          ),
          _leaders(d, d.scorers, 'gol'),
        ],
        if (d.assisters.isNotEmpty) ...[
          _sectionHeader(
            'ASİST KRALLIĞI',
            'İstatistik',
            () => widget.onOpenTab(4),
          ),
          _leaders(d, d.assisters, 'asist'),
        ],
        if (lastWeekMatches.isNotEmpty) ...[
          _sectionHeader(
            'GEÇEN HAFTA · $lastWeek. HAFTA',
            'Sonuçlar',
            () => widget.onOpenTab(2),
          ),
          for (final m in lastWeekMatches.take(4)) _matchRow(d, m, focusTeams),
        ],
      ],
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding, Color? border}) =>
      Container(
        padding: padding ?? const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: DashColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: border == null ? null : Border.all(color: border),
        ),
        child: child,
      );

  Widget _sectionHeader(String title, String action, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 0, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: _barlow(
                size: 13,
                weight: FontWeight.w800,
                color: DashColors.muted,
                spacing: 0.6,
              ),
            ),
          ),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                '$action ›',
                style: _barlow(
                  size: 12,
                  weight: FontWeight.w700,
                  color: DashColors.accent(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _alert(String text) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: DashColors.live.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DashColors.live.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 17,
            decoration: BoxDecoration(
              color: DashColors.red,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: _barlow(size: 13, weight: FontWeight.w700, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(_DashData d, int? week, {required bool showFollow}) {
    final finished = d.matches
        .where((m) => m.status == MatchStatus.finished)
        .length;
    final logo = widget.league.logoUrl.trim();
    final followed = _followedTeamId == null ? null : d.teams[_followedTeamId];
    Widget stat(String value, String label) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value, style: _condensed(size: 22)),
            const SizedBox(height: 2),
            Text(label, style: _barlow(size: 11, color: DashColors.muted)),
          ],
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, 0.75],
          colors: [DashColors.primary(), DashColors.surface],
        ),
        border: Border.all(color: DashColors.accent().withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TeamBadge(
                name: widget.league.name,
                logoUrl: logo,
                color: DashColors.accent(),
                size: 52,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.league.name,
                      style: _barlow(size: 16, weight: FontWeight.w800),
                    ),
                    Text(
                      [
                        d.seasonName,
                        if (week != null) '$week. Hafta oynanıyor',
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: _barlow(size: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              stat('${d.teams.length}', 'Takım'),
              const SizedBox(width: 8),
              stat('$finished', 'Maç'),
              const SizedBox(width: 8),
              stat('${d.totalGoals}', 'Gol'),
            ],
          ),
          if (showFollow) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: DashColors.accent(),
                  foregroundColor: DashColors.onAccent(),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _pickFollowedTeam(d),
                child: Text(
                  followed == null
                      ? 'Takımımı takip et'
                      : 'Takip: ${followed.name} · değiştir',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _barlow(
                    size: 13,
                    weight: FontWeight.w800,
                    color: DashColors.onAccent(),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _nextMatchCard(AppSessionState session, _DashData d, MatchModel m) {
    final home = d.teams[m.homeTeamId];
    final away = d.teams[m.awayTeamId];
    final kickoff = _kickoff(m);
    final live = _isLive(m);
    final hasTime = RegExp(
      r'^\d{1,2}:\d{2}',
    ).hasMatch((m.matchTime ?? '').trim());
    final openAt = kickoff == null || !hasTime
        ? null
        : kickoff.subtract(Duration(hours: d.openHours));
    final now = DateTime.now().toUtc();
    final managesThis =
        d.myTeamIds.contains(m.homeTeamId) &&
            session.managesTeam(m.seasonId, m.homeTeamId) ||
        d.myTeamIds.contains(m.awayTeamId) &&
            session.managesTeam(m.seasonId, m.awayTeamId);

    String esame;
    var esameOpen = false;
    if (openAt == null) {
      esame = 'Maç saati belli olunca esame zamanı görünür';
    } else if (now.isBefore(openAt)) {
      final t = _tr(openAt);
      esame =
          'Esame ${_days[t.weekday - 1]} ${DateFormat('HH:mm').format(t)}\'de açılır';
    } else {
      esameOpen = true;
      esame = managesThis ? 'Esame açık · kadronu gir' : 'Esame açık';
    }

    Widget side(_TeamInfo? t) => Expanded(
      child: Column(
        children: [
          TeamBadge(
            name: t?.name ?? '?',
            logoUrl: t?.logoUrl ?? '',
            color: t?.color,
            size: 52,
          ),
          const SizedBox(height: 6),
          Text(
            t?.name ?? '-',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _barlow(size: 13, weight: FontWeight.w800),
          ),
        ],
      ),
    );

    final accent = DashColors.accent();
    final kTr = kickoff == null ? null : _tr(kickoff);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, 0.8],
          colors: [DashColors.primary(), DashColors.surface],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'SIRADAKİ MAÇIN${m.week == null ? '' : ' · ${m.week}. HAFTA'}',
                  style: _barlow(
                    size: 12,
                    weight: FontWeight.w800,
                    color: accent,
                    spacing: 0.6,
                  ),
                ),
              ),
              if (live)
                _pill('● CANLI', DashColors.live)
              else if (kickoff != null)
                _pill(
                  _countdown(kickoff),
                  Colors.white.withValues(alpha: 0.12),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              side(home),
              SizedBox(
                width: 92,
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      live
                          ? '${m.homeScore} – ${m.awayScore}'
                          : (hasTime ? m.matchTime!.substring(0, 5) : '--:--'),
                      style: _condensed(
                        size: 30,
                        color: live ? Colors.white : accent,
                      ),
                    ),
                    Text(
                      kTr == null ? 'Tarih yok' : _daysLong[kTr.weekday - 1],
                      style: _barlow(size: 12, color: DashColors.muted),
                    ),
                  ],
                ),
              ),
              side(away),
            ],
          ),
          if ((m.pitchName ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.place_outlined,
                  size: 15,
                  color: DashColors.muted,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    m.pitchName!,
                    overflow: TextOverflow.ellipsis,
                    style: _barlow(size: 12, color: DashColors.muted),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                esameOpen ? Icons.lock_open_rounded : Icons.lock_clock_rounded,
                size: 16,
                color: esameOpen ? accent : DashColors.muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  esame,
                  style: _barlow(
                    size: 12.5,
                    weight: FontWeight.w700,
                    color: esameOpen ? DashColors.text : DashColors.muted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 36,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: DashColors.onAccent(),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  // Esame açıksa takım sorumlusu doğrudan Kadrolar sekmesine.
                  onPressed: () =>
                      _openMatch(m, tab: managesThis && esameOpen ? 1 : 0),
                  child: Text(
                    managesThis && esameOpen ? 'Esame' : 'Maç detayı',
                    style: _barlow(
                      size: 12.5,
                      weight: FontWeight.w800,
                      color: DashColors.onAccent(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color bg) => Container(
    height: 24,
    padding: const EdgeInsets.symmetric(horizontal: 9),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: _barlow(size: 11, weight: FontWeight.w800, color: Colors.white),
    ),
  );

  Widget _matchRow(_DashData d, MatchModel m, Set<String?> focus) {
    final home = d.teams[m.homeTeamId];
    final away = d.teams[m.awayTeamId];
    final kickoff = _kickoff(m);
    final live = _isLive(m);
    final finished = m.status == MatchStatus.finished;
    final mine = focus.contains(m.homeTeamId) || focus.contains(m.awayTeamId);

    Widget center;
    if (live || finished) {
      center = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${m.homeScore} – ${m.awayScore}', style: _condensed(size: 20)),
          Text(
            live ? '● CANLI' : 'BİTTİ',
            style: _barlow(
              size: 10,
              weight: FontWeight.w800,
              color: live ? DashColors.live : DashColors.finished,
            ),
          ),
        ],
      );
    } else {
      final t = kickoff == null ? null : _tr(kickoff);
      final hasTime = RegExp(
        r'^\d{1,2}:\d{2}',
      ).hasMatch((m.matchTime ?? '').trim());
      center = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hasTime ? m.matchTime!.substring(0, 5) : '--:--',
            style: _barlow(
              size: 14,
              weight: FontWeight.w800,
              color: DashColors.accent(),
            ),
          ),
          Text(
            t == null ? '' : _trUpper(_days[t.weekday - 1]),
            style: _barlow(
              size: 10,
              weight: FontWeight.w700,
              color: DashColors.muted,
            ),
          ),
        ],
      );
    }

    Widget name(_TeamInfo? t, {required bool end}) => Expanded(
      child: Row(
        mainAxisAlignment: end
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!end) ...[
            TeamBadge(
              name: t?.name ?? '?',
              logoUrl: t?.logoUrl ?? '',
              color: t?.color,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              t?.name ?? '-',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: end ? TextAlign.right : TextAlign.left,
              style: _barlow(size: 13, weight: FontWeight.w700),
            ),
          ),
          if (end) ...[
            const SizedBox(width: 8),
            TeamBadge(
              name: t?.name ?? '?',
              logoUrl: t?.logoUrl ?? '',
              color: t?.color,
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: DashColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openMatch(m),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: mine
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: DashColors.accent().withValues(alpha: 0.6),
                    ),
                  )
                : null,
            child: Row(
              children: [
                name(home, end: true),
                SizedBox(width: 68, child: Center(child: center)),
                name(away, end: false),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniStandings(_DashData d, String groupId, Set<String?> focus) {
    final rows = computeGroupStandings(
      leagueId: d.seasonId,
      groupId: groupId,
      groupName: d.groups[groupId] ?? '',
      seasonMatches: [
        for (final m in d.matches)
          {
            'group_id': m.groupId,
            'home_team_id': m.homeTeamId,
            'away_team_id': m.awayTeamId,
            'home_score': m.homeScore,
            'away_score': m.awayScore,
            'status': m.status == MatchStatus.finished ? 'finished' : '',
          },
      ],
      allTeams: [
        for (final t in d.teams.values)
          Team(
            id: t.id,
            name: t.name,
            logoUrl: t.logoUrl,
            seasonId: d.seasonId,
            groupId: t.groupId,
          ),
      ],
    );
    final title = d.groupRegion[groupId] ?? d.groups[groupId] ?? '';
    final head = _barlow(
      size: 11,
      weight: FontWeight.w800,
      color: DashColors.muted,
    );
    Widget cell(String s, TextStyle st, {double w = 30}) => SizedBox(
      width: w,
      child: Text(s, textAlign: TextAlign.center, style: st),
    );

    return _card(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: head)),
              cell('O', head),
              cell('AV', head, w: 36),
              cell('P', head),
            ],
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < rows.length && i < 4; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: Text(
                      '${i + 1}',
                      style: _condensed(
                        size: 15,
                        color: i == 0 ? DashColors.accent() : DashColors.muted,
                      ),
                    ),
                  ),
                  TeamBadge(
                    name: rows[i].name,
                    logoUrl: rows[i].logo,
                    color: d.teams[rows[i].teamId]?.color,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rows[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _barlow(
                        size: 13,
                        weight: focus.contains(rows[i].teamId)
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: focus.contains(rows[i].teamId)
                            ? DashColors.accent()
                            : DashColors.text,
                      ),
                    ),
                  ),
                  cell(
                    '${rows[i].played}',
                    _barlow(size: 13, color: DashColors.muted),
                  ),
                  cell(
                    rows[i].goalDiff > 0
                        ? '+${rows[i].goalDiff}'
                        : '${rows[i].goalDiff}',
                    _barlow(size: 13, color: DashColors.muted),
                    w: 36,
                  ),
                  cell('${rows[i].points}', _condensed(size: 16)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// İlk 3 oyuncu: fotoğrafı varsa fotoğraf, yoksa baş harf; dokununca
  /// oyuncu kartı.
  Widget _leaders(_DashData d, List<_Scorer> list, String unit) {
    final top = list.take(3).toList();
    return _card(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Column(
        children: [
          for (var i = 0; i < top.length; i++)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => showPlayerCard(context, playerKey: top[i].playerId),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: i == 0
                    ? null
                    : BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                      ),
                child: Row(
                  children: [
                    _avatar(top[i], highlight: i == 0),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            top[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _barlow(size: 14, weight: FontWeight.w700),
                          ),
                          Text(
                            d.teams[top[i].teamId]?.name ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _barlow(size: 12, color: DashColors.muted),
                          ),
                        ],
                      ),
                    ),
                    Text('${top[i].goals}', style: _condensed(size: 24)),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 30,
                      child: Text(
                        unit,
                        style: _barlow(size: 11, color: DashColors.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _avatar(_Scorer p, {required bool highlight}) {
    final ring = highlight ? DashColors.accent() : Colors.white24;
    final initial = Container(
      alignment: Alignment.center,
      color: highlight ? DashColors.accent() : const Color(0xFF334155),
      child: Text(
        p.name.isEmpty ? '?' : _trUpper(p.name[0]),
        style: _condensed(
          size: 16,
          color: highlight ? DashColors.onAccent() : Colors.white,
        ),
      ),
    );
    return Container(
      width: 38,
      height: 38,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(shape: BoxShape.circle, color: ring),
      child: ClipOval(
        child: p.photoUrl.isEmpty
            ? initial
            : WebSafeImage(
                url: p.photoUrl,
                width: 35,
                height: 35,
                fit: BoxFit.cover,
              ),
      ),
    );
  }
}
