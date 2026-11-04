import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/image_upload_service.dart';
import '../../core/utils/string_utils.dart';
import '../../core/utils/team_colors.dart';
import '../../core/utils/team_name.dart';
import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import 'poster_background.dart';
import 'poster_share.dart';

/// Takımın forma deseni (`teams.jersey_style`); afişlerde forma bununla
/// çizilir. Seçilmemişse düz.
enum JerseyStyle {
  stripes('stripes', 'Çizgili'),
  plain('plain', 'Düz'),
  half('half', 'Parçalı');

  const JerseyStyle(this.key, this.label);

  final String key;
  final String label;

  static JerseyStyle of(String? key) =>
      values.where((e) => e.key == key).firstOrNull ?? plain;
}

/// Afişteki takım: ad, arma, renkler ve forma deseni.
@immutable
class PosterSide {
  const PosterSide({
    required this.id,
    required this.name,
    required this.logo,
    required this.first,
    required this.second,
    required this.jersey,
  });

  factory PosterSide.of({
    required String id,
    required String name,
    required String logo,
    String? firstHex,
    String? secondHex,
    String? jerseyStyle,
  }) => PosterSide(
    id: id,
    name: name,
    logo: logo,
    first: parseHexColor(firstHex) ?? const Color(0xFF10B981),
    second: parseHexColor(secondHex) ?? Colors.white,
    jersey: JerseyStyle.of(jerseyStyle),
  );

  final String id;
  final String name;
  final String logo;
  final Color first;
  final Color second;
  final JerseyStyle jersey;

  /// Formada ve büyük başlıkta: "Feriköy Masterlar" → "FERİKÖY".
  String get shortLabel => shortTeamName(name).trUpper;
  String get fullLabel => posterTeamName(name).trUpper;
}

/// Sorumlular afişinde takım sorumlusu: ad ve (varsa) fotoğraf.
@immutable
class PosterManager {
  const PosterManager({required this.name, required this.photo});

  final String name;
  final String photo;
}

/// Takım odaklı afişlerin ortak bilgisi.
@immutable
class MatchPosterInfo {
  const MatchPosterInfo({
    required this.leagueName,
    required this.leagueLogo,
    required this.week,
    required this.home,
    required this.away,
    required this.pitchName,
    required this.dayName,
    required this.dateText,
    required this.timeText,
    this.homeManager,
    this.awayManager,
  });

  final PosterManager? homeManager;
  final PosterManager? awayManager;

  final String leagueName;
  final String leagueLogo;
  final int? week;
  final PosterSide home;
  final PosterSide away;
  final String pitchName;
  final String dayName;
  final String dateText;
  final String timeText;

  String get weekText => week == null ? '' : '$week. HAFTA';
}

/// Maç afişi tasarımları (paylaşım penceresinin ilk adımı).
enum MatchPosterDesign {
  classic('Klasik', 'Turnuva zemini'),
  jerseys('Formalar', 'İki takımın forması'),
  split('Çapraz', 'Takım renkleri'),
  team('Takım', 'Tek takım + slogan'),
  managers('Sorumlular', 'İki takım sorumlusu');

  const MatchPosterDesign(this.label, this.subtitle);

  final String label;
  final String subtitle;
}

const _gold = Color(0xFFE0A526);
const _muted = Color(0xFFBAC6D6);
const _sloganMax = 22;

/// Slogan en çok bu kadar karakter (afişteki satıra sığar).
const kPosterSloganMax = _sloganMax;

TextStyle _cond(
  double size, {
  Color color = Colors.white,
  bool italic = false,
  double spacing = 0,
  List<Shadow>? shadows,
}) => GoogleFonts.barlowCondensed(
  fontSize: size,
  color: color,
  fontWeight: FontWeight.w800,
  fontStyle: italic ? FontStyle.italic : FontStyle.normal,
  letterSpacing: spacing,
  height: 1,
  shadows: shadows,
);

const _shadow = [
  Shadow(color: Color(0xAA000000), blurRadius: 12, offset: Offset(0, 3)),
];

Color _dark(Color c, double k) => Color.fromARGB(
  255,
  (c.r * 255 * k).round(),
  (c.g * 255 * k).round(),
  (c.b * 255 * k).round(),
);

// ------------------------------------------------------------------ forma

/// Arkadan görünen forma: desen, sırtta ad ve numara.
class JerseyArt extends StatelessWidget {
  const JerseyArt({
    super.key,
    required this.width,
    required this.first,
    required this.second,
    required this.style,
    this.label = '',
    this.number = '10',
  });

  final double width;
  final Color first;
  final Color second;
  final JerseyStyle style;
  final String label;
  final String number;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, width * 1.08),
      painter: _JerseyPainter(
        first: first,
        second: second,
        style: style,
        label: label,
        number: number,
      ),
    );
  }
}

class _JerseyPainter extends CustomPainter {
  _JerseyPainter({
    required this.first,
    required this.second,
    required this.style,
    required this.label,
    required this.number,
  });

