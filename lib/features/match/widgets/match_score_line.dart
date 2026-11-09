import 'package:flutter/material.dart';

import '../../../core/utils/team_name.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../models/match.dart';
import '../utils/match_clock.dart';
import 'penalty_badge.dart';

/// Ana sayfa ve fikstürde ortak tek satırlık maç görünümü:
/// `saat | Ev Sahibi [logo]  2 - 1  [logo] Deplasman`
///
/// Sol sütun sabit genişlikte olduğundan skorlar alt alta hizalı durur; uzun
/// takım adları iki satıra iner; satırlar kendi içinde ortalanır.
class MatchScoreLine extends StatelessWidget {
  const MatchScoreLine({
    super.key,
    required this.match,
    required this.homeName,
    required this.awayName,
    required this.homeLogo,
    required this.awayLogo,
    this.leading,
    this.onWatch,
    this.showLogos = true,
    this.compact = false,
    this.homeShort = '',
    this.awayShort = '',
  });

  /// Tablodaki kısa adlar: takvim kartında tam ad sığmazsa kullanılır.
  final String homeShort;
  final String awayShort;

  final MatchModel match;
  final String homeName;
  final String awayName;
  final String homeLogo;
  final String awayLogo;

  /// Saatin üstündeki küçük ikon (yayın, yönetici düzenleme).
  final Widget? leading;

  /// Takvim düzeninde skorun altındaki "İzle" düğmesi (yayın varsa).
  final VoidCallback? onWatch;

  /// Ana sayfada logolar gösterilmez (yalnızca fikstürde).
  final bool showLogos;

  /// Maç takvimi düzeni: logo adın üstünde, ad büyük ve en çok iki satır;
  /// saat (canlıda dakika) skorun üstünde.
  final bool compact;

  static const _mid = Color(0xFF94A3B8);
  static const _accent = Color(0xFF10B981);
  static const _live = Color(0xFFF87171);

  ({String text, Color color})? _statusLabel(String? liveMinute) {
    switch (match.displayStatus) {
      case MatchStatus.notStarted:
        return null;
      case MatchStatus.finished:
        return (text: 'MS', color: _accent);
      case MatchStatus.halftime:
        return (text: 'İY', color: _live);
      case MatchStatus.live:
        return (text: liveMinute ?? 'CANLI', color: _live);
      case MatchStatus.cancelled:
        return (text: 'İPT', color: Colors.white54);
      case MatchStatus.postponed:
        return (text: 'ERT', color: Colors.white54);
    }
  }

  @override
  Widget build(BuildContext context) => MatchClockBuilder(
    match: match,
    builder: (context, liveMinute) => _build(context, liveMinute),
  );

  Widget _build(BuildContext context, String? liveMinute) {
    if (compact) return _buildStacked(context, liveMinute);
    final rawTime = (match.matchTime ?? '').trim();
    final time = rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime;
    final status = _statusLabel(liveMinute);

    final hs = match.homeScore;
    final as = match.awayScore;
    final isLive =
        match.status == MatchStatus.live ||
        match.status == MatchStatus.halftime;
    // İptal / ertelenen maçta skor kutusunda İPT / ERT yazar.
    final unplayed =
        match.displayStatus == MatchStatus.cancelled ||
        match.displayStatus == MatchStatus.postponed;
    final showScore =
        !unplayed &&
        (match.status == MatchStatus.finished || isLive || hs != 0 || as != 0);
    // Ad, kendi alanında logoya yaslı durur; iki satıra inerse satırlar da
    // logo tarafına hizalanır. Sonucu belli maçta yenen kalın, yenilen ince.
    // Eleme maçında berabere skor penaltılarla belirlenir.
    final winner = match.homeWins;
    final decided = match.status == MatchStatus.finished && winner != null;
    Widget name(String text, {required bool home}) {
      final won = winner == home;
      return Align(
        alignment: home ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(
          shortTeamName(text),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: home ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            fontWeight: !decided
                ? FontWeight.w600
                : (won ? FontWeight.w800 : FontWeight.w400),
            fontSize: compact ? 11.5 : 12,
            height: compact ? 1.05 : 1.15,
            color: Colors.white,
            fontFamily: 'Barlow',
          ),
        ),
      );
    }

