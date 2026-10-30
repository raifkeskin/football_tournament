import 'package:flutter/material.dart';

import '../../../core/services/league_scope.dart';
import '../../../core/services/service_locator.dart';
import '../../match/screens/live_draw_screen.dart';
import '../../news/news_article.dart';
import '../../news/screens/news_screens.dart';
import '../../tournament/models/league_extras.dart';
import '../home_warmup.dart';
import 'home_dashboard.dart';

/// Ana sayfadaki haberler (Kart Akışı): "HABERLER · Tümü ›" başlığı ve
/// yana kaydırılan büyük fotoğraflı kartlar. Karta dokununca haber detayı,
/// "Tümü"ye dokununca Haberler ekranı açılır. Haber yoksa görünmez.
class HomeNewsStrip extends StatefulWidget {
  const HomeNewsStrip({super.key, required this.leagueId, this.regionId});

  final String leagueId;
  final String? regionId;

  @override
  State<HomeNewsStrip> createState() => _HomeNewsStripState();
}

class _HomeNewsStripState extends State<HomeNewsStrip> {
  static const _maxItems = 6;

  // Servis aynı kullanıcı için tek akış döndürür (eski kartla ortak).
  late final Stream<List<NewsItem>> _stream = ServiceLocator.leagueService
      .watchNewsFeed();

  final _page = PageController(viewportFraction: 0.86);
  int _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<NewsItem>>(
      stream: _stream,
      initialData: HomeWarmup.news,
      builder: (context, snap) {
        final all = (snap.data ?? const <NewsItem>[])
            .where(
              (n) =>
                  LeagueScope.allows(n.tournamentId) &&
                  n.tournamentId == widget.leagueId &&
                  (widget.regionId == null ||
                      n.regionId == null ||
                      n.regionId == widget.regionId),
            )
            .take(_maxItems + 1)
            .toList();
        // Canlı kura kendi kartıyla üstte.
        final draw = all.where((n) => n.liveDrawId != null).firstOrNull;
        final items = all
            .where((n) => n.liveDrawId == null)
            .take(_maxItems)
            .toList();
        if (items.isEmpty && draw == null) return const SizedBox.shrink();
        if (_index >= items.length) _index = 0;
        final accent = DashColors.accent();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (draw != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: LiveDrawNewsCard(
                  key: ValueKey(draw.liveDrawId),
                  drawId: draw.liveDrawId!,
                  content: draw.content,
                ),
              ),
            if (items.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 18, 0, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'HABERLER',
                        style: TextStyle(
                          fontFamily: 'Barlow',
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: DashColors.muted,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => openNewsList(
                        context,
                        leagueId: widget.leagueId,
                        regionId: widget.regionId,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Text(
                          'Tümü ›',
                          style: TextStyle(
                            fontFamily: 'Barlow',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 250,
                child: PageView.builder(
                  controller: _page,
                  padEnds: false,
                  itemCount: items.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _StripCard(item: items[i]),
                  ),
                ),
              ),
              if (items.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < items.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 2.5),
                          width: i == _index ? 16 : 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: i == _index ? accent : Colors.white30,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _StripCard extends StatelessWidget {
  const _StripCard({required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final article = NewsArticle.of(item);
    final sub = [
      if (article?.home != null && article?.hs != null) article!.deck,
      newsAgo(item.createdAt),
    ].join(' · ');
    return Material(
      color: const Color(0xFF0B1220),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: InkWell(
        onTap: () => openNewsDetail(context, item),
        child: Stack(
          fit: StackFit.expand,
          children: [
            NewsVisual(item: item),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.35, 0.72],
                  colors: [Color(0x00050912), Color(0xEB050912)],
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NewsTag(item.tag),
                  const SizedBox(height: 6),
                  Text(
                    NewsArticle.headlineOf(item).toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'BarlowCondensed',
                      fontWeight: FontWeight.w800,
                      fontSize: 21,
                      height: 1.02,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
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
    );
  }
}
