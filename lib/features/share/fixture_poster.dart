import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/utils/string_utils.dart';
import '../../core/utils/team_name.dart';
import 'poster_share.dart';
import 'poster_background.dart';

/// Afişteki tek maç.
class PosterMatch {
  const PosterMatch({
    required this.homeName,
    required this.awayName,
    required this.homeLogo,
    required this.awayLogo,
    required this.time,
    this.score,
  });

  final String homeName;
  final String awayName;
  final String homeLogo;
  final String awayLogo;

  /// "19.30" — skor yoksa gösterilir.
  final String time;

  /// Oynanmış maçta "6 - 1".
  final String? score;
}

/// Afişte maçı olmayan (bay geçen) takım.
class PosterTeam {
  const PosterTeam({required this.name, required this.logo});

  final String name;
  final String logo;
}

/// Aynı gün ve aynı sahada oynanan maçlar.
class PosterDay {
  const PosterDay({
    required this.dateText,
    required this.pitchText,
    required this.matches,
  });

  final String dateText;
  final String pitchText;
  final List<PosterMatch> matches;
}

/// Haftalık fikstür afişi (sade): turnuva logosu, başlık, hafta bandı,
/// gün gün maçlar. Boyut [kPosterSize]; maç sayısı artarsa liste küçülür.
class FixturePoster extends StatelessWidget {
  const FixturePoster({
    super.key,
    required this.leagueName,
    required this.leagueLogo,
    required this.subtitle,
    required this.weekText,
    required this.days,
    this.byes = const [],
  });

  final String leagueName;
  final String leagueLogo;
  final String subtitle;
  final String weekText;
  final List<PosterDay> days;

  /// Bu hafta bay geçen takımlar (tek sayıda takımlı grupta).
  final List<PosterTeam> byes;

  static const _gold = Color(0xFFE2B845);
  static const _goldHi = Color(0xFFF6D77A);
  static const _navy = Color(0xFF0D1A4A);

  /// Doygunluk ×1.25, kontrast ×1.1, hafif parlaklık (+8).
  static const List<double> _vivid = [
    1.249, -0.183, -0.019, 0, 8, //
    -0.054, 1.178, -0.019, 0, 8, //
    -0.054, -0.183, 1.290, 0, 8, //
    0, 0, 0, 1, 0, //
  ];

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
    // Zemin görseli artık daha canlı: açık renkli yazılar gölgeyle okunur
    // kalır (beyaz kutulardaki koyu takım adlarına gölge verilmez).
    shadows: color.computeLuminance() > 0.4
        ? const [
            Shadow(
              color: Color(0xCC000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ]
        : null,
  );

  Widget _nameBox(String name, BorderRadius r) => Expanded(
    child: Container(
      height: 34,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF8FAFC), Color(0xFFD6DBE6)],
        ),
      ),
      child: Text(
        posterTeamName(name).trUpper,
        maxLines: 2,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        // Afişte tam ad yazılır; uzun adlarda yazı küçülür.
        style: _cond(
          posterTeamName(name).length > 24 ? 10.5 : 12.5,
          color: const Color(0xFF0B1440),
          spacing: 0.2,
        ),
      ),
    ),
  );

  /// Ortadaki lacivert kutu: üstte küçük etiket (SAAT / MS), altta değer.
  Widget _centerBox(String label, String value) => Container(
    width: 56,
    height: 40,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: _gold),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF13245E), Color(0xFF0A1336)],
      ),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (label.isNotEmpty) ...[
          Text(
            label,
            style: _cond(9, color: const Color(0xFFCBD5E1), spacing: 1),
          ),
          const SizedBox(height: 2),
        ],
        Text(value, style: _cond(18, color: _goldHi)),
      ],
    ),
  );

  Widget _match(PosterMatch m) {
    final played = (m.score ?? '').isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          PosterLogo(url: m.homeLogo, name: m.homeName, size: 34),
          const SizedBox(width: 4),
          _nameBox(
            m.homeName,
            const BorderRadius.horizontal(left: Radius.circular(8)),
          ),
          _centerBox(played ? 'MS' : 'SAAT', played ? m.score! : m.time),
          _nameBox(
            m.awayName,
            const BorderRadius.horizontal(right: Radius.circular(8)),
          ),
          const SizedBox(width: 4),
          PosterLogo(url: m.awayLogo, name: m.awayName, size: 34),
        ],
      ),
    );
  }

  /// Bay geçen takım: maç satırının sol yarısı; saat kutusunda "BAY",
  /// deplasman tarafı boş (hizalama maç satırlarıyla aynı kalır).
  Widget _bye(PosterTeam b) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          PosterLogo(url: b.logo, name: b.name, size: 34),
          const SizedBox(width: 4),
          _nameBox(
            b.name,
            const BorderRadius.horizontal(left: Radius.circular(8)),
          ),
          _centerBox('', 'BAY'),
          const Expanded(child: SizedBox()),
          const SizedBox(width: 38),
        ],
      ),
    );
  }

  Widget _day(PosterDay d) {
    Widget pill(String t, Color c, {IconData? icon}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: _navy.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _gold.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: _gold),
            const SizedBox(width: 3),
          ],
          Text(
            t,
            style: _cond(12.5, color: c, w: FontWeight.w700, spacing: 0.6),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: [
              pill(d.dateText.trUpper, _goldHi),
              if (d.pitchText.isNotEmpty)
                pill(
                  d.pitchText.trUpper,
                  Colors.white,
                  icon: Icons.place_rounded,
                ),
            ],
          ),
          for (final m in d.matches) _match(m),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = PosterOptions.of(context);
    final plain = st.plain;
    // Zemin: turnuvanın afiş görseli (yoksa stadyum fotoğrafı); üstünde
    // okunurluk için lacivert geçiş.
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
            // Zemin görseli ön planda: üstte başlık, altta boşluk için hafif
            // karartma; ortadaki maç satırları kendi beyaz kutularında.
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
            Column(
              children: [
                // Logo canlı ve parlak: hafif doygunluk/parlaklık artışı ve
                // şeklini izleyen gölge. (Arkasındaki altın ışıma, logoyu
                // soluk gösteren gri bir kutu oluşturduğu için kaldırıldı.)
                ColorFiltered(
                  colorFilter: const ColorFilter.matrix(_vivid),
                  child: PosterLogo(
                    url: leagueLogo,
                    name: leagueName,
                    size: st.pick(104, 54),
                    shadow: true,
                  ),
                ),
                SizedBox(height: st.pick(4, 2)),
                Text(
                  leagueName.trUpper,
                  textAlign: TextAlign.center,
                  maxLines: st.isPost ? 1 : 2,
                  style: _cond(st.pick(28, 21), w: FontWeight.w800, italic: true),
                ),
                if (subtitle.isNotEmpty) ...[
                  SizedBox(height: st.pick(3, 2)),
                  Text(
                    subtitle.trUpper,
                    textAlign: TextAlign.center,
                    style: _cond(st.pick(14, 12), color: _gold, spacing: 1.6),
                  ),
                ],
                if (weekText.isNotEmpty) ...[
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
                    child: Text(
                      weekText.trUpper,
                      style: _cond(15, spacing: 1.4),
                    ),
                  ),
                ],
                // Maç sayısı fazlaysa liste afişe sığacak şekilde küçülür.
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: kPosterSize.width - 28,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final d in days) _day(d),
                            if (byes.isNotEmpty) const SizedBox(height: 6),
                            for (final b in byes) _bye(b),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
