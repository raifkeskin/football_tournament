import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/utils/string_utils.dart';
import '../../core/utils/team_name.dart';
import '../team/utils/standings.dart';
import 'poster_share.dart';

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
    final st = _cond(12, color: _gold, spacing: 0.6);
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
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
          _cell('P', _pts, st),
        ],
      ),
    );
  }

  Widget _row(int i, StandingEntry r) {
    final leader = i == 0 && r.played > 0;
    final num = _cond(15, color: Colors.white, w: FontWeight.w700);
    final av = r.goalDiff;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: leader
          ? _gold.withValues(alpha: 0.18)
          : (i.isOdd
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.transparent),
      child: Row(
        children: [
          _cell(
            '${i + 1}',
            _rank,
            _cond(15, color: leader ? _goldHi : Colors.white),
          ),
          const SizedBox(width: 4),
          PosterLogo(url: r.logo, name: r.name, size: 22),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              shortTeamName(r.name).trUpper,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _cond(14.5, spacing: 0.2),
            ),
          ),
          _cell('${r.played}', _stat, num),
          _cell('${r.won}', _stat, num),
          _cell('${r.drawn}', _stat, num),
          _cell('${r.lost}', _stat, num),
          _cell(av > 0 ? '+$av' : '$av', _av, num),
          _cell('${r.points}', _pts, _cond(17, color: _goldHi)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1440), _navy, Color(0xFF08102E)],
          stops: [0, 0.4, 1],
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
              PosterLogo(url: leagueLogo, name: leagueName, size: 92),
              const SizedBox(height: 4),
              Text(
                leagueName.trUpper,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: _cond(26, w: FontWeight.w900, italic: true),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle.trUpper,
                  textAlign: TextAlign.center,
                  style: _cond(14, color: _gold, spacing: 1.6),
                ),
              ],
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
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _gold.withValues(alpha: 0.4)),
                      ),
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
            ],
          ),
        ],
      ),
    );
  }
}
