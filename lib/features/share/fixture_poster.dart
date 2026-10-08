import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/utils/string_utils.dart';
import 'poster_share.dart';

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
  });

  final String leagueName;
  final String leagueLogo;
  final String subtitle;
  final String weekText;
  final List<PosterDay> days;

  static const _gold = Color(0xFFE2B845);
  static const _goldHi = Color(0xFFF6D77A);
  static const _navy = Color(0xFF0D1A4A);

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

  Widget _match(PosterMatch m) {
    Widget nameBox(String name, BorderRadius r) => Expanded(
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
          name.trUpper,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: _cond(12.5, color: const Color(0xFF0B1440), spacing: 0.2),
        ),
      ),
    );

    final played = (m.score ?? '').isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          PosterLogo(url: m.homeLogo, name: m.homeName, size: 34),
          const SizedBox(width: 4),
          nameBox(
            m.homeName,
            const BorderRadius.horizontal(left: Radius.circular(8)),
          ),
          Container(
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
                Text(
                  played ? 'MS' : 'SAAT',
                  style: _cond(9, color: const Color(0xFFCBD5E1), spacing: 1),
                ),
                const SizedBox(height: 2),
                Text(
                  played ? m.score! : m.time,
                  style: _cond(18, color: _goldHi),
                ),
              ],
            ),
          ),
          nameBox(
            m.awayName,
            const BorderRadius.horizontal(right: Radius.circular(8)),
          ),
          const SizedBox(width: 4),
          PosterLogo(url: m.awayLogo, name: m.awayName, size: 34),
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
    // Zemin: stadyum fotoğrafı; üstünde okunurluk için lacivert geçiş.
    return Container(
      decoration: const BoxDecoration(
        color: _navy,
        image: DecorationImage(
          image: AssetImage('assets/anasayfa.jpg'),
          fit: BoxFit.cover,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF0B1440).withValues(alpha: 0.9),
              _navy.withValues(alpha: 0.72),
              const Color(0xFF08102E).withValues(alpha: 0.88),
            ],
            stops: const [0, 0.45, 1],
          ),
        ),
        child: Stack(
          children: [
            // Logonun arkasında altın, altta yeşil hafif ışıma.
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
                PosterLogo(url: leagueLogo, name: leagueName, size: 104),
                const SizedBox(height: 4),
                Text(
                  leagueName.trUpper,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: _cond(28, w: FontWeight.w800, italic: true),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle.trUpper,
                    textAlign: TextAlign.center,
                    style: _cond(14, color: _gold, spacing: 1.6),
                  ),
                ],
                if (weekText.isNotEmpty) ...[
                  const SizedBox(height: 7),
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
                          children: [for (final d in days) _day(d)],
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
