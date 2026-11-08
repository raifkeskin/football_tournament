import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/app_session.dart';
import '../../core/services/app_settings.dart';
import '../../core/services/service_locator.dart';
import '../../core/services/active_tournament.dart';
import '../../core/widgets/admin_form.dart';
import '../../core/utils/team_name.dart';
import '../../core/widgets/app_name_band.dart';
import '../match/widgets/match_highlights_section.dart';
import '../match/widgets/match_schedule_dialog.dart';
import '../referees/match_referee_picker.dart';
import '../share/pre_match_video.dart';
import '../videos/videos.dart';
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
  const AdminPanelScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'AdminPanelScreen'),
      builder: (_) => const AdminPanelScreen(),
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
  bool _loading = true;
  String? _error;
  int _tab = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
        _scope = list.isEmpty ? null : list.first;
        // Bölge sorumlusu tek bölgedeyse o bölgeye sabitlenir.
        final s = _scope;
        _regionId = s != null && !s.canAll && s.regions.length == 1
            ? s.regions.first.$1
            : null;
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

  Future<void> _loadMatches() async {
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
      setState(() {
        _matches = list;
        _loading = false;
        _error = null;
      });
      for (final m in list) {
        _checkEmbed(m['youtube_url'] as String?);
      }
    } catch (_) {
      _failed();
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

  Future<void> _media(String id, {bool liveLink = false}) async {
    final m = await _model(id);
    if (m == null || !mounted) return;
    await showMatchMediaAdder(
      context,
      match: m,
      liveLinkOnly: liveLink,
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
    final shown = switch (_tab) {
      0 => pre,
      1 => live,
      _ => post,
    };
    return BandBackPage(
      theme: _theme,
      subtitle: 'Yönetim Paneli',
      trailing: _scopes.length > 1
          ? IconButton(
              tooltip: 'Turnuva seç',
              onPressed: _pickLeague,
              icon: const Icon(Icons.expand_more_rounded, color: Colors.white),
            )
          : null,
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          top: false,
          child: ColoredBox(
            color: _bg,
            child: RefreshIndicator(
              onRefresh: _loadMatches,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 32),
                children: [
                  _scopeBar(),
                  const SizedBox(height: 10),
                  _tabs(pre.length, live.length, post.length),
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
                  else if (shown.isEmpty)
                    _empty(switch (_tab) {
                      0 => 'Önümüzdeki 7 günde maç yok.',
                      1 => 'Şu an canlı maç yok.',
                      _ => 'Son 3 günde biten maç yok.',
                    })
                  else
                    for (final m in shown)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: switch (_tab) {
                          0 => _preCard(m),
                          1 => _liveCard(m),
                          _ => _postCard(m),
                        },
                      ),
                ],
              ),
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

  Widget _scopeBar() {
    final s = _scope;
    if (s == null) return const SizedBox.shrink();
    final chips = <(String?, String)>[
      if (s.canAll && s.regions.length > 1) (null, 'Tümü'),
      if (s.canAll || s.regions.length > 1)
        for (final r in s.regions) (r.$1, r.$2),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (chips.length > 1) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (id, label) in chips)
                ChoiceChip(
                  label: Text(label),
                  selected: _regionId == id,
                  onSelected: (_) {
                    setState(() {
                      _regionId = id;
                      _loading = true;
                    });
                    _loadMatches();
                  },
                ),
            ],
          ),
        ] else if (!s.canAll && s.regions.length == 1) ...[
          Text(
            s.regions.first.$2,
            style: const TextStyle(color: _mid, fontWeight: FontWeight.w700),
          ),
        ],
      ],
    );
  }

  Future<void> _pickLeague() async {
    final picked = await showAdminOptionPicker<_Scope>(
      context: context,
      title: 'Turnuva',
      items: _scopes,
      labelBuilder: (s) => s.name,
      selected: _scope,
    );
    if (picked == null || picked == _scope) return;
    setState(() {
      _scope = picked;
      _regionId = !picked.canAll && picked.regions.length == 1
          ? picked.regions.first.$1
          : null;
      _loading = true;
      _theme = null;
    });
    _loadTheme();
    _loadMatches();
  }

  Widget _tabs(int pre, int live, int post) {
    final labels = ['Maç öncesi · $pre', 'Canlı · $live', 'Maç sonu · $post'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF13203A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _tab = i),
                child: Container(
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _tab == i
                        ? const Color(0xFFCBD5E1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: _tab == i ? _bg : const Color(0xFFCBD5E1),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
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
  Widget _head(Map m, {String? right, Color? rightColor, bool score = false}) {
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

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
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
            ],
          ),
          const SizedBox(height: 8),
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

  Widget _pill(String label, VoidCallback onTap, {bool filled = true}) =>
      SizedBox(
        height: 36,
        child: filled
            ? FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: const Color(0xFF1A1204),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: onTap,
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              )
            : OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _amber,
                  side: const BorderSide(color: Color(0xFFF59E0B)),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: onTap,
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
      );

  Widget _esameRows(Map m) {
    final need = _n(m, 'need_xi');
    Widget team(bool home) {
      final xi = _n(m, home ? 'xi_home' : 'xi_away');
      final name = '${m[home ? 'home' : 'away'] ?? ''}';
      if (xi >= need) {
        return _row(
          'ok',
          'Esame · $name',
          sub: '$xi/$need',
          trailing: _link('Düzenle', () => _openEsame(m, home, scan: false)),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row(
            'warn',
            'Esame · $name',
            sub: xi == 0 ? 'girilmedi' : 'İlk 11 $xi/$need',
          ),
          Padding(
            padding: const EdgeInsets.only(left: 24, bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: _pill(
                    'Elle gir',
                    () => _openEsame(m, home, scan: false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _pill(
                    'Kağıttan okut',
                    () => _openEsame(m, home, scan: true),
                    filled: false,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(children: [team(true), team(false)]);
  }

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

  Widget _preCard(Map m) {
    final id = '${m['id']}';
    final referee = ((m['referee'] as String?) ?? '').trim();
    final pitch = ((m['pitch'] as String?) ?? '').trim();
    final postponed = m['status'] == 'postponed';
    return _shell(
      head: _head(m, right: postponed ? 'ERTELENDİ' : null, rightColor: _amber),
      children: [
        _esameRows(m),
        _row(
          referee.isEmpty ? 'warn' : 'ok',
          referee.isEmpty ? 'Hakem atanmadı' : 'Hakem',
          sub: referee.isEmpty ? null : referee,
          trailing: _link(
            referee.isEmpty ? 'Ata' : 'Değiştir',
            () => _referee(id),
          ),
        ),
        _streamRow(m, okText: 'Yayın linki eklendi'),
        _row(
          (m['time'] ?? '').toString().isEmpty ? 'warn' : 'ok',
          'Maç saati',
          sub: (m['time'] ?? '').toString().isEmpty
              ? 'belirlenmedi'
              : '${m['time']}',
          trailing: _link('Değiştir', () => _schedule(id)),
        ),
        _row(
          pitch.isEmpty ? 'warn' : 'ok',
          'Saha',
          sub: pitch.isEmpty ? 'belirlenmedi' : pitch,
          trailing: _link('Değiştir', () => _schedule(id)),
        ),
        _row(
          m['preview_news'] == true ? 'ok' : 'none',
          'Maç önü haberi',
          sub: m['preview_news'] == true ? 'yayında' : 'henüz yok',
        ),
        _row('none', 'Maç afişi', trailing: _link('Paylaş', () => _share(m))),
        _primary('Maçı Yönet', Icons.sports_rounded, () => _openMatch(id)),
      ],
    );
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
    Widget tile(String title, String sub, String state, VoidCallback onTap) {
      final (bg, fg) = switch (state) {
        'ok' => (const Color(0xFF0F2E25), const Color(0xFF6EE7B7)),
        'bad' => (const Color(0xFF2A1416), const Color(0xFFFCA5A5)),
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

    void media() => _media(id);
    return _shell(
      head: _head(m, right: 'MAÇ SONU', rightColor: Colors.white, score: true),
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
              media,
            ),
            tile(
              'Maçtan fotoğraflar',
              moments == 0 ? 'Yok · Ekle' : '$moments fotoğraf',
              moments == 0 ? 'warn' : 'ok',
              media,
            ),
            tile(
              'Röportajlar',
              videos == 0 ? 'Yok · Instagram linki' : '$videos video',
              videos == 0 ? 'warn' : 'ok',
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
