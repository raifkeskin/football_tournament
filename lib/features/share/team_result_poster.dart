import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/team_name.dart';
import '../../core/widgets/admin_page.dart';
import '../../core/widgets/app_logo.dart';
import '../team/models/team.dart';
import '../team/utils/standings.dart';
import 'poster_background.dart';
import 'poster_share.dart';

/// Takımın maç sonucu afişi (takım sorumlusu "Bu hafta sen" kartından
/// paylaşır). İki tasarım:
/// * [TeamPosterDesign.band] Yayın Bandı: fotoğraf üstte tam genişlik
///   (arkası aynı fotoğrafın bulanığı), altta skor bandı, golcüler ve puan
///   durumu satırı.
/// * [TeamPosterDesign.colors] Takım Renkleri: alt yarı takımın renginde,
///   büyük arma, skor şeridi ve "3 MAÇTA 9 PUAN 10 GOL" sayıları.
/// Ölçüler afiş genişliğinin yüzdesi; gönderi ve hikâye aynı düzende.
enum TeamPosterDesign {
  band('Yayın Bandı'),
  colors('Takım Renkleri');

  const TeamPosterDesign(this.label);
  final String label;
}

class TeamResultPosterData {
  const TeamResultPosterData({
    required this.leagueName,
    required this.leagueLogo,
    required this.week,
    required this.teamName,
    required this.teamLogo,
    required this.teamColor,
    required this.homeName,
    required this.homeLogo,
    required this.awayName,
    required this.awayLogo,
    required this.homeScore,
    required this.awayScore,
    required this.mineHome,
    required this.scorers,
    this.motm = '',
    this.rank,
    this.played = 0,
    this.won = 0,
    this.drawn = 0,
    this.lost = 0,
    this.goalDiff = 0,
    this.points = 0,
    this.goalsFor = 0,
    this.form = const [],
    this.next = '',
  });

  final String leagueName;
  final String leagueLogo;
  final int? week;
  final String teamName;
  final String teamLogo;

  /// Takımın birinci rengi (Takım Renkleri zemini, isim bandı).
  final Color teamColor;
  final String homeName;
  final String homeLogo;
  final String awayName;
  final String awayLogo;
  final int homeScore;
  final int awayScore;
  final bool mineHome;

  /// "Ramis Eksikli 53' 63' · Ali Şemşek 61'" (dakika tutulmayan turnuvada
  /// dakikasız); gol yoksa boş.
  final String scorers;

  /// Maçın oyuncusu (takımdansa); yoksa boş.
  final String motm;

  /// Grup sırası (puan tablosu yoksa null: sıra kutuları çıkmaz).
  final int? rank;
  final int played;
  final int won;
  final int drawn;
  final int lost;
  final int goalDiff;
  final int points;
  final int goalsFor;

  /// Son maçlar, eskiden yeniye ('G', 'B', 'M'); en çok 3 gösterilir.
  final List<String> form;

  /// Sıradaki maç ("14 Kas · Fenerbahçe M."); yoksa boş.
  final String next;

  int get myScore => mineHome ? homeScore : awayScore;
  int get oppScore => mineHome ? awayScore : homeScore;

  /// GALİBİYET / BERABERLİK; yenilgide yalnız MAÇ SONUCU.
  String get resultTag => myScore > oppScore
      ? 'GALİBİYET'
      : myScore == oppScore
      ? 'BERABERLİK'
      : 'MAÇ SONUCU';
}

const _navy = Color(0xFF0B1322);
const _paper = Color(0xFFF4F6FA);
const _gold = Color(0xFFE2B845);
const _goldInk = Color(0xFF1A1405);
const _soft = Color(0xFFCDD6E3);

TextStyle _cond(
  double size, {
  Color color = Colors.white,
  double spacing = 0,
  FontWeight weight = FontWeight.w800,
  bool italic = false,
}) => TextStyle(
  fontFamily: 'BarlowCondensed',
  fontSize: size,
  fontWeight: weight,
  fontStyle: italic ? FontStyle.italic : FontStyle.normal,
  letterSpacing: spacing,
  color: color,
  height: 1,
);

