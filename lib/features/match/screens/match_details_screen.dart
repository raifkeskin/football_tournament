import '../widgets/quick_event_entry.dart';
import '../widgets/quick_score_dialog.dart';
import '../../../core/services/active_tournament.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../player/widgets/player_card.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../../tournament/models/league_extras.dart';
import '../models/match.dart';
import '../widgets/attendance_card.dart';
import '../widgets/match_control_bar.dart';
import '../widgets/penalty_badge.dart';
import '../widgets/shootout_board.dart';
import 'esame_edit_screen.dart';
import '../models/match_media.dart';
import '../../team/models/team.dart';
import '../../../core/utils/team_name.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../../core/services/app_session.dart';
import '../widgets/match_schedule_dialog.dart';
import '../../../core/services/app_settings.dart';
import '../../../core/services/image_upload_service.dart';
import '../../tournament/services/interfaces/i_league_service.dart';
import '../services/interfaces/i_match_service.dart';
import '../services/supabase/supabase_match_service.dart';
import '../../team/services/interfaces/i_team_service.dart';
import '../../../core/services/service_locator.dart';
import 'admin_match_event_screen.dart';
import '../../tournament/screens/formation_tab.dart';
import '../../share/poster_background.dart';
import '../../share/lineup_poster.dart';
import '../../share/match_poster.dart';
import '../../share/match_result_poster.dart';
import '../../share/poster_share.dart';
import '../../share/pre_match_video.dart';
import '../../share/squad_poster.dart';
import '../../../core/utils/team_colors.dart';
import '../../../core/widgets/pitch_token_style.dart';
import 'package:football_tournament/core/widgets/picked_image.dart';
import '../utils/match_clock.dart';
import '../utils/minute_label.dart';
import '../services/match_highlight_service.dart';
import '../widgets/match_highlights_section.dart';
import '../../media_credits/media_credit.dart';
import '../../media_credits/media_credit_card.dart';
import '../widgets/youtube_find_sheet.dart';
import '../widgets/match_weather.dart';
import '../services/youtube_autolink_service.dart';
import '../../team/screens/team_squad_screen.dart';
import 'package:football_tournament/core/widgets/admin_page.dart';
import 'package:football_tournament/core/widgets/admin_form.dart';
import '../../../core/widgets/app_name_band.dart';
import '../../../core/widgets/match_event_icons.dart';
import '../../../core/services/video_link.dart';
import '../../../core/widgets/youtube_player_page.dart'
    show
        openYoutubeClip,
        openYoutubeInApp,
        youtubePlayerOrigin,
        youtubeVideoId,
        YoutubePlayerFrame;
import '../utils/season_match_settings.dart';
import '../../team/screens/groups_screen.dart' show StandingsView;

// --- YARDIMCI WIDGETLAR ---

/// Çift sarıdan ihraç: arkada sarı, önde kırmızı kart.
/// Maç akışının ortasındaki dikey çizgi parçası.
class _TimelineLine extends StatelessWidget {
  const _TimelineLine();

  @override
  Widget build(BuildContext context) {
    return Container(width: 2, color: Colors.white.withValues(alpha: 0.1));
  }
}

/// Kaçan penaltı: soluk top, üzerinde kırmızı çarpı.
class _MissedPenaltyIcon extends StatelessWidget {
  const _MissedPenaltyIcon();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 20,
      height: 20,
      child: Stack(
        alignment: Alignment.center,
        children: [
          BallIcon(tint: BallTint.grey),
          Icon(Icons.close_rounded, size: 20, color: Colors.redAccent),
        ],
      ),
    );
  }
}

/// VAR ile iptal edilen gol: soluk top, sağ altında kırmızı X rozeti.
class _CancelledGoalIcon extends StatelessWidget {
  const _CancelledGoalIcon({this.base = const BallIcon(tint: BallTint.grey)});

