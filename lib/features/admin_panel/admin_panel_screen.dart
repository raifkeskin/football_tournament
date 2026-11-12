import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/app_session.dart';
import '../media_credits/match_crew_sheet.dart';
import '../media_credits/media_credit.dart';
import '../../core/services/app_settings.dart';
import '../../core/services/service_locator.dart';
import '../../core/services/active_tournament.dart';
import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import '../../core/utils/team_name.dart';
import '../../core/widgets/app_name_band.dart';
import '../match/widgets/match_highlights_section.dart';
import '../match/widgets/match_schedule_dialog.dart';
import '../referees/match_referee_picker.dart';
import '../share/pre_match_video.dart';
import '../videos/videos.dart';
import '../home/widgets/overdue_results_banner.dart';
import '../home/widgets/unassigned_referees_banner.dart';
import '../home/widgets/unscheduled_matches_banner.dart';
import '../identity/ibraz_pending_screen.dart';
import '../news/screens/week_awards_screen.dart';
import '../news/week_awards.dart';
import '../tournament/models/league.dart';
import '../tournament/screens/admin_penalty_management_screen.dart';
import '../news/news_talk.dart';
import '../news/screens/news_screens.dart';
import '../news/widgets/news_talk_widgets.dart';
import '../match/models/match.dart';
import '../match/screens/esame_edit_screen.dart';
import '../match/screens/match_details_screen.dart';

/// Menüdeki Yönetim Paneli: admin, kurucu başkan, bölge sorumlusu.
/// Ayar kapalıyken (admin_panel_enabled) yalnız admin görür.
class AdminPanelAccess {
  AdminPanelAccess._();

  static Listenable get changes => AppSettings.adminPanelEnabled;

  static bool visible(AppSessionState s) {
    final u = s.user;
    if (u == null || u.isAnonymous) return false;
    if (s.isAdmin) return true;
    return s.hasManagementPanel && AppSettings.adminPanelEnabled.value;
  }
}

/// Ana sayfada sponsor şeridinin altındaki ince geçiş şeridi.
class AdminPanelStrip extends StatelessWidget {
  const AdminPanelStrip({super.key, this.leagueId});

  /// Ana sayfada seçili turnuva; panel bu turnuvayla açılır.
  final String? leagueId;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF0F2E25),
    child: InkWell(
      onTap: () => AdminPanelScreen.open(context, leagueId: leagueId),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x5510B981))),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.dashboard_customize_rounded,
              size: 16,
              color: _greenText,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Yönetim Panelini aç',
                style: TextStyle(
                  color: _greenText,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: _greenText),
          ],
        ),
      ),
    ),
  );
}

/// Panel yetkisi olana uygulama açılışında panel bir kez kendiliğinden
/// açılır.
class AdminPanelAutoOpen {
  AdminPanelAutoOpen._();

  static bool _done = false;

  static void maybeOpen(
    BuildContext context,
    AppSessionState s, {
    String? leagueId,
  }) {
    if (_done || !AdminPanelAccess.visible(s)) return;
    _done = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        AdminPanelScreen.open(context, leagueId: leagueId);
      }
    });
  }
}

const _bg = Color(0xFF0E1626);
const _card = Color(0xFF1A2436);
const _line = Color(0xFF2B3A57);
const _mid = Color(0xFF94A3B8);
const _green = Color(0xFF10B981);
const _greenText = Color(0xFF34D399);
const _amber = Color(0xFFFBBF24);
const _red = Color(0xFFF87171);

class _Scope {
  _Scope(this.leagueId, this.name, this.canAll, this.regions);
  final String leagueId;
  final String name;
  final bool canAll;
  final List<(String, String)> regions;
}