    Widget logo(String url) => ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        1.237,
        -0.215,
        -0.022,
        0,
        4,
        -0.064,
        1.086,
        -0.022,
        0,
        4,
        -0.064,
        -0.215,
        1.278,
        0,
        4,
        0,
        0,
        0,
        1,
        0,
      ]),
      child: WebSafeImage(
        url: url,
        width: compact ? 17 : 20,
        height: compact ? 17 : 20,
        fit: BoxFit.contain,
        fallbackIconSize: compact ? 14 : 16,
      ),
    );

    return Row(
      children: [
        SizedBox(
          width: compact ? 34 : 40,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: leading,
                ),
              if (match.status == MatchStatus.finished)
                Text(
                  'MS',
                  style: TextStyle(
                    color: status?.color ?? _accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                )
              else ...[
                Text(
                  time.isEmpty ? '--:--' : time,
                  style: const TextStyle(
                    color: _mid,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                if (status != null && !unplayed)
                  Text(
                    status.text,
                    style: TextStyle(
                      color: status.color,
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Row(
            children: [
              Expanded(child: name(homeName, home: true)),
              if (showLogos) ...[const SizedBox(width: 5), logo(homeLogo)],
            ],
          ),
        ),
        // Skor kapsülü: isimlerden boşlukla ayrılır; canlı maçta kırmızı.
        // Penaltılı maçta altında iki sarı "4 P" kutusu.
        Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _scoreCapsule(isLive, unplayed, showScore, status, hs, as),
              if (match.hasPens && !unplayed) ...[
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PenaltyBadge(match.homePens!, size: 9.5),
                    const SizedBox(width: 4),
                    PenaltyBadge(match.awayPens!, size: 9.5),
                  ],
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              if (showLogos) ...[logo(awayLogo), const SizedBox(width: 5)],
              Expanded(child: name(awayName, home: false)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _scoreCapsule(
    bool isLive,
    bool unplayed,
    bool showScore,
    ({String text, Color color})? status,
    int hs,
    int as,
  ) {
    return Container(
      width: compact ? 46 : 56,
      height: compact ? 24 : 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isLive ? _live.withValues(alpha: 0.22) : const Color(0xFF064E3B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (isLive ? _live : _accent).withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        unplayed ? (status?.text ?? '-') : (showScore ? '$hs - $as' : '-'),
        style: TextStyle(
          color: isLive ? _live : (unplayed ? Colors.white70 : Colors.white),
          fontWeight: FontWeight.w800,
          fontSize: compact ? 12 : 14,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

extension on MatchScoreLine {
  /// Takvim kartı: solda dar durum sütunu (MS / dakika / saat + İzle), ince
  /// çizgi, sağda [ev sahibi] [skor] [deplasman]. Her satır aynı boyda; ad
  /// hiç 2. satıra inmez (sığmazsa kısa ad, sonra küçülür, en son "…").
  /// Telefonun yazı boyutu büyüdükçe satırların hepsi birlikte en çok %30
  /// büyür.
  Widget _buildStacked(BuildContext context, String? liveMinute) {
    const mid = MatchScoreLine._mid;
    const accent = MatchScoreLine._accent;
    const live = MatchScoreLine._live;
    final k = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3);
    final rawTime = (match.matchTime ?? '').trim();
    final time = rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime;
    final hs = match.homeScore;
    final as = match.awayScore;
    final isLive =
        match.status == MatchStatus.live ||
        match.status == MatchStatus.halftime;
    final unplayed =
        match.displayStatus == MatchStatus.cancelled ||
        match.displayStatus == MatchStatus.postponed;
    final showScore =
        !unplayed &&
        (match.status == MatchStatus.finished || isLive || hs != 0 || as != 0);
    final winner = match.homeWins;
    final decided = match.status == MatchStatus.finished && winner != null;

    Widget side(String name, String short, String logo, {required bool home}) {
      final won = winner == home;
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          WebSafeImage(
            url: logo,
            width: 26 * k,
            height: 26 * k,
            fit: BoxFit.contain,
            fallbackIconSize: 18 * k,
          ),
          SizedBox(height: 3 * k),
          _FitName(
            full: shortTeamName(name),
            short: short.trim(),
            style: TextStyle(
              fontWeight: decided && !won ? FontWeight.w600 : FontWeight.w700,
              fontSize: 13 * k,
              height: 1.1,
              color: decided && !won ? mid : Colors.white,
              fontFamily: 'Barlow',
            ),
          ),
        ],
      );
    }

    // Sol sütun: durum.
    final Widget status = switch (match.displayStatus) {
      MatchStatus.finished => Text(
        'MS',
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w800,
          fontSize: 13 * k,
        ),
      ),
      MatchStatus.live || MatchStatus.halftime => Container(
        padding: EdgeInsets.fromLTRB(4 * k, 1, 5 * k, 1),
        decoration: BoxDecoration(
          color: const Color(0xD9080C14),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: const Color(0x47FFFFFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (match.displayStatus == MatchStatus.live)
              _BlinkDot(size: 6 * k)
            else
              Container(
                width: 6 * k,
                height: 6 * k,
                decoration: const BoxDecoration(
                  color: Color(0xFFFBBF24),
                  shape: BoxShape.circle,
                ),
              ),
            SizedBox(width: 3 * k),
            Text(
              match.displayStatus == MatchStatus.halftime
                  ? 'İY'
                  : (liveMinute ?? 'CANLI'),
              maxLines: 1,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 13 * k,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
      MatchStatus.cancelled || MatchStatus.postponed => Text(
        match.displayStatus == MatchStatus.cancelled ? 'İPT' : 'ERT',
        style: TextStyle(
          color: Colors.white54,
          fontWeight: FontWeight.w800,
          fontSize: 12 * k,
        ),
      ),
      MatchStatus.notStarted => Text(
        time.isEmpty ? '--:--' : time,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 13.5 * k,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    };

    Widget left = SizedBox(
      width: 46 * k,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              status,
              if (onWatch != null) ...[
                SizedBox(height: 3 * k),
                YoutubeBrandIcon(size: 18 * k),
                Text(
                  isLive ? 'Canlı' : 'İzle',
                  style: TextStyle(
                    color: const Color(0xFFFCA5A5),
                    fontWeight: FontWeight.w800,
                    fontSize: 9.5 * k,
                    height: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    // Sol sütuna dokununca yayın açılır (yoksa kart maç detayına gider).
    if (onWatch != null) {
      left = InkWell(
        onTap: onWatch,
        borderRadius: BorderRadius.circular(8),
        child: left,
      );
    }

    final score = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 54 * k,
          height: 28 * k,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: !showScore && !unplayed
                ? Colors.transparent
                : isLive
                ? live.withValues(alpha: 0.22)
                : const Color(0xFF064E3B),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: !showScore && !unplayed
                  ? Colors.transparent
                  : (isLive ? live : accent).withValues(alpha: 0.45),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              unplayed ? '-' : (showScore ? '$hs - $as' : '–'),
              style: TextStyle(
                color: isLive
                    ? live
                    : (showScore ? Colors.white : Colors.white54),
                fontWeight: FontWeight.w800,
                fontSize: 17 * k,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        if (match.hasPens && !unplayed) ...[
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PenaltyBadge(match.homePens!, size: 9 * k),
              const SizedBox(width: 4),
              PenaltyBadge(match.awayPens!, size: 9 * k),
            ],
          ),
        ],
      ],
    );

    return MediaQuery(
      // Boyutlar elle k ile ölçeklenir; yazılar ikinci kez büyümesin.
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: SizedBox(
        height: 62 * k,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.025),
                borderRadius: BorderRadius.circular(8),
              ),
              child: left,
            ),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(vertical: 6),
              color: const Color(0xFF2B3A57),
            ),
            const SizedBox(width: 2),
            Expanded(child: side(homeName, homeShort, homeLogo, home: true)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Center(child: score),
            ),
            Expanded(child: side(awayName, awayShort, awayLogo, home: false)),
          ],
        ),
      ),
    );
  }
}

/// Tek satırlık takım adı: tam ad sığmazsa kısa ad, o da sığmazsa yazı
/// %20'ye kadar küçülür, en son sonu "…" ile kesilir.
class _FitName extends StatelessWidget {
  const _FitName({
    required this.full,
    required this.short,
    required this.style,
  });

  final String full;
  final String short;
  final TextStyle style;

  double _w(String t, TextStyle st) => (TextPainter(
    text: TextSpan(text: t, style: st),
    maxLines: 1,
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  )..layout()).width;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final max = c.maxWidth;
      var text = full;
      var w = _w(text, style);
      if (w > max && short.isNotEmpty && short != full) {
        text = short;
        w = _w(text, style);
      }
      final size = style.fontSize ?? 13;
      final scale = w <= max ? 1.0 : (max / w).clamp(0.8, 1.0);
      return Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: style.copyWith(fontSize: size * scale),
      );
    },
  );
}

/// Canlı maçın yanıp sönen kırmızı noktası.
class _BlinkDot extends StatefulWidget {
  const _BlinkDot({required this.size});

  final double size;

  @override
  State<_BlinkDot> createState() => _BlinkDotState();
}

class _BlinkDotState extends State<_BlinkDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: 0.3, end: 1).animate(_c),
    child: Container(
      width: widget.size,
      height: widget.size,
      decoration: const BoxDecoration(
        color: Color(0xFFEF4444),
        shape: BoxShape.circle,
      ),
    ),
  );
}

class YoutubeBrandIcon extends StatelessWidget {
  const YoutubeBrandIcon({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _YoutubeBrandPainter()),
  );
}

class _YoutubeBrandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final frame = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.04,
        size.height * 0.17,
        size.width * 0.92,
        size.height * 0.66,
      ),
      Radius.circular(size.height * 0.2),
    );
    canvas.drawRRect(frame, Paint()..color = const Color(0xFFFF0033));

    final play = Path()
      ..moveTo(size.width * 0.43, size.height * 0.31)
      ..lineTo(size.width * 0.43, size.height * 0.69)
      ..lineTo(size.width * 0.70, size.height * 0.50)
      ..close();
    canvas.drawPath(play, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _YoutubeBrandPainter oldDelegate) => false;
}
