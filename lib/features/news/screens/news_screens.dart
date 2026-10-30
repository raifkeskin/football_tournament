import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/utils/string_utils.dart';
import '../../../core/services/active_tournament.dart';
import '../../../core/services/app_session.dart';
import '../../../core/services/instagram_share.dart';
import '../../../core/services/league_scope.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/app_name_band.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../tournament/models/league_extras.dart';
import '../news_article.dart';
import '../widgets/result_news_cards.dart';
import 'news_feed_screen.dart';

const _bg = Color(0xFF0F172A);
const _card = Color(0xFF1E293B);
const _card2 = Color(0xFF162033);
const _muted = Color(0xFF94A3B8);
const _soft = Color(0xFFE2E8F0);
const _heart = Color(0xFFF87171);

// Gazete küpürü.
const _paper = Color(0xFFEFE6D1);
const _paper2 = Color(0xFFE6DBC2);
const _ink = Color(0xFF1D1A16);
const _ink2 = Color(0xFF5A5246);
const _kickRed = Color(0xFF8A1C1C);
const _amber = Color(0xFFFBBF24);

/// "14:05"
String hhmm(DateTime t) {
  final l = t.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

Color _accent() =>
    ActiveTournament.theme.value?.secondary ?? const Color(0xFF10B981);

TextStyle _cond(double size, {Color color = Colors.white}) => TextStyle(
  fontFamily: 'BarlowCondensed',
  fontSize: size,
  height: 1.05,
  color: color,
  fontWeight: FontWeight.w800,
);

/// "4 gün önce" gibi kısa zaman.
String newsAgo(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t.toLocal());
  if (d.inMinutes < 1) return 'Az önce';
  if (d.inMinutes < 60) return '${d.inMinutes} dk önce';
  if (d.inHours < 24) return '${d.inHours} saat önce';
  if (d.inDays == 1) return 'Dün';
  return '${d.inDays} gün önce';
}

void openNewsDetail(BuildContext context, NewsItem item) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'NewsDetailScreen'),
      builder: (_) => NewsDetailScreen(item: item),
    ),
  );
}

void openNewsList(
  BuildContext context, {
  required String leagueId,
  String? regionId,
  bool pending = false,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'NewsListScreen'),
      builder: (_) => NewsListScreen(
        leagueId: leagueId,
        regionId: regionId,
        pending: pending,
      ),
    ),
  );
}

/// Dolu küçük etiket ("MAÇ SONUCU").
class NewsTag extends StatelessWidget {
  const NewsTag(this.text, {super.key, this.small = false});

  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final accent = _accent();
    return Container(
      padding: EdgeInsets.fromLTRB(small ? 6 : 7, 3, small ? 6 : 7, 2),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: _cond(
          small ? 10 : 11.5,
          color: accent.computeLuminance() > 0.35
              ? const Color(0xFF04241A)
              : Colors.white,
        ).copyWith(letterSpacing: 1),
      ),
    );
  }
}

/// Haberin görseli: fotoğraf; yoksa maç sonucu / maç gününde takım renkli
/// zemin ve armalar (skor ya da saatle); o da yoksa turnuva logosu.
class NewsVisual extends StatelessWidget {
  const NewsVisual({super.key, required this.item, this.compact = false});

  final NewsItem item;