/// Yayın linki uygulama içinde oynatılabilir mi (YouTube oEmbed).
enum _Embed { ok, disabled, missing, unknown }

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key, this.leagueId});

  /// Açılışta seçilecek turnuva (ana sayfada seçili olan); yetki yoksa ilki.
  final String? leagueId;

  static Future<void> open(BuildContext context, {String? leagueId}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'AdminPanelScreen'),
          builder: (_) => AdminPanelScreen(leagueId: leagueId),
        ),
      );

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen>
    with WidgetsBindingObserver {
  final _sb = Supabase.instance.client;
  static final Map<String, _Embed> _embedCache = {};

  List<_Scope> _scopes = const [];
  _Scope? _scope;
  TournamentTheme? _theme;
  String? _regionId;
  List<Map<String, dynamic>> _matches = const [];

  /// Sıradaki maçlar: bugünden sonraki en yakın haftanın oynanmamış maçları.
  List<Map<String, dynamic>> _upcoming = const [];
  bool _loading = true;
  String? _error;

  /// Seçili sekme; boşsa ekran maçı olan sekmeye geçer (önce Canlı).
  int _tab = 1;

  /// Tamamlanan haftalar (Haftanın Enleri sekmesi): hafta, bölge, bülten yayında mı.
  List<({int week, String regionId, String region, String? newsId})> _enler =
      const [];
  String _enlerKey = '';

  /// Yayınlanan bültenlerdeki enler ve Instagram bağlantıları (haber id → enler).
  Map<String, List<({String kind, String title, String url})>> _awardsOf =
      const {};

  /// Kimlik ibrazı onayı bekleyen kayıt sayısı (yetki alanına göre).
  int _ibrazPending = 0;

  /// Bekleyen onaylar kartı: kapanır/açılır (son durum cihazda hatırlanır).
  bool _apOpen = false;
  int _penPending = 0, _newsPending = 0, _commentPending = 0;
  String _apKey = '';
  DateTime? _apAt;

  Future<void> _loadApprovalPref() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getBool('panel_approvals_open') ?? false;
      if (mounted && v != _apOpen) setState(() => _apOpen = v);
    } catch (_) {}
  }

  Future<void> _toggleApprovals() async {
    setState(() => _apOpen = !_apOpen);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('panel_approvals_open', _apOpen);
    } catch (_) {}
  }

  /// Ceza, haber, yorum bekleyen sayıları (seçili turnuva ve bölge).
  /// Sık sorgulanmaz: anahtar değişince ya da 3 dakikada bir.
  Future<void> _loadApprovals({bool force = false}) async {
    final s = _scope;
    if (s == null) return;
    final key = '${s.leagueId}|${_regionId ?? ''}';
    if (!force &&
        key == _apKey &&
        _apAt != null &&
        DateTime.now().difference(_apAt!) < const Duration(minutes: 3)) {
      return;
    }
    _apKey = key;
    _apAt = DateTime.now();
    final region = _regionId;
    var pen = 0, news = 0, com = 0;
    try {
      final seasons = await _sb
          .from('seasons')
          .select('id')
          .eq('league_id', s.leagueId)
          .eq('is_active', true)
          .isFilter('deleted_at', null);
      final sids = [for (final r in seasons) '${r['id']}'];
      if (sids.isNotEmpty) {
        final rows = await _sb
            .from('player_penalties')
            .select('id, match_id')
            .inFilter('season_id', sids)
            .eq('status', 'pending');
        if (region == null) {
          pen = rows.length;
        } else {
          // Maçsız elle girilen ceza her bölgede sayılır.
          final mids = [
            for (final r in rows)
              if (r['match_id'] != null) '${r['match_id']}',
          ];
          var inRegion = 0;
          if (mids.isNotEmpty) {
            final ms = await _sb
                .from('matches')
                .select('id, group_id')
                .inFilter('id', mids);
            final gs = await _sb
                .from('groups')
                .select('id, region_id')
                .inFilter('season_id', sids);
            final regionOf = {
              for (final g in gs) '${g['id']}': '${g['region_id'] ?? ''}',
            };
            final matchRegion = {
              for (final m in ms) '${m['id']}': regionOf['${m['group_id']}'],
            };
            inRegion = mids.where((id) => matchRegion[id] == region).length;
          }
          pen = inRegion + (rows.length - mids.length);
        }
      }
    } catch (_) {}
    try {
      final list = await ServiceLocator.leagueService
          .watchNewsFeed(leagueId: s.leagueId, pending: true)
          .first;
      news = list
          .where(
            (x) =>
                x.tournamentId == s.leagueId &&
                (region == null || x.regionId == null || x.regionId == region),
          )
          .length;
    } catch (_) {}
    try {
      com = await NewsTalkService.pendingCount(s.leagueId);
    } catch (_) {}
    if (!mounted || _apKey != key) return;
    setState(() {
      _penPending = pen;
      _newsPending = news;
      _commentPending = com;
    });
  }

  /// Bütün girişleri tamam olan maçlar özet görünür; dokununca açılır.
  final Set<String> _expanded = {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadApprovalPref();
    _loadScope();
    // Canlı skor ve durumlar için ara ara yenilenir.
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => _loadMatches());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _retry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Arka plandan dönünce bağlantı hazır olana kadar birkaç kez denenir.
  Timer? _retry;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _retry?.cancel();
      _retry = Timer(const Duration(milliseconds: 800), _reload);
    }
  }

  void _reload() => _scope == null ? _loadScope() : _loadMatches();

  /// Bağlantı hatası: eldeki liste korunur, ham hata gösterilmez; kısa
  /// süre sonra yeniden denenir.
  void _failed() {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = _matches.isEmpty
          ? 'Bağlantı kurulamadı, yeniden deneniyor…'
          : null;
    });
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 4), _reload);
  }

  Future<void> _loadScope() async {
    try {
      final raw = await _sb.rpc('admin_panel_scope');
      final list = <_Scope>[
        for (final r in (raw as List? ?? const []))
          if (r is Map)
            _Scope(
              '${r['league_id']}',
              '${r['name'] ?? ''}',
              r['can_all'] == true,
              [
                for (final g in (r['regions'] as List? ?? const []))
                  if (g is Map) ('${g['id']}', '${g['name'] ?? ''}'),
              ],
            ),
      ];
      if (!mounted) return;
      setState(() {
        _scopes = list;
        _scope = list.isEmpty
            ? null
            : list.firstWhere(
                (e) => e.leagueId == widget.leagueId,
                orElse: () => list.first,
              );
        // Admin ve kurucu "Tümü" ile başlar; bölge sorumlusu kendi (ilk)
        // bölgesine sabitlenir.
        final s = _scope;
        _regionId = s == null ? null : _defaultRegion(s);
      });
      _loadTheme();
      await _loadMatches();
    } catch (_) {
      _failed();
    }
  }

  /// Bantta seçili turnuvanın logosu ve adı (ana sayfadaki gibi).
  Future<void> _loadTheme() async {
    final s = _scope;
    if (s == null) return;
    try {
      final r = await _sb
          .from('leagues')
          .select(
            'id, name, short_name, logo_url, theme_primary, theme_secondary',
          )
          .eq('id', s.leagueId)
          .maybeSingle();
      if (r != null && mounted && _scope == s) {
        setState(() => _theme = TournamentTheme.fromRow(r));
      }
    } catch (_) {}
  }

  Future<void> _loadIbraz() async {
    try {
      final n = await _sb.rpc('ibraz_pending_count');
      if (mounted && n is int && n != _ibrazPending) {
        setState(() => _ibrazPending = n);
      }
    } catch (_) {}
  }

  /// Turnuvada maç önü haberi otomatik mi (kapalıysa panelde "kapalı" yazar).
  bool _autoPreview = true;

  /// Sezon Medya sekmesi: kapalıysa ilgili alan kartta hiç görünmez.
  bool _liveOn = true, _bcastOn = true, _photoOn = true;

  Future<void> _loadMatches() async {
    _loadIbraz();
    _loadApprovals();
    final s = _scope;
    if (s == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final raw = await _sb.rpc(
        'admin_panel_matches',
        params: {'p_league_id': s.leagueId, 'p_region_id': _regionId},
      );
      final list = [
        for (final r in (raw as List? ?? const []))
          if (r is Map) Map<String, dynamic>.from(r),
      ];
      if (!mounted) return;
      var up = <Map<String, dynamic>>[];
      try {
        final rawUp = await _sb.rpc(
          'admin_panel_upcoming',
          params: {'p_league_id': s.leagueId, 'p_region_id': _regionId},
        );
        up = [
          for (final r in (rawUp as List? ?? const []))
            if (r is Map) Map<String, dynamic>.from(r),
        ];
      } catch (_) {}
      try {
        final lg = await _sb
            .from('leagues')
            .select('auto_preview_news')
            .eq('id', s.leagueId)
            .maybeSingle();
        _autoPreview = lg?['auto_preview_news'] != false;
      } catch (_) {}
      try {
        final ss = await _sb
            .from('seasons')
            .select(
              'live_stream_enabled, broadcaster_enabled, photographer_enabled',
            )
            .eq('league_id', s.leagueId)
            .eq('is_active', true);
        if (ss.isNotEmpty) {
          bool any(String k) => ss.any((r) => r[k] != false);
          _liveOn = any('live_stream_enabled');
          _bcastOn = any('broadcaster_enabled');
          _photoOn = any('photographer_enabled');
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _matches = list;
        _upcoming = up;
        _loading = false;
        _error = null;
      });
      for (final m in list) {
        _checkEmbed(m['youtube_url'] as String?);
      }
      _loadCrew(list);
      await _loadEnler();
    } catch (_) {
      _failed();
    }
  }

  /// Tüm maçları bitmiş (ertelenen / iptal edilenler bekletmez) son haftalar.
  Future<void> _loadEnler({bool force = false}) async {
    final s = _scope;
    if (s == null) return;
    final key = '${s.leagueId}|${_regionId ?? ''}';
    if (!force && key == _enlerKey) return;
    _enlerKey = key;
    try {
      final seasons = await _sb
          .from('seasons')
          .select('id, is_active, start_date')
          .eq('league_id', s.leagueId)
          .isFilter('deleted_at', null)
          .order('start_date', ascending: false);
      if (seasons.isEmpty) return;
      final season = seasons.firstWhere(
        (x) => x['is_active'] == true,
        orElse: () => seasons.first,
      );
      final sid = season['id'].toString();
      final (matches, groups, news) = await (
        _sb
            .from('matches')
            .select('week, status, group_id')
            .eq('season_id', sid)
            .isFilter('deleted_at', null)
            .not('week', 'is', null),
        _sb.from('groups').select('id, region_id').eq('season_id', sid),
        _sb
            .from('news')
            .select('id, week, region_id, auto_data')
            .eq('season_id', sid)
            .eq('auto_kind', 'week_awards'),
      ).wait;
      final regionOfGroup = {
        for (final g in groups) '${g['id']}': '${g['region_id'] ?? ''}',
      };
      final names = {for (final r in s.regions) r.$1: r.$2};
      // (bölge, hafta) → [biten, bekleyen]
      final stat = <(String, int), List<int>>{};
      for (final m in matches) {
        final r = regionOfGroup['${m['group_id']}'] ?? '';
        if (_regionId != null && r != _regionId) continue;
        final e = stat.putIfAbsent((
          r,
          (m['week'] as num).toInt(),
        ), () => [0, 0]);
        final st = '${m['status']}';
        if (st == 'finished') {
          e[0]++;
        } else if (st != 'cancelled' && st != 'postponed') {
          e[1]++;
        }
      }
      final published = {
        for (final n in news)
          ('${n['region_id'] ?? ''}', (n['week'] as num?)?.toInt() ?? 0):
              '${n['id']}',
      };
      _awardsOf = {
        for (final n in news)
          '${n['id']}': [
            if (n['auto_data'] is Map)
              for (final x
                  in ((n['auto_data'] as Map)['awards'] as List? ?? const []))
                if (x is Map && AwardKindX.of('${x['kind']}') != null)
                  (
                    kind: '${x['kind']}',
                    title: AwardKindX.of('${x['kind']}')!.full,
                    url: '${x['instagram_url'] ?? ''}',
                  ),
          ],
      };
      final list = [
        for (final e in stat.entries)
          if (e.value[0] > 0 && e.value[1] == 0)
            (
              week: e.key.$2,
              regionId: e.key.$1,
              region: names[e.key.$1] ?? '',
              newsId: published[e.key],
            ),
      ];
      // Yalnız mevcut hafta: her bölgenin en son tamamlanan haftası.
      final latest =
          <
            String,
            ({int week, String regionId, String region, String? newsId})
          >{};
      for (final e in list) {
        final cur = latest[e.regionId];
        if (cur == null || e.week > cur.week) latest[e.regionId] = e;
      }
      if (!mounted) return;
      // Bülteni yayınlanan hafta için sekme gösterilmez.
      setState(
        () => _enler = [
          for (final e in latest.values)
            if (e.newsId == null) e,
        ],
      );
    } catch (_) {
      _enlerKey = '';
    }
  }

  bool get _showEnler =>
      AppSession.of(context).value.isAdmin ||
      AppSettings.weekAwardsEnabled.value;

  Future<void> _openEnler() async {
    final s = _scope;
    if (s == null) return;
    try {
      final row = await _sb
          .from('leagues')
          .select()
          .eq('id', s.leagueId)
          .single();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'WeekAwardsScreen'),
          builder: (_) => WeekAwardsScreen(
            tournaments: [League.fromMap(Map<String, dynamic>.from(row))],
          ),
        ),
      );
      _loadEnler(force: true);
    } catch (_) {}
  }

  Widget _enlerCard(
    ({int week, String regionId, String region, String? newsId}) e,
  ) {
    final published = e.newsId != null;
    final awards = published
        ? (_awardsOf[e.newsId] ??
              const <({String kind, String title, String url})>[])
        : const <({String kind, String title, String url})>[];
    final withIg = awards.where((a) => a.url.isNotEmpty).length;
    final title = '${e.week}. hafta${e.region.isEmpty ? '' : ' · ${e.region}'}';
    return _shell(
      border: published ? null : _amber.withValues(alpha: 0.5),
      head: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Row(
          children: [
            const Icon(Icons.military_tech_rounded, color: _amber, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              published ? 'Yayında' : 'Hazırlanmadı',
              style: TextStyle(
                color: published ? _greenText : _amber,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
      children: [
        Text(
          published
              ? 'Haftanın enleri bülteni yayınlandı; yayınlanan bülten '
                    'değiştirilmez. Turnuva sahipleri Instagram\'da bir en için '
                    'video paylaştıysa (ör. kurtarış) onu o enin 2. sayfası '
                    'olarak ekleyebilirsin.'
              : 'Bu haftanın bütün maçları bitti. Haftanın 11\'ini ve enlerini '
                    'seçip bülten olarak yayınlayabilirsin.',
          style: const TextStyle(color: _mid, fontSize: 13.5, height: 1.4),
        ),
        const SizedBox(height: 10),
        if (!published)
          FilledButton.icon(
            onPressed: _openEnler,
            icon: const Icon(Icons.military_tech_rounded, size: 18),
            label: const Text('Enleri seç ve yayınla'),
          )
        else
          OutlinedButton.icon(
            onPressed: awards.isEmpty
                ? null
                : () => _editInstagram(e.newsId!, awards),
            icon: const Icon(Icons.camera_alt_outlined, size: 18),
            label: Text(
              withIg == 0
                  ? 'Instagram videosu ekle'
                  : 'Instagram videoları · $withIg',
            ),
          ),
      ],
    );
  }

  /// Yayınlanan bültenin tek değiştirilebilen yeri: Instagram bağlantısı.
  Future<void> _editInstagram(
    String newsId,
    List<({String kind, String title, String url})> awards,
  ) async {
    final saved = await showAdminPopup<String>(
      context: context,
      builder: (_) => _InstagramLinkForm(newsId: newsId, awards: awards),
    );
    if (saved != null) {
      _loadEnler(force: true);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(saved)));
      }
    }
  }

  Future<void> _checkEmbed(String? url) async {
    final u = (url ?? '').trim();
    if (u.isEmpty || _embedCache.containsKey(u)) return;
    if (!u.contains('youtu')) {
      _embedCache[u] = _Embed.unknown;
      return;
    }
    // Web'de tarayıcı engelleyebilir; sonuç alınamazsa uyarı çıkmaz.
    try {
      final res = await http
          .get(
            Uri.parse(
              'https://www.youtube.com/oembed?format=json&url='
              '${Uri.encodeComponent(u)}',
            ),
          )
          .timeout(const Duration(seconds: 8));
      _embedCache[u] = switch (res.statusCode) {
        200 => _Embed.ok,
        401 || 403 => _Embed.disabled,
        404 || 400 => _Embed.missing,
        _ => _Embed.unknown,
      };
    } catch (_) {
      _embedCache[u] = _Embed.unknown;
    }
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------- yardım

  bool _isPre(Map m) =>
      m['status'] == 'notStarted' || m['status'] == 'postponed';
  bool _isLive(Map m) => m['status'] == 'live' || m['status'] == 'halftime';
  bool _isPost(Map m) => m['status'] == 'finished';

  int _n(Map m, String k) => (m[k] as num?)?.toInt() ?? 0;

  Future<MatchModel?> _model(String id) async {
    try {
      return await ServiceLocator.matchService.watchMatch(id).first;
    } catch (_) {
      return null;
    }
  }

  Future<void> _openMatch(String id, {int tab = 0}) async {
    final m = await _model(id);
    if (m == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'MatchDetailsScreen'),
        builder: (_) => MatchDetailsScreen(
          match: m,
          isAdmin: AppSession.of(context).value.isAdmin,
          initialTabIndex: tab,
        ),
      ),
    );
    _loadMatches();
  }

  Future<void> _openEsame(Map row, bool home, {required bool scan}) async {
    final m = await _model('${row['id']}');
    if (m == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EsameEditScreen(
          match: m,
          teamId: home ? m.homeTeamId : m.awayTeamId,
          teamName: '${row[home ? 'home' : 'away'] ?? ''}',
          isHome: home,
          autoScan: scan,
        ),
      ),
    );
    _loadMatches();
  }

  // ------------------------------------------- panel içi işlemler

  Future<void> _referee(String id) async {
    final m = await _model(id);
    if (m == null || !mounted) return;
    await showMatchRefereePicker(context, m);
    _loadMatches();
  }

  Future<void> _schedule(String id) async {
    final m = await _model(id);
    if (m == null || !mounted) return;
    await showMatchScheduleDialog(
      context,
      match: m,
      onDataChanged: _loadMatches,
    );
  }

  Future<void> _media(String id, {bool liveLink = false, String? type}) async {
    final m = await _model(id);
    if (m == null || !mounted) return;
    await showMatchMediaAdder(
      context,
      match: m,
      liveLinkOnly: liveLink,
      initialType: type,
      onSuccess: _loadMatches,
    );
  }

  Future<void> _interview(Map row) async {
    final ok = await showAddVideoDialog(
      context,
      match: VideoMatchRef(
        id: '${row['id']}',
        homeId: '${row['home_id']}',
        homeName: '${row['home'] ?? ''}',
        awayId: '${row['away_id']}',
        awayName: '${row['away'] ?? ''}',
      ),
    );
    if (ok) _loadMatches();
  }

  Future<void> _clips(Map row) async {
    final m = await _model('${row['id']}');
    if (m == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MatchHighlightReviewPage(
          match: m,
          homeName: '${row['home'] ?? ''}',
          awayName: '${row['away'] ?? ''}',
        ),
      ),
    );
    _loadMatches();
  }

  Future<void> _poster(Map row) async {
    final m = await _model('${row['id']}');
    if (m == null || !mounted) return;
    await shareMatchPoster(
      context,
      m: m,
      homeName: '${row['home'] ?? ''}',
      awayName: '${row['away'] ?? ''}',
      homeLogo: '${row['home_logo'] ?? ''}',
      awayLogo: '${row['away_logo'] ?? ''}',
    );
  }

  /// Maç öncesi Paylaş: maç önü videosu (admin) ya da maç afişi.
  Future<void> _share(Map row) async {
    final isAdmin = AppSession.of(context).value.isAdmin;
    if (!isAdmin) return _poster(row);
    final pick = await showAdminOptionPicker<String>(
      context: context,
      title: 'Paylaş',
      items: const ['video', 'poster'],
      labelBuilder: (v) => v == 'video' ? 'Maç önü videosu' : 'Maç afişi',
    );
    if (pick == 'video') {
      await openMatchPreviewVideo('${row['id']}');
    } else if (pick == 'poster') {
      await _poster(row);
    }
  }

  void _embedInfo(_Embed e) {
    final (title, body) = switch (e) {
      _Embed.disabled => (
        'Yerleştirme kapalı',
        'Yayıncı YouTube\'da "Yerleştirmeye izin ver" seçeneğini kapatmış; '
            'yayın uygulama içinde oynatılamıyor. YouTube Studio › Video › '
            'Ayrıntılar › Lisans ve Dağıtım bölümünden "Yerleştirmeye izin '
            'ver" işaretlenmeli.',
      ),
      _ => (
        'Video bulunamadı',
        'Link gizli, silinmiş ya da hatalı; yayın uygulama içinde '
            'açılamıyor. Linki kontrol edip yenisiyle değiştirin.',
      ),
    };
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(
          body,
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final pre = _matches.where(_isPre).toList();
    final live = _matches.where(_isLive).toList();
    final post = _matches.where(_isPost).toList();
    final enler = _showEnler
        ? _enler
        : const <
            ({int week, String regionId, String region, String? newsId})
          >[];
    final up = _upcoming;
    final counts = [
      pre.length,
      live.length,
      post.length,
      up.length,
      enler.length,
    ];
    // Maçı olmayan sekme seçilemez; seçili sekme boşsa sırayla Canlı,
    // Maç öncesi, Maç sonu, Sıradaki, Enler'den dolu olana geçilir.
    if (counts[_tab] == 0) {
      for (final i in const [1, 0, 2, 3, 4]) {
        if (counts[i] > 0) {
          _tab = i;
          break;
        }
      }
    }
    final shown = switch (_tab) {
      0 => pre,
      1 => live,
      3 => up,
      _ => post,
    };
    final onEnler = _tab == 4;
    final sc = _scope;
    final regionName = sc != null && sc.regions.length == 1
        ? sc.regions.first.$2
        : '';
    return BandBackPage(
      theme: _theme ?? ActiveTournament.theme.value,
      subtitle: regionName.isEmpty
          ? 'Yönetim Paneli'
          : 'Yönetim Paneli · $regionName',
      homeRight: true,
      onTitleTap: _scopes.length > 1 ? _pickLeague : null,
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          top: false,
          child: ColoredBox(
            color: _bg,
            child: Column(
              children: [
                _regionStrip(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      await _loadApprovals(force: true);
                      await _loadMatches();
                    },
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 32),
                      children: [
                        _approvalsCard(),
                        // Ana sayfadaki uyarılar artık panelde.
                        if (_scope != null) ...[
                          OverdueResultsBanner(leagueId: _scope!.leagueId),
                          UnassignedRefereesBanner(leagueId: _scope!.leagueId),
                          UnscheduledMatchesBanner(leagueId: _scope!.leagueId),
                        ],
                        _tabs(
                          pre.length,
                          live.length,
                          post.length,
                          up.length,
                          enler.length,
                        ),
                        const SizedBox(height: 12),
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.all(40),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (_error != null)
                          _empty(_error!)
                        else if (_scope == null)
                          _empty('Yönettiğin aktif bir turnuva yok.')
                        else if (onEnler)
                          for (final e in enler)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _enlerCard(e),
                            )
                        else if (shown.isEmpty)
                          _empty(switch (_tab) {
                            0 => 'Bugün maç yok.',
                            1 => 'Şu an canlı maç yok.',
                            3 => 'Planlanmış sıradaki maç yok.',
                            _ => 'Son 3 günde biten maç yok.',
                          })
                        else
                          for (final m in shown)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: switch (_tab) {
                                0 => _preCard(m),
                                1 => _liveCard(m),
                                3 => _upCard(m),
                                _ => _postCard(m),
                              },
                            ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty(String t) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Text(
      t,
      textAlign: TextAlign.center,
      style: const TextStyle(color: _mid),
    ),
  );

  Widget _regionStrip() {
    final s = _scope;
    if (s == null || s.regions.length < 2) return const SizedBox.shrink();
    final chips = <(String?, String)>[
      if (s.canAll) (null, 'Tümü'),
      for (final r in s.regions) (r.$1, r.$2),
    ];
    Widget tab((String?, String) c, {required bool stretch}) {
      final on = _regionId == c.$1;
      final t = InkWell(
        onTap: on
            ? null
            : () {
                setState(() {
                  _regionId = c.$1;
                  _loading = true;
                });
                _loadMatches();
              },
        child: Container(
          height: 38,
          padding: EdgeInsets.symmetric(horizontal: stretch ? 4 : 18),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? const Color(0x14FFFFFF) : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: on ? _green : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Text(
            c.$2,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: on ? Colors.white : _mid,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
      return stretch ? Expanded(child: t) : t;
    }

    return Material(
      color: _card,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _line)),
        ),
        child: chips.length <= 4
            ? Row(children: [for (final c in chips) tab(c, stretch: true)])
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [for (final c in chips) tab(c, stretch: false)],
                ),
              ),
      ),
    );
  }

  /// Bekleyen onaylar: kapanır/açılır kart; satırlar ilgili ekrana götürür.
  Widget _approvalsCard() {
    final s = _scope;
    final total = _penPending + _newsPending + _commentPending + _ibrazPending;
    if (s == null || total == 0) return const SizedBox.shrink();
    Widget row(
      IconData icon,
      Color color,
      String title,
      int n,
      Future<void> Function() go,
    ) {
      if (n == 0) return const SizedBox.shrink();
      return InkWell(
        onTap: () async {
          await go();
          if (mounted) {
            _loadApprovals(force: true);
            _loadIbraz();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: _line)),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                constraints: const BoxConstraints(minWidth: 24),
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$n',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: _mid, size: 20),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: _toggleApprovals,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'BEKLEYEN ONAYLAR',
                      style: TextStyle(
                        color: _mid,
                        fontSize: 12,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    constraints: const BoxConstraints(minWidth: 24),
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$total',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _apOpen
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: _mid,
                  ),
                ],
              ),
            ),
          ),
          if (_apOpen) ...[
            row(
              Icons.gavel_rounded,
              const Color(0xFFEF4444),
              'Kart cezası onayı',
              _penPending,
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  settings: const RouteSettings(
                    name: 'AdminPenaltyManagementScreen',
                  ),
                  builder: (_) =>
                      AdminPenaltyManagementScreen(initialLeagueId: s.leagueId),
                ),
              ),
            ),
            row(
              Icons.article_outlined,
              const Color(0xFF3B82F6),
              'Haber onayı',
              _newsPending,
              () async =>
                  openNewsList(context, leagueId: s.leagueId, pending: true),
            ),
            row(
              Icons.chat_bubble_outline_rounded,
              const Color(0xFF8B5CF6),
              'Yorum onayı',
              _commentPending,
              () => NewsCommentReviewScreen.open(context, s.leagueId),
            ),
            row(
              Icons.badge_outlined,
              const Color(0xFFF97316),
              'Kimlik ibraz onayı',
              _ibrazPending,
              () => IbrazPendingScreen.open(context),
            ),
          ],
        ],
      ),
    );
  }

  String? _defaultRegion(_Scope s) =>
      !s.canAll && s.regions.isNotEmpty ? s.regions.first.$1 : null;

  Future<void> _pickLeague() async {
    final known = {
      for (final l in ActiveTournament.myLeagues.value) l.id: l.logoUrl,
    };
    final id = await showBandLeagueList(
      items: [
        for (final e in _scopes)
          LeagueChoice(
            id: e.leagueId,
            name: e.name,
            logoUrl: known[e.leagueId] ?? '',
          ),
      ],
      selectedId: _scope?.leagueId,
    );
    if (id == null || id == _scope?.leagueId) return;
    final picked = _scopes.firstWhere((e) => e.leagueId == id);
    setState(() {
      _scope = picked;
      _regionId = _defaultRegion(picked);
      _loading = true;
      _theme = null;
    });
    _loadTheme();
    _loadMatches();
  }

  Widget _tabs(int pre, int live, int post, int up, int enler) {
    final counts = [pre, live, post, up, if (_showEnler) enler];
    // Sayı yalnız sıfırdan büyükse yazılır.
    String lab(String t, int n) => n > 0 ? '$t · $n' : t;
    final labels = [
      lab('Maç öncesi', pre),
      lab('Canlı', live),
      lab('Maç sonu', post),
      lab('Sıradaki', up),
      if (_showEnler) lab('Enler', enler),
    ];
    final compact = labels.length > 3;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF13203A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                // Maçı olmayan sekme görünür ama seçilemez.
                onTap: counts[i] == 0 ? null : () => setState(() => _tab = i),
                child: Container(
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _tab == i
                        ? const Color(0xFFCBD5E1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        color: _tab == i
                            ? _bg
                            : counts[i] == 0
                            ? const Color(0xFF475569)
                            : const Color(0xFFCBD5E1),
                        fontWeight: FontWeight.w800,
                        fontSize: compact ? 12 : 13,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _shell({
    required Widget head,
    required List<Widget> children,
    Color? border,
  }) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: border ?? _line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        head,
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    ),
  );

  static Color? _hex(Object? v) {
    final t = '${v ?? ''}'.trim().replaceFirst('#', '');
    if (t.length != 6) return null;
    final n = int.tryParse(t, radix: 16);
    return n == null ? null : Color(0xFF000000 | n);
  }

  Widget _logo(String? url, String name, Color? color) {
    final initials = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0])
        .join()
        .toUpperCase();
    final u = (url ?? '').trim();
    final fallback = Text(
      initials,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
    );
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black26,
        border: Border.all(color: color ?? Colors.white24, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: u.isEmpty
          ? fallback
          : Image.network(
              u,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }

  /// Maç detayı gibi başlık: takım renkleri geçişi, logolar, ortada saat
  /// (canlıda / maç sonunda skor).
  Widget _head(
    Map m, {
    String? right,
    Color? rightColor,
    bool score = false,
    VoidCallback? onTap,
    bool compact = false,
  }) {
    final region = (m['region'] as String?) ?? '';
    final d = DateTime.tryParse('${m['date'] ?? ''}');
    const days = [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];
    const months = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    final rawTime = '${m['time'] ?? ''}';
    final time = rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime;
    final dateText = d == null
        ? 'Tarih yok'
        : '${d.day} ${months[d.month - 1]} · ${days[d.weekday - 1]}';
    final hc = _hex(m['home_color']) ?? const Color(0xFF334155);
    final ac = _hex(m['away_color']) ?? const Color(0xFF334155);
    final week = m['week'];
    final tag = [
      if (region.isNotEmpty) region,
      if (week != null) '$week. Hafta',
    ].join(' · ').toUpperCase();
    Widget side(bool home) {
      final name = shortTeamName('${m[home ? 'home' : 'away'] ?? '-'}');
      return Expanded(
        child: Column(
          children: [
            _logo(
              m[home ? 'home_logo' : 'away_logo'] as String?,
              name,
              home ? hc : ac,
            ),
            const SizedBox(height: 6),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    final head = Container(
      padding: EdgeInsets.fromLTRB(10, compact ? 8 : 12, 10, compact ? 8 : 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.lerp(hc, _card, 0.55)!,
            _card,
            Color.lerp(ac, _card, 0.55)!,
          ],
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (tag.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xCC172554),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tag,
                    style: const TextStyle(
                      color: Color(0xFF93C5FD),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              const Spacer(),
              if (right != null)
                Text(
                  right,
                  style: TextStyle(
                    color: rightColor ?? _mid,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              // Üst banda dokununca maç detayı açılır; soluk ok yalnız bunu
              // hatırlatır.
              if (onTap != null) ...[
                if (right != null) const SizedBox(width: 10),
                const Text(
                  'Maç detayı ›',
                  style: TextStyle(
                    color: Color(0xB3FFFFFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: compact ? 4 : 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              side(true),
              SizedBox(
                width: 104,
                child: Column(
                  children: [
                    const SizedBox(height: 6),
                    Text(
                      score
                          ? '${m['home_score'] ?? 0} – ${m['away_score'] ?? 0}'
                          : (time.isEmpty ? '–' : time),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFE2E8F0),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              side(false),
            ],
          ),
          if ((m['pitch'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${m['pitch']}',
              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
            ),
          ],
        ],
      ),
    );
    return onTap == null ? head : InkWell(onTap: onTap, child: head);
  }

  /// Kontrol satırı: durum işareti, metin, sağda eylem.
  Widget _row(String state, String text, {String? sub, Widget? trailing}) {
    final (mark, color) = switch (state) {
      'ok' => ('✓', _greenText),
      'warn' => ('!', _amber),
      'bad' => ('!', _red),
      _ => ('○', _mid),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: Text(
              mark,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: text,
                children: [
                  if (sub != null)
                    TextSpan(
                      text: ' · $sub',
                      style: const TextStyle(color: _mid),
                    ),
                ],
              ),
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _link(String label, VoidCallback onTap, {Color color = _greenText}) =>
      TextButton(
        style: TextButton.styleFrom(
          foregroundColor: color,
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      );

  Widget _streamRow(Map m, {required String okText}) {
    final url = ((m['youtube_url'] as String?) ?? '').trim();
    final id = '${m['id']}';
    if (url.isEmpty) {
      return _row(
        'warn',
        'Yayın linki yok',
        trailing: _link('Ekle', () => _media(id, liveLink: true)),
      );
    }
    final e = _embedCache[url];
    if (e == _Embed.disabled || e == _Embed.missing) {
      return _row(
        'bad',
        'Yayın eklendi ama izlenemiyor',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Neden izlenemiyor',
              onPressed: () => _embedInfo(e!),
              icon: const Icon(Icons.info_outline_rounded, color: _red),
            ),
            _link('Değiştir', () => _media(id, liveLink: true), color: _red),
          ],
        ),
      );
    }
    return _row(e == null ? 'none' : 'ok', okText);
  }

  Widget _primary(String label, IconData icon, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: SizedBox(
      height: 48,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: _green,
          foregroundColor: const Color(0xFF04130D),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
    ),
  );

  /// Tamamlanmış maç: başlık + tek satır özet; "Ayrıntı" ile açılır.
  Widget _summary(Map m, Widget head, String text) {
    final id = '${m['id']}';
    return _shell(
      head: head,
      children: [
        _row(
          'ok',
          text,
          trailing: _link('Ayrıntı', () => setState(() => _expanded.add(id))),
        ),
      ],
    );
  }

  bool _streamOk(Map m) {
    final url = ((m['youtube_url'] as String?) ?? '').trim();
    if (url.isEmpty) return false;
    final e = _embedCache[url];
    return e != _Embed.disabled && e != _Embed.missing;
  }

  /// Sıradaki maç: tarih/saat, hafta, saha ve hakem bilgisi; dokununca detay.
  Widget _upCard(Map m) {
    final id = '${m['id']}';
    final pitch = '${m['pitch'] ?? ''}'.trim();
    final ref = '${m['referee'] ?? ''}'.trim();
    final undated = '${m['date'] ?? ''}'.trim().isEmpty;
    Widget info(IconData i, String t, {bool warn = false}) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(i, size: 16, color: warn ? _amber : _mid),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t,
              style: TextStyle(
                color: warn ? _amber : Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return _shell(
      head: _head(
        m,
        right: m['status'] == 'postponed' ? 'ERTELENDİ' : null,
        rightColor: _amber,
        onTap: () => _openMatch(id),
        compact: true,
      ),
      children: [
        if (undated)
          info(Icons.event_busy_rounded, 'Tarih/saat girilmemiş', warn: true),
        info(
          Icons.place_outlined,
          pitch.isEmpty ? 'Saha belirlenmedi' : pitch,
          warn: pitch.isEmpty,
        ),
        info(
          Icons.sports_rounded,
          ref.isEmpty ? 'Hakem atanmadı' : ref,
          warn: ref.isEmpty,
        ),
      ],
    );
  }

  Widget _preCard(Map m) {
    final id = '${m['id']}';
    final referee = ((m['referee'] as String?) ?? '').trim();
    final pitch = ((m['pitch'] as String?) ?? '').trim();
    final postponed = m['status'] == 'postponed';
    final need = _n(m, 'need_xi');
    final ready =
        _n(m, 'xi_home') >= need &&
        _n(m, 'xi_away') >= need &&
        referee.isNotEmpty &&
        pitch.isNotEmpty &&
        '${m['time'] ?? ''}'.isNotEmpty &&
        (!_liveOn || _streamOk(m));
    if (ready && !_expanded.contains(id)) {
      return _summary(
        m,
        _head(m, right: 'HAZIR ✓', rightColor: _greenText),
        'Esame, hakem, yayın, saat ve saha tamam',
      );
    }
    final isAdmin = AppSession.of(context).value.isAdmin;
    final url = ((m['youtube_url'] as String?) ?? '').trim();
    final emb = url.isEmpty ? null : _embedCache[url];
    final broken = emb == _Embed.disabled || emb == _Embed.missing;
    final time = '${m['time'] ?? ''}'.trim();
    final news = m['preview_news'] == true;
    return _shell(
      head: _head(
        m,
        right: postponed ? 'ERTELENDİ' : null,
        rightColor: _amber,
        onTap: () => _openMatch(id),
        compact: true,
      ),
      children: [
        _esameBand(m),
        ..._mediaRows([
          [
            if (_liveOn)
              _cell(
                'YAYIN LİNKİ',
                url.isEmpty ? 'warn' : (broken ? 'bad' : 'ok'),
                url.isEmpty ? 'Yok' : (broken ? 'İzlenemiyor' : 'Eklendi'),
                url.isEmpty ? 'Ekle' : 'Değiştir',
                () => _media(id, liveLink: true),
                color: broken ? _red : _greenText,
              ),
            if (_bcastOn) _crewCell(m, MediaCreditKind.broadcast),
          ],
          [
            _cell(
              'HAKEM',
              referee.isEmpty ? 'warn' : 'ok',
              referee.isEmpty ? 'Atanmadı' : referee,
              referee.isEmpty ? 'Ata' : 'Değiştir',
              () => _referee(id),
            ),
            if (_photoOn) _crewCell(m, MediaCreditKind.photo),
          ],
        ]),
        _pairDivider(),
        _pair(
          _cell(
            'MAÇ SAATİ',
            time.isEmpty ? 'warn' : 'ok',
            time.isEmpty ? 'Belirlenmedi' : time,
            'Değiştir',
            () => _schedule(id),
          ),
          _cell(
            'SAHA',
            pitch.isEmpty ? 'warn' : 'ok',
            pitch.isEmpty ? 'Belirlenmedi' : pitch,
            'Değiştir',
            () => _schedule(id),
          ),
        ),
        _pairDivider(),
        _pair(
          _cell(
            'MAÇ ÖNÜ HABERİ',
            news ? 'ok' : 'none',
            news
                ? 'Yayında'
                : (_autoPreview
                      ? 'Otomatik · maç günü 09:00'
                      : 'Otomatik kapalı'),
            news ? null : 'Oluştur',
            news ? null : () => _createPreviewNews(id),
          ),
          _cell(
            isAdmin ? 'MAÇ ÖNÜ AFİŞ / VİDEO' : 'MAÇ ÖNÜ AFİŞİ',
            'none',
            isAdmin ? 'Afiş / Video' : 'Afiş',
            'Paylaş',
            () => _share(m),
          ),
        ),
        _primary('Maçı Yönet', Icons.sports_rounded, () => _openMatch(id)),
      ],
    );
  }

  /// Satırlar (1-2 hücre): boş satır atlanır, tek hücre tam genişlik olur.
  List<Widget> _mediaRows(List<List<Widget>> rows) => [
    for (final r in rows)
      if (r.isNotEmpty) ...[
        _pairDivider(),
        r.length == 1 ? r.first : _pair(r[0], r[1]),
      ],
  ];

  /// Maç önü haberini elle oluşturur (otomatik kapalı ya da vakit gelmemiş).
  Future<void> _createPreviewNews(String id) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _sb.rpc('create_preview_news', params: {'p_match_id': id});
      messenger.showSnackBar(
        const SnackBar(content: Text('Maç önü haberi oluşturuldu.')),
      );
      _loadMatches();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Haber oluşturulamadı.')),
      );
    }
  }

  // ---- Medya ekibi (yayıncı / fotoğrafçı) ----

  /// Maç → o maçta görünen kişi adları (tür başına).
  Map<String, Map<MediaCreditKind, List<String>>> _crew = {};

  Future<void> _loadCrew(List<Map<String, dynamic>> list) async {
    final s = _scope;
    if (s == null || list.isEmpty) return;
    try {
      final pool = await MediaCreditFeed.fetch(s.leagueId);
      final rows = await _sb
          .from('matches')
          .select('id, media_crew_custom, match_media_crew(credit_id)')
          .inFilter('id', [for (final m in list) '${m['id']}']);
      final out = <String, Map<MediaCreditKind, List<String>>>{};
      for (final r in rows) {
        final crew = (
          custom: r['media_crew_custom'] == true,
          ids: {
            for (final x in (r['match_media_crew'] as List? ?? const []))
              (x as Map)['credit_id'].toString(),
          },
        );
        out['${r['id']}'] = {
          for (final k in MediaCreditKind.values)
            k: [for (final c in MatchMediaCrew.resolve(pool, crew, k)) c.name],
        };
      }
      if (mounted) setState(() => _crew = out);
    } catch (_) {}
  }

  Future<void> _editCrew(String id, MediaCreditKind kind) async {
    final m = await _model(id);
    if (m == null || !mounted) return;
    await showMatchCrewSheet(context, m, kind: kind);
    _loadMatches();
  }

  Widget _crewCell(Map m, MediaCreditKind kind) {
    final id = '${m['id']}';
    final names = _crew[id]?[kind] ?? const <String>[];
    return _cell(
      kind.label.toUpperCase(),
      names.isEmpty ? 'warn' : 'ok',
      names.isEmpty ? 'Atanmadı' : names.join(', '),
      names.isEmpty ? 'Ata' : 'Değiştir',
      () => _editCrew(id, kind),
    );
  }

  // ---- Maç öncesi: esame bandı ve çift satırlar ----

  static const _hair = Color(0x14FFFFFF);

  Widget _pairDivider() => const Divider(height: 1, thickness: 1, color: _hair);

  /// Sığdığı kadar yan yana: dar ekran ya da büyük yazıda alt alta geçer.
  Widget _pair(Widget a, Widget b) => LayoutBuilder(
    builder: (context, c) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      if (c.maxWidth >= 300 * scale) {
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: a),
              const VerticalDivider(width: 1, thickness: 1, color: _hair),
              Expanded(child: b),
            ],
          ),
        );
      }
      return Column(children: [a, _pairDivider(), b]);
    },
  );

  /// Etiket + durum + (sağda) eylem yazısı; hücrenin tamamına dokunulur.
  Widget _cell(
    String label,
    String state,
    String value,
    String? action,
    VoidCallback? onTap, {
    Color color = _greenText,
  }) {
    final (mark, mc) = switch (state) {
      'ok' => ('✓ ', _greenText),
      'warn' => ('! ', _amber),
      'bad' => ('! ', _red),
      _ => ('○ ', _mid),
    };
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: _mid,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      text: mark,
                      style: TextStyle(color: mc, fontWeight: FontWeight.w900),
                      children: [
                        TextSpan(
                          text: value,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: 6),
              Text(
                action,
                style: TextStyle(
                  color: color,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// İki takımın esame durumu tek bantta; her yarı kendi takımının esamesini
  /// açar (girilmişse düzenleme, eksikse giriş).
  Widget _esameBand(Map m) {
    final need = _n(m, 'need_xi');
    Widget half(bool home) {
      final xi = _n(m, home ? 'xi_home' : 'xi_away');
      final name = shortTeamName('${m[home ? 'home' : 'away'] ?? ''}');
      final done = xi >= need;
      return _cell(
        name.toUpperCase(),
        done ? 'ok' : 'warn',
        done ? 'Esame $xi/$need' : (xi == 0 ? 'Esame yok' : 'İlk 11 $xi/$need'),
        done ? 'Düzenle' : 'Ekle',
        () => _openEsame(m, home, scan: false),
      );
    }

    return _pair(half(true), half(false));
  }

  Widget _liveCard(Map m) {
    final id = '${m['id']}';
    final mine = m['controller_me'] == true;
    final who = (m['controller'] as String?) ?? '';
    final half = m['status'] == 'halftime';
    return _shell(
      border: _green,
      head: _head(
        m,
        right: half ? 'DEVRE ARASI' : '● CANLI',
        rightColor: half ? _amber : _red,
        score: true,
        onTap: () => _openMatch('${m['id']}'),
      ),
      children: [
        _row(
          mine ? 'ok' : (who.isEmpty ? 'warn' : 'none'),
          mine
              ? 'Yönetim sende'
              : who.isEmpty
              ? 'Yönetim boşta'
              : 'Yöneten',
          sub: mine || who.isEmpty ? null : who,
        ),
        _streamRow(m, okText: 'Yayın açık'),
        _primary(
          mine ? 'Maça git · olay gir' : 'Maçı aç · yönetimi al',
          mine ? Icons.sports_soccer_rounded : Icons.sports_rounded,
          () => _openMatch(id, tab: 1),
        ),
      ],
    );
  }

  Widget _postCard(Map m) {
    final id = '${m['id']}';
    final ph = m['photo_home'] == true, pa = m['photo_away'] == true;
    final moments = _n(m, 'moments');
    final videos = _n(m, 'videos');
    final clips = _n(m, 'clips');
    final clip = m['clip_status'] as String?;
    final news = m['result_news'] as String?;
    final motm = m['motm'] == true;
    final hasStream = ((m['youtube_url'] as String?) ?? '').trim().isNotEmpty;
    final done =
        ph &&
        pa &&
        moments > 0 &&
        (clips > 0 || !hasStream) &&
        news == 'published' &&
        motm;
    if (done && !_expanded.contains(id)) {
      return _summary(
        m,
        _head(m, right: 'TAMAM ✓', rightColor: _greenText, score: true),
        'Fotoğraflar, kesitler, haber ve maçın oyuncusu tamam',
      );
    }
    Widget tile(String title, String sub, String state, VoidCallback onTap) {
      final (bg, fg) = switch (state) {
        'ok' => (const Color(0xFF0F2E25), const Color(0xFF6EE7B7)),
        'bad' => (const Color(0xFF2A1416), const Color(0xFFFCA5A5)),
        'none' => (const Color(0xFF243044), _mid),
        _ => (const Color(0xFF2A1D0B), _amber),
      };
      return Material(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  sub,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _shell(
      head: _head(
        m,
        right: 'MAÇ SONU',
        rightColor: Colors.white,
        score: true,
        onTap: () => _openMatch(id),
      ),
      children: [
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.3,
          children: [
            tile(
              'Takım fotosu',
              ph && pa
                  ? 'İki takım ✓'
                  : '${ph ? '✓' : '✗'} ev · ${pa ? '✓' : '✗'} dep',
              ph && pa ? 'ok' : 'warn',
              () => _media(id, type: 'Takım Fotosu'),
            ),
            tile(
              'Maçtan fotoğraflar',
              moments == 0 ? 'Yok · Ekle' : '$moments fotoğraf',
              moments == 0 ? 'warn' : 'ok',
              () => _media(id, type: 'Önemli An'),
            ),
            tile(
              'Röportajlar',
              videos == 0 ? 'Yok · Instagram linki' : '$videos video',
              videos == 0 ? 'none' : 'ok',
              () => _interview(m),
            ),
            tile(
              'Gol kesitleri',
              clips > 0
                  ? '$clips kesit'
                  : !hasStream
                  ? 'Yayın linki yok'
                  : switch (clip) {
                      'failed' => 'Taranamadı · Yeniden tara',
                      'retry' => 'Hata · yeniden denenecek',
                      'running' => 'Taranıyor…',
                      'pending' => 'Sırada',
                      _ => 'Yok · Golleri bul',
                    },
              clips > 0
                  ? 'ok'
                  : clip == 'failed'
                  ? 'bad'
                  : 'warn',
              () => _clips(m),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _row(
          news == 'published'
              ? 'ok'
              : news == 'pending'
              ? 'warn'
              : 'none',
          news == 'published'
              ? 'Maç sonucu haberi yayında'
              : news == 'pending'
              ? 'Maç sonucu haberi onay bekliyor'
              : 'Maç sonucu haberi yok',
          trailing: news == 'pending'
              ? _link('Gör', () => _openMatch(id))
              : null,
        ),
        _row(
          motm ? 'ok' : 'warn',
          motm ? 'Maçın oyuncusu seçildi' : 'Maçın oyuncusu seçilmedi',
          trailing: motm ? null : _link('Seç', () => _openMatch(id, tab: 1)),
        ),
        if (hasStream) _streamRow(m, okText: 'Yayın kaydı izlenebilir'),
        _row(
          'none',
          'Sonuç afişi',
          trailing: _link('Paylaş', () => _poster(m)),
        ),
      ],
    );
  }
}

/// Yayınlanan bültendeki her en için Instagram gönderisi / Reels bağlantısı
/// (bültenin tek değiştirilebilen yeri; enin kartının 2. sayfası olur).
class _InstagramLinkForm extends StatefulWidget {
  const _InstagramLinkForm({required this.newsId, required this.awards});

  final String newsId;
  final List<({String kind, String title, String url})> awards;

  @override
  State<_InstagramLinkForm> createState() => _InstagramLinkFormState();
}

class _InstagramLinkFormState extends State<_InstagramLinkForm> {
  late final Map<String, TextEditingController> _c = {
    for (final a in widget.awards) a.kind: TextEditingController(text: a.url),
  };
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final changes = <String, String>{};
    for (final a in widget.awards) {
      final v = _c[a.kind]!.text.trim();
      if (v == a.url) continue;
      if (v.isNotEmpty && !isInstagramPostUrl(v)) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${a.title}: Instagram gönderisi ya da Reels bağlantısı gir.',
            ),
          ),
        );
        return;
      }
      changes[a.kind] = v.isEmpty
          ? ''
          : (v.startsWith('http') ? v : 'https://$v').split('?').first;
    }
    if (changes.isEmpty) {
      nav.pop();
      return;
    }
    setState(() => _saving = true);
    try {
      for (final e in changes.entries) {
        await Supabase.instance.client.rpc(
          'set_week_award_instagram',
          params: {
            'p_news_id': widget.newsId,
            'p_kind': e.key,
            'p_url': e.value,
          },
        );
      }
      nav.pop('Instagram videoları kaydedildi.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = e is PostgrestException ? e.message : '$e';
      messenger.showSnackBar(SnackBar(content: Text('Kaydedilemedi: $msg')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminDialogCloseOverlay(
      onClose: _saving ? null : () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AdminDialogHeader(
            icon: Icons.camera_alt_outlined,
            title: 'Instagram Videoları',
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdminFieldGroup(
                    children: [
                      for (final a in widget.awards)
                        AdminFieldRow(
                          icon: Icons.link_rounded,
                          label: a.title,
                          child: TextField(
                            controller: _c[a.kind],
                            enabled: !_saving,
                            keyboardType: TextInputType.url,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                            cursorColor: kAdminAccent,
                            decoration: adminInlineInputDecoration(
                              hint: 'instagram.com/reel/…',
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
                    child: Text(
                      'Gönderi ya da Reels bağlantısı. Eklenen video, enin '
                      'kartının 2. sayfası olarak gösterilir. Boş bırakıp '
                      'kaydedersen kaldırılır.',
                      style: TextStyle(color: kAdminMuted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: AdminPrimaryButton(
              label: 'Kaydet',
              busy: _saving,
              onPressed: _saving ? null : _save,
            ),
          ),
        ],
      ),
    );
  }
}
