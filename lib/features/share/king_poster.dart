import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/utils/string_utils.dart';
import '../../core/utils/team_name.dart';
import 'poster_background.dart';
import 'poster_share.dart';

/// Gol / asist krallığı afişindeki bir oyuncu.
class KingRow {
  const KingRow({
    required this.rank,
    required this.name,
    required this.team,
    required this.teamLogo,
    required this.photoUrl,
    required this.value,
  });

  final int rank;
  final String name;
  final String team;
  final String teamLogo;
  final String photoUrl;
  final int value;

  /// "Ali Cansun" + "BEGEÇARSLAN": son kelime soyad.
  (String, String) get split {
    final w = name.trim().split(RegExp(r'\s+'));
    if (w.length < 2) return ('', name.trUpper);
    return (w.sublist(0, w.length - 1).join(' '), w.last.trUpper);
  }
}

/// Krallık afişlerinin ortak bilgisi.
class KingPosterData {
  const KingPosterData({
    required this.title,
    required this.unit,
    required this.leagueName,
    required this.leagueLogo,
    required this.subtitle,
    required this.rows,
  });

  /// "GOL KRALLIĞI"
  final String title;

  /// "GOL"
  final String unit;
  final String leagueName;
  final String leagueLogo;

  /// "2026 Sezonu · A Grubu"
  final String subtitle;
  final List<KingRow> rows;
}

const _bg = Color(0xFF0B1220);
const _card = Color(0xFF1E293B);
const _line = Color(0xFF334155);
const _lime = Color(0xFFA3E635);
const _limeDark = Color(0xFF84CC16);
const _limeLight = Color(0xFFD9F99D);
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

/// Fotoğraf yoksa ya da inmezse siluet.
class _Silhouette extends StatelessWidget {
  const _Silhouette({required this.size, this.color = _muted});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
    child: Icon(Icons.person_rounded, size: size, color: color),
  );
}

/// Fotoğraf: üstü yuvarlak kesik (vesikalık gibi), yoksa siluet.
class _Photo extends StatelessWidget {
  const _Photo({
    required this.image,
    required this.width,
    required this.height,
    this.fill = _line,
    this.iconColor = _muted,
  });