  /// Küçük kapak (listede kare).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (item.imageUrls.isNotEmpty) {
      return WebSafeImage(url: item.imageUrls.first, fit: BoxFit.cover);
    }
    final a = NewsArticle.of(item);
    final d = item.autoData;
    if (a?.home != null && a?.away != null) {
      final home = a!.home!, away = a.away!;
      Widget crest(ArticleTeam t, double s) => t.logo.isEmpty
          ? Icon(Icons.shield_rounded, size: s * 0.8, color: _soft)
          : WebSafeImage(url: t.logo, width: s, height: s, fit: BoxFit.contain);
      final center = a.hs != null
          ? '${a.hs}–${a.as}'
          : (d?['time'] ?? '').toString();
      if (compact) {
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [home.band, away.band]),
          ),
          child: Center(
            child: crest(a.hs != null && a.as! > a.hs! ? away : home, 38),
          ),
        );
      }
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [home.band, const Color(0xFF0B1220), away.band],
            stops: const [0, 0.5, 1],
          ),
        ),
        child: Align(
          alignment: const Alignment(0, -0.35),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              crest(home, 64),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(center, style: _cond(44)),
              ),
              crest(away, 64),
            ],
          ),
        ),
      );
    }
    if (item.isWeekResults && d != null && !compact) {
      // Haftanın bütün maçları; sığmazsa satırlar birlikte küçülür.
      final matches = [
        for (final m in (d['matches'] as List? ?? const []))
          if (m is Map) m,
      ];
      final dense = matches.length > 5;
      final week = item.week ?? (d['week'] as num?)?.toInt();
      final leagueLogo = (item.leagueLogoUrl ?? '').trim();
      final title = [
        if (item.leagueName.isNotEmpty) item.leagueName.trUpper,
        if (week != null) '$week. HAFTA',
      ].join(' · ');
      return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 0.95,
            colors: [Color(0xFF172554), Color(0xFF0B1220)],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _LmPattern(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 70),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (leagueLogo.isNotEmpty) ...[
                        WebSafeImage(
                          url: leagueLogo,
                          width: 24,
                          height: 24,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _cond(13).copyWith(letterSpacing: 0.6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) => Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SizedBox(
                            width: c.maxWidth,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final m in matches)
                                  _WeekLine(m, dense: dense),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final logo = (item.leagueLogoUrl ?? '').trim();
    return ColoredBox(
      color: const Color(0xFF0B1220),
      child: Align(
        alignment: compact ? Alignment.center : const Alignment(0, -0.4),
        child: logo.isEmpty
            ? Icon(
                Icons.newspaper_rounded,
                size: compact ? 26 : 48,
                color: Colors.white38,
              )
            : WebSafeImage(
                url: logo,
                width: compact ? 38 : 76,
                height: compact ? 38 : 76,
                fit: BoxFit.contain,
              ),
      ),
    );
  }
}

/// Hafta özeti kapağının zemini: soluk, eğik Lig Masası arması deseni.
class _LmPattern extends StatelessWidget {
  const _LmPattern();

  static const _tile = 34.0;
  static const _px = 96;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, c) => OverflowBox(
            minWidth: c.maxWidth * 1.6,
            maxWidth: c.maxWidth * 1.6,
            minHeight: c.maxHeight * 1.6,
            maxHeight: c.maxHeight * 1.6,
            child: Transform.rotate(
              angle: -14 * math.pi / 180,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: ResizeImage(AssetImage(AppLogo.asset), width: _px),
                    repeat: ImageRepeat.repeat,
                    scale: _px / _tile,
                    opacity: 0.10,
                    alignment: Alignment.topLeft,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WeekLine extends StatelessWidget {
  const _WeekLine(this.m, {this.dense = false});

  final Map m;

  /// Çok maçlı haftada satırlar sıkışır.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final home = ArticleTeam(m['home'] as Map?);
    final away = ArticleTeam(m['away'] as Map?);
    Widget crest(ArticleTeam t) => SizedBox(
      width: 22,
      height: 22,
      child: t.logo.isEmpty
          ? const Icon(Icons.shield_rounded, size: 18, color: _soft)
          : WebSafeImage(url: t.logo, fit: BoxFit.contain),
    );
    const name = TextStyle(
      color: Colors.white,
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 2.5 : 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              home.name,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: name,
            ),
          ),
          const SizedBox(width: 6),
          crest(home),
          Container(
            width: 46,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xD905080F),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0x8CC9A44C)),
            ),
            child: Text(
              '${m['hs'] ?? 0}–${m['as'] ?? 0}',
              textAlign: TextAlign.center,
              style: _cond(16),
            ),
          ),
          crest(away),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              away.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: name,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Haberler ekranı
// ---------------------------------------------------------------------------

/// Turnuvanın tüm haberleri: türe göre süzülür; en yenisi büyük kartla,
/// diğerleri haftaya göre gruplu satırlarla. Dokununca detay açılır.
class NewsListScreen extends StatefulWidget {
  const NewsListScreen({
    super.key,
    required this.leagueId,
    this.regionId,
    this.pending = false,
  });

  final String leagueId;
  final String? regionId;

  /// Onay bekleyen otomatik haberler (sorumlular için).
  final bool pending;

  @override
  State<NewsListScreen> createState() => _NewsListScreenState();
}

class _NewsListScreenState extends State<NewsListScreen> {
  late final Stream<List<NewsItem>> _stream = ServiceLocator.leagueService
      .watchNewsFeed(leagueId: widget.leagueId, pending: widget.pending);