  final Color first;
  final Color second;
  final JerseyStyle style;
  final String label;
  final String number;

  static const _pts = [
    Offset(0.31, 0),
    Offset(0.40, 0.035),
    Offset(0.60, 0.035),
    Offset(0.69, 0),
    Offset(1, 0.17),
    Offset(0.90, 0.42),
    Offset(0.79, 0.36),
    Offset(0.80, 1),
    Offset(0.20, 1),
    Offset(0.21, 0.36),
    Offset(0.10, 0.42),
    Offset(0, 0.17),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Offset p(double x, double y) => Offset(x * w, y * h);
    final body = Path()
      ..addPolygon([for (final o in _pts) p(o.dx, o.dy)], true);

    canvas.save();
    canvas.clipPath(body);
    canvas.drawRect(Offset.zero & size, Paint()..color = first);
    final alt = Paint()..color = second;
    switch (style) {
      case JerseyStyle.stripes:
        const n = 7;
        final sw = w * 0.6 / n;
        for (var i = 1; i < n; i += 2) {
          canvas.drawRect(Rect.fromLTWH(w * 0.2 + i * sw, 0, sw, h), alt);
        }
      case JerseyStyle.half:
        canvas.drawRect(Rect.fromLTWH(w / 2, 0, w / 2, h), alt);
      case JerseyStyle.plain:
        break;
    }
    if (style != JerseyStyle.stripes) {
      // Kol ağzı bandı
      canvas.drawPath(
        Path()..addPolygon([
          p(0, 0.17),
          p(0.07, 0.135),
          p(0.17, 0.385),
          p(0.10, 0.42),
        ], true),
        alt,
      );
      canvas.drawPath(
        Path()..addPolygon([
          p(1, 0.17),
          p(0.93, 0.135),
          p(0.83, 0.385),
          p(0.90, 0.42),
        ], true),
        alt,
      );
    }
    // Kumaş ışığı ve kıvrımlar
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.14),
            Colors.black.withValues(alpha: 0.18),
          ],
        ).createShader(Offset.zero & size),
    );
    final fold = Paint()
      ..color = Colors.black.withValues(alpha: 0.22)
      ..strokeWidth = math.max(2, w / 60)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w / 90);
    canvas.drawLine(p(0.21, 0.36), p(0.24, 1), fold);
    canvas.drawLine(p(0.79, 0.36), p(0.76, 1), fold);
    canvas.restore();

    // Yaka
    canvas.drawArc(
      Rect.fromLTRB(0.38 * w, -0.05 * h, 0.62 * w, 0.09 * h),
      0,
      math.pi,
      false,
      Paint()
        ..color = _dark(first, 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.5, w / 45),
    );
    canvas.drawPath(
      body,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Sırtta ad ve numara; okunur renk
    final bright = first.computeLuminance() > 0.45;
    final ink = style == JerseyStyle.plain && _contrast(first, second) > 2.2
        ? second
        : (bright ? _dark(first, 0.25) : Colors.white);
    final edge = ink == Colors.white || ink.computeLuminance() > 0.6
        ? _dark(first, 0.3)
        : Colors.white;
    void text(String s, double size, double top, double maxW) {
      if (s.isEmpty) return;
      var fs = size;
      TextPainter make(Paint? stroke) => TextPainter(
        text: TextSpan(
          text: s,
          style: GoogleFonts.barlowCondensed(
            fontSize: fs,
            fontWeight: FontWeight.w800,
            height: 1,
            foreground: stroke,
            color: stroke == null ? ink : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      var tp = make(null);
      while (tp.width > maxW && fs > 6) {
        fs -= 1;
        tp = make(null);
      }
      final stroke = make(
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, fs / 14)
          ..color = edge,
      );
      final at = Offset(w / 2 - tp.width / 2, top);
      stroke.paint(canvas, at);
      tp.paint(canvas, at);
    }

    text(label, w * 0.13, h * 0.15, w * 0.52);
    text(number, w * 0.40, h * 0.29, w * 0.5);
  }

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  @override
  bool shouldRepaint(_JerseyPainter old) =>
      old.first != first ||
      old.second != second ||
      old.style != style ||
      old.label != label ||
      old.number != number;
}

/// Formanın asıldığı askı.
class _Hanger extends StatelessWidget {
  const _Hanger({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(width, width * 0.2), painter: _HangerPainter());
}

class _HangerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final paint = Paint()
      ..color = const Color(0xFFC8C8C8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, w / 160)
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(w / 2, h * 0.18),
        width: h * 0.3,
        height: h * 0.3,
      ),
      math.pi,
      math.pi,
      false,
      paint,
    );
    canvas.drawLine(
      Offset(w / 2 + h * 0.15, h * 0.18),
      Offset(w / 2, h * 0.55),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.2, h)
        ..lineTo(w / 2, h * 0.55)
        ..lineTo(w * 0.8, h),
      paint..strokeWidth = math.max(2, w / 110),
    );
  }

  @override
  bool shouldRepaint(_HangerPainter old) => false;
}

