import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/utils/string_utils.dart';
import '../../core/utils/team_colors.dart';
import '../../core/widgets/pitch_token_style.dart';
import '../tournament/utils/pitch_layout.dart';
import 'poster_share.dart';
import 'squad_poster.dart';

/// Maç kadrosu afişlerinin ortak verisi (paylaşan takım + rakip + maç).
class LineupPosterData {
  const LineupPosterData({
    required this.teamName,
    required this.teamLogo,
    required this.opponentName,
    required this.opponentLogo,
    required this.isHome,
    required this.leagueName,
    required this.leagueLogo,
    required this.week,
    required this.matchDate,
    required this.timeText,
    required this.pitchName,
    required this.palette,
    required this.formation,
    required this.lines,
    required this.subs,
    this.tokenStyle = PitchTokenStyle.circle,
  });

  final String teamName;
  final String teamLogo;
  final String opponentName;
  final String opponentLogo;
  final bool isHome;
  final String leagueName;
  final String leagueLogo;
  final int? week;

  /// YYYY-MM-DD; afişte "29 Eylül 2026" olarak yazılır.
  final String matchDate;
  final String timeText;
  final String pitchName;
  final TeamPalette palette;

  /// Örn. "4-3-3"; boş olabilir.
  final String formation;

  /// İlk 11 hatları: lines[0] kaleci, sonra defanstan hücuma.
  final List<List<PosterPlayer>> lines;
  final List<PosterPlayer> subs;

  /// Diziliş afişinde oyuncu gösterimi (diziliş sekmesindeki tercih).
  final PitchTokenStyle tokenStyle;

  List<PosterPlayer> get starters => [for (final l in lines) ...l];
}

TextStyle _cond({
  Color? color,
  double? fontSize,
  FontWeight? fontWeight,
  double? letterSpacing,
  double? height,
}) => GoogleFonts.barlowCondensed(
  color: color,
  fontSize: fontSize,
  fontWeight: fontWeight,
  letterSpacing: letterSpacing,
  height: height,
);

const _kMonths = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

/// "2026-09-29" → "29 Eylül 2026".
String posterDate(String iso) {
  final p = iso.trim().split('-');
  if (p.length != 3) return '';
  final m = int.tryParse(p[1]) ?? 0;
  final d = int.tryParse(p[2]) ?? 0;
  if (m < 1 || m > 12 || d == 0) return '';
  return '$d ${_kMonths[m - 1]} ${p[0]}';
}

/// Afiş zemini: takım renginde koyu degrade, ikinci renkte ışıma ve
/// arka planda büyük, soluk takım logosu.
class _PosterFrame extends StatelessWidget {
  const _PosterFrame({
    required this.data,
    required this.watermark,
    required this.child,
  });

  final LineupPosterData data;

  /// Logonun konumu ve boyu.
  final ({double? left, double? right, double top, double size}) watermark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = data.palette;
    final wm = watermark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.background, p.backgroundDeep],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(1, -1),
                  radius: 0.9,
                  colors: [
                    p.secondary.withValues(alpha: 0.22),
                    p.secondary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          if (data.teamLogo.isNotEmpty)
            Positioned(
              left: wm.left,
              right: wm.right,
              top: wm.top,
              child: Opacity(
                opacity: 0.09,
                child: PosterLogo(
                  url: data.teamLogo,
                  name: data.teamName,
                  size: wm.size,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
            child: child,
          ),
        ],
      ),
    );
  }
}

Widget _eyebrow(LineupPosterData d, String title) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    Text(
      title,
      textAlign: TextAlign.center,
      style: _cond(
        color: d.palette.accent,
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: 3,
      ),
    ),
    const SizedBox(height: 3),
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (d.leagueLogo.isNotEmpty) ...[
          PosterLogo(url: d.leagueLogo, name: d.leagueName, size: 14),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            [
              d.leagueName,
              if (d.week != null) '${d.week}. Hafta',
            ].where((e) => e.isNotEmpty).join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  ],
);

/// Tarih · saat ve stadyum ikonu + stat adı.
Widget _matchMeta(LineupPosterData d) {
  final date = [
    posterDate(d.matchDate),
    d.timeText,
  ].where((e) => e.trim().isNotEmpty).join(' · ');
  Widget item(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: d.palette.accent),
      const SizedBox(width: 4),
      Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
  return Padding(
    padding: const EdgeInsets.only(top: 9),
    child: Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        if (date.isNotEmpty) item(Icons.calendar_today_rounded, date),
        if (d.pitchName.trim().isNotEmpty)
          item(Icons.stadium_rounded, d.pitchName.trim()),
      ],
    ),
  );
}

