import 'package:flutter/material.dart';
import '../../match/screens/live_draw_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/active_tournament.dart';
import '../../../core/services/app_session.dart';
import '../../../core/services/global_filter.dart';
import '../../../core/services/league_scope.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/master_class_app_bar.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../tournament/models/league_extras.dart';
import '../../tournament/services/interfaces/i_league_service.dart';

const _bgDark = Color(0xFF0F172A);
const _card = Color(0xFF1E293B);
const _muted = Color(0xFF94A3B8);
const _heart = Color(0xFFF87171);

Color _accent() =>
    ActiveTournament.theme.value?.secondary ?? const Color(0xFF10B981);

/// Haberler: bantta seçili turnuvanın yayındaki haberleri, en yeni önce.
/// Turnuvanın bölgeleri varsa üstte "Tümü · Bölge…" sekmeleri; ekran kişinin
/// kendi bölgesiyle açılır. Haberler kompakt listelenir, dokununca yerinde
/// açılır (aynı anda tek haber açık).
class NewsFeedScreen extends StatefulWidget {
  const NewsFeedScreen({super.key});

  /// Ana sayfadaki son dakika kartından gelinen haber: açık gösterilir.
  static final focusNewsId = ValueNotifier<String?>(null);

  @override
  State<NewsFeedScreen> createState() => _NewsFeedScreenState();
}

class _Region {
  const _Region(this.id, this.name);
  final String id;
  final String name;
}

/// Turnuvanın bölgeleri + kişinin bölgesi.
class _RegionMeta {
  const _RegionMeta(this.regions, this.mine);
  final List<_Region> regions;
  final String? mine;
}

class _NewsFeedScreenState extends State<NewsFeedScreen> {
  final ILeagueService _leagueService = ServiceLocator.leagueService;

  /// Bölge bilgisi turnuva + kişi başına bir kez okunur.
  static final Map<String, _RegionMeta> _metaCache = {};

  /// Turnuva başına seçili sekme (null: Tümü).
  final Map<String, String?> _tabByLeague = {};
  final Set<String> _tabChosen = {};

  String? _openId;
  final Map<String, GlobalKey> _keys = {};
  List<NewsItem> _visible = const [];

  /// Sunucu yanıtı gelene kadar kullanıcının son tercihi (iyimser güncelleme).
  final Map<String, bool> _likeOverride = {};
  final Set<String> _likeBusy = {};