  /// İptal edilen olayın soluk ikonu (varsayılan top; kartta kart).
  final Widget base;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          base,
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF0F172A), width: 1),
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 8,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Penaltı golü: top, altında "P" rozeti.
class _PenaltyGoalIcon extends StatelessWidget {
  const _PenaltyGoalIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const BallIcon(),
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                'P',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondYellowCardIcon extends StatelessWidget {
  const _SecondYellowCardIcon();

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
            child: Transform.rotate(
              angle: -0.2,
              child: const RefereeCardIcon.yellow(height: 15),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Transform.rotate(
              angle: 0.15,
              child: const RefereeCardIcon.red(height: 15),
            ),
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
  final String teamId;
  final String seasonId;
  final String? firstColor;
  final String? secondColor;

  const _TeamInfo({
    required this.name,
    required this.logoUrl,
    required this.teamId,
    required this.seasonId,
    this.firstColor,
    this.secondColor,
  });

  @override
  Widget build(BuildContext context) {
    // Logoya / ada dokununca takımın sayfası (kadro, fikstür, istatistik).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: teamId.isEmpty
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: 'TeamSquadScreen'),
                builder: (_) => TeamSquadScreen(
                  teamId: teamId,
                  tournamentId: seasonId,
                  teamName: name,
                  teamLogoUrl: logoUrl,
                  initialFirstColor: firstColor,
                  initialSecondColor: secondColor,
                ),
              ),
            ),
      child: _content(),
    );
  }

  Widget _content() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Şeffaf logolar kırpılmadan, çerçevesiz gösterilir.
        WebSafeImage(
          url: logoUrl,
          // Her sekmede aynı boy (Diziliş'te küçülmez).
          width: 46,
          height: 46,
          fit: BoxFit.contain,
          fallbackIconSize: 24,
        ),
        const SizedBox(height: 3),
        Text(
          shortTeamName(name),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            // 700: uzun adlar da okunur kalsın.
            fontWeight: FontWeight.w700,
            fontSize: 14,
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
          MatchStatus.live when match.shootout != null => (
            'PENALTILAR',
            const Color(0xFFFBBF24),
          ),
          MatchStatus.live => (liveMinute ?? 'CANLI', const Color(0xFFF87171)),
          MatchStatus.halftime => ('İY', const Color(0xFFFBBF24)),
          // Uzatmada biten eleme maçı (penaltıya kalmadan).
          MatchStatus.finished
              when match.extraTimeAt != null && !match.hasPens =>
            ('MS · UZATMADA', const Color(0xFF10B981)),
          MatchStatus.finished => ('MS', const Color(0xFF10B981)),
          // Yeni güne alınmış ertelenen maç: "Ertelenen Maç".
          MatchStatus.postponed => (
            match.isRescheduled ? 'ERTELENEN MAÇ' : 'ERTELENDİ',
            Colors.white70,
          ),
          MatchStatus.cancelled => ('İPTAL', Colors.white70),
          MatchStatus.notStarted => (null, Colors.transparent),
        };
        if (text == null) return const SizedBox.shrink();
        return Text(
          text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
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
  const _MatchFlowBar({
    required this.match,
    required this.onAction,
    this.canUndo = false,
  });

  final MatchModel match;
  final Future<void> Function(String action) onAction;

  /// "Geri Al": son devre adımını geri alır (admin ve kurucu başkan).
  final bool canUndo;

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
          // Ertelenen maç yeni tarihinde doğrudan başlatılır.
          MatchStatus.notStarted || MatchStatus.postponed => (
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
          // Eleme maçı berabere: önce uzatma (kural izin veriyorsa), sonra
          // penaltılar. Atışlar sürerken düğme yerine atış paneli görünür.
          MatchStatus.live
              when m.isKnockout &&
                  m.homeScore == m.awayScore &&
                  m.shootout == null &&
                  m.tiebreak == 'et_pens' &&
                  m.extraTimeAt == null =>
            (
              action: 'start_extra_time',
              label: 'Uzatmaya Geç',
              icon: Icons.more_time_rounded,
              color: const Color(0xFFF59E0B),
            ),
          MatchStatus.live
              when m.isKnockout &&
                  m.homeScore == m.awayScore &&
                  m.shootout == null =>
            (
              action: 'start_shootout',
              label: 'Penaltılara Geç',
              icon: Icons.sports_soccer_rounded,
              color: const Color(0xFFF59E0B),
            ),
          MatchStatus.live
              when m.shootout != null &&
                  m.homeScore == m.awayScore &&
                  !shootoutDecided(m.shootout!) =>
            null,
          MatchStatus.live => (
            action: 'finish',
            label: 'Maçı Bitir',
            icon: Icons.sports_score_rounded,
            color: const Color(0xFFEF4444),
          ),
          _ => null,
        };
    final undo =
        widget.canUndo &&
        m.status != MatchStatus.notStarted &&
        m.status != MatchStatus.postponed;
    if (next == null && !undo) return const SizedBox.shrink();

    Widget pill({
      required String label,
      required IconData icon,
      required Color color,
      required VoidCallback? onTap,
      bool outlined = false,
    }) => SizedBox(
      height: 32,
      child: Material(
        color: outlined ? Colors.white.withValues(alpha: 0.06) : color,
        shape: StadiumBorder(
          side: outlined
              ? const BorderSide(color: Colors.white24)
              : BorderSide.none,
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: _busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_busy && !outlined)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  Icon(icon, size: 17, color: Colors.white),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (next != null)
          pill(
            label: next.label,
            icon: next.icon,
            color: next.color,
            onTap: () => _run(next.action),
          ),
        if (next != null && undo) const SizedBox(width: 6),
        if (undo)
          pill(
            label: 'Geri Al',
            icon: Icons.undo_rounded,
            color: Colors.transparent,
            outlined: true,
            onTap: () => _run('undo'),
          ),
      ],
    );
  }
}

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
  ModalRoute<dynamic>? _bandRoute;

  /// Gruplu maçta 5. sekme: canlı puan durumu.
  late final bool _hasStandings = (widget.match.groupId ?? '')
      .trim()
      .isNotEmpty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_regionOwnerChecked) {
      _regionOwnerChecked = true;
      _checkRegionOwner();
    }
    final route = ModalRoute.of(context);
    if (route == _bandRoute) return;
    if (_bandRoute != null) {
      LeagueSwitchScope.setBandHidden(_bandRoute, false);
    }
    _bandRoute = route;
    LeagueSwitchScope.setBandHidden(route, true);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _hasStandings ? 5 : 4,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _matchStream = _matchService.watchMatch(widget.match.id);
    YoutubeAutolinkService()
        .isEnabled(widget.match.leagueId)
        .then((on) {
          if (mounted && on) setState(() => _youtubeLive = true);
        })
        .catchError((_) {});
    _teamsStream = _teamService.watchSeasonTeams(widget.match.seasonId);
    _pitchesStream = _leagueService.watchPitches();
    _prefetchLineups(widget.match);
  }

  bool _regionOwnerChecked = false;

  /// Maçın bölgesinin sorumlusu mu (Medya sekmesindeki menü için).
  bool _matchRegionOwner = false;

  void _checkRegionOwner() {
    final session = AppSession.of(context).value;
    final m = widget.match;
    final groupId = (m.groupId ?? '').trim();
    if (groupId.isEmpty || session.regionsInSeason(m.seasonId).isEmpty) {
      return;
    }
    Supabase.instance.client
        .from('groups')
        .select('region_id')
        .eq('id', groupId)
        .maybeSingle()
        .then((row) {
          final regionId = row?['region_id']?.toString();
          if (mounted && session.ownedRegions.any((r) => r.id == regionId)) {
            setState(() => _matchRegionOwner = true);
          }
        })
        .catchError((_) {});
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

  /// Maçın yönetimi bende mi (MatchControlBar). Olay girişi, devreler,
  /// penaltı atışları ve skor yalnız yönetende açık.
  bool _hasControl = false;

  /// Maça yayın linki eklenmiş mi; skorun üstündeki yayın butonu açık mı.
  bool _hasStream = false;
  bool _streamOpen = false;

  /// "Maçı yönet" şeridi maç saatinden 1 saat önce açılır; o ana kadar
  /// ekran bir kez yenilenir.
  Timer? _controlOpenTimer;

  static DateTime? _scheduledStart(MatchModel m) {
    final d = DateTime.tryParse((m.matchDate ?? '').trim());
    if (d == null) return null;
    final t = RegExp(
      r'^(\d{1,2}):(\d{2})',
    ).firstMatch((m.matchTime ?? '').trim());
    if (t == null) return null;
    return DateTime(
      d.year,
      d.month,
      d.day,
      int.parse(t.group(1)!),
      int.parse(t.group(2)!),
    );
  }

  /// Başlamamış maçta yönetim saatinden önce mi (maçtan 1 saat öncesine
  /// kadar). Saat bilinmiyorsa kısıt yok.
  bool _beforeControlWindow(MatchModel m) {
    if (m.status != MatchStatus.notStarted &&
        m.status != MatchStatus.postponed) {
      return false;
    }
    final start = _scheduledStart(m);
    if (start == null) return false;
    final opens = start.subtract(const Duration(hours: 1));
    final wait = opens.difference(DateTime.now());
    if (wait <= Duration.zero) return false;
    if (_controlOpenTimer == null && wait < const Duration(days: 1)) {
      _controlOpenTimer = Timer(wait + const Duration(seconds: 1), () {
        _controlOpenTimer = null;
        if (mounted) setState(() {});
      });
    }
    return true;
  }

  /// Golleri afiş için takım tarafına göre toplar: "Kaya 12' 58'",
  /// dakikasız sezonda "Kaya ×2". Kendi kalesine gol rakip tarafa yazılır.
  Future<(List<PosterScorer>, List<PosterScorer>)> _posterScorers(
    MatchModel m,
  ) async {
    final db = Supabase.instance.client;
    final rows = await db
        .from('match_events')
        .select('team_id, minute, player_id, is_own_goal, is_penalty')
        .eq('match_id', m.id)
        .eq('event_type', 'goal');
    // match_events'te ad yok: adlar (soyad değil) oyunculardan okunur.
    final ids = {
      for (final r in rows)
        if ((r['player_id'] ?? '').toString().isNotEmpty) '${r['player_id']}',
    };
    final firstNames = <String, String>{};
    if (ids.isNotEmpty) {
      for (final p
          in await db
              .from('players')
              .select('id, name, surname')
              .inFilter('id', ids.toList())) {
        final name = (p['name'] ?? '').toString().trim();
        final sn = (p['surname'] ?? '').toString().trim();
        // Soyad ayrı sütunda değilse ad alanı "Ad Soyad" olabilir: son
        // kelime soyad sayılır.
        final parts = name.split(RegExp(r'\s+'));
        firstNames['${p['id']}'] = sn.isEmpty && parts.length > 1
            ? parts.sublist(0, parts.length - 1).join(' ')
            : name;
      }
    }
    // taraf → oyuncu → dakikalar (null: dakikasız); aynı adlı iki oyuncu
    // karışmasın diye oyuncu kimliğiyle tutulur.
    final sides = [<String, List<String?>>{}, <String, List<String?>>{}];
    final labels = <String, String>{};
    final firstMinute = <String, int>{};
    for (final r in rows) {
      final own = r['is_own_goal'] == true;
      final team = (r['team_id'] ?? '').toString();
      var home = team == m.homeTeamId;
      if (own) home = !home;
      final pid = (r['player_id'] ?? '').toString();
      final fn = firstNames[pid] ?? '';
      final label = fn.isEmpty ? 'Gol' : fn;
      final key = '$pid|$own';
      labels[key] = own ? '$label (K.K.)' : label;
      final minute = r['minute'] is num ? (r['minute'] as num).toInt() : null;
      final pen = r['is_penalty'] == true && !own;
      (sides[home ? 0 : 1][key] ??= []).add(
        minute == null ? (pen ? '(P)' : null) : "$minute'${pen ? ' (P)' : ''}",
      );
      if (minute != null) {
        firstMinute[key] = minute < (firstMinute[key] ?? 999)
            ? minute
            : firstMinute[key]!;
      }
    }
    List<PosterScorer> build(Map<String, List<String?>> side) {
      final names = side.keys.toList()
        ..sort(
          (a, b) => (firstMinute[a] ?? 999).compareTo(firstMinute[b] ?? 999),
        );
      return [
        for (final n in names)
          (
            name: labels[n]!,
            detail: side[n]!.any((x) => x != null && x.contains("'"))
                ? side[n]!.whereType<String>().join(' ')
                : [
                    if (side[n]!.length > 1) '×${side[n]!.length}',
                    if (side[n]!.contains('(P)')) '(P)',
                  ].join(' '),
          ),
      ];
    }

    return (build(sides[0]), build(sides[1]));
  }

  /// Tek maç afişi. Maç bittiyse Maç Sonucu (skor, gol atanlar), değilse
  /// Maç Afişi (saha, tarih, saat). Gönderi ve hikâye boyutunda.
  Future<void> _shareMatchPoster({
    required MatchModel m,
    required String homeName,
    required String awayName,
    required String homeLogo,
    required String awayLogo,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    String leagueName = '', leagueLogo = '', groupName = '', seasonName = '';
    var homeScorers = <PosterScorer>[], awayScorers = <PosterScorer>[];
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
      final season = await db
          .from('seasons')
          .select('name')
          .eq('id', m.seasonId)
          .maybeSingle();
      seasonName = (season?['name'] ?? '').toString().trim();
      if (m.status == MatchStatus.finished) {
        (homeScorers, awayScorers) = await _posterScorers(m);
      }
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
    final slug = '${homeName}_$awayName'.replaceAll(RegExp(r'\s+'), '_');
    if (m.status == MatchStatus.finished) {
      await showPosterPreview(
        context: context,
        title: 'Maç Sonucunu Paylaş',
        fileName: 'mac_sonucu_$slug',
        imageUrls: [leagueLogo, homeLogo, awayLogo],
        leagueId: m.leagueId,
        kind: PosterKind.match,
        formats: const [PosterFormat.post, PosterFormat.story],
        scorersOption: true,
        poster: MatchResultPoster(
          leagueName: leagueName,
          leagueLogo: leagueLogo,
          subtitle: [
            groupName,
            seasonName,
          ].where((e) => e.isNotEmpty).join(' · '),
          week: m.week,
          homeName: homeName,
          homeLogo: homeLogo,
          awayName: awayName,
          awayLogo: awayLogo,
          homeScore: m.homeScore,
          awayScore: m.awayScore,
          homeScorers: homeScorers,
          awayScorers: awayScorers,
        ),
      );
      return;
    }
    await showPosterPreview(
      context: context,
      title: 'Maç Afişini Paylaş',
      fileName: 'mac_$slug',
      imageUrls: [leagueLogo, homeLogo, awayLogo],
      leagueId: m.leagueId,
      kind: PosterKind.match,
      formats: const [PosterFormat.post, PosterFormat.story],
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

  /// Turnuvada "YouTube canlı yayın" açık mı (menüde "Yayını Bul" için).
  bool _youtubeLive = false;

  /// Medya sekmesindeki menüde "Canlı Yayını Kaldır" için.
  late final Stream<List<MatchMediaModel>> _fabMediaStream = ServiceLocator
      .matchService
      .watchMatchMedia(widget.match.id);

  /// Maçın canlı yayın linkini (linklerini) onayla kaldırır.
  Future<void> _removeLiveStream(List<MatchMediaModel> links) async {
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Canlı Yayını Kaldır',
      message: 'Maçın canlı yayın linki kaldırılacak. Onaylıyor musunuz?',
      confirmLabel: 'KALDIR',
      destructive: true,
      icon: Icons.live_tv_rounded,
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      for (final l in links) {
        await ServiceLocator.matchService.deleteMatchMedia(l.id);
      }
      _triggerRefresh();
      messenger.showSnackBar(
        const SnackBar(content: Text('Canlı yayın linki kaldırıldı.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Kaldırılamadı: $e')));
    }
  }

  @override
  void dispose() {
    LeagueSwitchScope.setBandHidden(_bandRoute, false);
    _controlOpenTimer?.cancel();
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

  static const _hdrShadow = [
    Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 2)),
  ];

  /// Başlamamış maç, skor yerinde: büyük saat, altında tarih ve gün.
  Widget _kickoffBlock(MatchModel m) {
    final time = _kickoffTime(m);
    final d = DateTime.tryParse((m.matchDate ?? '').trim());
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          time ?? '–',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 27,
            height: 1.1,
            fontFeatures: [FontFeature.tabularFigures()],
            shadows: _hdrShadow,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          d == null
              ? 'Tarih Belirlenmedi'
              : DateFormat('d MMMM y', 'tr_TR').format(d),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            shadows: _hdrShadow,
          ),
        ),
        if (d != null)
          Text(
            DateFormat('EEEE', 'tr_TR').format(d),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              shadows: _hdrShadow,
            ),
          ),
        MatchWeatherHeaderLine(matchId: m.id, shadows: _hdrShadow),
      ],
    );
  }

  /// Bandın alt satırı: ortalı stad ve haritaya götüren "Yol tarifi ›".
  /// (Tarih/saat başlamamış maçta ortada, başlamışta üst çubukta.)
  Widget _headerFooter(MatchModel m) {
    const small = TextStyle(
      color: Colors.white,
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      shadows: _hdrShadow,
    );
    final pitchId = (m.pitchId ?? '').trim();
    return SizedBox(
      height: 18,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (pitchId.isNotEmpty)
            Flexible(
              child: StreamBuilder<List<Pitch>>(
                stream: _pitchesStream,
                builder: (context, snap) {
                  Pitch? pitch;
                  for (final p in snap.data ?? const <Pitch>[]) {
                    if (p.id == pitchId) {
                      pitch = p;
                      break;
                    }
                  }
                  final name = pitch?.name ?? (m.pitchName ?? '').trim();
                  final location = (pitch?.location ?? '').trim();
                  if (name.isEmpty) return const SizedBox.shrink();
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        size: 12,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: small,
                        ),
                      ),
                      if (location.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => _openPitchLocation(context, location),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 1),
                            child: Text(
                              'Yol tarifi ›',
                              style: TextStyle(
                                color: Color(0xFF34D399),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                shadows: _hdrShadow,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  /// "6 Ekim 2026 Pazartesi" (kısaltmasız); tarih yoksa null.
  String? _fullDate(MatchModel m) {
    final d = DateTime.tryParse((m.matchDate ?? '').trim());
    if (d == null) return null;
    return DateFormat('d MMMM y EEEE', 'tr_TR').format(d);
  }

  /// "20:00"; saat girilmemişse null.
  String? _kickoffTime(MatchModel m) {
    final t = (m.matchTime ?? '').trim();
    if (t.isEmpty || t == 'null') return null;
    return t;
  }

  /// Alt sol köşe: "6 Ekim 2026 Pazartesi · 22:00".
  String _dateTimeLine(MatchModel m) {
    final date = _fullDate(m) ?? 'Tarih Belirlenmedi';
    final time = _kickoffTime(m);
    return time == null ? date : '$date · $time';
  }

  Widget? _buildTabFab({
    required MatchModel match,
    required int tabIndex,
    bool canUndo = false,
    bool canQuickScore = false,
    bool canControl = true,
    bool scheduleOnly = false,
    String homeName = '',
    String awayName = '',
  }) {
    if (tabIndex == 1 || tabIndex == 3) return null;
    // İptal maçta işlem yok (iptali kaldırmak fikstürdeki maç menüsünde).
    if (match.status == MatchStatus.cancelled) return null;

    if (tabIndex == 0) {
      // Canlı ve bitmiş maçta menü yok: olaylar alttaki hızlı girişten, devre
      // ve Geri Al skorun altındaki butonlardan; düzeltme olaya uzun basarak.
      if (match.status == MatchStatus.live ||
          match.status == MatchStatus.halftime ||
          match.status == MatchStatus.finished) {
        return null;
      }
      // Maçın bölge sorumlusu yalnızca tarih, saat ve stadı girer.
      if (scheduleOnly) {
        return _SpeedDialFab(
          key: const ValueKey('fab_schedule'),
          actions: [
            _SpeedDialAction(
              label: 'Tarih Girişi',
              icon: Icons.edit_calendar_rounded,
              onTap: () => _openScheduleDialog(match),
            ),
          ],
        );
      }
      // Maçı başka sorumlu yönetirken giriş menüsü yok (şeritten devral).
      if (!canControl) return null;
      return _SpeedDialFab(
        key: const ValueKey('fab_detail'),
        actions: [
          if (canQuickScore &&
              match.status != MatchStatus.postponed &&
              match.status != MatchStatus.cancelled)
            _SpeedDialAction(
              label: 'Hızlı Skor Girişi',
              icon: Icons.scoreboard_outlined,
              onTap: () => showQuickScoreDialog(
                context,
                match: match,
                homeName: homeName,
                awayName: awayName,
                onSaved: _triggerRefresh,
              ),
            ),
          _SpeedDialAction(
            label: 'Maç Detayı Gir',
            icon: Icons.edit_note_rounded,
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => AdminMatchEventScreen(match: match),
            ),
          ),
          _SpeedDialAction(
            label: 'Tarih Girişi',
            icon: Icons.edit_calendar_rounded,
            onTap: () => _openScheduleDialog(match),
          ),
        ],
      );
    }

    if (tabIndex == 2) {
      return StreamBuilder<List<MatchMediaModel>>(
        stream: _fabMediaStream,
        builder: (context, snap) {
          final links = [
            for (final m in snap.data ?? const <MatchMediaModel>[])
              if (m.mediaType == 'Maç Yayın Linki') m,
          ];
          return _SpeedDialFab(
            key: const ValueKey('fab_highlights'),
            actions: [
              _SpeedDialAction(
                label: 'Medya Ekle',
                icon: Icons.perm_media_rounded,
                onTap: () => _openHighlightMediaAdder(match, _triggerRefresh),
              ),
              if (links.isEmpty && _youtubeLive)
                _SpeedDialAction(
                  label: 'YouTube\'da Yayını Bul',
                  icon: Icons.travel_explore_rounded,
                  onTap: () => showYoutubeFindSheet(
                    context: context,
                    matchId: match.id,
                    onAttached: _triggerRefresh,
                    onManual: () =>
                        _openHighlightMediaAdder(match, _triggerRefresh),
                  ),
                ),
              if (links.isNotEmpty)
                _SpeedDialAction(
                  label: 'Canlı Yayını Kaldır',
                  icon: Icons.tv_off_rounded,
                  onTap: () => _removeLiveStream(links),
                ),
            ],
          );
        },
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
        // Bitmiş / iptal maçta yönetim kilidi yok (düzeltmeler serbest).
        // Maçtan 1 saat öncesine kadar yönetim şeridi ve maç akışı görünmez;
        // gözlemci atama, erteleme gibi işlemler açık kalır.
        final bool beforeWindow = _beforeControlWindow(m);
        final bool needsControl =
            isSuperAdmin &&
            !beforeWindow &&
            m.status != MatchStatus.finished &&
            m.status != MatchStatus.cancelled;
        final bool canControl = isSuperAdmin && (!needsControl || _hasControl);
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
            // Başlamamış maçta ortada skor yerine maç saati ve tarihi.
            final showKickoff = m.status == MatchStatus.notStarted;

            return Scaffold(
              extendBodyBehindAppBar: true,
              backgroundColor: const Color(0xFF0F172A),
              appBar: AppBar(
                toolbarHeight: 44,
                // Başlamış/bitmiş maçta tarih ve saat üst çubukta ortalı.
                centerTitle: true,
                // Yayın düğmesi geri/paylaş düğmeleriyle aynı satırda.
                title: _hasStream
                    ? _LiveWatchButton(
                        live:
                            m.status == MatchStatus.live ||
                            m.status == MatchStatus.halftime,
                        open: _streamOpen,
                        onTap: () => setState(() => _streamOpen = !_streamOpen),
                      )
                    : showKickoff
                    ? null
                    : Text(
                        _dateTimeLine(m),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          shadows: _hdrShadow,
                        ),
                      ),
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                // Maç afişi (öncesi ve sonucu): admin, turnuva sahibi ve
                // maçtaki takımların sorumluları.
                actions: [
                  // Maç önü Reels videosu: şimdilik yalnız admin.
                  if (session.isAdmin && m.status == MatchStatus.notStarted)
                    IconButton(
                      tooltip: 'Maç önü videosu',
                      icon: const Icon(
                        Icons.movie_creation_outlined,
                        color: Colors.white,
                      ),
                      onPressed: () => openMatchPreviewVideo(m.id),
                    ),
                  if (canManageLeague || managesHome || managesAway)
                    IconButton(
                      tooltip: m.status == MatchStatus.finished
                          ? 'Maç sonucunu paylaş'
                          : 'Maç afişini paylaş',
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
              // Maçın bölge sorumlusu Maç sekmesinde tarih girişini, Medya
              // sekmesinde medya menüsünü görür.
              floatingActionButton:
                  !(isSuperAdmin ||
                      (_matchRegionOwner &&
                          (_tabController.index == 0 ||
                              _tabController.index == 2)))
                  ? null
                  : _buildTabFab(
                      match: m,
                      tabIndex: _tabController.index,
                      scheduleOnly: !isSuperAdmin,
                      canUndo: canManageLeague,
                      canQuickScore: canManageLeague,
                      canControl: canControl,
                      homeName: homeName,
                      awayName: awayName,
                    ),
              // Canlı maçta yöneten yetkiliye hızlı olay girişi (Detay).
              bottomNavigationBar:
                  isSuperAdmin &&
                      canControl &&
                      _tabController.index == 0 &&
                      (m.status == MatchStatus.live ||
                          m.status == MatchStatus.halftime)
                  ? QuickEventBar(
                      match: m,
                      homeName: homeName,
                      awayName: awayName,
                    )
                  : null,
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
                          // Bant her sekmede aynı boyda (Diziliş'te de
                          // küçülmez). Altta iki uç: solda tarih/saat
                          // (başlamamış maçta ortada), sağda stad + yol
                          // tarifi.
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 9),
                            child: Column(
                              children: [
                                // Yayın düğmesi üst çubukta; başlamış maçın
                                // tarihi o zaman skorun üstüne iner.
                                if (_hasStream && !showKickoff)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      _dateTimeLine(m),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.3,
                                        shadows: _hdrShadow,
                                      ),
                                    ),
                                  ),
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
                                        teamId: m.homeTeamId,
                                        seasonId: m.seasonId,
                                        firstColor: homeTeam?.firstColor,
                                        secondColor: homeTeam?.secondColor,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 118,
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: showKickoff
                                            ? _kickoffBlock(m)
                                            : Column(
                                                children: [
                                                  Text(
                                                    "${m.homeScore} - ${m.awayScore}",
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 27,
                                                      shadows: _hdrShadow,
                                                    ),
                                                  ),
                                                  if (m.hasPens)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            bottom: 3,
                                                          ),
                                                      child: Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        children: [
                                                          PenaltyBadge(
                                                            m.homePens!,
                                                          ),
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          PenaltyBadge(
                                                            m.awayPens!,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Flexible(
                                                        child: _MatchPhaseLabel(
                                                          match: m,
                                                        ),
                                                      ),
                                                      // Geç başlatılan 2. yarı:
                                                      // dakika düzeltme (admin
                                                      // ve kurucu başkan).
                                                      if (canManageLeague &&
                                                          canControl &&
                                                          m.status ==
                                                              MatchStatus
                                                                  .live &&
                                                          m.secondHalfAt !=
                                                              null &&
                                                          m.extraTimeAt ==
                                                              null &&
                                                          m.shootout == null)
                                                        _SecondHalfMinuteEdit(
                                                          match: m,
                                                          onSaved:
                                                              _triggerRefresh,
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                      ),
                                    ),
                                    Expanded(
                                      child: _TeamInfo(
                                        name: awayName,
                                        logoUrl: awayLogo,
                                        teamId: m.awayTeamId,
                                        seasonId: m.seasonId,
                                        firstColor: awayTeam?.firstColor,
                                        secondColor: awayTeam?.secondColor,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                _headerFooter(m),
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
                            // Tek satır: solda yönetim rozeti, sağda küçük
                            // devre / Geri Al butonları (akışa yer kalsın).
                            if (needsControl || (canControl && !beforeWindow))
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  8,
                                  12,
                                  0,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    if (needsControl)
                                      Flexible(
                                        fit: canControl
                                            ? FlexFit.loose
                                            : FlexFit.tight,
                                        child: MatchControlBar(
                                          key: ValueKey('ctl_${m.id}'),
                                          match: m,
                                          onChanged: (v) {
                                            if (mounted && v != _hasControl) {
                                              setState(() => _hasControl = v);
                                            }
                                          },
                                        ),
                                      ),
                                    if (canControl && !beforeWindow) ...[
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerRight,
                                          child: _MatchFlowBar(
                                            match: m,
                                            canUndo: canManageLeague,
                                            onAction: (action) =>
                                                _runPhaseAction(m, action),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            if (m.shootout != null &&
                                (isSuperAdmin || m.shootout!.isNotEmpty))
                              ShootoutBoard(
                                match: m,
                                homeName: homeName,
                                awayName: awayName,
                                canEdit:
                                    canControl && m.status == MatchStatus.live,
                                onKick: (home, scored) =>
                                    _shootoutKick(m, home, scored),
                              ),
                            _LiveStreamPanel(
                              key: ValueKey('live_${m.id}_$_refreshKey'),
                              matchId: m.id,
                              expanded: _streamOpen,
                              onClose: () =>
                                  setState(() => _streamOpen = false),
                              onAvailable: (v) {
                                if (v != _hasStream) {
                                  setState(() => _hasStream = v);
                                }
                              },
                            ),
                            // Tam genişlikte sekme satırı: başlığın altında
                            // ayrı bir şerit, seçili sekmenin altı çizili.
                            Container(
                              height: 50,
                              margin: const EdgeInsets.only(top: 6),
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
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11.5,
                                ),
                                unselectedLabelStyle: const TextStyle(
                                  fontFamily: 'Batangas',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11.5,
                                ),
                                tabs: [
                                  const _IconTab(
                                    icon: Icons.schedule_rounded,
                                    label: 'Detay',
                                  ),
                                  const _IconTab(
                                    icon: Icons.groups_rounded,
                                    label: 'Kadro',
                                  ),
                                  const _IconTab(
                                    icon: Icons.play_circle_outline_rounded,
                                    label: 'Medya',
                                  ),
                                  const _IconTab(
                                    icon: Icons.sports_soccer_rounded,
                                    label: 'Diziliş',
                                  ),
                                  if (_hasStandings)
                                    _IconTab(
                                      icon: Icons.format_list_numbered_rounded,
                                      label: 'Puan',
                                      // Maç oynanırken kırmızı nokta yanıp
                                      // söner.
                                      live:
                                          m.status == MatchStatus.live ||
                                          m.status == MatchStatus.halftime,
                                    ),
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
                                      homeColor: sides.home,
                                      awayColor: sides.away,
                                      // Takım sorumlusu dizilişi yalnız maç
                                      // başlamadan değiştirir; paylaşım
                                      // sonra da açık.
                                      canEditHome:
                                          isSuperAdmin ||
                                          managesHome && _beforeKickoff(m),
                                      canEditAway:
                                          isSuperAdmin ||
                                          managesAway && _beforeKickoff(m),
                                      canShareHome: isSuperAdmin || managesHome,
                                      canShareAway: isSuperAdmin || managesAway,
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
                                    if (_hasStandings)
                                      StandingsView(
                                        leagueId: m.leagueId,
                                        seasonId: m.seasonId,
                                        groupId: m.groupId ?? '',
                                        includeLive: true,
                                        highlightTeamIds: {
                                          m.homeTeamId,
                                          m.awayTeamId,
                                        },
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
            ? (m.isKnockout
                  ? 'Skor ${m.homeScore} - ${m.awayScore}'
                        '${m.hasPens ? ' (penaltılar ${m.homePens} - ${m.awayPens})' : ''}'
                        ' olarak kaydedilecek. Onaylıyor musunuz?'
                  : 'Skor ${m.homeScore} - ${m.awayScore} olarak kaydedilecek ve '
                        'maç puan durumuna yansıyacak. Onaylıyor musunuz?')
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

  /// Penaltı atışı ekler; [home] null ise son atışı geri alır.
  Future<void> _shootoutKick(MatchModel m, bool? home, bool scored) async {
    try {
      await _matchService.shootoutKick(
        matchId: m.id,
        home: home,
        scored: scored,
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e is PostgrestException ? e.message : '$e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  /// Tarih, saat ve stad (Fikstür'deki Maçı Düzenle penceresi).
  void _openScheduleDialog(MatchModel m) => showMatchScheduleDialog(
    context,
    match: m,
    onDataChanged: _triggerRefresh,
  );

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

  /// Seçilen görseller (galeriden çoklu seçim).
  List<XFile> _pickedFiles = const [];
  bool _isUploading = false;

  /// Yükleme sırasında "3 / 5" ilerlemesi.
  int _uploaded = 0;

  /// Takım Fotosu seçiminde gösterilen takım adları.
  String _homeName = 'Ev Sahibi';
  String _awayName = 'Deplasman';

  /// Maçtaki fotoğraf sayısı (sınır göstergesi ve kontrolü için).
  late final Stream<List<MatchMediaModel>> _mediaStream = ServiceLocator
      .matchService
      .watchMatchMedia(widget.match.id);
  int _photoCount = 0;

  /// YouTube'a yapıştırılacak yayın başlığı (takım adları yüklenince dolar).
  String _broadcastTitle = '';

  @override
  void initState() {
    super.initState();
    final m = widget.match;
    _broadcastTitle = [
      if (m.week != null) '${m.week}. Hafta',
      broadcastCode(m.id),
    ].join(' | ');
    Supabase.instance.client
        .from('teams')
        .select('id, name')
        .inFilter('id', [m.homeTeamId, m.awayTeamId])
        .then((rows) {
          final name = {for (final r in rows) r['id']: '${r['name'] ?? ''}'};
          final home = shortTeamName(name[m.homeTeamId] ?? '');
          final away = shortTeamName(name[m.awayTeamId] ?? '');
          if (!mounted || home.isEmpty || away.isEmpty) return;
          setState(() {
            _broadcastTitle = '$home - $away | $_broadcastTitle';
            _homeName = home;
            _awayName = away;
          });
        })
        .catchError((_) {});
  }

  /// Canlı yayın linki seçiliyken: turnuva kanalındaki yayının başlığına
  /// yazılırsa link kendiliğinden eklenir.
  Widget _autoLinkHint() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Otomatik eklensin',
                  style: TextStyle(
                    color: Color(0xFF6EE7B7),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Yayını turnuvanın YouTube kanalında bu başlıkla açın; '
                  'link birkaç dakika içinde kendiliğinden eklenir.',
                  style: TextStyle(color: Colors.white60, fontSize: 12.5),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  _broadcastTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Başlığı kopyala',
            icon: const Icon(Icons.copy_rounded, color: Color(0xFF6EE7B7)),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _broadcastTitle));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Yayın başlığı kopyalandı.')),
              );
            },
          ),
        ],
      ),
    );
  }

  bool get _isUrlType =>
      _selectedType == kMediaLiveLink ||
      _selectedType == kMediaAlbumLink ||
      _selectedType == kMediaVideoLink;

  final List<String> _types = [
    kMediaLiveLink,
    kMediaVideoLink,
    kMediaAlbumLink,
    'Takım Fotosu',
    'Önemli An',
    'Maçın Adamı',
    'Diğer',
  ];

  static IconData _typeIcon(String t) => switch (t) {
    kMediaLiveLink => Icons.live_tv_rounded,
    kMediaAlbumLink => Icons.photo_library_outlined,
    kMediaVideoLink => Icons.smart_display_outlined,
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

  /// "Fotoğraflar 7 / 20" göstergesi; sınır dolunca kırmızı.
  Widget _photoCounter(int count, int limit) {
    final full = count >= limit;
    final color = full ? const Color(0xFFF87171) : const Color(0xFF10B981);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.photo_outlined, size: 18, color: color),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Bu maçın fotoğrafları',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '$count / $limit',
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: limit == 0 ? 1 : (count / limit).clamp(0, 1).toDouble(),
              minHeight: 5,
              color: color,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          if (full && !_isUrlType) ...[
            const SizedBox(height: 8),
            const Text(
              'Fotoğraf sınırı doldu. Yeni fotoğraf için önce birini silin '
              'ya da tüm fotoğrafları "Fotoğraf Albümü" linkiyle paylaşın.',
              style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MatchMediaModel>>(
      stream: _mediaStream,
      builder: (context, snap) {
        _photoCount = (snap.data ?? const <MatchMediaModel>[])
            .where((m) => m.isPhoto)
            .length;
        return _buildDialog(context);
      },
    );
  }

  Widget _buildDialog(BuildContext context) {
    final isLink = _isUrlType;
    final isAlbum = _selectedType == kMediaAlbumLink;
    final isVideo = _selectedType == kMediaVideoLink;
    final limit = AppSettings.matchPhotoLimit.value;
    final full = !isLink && _photoCount >= limit;
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
                _photoCounter(_photoCount, limit),
                const SizedBox(height: 12),
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
                                  _pickedFiles = const [];
                                });
                              }
                            },
                    ),
                    if (isLink)
                      _inputRow(
                        icon: Icons.link_rounded,
                        label: isAlbum
                            ? 'Albüm Linki'
                            : isVideo
                            ? 'Video Linki'
                            : 'YouTube Linki',
                        controller: _urlCtrl,
                        hint: isAlbum
                            ? 'Drive veya Google Fotoğraflar linki'
                            : isVideo
                            ? 'YouTube, Instagram, halısaha sitesi…'
                            : 'https://youtube.com/...',
                        keyboardType: TextInputType.url,
                      )
                    else
                      AdminFieldRow(
                        icon: Icons.image_outlined,
                        label: 'Görsel',
                        onTap: _isUploading
                            ? null
                            : () async {
                                final room = limit - _photoCount;
                                if (room <= 0) return;
                                final messenger = ScaffoldMessenger.of(context);
                                // Çoklu seçim; sınırı aşanlar alınmaz.
                                final picked = await ImagePicker()
                                    .pickMultiImage(
                                      imageQuality: 85,
                                      limit: room > 1 ? room : null,
                                    );
                                if (picked.isEmpty || !mounted) return;
                                setState(
                                  () =>
                                      _pickedFiles = picked.take(room).toList(),
                                );
                                if (picked.length > room) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Sınır nedeniyle ilk $room fotoğraf '
                                        'alındı.',
                                      ),
                                    ),
                                  );
                                }
                              },
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white54,
                        ),
                        child: Text(
                          _pickedFiles.isEmpty
                              ? 'Galeriden seçin (birden çok seçilebilir)'
                              : '${_pickedFiles.length} fotoğraf seçildi',
                          style: TextStyle(
                            color: _pickedFiles.isEmpty
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
                        value: _isHomeTeam ? _homeName : _awayName,
                        placeholder: 'Seçin',
                        onTap: _isUploading
                            ? null
                            : () async {
                                final v = await showAdminOptionPicker<bool>(
                                  context: context,
                                  title: 'Takım',
                                  items: const [true, false],
                                  labelBuilder: (h) =>
                                      h ? _homeName : _awayName,
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
                if (_selectedType == kMediaLiveLink) _autoLinkHint(),
                if (isAlbum || isVideo) ...[
                  const SizedBox(height: 10),
                  Text(
                    isAlbum
                        ? 'Albüm paylaşımı "Bağlantıya sahip herkes · '
                              'Görüntüleyen" olmalı; yoksa her izleyici erişim '
                              'izni ister.'
                        : 'Gol, pozisyon ya da röportaj videosu; her klip '
                              'ayrı link. YouTube uygulamada oynar, diğerleri '
                              '(Sosyal Halısaha vb.) uygulama içi tarayıcıda '
                              'açılır. Halısaha siteleri videoları bir süre '
                              'sonra silebilir.',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12.5,
                    ),
                  ),
                ],
                if (!isLink && _pickedFiles.length == 1) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image(
                        image: pickedImageProvider(_pickedFiles.first),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
                if (!isLink && _pickedFiles.length > 1) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 84,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _pickedFiles.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 84,
                          child: Image(
                            image: pickedImageProvider(_pickedFiles[i]),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                if (_isUploading && _pickedFiles.length > 1) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Yükleniyor: $_uploaded / ${_pickedFiles.length}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
                const SizedBox(height: 22),
                AdminPrimaryButton(
                  label: 'KAYDET',
                  busy: _isUploading,
                  onPressed: full ? null : _save,
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
    final desc = _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim();
    final teamId = _selectedType == 'Takım Fotosu'
        ? (_isHomeTeam ? m.homeTeamId : m.awayTeamId)
        : null;
    MatchMediaModel media(String url) => MatchMediaModel(
      id: '',
      matchId: m.id,
      mediaType: _selectedType,
      url: url,
      description: desc,
      teamId: teamId,
      createdAt: DateTime.now(),
    );
    void snack(String text, {Color? color}) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(text), backgroundColor: color));
    }

    if (_isUrlType) {
      final finalUrl = _urlCtrl.text.trim();
      final uri = Uri.tryParse(finalUrl);
      if (finalUrl.isEmpty ||
          uri == null ||
          !(uri.scheme == 'http' || uri.scheme == 'https')) {
        snack(
          _selectedType == kMediaAlbumLink
              ? 'Lütfen geçerli bir albüm linki girin (https://...).'
              : _selectedType == kMediaVideoLink
              ? 'Lütfen geçerli bir video linki girin (https://...).'
              : 'Lütfen geçerli bir yayın linki girin.',
        );
        return;
      }
      setState(() => _isUploading = true);
      try {
        await ServiceLocator.matchService.addMatchMedia(media(finalUrl));
        if (!mounted) return;
        Navigator.pop(context);
        widget.onSuccess();
        snack('Medya başarıyla eklendi.', color: Colors.green);
      } catch (e) {
        snack(
          e is PostgrestException ? e.message : 'Kayıt Hatası: $e',
          color: Colors.red,
        );
      } finally {
        if (mounted && _isUploading) setState(() => _isUploading = false);
      }
      return;
    }

    final limit = AppSettings.matchPhotoLimit.value;
    if (_photoCount >= limit) {
      snack('Bu maç için fotoğraf sınırı ($limit) doldu.');
      return;
    }
    if (_pickedFiles.isEmpty) {
      snack('Lütfen en az bir görsel seçin.');
      return;
    }
    final files = _pickedFiles.take(limit - _photoCount).toList();
    setState(() {
      _isUploading = true;
      _uploaded = 0;
    });
    var added = 0;
    String? error;
    final uploader = SupabaseImageUploadService();
    for (final f in files) {
      String? url;
      try {
        url = await uploader.uploadImage(f, folder: MediaFolder.matches);
        if (url == null) throw Exception('Görsel yüklenemedi.');
        await ServiceLocator.matchService.addMatchMedia(media(url));
        added++;
      } catch (e) {
        // Kayıt reddedildiyse (ör. sınır aynı anda doldu) dosya kalmasın.
        if (url != null) unawaited(uploader.deleteImageByUrl(url));
        error = e is PostgrestException ? e.message : '$e';
        break;
      }
      if (mounted) setState(() => _uploaded = added);
    }
    if (!mounted) return;
    setState(() => _isUploading = false);
    if (added > 0) {
      // Ekleme sonrası Fotoğraflar sekmesi açık kalır.
      _mediaSectionByMatch[m.id] = 1;
      Navigator.pop(context);
      widget.onSuccess();
    }
    if (error != null) {
      snack(
        added > 0
            ? '$added fotoğraf eklendi; kalanlar eklenemedi: $error'
            : 'Yükleme hatası: $error',
        color: Colors.red,
      );
    } else {
      snack(
        added == 1 ? 'Fotoğraf eklendi.' : '$added fotoğraf eklendi.',
        color: Colors.green,
      );
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

/// Medya alt sekmesi maç başına hatırlanır: ekleme sonrası sekme yeniden
/// kurulunca (ör. fotoğraf eklendi) Gol Videoları'na dönmez.
final Map<String, int> _mediaSectionByMatch = {};

class _HighlightsTabViewState extends State<_HighlightsTabView> {
  /// null: tümü; aksi hâlde takım id'si.
  String? _teamFilter;

  /// Alt sekme: 0 Gol Videoları, 1 Fotoğraflar (null: içeriğe göre).
  int? get _section => _mediaSectionByMatch[widget.match.id];
  set _section(int? v) {
    if (v == null) {
      _mediaSectionByMatch.remove(widget.match.id);
    } else {
      _mediaSectionByMatch[widget.match.id] = v;
    }
  }

  Widget _sectionSwitch(int selected, int photoCount) {
    final accent = ActiveTournament.theme.value?.secondary ?? kAdminAccent;
    Widget item(int i, IconData icon, String label) {
      final on = selected == i;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _section = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: on ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: on ? onColorOf(accent) : Colors.white60,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: on ? onColorOf(accent) : Colors.white60,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            item(0, Icons.movie_outlined, 'Gol Videoları'),
            item(
              1,
              Icons.photo_outlined,
              photoCount == 0 ? 'Fotoğraflar' : 'Fotoğraflar ($photoCount)',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MatchMediaModel>>(
      stream: widget.mediaStream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Hata: ${snap.error}'));
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final all = snap.data ?? const <MatchMediaModel>[];
        final albums = [
          for (final m in all)
            if (m.mediaType == kMediaAlbumLink && m.url.trim().isNotEmpty) m,
        ];
        final videos = [
          for (final m in all)
            if (m.mediaType == kMediaVideoLink && m.url.trim().isNotEmpty) m,
        ];
        final photos = all.where((m) => m.isPhoto).toList()
          ..sort(
            (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
              a.createdAt ?? DateTime(0),
            ),
          );
        final session = AppSession.of(context).value;
        // YZ yalnız maç yayınını tarar; yayın linki yoksa kart çıkmaz.
        final hasStream = all.any(
          (m) => m.mediaType == 'Maç Yayın Linki' && m.url.trim().isNotEmpty,
        );
        // Varsayılan: yayın ya da video varsa Gol Videoları.
        final section =
            _section ??
            (hasStream || videos.isNotEmpty || photos.isEmpty ? 0 : 1);
        final switcher = _sectionSwitch(section, photos.length);
        if (section == 0) {
          return Column(
            children: [
              switcher,
              Expanded(
                child: ListView(
                  // Altta sağdaki menü düğmesi son kartı örtmesin.
                  padding: const EdgeInsets.only(bottom: 104),
                  children: [
                    if (hasStream)
                      MediaCreditChip(
                        leagueId: widget.match.leagueId,
                        kind: MediaCreditKind.broadcast,
                      ),
                    MatchHighlightsStrip(
                      match: widget.match,
                      homeName: widget.homeName,
                      awayName: widget.awayName,
                      hasStream: hasStream,
                      canReview:
                          session.canManageLeague(widget.match.leagueId) ||
                          session
                              .regionsInSeason(widget.match.seasonId)
                              .isNotEmpty,
                      trailing: [
                        for (final v in videos) _albumCard(context, v),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        final header = <Widget>[
          switcher,
          if (photos.isNotEmpty || albums.isNotEmpty)
            MediaCreditChip(
              leagueId: widget.match.leagueId,
              kind: MediaCreditKind.photo,
            ),
          for (final a in albums) _albumCard(context, a),
          if (widget.isSuperAdmin)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Icon(
                    Icons.photo_outlined,
                    size: 16,
                    color: Colors.white54,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Fotoğraflar ${photos.length} / '
                    '${AppSettings.matchPhotoLimit.value}',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ];
        if (photos.isEmpty) {
          return Column(
            children: [
              ...header,
              const Expanded(
                child: Center(
                  child: Text(
                    'Henüz fotoğraf eklenmedi.',
                    style: TextStyle(color: Colors.white60),
                  ),
                ),
              ),
            ],
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
            ...header,
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

  /// Turnuvanın kendi albümü: dokununca Drive / Google Fotoğraflar açılır.
  /// Yönetici uzun basarak kaldırabilir.
  Widget _albumCard(BuildContext context, MatchMediaModel album) {
    final desc = (album.description ?? '').trim();
    final isVideo = album.mediaType == kMediaVideoLink;
    final platform = isVideo ? videoPlatformName(album.url) : null;
    final accent = isVideo ? const Color(0xFFF472B6) : const Color(0xFFFBBF24);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Material(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            if (isVideo) {
              await openMatchVideo(context, album.url);
              return;
            }
            final uri = Uri.tryParse(album.url.trim());
            if (uri == null) return;
            try {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } catch (_) {}
          },
          onLongPress: widget.isSuperAdmin
              ? () => _confirmRemoveAlbum(context, album)
              : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isVideo
                        ? Icons.smart_display_outlined
                        : Icons.photo_library_outlined,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isVideo
                            ? (platform == null ? 'Video' : '$platform Videosu')
                            : 'Tüm Fotoğraflar',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        desc.isNotEmpty
                            ? desc
                            : isVideo
                            ? 'Maç videosu'
                            : 'Maçın fotoğraf albümü',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  isVideo ? videoWatchLabel(album.url) : 'Albümü Aç',
                  style: TextStyle(
                    color: accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Icon(
                  platform == 'YouTube'
                      ? Icons.play_arrow_rounded
                      : Icons.open_in_new_rounded,
                  size: 16,
                  color: accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemoveAlbum(
    BuildContext context,
    MatchMediaModel album,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          album.mediaType == kMediaVideoLink
              ? 'Video linki kaldırılsın mı?'
              : 'Albüm linki kaldırılsın mı?',
          style: const TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Asıl içerik silinmez, yalnızca maçtaki bağlantı kalkar.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ServiceLocator.matchService.deleteMatchMedia(album.id);
      widget.onDataChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Kaldırılamadı: $e')));
      }
    }
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
          settings: const RouteSettings(name: 'PhotoGalleryScreen'),
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
  bool _downloading = false;

  /// Fotoğrafı telefonun galerisine kaydeder (web'de indirir); tarayıcı
  /// açılmaz.
  Future<void> _download(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _downloading = true);
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final name = 'ligmasasi_${DateTime.now().millisecondsSinceEpoch}';
      if (kIsWeb) {
        await XFile.fromData(
          res.bodyBytes,
          mimeType: 'image/jpeg',
          name: '$name.jpg',
        ).saveTo('$name.jpg');
        messenger.showSnackBar(
          const SnackBar(content: Text('Fotoğraf indirildi.')),
        );
      } else {
        if (!await Gal.hasAccess(toAlbum: false)) {
          await Gal.requestAccess(toAlbum: false);
        }
        await Gal.putImageBytes(res.bodyBytes, name: name);
        messenger.showSnackBar(
          const SnackBar(content: Text('Fotoğraf galeriye kaydedildi.')),
        );
      }
    } on GalException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.type == GalExceptionType.accessDenied
                ? 'Galeriye kaydetmek için fotoğraf izni gerekli.'
                : 'Kaydedilemedi: ${e.type.message}',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Fotoğraf indirilemedi.')),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

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
            tooltip: 'İndir',
            icon: _downloading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download_rounded),
            onPressed: _downloading ? null : () => _download(current.url),
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
    // Telefon uygulamasında oynatıcı, açılır panel/kaydırma alanı içinde
    // (WebView) donuk kalıyordu: tam ekran ayrı sayfada açılır.
    if (!kIsWeb) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'NativeYoutubeScreen'),
          fullscreenDialog: true,
          builder: (_) => _NativeYoutubeScreen(videoId: id, url: widget.url),
        ),
      );
      return;
    }
    setState(() {
      _controller = YoutubePlayerController.fromVideoId(
        videoId: id,
        autoPlay: true,
        params: const YoutubePlayerParams(
          // Android'de YouTube'un kendi tam ekranı WebView'da boş ekran
          // bırakıyor; telefonda tam ekran YoutubePlayerFrame düğmesiyle.
          showFullscreenButton: kIsWeb,
          strictRelatedVideos: true,
          origin: youtubePlayerOrigin,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final id = youtubeVideoId(widget.url);
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

/// Telefon uygulamasında YouTube oynatıcısı: siyah zeminli ayrı sayfa.
/// YouTube gömülü oynatıcı için geçerli bir https kaynağı (origin) ister;
/// verilmezse "oynatıcı yapılandırma hatası" verip boş kalabiliyor.
class _NativeYoutubeScreen extends StatefulWidget {
  const _NativeYoutubeScreen({required this.videoId, required this.url});

  final String videoId;
  final String url;

  @override
  State<_NativeYoutubeScreen> createState() => _NativeYoutubeScreenState();
}

class _NativeYoutubeScreenState extends State<_NativeYoutubeScreen> {
  late final YoutubePlayerController _controller =
      YoutubePlayerController.fromVideoId(
        videoId: widget.videoId,
        autoPlay: true,
        params: const YoutubePlayerParams(
          // Android'de YouTube'un kendi tam ekranı WebView'da boş ekran
          // bırakıyor; telefonda tam ekran YoutubePlayerFrame düğmesiyle.
          showFullscreenButton: kIsWeb,
          strictRelatedVideos: true,
          origin: youtubePlayerOrigin,
        ),
      );

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Tam ekran düğmesi ya da yatay tutuş: oynatıcı ekranı doldurur.
    return YoutubePlayerFrame(controller: _controller, title: 'Maç Yayını');
  }
}

/// Skorun üstündeki "Canlı Yayın / CANLI İZLE" butonuyla açılan yayın
/// oynatıcısı (sekmelerin üstünde). Kapalıyken yer kaplamaz; yayın linki
/// olup olmadığını [onAvailable] ile bildirir (buton ona göre görünür).
class _LiveStreamPanel extends StatefulWidget {
  final String matchId;
  final bool expanded;
  final VoidCallback onClose;
  final ValueChanged<bool> onAvailable;
  const _LiveStreamPanel({
    super.key,
    required this.matchId,
    required this.expanded,
    required this.onClose,
    required this.onAvailable,
  });

  @override
  State<_LiveStreamPanel> createState() => _LiveStreamPanelState();
}

class _LiveStreamPanelState extends State<_LiveStreamPanel> {
  late final Stream<List<MatchMediaModel>> _mediaStream = ServiceLocator
      .matchService
      .watchMatchMedia(widget.matchId);
  bool? _reported;

  void _report(bool available) {
    if (_reported == available) return;
    _reported = available;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onAvailable(available);
    });
  }

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
        if (snap.hasData) _report(stream != null);
        if (stream == null || !widget.expanded) return const SizedBox.shrink();

        final desc = (stream.description ?? '').trim();
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 2, 2),
                child: Row(
                  children: [
                    const Icon(
                      Icons.live_tv_rounded,
                      color: Colors.redAccent,
                      size: 18,
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
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Büyüt',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => openYoutubeInApp(
                        context,
                        stream.url,
                        fullscreen: true,
                      ),
                      icon: const Icon(
                        Icons.fullscreen_rounded,
                        color: Colors.white70,
                        size: 22,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onClose,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
              _YoutubeVideoView(key: ValueKey(stream.id), url: stream.url),
            ],
          ),
        );
      },
    );
  }
}

/// Skor tabelasının üstünde yayın butonu: maç başlamadan "Canlı Yayın",
/// maç oynanırken yanıp sönen kırmızı noktalı "CANLI İZLE".
class _LiveWatchButton extends StatefulWidget {
  const _LiveWatchButton({
    required this.live,
    required this.open,
    required this.onTap,
  });

  final bool live;
  final bool open;
  final VoidCallback onTap;

  @override
  State<_LiveWatchButton> createState() => _LiveWatchButtonState();
}

class _LiveWatchButtonState extends State<_LiveWatchButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.live) _blink.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _LiveWatchButton old) {
    super.didUpdateWidget(old);
    if (widget.live && !_blink.isAnimating) {
      _blink.repeat(reverse: true);
    } else if (!widget.live && _blink.isAnimating) {
      _blink.stop();
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.live;
    final color = live ? const Color(0xFFEF4444) : Colors.white;
    return Material(
      color: color.withValues(alpha: live ? 0.18 : 0.10),
      shape: StadiumBorder(
        side: BorderSide(color: color.withValues(alpha: live ? 0.7 : 0.35)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (live)
                FadeTransition(
                  opacity: Tween(begin: 1.0, end: 0.25).animate(_blink),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                  ),
                )
              else
                const Icon(
                  Icons.live_tv_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              const SizedBox(width: 6),
              Text(
                widget.open
                    ? 'Yayını Kapat'
                    : live
                    ? 'CANLI İZLE'
                    : 'Canlı Yayın',
                style: TextStyle(
                  color: live ? const Color(0xFFFECACA) : Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                  letterSpacing: live ? 0.6 : 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
                        'saatinde kendi takım sekmelerinde sağ alttaki menüden "Esame Girişi" ile girebilir. '
                        'Bu saatten önce menüde açılış saati görünür.'
                  : 'Takım sorumluları, kendi takımlarının esamesini maç '
                        'saatinden $hours saat önce kendi takım sekmelerinde sağ '
                        'alttaki menüden "Esame Girişi" ile girebilir. Bu '
                        'saatten önce menüde açılış saati görünür.',
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

/// Takım sorumlusu esameyi yalnız maç başlamadan girer (ertelenen maç da
/// başlamamış sayılır); admin ve turnuva/bölge sorumlusu için sınır yok.
bool _beforeKickoff(MatchModel m) =>
    m.status == MatchStatus.notStarted || m.status == MatchStatus.postponed;

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

  /// Sezonun ilk oyuncu sayısı (11, halı sahada 7-8); paylaşım için gerekli.
  int _startingCount = 11;

  /// Maçın bölgesinin sorumlusu mu (bölge sorumlusu esameyi maç başladıktan
  /// sonra da düzenler; admin, kurucu başkan ve gözlemci gibi).
  bool _regionOwner = false;
  bool _regionChecked = false;

  bool get _isStaff => widget.isSuperAdmin || _regionOwner;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_regionChecked) return;
    _regionChecked = true;
    // Takım sorumlusu kadro sekmesini kendi takımında açar.
    final m0 = widget.match;
    if (!widget.isSuperAdmin) {
      if (_managesTeam(m0.homeTeamId)) {
        _view = m0.homeTeamId;
      } else if (_managesTeam(m0.awayTeamId)) {
        _view = m0.awayTeamId;
      }
    }
    final session = AppSession.of(context).value;
    final m = widget.match;
    final groupId = (m.groupId ?? '').trim();
    if (widget.isSuperAdmin ||
        groupId.isEmpty ||
        session.regionsInSeason(m.seasonId).isEmpty) {
      return;
    }
    Supabase.instance.client
        .from('groups')
        .select('region_id')
        .eq('id', groupId)
        .maybeSingle()
        .then((row) {
          final regionId = row?['region_id']?.toString();
          if (mounted && session.canManageRegion(m.leagueId, regionId)) {
            setState(() => _regionOwner = true);
          }
        })
        .catchError((_) {});
  }

  /// Takım başına esame akışı (aynı maç akışından süzülür).
  final Map<String, Stream<List<MatchRosterModel>>> _rosterStreams = {};

  @override
  void initState() {
    super.initState();
    _loadOpenHours();
  }

  Future<void> _loadOpenHours() async {
    Supabase.instance.client
        .from('seasons')
        .select('starting_player_count')
        .eq('id', widget.match.seasonId)
        .maybeSingle()
        .then((row) {
          final n = (row?['starting_player_count'] as num?)?.toInt();
          if (n != null && n > 0 && n != _startingCount && mounted) {
            setState(() => _startingCount = n);
          }
        })
        .catchError((_) {});
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
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        // Esame bilgisi: düzenleme yetkisi olanlara (yetkililer ve maçın
        // takım sorumluları) gösterilir.
        // Maç başladıktan sonra esame girilmediği için uyarı da çıkmaz;
        // esame açıldıktan sonra da gösterilmez.
        if (_beforeKickoff(m) &&
            (_rosterOpenAt(m, _openHours)?.isAfter(DateTime.now().toUtc()) ??
                false) &&
            (widget.isSuperAdmin ||
                _managesTeam(m.homeTeamId) ||
                _managesTeam(m.awayTeamId))) ...[
          _RosterInfoNote(hours: _openHours),
          const SizedBox(height: 10),
        ],
        // Katılım Durum Sorgulama: yalnızca takımın sorumlusu ve kadrosu
        // görür (yetkisizde kart çizilmez).
        if (AppSession.of(context).value.user != null) ...[
          AttendanceCard(
            match: m,
            teamId: m.homeTeamId,
            teamName: widget.homeName,
            rivalName: widget.awayName,
          ),
          AttendanceCard(
            match: m,
            teamId: m.awayTeamId,
            teamName: widget.awayName,
            rivalName: widget.homeName,
          ),
        ],
        _viewSwitch(m),
        const SizedBox(height: 10),
        if (_view == null) ...[
          // VS: iki ilk 11 yan yana, altında iki takımın yedekleri yan yana;
          // takım adına dokununca o takım açılır.
          _vsRow(m, head: false, only: 'xi'),
          const SizedBox(height: 12),
          _vsRow(m, head: false, only: 'bench'),
        ] else
          // Tek takım: kadro ve yedekler yan yana.
          _TeamLineupColumn(
            key: ValueKey(_view),
            match: m,
            teamId: _view!,
            color: _view == m.homeTeamId ? _green : _blue,
            sideBySide: true,
          ),
      ],
    );
    return Stack(
      children: [
        list,
        Positioned(right: 16, bottom: 16, child: _lineupFab(m)),
      ],
    );
  }

  Widget _vsRow(MatchModel m, {required bool head, required String only}) {
    Widget col(String name, Color color, String teamId) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (head) _columnHead(name, color, teamId),
          _TeamLineupColumn(match: m, teamId: teamId, color: color, only: only),
        ],
      ),
    );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          col(widget.homeName, _green, m.homeTeamId),
          Container(
            width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            color: Colors.white.withValues(alpha: 0.08),
          ),
          col(widget.awayName, _blue, m.awayTeamId),
        ],
      ),
    );
  }

  /// Sağ alt köşe. Takım sekmesinde menü: esame girişi/düzenleme ve kadro
  /// afişi. VS'de yetkililere (admin, kurucu başkan, bölge sorumlusu) iki
  /// takımın esamesi ve paylaş menüsü; diğerlerine yalnız paylaş (iki
  /// takımın da ilk oyuncuları tamamsa).
  Widget _lineupFab(MatchModel m) {
    final session = AppSession.of(context).value;
    final view = _view;
    if (view == null && (session.canManageLeague(m.leagueId) || _regionOwner)) {
      return _vsStaffFab(m);
    }
    if (view == null) {
      final canShare =
          session.canManageLeague(m.leagueId) ||
          _managesTeam(m.homeTeamId) ||
          _managesTeam(m.awayTeamId);
      if (!canShare) return const SizedBox.shrink();
      return StreamBuilder<List<MatchRosterModel>>(
        stream: _rosterStream(m.homeTeamId),
        builder: (context, home) => StreamBuilder<List<MatchRosterModel>>(
          stream: _rosterStream(m.awayTeamId),
          builder: (context, away) {
            int xi(AsyncSnapshot<List<MatchRosterModel>> s) =>
                (s.data ?? const []).where((r) => r.isStarting).length;
            if (xi(home) < _startingCount || xi(away) < _startingCount) {
              return const SizedBox.shrink();
            }
            return FloatingActionButton(
              heroTag: 'vs_share_${m.id}',
              backgroundColor: kAdminAccent,
              foregroundColor: const Color(0xFF04130D),
              tooltip: 'Kadro afişini paylaş',
              onPressed: _shareFromVs,
              child: const Icon(Icons.ios_share_rounded),
            );
          },
        ),
      );
    }

    // Esame: maç başlamadan eskisi gibi (yetkililer her zaman, takım
    // sorumlusu açılış saatinden itibaren); başladıktan sonra yalnız admin
    // ve kurucu başkan.
    final managesThis = !_isStaff && _managesTeam(view);
    final openAt = _rosterOpenAt(m, _openHours);
    if (managesThis) _scheduleOpen(openAt);
    final started = !_beforeKickoff(m);
    final managerOpen =
        managesThis &&
        !started &&
        openAt != null &&
        !DateTime.now().toUtc().isBefore(openAt);
    final locked = managesThis && !started && !managerOpen;
    final canEsame = started
        ? session.canManageLeague(m.leagueId)
        : (_isStaff || managerOpen);
    final canShare = session.canManageLeague(m.leagueId) || _managesTeam(view);
    final actions = <_SpeedDialAction>[
      if (canEsame)
        _SpeedDialAction(
          label: started ? 'Esameyi Düzenle' : 'Esame Girişi',
          icon: Icons.edit_note_rounded,
          onTap: () => _showRosterEditSheet(context, view),
        )
      else if (locked)
        _SpeedDialAction(
          label: openAt == null
              ? 'Esame kapalı'
              : "Esame ${DateFormat('HH:mm').format(openAt.add(const Duration(hours: 3)))}'de açılır",
          icon: Icons.lock_clock_rounded,
          onTap: () {},
        ),
      if (canShare)
        _SpeedDialAction(
          label: 'Kadro Afişini Paylaş',
          icon: Icons.ios_share_rounded,
          onTap: () => _shareLineup(view),
        ),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();
    return _SpeedDialFab(key: ValueKey('lineup_fab_$view'), actions: actions);
  }

  /// VS'de yetkililerin menüsü: takımlar esameyi giremediyse iki takımın
  /// esamesi buradan girilir (maç başladıktan sonra yalnız admin ve kurucu
  /// başkan, takım sekmesindeki kuralla aynı).
  Widget _vsStaffFab(MatchModel m) {
    final session = AppSession.of(context).value;
    final started = !_beforeKickoff(m);
    final canEsame = started ? session.canManageLeague(m.leagueId) : true;
    return StreamBuilder<List<MatchRosterModel>>(
      stream: _rosterStream(m.homeTeamId),
      builder: (context, home) => StreamBuilder<List<MatchRosterModel>>(
        stream: _rosterStream(m.awayTeamId),
        builder: (context, away) {
          int xi(AsyncSnapshot<List<MatchRosterModel>> s) =>
              (s.data ?? const []).where((r) => r.isStarting).length;
          bool has(AsyncSnapshot<List<MatchRosterModel>> s) =>
              (s.data ?? const []).isNotEmpty;
          String label(String name, bool exists) =>
              '$name · ${exists ? 'Esameyi Düzenle' : 'Esame Girişi'}';
          final actions = <_SpeedDialAction>[
            if (canEsame) ...[
              _SpeedDialAction(
                label: label(widget.homeName, has(home)),
                icon: Icons.edit_note_rounded,
                onTap: () => _showRosterEditSheet(context, m.homeTeamId),
              ),
              _SpeedDialAction(
                label: label(widget.awayName, has(away)),
                icon: Icons.edit_note_rounded,
                onTap: () => _showRosterEditSheet(context, m.awayTeamId),
              ),
            ],
            if (xi(home) >= _startingCount && xi(away) >= _startingCount)
              _SpeedDialAction(
                label: 'Kadro Afişini Paylaş',
                icon: Icons.ios_share_rounded,
                onTap: _shareFromVs,
              ),
          ];
          if (actions.isEmpty) return const SizedBox.shrink();
          return _SpeedDialFab(
            key: ValueKey('lineup_fab_vs_${m.id}'),
            actions: actions,
          );
        },
      ),
    );
  }

  Stream<List<MatchRosterModel>> _rosterStream(String teamId) =>
      _rosterStreams.putIfAbsent(
        teamId,
        () => ServiceLocator.matchService
            .watchMatchRosters(widget.match.id, teamId)
            .asBroadcastStream(),
      );

  /// VS'den paylaşım: hangi takımın kadro afişi.
  Future<void> _shareFromVs() async {
    final m = widget.match;
    final teamId = await showAdminOptionPicker<String>(
      context: context,
      title: 'Kadro afişi',
      items: [m.homeTeamId, m.awayTeamId],
      labelBuilder: (id) =>
          id == m.homeTeamId ? widget.homeName : widget.awayName,
      emptyText: '',
    );
    if (teamId == null || !mounted) return;
    await _shareLineup(teamId);
  }

  /// Seçili görünüm: null iki takım yan yana (VS), değilse o takımın id'si.
  String? _view;

  /// Üstte Ev sahibi · VS · Deplasman sekmeleri (Diziliş'teki gibi).
  Widget _viewSwitch(MatchModel m) {
    Widget tab(String? id, Widget child, Color color) {
      final on = _view == id;
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _view = id),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: on ? const Color(0xFF1E293B) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: on ? Border.all(color: color, width: 1.5) : null,
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(
              color: on ? Colors.white : Colors.white60,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
            child: child,
          ),
        ),
      );
    }

    Widget team(String name, Color color) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            shortTeamName(name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: tab(m.homeTeamId, team(widget.homeName, _green), _green),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 56,
            child: tab(
              null,
              const Text('VS', style: TextStyle(letterSpacing: 0.5)),
              Colors.white54,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: tab(m.awayTeamId, team(widget.awayName, _blue), _blue),
          ),
        ],
      ),
    );
  }

  /// VS görünümünde sütun başlığı: takım adı; dokununca o takım açılır.
  Widget _columnHead(String name, Color color, String teamId) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _view = teamId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                shortTeamName(name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: color),
          ],
        ),
      ),
    );
  }

  Future<void> _shareLineup(String teamId) => shareLineupPoster(
    context,
    match: widget.match,
    homeName: widget.homeName,
    awayName: widget.awayName,
    teamId: teamId,
  );

  Future<void> _showRosterEditSheet(BuildContext context, String teamId) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EsameEditScreen(
          match: widget.match,
          teamId: teamId,
          teamName: teamId == widget.match.homeTeamId
              ? widget.homeName
              : widget.awayName,
          isHome: teamId == widget.match.homeTeamId,
        ),
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(this.context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Esame kaydedildi.'),
            duration: Duration(seconds: 2),
          ),
        );
    }
  }
}

