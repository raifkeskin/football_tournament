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
    this.photoUrl = '',
  });

  final String name;
  final String team;
  final String teamLogo;

  /// "Kırmızı kart", "İkinci sarı kart" ...
  final String reason;

  /// Kalan ceza maçı.
  final int remaining;

  /// Profil fotoğrafı (dekupe ya da düz); boşsa silüet.
  final String photoUrl;
}

class SuspendedPosterData {
  const SuspendedPosterData({
    required this.leagueName,
    required this.subtitle,
    required this.rows,
    this.leagueLogo = '',
    this.withPhoto = true,
  });

  final String leagueName;
  final String leagueLogo;

  /// Fotoğraflı / fotoğrafsız (kırmızı kart görseli) hâl.
  final bool withPhoto;

  /// "2026 Sezonu · A Grubu"
  final String subtitle;
  final List<SuspendedPosterRow> rows;
}

const _red = Color(0xFFDC2626);
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

/// Tasarım B: üstte diyagonal kırmızı alan (turnuva logosu, dev ceza rakamı,
/// sağda oyuncu fotoğrafı), altta ad, takım logosu ve sebep. Birden çok
/// cezalıda kırmızı alan küçülür ve altında fotoğraflı satırlar sıralanır.
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
          ? _single(st, size, data.rows.first)
          : _list(st, size),
    );
  }

  ImageProvider? _img(String url) =>
      url.trim().isEmpty ? null : NetworkImage(url.trim());

  Widget _leagueTag(PosterStyle st) => Row(
    children: [
      PosterLogo(url: data.leagueLogo, name: data.leagueName, size: 30),
      const SizedBox(width: 8),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              data.leagueName.trUpper,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _cond(15, spacing: 1),
            ),
            if (data.subtitle.isNotEmpty)
              Text(
                data.subtitle.trUpper,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _cond(12, color: Colors.white70, w: FontWeight.w600),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _photo(String url, double w, double h) {
    final img = _img(url);
    return SizedBox(
      width: w,
      height: h,
      child: img == null
          ? Icon(Icons.person_rounded, size: w * 0.9, color: const Color(0x66FFFFFF))
          : Image(
              image: img,
              fit: BoxFit.contain,
              alignment: Alignment.bottomCenter,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, _, _) => Icon(
                Icons.person_rounded,
                size: w * 0.9,
                color: const Color(0x66FFFFFF),
              ),
            ),
    );
  }

  Widget _redCard(double h) => Transform.rotate(
    angle: -0.14,
    child: Container(
      width: h * 0.7,
      height: h,
      decoration: BoxDecoration(
        color: const Color(0xFFEF2B2B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white, width: 5),
        boxShadow: const [
          BoxShadow(color: Color(0xCC000000), blurRadius: 22, offset: Offset(0, 10)),
          BoxShadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(0, 3)),
        ],
      ),
    ),
  );

  Widget _hero({required double height, required Widget child}) => ClipPath(
    clipper: _DiagonalClipper(),
    child: Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [_red, Color(0xFF7F1D1D)],
        ),
      ),
      child: child,
    ),
  );

  Widget _teamLine(SuspendedPosterRow r, double logo, double font) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      PosterLogo(url: r.teamLogo, name: r.team, size: logo),
      SizedBox(width: logo * 0.4),
      Flexible(
        child: Text(
          posterTeamName(r.team),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _cond(font, color: const Color(0xFFCBD5E1), w: FontWeight.w600),
        ),
      ),
    ],
  );

  Widget _single(PosterStyle st, Size size, SuspendedPosterRow r) {
    final heroH = size.height * 0.5;
    return Column(
      children: [
        Stack(
          children: [
            _hero(
              height: heroH,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: size.width * 0.62, child: _leagueTag(st)),
                ),
              ),
            ),
            Positioned(
              left: 14,
              bottom: heroH * 0.2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${r.remaining} MAÇ', style: _cond(st.pick(68, 54))),
                  const SizedBox(height: 2),
                  Text('CEZA', style: _cond(st.pick(26, 22), spacing: 3)),
                ],
              ),
            ),
            Positioned(
              right: 8,
              bottom: heroH * 0.12,
              child: data.withPhoto
                  ? _photo(r.photoUrl, size.width * 0.5, heroH * 0.82)
                  : _redCard(heroH * 0.5),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(r.name.trUpper, style: _cond(st.pick(40, 32))),
              ),
              const SizedBox(height: 8),
              _teamLine(r, st.pick(28, 24), st.pick(18, 16)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(r.reason.trUpper, style: _cond(15, spacing: 1)),
              ),
            ],
          ),
        ),
        const Spacer(),
        const PosterAppMark(),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _list(PosterStyle st, Size size) {
    final max = st.isPost ? 4 : 7;
    final shown = data.rows.take(max).toList();
    final more = data.rows.length - shown.length;
    return Column(
      children: [
        _hero(
          height: size.height * (st.isPost ? 0.3 : 0.26),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _leagueTag(st),
                const Spacer(),
                Padding(
                  padding: EdgeInsets.only(bottom: size.height * 0.05),
                  child: Text('CEZALILAR', style: _cond(st.pick(46, 38))),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
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

  Widget _row(SuspendedPosterRow r) => LayoutBuilder(
    builder: (context, c) {
      final h = c.maxHeight;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF131D33),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            if (data.withPhoto) ...[
              _photo(r.photoUrl, h * 0.8, h * 0.9),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.name.trUpper,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _cond(20),
                  ),
                  const SizedBox(height: 4),
                  _teamLine(r, 16, 13),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${r.remaining}',
              style: _cond(34, color: const Color(0xFFF87171)),
            ),
            const SizedBox(width: 3),
            Text('MAÇ', style: _cond(11, color: _muted, spacing: 1)),
          ],
        ),
      );
    },
  );
}

class _DiagonalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height * 0.82)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> old) => false;
}