Widget _divider() => Container(
  height: 1,
  margin: const EdgeInsets.only(top: 10),
  color: Colors.white.withValues(alpha: 0.12),
);

/// Diziliş afişi üst bölümü: iki takım, paylaşan takımın logosu daha büyük.
class _MatchHeader extends StatelessWidget {
  const _MatchHeader({required this.data, required this.title});

  final LineupPosterData data;
  final String title;

  Widget _team(String name, String logo, bool own) => Expanded(
    child: Column(
      children: [
        PosterLogo(
          url: logo,
          name: name,
          size: own ? 52 : 36,
          badgeColor: data.palette.primary,
          badgeTextColor: Colors.white,
        ),
        const SizedBox(height: 5),
        Text(
          name.trUpper,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: _cond(
            color: own ? Colors.white : Colors.white60,
            fontSize: 15,
            height: 1.05,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final d = data;
    final own = _team(d.teamName, d.teamLogo, true);
    final opp = _team(d.opponentName, d.opponentLogo, false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _eyebrow(d, title),
        const SizedBox(height: 12),
        Row(
          children: [
            d.isHome ? own : opp,
            Text(
              'VS',
              style: _cond(
                color: d.palette.accent,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            d.isHome ? opp : own,
          ],
        ),
        _matchMeta(d),
        _divider(),
      ],
    );
  }
}

Widget _numberBox(TeamPalette p, String? number, {double size = 22}) =>
    Container(
      width: size + 2,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        (number ?? '').isEmpty ? '–' : number!,
        style: _cond(
          color: p.accent,
          fontSize: size * 0.6,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

Widget _sectionTitle(TeamPalette p, String title, int count) => Row(
  children: [
    Text(
      title,
      style: _cond(
        color: p.accent,
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 2,
      ),
    ),
    const SizedBox(width: 8),
    Expanded(
      child: Container(height: 1, color: p.accent.withValues(alpha: 0.4)),
    ),
    const SizedBox(width: 8),
    Text(
      '$count',
      style: _cond(
        color: Colors.white60,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  ],
);

Widget _captainMark(TeamPalette p) => Container(
  margin: const EdgeInsets.only(left: 4),
  padding: const EdgeInsets.symmetric(horizontal: 3),
  decoration: BoxDecoration(
    color: p.accent,
    borderRadius: BorderRadius.circular(3),
  ),
  child: Text(
    'K',
    style: TextStyle(
      color: p.onAccent,
      fontSize: 8.5,
      fontWeight: FontWeight.w800,
    ),
  ),
);

/// Esame afişi: maç bilgisi + ilk 11 (saha sırasıyla) ve yedekler listesi.
class LineupListPoster extends StatelessWidget {
  const LineupListPoster({super.key, required this.data});

  final LineupPosterData data;

  Widget _row(PosterPlayer pl, {bool small = false}) {
    final p = data.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          _numberBox(p, pl.number),
          const SizedBox(width: 8),
          Flexible(
            child: Text.rich(
              TextSpan(
                text: '${pl.firstName} ',
                children: [
                  TextSpan(
                    text: pl.lastName.trUpper,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFFF1F5F9),
                fontSize: small ? 11.5 : 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (pl.isCaptain) _captainMark(p),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = data.palette;
    final d = data;
    return _PosterFrame(
      data: d,
      watermark: (left: -90, right: null, top: 120, size: 340),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _eyebrow(d, 'MAÇ KADROSU'),
          const SizedBox(height: 10),
          Center(
            child: PosterLogo(
              url: d.teamLogo,
              name: d.teamName,
              size: 96,
              badgeColor: p.primary,
              badgeTextColor: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            d.teamName.trUpper,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _cond(
              color: Colors.white,
              fontSize: 30,
              height: 1,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Rakip: ',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              PosterLogo(url: d.opponentLogo, name: d.opponentName, size: 16),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  d.opponentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          _matchMeta(d),
          _divider(),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: kPosterSize.width - 32,
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 115,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 12),
                              _sectionTitle(p, 'İLK 11', d.starters.length),
                              const SizedBox(height: 7),
                              for (final pl in d.starters) _row(pl),
                            ],
                          ),
                        ),
                        if (d.subs.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Container(
                            width: 1,
                            margin: const EdgeInsets.only(top: 12),
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 85,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 12),
                                _sectionTitle(p, 'YEDEKLER', d.subs.length),
                                const SizedBox(height: 7),
                                for (final pl in d.subs) _row(pl, small: true),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Diziliş afişi: maç bilgisi + sahada ilk 11 + altta yedekler.
class LineupPitchPoster extends StatelessWidget {
  const LineupPitchPoster({super.key, required this.data});

  final LineupPosterData data;

  /// İki isimli oyuncuda ilk ad kısaltılır: "Mehmet Ali" → "M. Ali".
  static String _shortFirst(String first) {
    final parts = first.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return first.trim();
    return '${parts.first.characters.first}. ${parts.skip(1).join(' ')}';
  }

  Widget _token(PosterPlayer pl) {
    final p = data.palette;
    final number = Text(
      (pl.number ?? '').isEmpty ? '–' : pl.number!,
      style: _cond(
        color: p.primary.computeLuminance() > 0.5
            ? const Color(0xFF0B1220)
            : Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    );
    final mark = data.tokenStyle == PitchTokenStyle.shirt
        ? JerseyShape(
            width: 36,
            color: p.primary,
            borderColor: p.secondary,
            child: number,
          )
        : Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.primary,
              shape: BoxShape.circle,
              border: Border.all(color: p.secondary, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 4),
              ],
            ),
            child: number,
          );
    final hasLast = pl.lastName.isNotEmpty;
    return SizedBox(
      width: 78,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              mark,
              if (pl.isCaptain)
                Positioned(right: -9, top: -5, child: _captainMark(p)),
            ],
          ),
          const SizedBox(height: 3),
          if (hasLast)
            Text(
              _shortFirst(pl.firstName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9.5,
                height: 1.15,
                fontWeight: FontWeight.w600,
              ),
            ),
          Text(
            (hasLast ? pl.lastName : pl.firstName).trUpper,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: _cond(
              color: Colors.white,
              fontSize: 12.5,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = data.palette;
    return _PosterFrame(
      data: data,
      watermark: (left: null, right: -80, top: 180, size: 320),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MatchHeader(data: data, title: 'İLK 11'),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF166534).withValues(alpha: 0.85),
                    const Color(0xFF14532D).withValues(alpha: 0.85),
                  ],
                ),
                border: Border.all(color: Colors.white24),
              ),
              child: CustomPaint(
                painter: _HalfPitchPainter(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                  // Diziliş sekmesiyle aynı gerçekçi yerleşim.
                  child: LayoutBuilder(
                    builder: (context, c) {
                      const tokenW = 78.0;
                      final outfield = data.lines.length - 1;
                      return Stack(
                        children: [
                          for (var li = 0; li < data.lines.length; li++)
                            for (var i = 0; i < data.lines[li].length; i++)
                              () {
                                final pos = pitchSlot(
                                  li: li,
                                  i: i,
                                  n: data.lines[li].length,
                                  outfieldLines: outfield,
                                );
                                return Positioned(
                                  left: (pos.dx * c.maxWidth - tokenW / 2)
                                      .clamp(0.0, c.maxWidth - tokenW),
                                  top: (pos.dy * c.maxHeight - 26).clamp(
                                    0.0,
                                    c.maxHeight - 60,
                                  ),
                                  width: tokenW,
                                  child: _token(data.lines[li][i]),
                                );
                              }(),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          if (data.subs.isNotEmpty) ...[
            const SizedBox(height: 8),
            _sectionTitle(p, 'YEDEKLER', data.subs.length),
            const SizedBox(height: 5),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 9,
              runSpacing: 4,
              children: [
                for (final pl in data.subs)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text:
                              '${(pl.number ?? '').isEmpty ? '–' : pl.number} ',
                          style: TextStyle(
                            color: p.accent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextSpan(
                          text:
                              (pl.lastName.isNotEmpty
                                      ? pl.lastName
                                      : pl.firstName)
                                  .trUpper,
                        ),
                      ],
                    ),
                    style: const TextStyle(
                      color: Color(0xFFE2E8F0),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Yarı saha çizgileri: orta çizgi/çember üstte, ceza sahası altta.
class _HalfPitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final w = size.width;
    final h = size.height;
    // Orta saha çemberinin alt yarısı
    canvas.drawArc(
      Rect.fromCircle(center: Offset(w / 2, 0), radius: w * 0.16),
      0,
      3.1416,
      false,
      paint,
    );
    // Ceza sahası ve kale alanı
    final boxW = w * 0.6;
    final boxH = h * 0.17;
    canvas.drawRect(Rect.fromLTWH((w - boxW) / 2, h - boxH, boxW, boxH), paint);
    final smallW = w * 0.3;
    final smallH = h * 0.07;
    canvas.drawRect(
      Rect.fromLTWH((w - smallW) / 2, h - smallH, smallW, smallH),
      paint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset(w / 2, h - boxH), radius: w * 0.1),
      3.1416,
      3.1416,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
