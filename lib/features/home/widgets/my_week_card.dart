import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/app_session.dart';
import '../../../core/services/app_settings.dart';
import '../../../core/services/data_versions.dart';
import '../../../core/services/image_upload_service.dart';
import '../../../core/utils/string_utils.dart';
import '../../../core/utils/team_name.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../../core/widgets/youtube_player_page.dart';
import '../../match/widgets/youtube_find_sheet.dart';
import '../../news/week_awards.dart';
import '../../referees/referee_widgets.dart';
import '../../share/match_player_poster.dart';
import '../../share/poster_background.dart';
import '../../share/poster_share.dart';
import '../../share/team_result_poster.dart';

/// Ana sayfada "Bu hafta sen": giriş yapan futbolcunun son maçı (son 7 gün,
/// bu turnuvada) için kart. Üstte gol/asist manşeti (yoksa doğrudan maç
/// sonucu), altta sezon şeridi. Arada, yalnız varsa, kaydırmalı sekmeler:
/// o hafta aldığı Haftanın Enleri ödülleri, gol videoları, maçın
/// fotoğrafları. Kartın boyu içeriğe göre; sabit boş alan yok.
/// Yeni özellik: admin her zaman, diğerleri my_week_enabled açıksa.
class MyWeekCard extends StatefulWidget {
  const MyWeekCard({super.key, required this.leagueId});

  final String leagueId;

  /// Kart ana sayfada görünsün mü (selamlamadaki profil kısayolu da aynı
  /// anahtarla açılır).
  static bool enabledFor(AppSessionState s) =>
      s.isAdmin || AppSettings.myWeekEnabled.value;

  /// Kartın altındaki maç afişi kısayolu (yeni özellik: admin her zaman,
  /// diğerleri my_week_poster_enabled açıksa).
  static bool posterFor(AppSessionState s) =>
      s.isAdmin || AppSettings.myWeekPosterEnabled.value;

  @override
  State<MyWeekCard> createState() => _MyWeekCardState();
}

class _Goal {
  const _Goal({
    required this.id,
    required this.label,
    required this.assist,
    this.videoId,
    this.start = 0,
    this.end = 0,
    this.clipUrl,
    this.storyUrl,
  });

  final String id;
  final String label;
  final bool assist;
  final String? videoId;
  final int start;
  final int end;
  final String? clipUrl;
  final String? storyUrl;
}

class _Week {
  const _Week({
    required this.id,
    required this.week,
    required this.mineHome,
    required this.homeName,
    required this.awayName,
    this.homeId = '',
    this.awayId = '',
    this.homeFull = '',
    this.awayFull = '',
    required this.homeLogo,
    required this.awayLogo,
    required this.hs,
    required this.as,
    required this.events,
    this.awards = const [],
    this.photos = const [],
    this.played = 0,
    this.wins = 0,
    this.seasonGoals = 0,
    this.seasonAssists = 0,
    this.rank,
    this.groups = 1,
  });

  /// Maç kimliği (karta dokununca maç detayı açılır).
  final String id;
  final int? week;

  /// Futbolcunun takımı ev sahibi mi (bilinmiyorsa null).
  final bool? mineHome;

  /// Sezon toplamları ve takımının grup sırası (alt şerit).
  final int played;
  final int wins;
  final int seasonGoals;
  final int seasonAssists;
  final int? rank;
  final int groups;
  final String homeName;
  final String awayName;

  /// Takım kimlikleri ve kısaltılmamış adları (maç afişi için).
  final String homeId;
  final String awayId;
  final String homeFull;
  final String awayFull;
  final String homeLogo;
  final String awayLogo;
  final int hs;
  final int as;
  final List<_Goal> events;

  /// O hafta Haftanın Enleri'nde aldığı ödüller (ör. "HAFTANIN OYUNCUSU").
  final List<({String title, Color color, String mark})> awards;

  /// Maçın fotoğrafları (albüm).
  final List<String> photos;

  int get goals => events.where((e) => !e.assist).length;
  int get assists => events.where((e) => e.assist).length;
  List<_Goal> get clips => [
    for (final e in events)
      if ((e.videoId ?? '').isNotEmpty) e,
  ];
}

class _MyWeekCardState extends State<MyWeekCard> {
  /// Turnuva + futbolcu → son yüklenen (ekrana dönüşte anında görünsün).
  static final Map<String, _Week?> _cache = {};

