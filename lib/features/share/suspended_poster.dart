import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/utils/string_utils.dart';
import '../../core/utils/team_name.dart';
import 'poster_background.dart';
import 'poster_share.dart';

/// Cezalı afişindeki bir oyuncu.
class SuspendedPosterRow {
  const SuspendedPosterRow({
    required this.name,
    required this.team,
    required this.teamLogo,
    required this.reason,
    required this.remaining,
  });

  final String name;
  final String team;
  final String teamLogo;

  /// "Kırmızı kart", "İkinci sarı kart" ...
  final String reason;

  /// Kalan ceza maçı.
  final int remaining;
}

class SuspendedPosterData {
  const SuspendedPosterData({
    required this.leagueName,
    required this.subtitle,
    required this.rows,
  });

  final String leagueName;

  /// "2026 Sezonu · A Grubu"
  final String subtitle;
  final List<SuspendedPosterRow> rows;
}

const _red = Color(0xFFDC2626);
const _yellow = Color(0xFFFACC15);
const _muted = Color(0xFF94A3B8);

TextStyle _cond(
  double size, {
  Color color = Colors.white,
  FontWeight w = FontWeight.w800,
  double spacing = 0,
}) => GoogleFonts.barlowCondensed(
  fontSize: size,
  color: color,
  fontWeight: w,
  letterSpacing: spacing,
  height: 1,
);

/// Tek cezalı: büyük kırmızı kart, ad, takım, ceza. Birden çok: sarı-siyah
/// bantlı cezalılar listesi (büyük rakam kalan ceza maçı).
class SuspendedPoster extends StatelessWidget {
  const SuspendedPoster({super.key, required this.data});

  final SuspendedPosterData data;

  @override
  Widget build(BuildContext context) {
    final st = PosterOptions.of(context);
    final size = st.format.size;
    return Container(
      width: size.width,
      height: size.height,
      color: const Color(0xFF0B1220),
      child: data.rows.length == 1
          ? _single(st, data.rows.first)
          : _list(st, size),
    );
  }

  Widget _head(PosterStyle st) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            data.leagueName.trUpper,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _cond(14, color: Colors.white70, spacing: 1.4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          data.subtitle.trUpper,
          maxLines: 1,
          style: _cond(13, color: Colors.white54, spacing: 1.2),
        ),
      ],
    ),
  );

  Widget _single(PosterStyle st, SuspendedPosterRow r) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7F1D1D), Color(0xFF1A0A0E)],
        ),
      ),
      child: Column(
        children: [
          _head(st),
          const Spacer(flex: 2),
          Transform.rotate(
            angle: -0.14,
            child: Container(
              width: st.pick(104, 74),
              height: st.pick(146, 104),
              decoration: BoxDecoration(
                color: _red,
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(color: Color(0x99000000), blurRadius: 24),
                ],
              ),
            ),
          ),
          SizedBox(height: st.pick(26, 14)),
          Text('CEZA BİLDİRİMİ', style: _cond(st.pick(46, 36), spacing: 2)),
          SizedBox(height: st.pick(18, 10)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(r.name.trUpper, style: _cond(st.pick(40, 32))),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            [posterTeamName(r.team), r.reason].where((e) => e.isNotEmpty).join(' · '),
            textAlign: TextAlign.center,
            style: _cond(st.pick(18, 15), color: Colors.white70, w: FontWeight.w600),
          ),
          SizedBox(height: st.pick(22, 12)),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: st.pick(26, 20),
              vertical: st.pick(10, 7),
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(40),
            ),
            child: Text(
              '${r.remaining} MAÇ CEZA',
              style: _cond(st.pick(26, 22), color: const Color(0xFF7F1D1D)),
            ),
          ),
          const Spacer(flex: 3),
          const PosterAppMark(),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _list(PosterStyle st, Size size) {
    final max = st.isPost ? 5 : 8;
    final shown = data.rows.take(max).toList();
    final more = data.rows.length - shown.length;
    return Column(
      children: [
        Container(
          height: 14,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              tileMode: TileMode.repeated,
              begin: Alignment(-0.1, -0.1),
              end: Alignment(0.1, 0.1),
              colors: [_yellow, _yellow, Color(0xFF111111), Color(0xFF111111)],
              stops: [0, .5, .5, 1],
            ),
          ),
        ),
        _head(st),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'CEZALILAR LİSTESİ',
                style: _cond(st.pick(40, 32), color: _yellow),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'SIRADAKİ MAÇLARDA OYNAYAMAYACAKLAR',
              style: _cond(12, color: _muted, spacing: 1.2, w: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (final r in shown) ...[
                  Expanded(child: _row(r)),
                  const SizedBox(height: 6),
                ],
                if (more > 0)
                  Text(
                    '+ $more oyuncu daha',
                    style: _cond(14, color: _muted, w: FontWeight.w600),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        const PosterAppMark(),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _row(SuspendedPosterRow r) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: const Color(0xFF131D33),
      borderRadius: BorderRadius.circular(10),
      border: const Border(left: BorderSide(color: _red, width: 4)),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(
            '${r.remaining}',
            textAlign: TextAlign.center,
            style: _cond(30, color: const Color(0xFFF87171)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                r.name.trUpper,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _cond(19),
              ),
              const SizedBox(height: 2),
              Text(
                [posterTeamName(r.team), r.reason]
                    .where((e) => e.isNotEmpty)
                    .join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _cond(12.5, color: _muted, w: FontWeight.w600),
              ),
            ],
          ),
        ),
        Text('MAÇ', style: _cond(11, color: _muted, spacing: 1)),
      ],
    ),
  );
}
