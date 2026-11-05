import 'package:flutter/material.dart';

import '../../core/services/app_session.dart';
import '../../core/widgets/admin_page.dart';
import '../../core/widgets/app_name_band.dart';
import '../news/screens/admin_manage_news_screen.dart';
import '../news/widgets/result_news_cards.dart';
import '../player/widgets/player_card.dart' show showPlayerCard;
import '../tournament/models/league_extras.dart';
import 'instagram_embed.dart';
import 'videos.dart';

/// Maç detayı › Medya › Röportajlar: maç öncesi / maç anı / maç sonrası
/// grupları. Yetkili her grubun sonunda "Video ekle" görür; diğerleri izler.
class MatchInterviewsView extends StatefulWidget {
  const MatchInterviewsView({
    super.key,
    required this.match,
    required this.canManage,
  });

  final VideoMatchRef match;
  final bool canManage;

  @override
  State<MatchInterviewsView> createState() => _MatchInterviewsViewState();
}

class _MatchInterviewsViewState extends State<MatchInterviewsView> {
  late Future<List<VideoItem>> _f = VideoService.forMatch(widget.match.id);

  @override
  void initState() {
    super.initState();
    VideoService.changed.addListener(_reload);
  }

  @override
  void dispose() {
    VideoService.changed.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) {
      setState(() => _f = VideoService.forMatch(widget.match.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<VideoItem>>(
      future: _f,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: kAdminAccent),
          );
        }
        final all = snap.data!;
        final groups = [
          for (final k in VideoKind.interviews)
            (
              k,
              [
                for (final v in all)
                  if (v.kind == k) v,
              ],
            ),
        ];
        final shown = [
          for (final g in groups)
            if (g.$2.isNotEmpty || widget.canManage) g,
        ];
        if (shown.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Bu maç için henüz röportaj eklenmedi.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 104),
          children: [
            for (final (kind, items) in shown) ...[
              _groupHead(kind, items.length),
              const SizedBox(height: 8),
              SizedBox(
                height: 168,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 134,
                          child: VideoTile(
                            item: items[i],
                            onTap: () => openVideoPlayer(context, items, i),
                            onLongPress: widget.canManage
                                ? () => showVideoActions(context, items[i])
                                : null,
                          ),
                        ),
                      ),
                    if (widget.canManage && items.length < 4)
                      SizedBox(
                        width: 134,
                        child: _AddSlot(
                          onTap: () => showAddVideoDialog(
                            context,
                            match: widget.match,
                            initialKind: kind,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
            if (widget.canManage)
              const Text(
                'Videoya uzun basarak kaldırabilirsiniz. Her tür için ilk '
                'video eklenince haber kendiliğinden açılır; sonrakiler aynı '
                'habere eklenir.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
          ],
        );
      },
    );
  }

  Widget _groupHead(VideoKind k, int n) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: k.color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 7),
      Text(
        n > 0 ? '${k.label.toUpperCase()} · $n' : k.label.toUpperCase(),
        style: TextStyle(
          color: k.color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    ],
  );
}