/// Tek takımın esamesi: İlk 11 ve Yedekler, önce mevki sonra forma
/// numarasına göre sıralı; sıkı satırlarla tüm ilk 11 tek ekrana sığar.
class _TeamLineupColumn extends StatefulWidget {
  const _TeamLineupColumn({
    super.key,
    required this.match,
    required this.teamId,
    required this.color,
    this.sideBySide = false,
    this.only,
  });

  final MatchModel match;
  final String teamId;
  final Color color;

  /// Tek takım görünümü: kadro solda, yedekler sağda.
  final bool sideBySide;

  /// VS görünümü: yalnız 'xi' (ilk oyuncular) ya da 'bench' (yedekler).
  final String? only;

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
              // Esame yoksa uyarı bir kez (ilk 11 bölümünde) görünür.
              if (widget.only == 'bench') return const SizedBox.shrink();
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
            // Esame sırası kayıtlıysa İlk 11 ve yedekler esamedeki sırayla
            // (forma numarasına göre değil); eski kayıtlarda diziliş/mevki.
            final hasOrder =
                rosters.isNotEmpty && rosters.every((r) => r.listOrder != null);
            int byList(MatchRosterModel a, MatchRosterModel b) =>
                a.listOrder!.compareTo(b.listOrder!);
            final starters = hasOrder
                ? (starterRosters..sort(byList))
                : [
                    for (final id in formationIds)
                      if (starterById[id] != null) starterById[id]!,
                  ];
            final gkId = formationIds.isEmpty ? null : formationIds.first;
            final subs = rosters.where((r) => !r.isStarting).toList()
              ..sort(hasOrder ? byList : order);

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