  final _sb = Supabase.instance.client;
  String? _pid;
  _Week? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pid = AppSession.of(context).value.playerId;
    if (pid != _pid) {
      _pid = pid;
      _data = pid == null ? null : _cache['${widget.leagueId}|$pid'];
      if (pid != null) _load(pid);
    }
  }

  /// Cihazdaki kopya (kişinin kendi haftası; çıkışta silinir).
  String _diskKey(String pid) =>
      '${VersionedCache.personalPrefix}my_week:${widget.leagueId}|$pid';

  /// Önce cihazdaki kopya (uygulama açılır açılmaz kart yerinde olsun),
  /// sonra tek istekle güncel hâli (bkz. 20261113160000_my_week.sql;
  /// önceden 4 sıralı tur atılıyor, kart Ana Sayfa'ya geç geliyordu).
  Future<void> _load(String pid) async {
    final key = '${widget.leagueId}|$pid';
    if (_data == null) {
      final saved = await VersionedCache.peek(_diskKey(pid));
      if (saved is Map && saved.isNotEmpty && mounted && _pid == pid) {
        try {
          final week = _build(Map<String, dynamic>.from(saved), pid);
          _cache.putIfAbsent(key, () => week);
          if (_data == null) setState(() => _data = week);
        } catch (_) {}
      }
    }
    try {
      final raw = await _sb.rpc(
        'my_week',
        params: {'p_league_id': widget.leagueId, 'p_player_id': pid},
      );
      final data = raw is Map ? Map<String, dynamic>.from(raw) : null;
      final week = data == null ? null : _build(data, pid);
      _cache[key] = week;
      if (data == null) {
        VersionedCache.remove(_diskKey(pid)).ignore();
      } else {
        VersionedCache.save(_diskKey(pid), data, null).ignore();
      }
      if (!mounted || _pid != pid) return;
      setState(() => _data = week);
    } catch (_) {
      // Kart isteğe bağlı: okunamazsa cihazdaki kopya (varsa) kalır.
    }
  }

  static List<Map<String, dynamic>> _rows(Object? v) => [
    if (v is List)
      for (final r in v)
        if (r is Map) Map<String, dynamic>.from(r),
  ];

  /// Sunucudan (ya da cihazdaki kopyadan) gelen ham veriden kart.
  static _Week _build(Map<String, dynamic> raw, String pid) {
    final m = Map<String, dynamic>.from(raw['match'] as Map);
    final wk = (m['week'] as num?)?.toInt();
    final here = _rows(raw['events']);
    final teams = _rows(raw['teams']);
    final clips = _rows(raw['clips']);
    final media = _rows(raw['media']);
    final news = _rows(raw['news']);
    final team = {for (final t in teams) t['id']: t};
    final clipOf = {for (final c in clips) c['match_event_id']: c};
    String label(Map e) {
      final n = (e['minute'] as num?)?.toInt() ?? 0;
      final a = (e['added_minute'] as num?)?.toInt() ?? 0;
      if (n <= 0) return '';
      return a > 0 ? "$n+$a'" : "$n'";
    }

    _Goal goal(Map e) {
      final own = e['player_id'] == pid;
      final c = clipOf[e['id']];
      return _Goal(
        id: e['id'].toString(),
        label: label(e),
        assist: !own,
        videoId: c?['video_id']?.toString(),
        start: (c?['start_sec'] as num?)?.toInt() ?? 0,
        end: (c?['end_sec'] as num?)?.toInt() ?? 0,
        clipUrl: c?['clip_url']?.toString(),
        storyUrl: c?['story_url']?.toString(),
      );
    }

    final awards = <({String title, Color color, String mark})>[];
    for (final n in news) {
      final d = n['auto_data'];
      if (d is! Map) continue;
      final w = WeekAwards.fromJson(d);
      for (final a in w.awards) {
        if (a.person?.id == pid) {
          awards.add((
            title: a.kind.full.trUpper,
            color: a.kind.color,
            mark: a.kind == AwardKind.player ? '★' : '',
          ));
        }
      }
      if (w.hasEleven && w.eleven.any((e) => e.person.id == pid)) {
        awards.add((
          title: "HAFTANIN 11'İ",
          color: const Color(0xFF34D399),
          mark: '11',
        ));
      }
    }

    // Fotoğraf sırası: önce kendi takımının takım fotoğrafı, sonra
    // futbolcunun yıldızladıkları, sonra diğerleri.
    final myTeam = raw['my_team']?.toString();
    final starred = {
      if (raw['starred'] is List)
        for (final x in raw['starred'] as List) x.toString(),
    };
    final events = [for (final e in here) goal(e)]
      ..sort((a, b) => _minute(a.label).compareTo(_minute(b.label)));
    final season = raw['season'] is Map ? raw['season'] as Map : const {};
    int stat(String k) => (season[k] as num?)?.toInt() ?? 0;
    return _Week(
      id: (m['id'] ?? '').toString(),
      week: wk,
      mineHome: myTeam == null
          ? null
          : myTeam == m['home_team_id']?.toString()
          ? true
          : myTeam == m['away_team_id']?.toString()
          ? false
          : null,
      played: stat('played'),
      wins: stat('wins'),
      seasonGoals: stat('goals'),
      seasonAssists: stat('assists'),
      rank: (season['rank'] as num?)?.toInt(),
      groups: stat('groups'),
      homeName: shortTeamName(
        (team[m['home_team_id']]?['name'] ?? '').toString(),
      ),
      homeId: (m['home_team_id'] ?? '').toString(),
      awayId: (m['away_team_id'] ?? '').toString(),
      homeFull: (team[m['home_team_id']]?['name'] ?? '').toString(),
      awayFull: (team[m['away_team_id']]?['name'] ?? '').toString(),
      awayName: shortTeamName(
        (team[m['away_team_id']]?['name'] ?? '').toString(),
      ),
      homeLogo: (team[m['home_team_id']]?['logo_url'] ?? '').toString(),
      awayLogo: (team[m['away_team_id']]?['logo_url'] ?? '').toString(),
      hs: (m['home_score'] as num?)?.toInt() ?? 0,
      as: (m['away_score'] as num?)?.toInt() ?? 0,
      events: events,
      awards: awards,
      photos: _orderPhotos(media, myTeam: myTeam, starred: starred),
    );
  }

  static List<String> _orderPhotos(
    List<Map<String, dynamic>> media, {
    required String? myTeam,
    required Set<String> starred,
  }) {
    int rank(Map r) {
      if (r['media_type'] == 'Takım Fotosu' &&
          myTeam != null &&
          r['team_id']?.toString() == myTeam) {
        return 0;
      }
      if (starred.contains(r['id'].toString())) return 1;
      return 2;
    }

    final list = [
      for (final r in media)
        if ((r['url'] ?? '').toString().trim().isNotEmpty) r,
    ];
    // Sıralama kararlı: aynı gruptakiler eklenme sırasını korur.
    final sorted = [
      for (var g = 0; g < 3; g++)
        for (final r in list)
          if (rank(r) == g) r['url'].toString().trim(),
    ];
    return sorted;
  }

  static int _minute(String label) =>
      int.tryParse(label.split(RegExp(r"[+']")).first) ?? 0;

  void _play(_Goal g) {
    openYoutubeClip(
      context,
      videoId: g.videoId!,
      startSec: g.start,
      endSec: g.end,
      clipUrl: g.clipUrl,
      storyUrl: g.storyUrl,
      title: '${g.assist ? 'Asist' : 'Gol'} ${g.label}'.trim(),
    );
  }

  final _pager = PageController();
  int _tab = 0;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  static const _gold = Color(0xFFE2B845);
  static const _green = Color(0xFF34D399);

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) return const SizedBox.shrink();
    // Alt alan yalnız gösterilecek bir şey varsa çıkar (sabit boş alan yok):
    // o hafta ödül, gol/asist videosu, maçın fotoğrafları.
    final clips = d.clips;
    final pages = <(String, Widget, double)>[
      if (d.awards.isNotEmpty)
        ('ÖDÜLLER', _awardsPage(d), 54.0 + 35 * d.awards.take(3).length),
      if (clips.isNotEmpty)
        (
          d.goals > 0 && d.assists > 0
              ? 'GOL & ASİST'
              : d.goals > 0
              ? 'GOLLER'
              : 'ASİSTLER',
          _clipsPage(clips),
          86.0,
        ),
      if (d.photos.isNotEmpty) ('FOTOĞRAFLAR', _photosPage(d), 92.0),
    ];
    final tab = pages.isEmpty ? 0 : _tab.clamp(0, pages.length - 1);
    final pageHeight = pages.fold<double>(0, (h, p) => p.$3 > h ? p.$3 : h);
    final strip = _seasonItems(d);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF10B981).withValues(alpha: 0.35),
          ),
          gradient: const RadialGradient(
            center: Alignment.topLeft,
            radius: 1.6,
            colors: [Color(0xFF14532D), Color(0xFF0F2A20), Color(0xFF1E293B)],
            stops: [0, 0.45, 1],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: d.id.isEmpty
                  ? null
                  : () => openRefereeMatch(context, d.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'BU HAFTA SEN',
                          style: TextStyle(
                            color: _green,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const Spacer(),
                        if (d.week != null)
                          Text(
                            '${d.week}. Hafta',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Gol/asist varsa manşet; yoksa doğrudan maç sonucu.
                    if (d.events.isNotEmpty) _headline(d) else _board(d),
                    if (d.events.isNotEmpty && clips.isEmpty) ...[
                      const SizedBox(height: 10),
                      _minuteChips(d),
                    ],
                  ],
                ),
              ),
            ),
            if (pages.length > 1) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 30,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: pages.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => _pager.animateToPage(
                      i,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i == tab
                            ? const Color(0xFF10B981)
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(
                        pages[i].$1,
                        style: TextStyle(
                          fontFamily: 'BarlowCondensed',
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          letterSpacing: 0.8,
                          color: i == tab
                              ? const Color(0xFF04211A)
                              : Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (pages.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: pageHeight,
                child: PageView(
                  controller: _pager,
                  onPageChanged: (i) => setState(() => _tab = i),
                  children: [
                    for (final p in pages)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: p.$2,
                      ),
                  ],
                ),
              ),
            ],
            if (pages.length > 1) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == tab ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == tab
                            ? const Color(0xFF10B981)
                            : Colors.white24,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ],
            if (strip.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 14),
                padding: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.09),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    for (final s in strip)
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              s.$1,
                              style: const TextStyle(
                                fontFamily: 'BarlowCondensed',
                                fontWeight: FontWeight.w800,
                                fontSize: 22,
                                height: 1,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              s.$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (MyWeekCard.posterFor(AppSession.of(context).value))
              _posterStrip(d),
          ],
        ),
      ),
    );
  }

  /// Sezon şeridi: en çok üç kutu. Sıfır olan gösterilmez, yerini sıradaki
  /// alır (gol/asisti olmayan oyuncu galibiyet ve takım sırasını görür).
  List<(String, String)> _seasonItems(_Week d) {
    if (d.played <= 0) return const [];
    return [
      ('${d.played}', 'Sezonda maç'),
      if (d.seasonGoals > 0) ('${d.seasonGoals}', 'Gol'),
      if (d.seasonAssists > 0) ('${d.seasonAssists}', 'Asist'),
      if (d.wins > 0) ('${d.wins}', 'Galibiyet'),
      if (d.rank != null)
        ('${d.rank}.', d.groups > 1 ? 'Grup sırası' : 'Lig sırası'),
    ].take(3).toList();
  }

  /// Maç afişi verisi. [extra] dokununca okunan bilgiler (turnuva, forma
  /// numarası, saha, ad); kart küçük resmi onsuz çizilir.
  MatchPosterData _posterData(
    _Week d, {
    String first = '',
    String last = '',
    String number = '',
    String leagueName = '',
    String leagueLogo = '',
    String pitch = '',
    String rosterTeam = '',
  }) {
    final mineHome = rosterTeam.isNotEmpty
        ? rosterTeam == d.homeId
        : (d.mineHome ?? true);
    String full(String raw) => posterTeamName(raw).trUpper;
    final goals = [
      for (final e in d.events)
        if (!e.assist) e.label,
    ];
    final assists = [
      for (final e in d.events)
        if (e.assist) e.label,
    ];
    String mins(List<String> l) => l.where((x) => x.isNotEmpty).join(' ');
    final a = d.awards.isEmpty ? null : d.awards.first;
    return MatchPosterData(
      firstName: first,
      lastName: last,
      number: number,
      leagueName: leagueName,
      leagueLogo: leagueLogo,
      week: d.week,
      home: PosterTeam(
        name: full(d.homeFull),
        logo: d.homeLogo,
        score: d.hs,
        own: mineHome,
      ),
      away: PosterTeam(
        name: full(d.awayFull),
        logo: d.awayLogo,
        score: d.as,
        own: !mineHome,
      ),
      teamName: full(mineHome ? d.homeFull : d.awayFull),
      teamLogo: mineHome ? d.homeLogo : d.awayLogo,
      pitch: pitch.trUpper,
      contributions: [
        if (goals.isNotEmpty)
          PosterContribution(
            count: goals.length,
            assist: false,
            minutes: mins(goals),
          ),
        if (assists.isNotEmpty)
          PosterContribution(
            count: assists.length,
            assist: true,
            minutes: mins(assists),
          ),
      ],
      // Kartın sezon şeridiyle aynı kural: sıfırlar yerine sıradaki bilgi.
      season: d.played <= 0
          ? const []
          : [
              ('${d.played}', 'MAÇ'),
              if (d.seasonGoals > 0) ('${d.seasonGoals}', 'GOL'),
              if (d.seasonAssists > 0) ('${d.seasonAssists}', 'ASİST'),
              if (d.wins > 0) ('${d.wins}', 'GALİBİYET'),
              if (d.rank != null) ('${d.rank}.', 'SIRA'),
            ].take(3).toList(),
      award: a?.title ?? '',
      awardStar: a?.mark == '★',
    );
  }

  bool _posterBusy = false;

  /// Futbolcunun bu maçtaki takımı (bilinmiyorsa boş).
  String _myTeamId(_Week d) => d.mineHome == null
      ? ''
      : d.mineHome!
      ? d.homeId
      : d.awayId;

  /// Takım afişi seçeneği: takımın sorumlusuna (yeni özellik: admin her
  /// zaman, diğerleri team_result_poster_enabled açıksa).
  bool _teamPosterFor(_Week d) {
    final team = _myTeamId(d);
    if (team.isEmpty || d.id.isEmpty) return false;
    final s = AppSession.of(context).value;
    if (s.isAdmin) return true;
    return AppSettings.teamPosterEnabled.value &&
        s.managedTeams.any((t) => t.teamId == team);
  }

  /// Takım afişinin küçük görüntüsü: takım fotoğrafı + skor şeridi.
  Widget _teamThumb(_Week d) {
    final photo = d.photos.isNotEmpty ? d.photos.first : '';
    return SizedBox(
      width: 46,
      height: 57.5,
      child: ColoredBox(
        color: const Color(0xFF0B1322),
        child: Column(
          children: [
            const SizedBox(height: 6),
            SizedBox(
              height: 28,
              width: 46,
              child: photo.isEmpty
                  ? const Icon(
                      Icons.groups_rounded,
                      color: Colors.white38,
                      size: 20,
                    )
                  : WebSafeImage(url: photo, fit: BoxFit.cover),
            ),
            const Spacer(),
            Container(
              height: 1.5,
              color: _gold,
              margin: const EdgeInsets.symmetric(horizontal: 4),
            ),
            Container(
              height: 7,
              margin: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Container(color: const Color(0xFFF4F6FA)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Container(color: const Color(0xFF0B1322)),
                  ),
                  Expanded(
                    flex: 4,
                    child: Container(color: const Color(0xFFF4F6FA)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Takım sorumlusunda tek PAYLAŞ: hangi afiş olduğu sorulur.
  Future<void> _choosePoster(_Week d) async {
    final session = AppSession.of(context).value;
    final name = (session.displayName ?? '').trim().split(RegExp(r'\s+'));
    final thumbPhoto = d.photos.isNotEmpty
        ? d.photos.first
        : (session.photoUrl ?? '').trim();
    Widget option(
      BuildContext ctx,
      Widget thumb,
      String label,
      String value,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.pop(ctx, value),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(5), child: thumb),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white54),
              ],
            ),
          ),
        ),
      ),
    );
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Hangi afişi paylaşacaksın?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              option(
                ctx,
                SizedBox(
                  width: 46,
                  height: 57.5,
                  child: FittedBox(
                    child: PosterOptions(
                      style: const PosterStyle(format: PosterFormat.post),
                      child: MatchPlayerPoster(
                        data: _posterData(
                          d,
                          first: name.length > 1
                              ? name
                                    .sublist(0, name.length - 1)
                                    .join(' ')
                                    .trUpper
                              : '',
                          last: name.last.trUpper,
                        ),
                        photo: thumbPhoto.isEmpty
                            ? null
                            : NetworkImage(thumbPhoto),
                      ),
                    ),
                  ),
                ),
                'Kendi afişim',
                'me',
              ),
              option(ctx, _teamThumb(d), 'Takım afişi', 'team'),
            ],
          ),
        ),
      ),
    );
    if (!mounted || picked == null) return;
    if (picked == 'me') {
      await _openPoster(d);
    } else {
      await _openTeamPoster(d);
    }
  }

  Future<void> _openTeamPoster(_Week d) async {
    if (_posterBusy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _posterBusy = true);
    try {
      await openTeamResultPoster(
        context,
        leagueId: widget.leagueId,
        matchId: d.id,
        teamId: _myTeamId(d),
        week: d.week,
        homeId: d.homeId,
        awayId: d.awayId,
        homeName: d.homeFull.isNotEmpty ? d.homeFull : d.homeName,
        awayName: d.awayFull.isNotEmpty ? d.awayFull : d.awayName,
        homeLogo: d.homeLogo,
        awayLogo: d.awayLogo,
        homeScore: d.hs,
        awayScore: d.as,
        onLoaded: () {
          if (mounted) setState(() => _posterBusy = false);
        },
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Afiş açılamadı, tekrar dene.')),
      );
    } finally {
      if (mounted) setState(() => _posterBusy = false);
    }
  }

  /// Kartın altında: afişin küçük hâli + "Paylaş". Takım sorumlusunda iki
  /// küçük görüntü (kendi + takım) ve tek PAYLAŞ; basınca seçim sorulur.
  Widget _posterStrip(_Week d) {
    final session = AppSession.of(context).value;
    final thumbPhoto = d.photos.isNotEmpty
        ? d.photos.first
        : (session.photoUrl ?? '').trim();
    final name = (session.displayName ?? '').trim().split(RegExp(r'\s+'));
    final team = _teamPosterFor(d);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _posterBusy
          ? null
          : () => team ? _choosePoster(d) : _openPoster(d),
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _gold.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 46,
                height: 57.5,
                child: FittedBox(
                  child: PosterOptions(
                    style: const PosterStyle(format: PosterFormat.post),
                    child: MatchPlayerPoster(
                      data: _posterData(
                        d,
                        first: name.length > 1
                            ? name.sublist(0, name.length - 1).join(' ').trUpper
                            : '',
                        last: name.last.trUpper,
                      ),
                      photo: thumbPhoto.isEmpty
                          ? null
                          : NetworkImage(thumbPhoto),
                    ),
                  ),
                ),
              ),
            ),
            if (team) ...[
              const SizedBox(width: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: _teamThumb(d),
              ),
            ],
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    team ? 'Afişler hazır' : 'Maç afişin hazır',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    team ? 'Kendi ve takım afişin' : 'Fotoğrafını seç, paylaş',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                color: _green,
                borderRadius: BorderRadius.circular(10),
              ),
              child: _posterBusy
                  ? const SizedBox(
                      width: 62,
                      height: 16,
                      child: Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF04211A),
                          ),
                        ),
                      ),
                    )
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.ios_share_rounded,
                          size: 16,
                          color: Color(0xFF04211A),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'PAYLAŞ',
                          style: TextStyle(
                            fontFamily: 'BarlowCondensed',
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            letterSpacing: 0.6,
                            color: Color(0xFF04211A),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Afiş penceresi: dokununca turnuva, forma numarası, saha, ad ve maçın
  /// bütün fotoğrafları okunur (kart isteği hafif kalsın). Fotoğraf sırası:
  /// bu maçta "Bu benim" denenler, profil fotoğrafı, maçın diğer anları,
  /// takım fotoğrafları. Pencerede telefondan fotoğraf da seçilebilir.
  Future<void> _openPoster(_Week d) async {
    final pid = _pid;
    if (pid == null || _posterBusy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _posterBusy = true);
    Future<Object?> safe(Future<Object?> f) async {
      try {
        return await f;
      } catch (_) {
        return null;
      }
    }

    try {
      final r = await Future.wait<Object?>([
        safe(
          _sb
              .from('leagues')
              .select('name, logo_url')
              .eq('id', widget.leagueId)
              .maybeSingle(),
        ),
        safe(
          _sb
              .from('match_rosters')
              .select('jersey_number, team_id')
              .eq('match_id', d.id)
              .eq('player_id', pid)
              .maybeSingle(),
        ),
        safe(
          _sb
              .from('matches')
              .select('pitches(name)')
              .eq('id', d.id)
              .maybeSingle(),
        ),
        safe(
          _sb
              .from('players')
              .select('name, surname, photo_url')
              .eq('id', pid)
              .maybeSingle(),
        ),
        safe(
          _sb
              .from('match_media')
              .select('id, url, media_type')
              .eq('match_id', d.id)
              .inFilter('media_type', ['Önemli An', 'Takım Fotosu'])
              .order('created_at'),
        ),
        safe(
          _sb
              .from('player_photo_stars')
              .select('media_id')
              .eq('player_id', pid),
        ),
      ]);
      if (!mounted) return;
      final league = r[0] as Map?;
      final roster = r[1] as Map?;
      final match = r[2] as Map?;
      final player = r[3] as Map?;
      final media = [
        if (r[4] is List)
          for (final x in r[4] as List)
            if (x is Map && (x['url'] ?? '').toString().trim().isNotEmpty) x,
      ];
      final stars = {
        if (r[5] is List)
          for (final x in r[5] as List)
            if (x is Map) x['media_id'].toString(),
      };

      final first = (player?['name'] ?? '').toString().trim();
      final last = (player?['surname'] ?? '').toString().trim();
      final data = _posterData(
        d,
        first: first.trUpper,
        last: last.trUpper,
        number: (roster?['jersey_number'] ?? '').toString(),
        leagueName: (league?['name'] ?? '').toString(),
        leagueLogo: (league?['logo_url'] ?? '').toString(),
        pitch: ((match?['pitches'] as Map?)?['name'] ?? '').toString(),
        rosterTeam: (roster?['team_id'] ?? '').toString(),
      );

      final profileRaw = (player?['photo_url'] ?? '').toString().trim();
      final profile = profileRaw.isEmpty
          ? ''
          : SupabaseImageUploadService.hdUrl(profileRaw);
      String url(Map x) => x['url'].toString().trim();
      final choices = <String>[];
      void add(String u) {
        if (u.isNotEmpty && !choices.contains(u)) choices.add(u);
      }

      for (final x in media) {
        if (stars.contains(x['id'].toString())) add(url(x));
      }
      add(profile);
      for (final x in media) {
        if (x['media_type'] == 'Önemli An') add(url(x));
      }
      for (final x in media) {
        add(url(x));
      }

      final slug = [
        last,
        if (d.week != null) '${d.week}_hafta',
      ].join('_').toLowerCase().replaceAll(RegExp(r'\s+'), '_');
      // Pencere açıkken düğmede dönen gösterge kalmasın.
      setState(() => _posterBusy = false);
      await showPosterPreview(
        context: context,
        title: 'Maç Afişi',
        fileName: 'mac_afisi_$slug',
        formats: const [PosterFormat.post, PosterFormat.story],
        imageUrls: [
          data.leagueLogo,
          d.homeLogo,
          d.awayLogo,
        ].where((u) => u.isNotEmpty).toList(),
        photoPoster: (photo, frame) =>
            MatchPlayerPoster(data: data, photo: photo, frame: frame),
        photoUrl: choices.isEmpty ? null : choices.first,
        photoChoices: choices,
      );
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Afiş açılamadı, tekrar dene.')),
      );
    } finally {
      if (mounted) setState(() => _posterBusy = false);
    }
  }

  Widget _crest(String url, [double size = 26]) => SizedBox(
    width: size,
    height: size,
    child: url.isEmpty
        ? Icon(Icons.shield_outlined, color: Colors.white38, size: size * 0.85)
        : WebSafeImage(url: url, fit: BoxFit.contain),
  );

  /// Kendi takımına göre sonuç etiketi (takımı bilinmiyorsa çıkmaz).
  Widget _resultTag(_Week d) {
    final mine = d.mineHome;
    if (mine == null) return const SizedBox.shrink();
    final diff = mine ? d.hs - d.as : d.as - d.hs;
    final (text, color) = diff > 0
        ? ('GALİBİYET', _green)
        : diff == 0
        ? ('BERABERLİK', const Color(0xFF93A3B8))
        : ('MAĞLUBİYET', const Color(0xFFEF6A5B));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'BarlowCondensed',
          fontWeight: FontWeight.w800,
          fontSize: 12.5,
          letterSpacing: 1.2,
          height: 1.1,
          color: Color(0xFF0A1020),
        ),
      ),
    );
  }

  /// Manşet: solda gol/asist sayısı, sağda sonuç etiketi ve iki takım.
  Widget _headline(_Week d) {
    Widget num(int n, String unit, Color color, double size) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$n',
          style: TextStyle(
            fontFamily: 'BarlowCondensed',
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w800,
            fontSize: size,
            height: 0.9,
            color: color,
          ),
        ),
        Text(
          unit,
          style: TextStyle(
            fontFamily: 'BarlowCondensed',
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w800,
            fontSize: size * 0.34,
            letterSpacing: 1,
            color: color,
          ),
        ),
      ],
    );
    final both = d.goals > 0 && d.assists > 0;
    final size = both ? 46.0 : 58.0;

    Widget teamRow(String logo, String name, int score, bool lost) => Opacity(
      opacity: lost ? 0.6 : 1,
      child: Row(
        children: [
          _crest(logo),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name.trUpper,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'BarlowCondensed',
                fontWeight: FontWeight.w800,
                // Uzun ad önce küçülür, yine sığmazsa "…" ile kesilir.
                fontSize: name.length > 16 ? 14.5 : 17,
                letterSpacing: 0.3,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$score',
            style: const TextStyle(
              fontFamily: 'BarlowCondensed',
              fontWeight: FontWeight.w800,
              fontSize: 23,
              height: 1,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );

    return Row(
      children: [
        SizedBox(
          width: 104,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (d.goals > 0) num(d.goals, 'GOL', _gold, size),
                if (both) const SizedBox(width: 10),
                if (d.assists > 0) num(d.assists, 'ASİST', _green, size),
              ],
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _resultTag(d),
              const SizedBox(height: 7),
              teamRow(d.homeLogo, d.homeName, d.hs, d.hs < d.as),
              const SizedBox(height: 6),
              teamRow(d.awayLogo, d.awayName, d.as, d.as < d.hs),
            ],
          ),
        ),
      ],
    );
  }

  /// Gol/asist yoksa: doğrudan maç sonucu (arma + ad, ortada skor).
  Widget _board(_Week d) {
    Widget side(String logo, String name, bool mine) => Expanded(
      child: Column(
        children: [
          _crest(logo, 44),
          const SizedBox(height: 7),
          Text(
            name.trUpper,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'BarlowCondensed',
              fontWeight: FontWeight.w800,
              fontSize: 16,
              height: 1.1,
              letterSpacing: 0.3,
              color: mine ? _green : Colors.white,
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          side(d.homeLogo, d.homeName, d.mineHome == true),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${d.hs}-${d.as}',
                style: const TextStyle(
                  fontFamily: 'BarlowCondensed',
                  fontWeight: FontWeight.w800,
                  fontSize: 46,
                  height: 1,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 7),
              _resultTag(d),
            ],
          ),
          const SizedBox(width: 8),
          side(d.awayLogo, d.awayName, d.mineHome == false),
        ],
      ),
    );
  }

  /// Videosu olmayan gol/asistlerin dakika rozetleri.
  Widget _minuteChips(_Week d) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final e in d.events)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: (e.assist ? _green : _gold).withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            [
              e.label,
              e.assist ? 'Asist' : 'Gol',
            ].where((t) => t.isNotEmpty).join(' '),
            style: TextStyle(
              fontFamily: 'BarlowCondensed',
              color: e.assist ? _green : _gold,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
    ],
  );

  Widget _awardsPage(_Week d) {
    final photo = (AppSession.of(context).value.photoUrl ?? '').trim();
    final shown = d.awards.take(3).toList();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64,
          height: 64,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _gold, width: 2),
            color: Colors.white10,
          ),
          child: photo.isEmpty
              ? const Icon(Icons.emoji_events_rounded, color: _gold, size: 32)
              : WebSafeImage(url: photo, fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TEBRİKLER!',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              Text(
                d.awards.length == 1
                    ? 'BU HAFTA ÖDÜL ALDIN'
                    : 'BU HAFTA ${d.awards.length} ÖDÜL',
                style: const TextStyle(
                  fontFamily: 'BarlowCondensed',
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w800,
                  fontSize: 24,
                  height: 1.05,
                  color: _gold,
                ),
              ),
              const SizedBox(height: 8),
              for (final a in shown)
                Container(
                  margin: const EdgeInsets.only(bottom: 5),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: a.color,
                          shape: BoxShape.circle,
                        ),
                        child: a.mark.isEmpty
                            ? const Icon(
                                Icons.emoji_events_rounded,
                                size: 13,
                                color: Color(0xFF0A1020),
                              )
                            : Text(
                                a.mark,
                                style: const TextStyle(
                                  color: Color(0xFF0A1020),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          a.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'BarlowCondensed',
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _clipsPage(List<_Goal> clips) => ListView.separated(
    scrollDirection: Axis.horizontal,
    itemCount: clips.length,
    separatorBuilder: (_, _) => const SizedBox(width: 8),
    itemBuilder: (context, i) {
      final g = clips[i];
      return GestureDetector(
        onTap: () => _play(g),
        child: SizedBox(
          width: 152,
          child: Stack(
            children: [
              BroadcastThumb(videoId: g.videoId!, radius: 10),
              Positioned(
                right: 6,
                top: 6,
                child: _tag(
                  g.assist ? 'ASİST' : 'GOL',
                  g.assist ? _green : _gold,
                ),
              ),
              if (g.label.isNotEmpty)
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      g.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _tag(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFF0A1020),
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      ),
    ),
  );

  Widget _photosPage(_Week d) => ListView.separated(
    scrollDirection: Axis.horizontal,
    itemCount: d.photos.length,
    separatorBuilder: (_, _) => const SizedBox(width: 6),
    itemBuilder: (_, i) => GestureDetector(
      onTap: () => _openPhotos(d.photos, i),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 92,
          child: WebSafeImage(url: d.photos[i], fit: BoxFit.cover),
        ),
      ),
    ),
  );

  void _openPhotos(List<String> urls, int start) {
    final page = PageController(initialPage: start);
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.black,
                iconTheme: const IconThemeData(color: Colors.white),
              ),
              body: PageView.builder(
                controller: page,
                itemCount: urls.length,
                itemBuilder: (_, i) => InteractiveViewer(
                  maxScale: 4,
                  child: Center(
                    child: WebSafeImage(
                      url: urls[i],
                      width: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
        )
        .whenComplete(page.dispose);
  }
}
