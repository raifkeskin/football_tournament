import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/app_session.dart';
import '../../../core/services/app_settings.dart';
import '../../../core/services/data_versions.dart';
import '../../../core/utils/string_utils.dart';
import '../../../core/utils/team_name.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../../core/widgets/youtube_player_page.dart';
import '../../match/widgets/youtube_find_sheet.dart';
import '../../news/week_awards.dart';

/// Ana sayfada "Bu hafta sen": giriş yapan futbolcunun son maçı (son 7 gün,
/// bu turnuvada) için kaydırmalı kart. Sekmeler sırayla: o hafta aldığı
/// Haftanın Enleri ödülleri, gol/asist (skor + gol videoları), maçın
/// fotoğrafları. Olmayan sekme çıkmaz; hiçbiri yoksa kart görünmez.
/// Yeni özellik: admin her zaman, diğerleri my_week_enabled açıksa.
class MyWeekCard extends StatefulWidget {
  const MyWeekCard({super.key, required this.leagueId});

  final String leagueId;

  /// Kart ana sayfada görünsün mü (selamlamadaki profil kısayolu da aynı
  /// anahtarla açılır).
  static bool enabledFor(AppSessionState s) =>
      s.isAdmin || AppSettings.myWeekEnabled.value;

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
    required this.week,
    required this.homeName,
    required this.awayName,
    required this.homeLogo,
    required this.awayLogo,
    required this.hs,
    required this.as,
    required this.events,
    this.awards = const [],
    this.photos = const [],
  });

  final int? week;
  final String homeName;
  final String awayName;
  final String homeLogo;
  final String awayLogo;
  final int hs;
  final int as;
  final List<_Goal> events;

  /// O hafta Haftanın Enleri'nde aldığı ödüller (ör. "HAFTANIN OYUNCUSU").
  final List<({String title, Color color, String mark})> awards;

  /// Maçın fotoğrafları (albüm).
  final List<String> photos;

  bool get isEmpty => events.isEmpty && awards.isEmpty && photos.isEmpty;

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
    return _Week(
      week: wk,
      homeName: shortTeamName(
        (team[m['home_team_id']]?['name'] ?? '').toString(),
      ),
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
    if (d == null || d.isEmpty) return const SizedBox.shrink();
    // Sekmeler: o hafta ödül varsa önce Ödüller, sonra gol/asist, sonra
    // maçın fotoğrafları; olmayan sekme hiç çıkmaz.
    final pages = <(String, Widget)>[
      if (d.awards.isNotEmpty) ('ÖDÜLLER', _awardsPage(d)),
      if (d.events.isNotEmpty)
        (
          d.goals > 0 && d.assists > 0
              ? 'GOL & ASİST'
              : d.goals > 0
              ? 'GOLLER'
              : 'ASİSTLER',
          _goalsPage(d),
        ),
      if (d.photos.isNotEmpty) ('FOTOĞRAFLAR', _photosPage(d)),
    ];
    final tab = _tab.clamp(0, pages.length - 1);
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
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
            const SizedBox(height: 10),
            SizedBox(
              height: 178,
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
            if (pages.length > 1)
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
        ),
      ),
    );
  }

  Widget _crest(String url) => SizedBox(
    width: 26,
    height: 26,
    child: url.isEmpty
        ? const Icon(Icons.shield_outlined, color: Colors.white38, size: 22)
        : WebSafeImage(url: url, fit: BoxFit.contain),
  );

  Widget _scoreRow(_Week d) => Row(
    children: [
      _crest(d.homeLogo),
      const SizedBox(width: 8),
      Text(
        '${d.hs}-${d.as}',
        style: const TextStyle(
          fontFamily: 'BarlowCondensed',
          fontWeight: FontWeight.w800,
          fontSize: 24,
          height: 1,
          color: Colors.white,
        ),
      ),
      const SizedBox(width: 8),
      _crest(d.awayLogo),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          '${d.homeName} – ${d.awayName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, fontSize: 12.5),
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

  Widget _goalsPage(_Week d) {
    final title = [
      if (d.goals > 0) '${d.goals} GOL',
      if (d.assists > 0) '${d.assists} ASİST',
    ].join(' · ');
    final clips = d.clips;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'BarlowCondensed',
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w800,
            fontSize: 30,
            height: 1,
            color: _gold,
          ),
        ),
        const SizedBox(height: 8),
        _scoreRow(d),
        const SizedBox(height: 10),
        if (clips.isNotEmpty)
          SizedBox(
            height: 86,
            child: ListView.separated(
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
            ),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in d.events)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (e.assist
                                ? const Color(0xFF38BDF8)
                                : const Color(0xFF10B981))
                            .withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    [
                      e.label,
                      e.assist ? 'Asist' : 'Gol',
                    ].where((t) => t.isNotEmpty).join(' '),
                    style: TextStyle(
                      color: e.assist
                          ? const Color(0xFF7DD3FC)
                          : const Color(0xFF34D399),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

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

  Widget _photosPage(_Week d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Maçından ${d.photos.length} fotoğraf',
          style: const TextStyle(
            fontFamily: 'BarlowCondensed',
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        _scoreRow(d),
        const SizedBox(height: 10),
        SizedBox(
          height: 92,
          child: ListView.separated(
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
          ),
        ),
      ],
    );
  }

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