            if (widget.only == 'xi') {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows(starters, xi: true),
              );
            }
            if (widget.only == 'bench') {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _section('Yedekler'),
                  if (subs.isEmpty)
                    const Text(
                      '-',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38),
                    ),
                  ...rows(subs),
                ],
              );
            }
            if (widget.sideBySide) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _section('Kadro'),
                          ...rows(starters, xi: true),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _section('Yedekler'),
                          if (subs.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'Yedek yok.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ...rows(subs),
                        ],
                      ),
                    ),
                  ],
                ),
              );
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
          fontWeight: FontWeight.w800,
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
                fontWeight: FontWeight.w800,
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
  late final Future<SeasonMatchSettings> _settingsFuture =
      SeasonMatchSettings.of(widget.match.seasonId);

  /// Onaylı YZ gol kesitleri, maç olayına göre (gol satırında video ikonu).
  late Map<String, MatchHighlight> _clips = _clipsByEvent(
    MatchHighlightService.cached(widget.match.id),
  );

  /// Maçın bölgesinin sorumlusu mu (olaya uzun basınca düzenle/sil).
  bool _regionOwner = false;

  @override
  void initState() {
    super.initState();
    MatchHighlightService.changes.addListener(_onClipsChanged);
    if (widget.match.status == MatchStatus.finished) {
      MatchHighlightService.fetch(
        widget.match.id,
      ).then((_) => _onClipsChanged()).catchError((_) {});
    }
  }

  @override
  void dispose() {
    MatchHighlightService.changes.removeListener(_onClipsChanged);
    super.dispose();
  }

  bool _regionChecked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_regionChecked) return;
    _regionChecked = true;
    final session = AppSession.of(context).value;
    final m = widget.match;
    final groupId = (m.groupId ?? '').trim();
    if (groupId.isEmpty || session.regionsInSeason(m.seasonId).isEmpty) {
      return;
    }
    Supabase.instance.client
        .from('groups')
        .select('region_id')
        .eq('id', groupId)
        .maybeSingle()
        .then((row) {
          final regionId = row?['region_id']?.toString();
          if (mounted && session.ownedRegions.any((r) => r.id == regionId)) {
            setState(() => _regionOwner = true);
          }
        })
        .catchError((_) {});
  }

  static Map<String, MatchHighlight> _clipsByEvent(List<MatchHighlight>? l) => {
    for (final h in l ?? const <MatchHighlight>[])
      if (h.isApproved && h.matchEventId != null) h.matchEventId!: h,
  };

  void _onClipsChanged() {
    if (!mounted) return;
    setState(
      () =>
          _clips = _clipsByEvent(MatchHighlightService.cached(widget.match.id)),
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _DetailTabView(
      match: widget.match,
      eventsStream: _eventsStream,
      settingsFuture: _settingsFuture,
      clips: _clips,
      regionOwner: _regionOwner,
    );
  }
}

