import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/utils/app_activity.dart';
import '../../core/utils/string_utils.dart';
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
      child: SponsorStripTile(sponsor: s),
    );
  }
}

/// Şeridin tek sponsorluk görünümü: solda sabit genişlikte başlık, kalan
/// yerde logo + ad (sponsorun yazı stiliyle). Sponsor Yönetimi'ndeki
/// önizleme de bunu kullanır; [logo] kaydedilmemiş yeni logoyu gösterir.
class SponsorStripTile extends StatelessWidget {
  const SponsorStripTile({
    super.key,
    required this.sponsor,
    this.logo,
    this.logoAspect,
  });

  final Sponsor sponsor;
  final Widget? logo;
  final double? logoAspect;

  @override
  Widget build(BuildContext context) {
    final s = sponsor;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      // Şerit kendiliğinden döndüğü için sayfa noktaları gösterilmez.
      child: SizedBox(
        height: _SponsorMark.boxHeight,
        child: Row(
          children: [
            SizedBox(
              width: 58,
              // Büyük yazı ayarında taşmasın.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  s.isMain ? 'ANA\nSPONSOR' : 'SPONSOR',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: s.isMain
                        ? const Color(0xFFB45309)
                        : const Color(0xFF64748B),
                    fontSize: 9,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            // Kurumsal stilde başlıkla logo arasında ince ayraç.
            if (s.nameStyle == SponsorNameStyle.kurumsal)
              Container(
                width: 1,
                height: 28,
                margin: const EdgeInsets.only(left: 4),
                color: const Color(0xFFE2E8F0),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 450),
                child: KeyedSubtree(
                  key: ValueKey('${s.id}|${s.nameStyle.name}'),
                  child: _SponsorMark(
                    sponsor: s,
                    logo: logo,
                    logoAspect: logoAspect,
                    // Başlık + ayraç + boşluk: işaret şeridin ortasına
                    // hizalanırken bu kadar sola kayabilir.
                    leadingWidth:
                        58 +
                        (s.nameStyle == SponsorNameStyle.kurumsal ? 5 : 0) +
                        8,
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

/// Logo ve ad yan yana, başlığın sağındaki alanda ortalı (ad sığmazsa
/// kesilmeden küçülür). Logo 40 px yükseklikte, oranı biliniyorsa kutu logo
/// kadar daraltılır (kare logoda ad uzak kalmasın). Ad sponsorun stiliyle:
/// sade (yarı kalın), kurumsal (aralıklı büyük harf), spor (dar yazı).
class _SponsorMark extends StatelessWidget {
  const _SponsorMark({
    required this.sponsor,
    this.logo,
    this.logoAspect,
    this.leadingWidth = 0,
  });

  final Sponsor sponsor;
  final Widget? logo;
  final double? logoAspect;

  /// Soldaki başlığın kapladığı genişlik; işaret bu alan dahil şeridin
  /// ortasına hizalanır (başlığa binmeden).
  final double leadingWidth;

  static const boxHeight = 48.0;
  static const logoHeight = 40.0;
  static const logoMaxWidth = 84.0;

  TextStyle get _style => switch (sponsor.nameStyle) {
    SponsorNameStyle.sade => const TextStyle(
      fontFamily: 'Barlow',
      color: Color(0xFF0F172A),
      fontSize: 16,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    ),
    SponsorNameStyle.kurumsal => const TextStyle(
      fontFamily: 'Barlow',
      color: Color(0xFF334155),
      fontSize: 13,
      fontWeight: FontWeight.w600,
      letterSpacing: 2.4,
    ),
    SponsorNameStyle.spor => const TextStyle(
      fontFamily: 'BarlowCondensed',
      color: Color(0xFF0F172A),
      fontSize: 19,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.8,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final raw = sponsor.name;
    final text = sponsor.nameStyle == SponsorNameStyle.sade ? raw : raw.trUpper;
    final name = Flexible(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text, maxLines: 1, style: _style),
      ),
    );
    final aspect = logoAspect ?? sponsor.logoAspect;
    final boxWidth = aspect == null
        ? logoMaxWidth
        : (logoHeight * aspect).clamp(logoHeight * 0.5, logoMaxWidth);
    final hasLogo = logo != null || sponsor.logoUrl.isNotEmpty;
    final mark = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasLogo) ...[
          SizedBox(
            width: boxWidth,
            height: logoHeight,
            child:
                logo ??
                WebSafeImage(
                  url: sponsor.logoUrl,
                  width: boxWidth,
                  height: logoHeight,
                  fit: BoxFit.contain,
                ),
          ),
          const SizedBox(width: 10),
        ],
        name,
      ],
    );
    // İşaretin genişliği ölçülür; şeridin (başlık dahil) ortasına gelecek
    // kadar sola kaydırılır, ama başlığın alanına taşmaz.
    return LayoutBuilder(
      builder: (context, box) {
        final tp = TextPainter(
          text: TextSpan(text: text, style: _style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final markWidth = ((hasLogo ? boxWidth + 10 : 0) + tp.width).clamp(
          0.0,
          box.maxWidth,
        );
        tp.dispose();
        final centered = (box.maxWidth + leadingWidth) / 2 - leadingWidth;
        final left = (centered - markWidth / 2).clamp(
          0.0,
          box.maxWidth - markWidth,
        );
        return Padding(
          padding: EdgeInsets.only(left: left),
          child: Align(alignment: Alignment.centerLeft, child: mark),
        );
      },
    );
  }
}
