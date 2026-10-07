import '../../../core/services/active_tournament.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../player/widgets/player_card.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../../tournament/models/league_extras.dart';
import '../models/match.dart';
import '../models/match_media.dart';
import '../../team/models/team.dart';
import '../../../core/utils/team_name.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../../core/services/app_session.dart';
import '../../../core/services/image_upload_service.dart';
import '../../tournament/services/interfaces/i_league_service.dart';
import '../services/interfaces/i_match_service.dart';
import '../../team/services/interfaces/i_team_service.dart';
import '../../../core/services/service_locator.dart';
import 'admin_match_event_screen.dart';
import '../../tournament/screens/formation_tab.dart';
import '../../share/lineup_poster.dart';
import '../../share/match_poster.dart';
import '../../share/poster_share.dart';
import '../../share/squad_poster.dart';
import '../../../core/utils/team_colors.dart';
import '../../../core/widgets/pitch_token_style.dart';
import 'package:football_tournament/core/widgets/picked_image.dart';
import '../utils/match_clock.dart';
import '../../../core/widgets/league_logo.dart';
import 'package:football_tournament/core/widgets/admin_page.dart';
import 'package:football_tournament/core/widgets/admin_form.dart';
import '../../../core/utils/string_utils.dart';
import '../../player/services/penalty_service.dart';

// --- YARDIMCI WIDGETLAR ---

/// Çift sarıdan ihraç: arkada sarı, önde kırmızı kart.
class _SecondYellowCardIcon extends StatelessWidget {
  const _SecondYellowCardIcon();

  Widget _card(Color c) => Container(
    width: 11,
    height: 15,
    decoration: BoxDecoration(
      color: c,
      borderRadius: BorderRadius.circular(2),
      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 2)],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 19,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Transform.rotate(angle: -0.2, child: _card(Colors.yellow)),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Transform.rotate(angle: 0.15, child: _card(Colors.red)),
          ),
        ],
      ),
    );
  }
}

/// Maç detayı üst bandı: logo üstte, takım adı altında ortalı (2 satır).
class _TeamInfo extends StatelessWidget {
  final String name;
  final String logoUrl;

  const _TeamInfo({required this.name, required this.logoUrl});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Şeffaf logolar kırpılmadan, çerçevesiz gösterilir.
        WebSafeImage(
          url: logoUrl,
          width: 64,
          height: 64,
          fit: BoxFit.contain,
          fallbackIconSize: 26,
        ),
        const SizedBox(height: 4),
        Text(
          shortTeamName(name),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 15,
            height: 1.15,
            letterSpacing: 0.2,
            shadows: [
              Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 2)),
              Shadow(color: Colors.black87, blurRadius: 3),
            ],
          ),
        ),
      ],
    );
  }
}

/// Geri okunun yanında turnuva bandı: logo + ad + hafta.
class _LeagueStrip extends StatefulWidget {
  const _LeagueStrip({required this.leagueId, this.week});

  final String leagueId;
  final int? week;

  @override
  State<_LeagueStrip> createState() => _LeagueStripState();
}

class _LeagueStripState extends State<_LeagueStrip> {
  static final Map<String, Future<({String name, String logo})?>> _cache = {};
  late Future<({String name, String logo})?> _info;

  @override
  void initState() {
    super.initState();
    _info = _load(widget.leagueId);
  }

