import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/utils/string_utils.dart';
import '../../core/utils/team_name.dart';
import 'poster_share.dart';
import 'poster_background.dart';

/// Tek maç afişi ("2. Hafta Maçı"): turnuva logosu, grup, hafta, takımlar,
/// saha, tarih ve saat. Zemin turnuvanın afiş görseli (yoksa stadyum) ya da
/// sade lacivert; boyut hikâye ya da gönderi ([PosterOptions]).
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

  Widget _team(String name, String logo, PosterStyle st) {
    final halo = st.pick(172, 118);
    return Expanded(
      child: Column(
        children: [
          // Çerçevesiz logo; arkasındaki koyu hale, zemin ne kadar parlak
          // olursa olsun logonun renklerini öne çıkarır.
          SizedBox(
            width: halo,
            height: st.pick(136, 94),
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: halo,
                  height: halo,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _navy.withValues(alpha: 0.85),
                        _navy.withValues(alpha: 0.55),
                        _navy.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.55, 1],
                    ),
                  ),
                ),
                PosterLogo(
                  url: logo,
                  name: name,
                  size: st.pick(124, 86),
                  shadow: true,
                ),
              ],
            ),
          ),
          SizedBox(height: st.pick(10, 6)),
          SizedBox(
            height: st.pick(42, 36),
            child: Text(
              posterTeamName(name).trUpper,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              // Afişte tam ad; uzun adlarda yazı küçülür.
              style: _cond(
                posterTeamName(name).length > 22
                    ? st.pick(15.5, 13.5)
                    : st.pick(19, 16),
                shadows: _shadow,
              ).copyWith(height: 1.05),
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
    final st = PosterOptions.of(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Zemin: turnuvanın afiş görseli (yoksa stadyum) + koyu lacivert geçiş.
        const PosterPhotoLayer(),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _navy.withValues(alpha: 0.92),
                _navy.withValues(alpha: 0.68),
                _navy.withValues(alpha: 0.55),
                _navy.withValues(alpha: 0.85),
              ],
              stops: const [0, 0.38, 0.62, 1],
            ),
          ),
        ),
        // Projektör ışıkları
        if (!st.plain)
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
          padding: EdgeInsets.fromLTRB(
            18,
            st.pick(22, 14),
            18,
            st.pick(14, 10),
          ),
          child: Column(
            children: [
              PosterLogo(
                url: leagueLogo,
                name: leagueName,
                size: st.pick(116, 64),
                shadow: true,
              ),
              SizedBox(height: st.pick(14, 6)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: _goldText(title, st.pick(46, 32)),
              ),
              SizedBox(height: st.pick(8, 6)),
              // Kırmızı kurdele
              Transform(
                transform: Matrix4.skewX(-0.18),
                alignment: Alignment.center,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: st.pick(6, 4),
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
                    style: _cond(st.pick(28, 20), italic: true, spacing: 1),
                  ),
                ),
              ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _team(homeName, homeLogo, st),
                  Padding(
                    padding: EdgeInsets.only(top: st.pick(34, 22)),
                    child: _goldText('VS', st.pick(52, 40)),
                  ),
                  _team(awayName, awayLogo, st),
                ],
              ),
              const Spacer(),
              // Bilgi bandı: saha | gün-tarih | saat
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: st.pick(10, 7),
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
              SizedBox(height: st.pick(14, 8)),
              const PosterAppMark(),
            ],
          ),
        ),
      ],
    );
  }
}
