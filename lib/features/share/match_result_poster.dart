import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/utils/string_utils.dart';
import '../../core/utils/team_name.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/app_name_band.dart' show kShowAppName;
import 'poster_background.dart';
import 'poster_share.dart';

/// Afişte bir golcü: "Kaya" + "12' 58'" ya da "×3" (dakikasız sezon).
typedef PosterScorer = ({String name, String detail});

/// Biten tek maçın sonuç afişi: turnuva logosu ve adı, grup · sezon, hafta;
/// "MAÇ SONUCU" ve skor; takım logoları, adları ve (seçiliyse) gol atanlar.
/// Saha / tarih / saat yazmaz. Zemin ve boyut [PosterOptions]'tan gelir.
class MatchResultPoster extends StatelessWidget {
  const MatchResultPoster({
    super.key,
    required this.leagueName,
    required this.leagueLogo,
    required this.subtitle,
    required this.week,
    required this.homeName,
    required this.homeLogo,
    required this.awayName,
    required this.awayLogo,
    required this.homeScore,
    required this.awayScore,
    this.homeScorers = const [],
    this.awayScorers = const [],
  });

  final String leagueName;
  final String leagueLogo;

  /// "Avrupa Yakası · 2026 Sezonu" (grup yalnız birden fazla grup varsa).
  final String subtitle;
  final int? week;
  final String homeName;
  final String homeLogo;
  final String awayName;
  final String awayLogo;
  final int homeScore;
  final int awayScore;
  final List<PosterScorer> homeScorers;
  final List<PosterScorer> awayScorers;

  static const _gold = Color(0xFFF6C744);
  static const _goldDeep = Color(0xFFC98A12);
  static const _navy = Color(0xFF0A1433);
  static const _red = Color(0xFFD7182A);
  static const _shadow = [
    Shadow(color: Color(0xAA000000), blurRadius: 10, offset: Offset(0, 3)),
  ];

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
        style: _cond(size, italic: true, spacing: 0.5),
      ),
    );
  }

  Widget _team(
    String name,
    String logo,
    List<PosterScorer> scorers,
    PosterStyle st,
  ) {
    final halo = st.pick(160, 112);
    final logoSize = st.pick(116, 82);
    final teamName = posterTeamName(name).trUpper;
    return Expanded(
      child: Column(
        children: [
          // Çerçevesiz logo; koyu hale zeminden bağımsız olarak öne çıkarır.
          SizedBox(
            width: halo,
            height: logoSize + st.pick(8, 6),
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
                        _navy.withValues(alpha: 0.8),
                        _navy.withValues(alpha: 0.5),
                        _navy.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.55, 1],
                    ),
                  ),
                ),
                PosterLogo(url: logo, name: name, size: logoSize, shadow: true),
              ],
            ),
          ),
          SizedBox(height: st.pick(8, 4)),
          Text(
            teamName,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: _cond(
              teamName.length > 22 ? st.pick(15.5, 12.5) : st.pick(19, 15),
              shadows: _shadow,
            ).copyWith(height: 1.05),
          ),
          if (st.showScorers && scorers.isNotEmpty) ...[
            SizedBox(height: st.pick(6, 3)),
            Text.rich(
              TextSpan(
                children: [
                  for (var i = 0; i < scorers.length; i++) ...[
                    if (i > 0) const TextSpan(text: '  ·  '),
                    TextSpan(text: scorers[i].name),
                    if (scorers[i].detail.isNotEmpty)
                      TextSpan(
                        text: ' ${scorers[i].detail}',
                        style: const TextStyle(color: _gold),
                      ),
                  ],
                ],
              ),
              maxLines: st.isPost ? 3 : 4,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: _cond(
                st.pick(13.5, 11),
                w: FontWeight.w700,
                color: const Color(0xFFE2E8F0),
                shadows: _shadow,
              ).copyWith(height: 1.3),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = PosterOptions.of(context);
    final weekText = week == null ? 'MAÇ SONU' : '$week. HAFTA';
    final digits = GoogleFonts.barlow(
      fontSize: st.pick(104, 72),
      fontWeight: FontWeight.w800,
      color: Colors.white,
      height: 1,
      shadows: _shadow,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        const PosterPhotoLayer(),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _navy.withValues(alpha: st.plain ? 0.3 : 0.9),
                _navy.withValues(alpha: st.plain ? 0 : 0.55),
                _navy.withValues(alpha: st.plain ? 0 : 0.55),
                _navy.withValues(alpha: st.plain ? 0.3 : 0.9),
              ],
              stops: const [0, 0.4, 0.62, 1],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            st.pick(30, 16),
            16,
            st.pick(14, 10),
          ),
          child: Column(
            children: [
              PosterLogo(
                url: leagueLogo,
                name: leagueName,
                size: st.pick(84, 56),
                shadow: true,
              ),
              SizedBox(height: st.pick(8, 4)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: _goldText(leagueName.trim().trUpper, st.pick(30, 22)),
              ),
              if (subtitle.trim().isNotEmpty) ...[
                SizedBox(height: st.pick(5, 3)),
                Text(
                  subtitle.trim().trUpper,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _cond(
                    st.pick(14, 11.5),
                    w: FontWeight.w700,
                    color: _gold,
                    spacing: 1.2,
                    shadows: _shadow,
                  ),
                ),
              ],
              SizedBox(height: st.pick(10, 6)),
              // Kırmızı kurdele: hafta.
              Transform(
                transform: Matrix4.skewX(-0.18),
                alignment: Alignment.center,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: st.pick(5, 3),
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF9E0F1D), _red, Color(0xFF9E0F1D)],
                    ),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    weekText,
                    style: _cond(st.pick(20, 15), italic: true, spacing: 1),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'MAÇ SONUCU',
                style: _cond(
                  st.pick(17, 13.5),
                  color: _gold,
                  spacing: 2.4,
                  shadows: _shadow,
                ),
              ),
              SizedBox(height: st.pick(4, 2)),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$homeScore', style: digits),
                  Container(
                    width: st.pick(30, 22),
                    height: st.pick(8, 6),
                    margin: EdgeInsets.symmetric(horizontal: st.pick(18, 14)),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: const [
                        BoxShadow(color: Color(0x88000000), blurRadius: 8),
                      ],
                    ),
                  ),
                  Text('$awayScore', style: digits),
                ],
              ),
              SizedBox(height: st.pick(18, 8)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _team(homeName, homeLogo, homeScorers, st),
                  const SizedBox(width: 8),
                  _team(awayName, awayLogo, awayScorers, st),
                ],
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppLogo(size: st.pick(22, 16)),
                  if (kShowAppName) ...[
                    const SizedBox(width: 6),
                    Text(
                      'LİG MASASI',
                      style: _cond(
                        st.pick(12, 10),
                        italic: true,
                        spacing: 2,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