  static Future<({String name, String logo})?> _load(String id) {
    if (id.trim().isEmpty) return Future.value(null);
    return _cache.putIfAbsent(id, () async {
      try {
        final r = await Supabase.instance.client
            .from('leagues')
            .select('name, logo_url')
            .eq('id', id)
            .maybeSingle();
        if (r == null) return null;
        return (
          name: (r['name'] ?? '').toString(),
          logo: (r['logo_url'] ?? '').toString(),
        );
      } catch (_) {
        _cache.remove(id);
        return null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFE2B845);
    return FutureBuilder<({String name, String logo})?>(
      future: _info,
      builder: (context, snap) {
        final info = snap.data;
        if (info == null) return const SizedBox.shrink();
        // Turnuva adı üstte, hafta altında: uzun adlarda hafta kesilmesin.
        return Center(
          child: Container(
            padding: const EdgeInsets.fromLTRB(5, 3, 14, 3),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: gold.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LeagueLogo(url: info.logo, size: 30, fallbackColor: gold),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        info.name.trUpper,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      if (widget.week != null)
                        Text(
                          '${widget.week}. HAFTA',
                          style: const TextStyle(
                            color: gold,
                            fontSize: 10,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Skorun altında: canlı dakika, İY veya MS.
class _MatchPhaseLabel extends StatelessWidget {
  const _MatchPhaseLabel({required this.match});

  final MatchModel match;

  @override
  Widget build(BuildContext context) {
    return MatchClockBuilder(
      match: match,
      builder: (context, liveMinute) {
        final (String? text, Color color) = switch (match.status) {
          MatchStatus.live => (liveMinute ?? 'CANLI', const Color(0xFFF87171)),
          MatchStatus.halftime => ('İY', const Color(0xFFFBBF24)),
          MatchStatus.finished => ('MS', const Color(0xFF10B981)),
          MatchStatus.postponed => ('ERTELENDİ', Colors.white70),
          MatchStatus.cancelled => ('İPTAL', Colors.white70),
          MatchStatus.notStarted => (null, Colors.transparent),
        };
        if (text == null) return const SizedBox.shrink();
        return Text(
          text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 13,
            shadows: const [
              Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 2)),
            ],
          ),
        );
      },
    );
  }
}

/// Yetkililere görünen maç akışı düğmesi (başlama düdüğü → İY → 2. yarı →
/// maç sonu). Son adımı geri alma, alttaki menü düğmesindedir.
class _MatchFlowBar extends StatefulWidget {
  const _MatchFlowBar({required this.match, required this.onAction});

  final MatchModel match;
  final Future<void> Function(String action) onAction;

  @override
  State<_MatchFlowBar> createState() => _MatchFlowBarState();
}

class _MatchFlowBarState extends State<_MatchFlowBar> {
  bool _busy = false;

  Future<void> _run(String action) async {
    setState(() => _busy = true);
    try {
      await widget.onAction(action);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    final ({String action, String label, IconData icon, Color color})? next =
        switch (m.status) {
          MatchStatus.notStarted => (
            action: 'start',
            label: 'Başlama Düdüğü',
            icon: Icons.sports_rounded,
            color: const Color(0xFF10B981),
          ),
          MatchStatus.live when m.secondHalfAt == null => (
            action: 'end_first_half',
            label: 'İlk Yarıyı Bitir',
            icon: Icons.pause_circle_outline_rounded,
            color: const Color(0xFFF59E0B),
          ),
          MatchStatus.halftime => (
            action: 'start_second_half',
            label: '2. Yarıyı Başlat',
            icon: Icons.play_circle_outline_rounded,
            color: const Color(0xFF10B981),
          ),
          MatchStatus.live => (
            action: 'finish',
            label: 'Maçı Bitir',
            icon: Icons.sports_score_rounded,
            color: const Color(0xFFEF4444),
          ),
          _ => null,
        };
    if (next == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: next.color,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: next.color.withValues(alpha: 0.4),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _busy ? null : () => _run(next.action),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(next.icon, size: 22),
                label: Text(
                  next.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- ANA EKRAN ---

class MatchDetailsScreen extends StatefulWidget {
  final MatchModel match;
  final bool isAdmin;
  final int initialTabIndex;
  const MatchDetailsScreen({
    super.key,
    required this.match,
    this.isAdmin = false,
    this.initialTabIndex = 0,
  });

  @override
  State<MatchDetailsScreen> createState() => _MatchDetailsScreenState();
}

class _MatchDetailsScreenState extends State<MatchDetailsScreen>
    with SingleTickerProviderStateMixin {
  final ITeamService _teamService = ServiceLocator.teamService;
  final IMatchService _matchService = ServiceLocator.matchService;
  final ILeagueService _leagueService = ServiceLocator.leagueService;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _matchStream = _matchService.watchMatch(widget.match.id);
    _teamsStream = _teamService.watchAllTeams();
    _pitchesStream = _leagueService.watchPitches();
    _prefetchLineups(widget.match);
  }

  // Akışlar bir kez kurulur; sekme değişimi gibi yeniden çizimlerde
  // baştan bağlanıp veri beklenmez.
  late final Stream<MatchModel> _matchStream;
  late final Stream<List<Team>> _teamsStream;
  late final Stream<List<Pitch>> _pitchesStream;

  /// Kadrolar sekmesine basılmadan önce oyuncu ve kadro verisini arka planda
  /// çekip servis önbelleğine alır; sekme açıldığında veri hazır olur.
  void _prefetchLineups(MatchModel m) {
    if (m.id.isEmpty || m.seasonId.isEmpty) return;
    for (final teamId in {m.homeTeamId, m.awayTeamId}) {
      if (teamId.isEmpty) continue;
      _teamService
          .watchPlayers(teamId: teamId, tournamentId: m.seasonId)
          .last
          .ignore();
    }
    _matchService.watchMatchRosters(m.id, m.homeTeamId).first.ignore();
  }

  int _refreshKey = 0;

  /// Tek maç afişi: turnuva logosu, grup, hafta, takımlar, saha, tarih, saat.
  Future<void> _shareMatchPoster({
    required MatchModel m,
    required String homeName,
    required String awayName,
    required String homeLogo,
    required String awayLogo,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    String leagueName = '', leagueLogo = '', groupName = '';
    var pitchName = (m.pitchName ?? '').trim();
    try {
      final db = Supabase.instance.client;
      final league = await db
          .from('leagues')
          .select('name, logo_url')
          .eq('id', m.leagueId)
          .maybeSingle();
      leagueName = (league?['name'] ?? '').toString().trim();
      leagueLogo = (league?['logo_url'] ?? '').toString().trim();
      final gid = (m.groupId ?? '').trim();
      if (gid.isNotEmpty) {
        // Tek gruplu sezonda grup adı turnuva adıyla aynı; başlıkta tekrar
        // etmesin.
        final groups = await db
            .from('groups')
            .select('id, name')
            .eq('season_id', m.seasonId);
        if (groups.length > 1) {
          for (final g in groups) {
            if (g['id'] == gid) groupName = (g['name'] ?? '').toString().trim();
          }
        }
      }
      final pid = (m.pitchId ?? '').trim();
      if (pitchName.isEmpty && pid.isNotEmpty) {
        final pitch = await db
            .from('pitches')
            .select('name')
            .eq('id', pid)
            .maybeSingle();
        pitchName = (pitch?['name'] ?? '').toString().trim();
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Maç bilgisi okunamadı: $e')),
      );
      return;
    }
    if (!mounted) return;

    final date = DateTime.tryParse((m.matchDate ?? '').trim());
    final rawTime = (m.matchTime ?? '').trim();
    await showPosterPreview(
      context: context,
      fileName: 'mac_${homeName}_$awayName'.replaceAll(RegExp(r'\s+'), '_'),
      imageUrls: [leagueLogo, homeLogo, awayLogo],
      poster: MatchPoster(
        leagueName: leagueName,
        leagueLogo: leagueLogo,
        groupName: groupName,
        week: m.week,
        homeName: homeName,
        homeLogo: homeLogo,
        awayName: awayName,
        awayLogo: awayLogo,
        pitchName: pitchName,
        dayName: date == null ? '' : DateFormat('EEEE', 'tr_TR').format(date),
        dateText: date == null
            ? ''
            : DateFormat('dd.MM.yyyy', 'tr_TR').format(date),
        timeText: rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime,
      ),
    );
  }

  void _triggerRefresh() {
    if (mounted) {
      setState(() => _refreshKey++);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _friendlyLoadError(Object? error) {
    final s = (error ?? '').toString();
    final lower = s.toLowerCase();
    if (lower.contains('permission-denied')) {
      return 'Yetki hatası. Giriş yapıldı mı ve kullanıcı yetkisi doğru mu kontrol edin.\n\n$s';
    }
    if (lower.contains('requires an index') ||
        lower.contains('failed-precondition')) {
      return 'Sorgu için Firestore index gerekli olabilir.\n\n$s';
    }
    if (lower.contains('unavailable') || lower.contains('network')) {
      return 'Bağlantı hatası. İnternet bağlantısını kontrol edin.\n\n$s';
    }
    return s;
  }

  String _resolvePitchLocation({
    required List<Pitch> pitches,
    required String pitchId,
    required String pitchName,
  }) {
    final id = pitchId.trim();
    final name = pitchName.trim();

    if (id.isNotEmpty) {
      for (final p in pitches) {
        if (p.id.trim() == id) {
          return p.location;
        }
      }
    }

    if (name.isNotEmpty) {
      for (final p in pitches) {
        if (p.name.trim().toLowerCase() == name.toLowerCase()) {
          return p.location;
        }
      }
    }

    return '';
  }

  Future<void> _openPitchLocation(
    BuildContext context,
    String rawLocation,
  ) async {
    if (rawLocation.isEmpty) return;
    final uri = Uri.tryParse(rawLocation);
    if (uri == null || uri.scheme.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Konum linki geçersiz.')));
      return;
    }

    try {
      final can = await canLaunchUrl(uri);
      if (!can) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Link açılamadı.')));
        return;
      }
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.externalNonBrowserApplication,
      );
      if (!ok) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Link açılamadı.')));
      }
    }
  }

  /// "12/10/2026  |  20:00"; saat yoksa yalnızca tarih ("Tarih Belirlenmedi").
  String _dateTimeText(MatchModel m) {
    final date = _formatDate(m.matchDate ?? '');
    final time = (m.matchTime ?? '').trim();
    if (time.isEmpty || time == 'null') return date;
    return '$date  |  $time';
  }

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty || dateStr == '__NO_DATE__') {
      return 'Tarih Belirlenmedi';
    }
    try {
      final p = dateStr.split('-');
      if (p.length != 3) return dateStr;
      return "${p[2]}/${p[1]}/${p[0]}";
    } catch (e) {
      return dateStr;
    }
  }

  Widget? _buildTabFab({
    required MatchModel match,
    required int tabIndex,
    bool canAssignObserver = false,
    bool canUndo = false,
  }) {
    if (tabIndex == 1 || tabIndex == 3) return null;

    if (tabIndex == 0) {
      return _SpeedDialFab(
        key: const ValueKey('fab_detail'),
        actions: [
          _SpeedDialAction(
            label: 'Maç Detayı Gir',
            icon: Icons.edit_note_rounded,
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => AdminMatchEventScreen(match: match),
            ),
          ),
          _SpeedDialAction(
            label: 'Stad Seç',
            icon: Icons.location_on,
            onTap: () => _openPitchEditor(match),
          ),
          if (canAssignObserver)
            _SpeedDialAction(
              label: 'Gözlemci Ata',
              icon: Icons.visibility_outlined,
              onTap: () => _openObserverPicker(match),
            ),
          if (canUndo &&
              match.status != MatchStatus.notStarted &&
              match.status != MatchStatus.postponed &&
              match.status != MatchStatus.cancelled)
            _SpeedDialAction(
              label: 'Son Adımı Geri Al',
              icon: Icons.undo_rounded,
              onTap: () => _runPhaseAction(match, 'undo'),
            ),
        ],
      );
    }

    if (tabIndex == 2) {
      return _SpeedDialFab(
        key: const ValueKey('fab_highlights'),
        actions: [
          _SpeedDialAction(
            label: 'Medya Ekle',
            icon: Icons.perm_media_rounded,
            onTap: () => _openHighlightMediaAdder(match, _triggerRefresh),
          ),
        ],
      );
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.of(context).value;

    return StreamBuilder<MatchModel>(
      stream: _matchStream,
      initialData: widget.match,
      builder: (context, matchSnap) {
        if (matchSnap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Maç Detayı')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Maç verisi yüklenemedi.\n\n${_friendlyLoadError(matchSnap.error)}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        final m = matchSnap.data ?? widget.match;

        // Maç detayındaki yetkiler: admin, turnuva sahibi ve maçın gözlemcisi.
        final bool canManageLeague = session.canManageLeague(m.leagueId);
        final bool isSuperAdmin =
            canManageLeague ||
            (m.observerId != null && m.observerId == session.user?.id);
        final bool managesHome =
            session.managesTeam(m.seasonId, m.homeTeamId) ||
            session.teamId == m.homeTeamId;
        final bool managesAway =
            session.managesTeam(m.seasonId, m.awayTeamId) ||
            session.teamId == m.awayTeamId;

        return StreamBuilder<List<Team>>(
          stream: _teamsStream,
          builder: (context, teamsSnap) {
            if (teamsSnap.hasError) {
              return Scaffold(
                appBar: AppBar(title: const Text('Maç Detayı')),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Takım verileri yüklenemedi.\n\n${_friendlyLoadError(teamsSnap.error)}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }
            final Map<String, String> logoMap = {};
            final Map<String, String> nameMap = {};
            Team? homeTeam, awayTeam;
            if (teamsSnap.hasData) {
              for (final team in teamsSnap.data!) {
                logoMap[team.id] = team.logoUrl;
                nameMap[team.id] = team.name;
                if (team.id == m.homeTeamId) homeTeam = team;
                if (team.id == m.awayTeamId) awayTeam = team;
              }
            }
            final sides = matchSideColors(
              homeFirst: homeTeam?.firstColor,
              homeSecond: homeTeam?.secondColor,
              awayFirst: awayTeam?.firstColor,
              awaySecond: awayTeam?.secondColor,
              fallback:
                  ActiveTournament.theme.value?.primary ??
                  const Color(0xFF064E3B),
            );

            final homeLogo = (logoMap[m.homeTeamId] ?? '').trim();
            final awayLogo = (logoMap[m.awayTeamId] ?? '').trim();
            final homeName = (nameMap[m.homeTeamId] ?? '').trim().isEmpty
                ? 'Ev Sahibi'
                : (nameMap[m.homeTeamId] ?? '').trim();
            final awayName = (nameMap[m.awayTeamId] ?? '').trim().isEmpty
                ? 'Deplasman'
                : (nameMap[m.awayTeamId] ?? '').trim();

            return Scaffold(
              extendBodyBehindAppBar: true,
              backgroundColor: const Color(0xFF0F172A),
              appBar: AppBar(
                toolbarHeight: 44,
                // Bant tam genişlikteki katmanda ortalanır; başlık alanı
                // geri okundan sonra ortaladığı için sağa kayıyordu. İki
                // yanda geri oku kadar (56px) boşluk bırakılır.
                flexibleSpace: SafeArea(
                  bottom: false,
                  child: SizedBox(
                    height: 44,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 56),
                      child: _LeagueStrip(leagueId: m.leagueId, week: m.week),
                    ),
                  ),
                ),
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                // Maç afişi: diğer afişler gibi admin ve turnuva sahibine.
                actions: [
                  if (canManageLeague)
                    IconButton(
                      tooltip: 'Maç afişini paylaş',
                      icon: const Icon(
                        Icons.ios_share_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => _shareMatchPoster(
                        m: m,
                        homeName: homeName,
                        awayName: awayName,
                        homeLogo: homeLogo,
                        awayLogo: awayLogo,
                      ),
                    ),
                ],
              ),
              floatingActionButton: !isSuperAdmin
                  ? null
                  : _buildTabFab(
                      match: m,
                      tabIndex: _tabController.index,
                      canAssignObserver: canManageLeague,
                      canUndo: canManageLeague,
                    ),
              body: Column(
                children: [
                  // Alt köşeleri yuvarlak, gölgeli bant: içerikten net ayrılır.
                  Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(26),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black54,
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Takım renkleri kenarlardan ortaya koyulaşır; saha çizgileri + alt şerit.
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _MatchHeaderPainter(sides),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.only(
                            // Takım bloğu üst çubuktaki turnuva bandının
                            // (44px) hemen altından başlar.
                            top: MediaQuery.of(context).padding.top + 50,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  // Üstten hizalı: isimler kaç satır olursa olsun
                                  // skor logolarla aynı hizada kalır.
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _TeamInfo(
                                        name: homeName,
                                        logoUrl: homeLogo,
                                      ),
                                    ),
                                    Padding(
                                      // Skor, büyütülen logoların ortasına
                                      // denk gelir.
                                      padding: const EdgeInsets.fromLTRB(
                                        10,
                                        12,
                                        10,
                                        0,
                                      ),
                                      child: Column(
                                        children: [
                                          Text(
                                            "${m.homeScore} - ${m.awayScore}",
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 30,
                                              shadows: [
                                                Shadow(
                                                  color: Colors.black,
                                                  blurRadius: 10,
                                                  offset: Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                          ),
                                          _MatchPhaseLabel(match: m),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: _TeamInfo(
                                        name: awayName,
                                        logoUrl: awayLogo,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.access_time_filled_rounded,
                                      size: 14,
                                      color: Colors.white70,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _dateTimeText(m),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black,
                                            blurRadius: 10,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if ((m.pitchId ?? '').isNotEmpty) ...[
                                      const SizedBox(width: 12),
                                      const Text(
                                        "|",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          shadows: [
                                            Shadow(
                                              color: Colors.black,
                                              blurRadius: 10,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Icon(
                                        Icons.location_on_rounded,
                                        size: 14,
                                        color: Colors.white70,
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: StreamBuilder<List<Pitch>>(
                                          stream: _pitchesStream,
                                          builder: (context, pitchSnap) {
                                            final pitchId = (m.pitchId ?? '')
                                                .trim();
                                            final pitches =
                                                pitchSnap.data ??
                                                const <Pitch>[];

                                            // pitchId ile eşleşen stadı bul
                                            String displayPitchName =
                                                'Bilinmeyen Saha';
                                            String location = '';

                                            for (final p in pitches) {
                                              if (p.id == pitchId) {
                                                displayPitchName = p.name;
                                                location = p.location;
                                                break;
                                              }
                                            }

                                            return InkWell(
                                              onTap: location.isEmpty
                                                  ? null
                                                  : () => _openPitchLocation(
                                                      context,
                                                      location,
                                                    ),
                                              child: Text(
                                                displayPitchName,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  shadows: [
                                                    Shadow(
                                                      color: Colors.black,
                                                      blurRadius: 10,
                                                      offset: Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Column(
                          children: [
                            if (isSuperAdmin)
                              _MatchFlowBar(
                                match: m,
                                onAction: (action) =>
                                    _runPhaseAction(m, action),
                              ),
                            _LiveStreamPanel(
                              key: ValueKey('live_${m.id}_$_refreshKey'),
                              matchId: m.id,
                            ),
                            // Tam genişlikte sekme satırı: başlığın altında
                            // ayrı bir şerit, seçili sekmenin altı çizili.
                            Container(
                              height: 46,
                              margin: const EdgeInsets.only(top: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF111A2E),
                                border: Border(
                                  bottom: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.08),
                                  ),
                                ),
                              ),
                              child: TabBar(
                                controller: _tabController,
                                dividerColor: Colors.transparent,
                                indicatorSize: TabBarIndicatorSize.tab,
                                indicatorColor: const Color(0xFF10B981),
                                indicatorWeight: 3,
                                labelColor: Colors.white,
                                unselectedLabelColor: Colors.white60,
                                overlayColor: WidgetStateProperty.all(
                                  Colors.transparent,
                                ),
                                labelPadding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                labelStyle: const TextStyle(
                                  fontFamily: 'Batangas',
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13.5,
                                ),
                                unselectedLabelStyle: const TextStyle(
                                  fontFamily: 'Batangas',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                ),
                                tabs: const [
                                  Tab(text: 'Detay'),
                                  Tab(text: 'Kadrolar'),
                                  Tab(text: 'Medya'),
                                  Tab(text: 'Diziliş'),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Container(
                                color: Colors.transparent,
                                child: TabBarView(
                                  controller: _tabController,
                                  children: [
                                    _DetailTab(match: m),

                                    // İŞTE DEĞİŞİKLİK YAPILAN YER: YENİ _LineupTab BAĞLANTISI
                                    _LineupTab(
                                      match: m,
                                      isSuperAdmin: isSuperAdmin,
                                      homeName: homeName,
                                      awayName: awayName,
                                    ),

                                    _HighlightsTab(
                                      key: ValueKey(_refreshKey),
                                      match: m,
                                      isSuperAdmin: isSuperAdmin,
                                      onDataChanged: _triggerRefresh,
                                      homeName: homeName,
                                      awayName: awayName,
                                    ),
                                    FormationTab(
                                      match: m,
                                      homeName: homeName,
                                      awayName: awayName,
                                      canEditHome: isSuperAdmin || managesHome,
                                      canEditAway: isSuperAdmin || managesAway,
                                      // Sorumlu kendi takımıyla açar.
                                      onShare: (teamId) => shareLineupPoster(
                                        context,
                                        match: m,
                                        homeName: homeName,
                                        awayName: awayName,
                                        teamId: teamId,
                                        kind: 'Diziliş',
                                      ),
                                      initialTeam:
                                          !isSuperAdmin &&
                                              managesAway &&
                                              !managesHome
                                          ? 1
                                          : 0,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Akış adımını uygular; maç sonu için skor onayı ister.
  Future<void> _runPhaseAction(MatchModel m, String action) async {
    if (action == 'finish' || action == 'undo') {
      final ok = await showAdminConfirmDialog(
        context: context,
        title: action == 'finish' ? 'Maçı Bitir' : 'Son Adımı Geri Al',
        message: action == 'finish'
            ? 'Skor ${m.homeScore} - ${m.awayScore} olarak kaydedilecek ve '
                  'maç puan durumuna yansıyacak. Onaylıyor musunuz?'
            : 'Maç bir önceki aşamaya döner.',
        confirmLabel: action == 'finish' ? 'BİTİR' : 'GERİ AL',
        destructive: action == 'undo',
        icon: action == 'finish'
            ? Icons.sports_score_rounded
            : Icons.undo_rounded,
      );
      if (!ok) return;
    }
    try {
      await _matchService.advanceMatchPhase(matchId: m.id, action: action);
    } catch (e) {
      if (!mounted) return;
      final msg = e is PostgrestException ? e.message : '$e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _openObserverPicker(MatchModel m) async {
    final List<({String userId, String label})> users;
    try {
      users = await _matchService.listObserverCandidates();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kullanıcılar okunamadı: $e')));
      return;
    }
    if (!mounted) return;
    const none = (userId: '', label: 'Gözlemci yok');
    final picked = await showAdminOptionPicker<({String userId, String label})>(
      context: context,
      title: 'Gözlemci Ata',
      items: [none, ...users],
      labelBuilder: (u) => u.label,
      selected: [
        none,
        ...users,
      ].where((u) => u.userId == (m.observerId ?? '')).firstOrNull,
      emptyText: 'Kayıtlı kullanıcı yok.',
    );
    if (picked == null || !mounted) return;
    try {
      await _matchService.setMatchObserver(
        matchId: m.id,
        userId: picked.userId.isEmpty ? null : picked.userId,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gözlemci atanamadı: $e')));
    }
  }

  void _openPitchEditor(MatchModel m) async {
    final list = await _leagueService.listPitchesOnce();
    String? sel = m.pitchName;
    if (!mounted) return;
    var saving = false;
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setS) {
          Future<void> pick() async {
            final v = await showAdminOptionPicker<String>(
              context: context,
              title: 'Saha',
              items: list,
              labelBuilder: (p) => p,
              selected: sel,
              emptyText: 'Kayıtlı saha yok.',
            );
            if (v != null) setS(() => sel = v);
          }

          Future<void> save() async {
            setS(() => saving = true);
            try {
              await _matchService.updateMatchPitchName(
                matchId: m.id,
                pitchName: sel,
              );
              if (c.mounted) Navigator.pop(c);
            } catch (e) {
              setS(() => saving = false);
              if (c.mounted) {
                ScaffoldMessenger.of(c).showSnackBar(
                  SnackBar(content: Text('Saha kaydedilemedi: $e')),
                );
              }
            }
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            child: AdminDialogCloseOverlay(
              onClose: saving ? null : () => Navigator.pop(c),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: adminDialogDecoration(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AdminDialogHeader(
                      icon: Icons.stadium_outlined,
                      title: 'Saha Seçimi',
                    ),
                    const SizedBox(height: 18),
                    AdminFieldGroup(
                      children: [
                        AdminSelectRow(
                          icon: Icons.location_on_outlined,
                          label: 'Saha',
                          value: sel,
                          placeholder: 'Saha seçin',
                          onTap: saving ? null : pick,
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    AdminPrimaryButton(
                      label: 'KAYDET',
                      busy: saving,
                      onPressed: save,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openHighlightMediaAdder(
    MatchModel matchModel,
    VoidCallback onSuccess,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) =>
          _MediaAdderDialog(match: matchModel, onSuccess: onSuccess),
    );
  }
}

class _MediaAdderDialog extends StatefulWidget {
  final MatchModel match;
  final VoidCallback onSuccess;
  const _MediaAdderDialog({required this.match, required this.onSuccess});

  @override
  State<_MediaAdderDialog> createState() => _MediaAdderDialogState();
}

class _MediaAdderDialogState extends State<_MediaAdderDialog> {
  String _selectedType = 'Maç Yayın Linki';
  final _urlCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _isHomeTeam = true;
  XFile? _pickedFile;
  bool _isUploading = false;

  final List<String> _types = [
    'Maç Yayın Linki',
    'Takım Fotosu',
    'Önemli An',
    'Maçın Adamı',
    'Diğer',
  ];

  static IconData _typeIcon(String t) => switch (t) {
    'Maç Yayın Linki' => Icons.live_tv_rounded,
    'Takım Fotosu' => Icons.groups_outlined,
    'Önemli An' => Icons.bolt_rounded,
    'Maçın Adamı' => Icons.star_outline_rounded,
    _ => Icons.perm_media_outlined,
  };

  Widget _inputRow({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return AdminFieldRow(
      icon: icon,
      label: label,
      child: TextField(
        controller: controller,
        enabled: !_isUploading,
        maxLines: maxLines,
        minLines: 1,
        keyboardType: keyboardType,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        decoration: adminInlineInputDecoration(hint: hint),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLink = _selectedType == 'Maç Yayın Linki';
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: AdminDialogCloseOverlay(
        onClose: _isUploading ? null : () => Navigator.pop(context),
        child: Container(
          decoration: adminDialogDecoration(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AdminDialogHeader(
                  icon: Icons.perm_media_outlined,
                  title: 'Medya Ekle',
                ),
                const SizedBox(height: 18),
                AdminFieldGroup(
                  children: [
                    AdminSelectRow(
                      icon: _typeIcon(_selectedType),
                      label: 'Medya Türü',
                      value: _selectedType,
                      placeholder: 'Seçin',
                      onTap: _isUploading
                          ? null
                          : () async {
                              final v = await showAdminOptionPicker<String>(
                                context: context,
                                title: 'Medya Türü',
                                items: _types,
                                labelBuilder: (t) => t,
                                selected: _selectedType,
                              );
                              if (v != null && mounted) {
                                setState(() {
                                  _selectedType = v;
                                  _pickedFile = null;
                                });
                              }
                            },
                    ),
                    if (isLink)
                      _inputRow(
                        icon: Icons.link_rounded,
                        label: 'YouTube Linki',
                        controller: _urlCtrl,
                        hint: 'https://youtube.com/...',
                        keyboardType: TextInputType.url,
                      )
                    else
                      AdminFieldRow(
                        icon: Icons.image_outlined,
                        label: 'Görsel',
                        onTap: _isUploading
                            ? null
                            : () async {
                                final picked = await ImagePicker().pickImage(
                                  source: ImageSource.gallery,
                                  imageQuality: 85,
                                );
                                if (picked != null && mounted) {
                                  setState(() => _pickedFile = picked);
                                }
                              },
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white54,
                        ),
                        child: Text(
                          _pickedFile == null
                              ? 'Galeriden seçin'
                              : 'Görsel seçildi',
                          style: TextStyle(
                            color: _pickedFile == null
                                ? Colors.white38
                                : Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (_selectedType == 'Takım Fotosu')
                      AdminSelectRow(
                        icon: Icons.shield_outlined,
                        label: 'Takım',
                        value: _isHomeTeam ? 'Ev Sahibi' : 'Deplasman',
                        placeholder: 'Seçin',
                        onTap: _isUploading
                            ? null
                            : () async {
                                final v = await showAdminOptionPicker<bool>(
                                  context: context,
                                  title: 'Takım',
                                  items: const [true, false],
                                  labelBuilder: (h) =>
                                      h ? 'Ev Sahibi' : 'Deplasman',
                                  selected: _isHomeTeam,
                                );
                                if (v != null && mounted) {
                                  setState(() => _isHomeTeam = v);
                                }
                              },
                      ),
                    _inputRow(
                      icon: Icons.notes_rounded,
                      label: 'Açıklama (İsteğe Bağlı)',
                      controller: _descCtrl,
                      hint: 'Kısa bir açıklama',
                      maxLines: 2,
                    ),
                  ],
                ),
                if (!isLink && _pickedFile != null) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image(
                        image: pickedImageProvider(_pickedFile!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                AdminPrimaryButton(
                  label: 'KAYDET',
                  busy: _isUploading,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final m = widget.match;
    String finalUrl = '';

    if (_selectedType == 'Maç Yayın Linki') {
      finalUrl = _urlCtrl.text.trim();
      if (finalUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lütfen geçerli bir yayın linki girin.'),
          ),
        );
        return;
      }
    } else {
      if (_pickedFile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen bir görsel seçin.')),
        );
        return;
      }
      setState(() => _isUploading = true);
      try {
        final uploadedUrl = await SupabaseImageUploadService().uploadImage(
          _pickedFile!,
          folder: MediaFolder.matches,
        );
        if (uploadedUrl == null) {
          throw Exception('Görsel yüklenemedi.');
        }
        finalUrl = uploadedUrl;
      } catch (e) {
        setState(() => _isUploading = false);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Yükleme hatası: $e')));
        }
        return;
      }
    }

    final media = MatchMediaModel(
      id: '',
      matchId: m.id,
      mediaType: _selectedType,
      url: finalUrl,
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      teamId: _selectedType == 'Takım Fotosu'
          ? (_isHomeTeam ? m.homeTeamId : m.awayTeamId)
          : null,
      createdAt: DateTime.now(),
    );

    try {
      await ServiceLocator.matchService.addMatchMedia(media);

      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Medya başarıyla eklendi.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kayıt Hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted && _isUploading) {
        setState(() => _isUploading = false);
      }
    }
  }
}

class _SpeedDialAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SpeedDialAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

class _SpeedDialFab extends StatefulWidget {
  final List<_SpeedDialAction> actions;

  const _SpeedDialFab({super.key, required this.actions});

  @override
  State<_SpeedDialFab> createState() => _SpeedDialFabState();
}

class _SpeedDialFabState extends State<_SpeedDialFab> {
  bool _open = false;

  void _toggle() {
    setState(() => _open = !_open);
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final actions = widget.actions;

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        if (_open)
          Positioned.fill(
            child: GestureDetector(
              onTap: _close,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.shrink(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ...List.generate(actions.length, (i) {
                final a = actions[i];
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: !_open
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.surface.withValues(alpha: 0.95),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: cs.outlineVariant),
                                ),
                                child: Text(
                                  a.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              FloatingActionButton(
                                heroTag: 'speed_${a.label}_$i',
                                mini: true,
                                onPressed: () {
                                  _close();
                                  a.onTap();
                                },
                                child: Icon(a.icon),
                              ),
                            ],
                          ),
                        ),
                );
              }),
              FloatingActionButton(
                heroTag: 'speed_main',
                onPressed: _toggle,
                tooltip: _open ? 'Kapat' : 'İşlemler',
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  transitionBuilder: (c, a) =>
                      RotationTransition(turns: a, child: c),
                  child: Icon(
                    _open ? Icons.close_rounded : Icons.menu_rounded,
                    key: ValueKey(_open),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- TAB İÇERİKLERİ ---

class _HighlightsTab extends StatefulWidget {
  final MatchModel match;
  final bool isSuperAdmin;
  final VoidCallback onDataChanged;
  final String homeName;
  final String awayName;
  const _HighlightsTab({
    super.key,
    required this.match,
    required this.isSuperAdmin,
    required this.onDataChanged,
    required this.homeName,
    required this.awayName,
  });

  @override
  State<_HighlightsTab> createState() => _HighlightsTabState();
}

class _HighlightsTabState extends State<_HighlightsTab>
    with AutomaticKeepAliveClientMixin {
  late final Stream<List<MatchMediaModel>> _mediaStream = ServiceLocator
      .matchService
      .watchMatchMedia(widget.match.id);

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _HighlightsTabView(
      match: widget.match,
      isSuperAdmin: widget.isSuperAdmin,
      onDataChanged: widget.onDataChanged,
      mediaStream: _mediaStream,
      homeName: widget.homeName,
      awayName: widget.awayName,
    );
  }
}

/// Maç fotoğrafları: takım filtresi + 3 sütunlu ızgara (yalnızca ekrana
/// gelen küçük resimler yüklenir), dokununca kaydırmalı tam ekran galeri.
/// Yayın linki burada listelenmez; skorun altında gösterilir.
class _HighlightsTabView extends StatefulWidget {
  final MatchModel match;
  final bool isSuperAdmin;
  final VoidCallback onDataChanged;
  final Stream<List<MatchMediaModel>> mediaStream;
  final String homeName;
  final String awayName;
  const _HighlightsTabView({
    required this.match,
    required this.isSuperAdmin,
    required this.onDataChanged,
    required this.mediaStream,
    required this.homeName,
    required this.awayName,
  });

  @override
  State<_HighlightsTabView> createState() => _HighlightsTabViewState();
}

class _HighlightsTabViewState extends State<_HighlightsTabView> {
  /// null: tümü; aksi hâlde takım id'si.
  String? _teamFilter;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MatchMediaModel>>(
      stream: widget.mediaStream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Hata: ${snap.error}'));
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final photos =
            (snap.data ?? const <MatchMediaModel>[])
                .where((m) => m.mediaType != 'Maç Yayın Linki')
                .toList()
              ..sort(
                (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
                  a.createdAt ?? DateTime(0),
                ),
              );
        if (photos.isEmpty) {
          return const Center(
            child: Text(
              'Henüz fotoğraf eklenmedi.',
              style: TextStyle(color: Colors.white60),
            ),
          );
        }

        final m = widget.match;
        final homeCount = photos.where((p) => p.teamId == m.homeTeamId).length;
        final awayCount = photos.where((p) => p.teamId == m.awayTeamId).length;
        final showFilter = homeCount > 0 || awayCount > 0;
        final shown = _teamFilter == null
            ? photos
            : photos.where((p) => p.teamId == _teamFilter).toList();

        return Column(
          children: [
            if (showFilter)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  children: [
                    _filterChip('Tümü', photos.length, null),
                    if (homeCount > 0)
                      _filterChip(
                        shortTeamName(widget.homeName),
                        homeCount,
                        m.homeTeamId,
                      ),
                    if (awayCount > 0)
                      _filterChip(
                        shortTeamName(widget.awayName),
                        awayCount,
                        m.awayTeamId,
                      ),
                  ],
                ),
              ),
            Expanded(
              child: shown.isEmpty
                  ? const Center(
                      child: Text(
                        'Bu takım için fotoğraf yok.',
                        style: TextStyle(color: Colors.white60),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(2, 6, 2, 24),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 2,
                            crossAxisSpacing: 2,
                          ),
                      itemCount: shown.length,
                      itemBuilder: (context, i) => _tile(context, shown, i),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _filterChip(String label, int count, String? teamId) {
    final on = _teamFilter == teamId;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: on,
        onSelected: (_) => setState(() => _teamFilter = teamId),
        label: Text('$label ($count)'),
        labelStyle: TextStyle(
          color: on ? Colors.white : Colors.white70,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
        selectedColor: const Color(0xFFC8102E),
        backgroundColor: const Color(0xFF1E293B),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  static IconData? _badgeIcon(String type) => switch (type) {
    'Maçın Adamı' => Icons.star_rounded,
    'Önemli An' => Icons.bolt_rounded,
    'Takım Fotosu' => Icons.groups_rounded,
    _ => null,
  };

  Widget _tile(BuildContext context, List<MatchMediaModel> list, int i) {
    final media = list[i];
    final badge = _badgeIcon(media.mediaType);
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _PhotoGalleryScreen(photos: list, initialIndex: i),
        ),
      ),
      onLongPress: widget.isSuperAdmin
          ? () => _confirmDelete(context, media)
          : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: const Color(0xFF1E293B),
            child: WebSafeImage(
              url: media.url,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              fallbackIconSize: 22,
            ),
          ),
          if (badge != null)
            Positioned(
              left: 5,
              top: 5,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: Icon(badge, size: 13, color: const Color(0xFFFBBF24)),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    MatchMediaModel media,
  ) async {
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Fotoğrafı Sil',
      message: 'Bu fotoğraf kalıcı olarak silinecek. Emin misiniz?',
    );

    if (ok == true) {
      await ServiceLocator.matchService.deleteMatchMedia(media.id);

      if (context.mounted) {
        widget.onDataChanged();
      }
    }
  }
}

/// Tam ekran galeri: sağa-sola kaydırma, yakınlaştırma, "3 / 24" sayacı ve
/// varsa açıklama.
class _PhotoGalleryScreen extends StatefulWidget {
  const _PhotoGalleryScreen({required this.photos, required this.initialIndex});

  final List<MatchMediaModel> photos;
  final int initialIndex;

  @override
  State<_PhotoGalleryScreen> createState() => _PhotoGalleryScreenState();
}

class _PhotoGalleryScreenState extends State<_PhotoGalleryScreen> {
  late final PageController _page = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.photos[_index];
    final caption = [
      if (current.mediaType != 'Diğer') current.mediaType,
      if ((current.description ?? '').isNotEmpty) current.description!,
    ].join(' · ');
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_index + 1} / ${widget.photos.length}',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: 'Aç / indir',
            icon: const Icon(Icons.download_rounded),
            onPressed: () => launchUrl(
              Uri.parse(current.url),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _page,
              itemCount: widget.photos.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => InteractiveViewer(
                maxScale: 4,
                child: Center(
                  child: WebSafeImage(
                    url: widget.photos[i].url,
                    width: double.infinity,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          if (caption.isNotEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Text(
                  caption,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// YouTube linkinden video id'si çıkarır (watch, youtu.be, embed, shorts, live).
String? _youtubeVideoId(String url) {
  final u = url.trim();
  if (RegExp(r'^[_\-a-zA-Z0-9]{11}$').hasMatch(u)) return u;
  final uri = Uri.tryParse(u);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  String? id;
  if (host.endsWith('youtu.be')) {
    id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
  } else if (host.contains('youtube.com') ||
      host.contains('youtube-nocookie.com')) {
    id = uri.queryParameters['v'];
    final seg = uri.pathSegments;
    if (id == null &&
        seg.length >= 2 &&
        const {'embed', 'shorts', 'live', 'v'}.contains(seg.first)) {
      id = seg[1];
    }
  }
  if (id == null || !RegExp(r'^[_\-a-zA-Z0-9]{11}$').hasMatch(id)) {
    return null;
  }
  return id;
}

Future<void> _openYoutubeExternally(BuildContext context, String url) async {
  final uri = Uri.tryParse(url.trim());
  final ok =
      uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Video linki açılamadı.')));
  }
}

/// 16:9 YouTube alanı: küçük resim + oynat butonu; dokununca video yerinde
/// oynar. Link YouTube'a ait değilse dışarıda açılır.
class _YoutubeVideoView extends StatefulWidget {
  final String url;
  const _YoutubeVideoView({super.key, required this.url});

  @override
  State<_YoutubeVideoView> createState() => _YoutubeVideoViewState();
}

class _YoutubeVideoViewState extends State<_YoutubeVideoView> {
  YoutubePlayerController? _controller;

  @override
  void dispose() {
    _controller?.close();
    super.dispose();
  }

  void _play(String? id) {
    if (id == null) {
      _openYoutubeExternally(context, widget.url);
      return;
    }
    setState(() {
      _controller = YoutubePlayerController.fromVideoId(
        videoId: id,
        autoPlay: true,
        params: const YoutubePlayerParams(
          showFullscreenButton: true,
          strictRelatedVideos: true,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final id = _youtubeVideoId(widget.url);
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: _controller != null
          ? YoutubePlayer(controller: _controller!)
          : GestureDetector(
              onTap: () => _play(id),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (id != null)
                    WebSafeImage(
                      url: 'https://img.youtube.com/vi/$id/hqdefault.jpg',
                      fit: BoxFit.cover,
                      fallbackIconSize: 48,
                    )
                  else
                    Container(color: Colors.black),
                  // Alt tarafı hafif karart
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 68,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF0000),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [
                          BoxShadow(color: Colors.black45, blurRadius: 12),
                        ],
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.smart_display_rounded,
                            color: Color(0xFFFF0000),
                            size: 18,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'İzlemek için dokun',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Sekmelerin üstünde, maça yayın linki eklendiyse görünen açılır/kapanır
/// "Maç Yayını" paneli. Kapatılınca oynatıcı kaldırılır (video durur).
class _LiveStreamPanel extends StatefulWidget {
  final String matchId;
  const _LiveStreamPanel({super.key, required this.matchId});

  @override
  State<_LiveStreamPanel> createState() => _LiveStreamPanelState();
}

class _LiveStreamPanelState extends State<_LiveStreamPanel> {
  late final Stream<List<MatchMediaModel>> _mediaStream = ServiceLocator
      .matchService
      .watchMatchMedia(widget.matchId);
  // Kapalı başlar; izlemek isteyen başlığa dokunup açar.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MatchMediaModel>>(
      stream: _mediaStream,
      builder: (context, snap) {
        final stream = (snap.data ?? const <MatchMediaModel>[])
            .where(
              (m) =>
                  m.mediaType == 'Maç Yayın Linki' && m.url.trim().isNotEmpty,
            )
            .firstOrNull;
        if (stream == null) return const SizedBox.shrink();

        final desc = (stream.description ?? '').trim();
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.live_tv_rounded,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            desc.isEmpty ? 'Maç Yayını' : desc,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: "YouTube'da aç",
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              _openYoutubeExternally(context, stream.url),
                          icon: const Icon(
                            Icons.open_in_new_rounded,
                            color: Colors.white54,
                            size: 20,
                          ),
                        ),
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_expanded)
                  _YoutubeVideoView(key: ValueKey(stream.id), url: stream.url),
              ],
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// YENİ EKLENEN KADROLAR (ESAME) TABI WIDGET'I
// -----------------------------------------------------------------------------

class _LineupTab extends StatefulWidget {
  final MatchModel match;

  /// Admin, turnuva sahibi ve maç gözlemcisi: esame her zaman açık.
  final bool isSuperAdmin;
  final String homeName;
  final String awayName;

  const _LineupTab({
    required this.match,
    required this.isSuperAdmin,
    required this.homeName,
    required this.awayName,
  });

  @override
  State<_LineupTab> createState() => _LineupTabState();
}

/// Kadrolar sekmesindeki esame giriş bilgisi.
class _RosterInfoNote extends StatelessWidget {
  const _RosterInfoNote({required this.hours});

  /// Turnuvanın esame açılış süresi (leagues.roster_open_hours).
  final int hours;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: Color(0xFFF59E0B),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hours == 0
                  ? 'Takım sorumluları, kendi takımlarının esamesini maç '
                        'saatinde bu sekmedeki "Esame" butonundan girebilir. '
                        'Bu saatten önce buton kilitli görünür.'
                  : 'Takım sorumluları, kendi takımlarının esamesini maç '
                        'saatinden $hours saat önce bu sekmedeki "Esame" '
                        'butonundan girebilir. Bu saatten önce buton kilitli '
                        'görünür.',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

int _jerseyValue(String? n) => int.tryParse((n ?? '').trim()) ?? 999;

/// Takım sorumlusunun esameyi girebileceği an: maç saatinden [hours] saat
/// önce. Maç tarih/saati Türkiye saatidir (UTC+3). Tarih/saat yoksa null.
DateTime? _rosterOpenAt(MatchModel m, int hours) {
  final d = DateTime.tryParse((m.matchDate ?? '').trim());
  final t = RegExp(
    r'^(\d{1,2}):(\d{2})',
  ).firstMatch((m.matchTime ?? '').trim());
  if (d == null || t == null) return null;
  final kickoff = DateTime.utc(
    d.year,
    d.month,
    d.day,
    int.parse(t.group(1)!),
    int.parse(t.group(2)!),
  ).subtract(const Duration(hours: 3));
  return kickoff.subtract(Duration(hours: hours));
}

class _LineupTabState extends State<_LineupTab>
    with AutomaticKeepAliveClientMixin {
  static const _green = Color(0xFF10B981);
  static const _blue = Color(0xFF3B82F6);

  // Sekmeler arası geçişte kadro yeniden yüklenmesin.
  @override
  bool get wantKeepAlive => true;

  /// Esame açılış anında ekranı yeniler (sayfa açıkken süre dolarsa).
  Timer? _openTimer;
  DateTime? _openTimerAt;

  /// Turnuvanın esame açılış süresi (saat); yüklenene kadar varsayılan 1.
  int _openHours = 1;

  @override
  void initState() {
    super.initState();
    _loadOpenHours();
  }

  Future<void> _loadOpenHours() async {
    try {
      final row = await Supabase.instance.client
          .from('leagues')
          .select('roster_open_hours')
          .eq('id', widget.match.leagueId)
          .maybeSingle();
      final h = (row?['roster_open_hours'] as num?)?.toInt();
      if (h != null && h != _openHours && mounted) {
        setState(() => _openHours = h);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _openTimer?.cancel();
    super.dispose();
  }

  void _scheduleOpen(DateTime? openAt) {
    if (openAt == _openTimerAt) return;
    _openTimer?.cancel();
    _openTimerAt = openAt;
    if (openAt == null) return;
    final wait = openAt.difference(DateTime.now().toUtc());
    if (wait.isNegative) return;
    _openTimer = Timer(wait + const Duration(seconds: 1), () {
      if (mounted) setState(() {});
    });
  }

  /// Takım sorumlusu bu takımın sorumlusu mu (yetkili rolleri hariç).
  bool _managesTeam(String teamId) {
    final session = AppSession.of(context).value;
    return session.managesTeam(widget.match.seasonId, teamId) ||
        (session.teamId != null && session.teamId == teamId);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final m = widget.match;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        // Esame bilgisi: düzenleme yetkisi olanlara (yetkililer ve maçın
        // takım sorumluları) gösterilir.
        if (widget.isSuperAdmin ||
            _managesTeam(m.homeTeamId) ||
            _managesTeam(m.awayTeamId)) ...[
          _RosterInfoNote(hours: _openHours),
          const SizedBox(height: 10),
        ],
        // Takım başlıkları + VS
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _teamHeader(
                name: widget.homeName,
                color: _green,
                teamId: m.homeTeamId,
                alignEnd: false,
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1E293B), Color(0xFF064E3B)],
                ),
                border: Border.all(color: Colors.white24),
              ),
              child: const Text(
                'VS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Expanded(
              child: _teamHeader(
                name: widget.awayName,
                color: _blue,
                teamId: m.awayTeamId,
                alignEnd: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // İki kadro yan yana
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _TeamLineupColumn(
                  match: m,
                  teamId: m.homeTeamId,
                  color: _green,
                ),
              ),
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: Colors.white.withValues(alpha: 0.08),
              ),
              Expanded(
                child: _TeamLineupColumn(
                  match: m,
                  teamId: m.awayTeamId,
                  color: _blue,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _teamHeader({
    required String name,
    required Color color,
    required String teamId,
    required bool alignEnd,
  }) {
    final label = Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: alignEnd ? TextAlign.right : TextAlign.left,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w900,
        fontSize: 14,
      ),
    );
    // Esame: admin / turnuva sahibi / gözlemci her zaman; takım sorumlusu
    // yalnızca kendi takımını, turnuvanın belirlediği süre kadar önce ve
    // maç bitene kadar.
    final m = widget.match;
    final managesThis = !widget.isSuperAdmin && _managesTeam(teamId);
    final openAt = _rosterOpenAt(m, _openHours);
    if (managesThis) _scheduleOpen(openAt);
    final managerOpen =
        managesThis &&
        m.status != MatchStatus.finished &&
        openAt != null &&
        !DateTime.now().toUtc().isBefore(openAt);
    final locked = managesThis && !managerOpen;
    final edit = locked
        ? Tooltip(
            message: m.status == MatchStatus.finished
                ? 'Maç bitti; esame kapandı.'
                : _openHours == 0
                ? 'Esame maç saatinde açılır.'
                : 'Esame maçtan $_openHours saat önce açılır.',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_clock_rounded,
                    size: 15,
                    color: Colors.white38,
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      m.status == MatchStatus.finished
                          ? 'Esame kapandı'
                          : openAt == null
                          ? 'Esame kapalı'
                          : 'Esame açılışı ${DateFormat('HH:mm').format(openAt.add(const Duration(hours: 3)))}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        : widget.isSuperAdmin || managerOpen
        ? InkWell(
            onTap: () => _showRosterEditSheet(context, teamId),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_note_rounded, size: 16, color: color),
                  const SizedBox(width: 3),
                  Text(
                    'Esame',
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          )
        : null;
    // Paylaşım: yalnızca o takımın sorumlusu ve lig yöneticileri.
    final session = AppSession.of(context).value;
    final canShare =
        session.canManageLeague(widget.match.leagueId) || _managesTeam(teamId);
    final share = canShare
        ? IconButton(
            tooltip: 'Kadroyu paylaş',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            onPressed: () => _shareLineup(teamId),
            icon: Icon(Icons.ios_share_rounded, size: 20, color: color),
          )
        : null;
    final info = Expanded(
      child: Column(
        crossAxisAlignment: alignEnd
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [label, ?edit],
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(children: alignEnd ? [?share, info] : [info, ?share]),
    );
  }

  Future<void> _shareLineup(String teamId) => shareLineupPoster(
    context,
    match: widget.match,
    homeName: widget.homeName,
    awayName: widget.awayName,
    teamId: teamId,
  );

  void _showRosterEditSheet(BuildContext context, String teamId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return _RosterEditSheet(
          match: widget.match,
          teamId: teamId,
          teamName: teamId == widget.match.homeTeamId
              ? widget.homeName
              : widget.awayName,
          isHome: teamId == widget.match.homeTeamId,
        );
      },
    );
  }
}

/// Tek takımın esamesi: İlk 11 ve Yedekler, önce mevki sonra forma
/// numarasına göre sıralı; sıkı satırlarla tüm ilk 11 tek ekrana sığar.
class _TeamLineupColumn extends StatefulWidget {
  const _TeamLineupColumn({
    required this.match,
    required this.teamId,
    required this.color,
  });

  final MatchModel match;
  final String teamId;
  final Color color;

  @override
  State<_TeamLineupColumn> createState() => _TeamLineupColumnState();
}

class _TeamLineupColumnState extends State<_TeamLineupColumn> {
  // Akışlar bir kez kurulur; üst widget yeniden çizildiğinde (ör. oyuncular
  // yüklendiğinde) kadro akışı baştan başlamaz.
  late Stream<List<PlayerModel>> _playersStream;
  late Stream<List<MatchRosterModel>> _rostersStream;

  MatchModel get match => widget.match;
  String get teamId => widget.teamId;
  Color get color => widget.color;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant _TeamLineupColumn old) {
    super.didUpdateWidget(old);
    if (old.match.id != widget.match.id ||
        old.match.seasonId != widget.match.seasonId ||
        old.teamId != widget.teamId) {
      _subscribe();
    }
  }

  void _subscribe() {
    _playersStream = ServiceLocator.teamService.watchPlayers(
      teamId: widget.teamId,
      tournamentId: widget.match.seasonId,
    );
    _rostersStream = ServiceLocator.matchService.watchMatchRosters(
      widget.match.id,
      widget.teamId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PlayerModel>>(
      stream: _playersStream,
      builder: (context, playerSnap) {
        final byId = {
          for (final p in playerSnap.data ?? const <PlayerModel>[]) p.id: p,
        };
        return StreamBuilder<List<MatchRosterModel>>(
          stream: _rostersStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Kadro yüklenemedi: ${snapshot.error}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              );
            }
            final rosters = snapshot.data ?? const <MatchRosterModel>[];
            if (rosters.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Kadro girilmemiş.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              );
            }

            String jerseyOf(MatchRosterModel r) =>
                (r.jerseyNumber ?? byId[r.playerId]?.number ?? '').trim();
            int lineOf(MatchRosterModel r) {
              final p = byId[r.playerId];
              return positionLineOf(p?.mainPosition, p?.position);
            }

            // Önce mevki (Kaleci → Defans → Orta Saha → Forvet), sonra numara.
            int order(MatchRosterModel a, MatchRosterModel b) {
              final c = lineOf(a).compareTo(lineOf(b));
              if (c != 0) return c;
              return _jerseyValue(
                jerseyOf(a),
              ).compareTo(_jerseyValue(jerseyOf(b)));
            }

            // İlk 11: oyuncunun kayıtlı mevkisi değil, o maçın diziliş
            // sahasındaki sırası (kaleci → defans → orta saha → forvet).
            final starterRosters = rosters.where((r) => r.isStarting).toList();
            final formationIds = starterIdsInFormationOrder(
              starters: starterRosters,
              players: byId,
              formation: teamId == match.homeTeamId
                  ? match.homeFormation
                  : match.awayFormation,
            );
            final starterById = {for (final r in starterRosters) r.playerId: r};
            final starters = [
              for (final id in formationIds)
                if (starterById[id] != null) starterById[id]!,
            ];
            final gkId = formationIds.isEmpty ? null : formationIds.first;
            final subs = rosters.where((r) => !r.isStarting).toList()
              ..sort(order);

            List<Widget> rows(List<MatchRosterModel> list, {bool xi = false}) {
              return [
                for (final r in list)
                  _row(
                    playerId: r.playerId,
                    jersey: jerseyOf(r),
                    name: byId[r.playerId]?.name ?? '-',
                    // İlk 11'de kaleci: sahadaki kaleci; yedeklerde mevki.
                    line: xi ? (r.playerId == gkId ? 0 : 1) : lineOf(r),
                    isCaptain: r.isCaptain,
                  ),
              ];
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...rows(starters, xi: true),
                if (subs.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _section('Yedekler'),
                  ...rows(subs),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 14,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _row({
    required String playerId,
    required String jersey,
    required String name,
    required int line,
    bool isCaptain = false,
  }) {
    final isGk = line == 0;
    final badge = isGk ? const Color(0xFFF59E0B) : color;
    // İsme dokununca oyuncu kartı açılır.
    return Builder(
      builder: (context) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: playerId.trim().isEmpty
            ? null
            : () =>
                  showPlayerCard(context, playerKey: playerId, number: jersey),
        child: _rowBody(jersey, name, badge, isCaptain),
      ),
    );
  }

  Widget _rowBody(String jersey, String name, Color badge, bool isCaptain) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badge.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              jersey.isEmpty ? '-' : jersey,
              style: TextStyle(
                color: badge,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
          if (isCaptain) ...[
            const SizedBox(width: 5),
            const CaptainBadge(size: 14),
          ],
        ],
      ),
    );
  }
}

class _RosterEditSheet extends StatefulWidget {
  final MatchModel match;
  final String teamId;
  final String teamName;
  final bool isHome;

  const _RosterEditSheet({
    required this.match,
    required this.teamId,
    required this.teamName,
    required this.isHome,
  });

  @override
  State<_RosterEditSheet> createState() => _RosterEditSheetState();
}

class _RosterEditSheetState extends State<_RosterEditSheet> {
  final _teamService = ServiceLocator.teamService;
  final _matchService = ServiceLocator.matchService;

  List<PlayerModel> _teamPlayers = [];
  final Set<String> _starterIds = {};
  final Set<String> _subIds = {};
  String? _captainId;
  final Map<String, TextEditingController> _jerseyControllers = {};
  final _searchController = TextEditingController();
  String _query = '';
  bool _isLoading = true;
  bool _isSaving = false;

  int _startingLimit = 11;
  int _subLimit = 7;

  /// Bu sezonda onaylı ve süren cezası olan oyuncular (kadroya eklenemez).
  Map<String, PlayerPenalty> _penalized = const {};

  static const _green = Color(0xFF10B981);
  static const _blue = Color(0xFF3B82F6);
  static const _mid = Color(0xFF94A3B8);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    for (final c in _jerseyControllers.values) {
      c.dispose();
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      // Sezon ayarları, oyuncular ve kadro paralel çekilir.
      Future<Map<String, dynamic>?> loadSeasonLimits() async {
        if (widget.match.seasonId.isEmpty) return null;
        try {
          return await Supabase.instance.client
              .from('seasons')
              .select('starting_player_count, sub_player_count')
              .eq('id', widget.match.seasonId)
              .maybeSingle();
        } catch (_) {
          return null;
        }
      }

      Future<Map<String, PlayerPenalty>> loadPenalties() async {
        try {
          return await PenaltyService()
              .watchActivePenaltiesByPlayerId(widget.match.seasonId)
              .first;
        } catch (_) {
          return const {};
        }
      }

      final (sRes, players, rosters, penalties) = await (
        loadSeasonLimits(),
        _teamService.getEligiblePlayers(widget.teamId, widget.match.seasonId),
        _matchService.watchMatchRosters(widget.match.id, widget.teamId).first,
        loadPenalties(),
      ).wait;
      final int sCount = sRes?['starting_player_count'] ?? 11;
      final int subCount = sRes?['sub_player_count'] ?? 7;

      if (!mounted) return;
      setState(() {
        _startingLimit = sCount;
        _subLimit = subCount;
        _teamPlayers = players;
        _penalized = penalties;
        // Kayıtlı kaleci (pos_x = 0) ilk sırada: yeniden kaydedince kaleci
        // olarak kalır.
        final gk = rosters
            .where((x) => x.isStarting && x.slot == 0)
            .firstOrNull;
        if (gk != null) _starterIds.add(gk.playerId);
        for (final p in _teamPlayers) {
          final pid = p.id;
          final r = rosters.where((x) => x.playerId == pid).firstOrNull;
          if (r != null) {
            (r.isStarting ? _starterIds : _subIds).add(pid);
            if (r.isCaptain && r.isStarting) _captainId = pid;
          }
          _jerseyControllers[pid] = TextEditingController(
            text: r?.jerseyNumber ?? p.number ?? '',
          );
        }
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _tab = 0; // 0: İlk 11, 1: Yedekler

  String _norm(String s) =>
      s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase().trim();

  /// Mevki (Kaleci → Forvet), sonra forma numarası sırası.
  List<PlayerModel> get _ordered {
    final list = [..._teamPlayers];
    list.sort((a, b) {
      final la = positionLineOf(a.mainPosition, a.position);
      final lb = positionLineOf(b.mainPosition, b.position);
      if (la != lb) return la.compareTo(lb);
      final c = _jerseyValue(
        _jerseyControllers[a.id]?.text,
      ).compareTo(_jerseyValue(_jerseyControllers[b.id]?.text));
      return c != 0 ? c : a.name.compareTo(b.name);
    });
    return list;
  }

  /// İlk 11 tamamlanınca kalan oyuncuları yedek kontenjanı kadar ekler.
  void _autoFillSubs() {
    if (_starterIds.length < _startingLimit) return;
    for (final p in _ordered) {
      if (_subIds.length >= _subLimit) break;
      if (!_starterIds.contains(p.id) && _penalized[p.id] == null) {
        _subIds.add(p.id);
      }
    }
  }

  void _toggleStarter(String pid) {
    if (_starterIds.contains(pid)) {
      setState(() {
        _starterIds.remove(pid);
        if (_captainId == pid) _captainId = null;
      });
      return;
    }
    if (_blockedByPenalty(pid)) return;
    if (_starterIds.length >= _startingLimit) {
      _toast('İlk 11 dolu ($_startingLimit). Önce birini çıkarın.');
      return;
    }
    setState(() {
      _starterIds.add(pid);
      _subIds.remove(pid);
      _autoFillSubs();
    });
  }

  void _toggleSub(String pid) {
    if (_subIds.contains(pid)) {
      setState(() => _subIds.remove(pid));
      return;
    }
    if (_blockedByPenalty(pid)) return;
    if (_subIds.length >= _subLimit) {
      _toast('Yedek kontenjanı dolu ($_subLimit).');
      return;
    }
    setState(() => _subIds.add(pid));
  }

  /// Cezalı oyuncu bu turnuvanın maç kadrosuna eklenemez (başka turnuvayı
  /// etkilemez; ceza sezona bağlı).
  bool _blockedByPenalty(String pid) {
    final p = _penalized[pid];
    if (p == null) return false;
    final left = p.remainingMatches ?? p.matchCount;
    _toast('Bu oyuncu cezalı ($left maç kaldı); kadroya eklenemez.');
    return true;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
  }

  Future<void> _showError(String msg) {
    return showAdminInfoDialog(context: context, title: 'Hata', message: msg);
  }

  Future<void> _save() async {
    final selectedIds = {..._starterIds, ..._subIds};
    final numericRegExp = RegExp(r'^\d+$');
    final usedNumbers = <String>{};

    for (final pid in selectedIds) {
      final numberText = _jerseyControllers[pid]?.text.trim() ?? '';
      if (numberText.isEmpty || !numericRegExp.hasMatch(numberText)) {
        await _showError(
          'Lütfen seçilen tüm oyuncuların forma numaralarını kontrol ediniz '
          '(Sadece sayı girilmelidir).',
        );
        return;
      }
      if (!usedNumbers.add(numberText)) {
        await _showError(
          'Aynı takımda birden fazla oyuncu aynı forma numarasını kullanamaz '
          '($numberText).',
        );
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      final newRosters = <MatchRosterModel>[];
      for (final p in _teamPlayers) {
        final pid = p.id;
        final isStarter = _starterIds.contains(pid);
        if (!isStarter && !_subIds.contains(pid)) continue;
        newRosters.add(
          MatchRosterModel(
            id: '',
            matchId: widget.match.id,
            leagueId: widget.match.leagueId,
            seasonId: widget.match.seasonId,
            teamId: widget.teamId,
            playerId: pid,
            isHome: widget.isHome,
            isStarting: isStarter,
            jerseyNumber: _jerseyControllers[pid]?.text.trim(),
            isCaptain: isStarter && pid == _captainId,
            // İlk seçilen ilk 11 oyuncusu kaleci olarak kaydedilir.
            slot: isStarter && pid == _starterIds.first ? 0 : null,
          ),
        );
      }

      await _matchService.updateMatchRoster(
        matchId: widget.match.id,
        leagueId: widget.match.leagueId,
        seasonId: widget.match.seasonId,
        teamId: widget.teamId,
        isHome: widget.isHome,
        rosters: newRosters,
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _toast('Hata: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _tabButton(int index, String label, int value, int limit, Color c) {
    final on = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
          decoration: BoxDecoration(
            color: on ? c.withValues(alpha: 0.22) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: on ? c : Colors.white.withValues(alpha: 0.12),
              width: on ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: on ? Colors.white : Colors.white60,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Text(
                '$value / $limit',
                style: TextStyle(
                  color: on ? c : Colors.white54,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _playerRow(PlayerModel p, {required bool starterTab}) {
    final pid = p.id;
    final selected = starterTab
        ? _starterIds.contains(pid)
        : _subIds.contains(pid);
    final color = starterTab ? _green : _blue;
    final sub = (p.position ?? '').trim();
    final isCaptain = _captainId == pid;

    return GestureDetector(
      onTap: () => starterTab ? _toggleStarter(pid) : _toggleSub(pid),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 38,
              child: TextField(
                controller: _jerseyControllers[pid],
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: '#',
                  isDense: true,
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.3),
                  contentPadding: const EdgeInsets.symmetric(vertical: 7),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: p.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                  children: [
                    if (starterTab &&
                        selected &&
                        _starterIds.isNotEmpty &&
                        _starterIds.first == pid)
                      const TextSpan(
                        text: '  KALECİ',
                        style: TextStyle(
                          color: Color(0xFFFBBF24),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                    if (sub.isNotEmpty)
                      TextSpan(
                        text: '  $sub',
                        style: const TextStyle(
                          color: _mid,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_penalized[pid] != null)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Cezalı · ${_penalized[pid]!.remainingMatches ?? _penalized[pid]!.matchCount} maç',
                  style: const TextStyle(
                    color: Color(0xFFF87171),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            if (starterTab && selected)
              GestureDetector(
                onTap: () =>
                    setState(() => _captainId = isCaptain ? null : pid),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Opacity(
                    opacity: isCaptain ? 1 : 0.3,
                    child: const CaptainBadge(size: 20),
                  ),
                ),
              ),
            const SizedBox(width: 4),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? color : Colors.white30,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final q = _norm(_query);
    final starterTab = _tab == 0;

    // İlk 11 sekmesi: tüm kadro. Yedekler: ilk 11 dışındakiler.
    final visible = _ordered.where((p) {
      if (!starterTab && _starterIds.contains(p.id)) return false;
      return q.isEmpty || _norm(p.name).contains(q);
    }).toList();
    final groups = List.generate(4, (_) => <PlayerModel>[]);
    for (final p in visible) {
      groups[positionLineOf(p.mainPosition, p.position)].add(p);
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.92,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: 'Esame Listesi',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                        children: [
                          TextSpan(
                            text: '  ${widget.teamName}',
                            style: const TextStyle(
                              color: _mid,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (!_isLoading)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    _tabButton(
                      0,
                      'İlk 11',
                      _starterIds.length,
                      _startingLimit,
                      _green,
                    ),
                    const SizedBox(width: 8),
                    _tabButton(1, 'Yedekler', _subIds.length, _subLimit, _blue),
                  ],
                ),
              ),
            if (!_isLoading)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Oyuncu ara',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _teamPlayers.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Bu takımın sezon kadrosunda oyuncu yok.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      children: [
                        for (var i = 0; i < groups.length; i++)
                          if (groups[i].isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
                              child: Text(
                                positionLineLabels[i],
                                style: const TextStyle(
                                  color: _mid,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            ...groups[i].map(
                              (p) => _playerRow(p, starterTab: starterTab),
                            ),
                          ],
                      ],
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isSaving || _isLoading ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'KAYDET',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// DETAY TABI (MAÇ AKIŞI)
// -----------------------------------------------------------------------------

class _DetailTab extends StatefulWidget {
  final MatchModel match;
  const _DetailTab({required this.match});

  @override
  State<_DetailTab> createState() => _DetailTabState();
}

class _DetailTabState extends State<_DetailTab>
    with AutomaticKeepAliveClientMixin {
  late final Stream<List<Map<String, dynamic>>> _eventsStream = ServiceLocator
      .matchService
      .watchInlineMatchEvents(widget.match.id);
  late final Future<int> _periodFuture = _DetailTabView._periodMinutes(
    widget.match.seasonId,
  );

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _DetailTabView(
      match: widget.match,
      eventsStream: _eventsStream,
      periodFuture: _periodFuture,
    );
  }
}

class _DetailTabView extends StatelessWidget {
  final MatchModel match;
  final Stream<List<Map<String, dynamic>>> eventsStream;
  final Future<int> periodFuture;
  const _DetailTabView({
    required this.match,
    required this.eventsStream,
    required this.periodFuture,
  });

  String _friendlyLoadError(Object? error) {
    final s = (error ?? '').toString();
    final lower = s.toLowerCase();
    if (lower.contains('permission-denied')) {
      return 'Yetki hatası. Giriş yapıldı mı ve kullanıcı yetkisi doğru mu kontrol edin.\n\n$s';
    }
    if (lower.contains('requires an index') ||
        lower.contains('failed-precondition')) {
      return 'Sorgu için Firestore index gerekli olabilir.\n\n$s';
    }
    if (lower.contains('unavailable') || lower.contains('network')) {
      return 'Bağlantı hatası. İnternet bağlantısını kontrol edin.\n\n$s';
    }
    return s;
  }

  int _readMinute(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    final s = v.toString().replaceAll('\u0000', '').trim();
    return int.tryParse(s) ??
        double.tryParse(s.replaceAll(',', '.'))?.toInt() ??
        0;
  }

  String _readString(dynamic v) => (v ?? '').toString().trim();

  Map<String, dynamic> _asMap(dynamic v) =>
      (v is Map) ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

  /// Sezon başına devre süresi (dk) önbelleği.
  static final Map<String, Future<int>> _periodBySeason = {};

  /// `seasons.match_period_duration` = TEK DEVRE süresi.
  /// Devre arası bu değer, maç sonu bu değerin iki katıdır.
  static Future<int> _periodMinutes(String seasonId) {
    final sid = seasonId.trim();
    if (sid.isEmpty) return Future.value(45);
    return _periodBySeason.putIfAbsent(sid, () async {
      try {
        final res = await Supabase.instance.client
            .from('seasons')
            .select('match_period_duration')
            .eq('id', sid)
            .limit(1);
        if (res.isEmpty) return 45;
        final v = res.first['match_period_duration'];
        final m = v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
        return m > 0 ? m : 45;
      } catch (_) {
        _periodBySeason.remove(sid); // hata kalıcı önbelleğe alınmasın
        return 45;
      }
    });
  }

  List<Map<String, dynamic>> _fallbackSystemStory(int period) {
    switch (match.status) {
      case MatchStatus.notStarted:
        return <Map<String, dynamic>>[
          {'minute': 0, 'type': 'status', 'title': 'Maç Henüz Başlamadı'},
        ];
      case MatchStatus.postponed:
        return <Map<String, dynamic>>[
          {'minute': 0, 'type': 'status', 'title': 'Maç Ertelendi'},
        ];
      case MatchStatus.cancelled:
        return <Map<String, dynamic>>[
          {'minute': 0, 'type': 'status', 'title': 'Maç İptal Edildi'},
        ];
      case MatchStatus.live:
        return <Map<String, dynamic>>[
          {'minute': 0, 'type': 'status', 'title': 'Maç Başladı'},
          // 2. yarı oynanıyorsa ilk yarı bitmiştir.
          if (match.secondHalfAt != null)
            {'minute': period, 'type': 'status', 'title': 'İlk Yarı Bitti'},
        ];
      case MatchStatus.halftime:
        return <Map<String, dynamic>>[
          {'minute': 0, 'type': 'status', 'title': 'Maç Başladı'},
          {'minute': period, 'type': 'status', 'title': 'İlk Yarı Bitti'},
        ];
      case MatchStatus.finished:
        return <Map<String, dynamic>>[
          {'minute': 0, 'type': 'status', 'title': 'Maç Başladı'},
          {'minute': period, 'type': 'status', 'title': 'İlk Yarı Bitti'},
          {'minute': period * 2, 'type': 'status', 'title': 'Maç Bitti'},
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: periodFuture,
      builder: (context, periodSnap) {
        if (!periodSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return _buildFlow(context, periodSnap.data!);
      },
    );
  }

  Widget _buildFlow(BuildContext context, int period) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: eventsStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Maç akışı yüklenemedi.\n\n${_friendlyLoadError(snap.error)}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final raw = snap.data ?? const <Map<String, dynamic>>[];

        final systemStory = _fallbackSystemStory(period);
        final List<Map<String, dynamic>> normalized = raw
            .map((e) => _asMap(e))
            .toList();

        String pickType(Map<String, dynamic> e) {
          return _readString(e['type']).isNotEmpty
              ? _readString(e['type'])
              : _readString(e['eventType']).isNotEmpty
              ? _readString(e['eventType'])
              : _readString(e['event_type']);
        }

        String pickTitle(Map<String, dynamic> e) {
          final a = _readString(e['playerName']);
          if (a.isNotEmpty) return a;
          final b = _readString(e['player_name']);
          if (b.isNotEmpty) return b;
          final c = _readString(e['title']);
          if (c.isNotEmpty) return c;
          final d = _readString(e['event_name']);
          if (d.isNotEmpty) return d;
          return _readString(e['eventType']).isNotEmpty
              ? _readString(e['eventType'])
              : _readString(e['event_type']);
        }

        String pickTeamId(Map<String, dynamic> e) {
          final a = _readString(e['teamId']);
          if (a.isNotEmpty) return a;
          return _readString(e['team_id']);
        }

        bool isSystem(Map<String, dynamic> e) {
          final t = pickType(e);
          final et = _readString(e['eventType']).isNotEmpty
              ? _readString(e['eventType'])
              : _readString(e['event_type']);
          if (t == 'status' || t == 'system') return true;
          if (et == 'status' || et == 'system') return true;
          if (pickTeamId(e).isEmpty && pickTitle(e).isNotEmpty) return true;
          return false;
        }

        if (normalized.isEmpty) {
          normalized.addAll(systemStory);
        } else {
          final existingTitleKeys = normalized
              .map((e) => pickTitle(e).toLowerCase())
              .where((s) => s.isNotEmpty)
              .toSet();
          for (final s in systemStory) {
            final key = pickTitle(s).toLowerCase();
            if (key.isNotEmpty && !existingTitleKeys.contains(key)) {
              normalized.add(s);
            }
          }
        }

        normalized.sort((a, b) {
          final am = _readMinute(a['minute']);
          final bm = _readMinute(b['minute']);
          if (am != bm) return am.compareTo(bm);
          final at = pickType(a);
          final bt = pickType(b);
          return at.compareTo(bt);
        });

        String pickPlayerId(Map<String, dynamic> e) {
          final a = _readString(e['player_id']);
          if (a.isNotEmpty) return a;
          return _readString(e['playerId']);
        }

        // Aynı oyuncunun maçtaki ikinci sarısı "çift sarıdan ihraç" gösterilir.
        final secondYellows = <Map<String, dynamic>>{};
        final yellowSeen = <String>{};
        for (final e in normalized) {
          if (pickType(e) != 'yellow_card') continue;
          final pid = pickPlayerId(e);
          final key = pid.isNotEmpty
              ? pid
              : '${pickTeamId(e)}|${pickTitle(e).toLowerCase()}';
          if (!yellowSeen.add(key)) secondYellows.add(e);
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: normalized.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, i) {
            if (i == 0) {
              return const Text(
                'Maç Detayı',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              );
            }
            final e = normalized[i - 1];
            final type = secondYellows.contains(e)
                ? 'second_yellow'
                : pickType(e);
            final title = pickTitle(e);
            final minute = _readMinute(e['minute']);
            final teamId = pickTeamId(e);
            final system = isSystem(e);

            final subIn = _readString(e['subInPlayerName']).isNotEmpty
                ? _readString(e['subInPlayerName'])
                : _readString(e['sub_in_player_name']);
            final assist = _readString(e['assistPlayerName']).isNotEmpty
                ? _readString(e['assistPlayerName'])
                : _readString(e['assist_player_name']);
            final isOwnGoal =
                (e['isOwnGoal'] as bool?) ??
                (e['is_own_goal'] as bool?) ??
                false;

            String displayTitle() {
              if (type == 'substitution') {
                return title.isEmpty ? 'Değişiklik' : title;
              }
              if (type == 'goal') {
                final suffix = isOwnGoal ? ' (KK)' : '';
                return '${title.isEmpty ? 'Gol' : title}$suffix';
              }
              return title;
            }

            return _DetailEventTile(
              minute: minute,
              fullTime: period * 2,
              type: type,
              title: displayTitle(),
              // Asist, gol atanın altında daha küçük ve soluk gösterilir.
              subtitle: type == 'goal' && assist.isNotEmpty
                  ? 'Asist: $assist'
                  : type == 'second_yellow'
                  ? 'Çift sarıdan ihraç'
                  : null,
              subInName: type == 'substitution' ? subIn : '',
              teamId: teamId,
              homeTeamId: match.homeTeamId,
              system: system,
              playerId: pickPlayerId(e),
            );
          },
        );
      },
    );
  }
}

class _DetailEventTile extends StatelessWidget {
  final int minute;

  /// Normal maç süresi (2 devre); aşan dakika "60+4'" gösterilir.
  final int fullTime;
  final String type;
  final String title;
  final String? subtitle;

  /// Oyuncu değişikliğinde giren oyuncu; [title] çıkan oyuncudur.
  final String subInName;
  final String teamId;
  final String homeTeamId;
  final bool system;

  /// Dolu ise satıra dokununca oyuncu kartı açılır.
  final String playerId;
  const _DetailEventTile({
    required this.minute,
    required this.fullTime,
    required this.type,
    required this.title,
    this.subtitle,
    this.subInName = '',
    required this.teamId,
    required this.homeTeamId,
    required this.system,
    this.playerId = '',
  });

  Widget _systemIcon(String title) {
    final t = title.toLowerCase();
    if (t.contains('başla')) {
      return const Icon(Icons.play_arrow_rounded);
    }
    if (t.contains('devre') || t.contains('yarı')) {
      return const Icon(Icons.timelapse_rounded);
    }
    if (t.contains('bitti') || t.contains('son')) {
      return const Icon(Icons.flag_rounded);
    }
    return const Icon(Icons.info_outline);
  }

  /// Değişiklik: giren oyuncu (yeşil ▲) üstte, çıkan oyuncu (kırmızı ▼)
  /// altında soluk.
  Widget _substitutionBlock(bool isHome) {
    Widget line(String name, bool isIn) {
      final arrow = Icon(
        isIn ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
        size: 14,
        color: isIn ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
      );
      final text = Flexible(
        child: Text(
          name,
          overflow: TextOverflow.ellipsis,
          style: isIn
              ? const TextStyle(fontWeight: FontWeight.bold)
              : const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w500,
                ),
        ),
      );
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: isHome
            ? [arrow, const SizedBox(width: 4), text]
            : [text, const SizedBox(width: 4), arrow],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: isHome
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        line(subInName, true),
        const SizedBox(height: 2),
        line(title.isEmpty ? '-' : title, false),
      ],
    );
  }

  Widget _titleBlock(CrossAxisAlignment align) {
    if (type == 'substitution' && subInName.isNotEmpty) {
      return _substitutionBlock(align == CrossAxisAlignment.start);
    }
    final sub = (subtitle ?? '').trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align,
      children: [
        Text(
          title.isEmpty ? '-' : title,
          style: const TextStyle(fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        if (sub.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              sub,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isHome = teamId == homeTeamId;
    // Maçın adamının dakikası yoktur.
    final String min = type == 'man_of_the_match'
        ? ''
        : minute > fullTime
        ? "$fullTime+${minute - fullTime}'"
        : "$minute'";

    Widget icon;
    if (system) {
      icon = _systemIcon(title);
    } else {
      switch (type) {
        case 'goal':
          icon = const Icon(Icons.sports_soccer, size: 18, color: Colors.white);
          break;
        case 'yellow_card':
          icon = const Icon(Icons.rectangle, color: Colors.yellow, size: 18);
          break;
        case 'red_card':
          icon = const Icon(Icons.rectangle, color: Colors.red, size: 18);
          break;
        case 'second_yellow':
          icon = const _SecondYellowCardIcon();
          break;
        case 'substitution':
          // Giren/çıkan okları yeterli; ayrıca ikon gösterilmez.
          icon = const SizedBox.shrink();
          break;
        case 'man_of_the_match':
          icon = const Icon(Icons.star_rounded, size: 18, color: Colors.amber);
          break;
        default:
          icon = const Icon(Icons.info_outline, size: 18);
      }
    }

    final tile = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: system
          ? Row(
              children: [
                Expanded(
                  child: Divider(
                    color: Colors.white.withValues(alpha: 0.12),
                    height: 1,
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        min,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.amber,
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconTheme(
                        data: const IconThemeData(
                          size: 13,
                          color: Colors.white60,
                        ),
                        child: icon,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        title.isEmpty ? '-' : title,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white70,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Divider(
                    color: Colors.white.withValues(alpha: 0.12),
                    height: 1,
                  ),
                ),
              ],
            )
          : Row(
              mainAxisAlignment: isHome
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.end,
              children: isHome
                  ? [
                      Text(
                        min,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                      const SizedBox(width: 8),
                      icon,
                      const SizedBox(width: 8),
                      Flexible(child: _titleBlock(CrossAxisAlignment.start)),
                    ]
                  : [
                      Flexible(child: _titleBlock(CrossAxisAlignment.end)),
                      const SizedBox(width: 8),
                      icon,
                      const SizedBox(width: 8),
                      Text(
                        min,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                    ],
            ),
    );
    if (playerId.isEmpty) return tile;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showPlayerCard(context, playerKey: playerId),
      child: tile,
    );
  }
}

/// Maç başlığının zemini: sol kenar ev sahibi, sağ kenar deplasman rengi,
/// ortaya doğru koyu zemine geçer. Üstte silik saha çizgileri, okunurluk için
/// koyu perde ve altta iki takımın diğer renklerinden ince şerit.
class _MatchHeaderPainter extends CustomPainter {
  const _MatchHeaderPainter(this.sides);

  final MatchSideColors sides;

  static const _stripe = 4.0;
  static const _dark = Color(0xFF0F172A);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height - _stripe;
    final rect = Rect.fromLTWH(0, 0, w, h);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          // Hafif eğik geçiş (yaklaşık 15°).
          begin: const Alignment(-1, -0.27),
          end: const Alignment(1, 0.27),
          colors: [
            sides.home,
            Color.lerp(sides.home, _dark, 0.55)!,
            _dark,
            Color.lerp(sides.away, _dark, 0.55)!,
            sides.away,
          ],
          stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.35),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.35),
          ],
          stops: const [0.0, 0.4, 1.0],
        ).createShader(rect),
    );

    // Saha çizgileri: orta çizgi, orta yuvarlak, iki ceza sahası ve yayları.
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.09)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final cy = h * 0.55;
    final r = h * 0.22;
    canvas.drawLine(Offset(w / 2, 0), Offset(w / 2, h), line);
    canvas.drawCircle(Offset(w / 2, cy), r, line);
    canvas.drawCircle(
      Offset(w / 2, cy),
      3,
      Paint()..color = Colors.white.withValues(alpha: 0.12),
    );
    final boxW = w * 0.17, boxH = h * 0.56;
    canvas.drawRect(Rect.fromLTWH(-2, cy - boxH / 2, boxW, boxH), line);
    canvas.drawRect(
      Rect.fromLTWH(w - boxW + 2, cy - boxH / 2, boxW, boxH),
      line,
    );
    final arc = r * 0.65;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(boxW - arc * 0.6, cy), radius: arc),
      -1.0,
      2.0,
      false,
      line,
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset(w - boxW + arc * 0.6, cy), radius: arc),
      2.14,
      2.0,
      false,
      line,
    );

    canvas.drawRect(
      Rect.fromLTWH(0, h, w / 2, _stripe),
      Paint()..color = sides.homeStripe,
    );
    canvas.drawRect(
      Rect.fromLTWH(w / 2, h, w / 2, _stripe),
      Paint()..color = sides.awayStripe,
    );
  }

  @override
  bool shouldRepaint(_MatchHeaderPainter old) => old.sides != sides;
}

/// Esame veya diziliş afişini hazırlayıp önizleme/paylaşım popup'ını açar.
/// [kind] verilmezse ('Esame' / 'Diziliş') kullanıcıya sorulur.
Future<void> shareLineupPoster(
  BuildContext context, {
  required MatchModel match,
  required String homeName,
  required String awayName,
  required String teamId,
  String? kind,
}) async {
  kind ??= await showAdminOptionPicker<String>(
    context: context,
    title: 'Kadroyu Paylaş',
    items: const ['Esame', 'Diziliş'],
    labelBuilder: (k) =>
        k == 'Esame' ? 'Esame (ilk 11 ve yedekler)' : 'Diziliş (sahada ilk 11)',
    emptyText: '',
  );
  if (kind == null || !context.mounted) return;
  await PitchTokenStylePref.load();
  if (!context.mounted) return;
  final m = match;
  final isHome = teamId == m.homeTeamId;
  final opponentId = isHome ? m.awayTeamId : m.homeTeamId;
  final messenger = ScaffoldMessenger.of(context);

  final LineupPosterData data;
  try {
    final db = Supabase.instance.client;
    final results = await Future.wait([
      ServiceLocator.teamService
          .watchPlayers(teamId: teamId, tournamentId: m.seasonId)
          .first,
      ServiceLocator.matchService.watchMatchRosters(m.id, teamId).first,
      db
          .from('teams')
          .select('id, name, logo_url, first_color, second_color')
          .inFilter('id', [teamId, opponentId]),
      db.from('leagues').select('name, logo_url').eq('id', m.leagueId),
    ]);
    final players = {for (final p in results[0] as List<PlayerModel>) p.id: p};
    final rosters = results[1] as List<MatchRosterModel>;
    final teams = {
      for (final r in results[2] as List) (r as Map)['id'].toString(): r,
    };
    final leagueRows = results[3] as List;
    final league = leagueRows.isEmpty ? null : leagueRows.first as Map;

    final starters = rosters.where((r) => r.isStarting).toList();
    if (starters.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Önce ilk 11 girilmelidir.')),
      );
      return;
    }
    String jersey(MatchRosterModel r) =>
        (r.jerseyNumber ?? players[r.playerId]?.number ?? '').trim();
    PosterPlayer toPoster(MatchRosterModel r) => PosterPlayer.fromFullName(
      players[r.playerId]?.name ?? '-',
      number: jersey(r),
      isCaptain: r.isCaptain,
    );
    final byId = {for (final r in rosters) r.playerId: r};
    final layout = formationLinesFor(
      starters: starters,
      players: players,
      formation: isHome ? m.homeFormation : m.awayFormation,
    );
    final subs = rosters.where((r) => !r.isStarting).toList()
      ..sort(
        (a, b) => _jerseyValue(jersey(a)).compareTo(_jerseyValue(jersey(b))),
      );
    final team = teams[teamId];
    final opp = teams[opponentId];
    data = LineupPosterData(
      teamName: isHome ? homeName : awayName,
      teamLogo: (team?['logo_url'] ?? '').toString().trim(),
      opponentName: isHome ? awayName : homeName,
      opponentLogo: (opp?['logo_url'] ?? '').toString().trim(),
      isHome: isHome,
      leagueName: (league?['name'] ?? '').toString(),
      leagueLogo: (league?['logo_url'] ?? '').toString().trim(),
      week: m.week,
      matchDate: m.matchDate ?? '',
      timeText: (m.matchTime ?? '').trim(),
      pitchName: (m.pitchName ?? '').trim(),
      palette: TeamPalette.of(
        team?['first_color']?.toString(),
        team?['second_color']?.toString(),
      ),
      formation: layout?.formation ?? '',
      lines: [
        for (final line in layout?.lines ?? const <List<String>>[])
          [
            for (final id in line)
              if (byId[id] != null) toPoster(byId[id]!),
          ],
      ],
      subs: [for (final r in subs) toPoster(r)],
      tokenStyle: PitchTokenStylePref.notifier.value,
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Kadro bilgisi okunamadı: $e')),
    );
    return;
  }
  if (!context.mounted) return;
  final slug = data.teamName.replaceAll(RegExp(r'\s+'), '_');
  await showPosterPreview(
    context: context,
    fileName: kind == 'Esame' ? 'esame_$slug' : 'dizilis_$slug',
    imageUrls: [data.teamLogo, data.opponentLogo, data.leagueLogo],
    poster: kind == 'Esame'
        ? LineupListPoster(data: data)
        : LineupPitchPoster(data: data),
  );
}