class _DetailTabView extends StatelessWidget {
  final MatchModel match;
  final Stream<List<Map<String, dynamic>>> eventsStream;
  final Future<SeasonMatchSettings> settingsFuture;
  final Map<String, MatchHighlight> clips;
  final bool regionOwner;
  const _DetailTabView({
    required this.match,
    required this.eventsStream,
    required this.settingsFuture,
    this.clips = const {},
    this.regionOwner = false,
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

  List<Map<String, dynamic>> _fallbackSystemStory(int period) {
    switch (match.status) {
      case MatchStatus.notStarted:
        return <Map<String, dynamic>>[
          {'minute': 0, 'type': 'status', 'title': 'Maç Henüz Başlamadı'},
        ];
      case MatchStatus.postponed:
        return <Map<String, dynamic>>[
          {
            'minute': 0,
            'type': 'status',
            'title': match.isRescheduled
                ? 'Ertelenen Maç · Henüz Başlamadı'
                : 'Maç Ertelendi',
          },
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
          // Uzatma golleri ve maçın adamından sonra, akışın en sonunda.
          {
            'minute': 100000,
            'type': 'status',
            'title': 'Maç Sonucu  ${match.homeScore} - ${match.awayScore}',
          },
        ];
    }
  }

  // Hava durumu yalnız maç öncesi başlıkta (tek satır); akışa yer kalsın.
  @override
  Widget build(BuildContext context) => _events(context);

  Widget _events(BuildContext context) {
    return FutureBuilder<SeasonMatchSettings>(
      future: settingsFuture,
      initialData: SeasonMatchSettings.cached(match.seasonId),
      builder: (context, settingsSnap) {
        final settings = settingsSnap.data;
        if (settings == null) {
          return const Center(child: CircularProgressIndicator());
        }
        // Dakika tutulmayan sezonda (halısaha) zaman çizelgesi yerine
        // takımların altında golcüler listelenir.
        if (!settings.tracksGoalMinutes) {
          return _MinutelessSummary(
            match: match,
            eventsStream: eventsStream,
            clips: clips,
          );
        }
        return _buildFlow(context, settings.periodMinutes);
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
          // Aynı dakikada uzatma (30+2') sonra gelir.
          final aa = readAddedMinute(a) ?? 0;
          final ba = readAddedMinute(b) ?? 0;
          if (aa != ba) return aa.compareTo(ba);
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
          // Altta sağdaki menü düğmesi son satırları örtmesin.
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 104),
          itemCount: normalized.length,
          separatorBuilder: (_, _) =>
              const SizedBox(height: 2, child: Center(child: _TimelineLine())),
          itemBuilder: (context, i) {
            final e = normalized[i];
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
            final isPenalty =
                (e['isPenalty'] as bool?) ??
                (e['is_penalty'] as bool?) ??
                false;

            String displayTitle() {
              if (type == 'substitution') {
                return title.isEmpty ? 'Değişiklik' : title;
              }
              if (type == 'goal' || type == 'goal_cancelled') {
                // Penaltı ikonda (P rozeti) belli; adın yanına yazılmaz.
                // Kendi kalesine: adın altında soluk alt satırda yazılır.
                return title.isEmpty ? 'Gol' : title;
              }
              return title;
            }

            // Kendi kalesine gol, golün yazıldığı (rakip) takım tarafında.
            final anyGoal = type == 'goal' || type == 'goal_cancelled';
            final sideTeamId = anyGoal && isOwnGoal
                ? (teamId == match.homeTeamId
                      ? match.awayTeamId
                      : match.homeTeamId)
                : teamId;
            final eventId = system ? '' : _readString(e['id']);
            String? idOf(String snake, String camel) {
              final s = _readString(e[snake]).isNotEmpty
                  ? _readString(e[snake])
                  : _readString(e[camel]);
              return s.isEmpty ? null : s;
            }

            return _DetailEventTile(
              eventId: eventId,
              // Uzun basınca açılan düzenleme formu için olayın ham hali.
              event: eventId.isEmpty
                  ? null
                  : MatchEvent(
                      id: eventId,
                      matchId: match.id,
                      teamId: teamId,
                      eventType: pickType(e),
                      minute: minute,
                      addedMinute: readAddedMinute(e),
                      eventName: title,
                      playerId: idOf('player_id', 'playerId'),
                      assistPlayerId: idOf(
                        'assist_player_id',
                        'assistPlayerId',
                      ),
                      subInPlayerId: idOf('sub_in_player_id', 'subInPlayerId'),
                      isOwnGoal: isOwnGoal,
                      isPenalty: isPenalty,
                    ),
              clip: type == 'goal' ? clips[eventId] : null,
              regionOwner: regionOwner,
              isPenalty: type == 'goal' && isPenalty,
              isOwnGoal: type == 'goal' && isOwnGoal,
              match: match,
              minute: minute,
              addedMinute: system ? null : readAddedMinute(e),
              fullTime: period * 2,
              type: type,
              title: displayTitle(),
              // Asist, gol atanın altında daha küçük ve soluk gösterilir.
              subtitle: type == 'goal_cancelled'
                  ? 'VAR · Gol iptal'
                  : type == 'red_card_cancelled'
                  ? 'VAR · Kart iptal'
                  : type == 'goal' && isOwnGoal
                  ? 'Kendi Kalesine'
                  : type == 'goal' && assist.isNotEmpty
                  ? 'Asist: $assist'
                  : type == 'second_yellow'
                  ? 'Çift sarıdan ihraç'
                  : type == 'penalty_missed'
                  ? 'Penaltı kaçtı'
                  : null,
              subInName: type == 'substitution' ? subIn : '',
              teamId: sideTeamId,
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

/// Dakika tutulmayan sezonun (halısaha) maç detayı: zaman çizelgesi yok;
/// golcüler ve kartlar her takımın altında listelenir.
class _MinutelessSummary extends StatelessWidget {
  const _MinutelessSummary({
    required this.match,
    required this.eventsStream,
    this.clips = const {},
  });

  final MatchModel match;
  final Stream<List<Map<String, dynamic>>> eventsStream;

  /// Onaylı YZ gol kesitleri (olay id'sine göre); golcü satırında oynatılır.
  final Map<String, MatchHighlight> clips;

  static const _muted = Color(0xFF94A3B8);

  static String _str(dynamic v) => (v ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: eventsStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text('Maç olayları yüklenemedi.\n${snap.error}'),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final events = [
          for (final e in snap.data!) Map<String, dynamic>.from(e),
        ];
        // Girildiği sırayla (dakika yok); aynı oyuncunun golleri tek satırda.
        events.sort(
          (a, b) => _str(a['created_at']).compareTo(_str(b['created_at'])),
        );

        final goals = {
          match.homeTeamId: <String, _SummaryRow>{},
          match.awayTeamId: <String, _SummaryRow>{},
        };
        final cards = {
          match.homeTeamId: <String, _SummaryRow>{},
          match.awayTeamId: <String, _SummaryRow>{},
        };
        String? motm;
        String motmId = '';
        for (final e in events) {
          final type = _str(e['event_type']).isNotEmpty
              ? _str(e['event_type'])
              : _str(e['type']);
          final teamId = _str(e['team_id']);
          final playerId = _str(e['player_id']);
          final name = _str(e['player_name']).isNotEmpty
              ? _str(e['player_name'])
              : _str(e['event_name']);
          final ownGoal = e['is_own_goal'] == true;
          if (type == 'goal') {
            // Kendi kalesine gol, golün yazıldığı (rakip) takımın altında.
            final side = ownGoal
                ? (teamId == match.homeTeamId
                      ? match.awayTeamId
                      : match.homeTeamId)
                : teamId;
            final row = goals[side]?.putIfAbsent(
              '${ownGoal ? 'og' : ''}|${playerId.isEmpty ? name : playerId}',
              () => _SummaryRow(name, playerId, ownGoal: ownGoal),
            );
            row?.count++;
            if (e['is_penalty'] == true) row?.penalties++;
            final clip = clips[_str(e['id'])];
            if (clip != null) row?.clips.add(clip);
          } else if (type == 'yellow_card' || type == 'red_card') {
            final row = cards[teamId]?.putIfAbsent(
              playerId.isEmpty ? name : playerId,
              () => _SummaryRow(name, playerId),
            );
            if (type == 'red_card') {
              row?.reds++;
            } else {
              row?.yellows++;
            }
          } else if (type == 'man_of_the_match') {
            motm = name;
            motmId = playerId;
          }
        }

        final hasCards = cards.values.any((m) => m.isNotEmpty);
        return ListView(
          // Altta sağdaki menü düğmesi son satırları örtmesin.
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
          children: [
            _section(
              context,
              goals[match.homeTeamId]!.values.toList(),
              goals[match.awayTeamId]!.values.toList(),
              emptyHome: match.homeScore > 0 ? '' : 'Gol yok',
              emptyAway: match.awayScore > 0 ? '' : 'Gol yok',
              goal: true,
            ),
            if (hasCards)
              _section(
                context,
                cards[match.homeTeamId]!.values.toList(),
                cards[match.awayTeamId]!.values.toList(),
              ),
            if (motm != null)
              _card(
                child: InkWell(
                  onTap: motmId.isEmpty
                      ? null
                      : () => showPlayerCard(context, playerKey: motmId),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: Color(0xFFFBBF24),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Maçın Adamı',
                        style: TextStyle(color: _muted, fontSize: 12.5),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          motm,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _card({required Widget child}) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: const Color(0xFF1E293B).withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
    ),
    child: child,
  );

  Widget _section(
    BuildContext context,
    List<_SummaryRow> home,
    List<_SummaryRow> away, {
    String emptyHome = '',
    String emptyAway = '',
    bool goal = false,
  }) {
    Widget column(List<_SummaryRow> rows, bool end, String empty) {
      if (rows.isEmpty) {
        return Text(
          empty,
          textAlign: end ? TextAlign.right : TextAlign.left,
          style: const TextStyle(color: _muted, fontSize: 12.5),
        );
      }
      return Column(
        crossAxisAlignment: end
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          for (final r in rows)
            InkWell(
              onTap: r.playerId.isEmpty
                  ? null
                  : () => showPlayerCard(context, playerKey: r.playerId),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _rowContent(r, end, goal),
              ),
            ),
        ],
      );
    }

    // Başlık yok; takımlar zaman çizgisindeki gibi ortadaki ince çizgiyle
    // ayrılır.
    return _card(
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: column(home, false, emptyHome)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: _TimelineLine(),
            ),
            Expanded(child: column(away, true, emptyAway)),
          ],
        ),
      ),
    );
  }

  /// Gol: 1-2 golde top ikonu tekrarlanır, 3 ve üstünde "⚽ ×3".
  /// Kart: sarı/kırmızı kart ikonları.
  Widget _rowContent(_SummaryRow r, bool end, bool goal) {
    final icons = <Widget>[];
    if (goal) {
      Widget ball() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 1),
        child: BallIcon(size: 14),
      );
      if (r.count <= 2) {
        for (var i = 0; i < r.count; i++) {
          icons.add(ball());
        }
      } else {
        icons
          ..add(ball())
          ..add(
            Text(
              '×${r.count}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          );
      }
    } else {
      Widget card(Color c) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1.5),
        child: RefereeCardIcon(color: c, height: 14),
      );
      for (var i = 0; i < r.yellows; i++) {
        icons.add(card(const Color(0xFFFACC15)));
      }
      for (var i = 0; i < r.reds; i++) {
        icons.add(card(const Color(0xFFEF4444)));
      }
    }
    // Birden fazla gol: penaltıdan bağımsız yalnız sayı, ör. "Ali (2)".
    final suffix = !goal
        ? ''
        : r.ownGoal
        ? ' (K.K.)'
        : '';
    final nameText = Text(
      '${r.name.isEmpty ? '-' : r.name}$suffix',
      overflow: TextOverflow.ellipsis,
      textAlign: end ? TextAlign.right : TextAlign.left,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
    );
    final iconRow = Row(mainAxisSize: MainAxisSize.min, children: icons);
    final clipButtons = [
      for (final c in r.clips)
        Builder(
          builder: (context) => InkWell(
            customBorder: const CircleBorder(),
            onTap: () => openYoutubeClip(
              context,
              videoId: c.videoId,
              startSec: c.startSec,
              endSec: c.endSec,
              title: r.name.isEmpty ? 'Gol' : r.name,
            ),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(
                Icons.play_circle_fill_rounded,
                size: 20,
                color: Color(0xFF10B981),
              ),
            ),
          ),
        ),
    ];
    // Video varsa isim kalan tüm genişliği kullanır, ikon orta çizgi
    // tarafına yaslanır (ev sahibinde sağda, deplasmanda solda).
    final Widget name = clipButtons.isEmpty
        ? Flexible(child: nameText)
        : Expanded(child: nameText);
    return Row(
      mainAxisAlignment: end ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: end
          ? [...clipButtons, name, const SizedBox(width: 6), iconRow]
          : [iconRow, const SizedBox(width: 6), name, ...clipButtons],
    );
  }
}

class _SummaryRow {
  _SummaryRow(this.name, this.playerId, {this.ownGoal = false});

