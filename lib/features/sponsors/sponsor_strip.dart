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

  @override
  void initState() {
    super.initState();
    AppActivity.foreground.addListener(_reschedule);
    _load();
  }

  Future<void> _load() async {
    final id = widget.leagueId;
    final cached = await SponsorFeed.cached(id);
    if (!mounted || id != widget.leagueId) return;
    if (cached != null) _apply(cached);
    try {
      final fresh = await SponsorFeed.fetch(id);
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
    AppActivity.foreground.removeListener(_reschedule);
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
        height: 46,
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            SizedBox(
              width: 74,
              child: Text(
                s.isMain ? 'ANA\nSPONSOR' : 'SPONSOR',
                style: TextStyle(
                  color: s.isMain
                      ? const Color(0xFFB45309)
                      : const Color(0xFF64748B),
                  fontSize: 9.5,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 450),
                child: KeyedSubtree(
                  key: ValueKey(s.id),
                  child: Center(child: _SponsorMark(sponsor: s)),
                ),
              ),
            ),
            SizedBox(
              width: 74,
              child: list.length > 1 && list.length <= 8
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.end,
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
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Logo (varsa) ve yanında ad; logo yoksa yalnız ad.
class _SponsorMark extends StatelessWidget {
  const _SponsorMark({required this.sponsor});

  final Sponsor sponsor;

  @override
  Widget build(BuildContext context) {
    final name = Text(
      sponsor.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Color(0xFF0F172A),
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    );
    if (sponsor.logoUrl.isEmpty) return name;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WebSafeImage(
          url: sponsor.logoUrl,
          height: 32,
          width: 80,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: 8),
        Flexible(child: name),
      ],
    );
  }
}
