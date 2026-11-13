import 'package:flutter/material.dart';

import '../../core/widgets/app_logo.dart';
import 'poster_background.dart';
import 'poster_share.dart';

/// Futbolcunun maç afişi ("yayın grafiği"): fotoğraf tam kare; sol üstte
/// televizyondaki gibi skor kutusu (MS), sağ üstte uygulamanın arması ve
/// adı; altta forma numaralı isim bandı, takım + saha satırı, "Bu maç" ve
/// "Sezon" sayıları. Ölçüler afiş genişliğinin yüzdesi ([_u]); gönderi
/// (360×450) ve hikâye (360×640) aynı düzende çizilir.

/// Skor kutusundaki bir takım satırı.
class PosterTeam {
  const PosterTeam({
    required this.name,
    required this.logo,
    required this.score,
    this.own = false,
  });

  final String name;
  final String logo;
  final int score;

  /// Futbolcunun takımı (yeşil kenar çizgisi).
  final bool own;
}

/// "Bu maç" satırındaki katkı: 1 GOL 12'.
class PosterContribution {
  const PosterContribution({
    required this.count,
    required this.assist,
    this.minutes = '',
  });

  final int count;
  final bool assist;

  /// Dakikalar ("12' 61'"); dakika tutulmayan turnuvada boş.
  final String minutes;
}

class MatchPosterData {
  const MatchPosterData({
    required this.firstName,
    required this.lastName,
    required this.number,
    required this.leagueName,
    required this.leagueLogo,
    required this.week,
    required this.home,
    required this.away,
    required this.teamName,
    required this.teamLogo,
    required this.pitch,
    required this.contributions,
    required this.season,
    this.award = '',
    this.awardStar = false,
  });

  final String firstName;
  final String lastName;

  /// Forma numarası (yoksa boş; numara kutusu çıkmaz).
  final String number;
  final String leagueName;
  final String leagueLogo;
  final int? week;
  final PosterTeam home;
  final PosterTeam away;

  /// Futbolcunun takımı (isim bandındaki arma ve alt satır).
  final String teamName;
  final String teamLogo;

  /// Saha adı (yoksa boş).
  final String pitch;
  final List<PosterContribution> contributions;

  /// Sezon kutuları: (sayı, birim) — en çok üç; sıfırlar gelmez.
  final List<(String, String)> season;

  /// O hafta alınan ödül ("HAFTANIN OYUNCUSU"); yoksa sekme çıkmaz.
  final String award;

  /// Ödülün önünde yıldız (Haftanın Oyuncusu). Yazı tipinde ★ olmadığı
  /// için ikonla çizilir.
  final bool awardStar;
}

const _navy = Color(0xFF0B1322);
const _paper = Color(0xFFF4F6FA);
const _panel = Color(0xF00A101D);
const _gold = Color(0xFFE2B845);
const _green = Color(0xFF34D399);
const _soft = Color(0xFFCDD6E3);

TextStyle _cond(
  double size, {
  Color color = Colors.white,
  double spacing = 0,
}) => TextStyle(
  fontFamily: 'BarlowCondensed',
  fontSize: size,
  fontWeight: FontWeight.w800,
  letterSpacing: spacing,
  color: color,
  height: 1,
);

TextStyle _body(
  double size, {
  Color color = _soft,
  double spacing = 0,
  FontWeight weight = FontWeight.w600,
}) => TextStyle(
  fontFamily: 'Barlow',
  fontSize: size,
  fontWeight: weight,
  letterSpacing: spacing,
  color: color,
  height: 1,
);

class MatchPlayerPoster extends StatelessWidget {
  const MatchPlayerPoster({
    super.key,
    required this.data,
    this.photo,
    this.frame = const PhotoFrame(),
  });

  final MatchPosterData data;
  final ImageProvider? photo;
  final PhotoFrame frame;