/// Askıda forma ([JerseyArt]) — askı formanın yakasına oturur.
class _HungJersey extends StatelessWidget {
  const _HungJersey({required this.side, required this.width, this.angle = 0});

  final PosterSide side;
  final double width;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Hanger(width: width),
          Transform.translate(
            offset: Offset(0, -width * 0.03),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: JerseyArt(
                width: width,
                first: side.first,
                second: side.second,
                style: side.jersey,
                label: side.shortLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ parçalar

/// Tarih • saat ve altında stat (altın ikonlar).
class _InfoRows extends StatelessWidget {
  const _InfoRows({required this.info});

  final MatchPosterInfo info;

  @override
  Widget build(BuildContext context) {
    final st = PosterOptions.of(context);
    final size = st.pick(18, 15);
    final date = [
      info.dateText,
      info.dayName.trUpper,
    ].where((e) => e.trim().isNotEmpty).join(' ');
    final time = info.timeText.trim().isEmpty ? '--:--' : info.timeText.trim();
    final pitch = info.pitchName.trim().isEmpty
        ? 'SAHA BELİRLENMEDİ'
        : info.pitchName.trim().trUpper;
    Widget item(IconData icon, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _gold, size: size + 2),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _cond(size, shadows: _shadow),
          ),
        ),
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              item(
                Icons.calendar_month_rounded,
                date.isEmpty ? 'TARİH BELİRLENMEDİ' : date,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _gold,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              item(Icons.schedule_rounded, time),
            ],
          ),
        ),
        SizedBox(height: st.pick(8, 5)),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: item(Icons.location_on_rounded, pitch),
        ),
      ],
    );
  }
}

/// İki yanında çizgi olan ortalı yazı.
class _RuleText extends StatelessWidget {
  const _RuleText(this.text, {required this.size});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    Widget line() => Expanded(
      child: Container(height: 1.2, color: _gold.withValues(alpha: 0.9)),
    );
    return Row(
      children: [
        line(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(text, maxLines: 1, style: _cond(size, color: _gold)),
        ),
        line(),
      ],
    );
  }
}

/// Üst köşelerde projektör ışığı.
class _Lights extends StatelessWidget {
  const _Lights({this.color = const Color(0xFFFFE6A0)});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (final a in const [Alignment(-1.25, -1.12), Alignment(1.25, -1.12)])
          Align(
            alignment: a,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.9),
                    color.withValues(alpha: 0.35),
                    color.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.18, 1],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Takım renginde yumuşak parıltı.
Widget _glow(Color c, Alignment a, double size) => Align(
  alignment: a,
  child: Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [c.withValues(alpha: 0.38), c.withValues(alpha: 0)],
      ),
    ),
  ),
);

/// Turnuva arması + adı + hafta (üstte).
class _LeagueHead extends StatelessWidget {
  const _LeagueHead({required this.info});

  final MatchPosterInfo info;

