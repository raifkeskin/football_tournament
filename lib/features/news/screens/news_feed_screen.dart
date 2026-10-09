import 'package:flutter/material.dart';
import '../../match/screens/live_draw_screen.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/active_tournament.dart';
import '../../../core/services/app_session.dart';
import '../../../core/services/league_scope.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../tournament/models/league_extras.dart';
import '../../tournament/services/interfaces/i_league_service.dart';

const _bgDark = Color(0xFF0F172A);
const _card = Color(0xFF1E293B);
const _muted = Color(0xFF94A3B8);
const _heart = Color(0xFFF87171);

Color _accent() =>
    ActiveTournament.theme.value?.secondary ?? const Color(0xFF10B981);

/// Bir sezonun yayındaki haberleri, en yeni önce: tüm turnuvaya ait olanlar
/// ve [regionId] verilirse o bölgeninkiler. Başlık çubuğu yok; Turnuva
/// Sayfası'nın Haberler sekmesinde gösterilir. Haberler kompakt listelenir,
/// dokununca yerinde açılır (aynı anda tek haber açık).
class NewsView extends StatefulWidget {
  const NewsView({super.key, required this.seasonId, this.regionId});

  final String seasonId;
  final String? regionId;

  /// Açılınca açık gösterilecek haber (ör. bildirimden gelinen).
  static final focusNewsId = ValueNotifier<String?>(null);

  @override
  State<NewsView> createState() => _NewsViewState();
}

class _NewsViewState extends State<NewsView> {
  final ILeagueService _leagueService = ServiceLocator.leagueService;

  String? _openId;
  final Map<String, GlobalKey> _keys = {};

  /// Sunucu yanıtı gelene kadar kullanıcının son tercihi (iyimser güncelleme).
  final Map<String, bool> _likeOverride = {};
  final Set<String> _likeBusy = {};

  @override
  void initState() {
    super.initState();
    ActiveTournament.theme.addListener(_onChanged);
    NewsView.focusNewsId.addListener(_onFocus);
    // Sekme ilk kez kurulurken bekleyen bir haber varsa.
    if (NewsView.focusNewsId.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onFocus());
    }
  }

  @override
  void dispose() {
    ActiveTournament.theme.removeListener(_onChanged);
    NewsView.focusNewsId.removeListener(_onFocus);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ---- Etkileşim ------------------------------------------------------

  void _onFocus() {
    final id = NewsView.focusNewsId.value;
    if (id == null || !mounted) return;
    setState(() => _openId = id);
    NewsView.focusNewsId.value = null;
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
    return _feed(AppSession.of(context).value, widget.regionId);
  }

  Widget _feed(AppSessionState session, String? regionId) {
    final loggedIn = session.user != null;
    return StreamBuilder<List<NewsItem>>(
      // Servis aynı kullanıcı + sezon için tek akış döndürür.
      stream: _leagueService.watchNewsFeed(seasonId: widget.seasonId),
      builder: (context, snap) {
        if (snap.hasError && !snap.hasData) {
          return const _Message('Haberler yüklenemedi.');
        }
        if (!snap.hasData) {
          return Center(child: CircularProgressIndicator(color: _accent()));
        }
        // Tüm turnuvanın ve (verildiyse) grubun bölgesinin haberleri.
        final items = snap.data!
            .where(
              (n) =>
                  LeagueScope.allows(n.tournamentId) &&
                  (regionId == null ||
                      n.regionId == null ||
                      n.regionId == regionId),
            )
            .toList();

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
