import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/utils/app_activity.dart';
import '../../core/widgets/web_safe_image.dart';
import 'sponsor.dart';

/// Ana sayfada, bandın hemen altında ince beyaz sponsor şeridi. Önce ana
/// sponsorlar, sonra alt sponsorlar sırayla döner; ekranda kalma süreleri
/// turnuva ayarından. Sponsor yoksa hiç çizilmez. Uygulama arka plandayken
/// ya da sekme görünmezken dönüş durur.
class SponsorStrip extends StatefulWidget {
  const SponsorStrip({super.key, required this.leagueId});

  final String leagueId;

  @override
  State<SponsorStrip> createState() => _SponsorStripState();
}

class _SponsorStripState extends State<SponsorStrip> {
  SponsorFeed? _feed;
  int _index = 0;
  Timer? _timer;
  bool _visible = true;

  /// Son sunucu okuması; arka plandan dönüşte eskiyse yeniden okunur.
  DateTime? _fetchedAt;
  static const _staleAfter = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    AppActivity.foreground.addListener(_onForeground);
    SponsorFeed.changes.addListener(_onSponsorsChanged);
    _load();
  }

  void _onForeground() {
    final at = _fetchedAt;
    if (AppActivity.foreground.value &&
        (at == null || DateTime.now().difference(at) > _staleAfter)) {
      _refresh();
    }
    _reschedule();
  }

  /// Sponsor Yönetimi'nde bu turnuva değiştiyse hemen yenilenir.
  void _onSponsorsChanged() {
    if (SponsorFeed.changes.value == widget.leagueId) _refresh();
  }

  Future<void> _refresh() async {
    final id = widget.leagueId;
    try {
      final fresh = await SponsorFeed.fetch(id);
      _fetchedAt = DateTime.now();
      if (mounted && id == widget.leagueId) _apply(fresh);
    } catch (_) {}
  }

  Future<void> _load() async {
    final id = widget.leagueId;
    final cached = await SponsorFeed.cached(id);
    if (!mounted || id != widget.leagueId) return;
    if (cached != null) _apply(cached);
    try {
      final fresh = await SponsorFeed.fetch(id);
      _fetchedAt = DateTime.now();
      if (mounted && id == widget.leagueId) _apply(fresh);
    } catch (_) {}
  }

  void _apply(SponsorFeed feed) {
    setState(() {
      _feed = feed;
      if (_index >= feed.sponsors.length) _index = 0;
    });
    _reschedule();
  }

  @override
  void didUpdateWidget(covariant SponsorStrip old) {
    super.didUpdateWidget(old);
    if (old.leagueId != widget.leagueId) {
      _timer?.cancel();
      _feed = null;
      _index = 0;
      _load();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ana sayfa sekmesi arkadayken (TickerMode kapalı) dönüş durur.
    final v = TickerMode.valuesOf(context).enabled;
    if (v != _visible) {
      _visible = v;
      _reschedule();
    }
  }

  void _reschedule() {
    _timer?.cancel();
    final list = _feed?.sponsors ?? const <Sponsor>[];
    if (!mounted ||
        list.length < 2 ||
        !_visible ||
        !AppActivity.foreground.value) {
      return;
    }
    final current = list[_index % list.length];
    final seconds = current.isMain ? _feed!.mainSeconds : _feed!.subSeconds;
    _timer = Timer(Duration(seconds: seconds.clamp(2, 60)), () {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % list.length);
      _reschedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    AppActivity.foreground.removeListener(_onForeground);
    SponsorFeed.changes.removeListener(_onSponsorsChanged);
    super.dispose();
  }

  Future<void> _open(Sponsor s) async {
    final uri = Uri.tryParse(s.linkUrl ?? '');
    if (uri == null || !uri.hasScheme) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final list = _feed?.sponsors ?? const <Sponsor>[];
    if (list.isEmpty) return const SizedBox.shrink();
    final s = list[_index % list.length];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: s.linkUrl == null ? null : () => _open(s),
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Üstte ortalı küçük başlık; noktalar sağ üstte.
            SizedBox(
              height: 10,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Sabit 10 px yükseklik: büyük yazı ayarında taşmasın.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      s.isMain ? 'ANA SPONSOR' : 'SPONSOR',
                      style: TextStyle(
                        color: s.isMain
                            ? const Color(0xFFB45309)
                            : const Color(0xFF64748B),
                        fontSize: 9,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  if (list.length > 1 && list.length <= 8)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < list.length; i++)
                            Container(
                              width: 5,
                              height: 5,
                              margin: const EdgeInsets.only(left: 4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i == _index % list.length
                                    ? const Color(0xFF0F172A)
                                    : const Color(0xFFCBD5E1),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: _SponsorMark.logoHeight,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 450),
                child: KeyedSubtree(
                  key: ValueKey(s.id),
                  child: _SponsorMark(sponsor: s),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Logo ve ad yan yana, ortalı; içerik büyüdükçe kenarlara doğru açılır
/// ama taşmaz (ad sığmazsa kesilmeden küçülür). Logo her zaman sabit
/// 96×36 kutuda, kutuya sığacak en büyük hâliyle çizilir.
class _SponsorMark extends StatelessWidget {
  const _SponsorMark({required this.sponsor});

  final Sponsor sponsor;

  static const logoWidth = 96.0;
  static const logoHeight = 36.0;

  @override
  Widget build(BuildContext context) {
    final name = Flexible(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          sponsor.name,
          maxLines: 1,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sponsor.logoUrl.isNotEmpty) ...[
            WebSafeImage(
              url: sponsor.logoUrl,
              width: logoWidth,
              height: logoHeight,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 10),
          ],
          name,
        ],
      ),
    );
  }
}