class _AddSlot extends StatelessWidget {
  const _AddSlot({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF334155), width: 1.5),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, color: Colors.white60),
              SizedBox(height: 4),
              Text(
                'Video ekle',
                style: TextStyle(
                  color: Colors.white60,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Haber kartı: maç röportajları ('interviews') ve turnuva videosu
/// ('video'). Videolar yan yana; dokununca kartın içinde oynar.
class NewsVideosCard extends StatefulWidget {
  const NewsVideosCard({
    super.key,
    required this.item,
    required this.meta,
    required this.loggedIn,
    required this.liked,
    required this.likeCount,
    required this.onToggleLike,
    required this.onShare,
  });

  final NewsItem item;
  final String meta;
  final bool loggedIn;
  final bool liked;
  final int likeCount;
  final VoidCallback onToggleLike;
  final VoidCallback onShare;

  static bool handles(NewsItem n) =>
      (n.autoKind == 'interviews' || n.autoKind == 'video') &&
      n.autoData != null;

  @override
  State<NewsVideosCard> createState() => _NewsVideosCardState();
}

class _NewsVideosCardState extends State<NewsVideosCard> {
  /// Kartın içinde oynayan video; null: kapaklar.
  int? _playing;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final d = item.autoData!;
    final logo = (d['logo'] ?? '').toString().trim();
    final kind = item.autoKind == 'video'
        ? VideoKind.tournament
        : VideoKind.of(d['kind']?.toString());
    final videos = [
      for (final v in (d['videos'] as List? ?? const []))
        if (v is Map) VideoItem.fromNews(v, kind, logo: logo),
    ];
    // Oynayan videonun etiketleri; kapak görünümünde hepsinin.
    final p = _playing;
    final tags = <VideoTag>[];
    for (final v in (p != null && p < videos.length) ? [videos[p]] : videos) {
      for (final t in v.players) {
        if (!tags.any((x) => x.id == t.id)) tags.add(t);
      }
    }
    final title = (item.headline ?? '').trim().isNotEmpty
        ? item.headline!
        : item.autoKind == 'video'
        ? ((d['title'] ?? '').toString().trim().isEmpty
              ? item.content
              : d['title'].toString())
        : '${d['home']} – ${d['away']}';
    final kicker = item.autoKind == 'video'
        ? 'TURNUVA VİDEOSU'
        : '${kind.label.toUpperCase()} RÖPORTAJLARI'
              '${item.week != null ? ' · ${item.week}. HAFTA' : ''}';
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF131D33),
        borderRadius: BorderRadius.circular(16),
        border: item.pinnedAt != null
            ? Border.all(color: const Color(0x66FBBF24))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (item.pinnedAt != null) ...[
                      const Icon(
                        Icons.push_pin_rounded,
                        size: 14,
                        color: Color(0xFFFBBF24),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        kicker,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: kind.color,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    Text(
                      widget.meta,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
          if (_playing != null && _playing! < videos.length)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColoredBox(
                  color: Colors.black,
                  child: Stack(
                    children: [
                      InstagramEmbed(url: videos[_playing!].url, focused: true),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Material(
                          color: const Color(0x99000000),
                          shape: const CircleBorder(),
                          child: IconButton(
                            tooltip: 'Kapat',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            onPressed: () => setState(() => _playing = null),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: videos.length == 1 ? 220 : 190,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  for (var i = 0; i < videos.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        right: i == videos.length - 1 ? 0 : 8,
                      ),
                      child: SizedBox(
                        width: videos.length == 1
                            ? MediaQuery.sizeOf(context).width - 56
                            : 150,
                        child: VideoTile(
                          item: videos[i],
                          large: videos.length == 1,
                          onTap: () => setState(() => _playing = i),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: VideoTagsRow(
                tags: tags,
                onTap: (t) => showPlayerCard(context, playerKey: t.id),
              ),
            ),
          NewsCardActions(
            loggedIn: widget.loggedIn,
            liked: widget.liked,
            likeCount: widget.likeCount,
            onToggleLike: widget.onToggleLike,
            onShare: widget.onShare,
            linkText: item.matchId != null ? 'Maça git' : null,
            onLink: item.matchId != null
                ? () => openNewsMatch(context, item.matchId!)
                : null,
          ),
        ],
      ),
    );
  }
}

/// Menüdeki Videolar simgesi: turnuvanın güncel sezonunun videoları ve
/// (yetkiliye) turnuvanın haberleri.
class TournamentVideosScreen extends StatelessWidget {
  const TournamentVideosScreen({
    super.key,
    required this.leagueId,
    required this.seasonId,
  });

  final String leagueId;
  final String seasonId;

  static Future<void> open(
    BuildContext context, {
    required String leagueId,
    required String seasonId,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'TournamentVideosScreen'),
      builder: (_) =>
          TournamentVideosScreen(leagueId: leagueId, seasonId: seasonId),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final session = AppSession.of(context).value;
    final manage = canManageVideos(session, leagueId, seasonId);
    final videos = _VideosTab(
      leagueId: leagueId,
      seasonId: seasonId,
      canManage: manage,
    );
    if (!manage) {
      return BandBackPage(
        subtitle: 'Videolar',
        child: Scaffold(
          backgroundColor: kAdminBg,
          body: SafeArea(top: false, child: videos),
        ),
      );
    }
    return BandBackPage(
      subtitle: 'Videolar ve Haberler',
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: kAdminBg,
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                const TabBar(
                  indicatorColor: kAdminAccent,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white60,
                  dividerColor: Colors.transparent,
                  labelStyle: TextStyle(fontWeight: FontWeight.w800),
                  tabs: [
                    Tab(text: 'Videolar'),
                    Tab(text: 'Haberler'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      videos,
                      AdminManageNewsScreen(leagueId: leagueId, embedded: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideosTab extends StatefulWidget {
  const _VideosTab({
    required this.leagueId,
    required this.seasonId,
    required this.canManage,
  });

  final String leagueId;
  final String seasonId;
  final bool canManage;

  @override
  State<_VideosTab> createState() => _VideosTabState();
}

class _VideosTabState extends State<_VideosTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<VideoItem>> _f = VideoService.forSeason(widget.seasonId);

  /// 0 tümü, 1 turnuva, 2 röportajlar.
  int _filter = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    VideoService.changed.addListener(_reload);
  }

  @override
  void dispose() {
    VideoService.changed.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) {
      setState(() => _f = VideoService.forSeason(widget.seasonId));
    }
  }

  String _caption(VideoItem v) => v.kind == VideoKind.tournament
      ? 'TURNUVA'
      : [
          v.kind.label.toUpperCase(),
          if (v.week != null) '${v.week}. HAFTA',
        ].join(' · ');

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: widget.canManage
          ? FloatingActionButton(
              heroTag: null,
              tooltip: 'Turnuva videosu ekle',
              backgroundColor: kAdminAccent,
              foregroundColor: Colors.white,
              onPressed: () =>
                  showAddVideoDialog(context, seasonId: widget.seasonId),
              child: const Icon(Icons.add_rounded, size: 28),
            )
          : null,
      body: FutureBuilder<List<VideoItem>>(
        future: _f,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: kAdminAccent),
            );
          }
          final all = snap.data!;
          final tCount = all
              .where((v) => v.kind == VideoKind.tournament)
              .length;
          final list = [
            for (final v in all)
              if (_filter == 0 ||
                  (_filter == 1) == (v.kind == VideoKind.tournament))
                v,
          ];
          // Sabitlenen turnuva videosu en üstte büyük.
          final featured = _filter == 2
              ? null
              : list
                    .where((v) => v.pinned && v.kind == VideoKind.tournament)
                    .firstOrNull;
          final grid = [
            for (final v in list)
              if (v != featured) v,
          ];
          final playList = [?featured, ...grid];
          Widget chip(int i, String label) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(label),
              selected: _filter == i,
              showCheckmark: false,
              onSelected: (_) => setState(() => _filter = i),
              labelStyle: TextStyle(
                color: _filter == i ? kAdminAccent : Colors.white70,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
              backgroundColor: const Color(0xFF131D33),
              selectedColor: kAdminAccent.withValues(alpha: 0.16),
              side: BorderSide.none,
              shape: const StadiumBorder(),
            ),
          );
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, kAdminFabClearance),
            children: [
              Row(
                children: [
                  chip(0, 'Tümü ${all.length}'),
                  chip(1, 'Turnuva $tCount'),
                  chip(2, 'Röportajlar ${all.length - tCount}'),
                ],
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Text(
                    widget.canManage
                        ? 'Henüz video yok.\nSağ alttaki ＋ ile turnuva videosu '
                              'ekleyin; maç röportajları maç detayından eklenir.'
                        : 'Henüz video yok.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, height: 1.4),
                  ),
                ),
              if (featured != null) ...[
                AspectRatio(
                  aspectRatio: 16 / 10,
                  child: VideoTile(
                    item: featured,
                    large: true,
                    caption: 'TURNUVA',
                    onTap: () => openVideoPlayer(context, playList, 0),
                    onLongPress: widget.canManage
                        ? () =>
                              showVideoActions(context, featured, canPin: true)
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: grid.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 9 / 14,
                ),
                itemBuilder: (_, i) {
                  final v = grid[i];
                  return VideoTile(
                    item: v,
                    caption: _caption(v),
                    onTap: () =>
                        openVideoPlayer(context, playList, playList.indexOf(v)),
                    onLongPress: widget.canManage
                        ? () => showVideoActions(
                            context,
                            v,
                            canPin: v.kind == VideoKind.tournament,
                          )
                        : null,
                  );
                },
              ),
              if (widget.canManage && all.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Videoya uzun basarak sabitleyebilir ya da '
                    'kaldırabilirsiniz.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Takım sayfası › Medya: takımın röportajları (en yenisi önce).
class TeamVideosTab extends StatefulWidget {
  const TeamVideosTab({
    super.key,
    required this.seasonId,
    required this.teamId,
  });

  final String? seasonId;
  final String teamId;

  @override
  State<TeamVideosTab> createState() => _TeamVideosTabState();
}

class _TeamVideosTabState extends State<TeamVideosTab> {
  late Future<List<VideoItem>> _f = _load();

  Future<List<VideoItem>> _load() {
    final sid = widget.seasonId;
    if (sid == null || sid.isEmpty) return Future.value(const []);
    return VideoService.forTeam(sid, widget.teamId);
  }

  @override
  void initState() {
    super.initState();
    VideoService.changed.addListener(_reload);
  }

  @override
  void didUpdateWidget(covariant TeamVideosTab old) {
    super.didUpdateWidget(old);
    if (old.seasonId != widget.seasonId) _f = _load();
  }

  @override
  void dispose() {
    VideoService.changed.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _f = _load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<VideoItem>>(
      future: _f,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: CircularProgressIndicator(color: kAdminAccent),
            ),
          );
        }
        final list = snap.data!;
        if (list.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Henüz röportaj yok.\nMaç detayında Medya › Röportaj bölümünden '
              'eklenen videolar burada görünür.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, height: 1.4),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: list.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 9 / 14,
            ),
            itemBuilder: (context, i) {
              final v = list[i];
              return VideoTile(
                item: v,
                caption: [
                  v.kind.label.toUpperCase(),
                  if (v.week != null) '${v.week}. HAFTA',
                ].join(' · '),
                onTap: () => openVideoPlayer(context, list, i),
              );
            },
          ),
        );
      },
    );
  }
}