  @override
  Widget build(BuildContext context) {
    final st = PosterOptions.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PosterLogo(
          url: info.leagueLogo,
          name: info.leagueName,
          size: st.pick(36, 28),
          shadow: true,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                info.leagueName.trim().trUpper,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _cond(st.pick(14, 12), shadows: _shadow),
              ),
              if (info.weekText.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  info.weekText,
                  style: _cond(st.pick(11, 10), color: _gold),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ A

/// Formalar: iki takımın forması askıda, altta armalar.
class JerseysPoster extends StatelessWidget {
  const JerseysPoster({super.key, required this.info});

  final MatchPosterInfo info;

  @override
  Widget build(BuildContext context) {
    final st = PosterOptions.of(context);
    final h = info.home, a = info.away;
    final jw = st.pick(150, 104);
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF10141E), Color(0xFF06080E)],
            ),
          ),
        ),
        _glow(h.first, const Alignment(-1.2, 0.05), 330),
        _glow(a.first, const Alignment(1.2, 0.05), 330),
        const _Lights(),
        Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            st.pick(40, 18),
            18,
            st.pick(14, 10),
          ),
          child: Column(
            children: [
              _RuleText(
                [
                  info.leagueName.trim().trUpper,
                  info.weekText,
                ].where((e) => e.isNotEmpty).join(' · '),
                size: st.pick(13, 11),
              ),
              SizedBox(height: st.pick(6, 2)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'MAÇ GÜNÜ',
                  style: _cond(st.pick(70, 46), italic: true, shadows: _shadow),
                ),
              ),
              SizedBox(height: st.pick(10, 4)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _HungJersey(side: h, width: jw, angle: 0.1),
                  _HungJersey(side: a, width: jw, angle: -0.1),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  for (final (i, s) in [h, a].indexed) ...[
                    if (i == 1)
                      Text(
                        'VS',
                        style: _cond(
                          st.pick(40, 30),
                          italic: true,
                          color: _gold,
                          shadows: _shadow,
                        ),
                      ),
                    Expanded(
                      child: Column(
                        children: [
                          PosterLogo(
                            url: s.logo,
                            name: s.name,
                            size: st.pick(82, 58),
                            shadow: true,
                          ),
                          SizedBox(height: st.pick(8, 4)),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              s.shortLabel,
                              maxLines: 1,
                              style: _cond(st.pick(21, 16), shadows: _shadow),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(height: st.pick(18, 8)),
              _InfoRows(info: info),
              SizedBox(height: st.pick(16, 8)),
              _RuleText('TÜM SPORSEVERLER DAVETLİDİR', size: st.pick(15, 12)),
              SizedBox(height: st.pick(14, 8)),
              const PosterAppMark(),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ B

/// Çapraz: zemin iki takımın rengine çapraz bölünür, büyük armalar.
class SplitPoster extends StatelessWidget {
  const SplitPoster({super.key, required this.info});

  final MatchPosterInfo info;

  Widget _splitTeam(PosterSide s, double crest) => SizedBox(
    width: 190,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PosterLogo(url: s.logo, name: s.name, size: crest, shadow: true),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            s.shortLabel,
            maxLines: 1,
            style: _cond(30, italic: true, shadows: _shadow),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final st = PosterOptions.of(context);
    final h = info.home, a = info.away;
    final crest = st.pick(112, 84);
    return LayoutBuilder(
      builder: (context, box) {
        final band = st.pick(140.0, 104.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_dark(h.first, 0.95), _dark(h.first, 0.35)],
                ),
              ),
            ),
            ClipPath(
              clipper: _DiagonalClipper(),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_dark(a.first, 0.9), _dark(a.first, 0.3)],
                  ),
                ),
              ),
            ),
            CustomPaint(painter: _SplitDecorPainter()),
            _glow(Colors.white, const Alignment(0, 0.05), 260),
            Padding(
              padding: EdgeInsets.only(top: st.pick(18, 10)),
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: st.pick(10, 6),
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xC0060910),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PosterLogo(
                        url: info.leagueLogo,
                        name: info.leagueName,
                        size: st.pick(50, 34),
                        shadow: true,
                      ),
                      SizedBox(height: st.pick(6, 3)),
                      Text(
                        info.leagueName.trim().trUpper,
                        maxLines: 1,
                        style: _cond(st.pick(14, 12)),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          info.weekText,
                          'MAÇ GÜNÜ',
                        ].where((e) => e.isNotEmpty).join(' · '),
                        style: _cond(st.pick(13, 11), color: _gold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Ev sahibi solda, VS ortada, deplasman sağda; üst üste binmez,
            // sığmazsa birlikte küçülür.
            Positioned(
              left: 0,
              right: 0,
              top: st.pick(128, 88),
              bottom: band + st.pick(8, 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: 340,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _splitTeam(h, crest),
                      ),
                      SizedBox(height: st.pick(4, 2)),
                      Container(
                        width: st.pick(70, 56),
                        height: st.pick(70, 56),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C101A),
                          shape: BoxShape.circle,
                          border: Border.all(color: _gold, width: 2.5),
                          boxShadow: const [
                            BoxShadow(color: Color(0x99000000), blurRadius: 16),
                          ],
                        ),
                        child: Text(
                          'VS',
                          style: _cond(
                            st.pick(32, 25),
                            italic: true,
                            color: _gold,
                          ),
                        ),
                      ),
                      SizedBox(height: st.pick(4, 2)),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _splitTeam(a, crest),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Alt bilgi bandı
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: band,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  18,
                  st.pick(16, 10),
                  18,
                  st.pick(12, 8),
                ),
                decoration: const BoxDecoration(
                  color: Color(0xEB060910),
                  border: Border(top: BorderSide(color: _gold, width: 2)),
                ),
                child: Column(
                  children: [
                    _InfoRows(info: info),
                    const Spacer(),
                    _RuleText(
                      'TÜM SPORSEVERLER DAVETLİDİR',
                      size: st.pick(13, 11),
                    ),
                    SizedBox(height: st.pick(8, 5)),
                    const PosterAppMark(),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DiagonalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(s.width * 0.62, 0)
    ..lineTo(s.width, 0)
    ..lineTo(s.width, s.height)
    ..lineTo(s.width * 0.38, s.height)
    ..close();

  @override
  bool shouldReclip(_DiagonalClipper old) => false;
}

/// Çapraz afişte ince şerit dokusu ve beyaz ayırıcı çizgi.
class _SplitDecorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final tex = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 5;
    for (var x = -s.height; x < s.width; x += 16) {
      canvas.drawLine(Offset(x, s.height), Offset(x + s.height * 0.4, 0), tex);
    }
    canvas.drawLine(
      Offset(s.width * 0.62, 0),
      Offset(s.width * 0.38, s.height),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 3.5,
    );
  }

  @override
  bool shouldRepaint(_SplitDecorPainter old) => false;
}

// ------------------------------------------------------------------ D

/// Sorumlular: ev sahibi sorumlusu üstte, deplasman altta; ortada saat
/// bandı. Fotoğraf yoksa o tarafta büyük arma.
class ManagersPoster extends StatelessWidget {
  const ManagersPoster({super.key, required this.info});

  final MatchPosterInfo info;

  @override
  Widget build(BuildContext context) {
    final st = PosterOptions.of(context);
    final time = info.timeText.trim().isEmpty ? '--:--' : info.timeText.trim();
    final when = [
      info.dateText,
      info.dayName.trUpper,
      info.pitchName.trim().isEmpty ? '' : info.pitchName.trim().trUpper,
    ].where((e) => e.trim().isNotEmpty).join(' · ');
    return ColoredBox(
      color: const Color(0xFF070B14),
      child: Column(
        children: [
          Expanded(
            child: _ManagerHalf(
              info: info,
              side: info.home,
              manager: info.homeManager,
              top: true,
            ),
          ),
          Container(
            height: st.pick(96, 72),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: Color(0xFF070B14),
              border: Border.symmetric(
                horizontal: BorderSide(color: _gold, width: 2),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          info.weekText,
                          'MAÇ GÜNÜ',
                        ].where((e) => e.isNotEmpty).join(' · '),
                        style: _cond(st.pick(11, 10), color: _gold, spacing: 2),
                      ),
                      SizedBox(height: st.pick(4, 2)),
                      Text(time, style: _cond(st.pick(34, 26))),
                      if (when.isNotEmpty) ...[
                        SizedBox(height: st.pick(4, 2)),
                        Text(
                          when,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _cond(st.pick(12, 10.5), color: _muted),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  'VS',
                  style: _cond(st.pick(46, 36), italic: true, color: _gold),
                ),
              ],
            ),
          ),
          Expanded(
            child: _ManagerHalf(
              info: info,
              side: info.away,
              manager: info.awayManager,
              top: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _ManagerHalf extends StatelessWidget {
  const _ManagerHalf({
    required this.info,
    required this.side,
    required this.manager,
    required this.top,
  });

  final MatchPosterInfo info;
  final PosterSide side;
  final PosterManager? manager;

  /// Üstte (ev sahibi): fotoğraf solda, turnuva başlığı üstte.
  final bool top;

  Widget _photo(double crest) {
    final small = (manager?.photo ?? '').trim();
    final fallback = Center(
      child: PosterLogo(
        url: side.logo,
        name: side.name,
        size: crest,
        shadow: true,
      ),
    );
    if (small.isEmpty) return fallback;
    Widget net(String url, Widget Function() onError) => Image.network(
      url,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, _, _) => onError(),
    );
    // Afiş 1080 px basılır: varsa fotoğrafın büyük kopyası.
    final hd = SupabaseImageUploadService.hdUrl(small);
    Widget smallImg() => net(small, () => fallback);
    return hd == small ? smallImg() : net(hd, smallImg);
  }

  @override
  Widget build(BuildContext context) {
    final st = PosterOptions.of(context);
    final head = st.pick(52.0, 40.0);
    final hasPhoto = (manager?.photo ?? '').trim().isNotEmpty;
    // Fotoğraf yazının altına doğru uzar ve kenarlarından zemine erir;
    // vesikalık gibi keskin kutu görünmesin.
    final photoW = hasPhoto ? st.pick(230.0, 190.0) : st.pick(168.0, 140.0);
    final inner = top ? Alignment.centerRight : Alignment.centerLeft;
    final outer = top ? Alignment.centerLeft : Alignment.centerRight;
    Widget blend(Widget child) => ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => LinearGradient(
        begin: outer,
        end: inner,
        colors: const [Colors.white, Colors.white, Colors.transparent],
        stops: const [0, 0.5, 0.98],
      ).createShader(r),
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.white],
          stops: [0, 0.22],
        ).createShader(r),
        child: child,
      ),
    );
    final photo = Positioned(
      top: top ? head * 0.4 : 0,
      bottom: 0,
      left: top ? 0 : null,
      right: top ? null : 0,
      width: photoW,
      child: hasPhoto
          ? blend(_photo(st.pick(118, 88)))
          : Padding(
              padding: EdgeInsets.only(top: top ? head : st.pick(14, 10)),
              child: _photo(st.pick(118, 88)),
            ),
    );
    final gap = SizedBox(width: st.pick(168, 140));
    final text = Expanded(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          top ? 4 : 16,
          0,
          top ? 16 : 4,
          top ? st.pick(16, 10) : st.pick(46, 36),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: top
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            PosterLogo(
              url: side.logo,
              name: side.name,
              size: st.pick(44, 34),
              shadow: true,
            ),
            SizedBox(height: st.pick(6, 4)),
            Text(
              side.fullLabel,
              maxLines: 2,
              textAlign: top ? TextAlign.right : TextAlign.left,
              style: _cond(st.pick(24, 19), shadows: _shadow),
            ),
            if ((manager?.name ?? '').trim().isNotEmpty) ...[
              SizedBox(height: st.pick(5, 3)),
              Text(
                manager!.name.trim().trUpper,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _cond(st.pick(13, 11.5), shadows: _shadow),
              ),
              const SizedBox(height: 2),
              Text(
                'TAKIM SORUMLUSU',
                style: _cond(st.pick(10, 9), color: _muted, spacing: 1.5),
              ),
            ],
          ],
        ),
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [const Color(0xFF0B1220), _dark(side.first, 0.85)],
            ),
          ),
        ),
        photo,
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: top ? [gap, text] : [text, gap],
        ),
        if (top)
          Positioned(
            left: 16,
            right: 16,
            top: st.pick(14, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _LeagueHead(info: info),
            ),
          )
        else
          Positioned(
            left: 16,
            bottom: st.pick(12, 8),
            child: const PosterAppMark(),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------------ C

/// Takım: seçilen takımın kendi renklerinde "maç günü" afişi ve sloganı.
class TeamDayPoster extends StatelessWidget {
  const TeamDayPoster({
    super.key,
    required this.info,
    required this.homeSide,
    required this.slogan,
  });

  final MatchPosterInfo info;

  /// Afiş ev sahibinin mi (değilse deplasman takımının).
  final bool homeSide;
  final String slogan;

  @override
  Widget build(BuildContext context) {
    final st = PosterOptions.of(context);
    final t = homeSide ? info.home : info.away;
    final o = homeSide ? info.away : info.home;
    final sloganText = slogan.trim().isEmpty
        ? 'HAYDİ ${t.shortLabel}!'
        : slogan.trim().trUpper;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_dark(t.first, 0.75), const Color(0xFF080608)],
            ),
          ),
        ),
        // İkinci renkte dikey şeritler, aşağı doğru kaybolur
        ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.transparent],
          ).createShader(r),
          blendMode: BlendMode.dstIn,
          child: Row(
            children: [
              for (var i = 0; i < 8; i++)
                Expanded(
                  child: ColoredBox(
                    color: i.isOdd
                        ? t.second.withValues(alpha: 0.1)
                        : Colors.transparent,
                  ),
                ),
            ],
          ),
        ),
        const _Lights(color: Color(0xFFFFDCC8)),
        Padding(
          padding: EdgeInsets.fromLTRB(16, st.pick(20, 10), 16, st.pick(12, 8)),
          child: Column(
            children: [
              _LeagueHead(info: info),
              SizedBox(height: st.pick(18, 6)),
              Text(
                'MAÇ GÜNÜ',
                style: _cond(st.pick(60, 40), italic: true, shadows: _shadow),
              ),
              SizedBox(height: st.pick(8, 2)),
              Expanded(
                child: FittedBox(child: _HungJersey(side: t, width: 180)),
              ),
              SizedBox(height: st.pick(10, 4)),
              // Afişi paylaşan takım: kutunun hemen üstünde, rakip adından büyük.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  t.fullLabel,
                  maxLines: 1,
                  style: _cond(st.pick(30, 20), italic: true, shadows: _shadow),
                ),
              ),
              SizedBox(height: st.pick(8, 4)),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: st.pick(10, 6),
                ),
                decoration: BoxDecoration(
                  color: const Color(0xD8080A10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.first, width: 1.4),
                ),
                child: Row(
                  children: [
                    PosterLogo(
                      url: t.logo,
                      name: t.name,
                      size: st.pick(58, 40),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            'VS',
                            style: _cond(
                              st.pick(34, 26),
                              italic: true,
                              color: _gold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              o.fullLabel,
                              maxLines: 1,
                              style: _cond(st.pick(12, 11), color: _muted),
                            ),
                          ),
                        ],
                      ),
                    ),
                    PosterLogo(
                      url: o.logo,
                      name: o.name,
                      size: st.pick(58, 40),
                    ),
                  ],
                ),
              ),
              SizedBox(height: st.pick(14, 8)),
              _InfoRows(info: info),
              SizedBox(height: st.pick(12, 6)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  sloganText,
                  maxLines: 1,
                  style: _cond(
                    st.pick(24, 19),
                    italic: true,
                    color: _gold,
                    shadows: _shadow,
                  ),
                ),
              ),
              SizedBox(height: st.pick(10, 6)),
              const PosterAppMark(),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ küçük önizleme