  @override
  Widget build(BuildContext context) {
    final st = PosterOptions.of(context);
    final size = st.format.size;
    final w = size.width;
    final h = size.height;
    final u = w / 100;
    // Hikâyede yazılar Instagram'ın üst (profil) ve alt (yanıt) çubuklarına
    // değmesin; boşluk dar tutuldu (kullanıcı isteği 2026-11-13).
    final pad = st.isPost
        ? EdgeInsets.all(4.6 * u)
        : EdgeInsets.fromLTRB(4.6 * u, 12 * u, 4.6 * u, 14 * u);

    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: _navy)),
            if (photo != null)
              Positioned.fill(
                child: ClipRect(
                  child: Transform.scale(
                    scale: frame.zoom,
                    alignment: frame.align,
                    child: Image(
                      image: photo!,
                      width: w,
                      height: h,
                      fit: BoxFit.cover,
                      alignment: frame.align,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              )
            else
              Positioned.fill(
                child: Center(
                  child: Opacity(
                    opacity: 0.14,
                    child: PosterLogo(
                      url: data.teamLogo,
                      name: data.teamName,
                      size: 62 * u,
                    ),
                  ),
                ),
              ),
            // Köşelerde hafif kararma + üstte ve altta yazıların zemini.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.16),
                    radius: 1.05,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      Color(0x6B000000),
                    ],
                    stops: [0, 0.52, 1],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: const [
                      Color(0x80060A12),
                      Color(0x00060A12),
                      Color(0x00060A12),
                      Color(0x99060A12),
                      Color(0xE6060A12),
                    ],
                    stops: st.isPost
                        ? const [0, 0.2, 0.52, 0.74, 1]
                        : const [0, 0.24, 0.5, 0.66, 1],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: pad,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _scoreBug(u),
                          ),
                        ),
                        SizedBox(width: 3 * u),
                        _channel(u),
                      ],
                    ),
                    const Spacer(),
                    _lowerThird(u),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sol üst: turnuva logosu + hafta | iki takım ve skor | MS.
  Widget _scoreBug(double u) {
    Widget row(PosterTeam t) {
      final long = t.name.length > 22;
      return Container(
        padding: EdgeInsets.fromLTRB(2 * u, 0.8 * u, 1.6 * u, 0.8 * u),
        decoration: t.own
            ? BoxDecoration(
                border: Border(
                  left: BorderSide(color: _green, width: 0.7 * u),
                ),
              )
            : null,
        child: Row(
          children: [
            PosterLogo(url: t.logo, name: t.name, size: 3.8 * u),
            SizedBox(width: 1.5 * u),
            Expanded(
              child: Text(
                t.name,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: _cond(
                  long ? 2.2 * u : 2.9 * u,
                  spacing: long ? 0 : 0.1 * u,
                ),
              ),
            ),
            SizedBox(width: 1.5 * u),
            SizedBox(
              width: 4.8 * u,
              child: Text(
                '${t.score}',
                textAlign: TextAlign.center,
                style: _cond(3.4 * u),
              ),
            ),
          ],
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 68 * u),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(1.2 * u),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 2.4 * u,
              offset: Offset(0, 0.8 * u),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(1.2 * u),
          child: IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 11 * u,
                  color: _paper,
                  padding: EdgeInsets.symmetric(vertical: u),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PosterLogo(
                        url: data.leagueLogo,
                        name: data.leagueName,
                        size: 6.6 * u,
                      ),
                      if (data.week != null) ...[
                        SizedBox(height: 0.6 * u),
                        Text(
                          '${data.week}. HAFTA',
                          maxLines: 1,
                          style: _cond(1.9 * u, color: _navy, spacing: 0.2 * u),
                        ),
                      ],
                    ],
                  ),
                ),
                Flexible(
                  child: Container(
                    color: _panel,
                    padding: EdgeInsets.symmetric(vertical: 0.8 * u),
                    child: IntrinsicWidth(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [row(data.home), row(data.away)],
                      ),
                    ),
                  ),
                ),
                Container(
                  color: _gold,
                  padding: EdgeInsets.symmetric(horizontal: 1.6 * u),
                  alignment: Alignment.center,
                  child: Text(
                    'MS',
                    style: _cond(
                      3 * u,
                      color: const Color(0xFF1A1405),
                      spacing: 0.2 * u,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Sağ üst: kanal logosu gibi uygulamanın arması ve adı.
  Widget _channel(double u) {
    const shadow = [Shadow(color: Color(0x99000000), blurRadius: 8)];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogo(size: 8.4 * u),
        SizedBox(width: 1.4 * u),
        Text(
          'LİG\nMASASI',
          style: _cond(3 * u, spacing: 0.35 * u).copyWith(
            fontStyle: FontStyle.italic,
            height: 0.95,
            shadows: shadow,
          ),
        ),
      ],
    );
  }

  Widget _lowerThird(double u) {
    final contrib = data.contributions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (data.award.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: ClipPath(
              clipper: _TabClipper(2.6 * u),
              child: Container(
                color: _gold,
                padding: EdgeInsets.fromLTRB(2.4 * u, 1.2 * u, 5 * u, 1.1 * u),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (data.awardStar) ...[
                      Icon(
                        Icons.star_rounded,
                        size: 3.2 * u,
                        color: const Color(0xFF1A1405),
                      ),
                      SizedBox(width: 0.8 * u),
                    ],
                    Text(
                      data.award,
                      style: _cond(
                        2.7 * u,
                        color: const Color(0xFF1A1405),
                        spacing: 0.45 * u,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        // İsim bandı: forma numarası | ad SOYAD | takım arması
        Container(
          color: _paper,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (data.number.trim().isNotEmpty)
                  Container(
                    width: 12.5 * u,
                    color: _navy,
                    alignment: Alignment.center,
                    child: Text(
                      data.number.trim(),
                      style: _cond(7.6 * u, color: _gold),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      2.4 * u,
                      1.8 * u,
                      2.4 * u,
                      1.4 * u,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              if (data.firstName.isNotEmpty)
                                TextSpan(
                                  text: '${data.firstName} ',
                                  style: const TextStyle(
                                    color: Color(0xFF3B4A60),
                                  ),
                                ),
                              TextSpan(text: data.lastName),
                            ],
                          ),
                          maxLines: 1,
                          style: _cond(
                            8.6 * u,
                            color: _navy,
                            spacing: 0.05 * u,
                          ).copyWith(height: 0.95),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(right: 2.4 * u),
                  child: Center(
                    child: PosterLogo(
                      url: data.teamLogo,
                      name: data.teamName,
                      size: 7.4 * u,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Takım • saha
        Container(
          color: _panel,
          padding: EdgeInsets.symmetric(horizontal: 2.4 * u, vertical: 1.5 * u),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  data.teamName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _body(2.3 * u, spacing: 0.3 * u),
                ),
              ),
              if (data.pitch.isNotEmpty) ...[
                Text('  •  ', style: _body(2.3 * u, color: _gold)),
                Flexible(
                  child: Text(
                    data.pitch,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _body(2.3 * u, spacing: 0.3 * u),
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: 1.4 * u),
        if (contrib.isNotEmpty) ...[
          _statRow(u, 'BU MAÇ', [
            for (final c in contrib)
              _cell(
                u,
                '${c.count}',
                c.assist ? 'ASİST' : 'GOL',
                color: c.assist ? _green : _gold,
                minutes: c.minutes,
              ),
          ]),
          SizedBox(height: 0.8 * u),
        ],
        if (data.season.isNotEmpty)
          _statRow(u, 'SEZON', [
            for (final s in data.season) _cell(u, s.$1, s.$2),
          ]),
      ],
    );
  }

  Widget _statRow(double u, String label, List<Widget> cells) {
    return Container(
      color: const Color(0xDB09101D),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 15 * u,
              color: Colors.white.withValues(alpha: 0.1),
              alignment: Alignment.center,
              child: Text(
                label,
                style: _body(
                  2.2 * u,
                  color: const Color(0xFFE1E8F2),
                  spacing: 0.4 * u,
                  weight: FontWeight.w700,
                ),
              ),
            ),
            for (final c in cells)
              Expanded(
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    0.6 * u,
                    1.4 * u,
                    0.6 * u,
                    1.2 * u,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08),
                        width: 0.2 * u,
                      ),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: c,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell(
    double u,
    String n,
    String unit, {
    Color color = Colors.white,
    String minutes = '',
  }) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(n, style: _cond(5.4 * u, color: color)),
          SizedBox(width: u),
          Text(unit, style: _body(2.2 * u, spacing: 0.3 * u)),
          if (minutes.isNotEmpty) ...[
            SizedBox(width: u),
            Text(
              minutes,
              style: _body(2.1 * u, color: const Color(0xFF8FA0B6)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Ödül sekmesi: sağ kenarı eğik.
class _TabClipper extends CustomClipper<Path> {
  const _TabClipper(this.cut);

  final double cut;

  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width - cut, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(_TabClipper old) => old.cut != cut;
}
