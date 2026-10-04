import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/app_session.dart';
import '../../../core/services/app_settings.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/master_class_app_bar.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../tournament/models/league.dart';
import '../../tournament/models/league_extras.dart';
import '../../tournament/services/interfaces/i_league_service.dart';

const _bgDark = Color(0xFF0F172A);
const _card = Color(0xFF1E293B);
const _accent = Color(0xFF10B981);
const _muted = Color(0xFF94A3B8);
const _heart = Color(0xFFF87171);

/// Menü → Haberler: turnuvaların yayındaki haberleri, en yeni önce.
/// Beğeni yalnızca giriş yapmış kullanıcıya açıktır; misafir sayıyı görür.
class NewsFeedScreen extends StatefulWidget {
  const NewsFeedScreen({super.key});

  @override
  State<NewsFeedScreen> createState() => _NewsFeedScreenState();
}

class _NewsFeedScreenState extends State<NewsFeedScreen> {
  final ILeagueService _leagueService = ServiceLocator.leagueService;
  late final Stream<List<League>> _leaguesStream = _leagueService
      .watchLeagues();

  String? _leagueId; // null = tümü
  final Set<String> _expanded = {};

  /// Sunucu yanıtı gelene kadar kullanıcının son tercihi (iyimser güncelleme).
  final Map<String, bool> _likeOverride = {};
  final Set<String> _likeBusy = {};

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
    final image = (n.imageUrl ?? '').isEmpty ? '' : '\n\n${n.imageUrl}';
    await SharePlus.instance.share(
      ShareParams(text: '$title${n.content}$image'),
    );
  }

  void _openPhoto(String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: InteractiveViewer(
          maxScale: 4,
          child: Center(
            child: WebSafeImage(url: url, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.of(context).value;
    final loggedIn = session.user != null;

    return Scaffold(
      backgroundColor: _bgDark,
      extendBodyBehindAppBar: true,
      appBar: const MasterClassAppBar(title: 'Haberler'),
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.15,
              child: Image.asset(
                'assets/images/background_ball.jpg',
                fit: BoxFit.cover,
              ),
            ),
          ),
          SafeArea(
            child: StreamBuilder<List<League>>(
              stream: _leaguesStream,
              builder: (context, leaguesSnap) {
                final leagues = (leaguesSnap.data ?? const <League>[])
                    .where(
                      (l) =>
                          !AppSettings.privateLeaguesEnabled.value ||
                          !l.isPrivate ||
                          session.canManageLeague(l.id),
                    )
                    .toList();
                if (_leagueId != null &&
                    leaguesSnap.hasData &&
                    leagues.every((l) => l.id != _leagueId)) {
                  _leagueId = null;
                }
                return Column(
                  children: [
                    _LeagueChips(
                      leagues: leagues,
                      selectedId: _leagueId,
                      onSelected: (id) => setState(() => _leagueId = id),
                    ),
                    Expanded(child: _feed(session, loggedIn)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _feed(AppSessionState session, bool loggedIn) {
    return StreamBuilder<List<NewsItem>>(
      // Servis aynı kullanıcı + filtre için tek akış döndürür.
      stream: _leagueService.watchNewsFeed(leagueId: _leagueId),
      builder: (context, snap) {
        if (snap.hasError && !snap.hasData) {
          return const _Message('Haberler yüklenemedi.');
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: _accent));
        }
        // Gizli turnuvaların haberleri yalnızca görme yetkisi olana gelir
        // (veritabanı kuralı).
        final items = snap.data!.toList();

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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 16),
          itemBuilder: (context, i) {
            final n = items[i];
            final liked = _likeOverride[n.id] ?? n.likedByMe;
            final count =
                (n.likeCount - (n.likedByMe ? 1 : 0) + (liked ? 1 : 0)).clamp(
                  0,
                  1 << 31,
                );
            return _NewsCard(
              item: n,
              loggedIn: loggedIn,
              liked: liked,
              likeCount: count,
              expanded: _expanded.contains(n.id),
              onToggleExpand: () => setState(() {
                if (!_expanded.remove(n.id)) _expanded.add(n.id);
              }),
              onToggleLike: () => _toggleLike(n, liked),
              onShare: () => _share(n),
              onOpenPhoto: _openPhoto,
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

class _LeagueChips extends StatelessWidget {
  const _LeagueChips({
    required this.leagues,
    required this.selectedId,
    required this.onSelected,
  });

  final List<League> leagues;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final entries = <MapEntry<String?, String>>[
      const MapEntry(null, 'Tümü'),
      for (final l in leagues) MapEntry(l.id, l.name),
    ];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
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
                color: active ? _accent : _card.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: active
                      ? _accent
                      : Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Text(
                e.value,
                style: TextStyle(
                  color: active
                      ? const Color(0xFF04241A)
                      : const Color(0xFFCBD5E1),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({
    required this.item,
    required this.loggedIn,
    required this.liked,
    required this.likeCount,
    required this.expanded,
    required this.onToggleExpand,
    required this.onToggleLike,
    required this.onShare,
    required this.onOpenPhoto,
  });

  final NewsItem item;
  final bool loggedIn;
  final bool liked;
  final int likeCount;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onToggleLike;
  final VoidCallback onShare;
  final ValueChanged<String> onOpenPhoto;

  @override
  Widget build(BuildContext context) {
    final img = (item.imageUrl ?? '').trim();
    final hasImg = img.isNotEmpty;
    final caption = _Caption(
      text: item.content,
      large: !hasImg,
      expanded: expanded,
      onToggle: onToggleExpand,
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _card.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          if (hasImg)
            GestureDetector(
              onTap: () => onOpenPhoto(img),
              child: _NewsPhoto(url: img),
            ),
          if (!hasImg)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
              child: caption,
            ),
          _actions(),
          if (hasImg)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
              child: caption,
            )
          else
            const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _header() {
    final logo = (item.leagueLogoUrl ?? '').trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _bgDark,
              border: Border.all(color: _accent.withValues(alpha: 0.55)),
            ),
            clipBehavior: Clip.antiAlias,
            child: logo.isEmpty
                ? const Icon(
                    Icons.emoji_events_outlined,
                    color: _accent,
                    size: 22,
                  )
                : WebSafeImage(
                    url: logo,
                    width: 40,
                    height: 40,
                    fit: BoxFit.contain,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    item.leagueName.isEmpty ? 'Turnuva' : item.leagueName,
                    if (item.regionName.isNotEmpty) item.regionName,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _timeAgo(item.createdAt),
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
      child: Row(
        children: [
          if (loggedIn) ...[
            IconButton(
              tooltip: liked ? 'Beğeniyi geri al' : 'Beğen',
              onPressed: onToggleLike,
              icon: Icon(
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: liked ? _heart : Colors.white,
                size: 27,
              ),
            ),
            Text(
              '$likeCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Text(
                '$likeCount beğeni',
                style: const TextStyle(
                  color: _muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const Spacer(),
          IconButton(
            tooltip: 'Paylaş',
            onPressed: onShare,
            icon: const Icon(
              Icons.send_outlined,
              color: Colors.white,
              size: 23,
            ),
          ),
        ],
      ),
    );
  }
}

/// Uzun metni 3 satırda keser, "devamını gör" ile açar.
class _Caption extends StatelessWidget {
  const _Caption({
    required this.text,
    required this.large,
    required this.expanded,
    required this.onToggle,
  });

  final String text;
  final bool large;
  final bool expanded;
  final VoidCallback onToggle;

  static const _maxLines = 3;

  @override
  Widget build(BuildContext context) {
    final style = large
        ? const TextStyle(
            color: Colors.white,
            fontSize: 16,
            height: 1.5,
            fontWeight: FontWeight.w600,
          )
        : const TextStyle(color: Color(0xFFE2E8F0), fontSize: 14, height: 1.5);

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: _maxLines,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: style,
              maxLines: expanded ? null : _maxLines,
              overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            if (overflows)
              InkWell(
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    expanded ? 'daha az' : 'devamını gör',
                    style: const TextStyle(
                      color: _accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Fotoğrafı kendi oranında gösterir; en dik 4:5, en yatay 1.91:1 (Instagram
/// ile aynı sınırlar). Web'de resim HTML ile çizildiği için oran ölçülemez;
/// orada 4:3 kullanılır.
class _NewsPhoto extends StatefulWidget {
  const _NewsPhoto({required this.url});

  final String url;

  @override
  State<_NewsPhoto> createState() => _NewsPhotoState();
}

class _NewsPhotoState extends State<_NewsPhoto> {
  static final Map<String, double> _ratioCache = {};
  double? _ratio;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _NewsPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _resolve();
  }

  void _resolve() {
    _detach();
    _ratio = _ratioCache[widget.url];
    if (_ratio != null || kIsWeb) return;
    final stream = NetworkImage(widget.url).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) {
      final w = info.image.width.toDouble();
      final h = info.image.height.toDouble();
      if (h > 0) {
        final r = w / h;
        _ratioCache[widget.url] = r;
        if (mounted) setState(() => _ratio = r);
      }
      _detach();
    }, onError: (_, _) => _detach());
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  void _detach() {
    final l = _listener;
    if (l != null) _stream?.removeListener(l);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Dikey fotoğraflar kare alana kırpılır (ekranı kaplamasın); yatay olanlar
    // 1.91:1'e kadar kendi oranında gösterilir. Tamamı dokununca açılır.
    final ratio = (_ratio ?? 4 / 3).clamp(1.0, 1.91);
    return AspectRatio(
      aspectRatio: ratio,
      child: WebSafeImage(url: widget.url, fit: BoxFit.cover),
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