  final ImageProvider? image;
  final double width;
  final double height;
  final Color fill;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final fallback = _Silhouette(size: width * 0.6, color: iconColor);
    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(width / 2)),
      child: Container(
        width: width,
        height: height,
        color: fill,
        child: image == null
            ? fallback
            : Image(
                image: image!,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

ImageProvider? _net(String url) =>
    url.trim().isEmpty ? null : NetworkImage(url.trim());

/// Afişin üst satırı: turnuva logosu, adı ve sezon/grup.
class _Head extends StatelessWidget {
  const _Head({required this.data, this.center = false});

  final KingPosterData data;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final st = PosterOptions.of(context);
    return Row(
      mainAxisAlignment: center
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        PosterLogo(
          url: data.leagueLogo,
          name: data.leagueName,
          size: st.pick(26, 22),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Column(
            crossAxisAlignment: center
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                data.leagueName.trUpper,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _cond(st.pick(12, 11), spacing: 0.8),
              ),
              if (data.subtitle.isNotEmpty)
                Text(
                  data.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _cond(
                    st.pick(10.5, 9.5),
                    color: _muted,
                    w: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Afiş 1: solda liderin büyük fotoğrafı ve tacı, sağda başlık ve liste.
/// [photo] paylaşım penceresinde seçilen fotoğraf (yoksa profil fotoğrafı).
class KingPhotoPoster extends StatelessWidget {
  const KingPhotoPoster({super.key, required this.data, this.photo});

  final KingPosterData data;
  final ImageProvider? photo;

  @override
  Widget build(BuildContext context) {
    final st = PosterOptions.of(context);
    final size = st.format.size;
    final w = size.width;
    final h = size.height;
    final rows = data.rows.take(st.isPost ? 6 : 8).toList();
    final photoW = w * 0.52;
    final photoH = h * (st.isPost ? 0.74 : 0.7);
    final rowH = st.pick(40, 36);
    final titleWords = data.title.split(' ');
    return Container(
      width: w,
      height: h,
      color: _bg,
      child: Stack(
        children: [
          Positioned(
            left: -w * 0.35,
            top: h * 0.12,
            width: w * 1.1,
            height: w * 1.1,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [Color(0x5510B981), Color(0x000B1220)],
                ),
              ),
            ),
          ),
          // Liderin fotoğrafı: altta ve sağda zemine karışır.
          Positioned(
            left: 0,
            bottom: 0,
            width: photoW,
            height: photoH,
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Colors.black, Colors.black, Colors.transparent],
                stops: [0, 0.7, 1],
              ).createShader(r),
              child: photo == null
                  ? Container(
                      color: _card,
                      child: _Silhouette(size: photoW * 0.7),
                    )
                  : Image(
                      image: photo!,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, _, _) => Container(
                        color: _card,
                        child: _Silhouette(size: photoW * 0.7),
                      ),
                    ),
            ),
          ),
          Positioned(
            left: photoW * 0.18,
            bottom: photoH - st.pick(30, 26),
            child: Transform.rotate(
              angle: -0.14,
              child: Icon(
                Icons.workspace_premium_rounded,
                color: _lime,
                size: st.pick(54, 46),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: st.pick(22, 16),
            child: _Head(data: data),
          ),
          Positioned(
            right: 16,
            top: st.pick(70, 54),
            width: w * 0.56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final t in titleWords)
                  Text(
                    t,
                    style: _cond(st.pick(50, 40), color: _lime, w: FontWeight.w900),
                  ),
              ],
            ),
          ),
          Positioned(
            right: 14,
            bottom: st.pick(44, 36),
            width: w * 0.6,
            child: Column(
              children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: SizedBox(
                      height: rowH,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _listRow(r, rowH)),
                          const SizedBox(width: 4),
                          Container(
                            width: rowH * 1.05,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _lime,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${r.value}',
                              style: _cond(rowH * 0.62, color: _bg, w: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: PosterAppMark(),
          ),
        ],
      ),
    );
  }

  Widget _listRow(KingRow r, double h) {
    final (first, last) = r.split;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: _card.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          PosterLogo(url: r.teamLogo, name: r.team, size: h * 0.55),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        if (first.isNotEmpty)
                          TextSpan(
                            text: '$first ',
                            style: _cond(
                              h * 0.38,
                              color: const Color(0xFFCBD5E1),
                              w: FontWeight.w600,
                            ),
                          ),
                        TextSpan(text: last, style: _cond(h * 0.38)),
                      ],
                    ),
                    maxLines: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  posterTeamName(r.team),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _cond(h * 0.24, color: _muted, w: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Afiş 2: lider yeşil şeritte, sonrakiler koyu şeritlerde; her şeritte
/// profil fotoğrafı, "5 GOL", ad ve takım logosu.
class KingStripPoster extends StatelessWidget {
  const KingStripPoster({super.key, required this.data});

  final KingPosterData data;

  @override
  Widget build(BuildContext context) {
    final st = PosterOptions.of(context);
    final size = st.format.size;
    final rows = data.rows.take(st.isPost ? 4 : 6).toList();
    return Container(
      width: size.width,
      height: size.height,
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.2,
          colors: [Color(0xFF1E293B), Color(0xFF070B14)],
        ),
      ),
      padding: EdgeInsets.fromLTRB(16, st.pick(22, 14), 16, 10),
      child: Column(
        children: [
          _Head(data: data, center: true),
          SizedBox(height: st.pick(10, 6)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              data.title,
              style: _cond(st.pick(46, 38), w: FontWeight.w900),
            ),
          ),
          SizedBox(height: st.pick(14, 8)),
          Expanded(
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) SizedBox(height: st.pick(8, 6)),
                  Expanded(flex: i == 0 ? 13 : 10, child: _strip(rows[i], i == 0)),
                ],
                // Az oyuncu varsa şeritler uzamasın.
                for (var i = rows.length; i < (st.isPost ? 4 : 6); i++) ...[
                  SizedBox(height: st.pick(8, 6)),
                  const Spacer(flex: 10),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          const PosterAppMark(),
        ],
      ),
    );
  }

  Widget _strip(KingRow r, bool leader) {
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight;
        final ink = leader ? _bg : Colors.white;
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: leader
                ? const LinearGradient(colors: [_limeDark, _lime, _limeLight])
                : const LinearGradient(
                    colors: [Color(0xFF1E293B), Color(0xFF111827)],
                  ),
            border: leader ? null : Border.all(color: _line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(width: h * 0.15),
              _Photo(
                image: _net(r.photoUrl),
                width: h * 0.8,
                height: h * 0.92,
                fill: leader ? const Color(0x330B1220) : _line,
                iconColor: leader ? const Color(0xFF1A2E05) : _muted,
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${r.value} ${data.unit}',
                        style: _cond(h * 0.42, color: ink, w: FontWeight.w900),
                      ),
                    ),
                    SizedBox(height: h * 0.04),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          r.name.trUpper,
                          maxLines: 1,
                          style: _cond(
                            h * 0.16,
                            color: leader ? _bg : _lime,
                            w: FontWeight.w700,
                            spacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: h * 0.75,
                height: h,
                child: Center(
                  child: PosterLogo(
                    url: r.teamLogo,
                    name: r.team,
                    size: h * 0.48,
                    shadow: true,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
