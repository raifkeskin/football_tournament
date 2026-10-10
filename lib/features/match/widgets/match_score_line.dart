import 'package:flutter/material.dart';

import '../../../core/utils/team_name.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../models/match.dart';
import '../utils/match_clock.dart';

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
    this.showLogos = true,
    this.compact = false,
  });

  final MatchModel match;
  final String homeName;
  final String awayName;
  final String homeLogo;
  final String awayLogo;

  /// Saatin üstündeki küçük ikon (yayın, yönetici düzenleme).
  final Widget? leading;

  /// Ana sayfada logolar gösterilmez (yalnızca fikstürde).
  final bool showLogos;

  /// Takvim listesinde daha fazla maçın görünmesi için sıkı satır ölçüleri.
  final bool compact;

  static const _mid = Color(0xFF94A3B8);
  static const _accent = Color(0xFF10B981);
  static const _live = Color(0xFFF87171);

  ({String text, Color color})? _statusLabel(String? liveMinute) {
    switch (match.status) {
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
    final rawTime = (match.matchTime ?? '').trim();
    final time = rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime;
    final status = _statusLabel(liveMinute);

    final hs = match.homeScore;
    final as = match.awayScore;
    final isLive =
        match.status == MatchStatus.live ||
        match.status == MatchStatus.halftime;
    final showScore =
        match.status == MatchStatus.finished || isLive || hs != 0 || as != 0;
    // Ad, kendi alanında skora yaslı durur; iki satıra inerse satırlar
    // birbirine göre ortalanır.
    Widget name(String text, Alignment align) => Align(
      alignment: align,
      child: Text(
        shortTeamName(text),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: compact ? 11.5 : 12,
          height: compact ? 1.05 : 1.15,
          color: Colors.white,
          fontFamily: 'Barlow',
        ),
      ),
    );

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
                if (status != null)
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
              Expanded(child: name(homeName, Alignment.centerRight)),
              if (showLogos) ...[const SizedBox(width: 5), logo(homeLogo)],
            ],
          ),
        ),
        // Skor kapsülü: isimlerden boşlukla ayrılır; canlı maçta kırmızı.
        Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 10),
          child: Container(
            width: compact ? 46 : 56,
            height: compact ? 24 : 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isLive
                  ? _live.withValues(alpha: 0.22)
                  : const Color(0xFF064E3B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (isLive ? _live : _accent).withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              showScore ? '$hs - $as' : '-',
              style: TextStyle(
                color: isLive ? _live : Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: compact ? 12 : 14,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              if (showLogos) ...[logo(awayLogo), const SizedBox(width: 5)],
              Expanded(child: name(awayName, Alignment.centerLeft)),
            ],
          ),
        ),
      ],
    );
  }
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