  final String name;
  final String playerId;
  final bool ownGoal;
  final clips = <MatchHighlight>[];
  int count = 0;
  int penalties = 0;
  int yellows = 0;
  int reds = 0;
}

class _DetailEventTile extends StatelessWidget {
  /// Dolu ise yetkili kullanıcı uzun basarak olayı silebilir.
  final String eventId;
  final MatchEvent? event;
  final MatchModel match;

  /// Penaltı golü: top yerine penaltı noktası ikonu.
  final bool isPenalty;

  /// Kendi kalesine gol: kırmızı top ikonu.
  final bool isOwnGoal;
  final int minute;

  /// Uzatma dakikası (30+2'); yoksa null.
  final int? addedMinute;

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

  /// Onaylı YZ gol kesiti; varsa gol satırında video ikonu çıkar.
  final MatchHighlight? clip;

  /// Maçın bölge sorumlusu (turnuva sorumlusu) da olayı düzenler/siler.
  final bool regionOwner;
  const _DetailEventTile({
    required this.eventId,
    this.event,
    this.clip,
    this.regionOwner = false,
    required this.match,
    this.isPenalty = false,
    this.isOwnGoal = false,
    required this.minute,
    this.addedMinute,
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
    if (t.contains('bitti') || t.contains('son') || t.contains('sonuç')) {
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
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            name,
            maxLines: 1,
            style: isIn
                ? const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)
                : const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
                  ),
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
    // VAR ile iptal edilen gol: ad soluk ve üstü çizili.
    final cancelled = type == 'goal_cancelled' || type == 'red_card_cancelled';
    // Ad tek satırda tam görünür (Kadro sekmesindeki gibi); yalnız sığmayan
    // çok uzun ad, alana sığacak kadar küçülür.
    final name = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: align == CrossAxisAlignment.end
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Text(
        title.isEmpty ? '-' : title,
        maxLines: 1,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: cancelled ? const Color(0xFF94A3B8) : null,
          decoration: cancelled ? TextDecoration.lineThrough : null,
          decorationColor: const Color(0xFFDC2626),
          decorationThickness: 2,
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align,
      children: [
        if (clip == null)
          name
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: align == CrossAxisAlignment.start
                ? [
                    Flexible(child: name),
                    const SizedBox(width: 6),
                    _clipButton(),
                  ]
                : [
                    _clipButton(),
                    const SizedBox(width: 6),
                    Flexible(child: name),
                  ],
          ),
        if (sub.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              sub,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: cancelled
                    ? const Color(0xFFF87171)
                    : const Color(0xFF94A3B8),
                fontWeight: cancelled ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  /// Gol kesitini oynatan küçük video ikonu.
  Widget _clipButton() {
    final c = clip!;
    return Builder(
      builder: (context) => InkWell(
        customBorder: const CircleBorder(),
        onTap: () => openYoutubeClip(
          context,
          videoId: c.videoId,
          startSec: c.startSec,
          endSec: c.endSec,
          title: title.isEmpty ? 'Gol' : "$minute' $title",
        ),
        child: const Padding(
          padding: EdgeInsets.all(2),
          child: Icon(
            Icons.play_circle_fill_rounded,
            size: 20,
            color: Color(0xFF10B981),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isHome = teamId == homeTeamId;
    // Maçın adamının dakikası yoktur.
    final String min = type == 'man_of_the_match'
        ? ''
        : minuteLabel(minute, addedMinute, fullTime: fullTime);

    Widget icon;
    if (system) {
      icon = _systemIcon(title);
    } else {
      switch (type) {
        case 'goal':
          icon = isOwnGoal
              ? const BallIcon(tint: BallTint.red)
              : isPenalty
              ? const _PenaltyGoalIcon()
              : const BallIcon();
          break;
        case 'yellow_card':
          icon = const RefereeCardIcon.yellow();
          break;
        case 'red_card':
          icon = const RefereeCardIcon.red();
          break;
        case 'second_yellow':
          icon = const _SecondYellowCardIcon();
          break;
        case 'substitution':
          // Giren/çıkan okları yeterli; ayrıca ikon gösterilmez.
          icon = const SizedBox.shrink();
          break;
        case 'penalty_missed':
          icon = const _MissedPenaltyIcon();
          break;
        case 'man_of_the_match':
          icon = const Icon(Icons.star_rounded, size: 18, color: Colors.amber);
          break;
        case 'goal_cancelled':
          icon = const _CancelledGoalIcon();
          break;
        case 'red_card_cancelled':
          icon = const _CancelledGoalIcon(
            base: Center(child: RefereeCardIcon.grey()),
          );
          break;
        default:
          icon = const Icon(Icons.info_outline, size: 18);
      }
    }

    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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
                    // Opak: ortadaki çizgi rozetin içinden görünmesin.
                    color: const Color(0xFF1A2335),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    // Durum satırlarında (başladı, ilk yarı, sonuç) dakika yok.
                    children: [
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
          // Ortada dakika rozeti; ev sahibi olayları solda (dakikaya
          // yaslı), deplasman olayları sağda.
          : Row(
              children: [
                Expanded(
                  child: isHome
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Flexible(
                              child: _titleBlock(CrossAxisAlignment.end),
                            ),
                            const SizedBox(width: 4),
                            icon,
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
                // Rozetle iki yandaki yazı arasında az boşluk; dar tutulur
                // ki oyuncu adlarına yer kalsın.
                SizedBox(width: 44, child: Center(child: _minuteBadge(min))),
                Expanded(
                  child: isHome
                      ? const SizedBox.shrink()
                      : Row(
                          children: [
                            icon,
                            const SizedBox(width: 4),
                            Flexible(
                              child: _titleBlock(CrossAxisAlignment.start),
                            ),
                          ],
                        ),
                ),
              ],
            ),
    );
    // Akışın ortasından geçen dikey çizgi (rozetler üstünde durur).
    final tile = Stack(
      children: [
        const Positioned.fill(child: Center(child: _TimelineLine())),
        content,
      ],
    );
    final session = AppSession.of(context).value;
    // Olay girebilenler (admin, turnuva sahibi, bölge sorumlusu, gözlemci)
    // düzenleyip silebilir.
    final canDelete =
        eventId.isNotEmpty &&
        (session.canManageLeague(match.leagueId) ||
            regionOwner ||
            (match.observerId != null && match.observerId == session.user?.id));
    if (playerId.isEmpty && !canDelete) return tile;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: playerId.isEmpty
          ? null
          : () => showPlayerCard(context, playerKey: playerId),
      onLongPress: canDelete ? () => _confirmDelete(context) : null,
      child: tile,
    );
  }

  /// Ortadaki dakika rozeti; maçın adamında dakika yerine yıldız. Gol
  /// dakikası yeşil zeminde beyaz, diğer olaylar beyaz zeminde koyu yazı.
  Widget _minuteBadge(String min) {
    final goal = type == 'goal';
    final fg = goal ? Colors.white : const Color(0xFF0F172A);
    // Sabit boy: 2 haneli dakika sığar, satır genişliğine yayılmaz;
    // 60+4' gibi uzatma dakikası için biraz genişleyebilir.
    return Container(
      constraints: const BoxConstraints(minWidth: 34, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: goal ? const Color(0xFF10B981) : Colors.white,
        borderRadius: BorderRadius.circular(999),
      ),
      child: min.isEmpty
          ? Icon(Icons.star_rounded, size: 12, color: fg)
          // widthFactor 1: rozet yazı kadar (en az minWidth), yazı ortada.
          : Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(
                min,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: fg,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
    );
  }

  /// Olaya uzun basınca açılan işlem popup'ı (sağ üstte X ile kapanır):
  /// golde "VAR: Gol İptali", kırmızı kartta "VAR: Kart İptali", VAR ile
  /// iptal edilmiş golde "İptali geri al"; her olayda "Sil".
  Future<void> _confirmDelete(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final session = AppSession.of(context).value;
    final who = title.isEmpty ? 'Olay' : title;
    final subject = type == 'man_of_the_match'
        ? who
        : '${minuteLabel(minute, addedMinute, fullTime: fullTime)} $who';
    // Gol iptali skor tetikleyicisi canlı DB'ye uygulanana kadar yalnız admin.
    final canVarGoal = type == 'goal' && session.isAdmin;
    final canVarCard = type == 'red_card';
    // Düzenleme: olay giriş formu kayıtlı değerlerle açılır.
    final canEdit = !system && event != null;
    final (IconData icon, String kind) = switch (type) {
      'goal' => (Icons.sports_soccer, 'Gol'),
      'goal_cancelled' => (Icons.tv_off_rounded, 'VAR ile iptal edilen gol'),
      'red_card' => (Icons.rectangle, 'Kırmızı kart'),
      'red_card_cancelled' => (
        Icons.tv_off_rounded,
        'VAR ile iptal edilen kart',
      ),
      'yellow_card' => (Icons.rectangle, 'Sarı kart'),
      'second_yellow' => (Icons.rectangle, 'Çift sarıdan ihraç'),
      'substitution' => (Icons.swap_vert_rounded, 'Oyuncu değişikliği'),
      'penalty_missed' => (Icons.sports_soccer, 'Kaçan penaltı'),
      'man_of_the_match' => (Icons.star_rounded, 'Maçın adamı'),
      _ => (Icons.event_note_rounded, 'Maç olayı'),
    };

    Widget action(
      BuildContext ctx,
      String value,
      String label,
      IconData icon,
      Color bg, {
      Color fg = Colors.white,
    }) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        height: 48,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () => Navigator.pop(ctx, value),
          icon: Icon(icon, size: 20),
          label: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: AdminDialogCloseOverlay(
          onClose: () => Navigator.pop(ctx),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: adminDialogDecoration(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminDialogHeader(icon: icon, title: subject, subtitle: kind),
                const SizedBox(height: 6),
                if (canEdit)
                  action(
                    ctx,
                    'edit',
                    'DÜZENLE',
                    Icons.edit_rounded,
                    kAdminAccent,
                  ),
                if (canVarGoal)
                  action(
                    ctx,
                    'var',
                    'VAR: GOL İPTALİ',
                    Icons.tv_off_rounded,
                    kAdminAmber,
                    fg: const Color(0xFF0F172A),
                  ),
                if (canVarCard)
                  action(
                    ctx,
                    'var',
                    'VAR: KART İPTALİ',
                    Icons.tv_off_rounded,
                    kAdminAmber,
                    fg: const Color(0xFF0F172A),
                  ),
                if (type == 'goal_cancelled')
                  action(
                    ctx,
                    'restore',
                    'İPTALİ GERİ AL',
                    Icons.undo_rounded,
                    kAdminAccent,
                  ),
                action(
                  ctx,
                  'delete',
                  'SİL',
                  Icons.delete_outline_rounded,
                  const Color(0xFFDC2626),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    final svc = ServiceLocator.matchService;
    try {
      switch (choice) {
        case 'var':
          final goal = type == 'goal';
          final ok = await showVarConfirmDialog(
            context,
            title: goal ? 'VAR: Gol İptali' : 'VAR: Kart İptali',
            subject: subject,
            message: goal
                ? 'Bu gol iptal edilecek. Skor güncellenir ve maçı takip '
                      'edenlere bildirim gider.'
                : 'Bu kırmızı kart iptal edilecek; karttan doğan ceza da '
                      'kaldırılır.',
          );
          if (!ok) return;
          if (goal) {
            await svc.setGoalCancelled(eventId, cancelled: true);
          } else {
            await svc.cancelRedCard(eventId);
          }
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                goal
                    ? 'Gol VAR kararıyla iptal edildi.'
                    : 'Kart VAR kararıyla iptal edildi.',
              ),
            ),
          );
        case 'edit':
          await showDialog<void>(
            context: context,
            builder: (_) => AdminMatchEventScreen(match: match, event: event),
          );
        case 'restore':
          await svc.setGoalCancelled(eventId, cancelled: false);
          messenger.showSnackBar(
            const SnackBar(content: Text('Gol yeniden geçerli.')),
          );
        case 'delete':
          final ok = await showAdminConfirmDialog(
            context: context,
            title: 'Olayı sil',
            message: '$subject kaydı silinsin mi?',
          );
          if (!ok) return;
          await svc.deleteMatchEvent(eventId);
          messenger.showSnackBar(
            const SnackBar(content: Text('Olay silindi.')),
          );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
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
      db.from('seasons').select('starting_player_count').eq('id', m.seasonId),
    ]);
    final players = {for (final p in results[0] as List<PlayerModel>) p.id: p};
    final rosters = results[1] as List<MatchRosterModel>;
    final teams = {
      for (final r in results[2] as List) (r as Map)['id'].toString(): r,
    };
    final leagueRows = results[3] as List;
    final league = leagueRows.isEmpty ? null : leagueRows.first as Map;

    final seasonRows = results[4] as List;
    final need = seasonRows.isEmpty
        ? 11
        : ((seasonRows.first as Map)['starting_player_count'] as num?)
                  ?.toInt() ??
              11;

    // Eksik kadronun afişi çıkmaz (Kadro ve Diziliş sekmesi aynı kural).
    final starters = rosters.where((r) => r.isStarting).toList();
    if (starters.length < need) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Esame girişini tamamlayın: ilk $need oyuncunun tamamını seçin '
            '(şu an ${starters.length} / $need).',
          ),
        ),
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
      // Maç detayı bandındaki kısa ad ("Masterler" vb. olmadan).
      teamName: shortTeamName(isHome ? homeName : awayName),
      teamLogo: (team?['logo_url'] ?? '').toString().trim(),
      opponentName: shortTeamName(isHome ? awayName : homeName),
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
    leagueId: match.leagueId,
    poster: kind == 'Esame'
        ? LineupListPoster(data: data)
        : LineupPitchPoster(data: data),
  );
}

/// Sekme: üstte ikon, altında kısa ad; [live] ise ikonun köşesinde yanıp
/// sönen kırmızı nokta.
class _IconTab extends StatelessWidget {
  const _IconTab({required this.icon, required this.label, this.live = false});

  final IconData icon;
  final String label;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Tab(
      height: 50,
      iconMargin: const EdgeInsets.only(bottom: 2),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, size: 19),
          if (live) const Positioned(top: -2, right: -6, child: _LiveDot()),
        ],
      ),
      text: label,
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.25, end: 1).animate(_blink),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF111A2E), width: 1.5),
        ),
      ),
    );
  }
}

