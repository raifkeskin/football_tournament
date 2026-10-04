import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/utils/string_utils.dart';
import '../../core/utils/team_name.dart';
import '../../core/widgets/app_name_band.dart' show kShowAppName;
import '../../core/widgets/tvl_logo.dart';
import 'poster_share.dart';

/// Tek maç afişi ("2. Hafta Maçı"). Zemin sabittir (stadyum fotoğrafı);
/// turnuva logosu, grup, hafta, takımlar, saha, tarih ve saat maça göre
/// değişir. Boyut [kPosterSize].
class MatchPoster extends StatelessWidget {
  const MatchPoster({
    super.key,
    required this.leagueName,
    required this.leagueLogo,
    required this.groupName,
    required this.week,
    required this.homeName,
    required this.homeLogo,
    required this.awayName,
    required this.awayLogo,
    required this.pitchName,
    required this.dayName,
    required this.dateText,
    required this.timeText,
  });

  final String leagueName;
  final String leagueLogo;

  /// Ör. "Avrupa Yakası"; tek gruplu sezonda boş.
  final String groupName;
  final int? week;
  final String homeName;
  final String homeLogo;
  final String awayName;
  final String awayLogo;
  final String pitchName;

  /// "PAZAR" / "04.10.2026" / "19:40"; tarih yoksa boş.
  final String dayName;
  final String dateText;
  final String timeText;

  static const _gold = Color(0xFFF6C744);
  static const _goldDeep = Color(0xFFC98A12);
  static const _navy = Color(0xFF0A1433);
  static const _red = Color(0xFFD7182A);

  TextStyle _cond(
    double size, {
    Color color = Colors.white,
    FontWeight w = FontWeight.w800,
    bool italic = false,
    double spacing = 0,
    List<Shadow>? shadows,
  }) => GoogleFonts.barlowCondensed(
    fontSize: size,
    color: color,
    fontWeight: w,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    letterSpacing: spacing,
    height: 1,
    shadows: shadows,
  );

  static const _shadow = [
    Shadow(color: Color(0xAA000000), blurRadius: 10, offset: Offset(0, 3)),
  ];

  Widget _goldText(String text, double size) {
    return ShaderMask(
      shaderCallback: (r) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFF1B8), _gold, _goldDeep],
        stops: [0, 0.45, 1],
      ).createShader(r),
      child: Text(
        text,
        maxLines: 1,
        textAlign: TextAlign.center,
        style: _cond(size, italic: true, w: FontWeight.w800, spacing: 0.5),
      ),
    );
  }

  Widget _team(String name, String logo) {
    return Expanded(
      child: Column(
        children: [
          // Çerçevesiz logo; gölge koyu zeminde öne çıkarır.
          PosterLogo(url: logo, name: name, size: 124, shadow: true),
          const SizedBox(height: 10),
          SizedBox(
            height: 42,
            child: Text(
              compactTeamName(name, maxLength: 20).trUpper,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: _cond(19, shadows: _shadow).copyWith(height: 1.05),
            ),
          ),
        ],
      ),
    );
  }

  Widget _info(IconData icon, String top, String bottom) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: _navy, size: 24),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  top,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _cond(12.5, color: _navy).copyWith(height: 1.05),
                ),
                if (bottom.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    bottom,
                    maxLines: 1,
                    style: _cond(15, color: _navy, w: FontWeight.w800),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() =>
      Container(width: 1.5, height: 34, color: _navy.withValues(alpha: 0.25));

  @override
  Widget build(BuildContext context) {
    final title = groupName.trim().isEmpty
        ? leagueName.trim().trUpper
        : groupName.trim().trUpper;
    final weekText = week == null ? 'MAÇ GÜNÜ' : '$week. HAFTA MAÇI';
    final hasDate = dateText.trim().isNotEmpty;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Sabit zemin: stadyum + koyu lacivert geçiş.
        Image.asset('assets/anasayfa.jpg', fit: BoxFit.cover),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _navy.withValues(alpha: 0.92),
                _navy.withValues(alpha: 0.55),
                _navy.withValues(alpha: 0.35),
                _navy.withValues(alpha: 0.85),
              ],
              stops: const [0, 0.38, 0.62, 1],
            ),
          ),
        ),
        // Projektör ışıkları
        for (final align in const [Alignment(-1.1, -1), Alignment(1.1, -1)])
          Align(
            alignment: align,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.45),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 14),
          child: Column(
            children: [
              PosterLogo(
                url: leagueLogo,
                name: leagueName,
                size: 116,
                shadow: true,
              ),
              const SizedBox(height: 14),
              FittedBox(fit: BoxFit.scaleDown, child: _goldText(title, 46)),
              const SizedBox(height: 8),
              // Kırmızı kurdele
              Transform(
                transform: Matrix4.skewX(-0.18),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF9E0F1D), _red, Color(0xFF9E0F1D)],
                    ),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Color(0x88000000), blurRadius: 10),
                    ],
                  ),
                  child: Text(
                    weekText,
                    style: _cond(28, italic: true, spacing: 1),
                  ),
                ),
              ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _team(homeName, homeLogo),
                  Padding(
                    padding: const EdgeInsets.only(top: 34),
                    child: _goldText('VS', 52),
                  ),
                  _team(awayName, awayLogo),
                ],
              ),
              const Spacer(),
              // Bilgi bandı: saha | gün-tarih | saat
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x88000000),
                      blurRadius: 14,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _info(
                      Icons.stadium_rounded,
                      pitchName.trim().isEmpty
                          ? 'SAHA BELİRLENMEDİ'
                          : pitchName.trim().trUpper,
                      '',
                    ),
                    _divider(),
                    _info(
                      Icons.calendar_month_rounded,
                      hasDate ? dayName.trUpper : 'TARİH',
                      hasDate ? dateText : 'BELİRLENMEDİ',
                    ),
                    _divider(),
                    _info(
                      Icons.schedule_rounded,
                      'SAAT',
                      timeText.trim().isEmpty ? '--:--' : timeText.trim(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const TvlLogo(size: 22),
                  if (kShowAppName) const SizedBox(width: 6),
                  if (kShowAppName)
                    Text(
                      'TÜRK VETERANLAR LİGİ',
                      style: _cond(
                        12,
                        italic: true,
                        spacing: 2,
                        color: Colors.white70,
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