  @override
  void initState() {
    super.initState();
    GlobalFilter.leagueId.addListener(_onChanged);
    ActiveTournament.theme.addListener(_onChanged);
    NewsFeedScreen.focusNewsId.addListener(_onFocus);
    // Sekme ilk kez kurulurken bekleyen bir haber varsa.
    if (NewsFeedScreen.focusNewsId.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onFocus());
    }
  }

  @override
  void dispose() {
    GlobalFilter.leagueId.removeListener(_onChanged);
    ActiveTournament.theme.removeListener(_onChanged);
    NewsFeedScreen.focusNewsId.removeListener(_onFocus);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  String? get _leagueId =>
      GlobalFilter.leagueId.value ?? ActiveTournament.currentLeagueId.value;

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ---- Bölgeler -------------------------------------------------------

  Future<void> _ensureMeta(String leagueId, AppSessionState session) async {
    final key = '$leagueId|${session.user?.id}';
    if (_metaCache.containsKey(key)) return;
    _metaCache[key] = const _RegionMeta([], null); // tekrar istenmesin
    try {
      final sb = Supabase.instance.client;
      final seasons = await sb
          .from('seasons')
          .select('id')
          .eq('league_id', leagueId)
          .order('is_active', ascending: false)
          .order('start_date', ascending: false)
          .limit(1);
      if (seasons.isEmpty) return;
      final seasonId = seasons.first['id'].toString();
      final rows = await sb
          .from('season_regions')
          .select('id, name, sort_order')
          .eq('season_id', seasonId)
          .order('sort_order');
      final regions = [
        for (final r in rows) _Region(r['id'].toString(), '${r['name']}'),
      ];
      String? mine;
      if (regions.length > 1) {
        mine = await _myRegion(leagueId, seasonId, session, regions);
      }
      _metaCache[key] = _RegionMeta(regions, mine);
      if (mounted) setState(() {});
    } catch (_) {
      _metaCache.remove(key);
    }
  }

  /// Kişinin bölgesi: bölge sorumlusu → kendi bölgesi; oyuncu / takım
  /// sorumlusu / takip edilen takım → takımın grubunun bölgesi.
  Future<String?> _myRegion(
    String leagueId,
    String seasonId,
    AppSessionState s,
    List<_Region> regions,
  ) async {
    for (final r in s.ownedRegions) {
      if (r.seasonId == seasonId && regions.any((x) => x.id == r.id)) {
        return r.id;
      }
    }
    final sb = Supabase.instance.client;
    final teamIds = <String>{
      for (final m in s.managedTeams)
        if (m.seasonId == seasonId) m.teamId,
      ?s.teamId,
    };
    final playerId = s.playerId ?? '';
    if (playerId.isNotEmpty) {
      final rows = await sb
          .from('season_team_players')
          .select('team_id')
          .eq('season_id', seasonId)
          .eq('player_id', playerId)
          .eq('is_active', true);
      teamIds.addAll(rows.map((r) => r['team_id'].toString()));
    }
    if (teamIds.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final followed = prefs.getString('followed_team_$leagueId');
      if (followed != null) teamIds.add(followed);
    }
    if (teamIds.isEmpty) return null;
    final links = await sb
        .from('season_teams')
        .select('groups(region_id)')
        .eq('season_id', seasonId)
        .inFilter('team_id', teamIds.toList());
    for (final l in links) {
      final rid = (l['groups'] as Map?)?['region_id']?.toString();
      if (rid != null && regions.any((x) => x.id == rid)) return rid;
    }
    return null;
  }

  // ---- Etkileşim ------------------------------------------------------

  void _onFocus() {
    final id = NewsFeedScreen.focusNewsId.value;
    if (id == null || !mounted) return;
    final leagueId = _leagueId;
    final item = _visible.where((n) => n.id == id).firstOrNull;
    setState(() {
      _openId = id;
      // Haber seçili sekmede yoksa Tümü'ne geç.
      if (item == null && leagueId != null) {
        _tabByLeague[leagueId] = null;
        _tabChosen.add(leagueId);
      }
    });
    NewsFeedScreen.focusNewsId.value = null;
    _scrollTo(id);
  }

  void _toggle(String id) {
    setState(() => _openId = _openId == id ? null : id);
    if (_openId == id) _scrollTo(id);
  }

  /// Açılan haber ekranın üstüne gelsin (üstteki haber kapanınca liste
  /// kaysa da gözden kaçmasın).
  void _scrollTo(String id) {
    Future.delayed(const Duration(milliseconds: 260), () {
      final ctx = _keys[id]?.currentContext;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        alignment: 0.02,
      );
    });
  }

  Future<void> _toggleLike(NewsItem n, bool currentlyLiked) async {
    if (_likeBusy.contains(n.id)) return;
    final next = !currentlyLiked;
    setState(() {
      _likeOverride[n.id] = next;
      _likeBusy.add(n.id);
    });
    try {
      await _leagueService.setNewsLike(newsId: n.id, liked: next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _likeOverride.remove(n.id));
      _snack('Beğeni kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _likeBusy.remove(n.id));
    }
  }

  Future<void> _share(NewsItem n) async {
    final title = n.leagueName.isEmpty ? '' : '${n.leagueName}\n\n';
    final images = n.imageUrls.isEmpty ? '' : '\n\n${n.imageUrls.join('\n')}';
    await SharePlus.instance.share(
      ShareParams(text: '$title${n.content}$images'),
    );
  }

  void _openGallery(List<String> urls, int index) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.94),
      builder: (ctx) => _GalleryViewer(urls: urls, initial: index),
    );
  }

  // ---- Görünüm --------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final session = AppSession.of(context).value;
    final leagueId = _leagueId;
    _RegionMeta? meta;
    if (leagueId != null) {
      _ensureMeta(leagueId, session);
      meta = _metaCache['$leagueId|${session.user?.id}'];
      // Kişinin bölgesi bilinince (kendisi seçmediyse) o sekmeyle açılır.
      if (meta != null && !_tabChosen.contains(leagueId)) {
        _tabByLeague[leagueId] = meta.mine;
      }
    }
    final regions = meta?.regions ?? const <_Region>[];
    final tab = leagueId == null ? null : _tabByLeague[leagueId];

    return Scaffold(
      backgroundColor: _bgDark,
      extendBodyBehindAppBar: true,
      appBar: const MasterClassAppBar(title: 'Haberler'),
      body: SafeArea(
        child: Column(
          children: [
            if (regions.length > 1)
              _RegionTabs(
                regions: regions,
                selectedId: tab,
                onSelected: (id) => setState(() {
                  _tabByLeague[leagueId!] = id;
                  _tabChosen.add(leagueId);
                }),
              ),
            Expanded(child: _feed(session, leagueId, tab)),
          ],
        ),
      ),
    );
  }

  Widget _feed(AppSessionState session, String? leagueId, String? regionId) {
    final loggedIn = session.user != null;
    return StreamBuilder<List<NewsItem>>(
      // Servis aynı kullanıcı + turnuva için tek akış döndürür.
      stream: _leagueService.watchNewsFeed(leagueId: leagueId),
      builder: (context, snap) {
        if (snap.hasError && !snap.hasData) {
          return const _Message('Haberler yüklenemedi.');
        }
        if (!snap.hasData) {
          return Center(child: CircularProgressIndicator(color: _accent()));
        }
        // Bölge sekmesinde: o bölgenin ve tüm turnuvanın haberleri.
        final items = snap.data!
            .where(
              (n) =>
                  LeagueScope.allows(n.tournamentId) &&
                  (regionId == null ||
                      n.regionId == null ||
                      n.regionId == regionId),
            )
            .toList();
        _visible = items;

        // Sunucu verisi kullanıcının tercihine yetiştiyse geçici durumu bırak.
        for (final n in items) {
          final o = _likeOverride[n.id];
          if (o != null && o == n.likedByMe && !_likeBusy.contains(n.id)) {
            _likeOverride.remove(n.id);
          }
        }

        if (items.isEmpty) {
          return const _Message('Henüz yayınlanmış haber yok.');
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 32),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final n = items[i];
            if (n.liveDrawId != null) {
              return LiveDrawNewsCard(
                key: _keys.putIfAbsent(n.id, GlobalKey.new),
                drawId: n.liveDrawId!,
                content: n.content,
              );
            }
            final liked = _likeOverride[n.id] ?? n.likedByMe;
            final count =
                (n.likeCount - (n.likedByMe ? 1 : 0) + (liked ? 1 : 0)).clamp(
                  0,
                  1 << 31,
                );
            return _NewsTile(
              key: _keys.putIfAbsent(n.id, GlobalKey.new),
              item: n,
              open: _openId == n.id,
              loggedIn: loggedIn,
              liked: liked,
              likeCount: count,
              onToggle: () => _toggle(n.id),
              onToggleLike: () => _toggleLike(n, liked),
              onShare: () => _share(n),
              onOpenPhoto: (i) => _openGallery(n.imageUrls, i),
            );
          },
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, fontSize: 15),
        ),
      ),
    );
  }
}