/// Tasarım seçiminde küçük önizleme: afişi hikâye boyutunda çizip sığdırır.
class PosterThumb extends StatelessWidget {
  const PosterThumb({super.key, required this.child, this.background});

  final Widget child;
  final ImageProvider? background;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox.fromSize(
        size: PosterFormat.story.size,
        child: PosterOptions(
          style: PosterStyle(plain: background == null),
          child: PosterBackground(image: background, child: child),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ paylaşım akışı

/// Maç afişi paylaşımı. [designsEnabled] kapalıysa doğrudan Klasik afiş
/// açılır; açıksa önce tasarım seçilir (2×2), sonra seçilen afiş önizlenip
/// paylaşılır. Önizlemedeki geri oku tasarım seçimine döndürür.
Future<void> showMatchPosterShare({
  required BuildContext context,
  required MatchPosterInfo info,
  required Widget classic,
  required String fileSlug,
  required String leagueId,
  required List<String> imageUrls,
  required bool designsEnabled,
  bool managersEnabled = false,
}) async {
  Future<bool?> preview(MatchPosterDesign d) async {
    final common = (
      fileName: d == MatchPosterDesign.classic
          ? 'mac_$fileSlug'
          : 'mac_${d.name}_$fileSlug',
      urls: [
        info.leagueLogo,
        info.home.logo,
        info.away.logo,
        ...imageUrls,
        if (d == MatchPosterDesign.managers)
          for (final m in [info.homeManager, info.awayManager])
            if ((m?.photo ?? '').trim().isNotEmpty)
              SupabaseImageUploadService.hdUrl(m!.photo),
      ],
    );
    if (d != MatchPosterDesign.team) {
      return showPosterPreview(
        context: context,
        title: 'Maç Afişini Paylaş',
        backTitle: designsEnabled ? d.label : null,
        fileName: common.fileName,
        imageUrls: common.urls,
        leagueId: leagueId,
        kind: PosterKind.match,
        formats: const [PosterFormat.post, PosterFormat.story],
        poster: switch (d) {
          MatchPosterDesign.jerseys => JerseysPoster(info: info),
          MatchPosterDesign.split => SplitPoster(info: info),
          MatchPosterDesign.managers => ManagersPoster(info: info),
          _ => classic,
        },
      );
    }
    final pick = ValueNotifier<({bool home, String slogan})>((
      home: true,
      slogan: await _savedSlogan(info.home),
    ));
    if (!context.mounted) return null;
    try {
      return await showPosterPreview(
        context: context,
        title: 'Maç Afişini Paylaş',
        backTitle: d.label,
        fileName: common.fileName,
        imageUrls: common.urls,
        leagueId: leagueId,
        kind: PosterKind.match,
        formats: const [PosterFormat.post, PosterFormat.story],
        controls: _TeamPosterControls(info: info, pick: pick),
        poster: ValueListenableBuilder(
          valueListenable: pick,
          builder: (_, v, _) =>
              TeamDayPoster(info: info, homeSide: v.home, slogan: v.slogan),
        ),
      );
    } finally {
      pick.dispose();
    }
  }

  if (!designsEnabled) {
    await preview(MatchPosterDesign.classic);
    return;
  }
  var selected = MatchPosterDesign.classic;
  while (true) {
    if (!context.mounted) return;
    final d = await showDialog<MatchPosterDesign>(
      context: context,
      builder: (_) => _DesignPickerDialog(
        info: info,
        classic: classic,
        leagueId: leagueId,
        selected: selected,
        managersEnabled: managersEnabled,
      ),
    );
    if (d == null || !context.mounted) return;
    selected = d;
    final back = await preview(d);
    if (back != true) return;
  }
}

String _sloganKey(PosterSide s) => 'poster_slogan_${s.id}';

/// Takımın bu cihazda son kullanılan sloganı; yoksa `HAYDİ TAKIM!`.
Future<String> _savedSlogan(PosterSide s) async {
  try {
    final p = await SharedPreferences.getInstance();
    final v = (p.getString(_sloganKey(s)) ?? '').trim();
    if (v.isNotEmpty) return v;
  } catch (_) {}
  return _presets(s).first;
}

List<String> _presets(PosterSide s) {
  // Ad sığmazsa ilk kelimesi ("FORZA GAZİOSMANPAŞA"); o da sığmazsa kesilir.
  final first = s.shortLabel.split(' ').first;
  String fit(String Function(String) make) {
    for (final name in [s.shortLabel, first]) {
      final v = make(name);
      if (v.characters.length <= kPosterSloganMax) return v;
    }
    return make(first).characters.take(kPosterSloganMax).toString();
  }

  return [fit((n) => 'HAYDİ $n!'), fit((n) => 'FORZA $n')];
}

/// İlk adım: dört tasarım küçük önizlemeleriyle (2×2).
class _DesignPickerDialog extends StatefulWidget {
  const _DesignPickerDialog({
    required this.info,
    required this.classic,
    required this.leagueId,
    required this.selected,
    this.managersEnabled = false,
  });

  final MatchPosterInfo info;
  final Widget classic;
  final String leagueId;
  final MatchPosterDesign selected;

  /// Sorumlular tasarımı (yeni; şimdilik yalnız admin).
  final bool managersEnabled;

  @override
  State<_DesignPickerDialog> createState() => _DesignPickerDialogState();
}

class _DesignPickerDialogState extends State<_DesignPickerDialog> {
  late final Future<ImageProvider?> _bg = PosterBackgrounds.resolve(
    kind: PosterKind.match,
    leagueId: widget.leagueId,
  ).then((u) => u == null ? null : NetworkImage(u));

  Widget _poster(MatchPosterDesign d) => switch (d) {
    MatchPosterDesign.classic => widget.classic,
    MatchPosterDesign.jerseys => JerseysPoster(info: widget.info),
    MatchPosterDesign.split => SplitPoster(info: widget.info),
    MatchPosterDesign.team => TeamDayPoster(
      info: widget.info,
      homeSide: true,
      slogan: '',
    ),
    MatchPosterDesign.managers => ManagersPoster(info: widget.info),
  };

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: AdminDialogCloseOverlay(
        onClose: () => Navigator.pop(context),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: adminDialogDecoration(),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Maç Afişini Paylaş',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Afiş tasarımını seç',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 14),
                FutureBuilder<ImageProvider?>(
                  future: _bg,
                  builder: (context, snap) {
                    final bg = snap.data;
                    Widget tile(MatchPosterDesign d) {
                      final sel = d == widget.selected;
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.pop(context, d),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AspectRatio(
                              aspectRatio: 9 / 16,
                              child: Container(
                                foregroundDecoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: sel
                                        ? kAdminAccent
                                        : Colors.white.withValues(alpha: 0.16),
                                    width: sel ? 2.5 : 1,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: IgnorePointer(
                                    child: PosterThumb(
                                      background: d == MatchPosterDesign.classic
                                          ? bg
                                          : null,
                                      child: _poster(d),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              d.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              d.subtitle,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final all = MatchPosterDesign.values
                        .where(
                          (d) =>
                              d != MatchPosterDesign.managers ||
                              widget.managersEnabled,
                        )
                        .toList();
                    return Column(
                      children: [
                        for (var r = 0; r * 2 < all.length; r++) ...[
                          if (r > 0) const SizedBox(height: 14),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: tile(all[r * 2])),
                              const SizedBox(width: 12),
                              Expanded(
                                child: r * 2 + 1 < all.length
                                    ? tile(all[r * 2 + 1])
                                    : const SizedBox(),
                              ),
                            ],
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Takım afişinde takım seçimi ve slogan (hazır seçenek ya da en çok
/// [kPosterSloganMax] karakter).
class _TeamPosterControls extends StatefulWidget {
  const _TeamPosterControls({required this.info, required this.pick});

  final MatchPosterInfo info;
  final ValueNotifier<({bool home, String slogan})> pick;

  @override
  State<_TeamPosterControls> createState() => _TeamPosterControlsState();
}

class _TeamPosterControlsState extends State<_TeamPosterControls> {
  late final _ctrl = TextEditingController(text: widget.pick.value.slogan);

  PosterSide get _team =>
      widget.pick.value.home ? widget.info.home : widget.info.away;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _setSlogan(String v) {
    widget.pick.value = (home: widget.pick.value.home, slogan: v);
    final key = _sloganKey(_team);
    SharedPreferences.getInstance()
        .then((p) => p.setString(key, v.trim()))
        .catchError((_) => true);
    setState(() {});
  }

  Future<void> _setTeam(bool home) async {
    if (home == widget.pick.value.home) return;
    final s = await _savedSlogan(home ? widget.info.home : widget.info.away);
    if (!mounted) return;
    _ctrl.text = s;
    widget.pick.value = (home: home, slogan: s);
    setState(() {});
  }

  Widget _segment(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: Material(
        color: selected
            ? kAdminAccent.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected
                ? kAdminAccent
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final home = widget.pick.value.home;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _segment(
              posterTeamName(widget.info.home.name),
              home,
              () => _setTeam(true),
            ),
            const SizedBox(width: 8),
            _segment(
              posterTeamName(widget.info.away.name),
              !home,
              () => _setTeam(false),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              const Icon(Icons.edit_rounded, color: Colors.white54, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SLOGAN',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      TextField(
                        controller: _ctrl,
                        onChanged: _setSlogan,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(kPosterSloganMax),
                          _TrUpperFormatter(),
                        ],
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                        cursorColor: kAdminAccent,
                        // Uygulamanın genel kutu stili burada istenmiyor.
                        decoration: const InputDecoration(
                          isDense: true,
                          filled: false,
                          contentPadding: EdgeInsets.only(top: 2),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${_ctrl.text.characters.length}/$kPosterSloganMax',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              PopupMenuButton<String>(
                tooltip: 'Hazır sloganlar',
                color: const Color(0xFF111827),
                icon: const Icon(
                  Icons.expand_more_rounded,
                  color: Colors.white,
                ),
                onSelected: (v) {
                  _ctrl.text = v;
                  _setSlogan(v);
                },
                itemBuilder: (_) => [
                  for (final v in _presets(_team))
                    PopupMenuItem(
                      value: v,
                      child: Text(
                        v,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Slogan büyük harfle (Türkçe i → İ).
class _TrUpperFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.trUpper);
}