  @override
  Widget build(BuildContext context) {
    final accent = _accent();
    // Üst bantta turnuva adı, altında küçük puntoyla "Haberler".
    return BandBackPage(
      theme: ActiveTournament.theme.value,
      subtitle: widget.pending ? 'Onay Bekleyen Haberler' : 'Haberler',
      child: Scaffold(
        backgroundColor: _bg,
        body: StreamBuilder<List<NewsItem>>(
          stream: _stream,
          builder: (context, snap) {
            if (snap.hasError && !snap.hasData) {
              return const _Empty('Haberler yüklenemedi.');
            }
            if (!snap.hasData) {
              return Center(child: CircularProgressIndicator(color: accent));
            }
            final all = snap.data!
                .where(
                  (n) =>
                      n.liveDrawId == null &&
                      LeagueScope.allows(n.tournamentId) &&
                      n.tournamentId == widget.leagueId &&
                      (widget.regionId == null ||
                          n.regionId == null ||
                          n.regionId == widget.regionId),
                )
                .toList();
            final items = all;
            return CustomScrollView(
              slivers: [
                if (items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _Empty(
                      widget.pending
                          ? 'Onay bekleyen haber yok.'
                          : 'Henüz haber yok.',
                    ),
                  )
                else if (widget.pending) ...[
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                  SliverList.list(
                    children: [for (final n in items) _Row(item: n)],
                  ),
                ] else ...[
                  SliverToBoxAdapter(child: _Featured(item: items.first)),
                  SliverList.list(children: _rows(items.skip(1).toList())),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// Satırlar; hafta (yoksa gün) değişince küçük başlık.
  List<Widget> _rows(List<NewsItem> items) {
    const months = [
      'OCAK',
      'ŞUBAT',
      'MART',
      'NİSAN',
      'MAYIS',
      'HAZİRAN',
      'TEMMUZ',
      'AĞUSTOS',
      'EYLÜL',
      'EKİM',
      'KASIM',
      'ARALIK',
    ];
    String group(NewsItem n) {
      final w = n.week ?? (n.autoData?['week'] as num?)?.toInt();
      if (w != null) return '$w. HAFTA';
      final t = n.createdAt?.toLocal();
      return t == null ? '' : '${t.day} ${months[t.month - 1]}';
    }

    final out = <Widget>[];
    String? last;
    for (final n in items) {
      final g = group(n);
      if (g != last && g.isNotEmpty) {
        out.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
            child: Text(
              g,
              style: _cond(13, color: _muted).copyWith(letterSpacing: 1.5),
            ),
          ),
        );
        last = g;
      }
      out.add(_Row(item: n));
    }
    return out;
  }
}

class _Featured extends StatelessWidget {
  const _Featured({required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (item.week != null) '${item.week}. Hafta',
      newsAgo(item.createdAt),
      if (item.regionName.isNotEmpty) item.regionName,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Material(
        color: _card,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: InkWell(
          onTap: () => openNewsDetail(context, item),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 170, child: NewsVisual(item: item)),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NewsTag(item.tag),
                    const SizedBox(height: 6),
                    Text(
                      NewsArticle.headlineOf(item).trUpper,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: _cond(22).copyWith(letterSpacing: 0.3),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      meta,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      child: Material(
        color: _card2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => openNewsDetail(context, item),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox(
                    width: 62,
                    height: 62,
                    child: NewsVisual(item: item, compact: true),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      NewsTag(item.tag, small: true),
                      const SizedBox(height: 4),
                      Text(
                        NewsArticle.headlineOf(item).trUpper,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _cond(16.5).copyWith(letterSpacing: 0.2),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.isPending
                            ? 'Onay bekliyor · saat ${hhmm(item.pendingUntil!)} olunca yayınlanır'
                            : newsAgo(item.createdAt),
                        style: TextStyle(
                          color: item.isPending ? _amber : _muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
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

// ---------------------------------------------------------------------------
// Haber detayı
// ---------------------------------------------------------------------------

/// Haberin uzun hâli: üstte fotoğraf (ya da takım renkli zemin), altında
/// bantla yapıştırılmış gazete küpürü; altta Maç Detayı, beğen, paylaş.
class NewsDetailScreen extends StatefulWidget {
  const NewsDetailScreen({super.key, required this.item});

  final NewsItem item;

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  late bool _liked = widget.item.likedByMe;
  late int _count = widget.item.likeCount;
  bool _busy = false;
  int _page = 0;

  /// Bu ekranda kaydedilen manşet ve metin ('' = otomatiğe dönüldü).
  String? _headline;
  String? _article;

  /// Instagram yüklü mü (Android / iOS).
  late final Future<bool> _ig = InstagramShare.isAvailable();

  /// Onay bekleyen haber bu ekranda yayınlandı mı.
  bool _published = false;
  bool _publishing = false;

  bool get _pending => widget.item.isPending && !_published;

  Future<void> _publish() async {
    if (_publishing) return;
    setState(() => _publishing = true);
    try {
      await ServiceLocator.leagueService.setNewsPublished(
        newsId: widget.item.id,
        isPublished: true,
      );
      if (!mounted) return;
      setState(() => _published = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Haber yayınlandı.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Yayınlanamadı: $e')));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _editHeadline(NewsArticle current) async {
    final n = widget.item;
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _HeadlineSheet(
        current: current.headline,
        currentBody: current.paragraphs.join('\n\n'),
        autoBody: NewsArticle.autoBody(n),
        suggestions: NewsArticle.suggestions(n),
        custom:
            (_headline ?? n.headline ?? '').isNotEmpty ||
            (_article ?? n.article ?? '').isNotEmpty,
      ),
    );
    if (result == null || !mounted) return;
    final (headline, article) = result;
    try {
      await ServiceLocator.leagueService.setNewsHeadline(
        newsId: n.id,
        headline: headline,
        article: article,
      );
      if (!mounted) return;
      setState(() {
        _headline = headline.trim();
        _article = article.trim();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Haber kaydedildi.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Haber kaydedilemedi: $e')));
    }
  }

  Future<void> _toggleLike() async {
    if (_busy) return;
    final next = !_liked;
    setState(() {
      _busy = true;
      _liked = next;
      _count += next ? 1 : -1;
    });
    try {
      await ServiceLocator.leagueService.setNewsLike(
        newsId: widget.item.id,
        liked: next,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _liked = !next;
        _count += next ? -1 : 1;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Beğeni kaydedilemedi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Haber; bu ekranda kaydedilen manşet / metinle.
  NewsArticle _current(NewsItem n) {
    var article = NewsArticle.of(n)!;
    if (_headline != null) {
      article = article.withHeadline(
        _headline!.isEmpty ? NewsArticle.suggestions(n).first : _headline!,
      );
    }
    if (_article != null) {
      article = article.withBody(
        _article!.isEmpty ? NewsArticle.autoBody(n) : _article!,
      );
    }
    return article;
  }

  String get _matchId {
    final n = widget.item;
    final id = (n.autoData?['match_id'] ?? '').toString();
    return id.isNotEmpty ? id : (n.matchId ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.item;
    final loggedIn = AppSession.of(context).value.user != null;
    final session = AppSession.of(context).value;
    final base = NewsArticle.of(n);
    final article = base == null ? null : _current(n);
    final canEdit =
        base != null &&
        n.autoKind != null &&
        session.canManageRegion(n.tournamentId, n.regionId);
    final top = MediaQuery.paddingOf(context).top;
    return BandBackPage(
      theme: ActiveTournament.theme.value,
      subtitle: 'Haberler',
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            ListView(
              padding: EdgeInsets.zero,
              children: [
                if (article == null) ...[
                  SizedBox(height: top + 56),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    child: _ownCard(n, loggedIn),
                  ),
                ] else ...[
                  _hero(n, top),
                  Transform.translate(
                    offset: const Offset(0, -34),
                    child: _Clipping(
                      item: n,
                      article: article,
                      onEdit: canEdit ? () => _editHeadline(article) : null,
                    ),
                  ),
                ],
                const SizedBox(height: 90),
              ],
            ),
            if (article != null)
              Positioned(left: 0, right: 0, bottom: 0, child: _bar(loggedIn)),
          ],
        ),
      ),
    );
  }

  Widget _hero(NewsItem n, double top) {
    final urls = n.imageUrls;
    return SizedBox(
      height: 250 + top,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (urls.isEmpty)
            NewsVisual(item: n)
          else
            PageView.builder(
              itemCount: urls.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => GestureDetector(
                onTap: () => openNewsGallery(context, urls, i),
                child: WebSafeImage(url: urls[i], fit: BoxFit.cover),
              ),
            ),
          if (urls.length > 1)
            Positioned(
              right: 12,
              top: top + 14,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_page + 1}/${urls.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Küpürle anlatılamayan haberler kendi kartıyla.
  Widget _ownCard(NewsItem n, bool loggedIn) {
    final meta = [
      newsAgo(n.createdAt),
      if (n.regionName.isNotEmpty) n.regionName,
    ].join(' · ');
    void like() => _toggleLike();
    void share() => shareNews(n);
    if (n.isDayPreview) {
      return DayPreviewNewsCard(
        item: n,
        meta: meta,
        loggedIn: loggedIn,
        liked: _liked,
        likeCount: _count,
        onToggleLike: like,
        onShare: share,
      );
    }
    if (n.isWeeklyPick) {
      return WeeklyPickNewsCard(
        item: n,
        meta: meta,
        loggedIn: loggedIn,
        liked: _liked,
        likeCount: _count,
        onToggleLike: like,
        onShare: share,
      );
    }
    // Instagram gönderisi: fotoğraf ve metin.
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (n.imageUrls.isNotEmpty)
            GestureDetector(
              onTap: () => openNewsGallery(context, n.imageUrls, 0),
              child: AspectRatio(
                aspectRatio: 1,
                child: WebSafeImage(url: n.imageUrls.first, fit: BoxFit.cover),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              n.content,
              style: const TextStyle(color: _soft, fontSize: 14, height: 1.5),
            ),
          ),
          _bar(loggedIn, inline: true),
        ],
      ),
    );
  }

  Widget _bar(bool loggedIn, {bool inline = false}) {
    final accent = _accent();
    final n = widget.item;
    // Onay bekleyen haberde sorumluya "YAYINLA"; diğerleri yalnız görür.
    final approve =
        _pending &&
        AppSession.of(
          context,
        ).value.canManageRegion(n.tournamentId, n.regionId);
    final matchId = approve ? '' : _matchId;
    Widget square(Widget icon, String tip, VoidCallback? onTap) => Tooltip(
      message: tip,
      child: Material(
        color: const Color(0xFF0D1729),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              child: Center(child: icon),
            ),
          ),
        ),
      ),
    );
    final row = Row(
      children: [
        if (matchId.isNotEmpty)
          Expanded(
            child: SizedBox(
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: accent.computeLuminance() > 0.35
                      ? const Color(0xFF04241A)
                      : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => openNewsMatch(context, matchId),
                child: Text(
                  'MAÇ DETAYI →',
                  style: TextStyle(
                    fontFamily: 'BarlowCondensed',
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          )
        else if (approve)
          Expanded(
            child: SizedBox(
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _amber,
                  foregroundColor: const Color(0xFF2A1D00),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _publishing ? null : _publish,
                child: const Text(
                  'YAYINLA',
                  style: TextStyle(
                    fontFamily: 'BarlowCondensed',
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          )
        else
          const Spacer(),
        const SizedBox(width: 8),
        square(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: _liked ? _heart : Colors.white,
                size: 22,
              ),
              const SizedBox(width: 6),
              Text(
                '$_count',
                style: const TextStyle(
                  color: _soft,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          loggedIn
              ? (_liked ? 'Beğeniyi geri al' : 'Beğen')
              : 'Beğenmek için giriş yap',
          loggedIn ? _toggleLike : null,
        ),
        // Yayındaki haber Instagram hikâyesi olarak paylaşılır.
        if (!_pending && NewsArticle.of(n) != null)
          FutureBuilder<bool>(
            future: _ig,
            builder: (context, snap) => snap.data != true
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: square(
                      ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (b) => const LinearGradient(
                          colors: [
                            Color(0xFFF58529),
                            Color(0xFFDD2A7B),
                            Color(0xFF8134AF),
                          ],
                        ).createShader(b),
                        child: const Icon(Icons.camera_alt_outlined, size: 22),
                      ),
                      'Instagram hikâyesinde paylaş',
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          settings: const RouteSettings(
                            name: 'NewsStoryScreen',
                          ),
                          builder: (_) => _NewsStoryScreen(
                            item: n,
                            article: _current(n),
                            // Detayda o an görünen fotoğraf seçili gelir.
                            initialPhoto: _page,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        const SizedBox(width: 8),
        square(
          const Icon(Icons.send_outlined, color: Colors.white, size: 21),
          'Paylaş',
          () => shareNews(widget.item),
        ),
      ],
    );
    if (inline) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: row,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_bg.withValues(alpha: 0), _bg.withValues(alpha: 0.96)],
          stops: const [0, 0.35],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 22, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_pending && n.pendingUntil != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Onay bekliyor · Manşeti düzenleyip yayınlayabilirsin. '
                    'Onaylanmazsa saat ${hhmm(n.pendingUntil!)} olunca '
                    'kendiliğinden yayınlanır.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _amber,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              row,
            ],
          ),
        ),
      ),
    );
  }
}

/// Bantla yapıştırılmış, kenarları yırtık gazete küpürü.
class _Clipping extends StatelessWidget {
  const _Clipping({
    required this.item,
    required this.article,
    this.onEdit,
    this.maxParagraphs,
    this.tilt = true,
  });

  final NewsItem item;
  final NewsArticle article;

  /// Instagram hikâyesinde metnin ilk paragrafları.
  final int? maxParagraphs;

  /// Hafif eğik durur (hikâyede düz).
  final bool tilt;

  /// Sorumluya manşeti düzenleme düğmesi.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final a = article;
    final t = item.createdAt?.toLocal();
    final date = t == null
        ? ''
        : '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';
    final byline = [
      'Lig Masası',
      if (item.leagueName.isNotEmpty) item.leagueName,
      if (date.isNotEmpty) date,
    ].join(' · ');
    const body = TextStyle(
      fontFamily: 'OldStandard',
      color: _ink,
      fontSize: 15,
      height: 1.55,
    );
    final paper = ClipPath(
      clipper: _TornClipper(item.id.hashCode),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.4, -0.6),
            radius: 1.3,
            colors: [_paper, _paper2],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              a.kicker,
              style: _cond(12.5, color: _kickRed).copyWith(letterSpacing: 1.6),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    a.headline,
                    style: const TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontWeight: FontWeight.w900,
                      color: _ink,
                      fontSize: 27,
                      height: 1.08,
                    ),
                  ),
                ),
                if (onEdit != null)
                  IconButton(
                    tooltip: 'Haberi düzenle',
                    onPressed: onEdit,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined, color: _ink2),
                  ),
              ],
            ),
            if (a.home != null && a.away != null) ...[
              const SizedBox(height: 12),
              _ScoreBox(
                article: a,
                time: (item.autoData?['time'] ?? '').toString(),
              ),
            ],
            // Maç sonucunda skor kutusu zaten var; skor satırı tekrar yazılmaz.
            if (a.deck.isNotEmpty && a.hs == null) ...[
              const SizedBox(height: 10),
              Text(
                a.deck,
                style: const TextStyle(
                  fontFamily: 'OldStandard',
                  fontStyle: FontStyle.italic,
                  color: _ink2,
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Container(height: 1, color: _ink.withValues(alpha: 0.45)),
            const SizedBox(height: 10),
            for (final p in a.paragraphs.take(
              maxParagraphs ?? a.paragraphs.length,
            ))
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: maxParagraphs == null
                    ? SelectableText(p, style: body)
                    : Text(p, style: body),
              ),
            const SizedBox(height: 4),
            Container(height: 1, color: _ink.withValues(alpha: 0.35)),
            const SizedBox(height: 5),
            Text(
              byline,
              style: const TextStyle(
                fontFamily: 'OldStandard',
                color: _ink2,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
    Widget tape(double angle) => Transform.rotate(
      angle: angle,
      child: Container(
        width: 66,
        height: 20,
        decoration: BoxDecoration(
          color: const Color(0xFFF0E8C8).withValues(alpha: 0.6),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Transform.rotate(
        angle: tilt ? -0.018 : 0,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Color(0x8C000000),
                    blurRadius: 26,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: paper,
            ),
            Positioned(left: 16, top: -6, child: tape(-0.14)),
            Positioned(right: 16, top: -6, child: tape(0.12)),
          ],
        ),
      ),
    );
  }
}

/// Küpürdeki skor kutusu: armalar ve skor (maç gününde saat).
class _ScoreBox extends StatelessWidget {
  const _ScoreBox({required this.article, required this.time});

  final NewsArticle article;
  final String time;

  @override
  Widget build(BuildContext context) {
    final a = article;
    Widget team(ArticleTeam t, {required bool end}) => Expanded(
      child: Row(
        mainAxisAlignment: end
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!end) _crest(t),
          if (!end) const SizedBox(width: 8),
          Flexible(
            child: Text(
              t.name.trUpper,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: end ? TextAlign.right : TextAlign.left,
              style: _cond(14, color: _ink).copyWith(letterSpacing: 0.3),
            ),
          ),
          if (end) const SizedBox(width: 8),
          if (end) _crest(t),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(border: Border.all(color: _ink, width: 1.5)),
      child: Row(
        children: [
          team(a.home!, end: false),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              a.hs != null ? '${a.hs}–${a.as}' : time,
              style: const TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontWeight: FontWeight.w900,
                color: _ink,
                fontSize: 26,
                height: 1,
              ),
            ),
          ),
          team(a.away!, end: true),
        ],
      ),
    );
  }

  Widget _crest(ArticleTeam t) => SizedBox(
    width: 30,
    height: 30,
    child: t.logo.isEmpty
        ? const Icon(Icons.shield_rounded, size: 24, color: _ink2)
        : WebSafeImage(url: t.logo, fit: BoxFit.contain),
  );
}

/// Üst ve alt kenarı yırtık kâğıt gibi kesen kırpıcı (haber kimliğine göre
/// sabit: her açılışta aynı yırtık).
class _TornClipper extends CustomClipper<Path> {
  _TornClipper(this.seed);

  final int seed;

  @override
  Path getClip(Size size) {
    final r = math.Random(seed);
    const steps = 34;
    const depth = 5.0;
    final p = Path()..moveTo(0, r.nextDouble() * depth);
    for (var i = 1; i <= steps; i++) {
      p.lineTo(size.width * i / steps, r.nextDouble() * depth);
    }
    for (var i = steps; i >= 0; i--) {
      p.lineTo(size.width * i / steps, size.height - r.nextDouble() * depth);
    }
    return p..close();
  }

  @override
  bool shouldReclip(covariant _TornClipper old) => old.seed != seed;
}

/// Haberi düzenleme: manşet (hazır önerilerle) ve metin; otomatiğe dönüş.
/// (manşet, metin) döndürür; '' = kurallarla yazılan.
class _HeadlineSheet extends StatefulWidget {
  const _HeadlineSheet({
    required this.current,
    required this.currentBody,
    required this.autoBody,
    required this.suggestions,
    required this.custom,
  });

  final String current;
  final String currentBody;
  final String autoBody;
  final List<String> suggestions;

  /// Manşet ya da metin elle yazılmış mı.
  final bool custom;

  @override
  State<_HeadlineSheet> createState() => _HeadlineSheetState();
}

class _HeadlineSheetState extends State<_HeadlineSheet> {
  late final _ctrl = TextEditingController(text: _plain(widget.current));
  late final _body = TextEditingController(text: _plain(widget.currentBody));

  /// Satır kırılmasın diye eklenen görünmez işaretler alanda görünmez.
  static String _plain(String s) =>
      s.replaceAll('\u2060', '').replaceAll('\u00A0', ' ');

  @override
  void dispose() {
    _ctrl.dispose();
    _body.dispose();
    super.dispose();
  }

  InputDecoration get _field => InputDecoration(
    filled: true,
    fillColor: _bg,
    counterStyle: const TextStyle(color: _muted),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      t,
      style: const TextStyle(
        color: _muted,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final accent = _accent();
    final auto = _plain(
      widget.suggestions.isEmpty ? '' : widget.suggestions.first,
    );
    final autoBody = _plain(widget.autoBody);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'HABERİ DÜZENLE',
                  style: _cond(18).copyWith(letterSpacing: 1),
                ),
                const SizedBox(height: 12),
                _label('MANŞET'),
                TextField(
                  controller: _ctrl,
                  maxLength: 140,
                  maxLines: 3,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: _field,
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in widget.suggestions)
                      ActionChip(
                        label: Text(_plain(s)),
                        labelStyle: const TextStyle(color: _soft, fontSize: 13),
                        backgroundColor: _card2,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                        onPressed: () => setState(() => _ctrl.text = _plain(s)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _label('HABER METNİ · paragraflar arasında boş satır'),
                TextField(
                  controller: _body,
                  maxLength: 4000,
                  minLines: 6,
                  maxLines: 14,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.4,
                  ),
                  decoration: _field,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (widget.custom)
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(('', '')),
                        child: const Text(
                          'Otomatiğe dön',
                          style: TextStyle(color: _muted),
                        ),
                      ),
                    const Spacer(),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: accent),
                      onPressed: () {
                        final t = _ctrl.text.trim();
                        final b = _body.text.trim();
                        // Otomatikle aynıysa elle yazılmış sayılmaz.
                        Navigator.of(
                          context,
                        ).pop((t == auto ? '' : t, b == autoBody ? '' : b));
                      },
                      child: const Text('Kaydet'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Instagram hikâyesi: 9:16 görsel (fotoğraf + gazete küpürü) önizlenir,
/// "Hikâyede paylaş" ile Instagram'ın hikâye ekranı açılır.
class _NewsStoryScreen extends StatefulWidget {
  const _NewsStoryScreen({
    required this.item,
    required this.article,
    this.initialPhoto = 0,
  });

  final NewsItem item;
  final NewsArticle article;
  final int initialPhoto;

  @override
  State<_NewsStoryScreen> createState() => _NewsStoryScreenState();
}

class _NewsStoryScreenState extends State<_NewsStoryScreen> {
  final _shot = GlobalKey();
  bool _busy = false;

  /// Hikâyede kullanılacak fotoğraf (birden fazlaysa seçilir).
  late int _photo = widget.initialPhoto.clamp(
    0,
    widget.item.imageUrls.isEmpty ? 0 : widget.item.imageUrls.length - 1,
  );

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final boundary =
          _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(
        pixelRatio: 1080 / boundary.size.width,
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Görsel oluşturulamadı.');
      final ok = await InstagramShare.share(
        data.buffer.asUint8List(),
        story: true,
      );
      if (!ok) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Instagram açılamadı.')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Instagram\'a aktarılamadı: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.item;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Instagram hikâyesi'),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: FittedBox(
                  child: RepaintBoundary(
                    key: _shot,
                    child: SizedBox(width: 360, height: 640, child: _story(n)),
                  ),
                ),
              ),
            ),
            if (n.imageUrls.length > 1) _photoPicker(n.imageUrls),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFDD2A7B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _busy ? null : _share,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: Text(
                    _busy ? 'Hazırlanıyor…' : 'HİKÂYEDE PAYLAŞ',
                    style: const TextStyle(
                      fontFamily: 'BarlowCondensed',
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Instagram\'da o an açık olan hesaptan paylaşılır.',
                style: TextStyle(color: _muted, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Fotoğraf seçimi: küçük kareler, seçili olan çerçeveli.
  Widget _photoPicker(List<String> urls) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text(
            'FOTOĞRAF SEÇ',
            style: TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ),
        SizedBox(
          height: 60,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final on = i == _photo;
              return GestureDetector(
                onTap: () => setState(() => _photo = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 80,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: on ? const Color(0xFFDD2A7B) : Colors.white24,
                      width: on ? 2.5 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: WebSafeImage(url: urls[i], fit: BoxFit.cover),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _story(NewsItem n) {
    final logo = (n.leagueLogoUrl ?? '').trim();
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1220), Color(0xFF0F172A)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 300,
            child: n.imageUrls.isEmpty
                ? NewsVisual(item: n)
                // Takım fotoğrafı kırpılmaz (kenardaki oyuncular da görünür);
                // boşluğu aynı fotoğrafın bulanık hâli doldurur.
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(
                          sigmaX: 18,
                          sigmaY: 18,
                        ),
                        child: WebSafeImage(
                          url: n.imageUrls[_photo],
                          fit: BoxFit.cover,
                        ),
                      ),
                      ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
                      Align(
                        alignment: Alignment.topCenter,
                        child: WebSafeImage(
                          url: n.imageUrls[_photo],
                          fit: BoxFit.contain,
                        ),
                      ),
                    ],
                  ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 262,
            bottom: 52,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 360,
                child: _Clipping(
                  item: n,
                  article: widget.article,
                  maxParagraphs: 2,
                  tilt: false,
                ),
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 14,
            child: Row(
              children: [
                if (logo.isNotEmpty) ...[
                  WebSafeImage(url: logo, width: 26, height: 26),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    n.leagueName.trUpper,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _cond(14, color: _soft).copyWith(letterSpacing: 0.8),
                  ),
                ),
                Text(
                  'LİG MASASI',
                  style: _cond(
                    14,
                    color: _accent(),
                  ).copyWith(fontStyle: FontStyle.italic, letterSpacing: 0.8),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