TextStyle _body(
  double size, {
  Color color = _soft,
  FontWeight weight = FontWeight.w600,
}) => TextStyle(
  fontFamily: 'Barlow',
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: 1.1,
);

class TeamResultPoster extends StatelessWidget {
  const TeamResultPoster({
    super.key,
    required this.data,
    required this.design,
    this.photo,
    this.frame = const PhotoFrame(align: Alignment.center),
  });

  final TeamResultPosterData data;
  final TeamPosterDesign design;
  final ImageProvider? photo;
  final PhotoFrame frame;

  @override
  Widget build(BuildContext context) {
    final st = PosterOptions.of(context);
    final size = st.format.size;
    final u = size.width / 100;
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: ClipRect(
          child: design == TeamPosterDesign.band
              ? _band(size, u, st.isPost)
              : _colors(size, u, st.isPost),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- ortak

  Widget _photo(double w, double h) {
    if (photo == null) {
      return Center(
        child: Opacity(
          opacity: 0.16,
          child: PosterLogo(
            url: data.teamLogo,
            name: data.teamName,
            size: h * 0.7,
          ),
        ),
      );
    }
    return Transform.scale(
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
    );
  }

  Widget _channel(double u) {
    const shadow = [Shadow(color: Color(0x99000000), blurRadius: 8)];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogo(size: 8.4 * u),
        SizedBox(width: 1.4 * u),
        Text(
          'LİG\nMASASI',
          style: _cond(
            3 * u,
            spacing: 0.35 * u,
            italic: true,
          ).copyWith(height: 0.95, shadows: shadow),
        ),
      ],
    );
  }