class _RegionTabs extends StatelessWidget {
  const _RegionTabs({
    required this.regions,
    required this.selectedId,
    required this.onSelected,
  });

  final List<_Region> regions;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final entries = <MapEntry<String?, String>>[
      const MapEntry(null, 'Tümü'),
      for (final r in regions) MapEntry(r.id, r.name),
    ];
    final accent = _accent();
    final onAccent = accent.computeLuminance() > 0.45
        ? const Color(0xFF0B1220)
        : Colors.white;
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final e = entries[i];
          final active = e.key == selectedId;
          return InkWell(
            onTap: () => onSelected(e.key),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? accent : _card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: active ? accent : Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Text(
                e.value,
                style: TextStyle(
                  color: active ? onAccent : const Color(0xFFCBD5E1),
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Kompakt haber kartı: solda kapak, sağda başlık ve bilgi; dokununca
/// yerinde açılır (tam metin, fotoğraf kaydırıcı, beğen / paylaş).
class _NewsTile extends StatelessWidget {
  const _NewsTile({
    super.key,
    required this.item,
    required this.open,
    required this.loggedIn,
    required this.liked,
    required this.likeCount,
    required this.onToggle,
    required this.onToggleLike,
    required this.onShare,
    required this.onOpenPhoto,
  });

  final NewsItem item;
  final bool open;
  final bool loggedIn;
  final bool liked;
  final int likeCount;
  final VoidCallback onToggle;
  final VoidCallback onToggleLike;
  final VoidCallback onShare;
  final ValueChanged<int> onOpenPhoto;

  /// İlk satır kısa ise başlık, kalanı gövde; değilse metnin tamamı.
  (String, String) _split() {
    final text = item.content.trim();
    final nl = text.indexOf('\n');
    if (nl > 0 && nl <= 140) {
      return (text.substring(0, nl).trim(), text.substring(nl + 1).trim());
    }
    return (text, '');
  }

  @override
  Widget build(BuildContext context) {
    final (title, body) = _split();
    final accent = _accent();
    final imgs = item.imageUrls;
    final meta = [
      _timeAgo(item.createdAt),
      if (item.regionName.isNotEmpty) item.regionName,
    ].join(' · ');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: open
              ? accent.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Thumb(item: item),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: open && body.isEmpty ? null : 2,
                          overflow: open && body.isEmpty
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            height: 1.3,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Icon(
                              liked
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 14,
                              color: liked ? _heart : _muted,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '$likeCount',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 6),
                            AnimatedRotation(
                              turns: open ? 0.5 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 20,
                                color: _muted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !open
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (imgs.isNotEmpty)
                        _Carousel(urls: imgs, onOpen: onOpenPhoto),
                      if (body.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                          child: SelectableText(
                            body,
                            style: const TextStyle(
                              color: Color(0xFFE2E8F0),
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ),
                      _actions(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
      child: Row(
        children: [
          if (loggedIn) ...[
            IconButton(
              tooltip: liked ? 'Beğeniyi geri al' : 'Beğen',
              onPressed: onToggleLike,
              icon: Icon(
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: liked ? _heart : Colors.white,
                size: 25,
              ),
            ),
            Text(
              liked ? 'Beğendin' : 'Beğen',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Text(
                'Beğenmek için giriş yap',
                style: TextStyle(color: _muted, fontSize: 13),
              ),
            ),
          const Spacer(),
          IconButton(
            tooltip: 'Paylaş',
            onPressed: onShare,
            icon: const Icon(
              Icons.send_outlined,
              color: Colors.white,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kartın solundaki kare kapak; birden fazla fotoğrafta "+N" rozeti.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final imgs = item.imageUrls;
    final logo = (item.leagueLogoUrl ?? '').trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 68,
        height: 68,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imgs.isNotEmpty)
              WebSafeImage(url: imgs.first, fit: BoxFit.cover)
            else
              Container(
                color: _bgDark,
                padding: const EdgeInsets.all(10),
                child: logo.isEmpty
                    ? Icon(Icons.article_outlined, color: _accent(), size: 28)
                    : WebSafeImage(url: logo, fit: BoxFit.contain),
              ),
            if (imgs.length > 1)
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '+${imgs.length - 1}',
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
  }
}

/// Açık haberdeki fotoğraflar: parmakla kaydırılır, altta nokta göstergesi;
/// dokununca tam ekran.
class _Carousel extends StatefulWidget {
  const _Carousel({required this.urls, required this.onOpen});

  final List<String> urls;
  final ValueChanged<int> onOpen;

  @override
  State<_Carousel> createState() => _CarouselState();
}

class _CarouselState extends State<_Carousel> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: PageView.builder(
            itemCount: urls.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => GestureDetector(
              onTap: () => widget.onOpen(i),
              child: WebSafeImage(url: urls[i], fit: BoxFit.cover),
            ),
          ),
        ),
        if (urls.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < urls.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _page ? _accent() : Colors.white24,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Tam ekran fotoğraf galerisi (kaydır, yakınlaştır, dokununca kapan).
class _GalleryViewer extends StatefulWidget {
  const _GalleryViewer({required this.urls, required this.initial});

  final List<String> urls;
  final int initial;

  @override
  State<_GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<_GalleryViewer> {
  late final _controller = PageController(initialPage: widget.initial);
  late int _page = widget.initial;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: widget.urls.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (context, i) => GestureDetector(
            onTap: () => Navigator.pop(context),
            child: InteractiveViewer(
              maxScale: 4,
              child: Center(
                child: WebSafeImage(url: widget.urls[i], fit: BoxFit.contain),
              ),
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          right: 8,
          child: IconButton(
            tooltip: 'Kapat',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ),
        if (widget.urls.length > 1)
          Positioned(
            bottom: MediaQuery.paddingOf(context).bottom + 16,
            left: 0,
            right: 0,
            child: Text(
              '${_page + 1} / ${widget.urls.length}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
                fontSize: 14,
              ),
            ),
          ),
      ],
    );
  }
}

String _timeAgo(DateTime? at) {
  if (at == null) return '';
  final local = at.toLocal();
  final diff = DateTime.now().difference(local);
  if (diff.inMinutes < 1) return 'az önce';
  if (diff.inMinutes < 60) return '${diff.inMinutes} dakika önce';
  if (diff.inHours < 24) return '${diff.inHours} saat önce';
  if (diff.inDays < 7) return '${diff.inDays} gün önce';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year}';
}
