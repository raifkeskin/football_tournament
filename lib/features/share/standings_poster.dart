import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/utils/string_utils.dart';
import '../team/utils/standings.dart';
import '../../core/utils/team_name.dart';
import 'poster_share.dart';
import 'poster_background.dart';

/// Grup puan durumu afişi (fikstür afişiyle aynı dil): turnuva logosu,
/// başlık, "PUAN DURUMU" bandı ve tablo. Boyut [kPosterSize]; takım sayısı
/// artarsa tablo afişe sığacak şekilde küçülür.
class StandingsPoster extends StatelessWidget {
  const StandingsPoster({
    super.key,
    required this.leagueName,
    required this.leagueLogo,
    required this.subtitle,
    required this.rows,
  });

  final String leagueName;
  final String leagueLogo;

  /// "2026 Güz · A Grubu"
  final String subtitle;
  final List<StandingEntry> rows;

  static const _gold = Color(0xFFE2B845);
  static const _goldHi = Color(0xFFF6D77A);
  static const _navy = Color(0xFF0D1A4A);

  static const _rank = 22.0;
  static const _stat = 22.0;
  static const _av = 28.0;
  static const _pts = 30.0;

  TextStyle _cond(
    double size, {
    Color color = Colors.white,
    FontWeight w = FontWeight.w800,
    bool italic = false,
    double spacing = 0,
  }) => GoogleFonts.barlowCondensed(
    fontSize: size,
    color: color,
    fontWeight: w,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    letterSpacing: spacing,
    height: 1,
  );

  Widget _cell(String t, double w, TextStyle style) => SizedBox(
    width: w,
    child: Text(t, textAlign: TextAlign.center, style: style),
  );

  Widget _header() {
    final st = _cond(
      12,
      color: Colors.white.withValues(alpha: 0.6),
      spacing: 0.6,
    );
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _gold.withValues(alpha: 0.6))),
      ),
      child: Row(
        children: [
          _cell('#', _rank, st),
          const SizedBox(width: 30),
          Expanded(child: Text('TAKIM', style: st)),
          _cell('O', _stat, st),
          _cell('G', _stat, st),
          _cell('B', _stat, st),
          _cell('M', _stat, st),
          _cell('AV', _av, st),
          _cell('P', _pts, st.copyWith(color: _gold)),
        ],
      ),
    );
  }

  /// Lider (ilk sıra, maç oynanmışsa) listenin içinde dolu altın şerit:
  /// daha yüksek satır, büyük ve lacivert yazı. Diğerleri sade çizgili.
  Widget _row(int i, StandingEntry r) {
    final leader = i == 0 && r.played > 0;
    final ink = leader ? _navy : Colors.white;
    final num = _cond(
      leader ? 17 : 15,
      color: leader ? _navy : Colors.white.withValues(alpha: 0.85),
      w: FontWeight.w700,
    );
    final av = r.goalDiff;
    final content = Row(
      children: [
        _cell(
          '${i + 1}',
          _rank,
          _cond(
            leader ? 24 : 17,
            color: leader ? _navy : Colors.white.withValues(alpha: 0.75),
            italic: true,
          ),
        ),
        const SizedBox(width: 4),
        PosterLogo(url: r.logo, name: r.name, size: leader ? 28 : 22),
        const SizedBox(width: 6),
        // Afişte tam ad; sığmazsa yazı küçülür (asla "..." ile kesilmez).
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              posterTeamName(r.name).trUpper,
              maxLines: 1,
              style: _cond(leader ? 20 : 15, color: ink, spacing: 0.2),
            ),
          ),
        ),
        _cell('${r.played}', _stat, num),
        _cell('${r.won}', _stat, num),
        _cell('${r.drawn}', _stat, num),
        _cell('${r.lost}', _stat, num),
        _cell(av > 0 ? '+$av' : '$av', _av, num),
        _cell(
          '${r.points}',
          _pts,
          _cond(leader ? 24 : 17, color: leader ? _navy : _goldHi),
        ),
      ],
    );
    if (leader) {
      return Container(
        height: 42,
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: const LinearGradient(
            begin: Alignment(-1, -0.4),
            end: Alignment(1, 0.4),
            colors: [Color(0xFFF0CD62), Color(0xFFC99A2E)],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: content,
      );
    }
    return Container(
      height: 31,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = PosterOptions.of(context);
    final plain = st.plain;
    // Zemin fikstür afişiyle aynı: turnuvanın afiş görseli (yoksa stadyum
    // fotoğrafı), üstünde okunurluk için hafif lacivert geçiş.
    return Container(
      decoration: BoxDecoration(
        color: _navy,
        // Sade zemin seçildiyse fotoğraf yerine lacivert geçiş.
        gradient: plain ? kPlainPosterGradient : null,
        image: plain
            ? null
            : DecorationImage(
                image: PosterBackground.photoOf(context),
                fit: BoxFit.cover,
              ),
      ),
      child: Container(
        padding: EdgeInsets.fromLTRB(14, st.pick(16, 10), 14, st.pick(12, 8)),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF0B1440).withValues(alpha: 0.55),
              _navy.withValues(alpha: 0.18),
              _navy.withValues(alpha: 0.18),
              const Color(0xFF08102E).withValues(alpha: 0.5),
            ],
            stops: const [0, 0.32, 0.75, 1],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.85),
                    radius: 0.75,
                    colors: [
                      _gold.withValues(alpha: 0.28),
                      _gold.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Column(
              children: [
                PosterLogo(
                  url: leagueLogo,
                  name: leagueName,
                  size: st.pick(92, 50),
                ),
                SizedBox(height: st.pick(4, 2)),
                Text(
                  leagueName.trUpper,
                  textAlign: TextAlign.center,
                  maxLines: st.isPost ? 1 : 2,
                  style: _cond(
                    st.pick(26, 20),
                    w: FontWeight.w800,
                    italic: true,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  SizedBox(height: st.pick(3, 2)),
                  Text(
                    subtitle.trUpper,
                    textAlign: TextAlign.center,
                    style: _cond(st.pick(14, 12), color: _gold, spacing: 1.6),
                  ),
                ],
                SizedBox(height: st.pick(7, 4)),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0x00C81E3A),
                        Color(0xFFC81E3A),
                        Color(0xFFC81E3A),
                        Color(0x00C81E3A),
                      ],
                      stops: [0, 0.15, 0.85, 1],
                    ),
                  ),
                  child: Text('PUAN DURUMU', style: _cond(15, spacing: 1.4)),
                ),
                const SizedBox(height: 10),
                // Takım sayısı fazlaysa tablo afişe sığacak şekilde küçülür.
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: Container(
                        width: kPosterSize.width - 28,
                        // Fotoğraf zeminde okunurluk: kutusuz, hafif koyu
                        // geçiş; satırlar ince çizgilerle ayrılır.
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              _navy.withValues(alpha: 0.45),
                              _navy.withValues(alpha: 0.6),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _header(),
                            for (var i = 0; i < rows.length; i++)
                              _row(i, rows[i]),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: st.pick(6, 4)),
                const PosterAppMark(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
