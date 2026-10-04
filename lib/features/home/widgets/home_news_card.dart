import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/active_tournament.dart';
import '../../../core/services/league_scope.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../tournament/models/league_extras.dart';

/// Ana sayfanın üstündeki "Son Dakika" haber kartı: son günlerin haberleri
/// sırayla döner; dokununca Haberler sekmesi açılır. Yeni haber yoksa hiç
/// görünmez.
class HomeNewsCard extends StatefulWidget {
  const HomeNewsCard({super.key, required this.onOpenNews});

  final VoidCallback onOpenNews;

  @override
  State<HomeNewsCard> createState() => _HomeNewsCardState();
}

class _HomeNewsCardState extends State<HomeNewsCard> {
  /// Kartta gösterilecek en fazla haber ve ne kadar geriye bakılacağı.
  static const _maxItems = 3;
  static const _window = Duration(days: 7);

  static const _red = Color(0xFFE5383B);

  // Servis aynı kullanıcı için tek akış döndürür (Haberler ekranıyla ortak).
  late final Stream<List<NewsItem>> _stream = ServiceLocator.leagueService
      .watchNewsFeed();

  final _page = PageController();
  Timer? _timer;
  int _index = 0;
  int _count = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  /// Birden fazla haber varsa kart birkaç saniyede bir sonrakine geçer.
  void _syncTimer(int count) {
    if (count == _count) return;
    _count = count;
    _timer?.cancel();
    if (count < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_page.hasClients) return;
      final next = (_index + 1) % _count;
      _page.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  static String _ago(DateTime? t) {
    if (t == null) return '';
    final d = DateTime.now().difference(t.toLocal());
    if (d.inMinutes < 1) return 'Az önce';
    if (d.inMinutes < 60) return '${d.inMinutes} dk önce';
    if (d.inHours < 24) return '${d.inHours} saat önce';
    if (d.inDays == 1) return 'Dün';
    return '${d.inDays} gün önce';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<NewsItem>>(
      stream: _stream,
      builder: (context, snap) {
        final since = DateTime.now().subtract(_window);
        final items = (snap.data ?? const <NewsItem>[])
            .where(
              (n) =>
                  LeagueScope.allows(n.tournamentId) &&
                  n.createdAt != null &&
                  n.createdAt!.isAfter(since),
            )
            .take(_maxItems)
            .toList();
        _syncTimer(items.length);
        if (items.isEmpty) return const SizedBox.shrink();
        if (_index >= items.length) _index = 0;

        final theme = ActiveTournament.theme.value;
        final primary = theme?.primary ?? const Color(0xFF0B2A6B);
        final accent = theme?.secondary ?? const Color(0xFFD4A017);

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onOpenNews,
              borderRadius: BorderRadius.circular(18),
              child: Ink(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      primary.withValues(alpha: 0.95),
                      const Color(0xFF1E293B).withValues(alpha: 0.95),
                    ],
                  ),
                  border: Border.all(color: accent.withValues(alpha: 0.4)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          height: 22,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: _red,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bolt_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                              SizedBox(width: 2),
                              Text(
                                'SON DAKİKA',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _ago(items[_index].createdAt),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Tümü',
                          style: TextStyle(
                            color: accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: accent,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 68,
                      child: PageView.builder(
                        controller: _page,
                        itemCount: items.length,
                        onPageChanged: (i) => setState(() => _index = i),
                        itemBuilder: (context, i) => _NewsRow(item: items[i]),
                      ),
                    ),
                    if (items.length > 1) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < items.length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              margin: const EdgeInsets.symmetric(
                                horizontal: 2.5,
                              ),
                              width: i == _index ? 16 : 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: i == _index ? accent : Colors.white30,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NewsRow extends StatelessWidget {
  const _NewsRow({required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    // Haber fotoğrafı yoksa turnuvanın logosu.
    final photo = (item.imageUrl ?? '').isNotEmpty
        ? item.imageUrl!
        : (item.leagueLogoUrl ?? '');
    final source = [
      if (item.leagueName.isNotEmpty) item.leagueName,
      if (item.regionName.isNotEmpty) item.regionName,
    ].join(' · ');

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 68,
            height: 68,
            color: Colors.white.withValues(alpha: 0.08),
            child: photo.isEmpty
                ? const Icon(Icons.newspaper_rounded, color: Colors.white38)
                : WebSafeImage(
                    url: photo,
                    width: 68,
                    height: 68,
                    fit: (item.imageUrl ?? '').isNotEmpty
                        ? BoxFit.cover
                        : BoxFit.contain,
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.content.trim().replaceAll(RegExp(r'\s+'), ' '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              if (source.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