  /// Sol üst: turnuva logosu | ad + hafta.
  Widget _leagueBug(double u) {
    return Container(
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
                alignment: Alignment.center,
                child: PosterLogo(
                  url: data.leagueLogo,
                  name: data.leagueName,
                  size: 7 * u,
                ),
              ),
              Flexible(
                child: Container(
                  color: const Color(0xF00A101D),
                  padding: EdgeInsets.symmetric(horizontal: 2.4 * u),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: 46 * u),
                        child: Text(
                          data.leagueName.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _cond(3 * u, spacing: 0.1 * u),
                        ),
                      ),
                      if (data.week != null) ...[
                        SizedBox(height: 0.6 * u),
                        Text(
                          '${data.week}. HAFTA',
                          style: _cond(
                            2.3 * u,
                            color: _gold,
                            spacing: 0.25 * u,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ A: bant

  Widget _band(Size size, double u, bool post) {
    final w = size.width;
    final h = size.height;
    // Fotoğraf kutusu: tam genişlik, yatay takım fotoğrafı kesilmeden
    // görünsün (≈3:2). Hikâyede biraz daha aşağıda ve uzun.
    final photoTop = post ? 9 * u : 24 * u;
    final photoH = post ? 67 * u : 78 * u;
    final pad = post
        ? EdgeInsets.all(4.6 * u)
        : EdgeInsets.fromLTRB(4.6 * u, 12 * u, 4.6 * u, 14 * u);
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: _navy)),
        if (photo != null)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Opacity(
                opacity: 0.5,
                child: Image(
                  image: photo!,
                  width: w,
                  height: h,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          top: photoTop,
          height: photoH,
          child: ClipRect(child: _photo(w, photoH)),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: const [
                  Color(0x8C060A12),
                  Color(0x00060A12),
                  Color(0x00060A12),
                  Color(0xBF060A12),
                  Color(0xF5060A12),
                ],
                stops: post
                    ? const [0, 0.16, 0.5, 0.64, 1]
                    : const [0, 0.2, 0.55, 0.68, 1],
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
                        child: _leagueBug(u),
                      ),
                    ),
                    SizedBox(width: 3 * u),
                    _channel(u),
                  ],
                ),
                const Spacer(),
                _bandLower(u),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bandLower(double u) {
    Widget side(String name, String logo, bool mine, bool left) {
      final crest = mine
          ? Container(
              width: 11 * u,
              color: data.teamColor,
              alignment: Alignment.center,
              child: PosterLogo(url: logo, name: name, size: 8.6 * u),
            )
          : Padding(
              padding: EdgeInsets.symmetric(horizontal: 1.6 * u),
              child: Center(
                child: PosterLogo(url: logo, name: name, size: 8.6 * u),
              ),
            );
      final text = Expanded(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 1.4 * u, vertical: 1.4 * u),
          child: Align(
            alignment: left ? Alignment.centerLeft : Alignment.centerRight,
            child: Text(
              name.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: left ? TextAlign.left : TextAlign.right,
              style: _cond(3 * u, color: _navy, weight: FontWeight.w900),
            ),
          ),
        ),
      );
      return Expanded(
        child: Container(
          color: _paper,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: left ? [crest, text] : [text, crest],
          ),
        ),
      );
    }

    final homeWin = data.homeScore > data.awayScore;
    final awayWin = data.awayScore > data.homeScore;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                  if (data.myScore > data.oppScore) ...[
                    Icon(Icons.star_rounded, size: 3.2 * u, color: _goldInk),
                    SizedBox(width: 0.8 * u),
                  ],
                  Text(
                    data.resultTag,
                    style: _cond(2.7 * u, color: _goldInk, spacing: 0.45 * u),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(
          height: 12.5 * u,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              side(data.homeName, data.homeLogo, data.mineHome, true),
              Container(
                color: _navy,
                padding: EdgeInsets.symmetric(horizontal: 2.6 * u),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${data.homeScore}',
                      style: _cond(
                        8.6 * u,
                        color: homeWin ? _gold : Colors.white,
                        weight: FontWeight.w900,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 1.3 * u),
                      child: Text(
                        '–',
                        style: _cond(5 * u, color: const Color(0xFF6F7F96)),
                      ),
                    ),
                    Text(
                      '${data.awayScore}',
                      style: _cond(
                        8.6 * u,
                        color: awayWin ? _gold : Colors.white,
                        weight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              side(data.awayName, data.awayLogo, !data.mineHome, false),
            ],
          ),
        ),
        if (data.scorers.isNotEmpty)
          Container(
            color: const Color(0xE609101D),
            padding: EdgeInsets.symmetric(
              horizontal: 2.4 * u,
              vertical: 1.2 * u,
            ),
            alignment: data.mineHome
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'GOL  ',
                    style: _cond(2.4 * u, color: _gold, spacing: 0.3 * u),
                  ),
                  TextSpan(text: data.scorers),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _body(2.4 * u),
            ),
          ),
        if (data.rank != null) _bandStats(u),
        if (data.motm.isNotEmpty || data.next.isNotEmpty) ...[
          SizedBox(height: 1.4 * u),
          Row(
            children: [
              if (data.motm.isNotEmpty)
                Flexible(child: _foot(u, 'Maçın oyuncusu ', data.motm)),
              const Spacer(),
              if (data.next.isNotEmpty)
                Flexible(child: _foot(u, 'Sıradaki ', data.next, end: true)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _foot(double u, String label, String value, {bool end = false}) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: label),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: end ? TextAlign.right : TextAlign.left,
      style: _body(2.3 * u),
    );
  }

  Widget _bandStats(double u) {
    String sign(int v) => v > 0 ? '+$v' : '$v';
    Widget cell(String n, String l, {bool rank = false}) => Expanded(
      flex: rank ? 5 : 4,
      child: Container(
        color: rank ? _gold : null,
        padding: EdgeInsets.fromLTRB(0, 1.3 * u, 0, 1.1 * u),
        decoration: rank
            ? null
            : BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 0.25 * u,
                  ),
                ),
              ),
        child: Column(
          children: [
            FittedBox(
              child: Text(
                n,
                style: _cond(5 * u, color: rank ? _goldInk : Colors.white),
              ),
            ),
            SizedBox(height: 0.4 * u),
            Text(
              l,
              style: _cond(
                2 * u,
                color: rank ? _goldInk : const Color(0xFF8FA0B6),
                spacing: 0.25 * u,
                weight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xDB09101D),
        border: Border(
          top: BorderSide(color: data.teamColor, width: 0.5 * u),
        ),
      ),
      child: Row(
        children: [
          cell('${data.rank}.', 'SIRA', rank: true),
          cell('${data.played}', 'O'),
          cell('${data.won}', 'G'),
          cell('${data.drawn}', 'B'),
          cell('${data.lost}', 'M'),
          cell(sign(data.goalDiff), 'AV'),
          cell('${data.points}', 'P'),
        ],
      ),
    );
  }

  // --------------------------------------------------- B: takım renkleri

  Widget _colors(Size size, double u, bool post) {
    final w = size.width;
    final h = size.height;
    final base = data.teamColor;
    final dark = Color.lerp(base, Colors.black, 0.45)!;
    // Hikâyede alt panel ekranın daha küçük bir kısmını kaplar.
    final panelH = post ? h * 0.47 : h * 0.4;
    final photoH = h - panelH + 8 * u;
    final bottomPad = post ? 0.0 : 12 * u;
    final topPad = post ? 4.6 * u : 12 * u;
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: dark)),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: photoH,
          child: ClipRect(child: _photo(w, photoH)),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: photoH,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0x66000000),
                  const Color(0x00000000),
                  const Color(0x00000000),
                  dark.withValues(alpha: 0.55),
                ],
                stops: const [0, 0.22, 0.7, 1],
              ),
            ),
          ),
        ),
        // Eğik panel + altın şerit.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: panelH,
          child: ClipPath(
            clipper: _SlantClipper(0.15),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(-1, -1),
                  end: const Alignment(0.6, 1),
                  colors: [base, dark],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: panelH - 0.15 * panelH - 1.2 * u,
          height: 0.15 * panelH + 1.2 * u,
          child: ClipPath(
            clipper: _StripeClipper(1.2 * u),
            child: const ColoredBox(color: _gold),
          ),
        ),
        // Üst: turnuva hapı + kanal.
        Positioned(
          left: 4.6 * u,
          right: 4.6 * u,
          top: topPad,
          child: Row(
            children: [
              Flexible(
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    1.4 * u,
                    1.2 * u,
                    2.4 * u,
                    1.2 * u,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x8C060A12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PosterLogo(
                        url: data.leagueLogo,
                        name: data.leagueName,
                        size: 5.6 * u,
                      ),
                      SizedBox(width: 1.6 * u),
                      Flexible(
                        child: Text(
                          [
                            data.leagueName.toUpperCase(),
                            if (data.week != null) '${data.week}. HAFTA',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _cond(2.7 * u, spacing: 0.2 * u),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Panel içeriği.
        Positioned(
          left: 0,
          right: 0,
          bottom: bottomPad,
          height: panelH - bottomPad + 9 * u,
          child: _colorsPanel(u),
        ),
      ],
    );
  }

  Widget _colorsPanel(double u) {
    String sh(String s) => s.toUpperCase();
    Widget sideName(String name, String logo, bool right) {
      final crest = PosterLogo(url: logo, name: name, size: 6.4 * u);
      final text = Flexible(
        child: Text(
          sh(name),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: right ? TextAlign.right : TextAlign.left,
          style: _cond(2.9 * u),
        ),
      );
      return Expanded(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 1.8 * u),
          child: Row(
            mainAxisAlignment: right
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: right
                ? [text, SizedBox(width: 1.4 * u), crest]
                : [crest, SizedBox(width: 1.4 * u), text],
          ),
        ),
      );
    }

    Widget big(String n, String l, {Color color = Colors.white}) => Expanded(
      child: Container(
        padding: EdgeInsets.only(left: 2 * u),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: _gold, width: 0.6 * u),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              child: Text(
                n,
                style: _cond(
                  8 * u,
                  color: color,
                  weight: FontWeight.w900,
                ).copyWith(height: 0.9),
              ),
            ),
            SizedBox(height: 0.6 * u),
            Text(
              l,
              maxLines: 1,
              style: _cond(
                2.3 * u,
                color: color == Colors.white ? const Color(0xFFD5EADB) : color,
                spacing: 0.3 * u,
                weight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );

    final form = data.form.length > 3
        ? data.form.sublist(data.form.length - 3)
        : data.form;
    Color formColor(String f) => f == 'G'
        ? const Color(0xFF34D399)
        : f == 'B'
        ? const Color(0xFF94A3B8)
        : const Color(0xFFF87171);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.6 * u),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Arma + başlık
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    width: 19 * u,
                    height: 19 * u,
                    padding: EdgeInsets.all(1.6 * u),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: data.teamColor, width: u),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 3 * u,
                          offset: Offset(0, 1.5 * u),
                        ),
                      ],
                    ),
                    child: PosterLogo(
                      url: data.teamLogo,
                      name: data.teamName,
                      size: 15 * u,
                    ),
                  ),
                  SizedBox(width: 3 * u),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MAÇ SONUCU${data.myScore >= data.oppScore ? ' · ${data.resultTag}' : ''}',
                          style: _cond(
                            3.1 * u,
                            color: _gold,
                            spacing: 0.5 * u,
                            italic: true,
                          ),
                        ),
                        SizedBox(height: 0.8 * u),
                        Text(
                          sh(data.teamName),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _cond(
                            6 * u,
                            weight: FontWeight.w900,
                          ).copyWith(height: 0.92),
                        ),
                        SizedBox(height: 0.6 * u),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 2.4 * u),
              // Skor şeridi
              Container(
                height: 9.5 * u,
                decoration: BoxDecoration(
                  color: const Color(0x52000000),
                  borderRadius: BorderRadius.circular(1.4 * u),
                ),
                clipBehavior: Clip.antiAlias,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    sideName(data.homeName, data.homeLogo, false),
                    Container(
                      color: _gold,
                      padding: EdgeInsets.symmetric(horizontal: 3 * u),
                      alignment: Alignment.center,
                      child: Text(
                        '${data.homeScore} – ${data.awayScore}',
                        style: _cond(
                          7 * u,
                          color: _goldInk,
                          weight: FontWeight.w900,
                        ),
                      ),
                    ),
                    sideName(data.awayName, data.awayLogo, true),
                  ],
                ),
              ),
              SizedBox(height: 3 * u),
              // Büyük sayılar: 3 MAÇTA · 9 PUAN · 10 GOL · 1. SIRA · form
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  big('${data.played}', 'MAÇTA'),
                  SizedBox(width: 1.6 * u),
                  big('${data.points}', 'PUAN'),
                  SizedBox(width: 1.6 * u),
                  big('${data.goalsFor}', 'GOL'),
                  if (data.rank != null) ...[
                    SizedBox(width: 1.6 * u),
                    big('${data.rank}.', 'SIRA', color: _gold),
                  ],
                  if (form.isNotEmpty) ...[
                    SizedBox(width: 1.6 * u),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            for (final f in form)
                              Container(
                                width: 5 * u,
                                height: 5 * u,
                                margin: EdgeInsets.only(right: u),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: formColor(f),
                                  borderRadius: BorderRadius.circular(u),
                                ),
                                child: Text(
                                  f,
                                  style: _cond(
                                    3 * u,
                                    color: const Color(0xFF052E16),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: 1.2 * u),
                        Text(
                          'SON ${form.length} MAÇ',
                          style: _cond(
                            2.3 * u,
                            color: const Color(0xFFD5EADB),
                            spacing: 0.3 * u,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: 2.6 * u),
        // Alt şerit: golcüler + kanal
        Container(
          height: 9 * u,
          padding: EdgeInsets.symmetric(horizontal: 4.6 * u),
          color: const Color(0x59000000),
          child: Row(
            children: [
              Expanded(
                child: data.scorers.isEmpty
                    ? const SizedBox.shrink()
                    : Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'Goller: '),
                            TextSpan(
                              text: data.scorers,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _body(2.4 * u, color: const Color(0xFFD7E7DC)),
                      ),
              ),
              SizedBox(width: 2 * u),
              AppLogo(size: 4.6 * u),
              SizedBox(width: u),
              Text(
                'LİG MASASI',
                style: _cond(2.5 * u, spacing: 0.25 * u, italic: true),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Ödül / sonuç sekmesi: sağ kenarı eğik.
class _TabClipper extends CustomClipper<Path> {
  const _TabClipper(this.cut);
  final double cut;

  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width - cut, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(_TabClipper old) => old.cut != cut;
}

/// Takım Renkleri paneli: sol kenar [ratio] kadar aşağıdan başlar.
class _SlantClipper extends CustomClipper<Path> {
  const _SlantClipper(this.ratio);
  final double ratio;

  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, size.height * ratio)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(_SlantClipper old) => old.ratio != ratio;
}

/// Panelin üst kenarındaki ince altın şerit.
class _StripeClipper extends CustomClipper<Path> {
  const _StripeClipper(this.thick);
  final double thick;

  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, size.height)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, thick)
    ..lineTo(0, size.height + thick)
    ..close();

  @override
  bool shouldReclip(_StripeClipper old) => old.thick != thick;
}

/// Paylaşım penceresinde tasarım seçimi (Yayın Bandı / Takım Renkleri).
class TeamPosterDesignControls extends StatelessWidget {
  const TeamPosterDesignControls({super.key, required this.pick});

  final ValueNotifier<TeamPosterDesign> pick;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TeamPosterDesign>(
      valueListenable: pick,
      builder: (_, v, _) => Row(
        children: [
          for (final d in TeamPosterDesign.values) ...[
            if (d != TeamPosterDesign.values.first) const SizedBox(width: 10),
            Expanded(
              child: Material(
                color: d == v
                    ? kAdminAccent.withValues(alpha: 0.16)
                    : Colors.white.withValues(alpha: 0.04),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: d == v
                        ? kAdminAccent
                        : Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => pick.value = d,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Text(
                      d.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: d == v ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Takımın maç sonucu afişini hazırlayıp paylaşım penceresini açar.
/// Okunanlar: turnuva, maçın golleri ve maçın oyuncusu, sezonun maçları
/// (puan durumu, form, sıradaki maç), takım rengi, fotoğraflar. Fotoğraf
/// sırası: bu maça eklenen takım fotoğrafı, takımın son takım fotoğrafı,
/// maçın diğer anları. Hata olursa false döner.
Future<bool> openTeamResultPoster(
  BuildContext context, {
  required String leagueId,
  required String matchId,
  required String teamId,
  required int? week,
  required String homeId,
  required String awayId,
  required String homeName,
  required String awayName,
  required String homeLogo,
  required String awayLogo,
  required int homeScore,
  required int awayScore,

  /// Veriler okununca, pencere açılmadan hemen önce çağrılır (düğmedeki
  /// dönen gösterge kalksın).
  VoidCallback? onLoaded,
}) async {
  final sb = Supabase.instance.client;
  Future<Object?> safe(Future<Object?> f) async {
    try {
      return await f;
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> rows(Object? v) => [
    if (v is List)
      for (final r in v)
        if (r is Map) Map<String, dynamic>.from(r),
  ];

  final r = await Future.wait<Object?>([
    safe(
      sb
          .from('leagues')
          .select('name, logo_url')
          .eq('id', leagueId)
          .maybeSingle(),
    ),
    safe(
      sb
          .from('matches')
          .select('season_id, group_id')
          .eq('id', matchId)
          .maybeSingle(),
    ),
    safe(
      sb
          .from('match_events')
          .select(
            'event_type, team_id, player_id, minute, added_minute, is_own_goal',
          )
          .eq('match_id', matchId)
          .inFilter('event_type', ['goal', 'man_of_the_match'])
          .order('minute'),
    ),
    safe(sb.from('teams').select('first_color').eq('id', teamId).maybeSingle()),
    safe(
      sb
          .from('match_media')
          .select('match_id, url, media_type, created_at')
          .eq('team_id', teamId)
          .eq('media_type', 'Takım Fotosu')
          .order('created_at', ascending: false)
          .limit(10),
    ),
    safe(
      sb
          .from('match_media')
          .select('url')
          .eq('match_id', matchId)
          .eq('media_type', 'Önemli An')
          .order('created_at'),
    ),
  ]);
  final league = r[0] as Map?;
  final match = r[1] as Map?;
  final events = rows(r[2]);
  final team = r[3] as Map?;
  final teamPhotos = rows(r[4]);
  final moments = rows(r[5]);
  final seasonId = (match?['season_id'] ?? '').toString();
  final groupId = (match?['group_id'] ?? '').toString();

  // Golcü ve maçın oyuncusu adları.
  final pids = {
    for (final e in events)
      if ((e['player_id'] ?? '').toString().isNotEmpty)
        e['player_id'].toString(),
  };
  final r2 = await Future.wait<Object?>([
    pids.isEmpty
        ? Future<Object?>.value(const [])
        : safe(
            sb
                .from('players')
                .select('id, name, surname')
                .inFilter('id', pids.toList()),
          ),
    seasonId.isEmpty
        ? Future<Object?>.value(const [])
        : safe(
            sb
                .from('matches')
                .select(
                  'id, group_id, home_team_id, away_team_id, home_score, '
                  'away_score, status, tiebreak, match_date, match_time, week',
                )
                .eq('season_id', seasonId),
          ),
    groupId.isEmpty
        ? Future<Object?>.value(const [])
        : safe(
            sb
                .from('season_teams')
                .select('team_id, group_id, teams(name, logo_url)')
                .eq('group_id', groupId),
          ),
  ]);
  final names = {
    for (final p in rows(r2[0]))
      p['id'].toString(): '${p['name'] ?? ''} ${p['surname'] ?? ''}'.trim(),
  };
  final seasonMatches = rows(r2[1]);
  final groupTeams = rows(r2[2]);

  // Golcüler: kendi takımının golleri (kendi kalesine olanlar hariç) ve
  // rakibin kendi kalesine attıkları ("K.K.").
  final order = <String>[];
  final mins = <String, List<String>>{};
  var ownGoals = 0;
  String? motm;
  for (final e in events) {
    final tid = (e['team_id'] ?? '').toString();
    final own = e['is_own_goal'] == true;
    if (e['event_type'] == 'man_of_the_match') {
      if (tid == teamId) motm = names[(e['player_id'] ?? '').toString()];
      continue;
    }
    if (tid == teamId && !own) {
      final pid = (e['player_id'] ?? '').toString();
      if (!mins.containsKey(pid)) order.add(pid);
      final n = (e['minute'] as num?)?.toInt() ?? 0;
      final a = (e['added_minute'] as num?)?.toInt() ?? 0;
      (mins[pid] ??= []).add(n <= 0 ? '' : (a > 0 ? "$n+$a'" : "$n'"));
    } else if (tid != teamId && own) {
      ownGoals++;
    }
  }
  final scorers = [
    for (final pid in order)
      () {
        final n = names[pid] ?? '';
        final m = mins[pid]!.where((x) => x.isNotEmpty).toList();
        if (n.isEmpty) return '';
        if (m.isNotEmpty) return '$n ${m.join(' ')}';
        return mins[pid]!.length > 1 ? '$n ${mins[pid]!.length}' : n;
      }(),
    if (ownGoals > 0) ownGoals > 1 ? 'K.K. $ownGoals' : 'K.K.',
  ].where((s) => s.isNotEmpty).join(' · ');

  // Puan durumu: grup tablosundaki satırı (ana sayfadaki hesapla aynı).
  StandingEntry? entry;
  int? rank;
  if (groupId.isNotEmpty) {
    final table = computeGroupStandings(
      leagueId: seasonId,
      groupId: groupId,
      groupName: '',
      seasonMatches: seasonMatches,
      allTeams: [
        for (final t in groupTeams)
          Team(
            id: t['team_id'].toString(),
            name: ((t['teams'] as Map?)?['name'] ?? '').toString(),
            logoUrl: ((t['teams'] as Map?)?['logo_url'] ?? '').toString(),
            seasonId: seasonId,
            groupId: groupId,
          ),
      ],
    );
    final i = table.indexWhere((e) => e.teamId == teamId);
    if (i >= 0) {
      entry = table[i];
      rank = i + 1;
    }
  }

  // Sıradaki maç: bugünden sonraki oynanmamış ilk maçı.
  final today = DateTime.now();
  final todayKey =
      '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
  final upcoming =
      [
        for (final m in seasonMatches)
          if ((m['home_team_id'] == teamId || m['away_team_id'] == teamId) &&
              m['status'] == 'notStarted' &&
              (m['match_date'] ?? '').toString().compareTo(todayKey) >= 0)
            m,
      ]..sort(
        (a, b) => '${a['match_date']}|${a['match_time'] ?? ''}'.compareTo(
          '${b['match_date']}|${b['match_time'] ?? ''}',
        ),
      );
  var next = '';
  if (upcoming.isNotEmpty) {
    final m = upcoming.first;
    final oppId = m['home_team_id'] == teamId
        ? m['away_team_id']
        : m['home_team_id'];
    var opp = '';
    for (final t in groupTeams) {
      if (t['team_id'] == oppId) {
        opp = ((t['teams'] as Map?)?['name'] ?? '').toString();
      }
    }
    if (opp.isEmpty) {
      try {
        final row = await sb
            .from('teams')
            .select('name')
            .eq('id', oppId)
            .maybeSingle();
        opp = (row?['name'] ?? '').toString();
      } catch (_) {}
    }
    final d = DateTime.tryParse((m['match_date'] ?? '').toString());
    if (d != null && opp.isNotEmpty) {
      next =
          '${DateFormat('d MMM', 'tr_TR').format(d)} · ${shortTeamName(opp)}';
    }
  }

  Color color = const Color(0xFF0B5D1E);
  final hex = (team?['first_color'] ?? '').toString().trim();
  if (RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) {
    color = Color(int.parse('FF${hex.substring(1)}', radix: 16));
    // Çok açık renkte (beyaz forma) yazılar okunmasın diye koyulaştırılır.
    if (color.computeLuminance() > 0.5) {
      color = Color.lerp(color, const Color(0xFF0B1322), 0.7)!;
    }
  }

  final mineHome = homeId == teamId;
  final data = TeamResultPosterData(
    leagueName: (league?['name'] ?? '').toString(),
    leagueLogo: (league?['logo_url'] ?? '').toString(),
    week: week,
    teamName: mineHome ? homeName : awayName,
    teamLogo: mineHome ? homeLogo : awayLogo,
    teamColor: color,
    homeName: homeName,
    homeLogo: homeLogo,
    awayName: awayName,
    awayLogo: awayLogo,
    homeScore: homeScore,
    awayScore: awayScore,
    mineHome: mineHome,
    scorers: scorers,
    motm: motm ?? '',
    rank: rank,
    played: entry?.played ?? 0,
    won: entry?.won ?? 0,
    drawn: entry?.drawn ?? 0,
    lost: entry?.lost ?? 0,
    goalDiff: entry?.goalDiff ?? 0,
    points: entry?.points ?? 0,
    goalsFor: entry?.goalsFor ?? 0,
    form: entry?.form ?? const [],
    next: next,
  );

  final choices = <String>[];
  void add(String u) {
    final s = u.trim();
    if (s.isNotEmpty && !choices.contains(s)) choices.add(s);
  }

  for (final p in teamPhotos) {
    if (p['match_id'] == matchId) add((p['url'] ?? '').toString());
  }
  for (final p in teamPhotos) {
    add((p['url'] ?? '').toString());
  }
  for (final p in moments) {
    add((p['url'] ?? '').toString());
  }

  if (!context.mounted) return false;
  onLoaded?.call();
  final pick = ValueNotifier(TeamPosterDesign.band);
  final slug = [
    shortTeamName(data.teamName),
    if (week != null) '${week}_hafta',
  ].join('_').toLowerCase().replaceAll(RegExp(r'\s+'), '_');
  try {
    await showPosterPreview(
      context: context,
      title: 'Takım Afişi',
      fileName: 'takim_afisi_$slug',
      formats: const [PosterFormat.post, PosterFormat.story],
      imageUrls: [
        data.leagueLogo,
        homeLogo,
        awayLogo,
      ].where((u) => u.isNotEmpty).toList(),
      controls: TeamPosterDesignControls(pick: pick),
      photoPoster: (photo, frame) => ValueListenableBuilder<TeamPosterDesign>(
        valueListenable: pick,
        builder: (_, d, _) =>
            TeamResultPoster(data: data, design: d, photo: photo, frame: frame),
      ),
      photoUrl: choices.isEmpty ? null : choices.first,
      photoChoices: choices,
    );
  } finally {
    pick.dispose();
  }
  return true;
}