/// Skorun yanındaki küçük kalem: 2. yarı geç başlatıldıysa şu anki dakika
/// düzeltilir (ör. 31' → 35'); second_half_at buna göre geri alınır.
class _SecondHalfMinuteEdit extends StatelessWidget {
  const _SecondHalfMinuteEdit({required this.match, required this.onSaved});

  final MatchModel match;
  final VoidCallback onSaved;

  Future<void> _edit(BuildContext context) async {
    final now = MatchClock.liveMinuteParts(match);
    if (now == null) return;
    final period = MatchClock.periodOf(match.seasonId);
    final current = now.minute + (now.added ?? 0);
    var value = current;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Widget step(IconData icon, int d) => SizedBox(
            width: 48,
            height: 48,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                side: const BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => setLocal(
                () => value = (value + d).clamp(period + 1, period * 2 + 30),
              ),
              child: Icon(icon),
            ),
          );
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 28),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: adminDialogDecoration(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AdminDialogHeader(
                    icon: Icons.timer_outlined,
                    title: '2. yarı dakikası',
                    subtitle: 'Geç başlatıldıysa şu anki dakikayı ayarla',
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      step(Icons.remove_rounded, -1),
                      SizedBox(
                        width: 110,
                        child: Text(
                          "$value'",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      step(Icons.add_rounded, 1),
                    ],
                  ),
                  const SizedBox(height: 18),
                  AdminPrimaryButton(
                    label: 'KAYDET',
                    onPressed: () => Navigator.pop(ctx, value),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (picked == null || picked == current || !context.mounted) return;
    // Dakika = period + (şimdi − 2. yarı başlangıcı) + 1.
    final start = DateTime.now().toUtc().subtract(
      Duration(minutes: picked - period - 1),
    );
    final messenger = ScaffoldMessenger.of(context);
    try {
      final rows = await Supabase.instance.client
          .from('matches')
          .update({'second_half_at': start.toIso8601String()})
          .eq('id', match.id)
          .select('id');
      if (rows.isEmpty) throw Exception('yetki yok');
      SupabaseMatchService.notifyLocalChange(match.id);
      onSaved();
      messenger.showSnackBar(
        SnackBar(content: Text("Dakika $picked' olarak düzeltildi.")),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Düzeltilemedi: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () => _edit(context),
        child: Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFFBBF24).withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: const Color(0xFFFBBF24).withValues(alpha: 0.5),
            ),
          ),
          child: const Icon(
            Icons.edit_rounded,
            size: 13,
            color: Color(0xFFFBBF24),
          ),
        ),
      ),
    );
  }
}
