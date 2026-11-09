import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/app_session.dart';
import '../../../core/services/app_settings.dart';
import '../../../core/services/image_upload_service.dart';
import '../../../core/services/instagram_share.dart';
import '../../../core/services/photo_cutouts.dart';
import '../../../core/utils/string_utils.dart';
import '../../../core/utils/team_colors.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/youtube_player_page.dart';
import '../../tournament/models/league_extras.dart';
import '../../videos/instagram_embed.dart';
import '../week_awards.dart';
import 'result_news_cards.dart';

/// Haftanın Enleri kartları (4:5, Instagram gönderisi oranı): haftanın
/// 11'i (saha + puan) ve her en için ödül kartı. Görseller paylaşımda
/// PNG'ye çizildiği için resimler Image.network ile yüklenir.

const _card = Color(0xFF1E293B);
const _muted = Color(0xFF94A3B8);
const _gold = Color(0xFFE2B845);
const _goldHi = Color(0xFFF6D77A);
const _night = Color(0xFF0C1424);

/// Puanlar kartta yalnız futbolcu puanı herkese açıksa görünür.
bool weekAwardsShowRatings() => AppSettings.matchInsightsEnabled.value;

TextStyle _cond(
  double size, {
  Color color = Colors.white,
  bool italic = false,
}) => TextStyle(
  fontFamily: 'BarlowCondensed',
  fontSize: size,
  height: 1.05,
  color: color,
  fontWeight: FontWeight.w800,
  fontStyle: italic ? FontStyle.italic : FontStyle.normal,
);

/// Kart zemini: üstte koyu lacivert ışık.
const _bgGradient = RadialGradient(
  center: Alignment(0, -1),
  radius: 1.4,
  colors: [Color(0xFF17324A), _night, Color(0xFF080D18)],
  stops: [0, 0.6, 1],
);

Widget _net(
  String url, {
  required double size,
  BoxFit fit = BoxFit.cover,
  Alignment alignment = Alignment.center,
  required Widget fallback,
}) {
  if (url.trim().isEmpty) return fallback;
  return Image.network(
    url,
    width: size,
    height: size,
    fit: fit,
    alignment: alignment,
    filterQuality: FilterQuality.high,
    errorBuilder: (_, _, _) => fallback,
  );
}

/// Turnuva logosu; yoksa altın rozet ve baş harfler.
Widget _crest(String url, String name, double size) {
  final initials = name
      .split(RegExp(r'\s+'))
      .where((e) => e.isNotEmpty)
      .take(3)
      .map((e) => e.characters.first)
      .join()
      .trUpper;
  final badge = Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: SweepGradient(
        colors: [_goldHi, _gold, Color(0xFFA77A1F), _goldHi],
      ),
    ),
    child: Text(
      initials,
      style: _cond(size * 0.36, color: const Color(0xFF1B1405)),
    ),
  );
  return _net(url, size: size, fit: BoxFit.contain, fallback: badge);
}

/// Kartın üst satırı: turnuva logosu, adı, hafta.
class _Head extends StatelessWidget {
  const _Head({
    required this.u,
    required this.league,
    required this.logo,
    required this.week,
  });

  final double u;
  final String league;
  final String logo;
  final int week;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _crest(logo, league, 9 * u),
      SizedBox(width: 2.6 * u),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              league.trUpper,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _cond(
                3.4 * u,
                color: _gold,
              ).copyWith(letterSpacing: 0.3 * u),
            ),
            SizedBox(height: 0.6 * u),
            Text(
              '$week. HAFTA',
              style: _cond(
                3 * u,
                color: const Color(0xFFC8D3E6),
              ).copyWith(letterSpacing: 0.36 * u),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Kartın altındaki imza.
class _Brand extends StatelessWidget {
  const _Brand(this.u, {this.align = MainAxisAlignment.center});
  final double u;
  final MainAxisAlignment align;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: align,
    children: [
      AppLogo(size: 5 * u),
      SizedBox(width: 1.6 * u),
      Text(
        'LİG MASASI',
        style: _cond(
          3.4 * u,
          color: const Color(0xFFDFE7F3),
          italic: true,
        ).copyWith(letterSpacing: 0.5 * u),
      ),
    ],
  );
}

// ------------------------------------------------------------- haftanın 11'i

/// Haftanın 11'i: saha üzerinde fotoğraf (yoksa baş harfler), ad, takım ve
/// varsa puan rozeti. [slots] dizilişteki sırayla (0 kaleci); boş yer
/// düzenleme ekranında "+" olarak çizilir.
class WeekElevenCard extends StatelessWidget {
  const WeekElevenCard({
    super.key,
    required this.league,
    required this.leagueLogo,
    required this.week,
    required this.formation,
    required this.slots,
    required this.showRatings,
    this.onTapSlot,
  });

  final String league;
  final String leagueLogo;
  final int week;
  final String formation;
  final List<ElevenSlot?> slots;
  final bool showRatings;
  final ValueChanged<int>? onTapSlot;

  /// Her sıranın sahadaki yeri (0..1; y yukarıdan).
  static List<Offset> layout(String formation) {
    final counts = formationCounts(formation);
    final out = <Offset>[const Offset(0.5, 0.88)];
    final lines = counts.length;
    for (var li = 0; li < lines; li++) {
      final y = lines == 1 ? 0.45 : 0.68 - li * (0.61 / (lines - 1));
      final n = counts[li];
      final step = math.min(0.25, 0.92 / n);
      for (var j = 0; j < n; j++) {
        out.add(Offset(0.5 + (j - (n - 1) / 2) * step, y));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    PhotoCutouts.ensureLoaded();
    final showCutouts = PhotoCutouts.visible(context);
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: PhotoCutouts.map,
      builder: (context, cutouts, _) =>
          _build(context, showCutouts ? cutouts : const {}),
    );
  }

  Widget _build(BuildContext context, Map<String, String> cutouts) {
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: LayoutBuilder(
        builder: (context, c) {
          final u = c.maxWidth / 100;
          final pos = layout(formation);
          // Hatta kaç kişi varsa o kadar dar: adlar yan yana binmesin.
          final perLine = <double, int>{};
          for (final o in pos) {
            perLine[o.dy] = (perLine[o.dy] ?? 0) + 1;
          }
          final best = showRatings
              ? slots.map((s) => s?.rating ?? 0).fold<double>(0, math.max)
              : 0.0;
          return ClipRRect(
            borderRadius: BorderRadius.circular(2 * u),
            child: DecoratedBox(
              decoration: const BoxDecoration(gradient: _bgGradient),
              child: Stack(
                children: [
                  Positioned(
                    left: 5 * u,
                    right: 5 * u,
                    top: 4 * u,
                    child: _Head(
                      u: u,
                      league: league,
                      logo: leagueLogo,
                      week: week,
                    ),
                  ),
                  Positioned(
                    left: 5 * u,
                    top: 14.5 * u,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          "HAFTANIN 11'İ",
                          style: _cond(8.6 * u, italic: true),
                        ),
                        SizedBox(width: 2 * u),
                        Text(
                          formation,
                          style: _cond(
                            3.4 * u,
                            color: _goldHi,
                          ).copyWith(letterSpacing: 0.3 * u),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 4 * u,
                    right: 4 * u,
                    top: 24 * u,
                    bottom: 9.5 * u,
                    child: LayoutBuilder(
                      builder: (context, p) => Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: CustomPaint(painter: _PitchPainter(u)),
                          ),
                          for (
                            var i = 0;
                            i < pos.length && i < slots.length;
                            i++
                          )
                            Positioned(
                              left:
                                  pos[i].dx * p.maxWidth -
                                  _w(u, p, perLine[pos[i].dy]!) / 2,
                              top: pos[i].dy * p.maxHeight - 7 * u,
                              width: _w(u, p, perLine[pos[i].dy]!),
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: onTapSlot == null
                                    ? null
                                    : () => onTapSlot!(i),
                                child: _PitchPlayer(
                                  u: u,
                                  slot: slots[i],
                                  cutout:
                                      cutouts[(slots[i]?.person.photo ?? '')
                                          .trim()],
                                  showRating: showRatings,
                                  top: best > 0 && slots[i]?.rating == best,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 2.6 * u,
                    child: _Brand(u),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Oyuncu kutusunun genişliği: hattaki komşusuna değmeyecek kadar.
  static double _w(double u, BoxConstraints p, int n) =>
      math.min(22 * u, p.maxWidth * math.min(0.25, 0.92 / n) - 0.8 * u);
}

/// Uzun adlar sahada kısalır: "Ersel Kahraman" → "E. KAHRAMAN".
String _pitchName(String name) {
  final w = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
  if (name.trim().length <= 12 || w.length < 2) return name.trUpper;
  return '${w.first.characters.first}. ${w.last}'.trUpper;
}

class _PitchPlayer extends StatelessWidget {
  const _PitchPlayer({
    required this.u,
    required this.slot,
    required this.showRating,
    required this.top,
    this.cutout,
  });

  final double u;
  final ElevenSlot? slot;
  final bool showRating;
  final bool top;

  /// Dekupe varsa daire yerine o (maç detayındaki dizilişte olduğu gibi).
  final String? cutout;

  @override
  Widget build(BuildContext context) {
    final s = slot;
    final d = 9.5 * u;
    if (s == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: d,
            height: d,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.25),
              border: Border.all(color: Colors.white54, width: 0.5 * u),
            ),
            child: Icon(Icons.add_rounded, color: Colors.white70, size: 6 * u),
          ),
        ],
      );
    }
    final color = TeamPalette.of(s.team.color, null).background;
    final initials = Container(
      color: color,
      alignment: Alignment.center,
      child: Text(s.person.initials, style: _cond(4.6 * u)),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: d + 5 * u,
          height: d * 1.2,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              if ((cutout ?? '').isNotEmpty) ...[
                Positioned(
                  bottom: 0,
                  child: Container(
                    width: d,
                    height: 2.6 * u,
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.all(
                        Radius.elliptical(d / 2, 1.3 * u),
                      ),
                      border: Border.all(color: color, width: 0.5 * u),
                    ),
                  ),
                ),
                Positioned(
                  bottom: u,
                  child: Image.network(
                    cutout!,
                    height: d * 1.2 - u,
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomCenter,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ] else
                Container(
                  width: d,
                  height: d * 1.2,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(1.6 * u),
                    border: Border(
                      bottom: BorderSide(color: color, width: 0.8 * u),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 2 * u,
                        offset: Offset(0, u),
                      ),
                    ],
                  ),
                  child: _net(
                    s.person.photo,
                    size: d * 1.2,
                    alignment: Alignment.topCenter,
                    fallback: initials,
                  ),
                ),
              if (showRating && s.rating != null)
                Positioned(
                  right: -0.4 * u,
                  top: -1.6 * u,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 1.1 * u,
                      vertical: 0.5 * u,
                    ),
                    decoration: BoxDecoration(
                      color: top ? Colors.white : _gold,
                      borderRadius: BorderRadius.circular(u),
                    ),
                    child: Text(
                      s.rating!.toStringAsFixed(1),
                      style: _cond(2.8 * u, color: const Color(0xFF1A1404)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: 0.8 * u),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _pitchName(s.person.name),
            maxLines: 1,
            style: _cond(3 * u).copyWith(
              shadows: [Shadow(color: Colors.black87, blurRadius: u)],
            ),
          ),
        ),
        SizedBox(height: 0.6 * u),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 1.2 * u,
              vertical: 0.4 * u,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(u),
            ),
            child: Text(
              s.team.short.trUpper,
              maxLines: 1,
              style: TextStyle(
                color: const Color(0xFFD5F5E6),
                fontSize: 2.1 * u,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.15 * u,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Çimen şeritleri ve saha çizgileri.
class _PitchPainter extends CustomPainter {
  _PitchPainter(this.u);
  final double u;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(2 * u),
    );
    canvas.save();
    canvas.clipRRect(r);
    const bands = 10;
    final h = size.height / bands;
    for (var i = 0; i < bands; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, i * h, size.width, h + 0.5),
        Paint()
          ..color = i.isEven
              ? const Color(0xFF0F6B47)
              : const Color(0xFF0D6141),
      );
    }
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5 * u;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      line,
    );
    canvas.drawCircle(size.center(Offset.zero), 11 * u, line);
    final bw = size.width / 2, bh = size.height * 0.11;
    canvas.drawRect(Rect.fromLTWH(size.width / 4, -1, bw, bh + 1), line);
    canvas.drawRect(
      Rect.fromLTWH(size.width / 4, size.height - bh, bw, bh + 1),
      line,
    );
    canvas.restore();
    canvas.drawRRect(
      r.deflate(0.25 * u),
      line..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_PitchPainter old) => old.u != u;
}

// ------------------------------------------------------------- ödül kartı

/// Tek en kartı. Takımı: fotoğraf tam kadraj; kişiye verilen enler (oyuncu,
/// kaleci, centilmen, gol): solda eğik kesik fotoğraf, sağda başlık ve ad;
/// maçı: iki arma ve skor.
class WeekAwardCard extends StatelessWidget {
  const WeekAwardCard({
    super.key,
    required this.award,
    required this.league,
    required this.leagueLogo,
    required this.week,
    required this.showRatings,
  });

  final WeekAward award;
  final String league;
  final String leagueLogo;
  final int week;
  final bool showRatings;

  @override
  Widget build(BuildContext context) {
    final a = award;
    if (a.kind == AwardKind.team) return _fullBleed();
    if (a.kind != AwardKind.match) return _split();
    final accent = a.kind.color;
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: LayoutBuilder(
        builder: (context, c) {
          final u = c.maxWidth / 100;
          final stats = [
            ...a.stats,
            if (a.kind == AwardKind.goal &&
                (a.clip?['video_id'] ?? '').toString().isNotEmpty)
              '▶ VİDEO',
            if (showRatings && a.rating != null)
              '${a.rating!.toStringAsFixed(1)} PUAN',
          ];
          final String title;
          final String sub;
          switch (a.kind) {
            case AwardKind.match:
              title = '${a.home?.short ?? ''} · ${a.away?.short ?? ''}';
              sub = '';
            case AwardKind.team:
              title = a.team.short;
              sub = a.home == null
                  ? ''
                  : '${a.score} · ${(a.home!.id == a.team.id ? a.away! : a.home!).short}';
            default:
              title = a.person?.name ?? '';
              sub = a.team.short;
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(2 * u),
            child: DecoratedBox(
              decoration: const BoxDecoration(gradient: _bgGradient),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0, -0.08),
                          radius: 0.62,
                          colors: [
                            accent.withValues(alpha: 0.3),
                            accent.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 5 * u,
                    right: 5 * u,
                    top: 4 * u,
                    child: _Head(
                      u: u,
                      league: league,
                      logo: leagueLogo,
                      week: week,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 17 * u,
                    child: Column(
                      children: [
                        Text(
                          'HAFTANIN',
                          style: _cond(
                            3.4 * u,
                            color: accent,
                          ).copyWith(letterSpacing: u),
                        ),
                        SizedBox(height: 0.8 * u),
                        Text(
                          a.kind.title.trUpper,
                          style: _cond(11.5 * u, italic: true),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 37 * u,
                    child: Center(child: _portrait(u, accent)),
                  ),
                  Positioned(
                    left: 6 * u,
                    right: 6 * u,
                    bottom: 12 * u,
                    child: Column(
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            title.trUpper,
                            maxLines: 1,
                            style: _cond(
                              a.kind == AwardKind.match ? 6.4 * u : 9 * u,
                            ),
                          ),
                        ),
                        if (sub.isNotEmpty) ...[
                          SizedBox(height: 1.4 * u),
                          Text(
                            sub.trUpper,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: const Color(0xFFC8D3E6),
                              fontSize: 3.2 * u,
                              letterSpacing: 0.3 * u,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (stats.isNotEmpty) ...[
                          SizedBox(height: 2 * u),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 1.6 * u,
                            runSpacing: 1.2 * u,
                            children: [
                              for (final s in stats)
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 2 * u,
                                    vertical: 0.8 * u,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(5 * u),
                                    border: Border.all(
                                      color: accent.withValues(alpha: 0.7),
                                      width: 0.35 * u,
                                    ),
                                  ),
                                  child: Text(
                                    s.trUpper,
                                    style: _cond(3.4 * u, color: accent),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 3.4 * u,
                    child: _Brand(u),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Kartın satırları: "2 GOL" → GOL 2, "4-0" → SKOR 4-0. Kalecide ve
  /// centilmende satır yok (centilmende FAIR PLAY rozeti).
  List<(String, String)> _rows() {
    final a = award;
    if (a.kind == AwardKind.keeper || a.kind == AwardKind.fair) return const [];
    final rows = <(String, String)>[];
    for (final s in a.stats) {
      final m = RegExp(r'^(\d+)\s+(.+)$').firstMatch(s.trim());
      if (m != null) {
        rows.add((m.group(2)!.trUpper, m.group(1)!));
      }
    }
    if (showRatings && a.rating != null && a.kind == AwardKind.player) {
      rows.add(('PUAN', a.rating!.toStringAsFixed(1)));
    }
    return rows;
  }

  Widget _photoFallback(double u, {bool team = false}) {
    final a = award;
    final bg = TeamPalette.of(a.team.color, null).background;
    return ColoredBox(
      color: bg,
      child: Center(
        child: team
            ? _net(
                a.team.logo,
                size: 40 * u,
                fit: BoxFit.contain,
                fallback: Text(
                  AwardPerson(id: '', name: a.team.short).initials,
                  style: _cond(16 * u),
                ),
              )
            : Text(a.person?.initials ?? '?', style: _cond(18 * u)),
      ),
    );
  }

  Widget _photo(
    double u, {
    Alignment alignment = Alignment.topCenter,
    bool team = false,
    BoxFit fit = BoxFit.cover,
  }) {
    final url = award.photo.trim();
    if (url.isEmpty) return _photoFallback(u, team: team);
    Widget net(String src, Widget Function() onError) => Image.network(
      src,
      fit: fit,
      alignment: alignment,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, _, _) => onError(),
    );
    // Kart 1080 px basılır: varsa fotoğrafın büyük kopyası.
    final hd = SupabaseImageUploadService.hdUrl(url);
    Widget small() => net(url, () => _photoFallback(u, team: team));
    return hd == url ? small() : net(hd, small);
  }

  /// Haftanın takımı: takım fotoğrafı bütün kartı kaplar.
  Widget _fullBleed() {
    final a = award;
    final accent = a.kind.color;
    final rival = a.home == null
        ? null
        : (a.home!.id == a.team.id ? a.away! : a.home!);
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: LayoutBuilder(
        builder: (context, c) {
          final u = c.maxWidth / 100;
          return ClipRRect(
            borderRadius: BorderRadius.circular(2 * u),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Takım fotoğrafı genelde yatay: kırpılmasın diye bütünü
                // ortada, arkasında aynı fotoğrafın bulanık hâli.
                if (a.photo.trim().isNotEmpty)
                  ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: 6 * u,
                      sigmaY: 6 * u,
                    ),
                    child: _photo(u, alignment: Alignment.center, team: true),
                  ),
                _photo(
                  u,
                  alignment: Alignment.center,
                  team: true,
                  fit: BoxFit.contain,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xD9050C14),
                        Color(0x00050C14),
                        Color(0x00050C14),
                        Color(0xBF050C14),
                        Color(0xF2050C14),
                      ],
                      stops: [0, 0.27, 0.5, 0.75, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 4.4 * u,
                  right: 34 * u,
                  top: 4 * u,
                  child: _Head(
                    u: u,
                    league: league,
                    logo: leagueLogo,
                    week: week,
                  ),
                ),
                Positioned(
                  right: 4 * u,
                  top: 3.4 * u,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'HAFTANIN',
                        style: _cond(
                          2.8 * u,
                          color: accent,
                        ).copyWith(letterSpacing: 0.8 * u),
                      ),
                      Text(
                        a.kind.title.trUpper,
                        style: _cond(9.4 * u, italic: true),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 4.4 * u,
                  right: 4.4 * u,
                  bottom: 4 * u,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _crest(a.team.logo, a.team.short, 11 * u),
                          SizedBox(width: 2.6 * u),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                a.team.short.trUpper,
                                maxLines: 1,
                                style: _cond(8.4 * u),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 1.6 * u),
                      Wrap(
                        spacing: 1.6 * u,
                        runSpacing: 1.2 * u,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (rival != null)
                            Text(
                              '${a.score} · ${rival.short}'.trUpper,
                              style: _cond(
                                3.8 * u,
                                color: const Color(0xFFCBD5E1),
                              ).copyWith(letterSpacing: 0.3 * u),
                            ),
                          for (final st in a.stats) _chip(u, st, accent),
                        ],
                      ),
                      SizedBox(height: 2.4 * u),
                      Container(height: 0.3 * u, color: Colors.white24),
                      SizedBox(height: 2 * u),
                      _Brand(u, align: MainAxisAlignment.start),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _chip(double u, String text, Color accent) => Container(
    padding: EdgeInsets.symmetric(horizontal: 2 * u, vertical: 0.6 * u),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(5 * u),
      border: Border.all(color: accent.withValues(alpha: 0.8), width: 0.35 * u),
    ),
    child: Text(text.trUpper, style: _cond(3.2 * u, color: accent)),
  );

  /// Kişiye verilen enler: solda eğik kesik fotoğraf, sağda bilgiler.
  Widget _split() {
    final a = award;
    final accent = a.kind.color;
    final words = (a.person?.name ?? '').trim().split(RegExp(r'\s+'));
    final first = words.length > 1
        ? words.sublist(0, words.length - 1).join(' ')
        : '';
    final last = words.isEmpty ? '' : words.last;
    final rows = _rows();
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: LayoutBuilder(
        builder: (context, c) {
          final u = c.maxWidth / 100;
          return ClipRRect(
            borderRadius: BorderRadius.circular(2 * u),
            child: ColoredBox(
              color: const Color(0xFF0B1A1F),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 53 * u,
                    child: ClipPath(
                      clipper: const _SlantClipper(),
                      child: _photo(u),
                    ),
                  ),
                  Positioned(
                    left: 47 * u,
                    right: 4.4 * u,
                    top: 4.4 * u,
                    bottom: 3.8 * u,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    league.trUpper,
                                    maxLines: 2,
                                    textAlign: TextAlign.right,
                                    style: _cond(3 * u, color: _gold),
                                  ),
                                  Text(
                                    '$week. HAFTA',
                                    style: _cond(
                                      2.8 * u,
                                      color: const Color(0xFFC8D3E6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: 1.8 * u),
                            _crest(leagueLogo, league, 7 * u),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          'HAFTANIN',
                          style: _cond(
                            2.8 * u,
                            color: accent,
                          ).copyWith(letterSpacing: 0.8 * u),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            a.kind.title.trUpper,
                            maxLines: 1,
                            style: _cond(
                              9 * u,
                              italic: true,
                              color: a.kind == AwardKind.goal
                                  ? accent
                                  : Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(height: 5 * u),
                        if (first.isNotEmpty)
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              first.trUpper,
                              maxLines: 1,
                              style: _cond(
                                5.4 * u,
                                color: const Color(0xFFCBD5E1),
                              ).copyWith(height: 1, letterSpacing: 0.3 * u),
                            ),
                          ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            last.trUpper,
                            maxLines: 1,
                            style: _cond(
                              9.6 * u,
                              color: accent,
                              italic: true,
                            ).copyWith(height: 1),
                          ),
                        ),
                        SizedBox(height: 1.6 * u),
                        Container(
                          width: 14 * u,
                          height: 0.6 * u,
                          color: accent,
                        ),
                        SizedBox(height: 2 * u),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Flexible(
                              child: Text(
                                a.team.short.trUpper,
                                maxLines: 2,
                                textAlign: TextAlign.right,
                                style: _cond(
                                  3.4 * u,
                                  color: const Color(0xFFE2E8F0),
                                ).copyWith(letterSpacing: 0.3 * u),
                              ),
                            ),
                            SizedBox(width: 1.8 * u),
                            _crest(a.team.logo, a.team.short, 7.5 * u),
                          ],
                        ),
                        if (a.kind == AwardKind.fair) ...[
                          SizedBox(height: 4 * u),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 2.8 * u,
                              vertical: 1.4 * u,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2.6 * u),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.7),
                                width: 0.3 * u,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(a.kind.icon, size: 5 * u, color: accent),
                                SizedBox(width: 1.6 * u),
                                Text(
                                  'FAIR PLAY',
                                  style: _cond(
                                    4.4 * u,
                                    color: accent,
                                  ).copyWith(letterSpacing: 0.4 * u),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (rows.isNotEmpty) ...[
                          SizedBox(height: 4 * u),
                          SizedBox(
                            width: 32 * u,
                            child: Column(
                              children: [
                                for (var i = 0; i < rows.length; i++)
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 0.6 * u,
                                    ),
                                    decoration: i == rows.length - 1
                                        ? null
                                        : BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: Colors.white.withValues(
                                                  alpha: 0.14,
                                                ),
                                                width: 0.3 * u,
                                              ),
                                            ),
                                          ),
                                    child: Row(
                                      children: [
                                        Text(
                                          rows[i].$1,
                                          style: TextStyle(
                                            color: _muted,
                                            fontSize: 2.8 * u,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.3 * u,
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          rows[i].$2,
                                          style: _cond(
                                            6 * u,
                                            color: i == 0
                                                ? accent
                                                : Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        const Spacer(),
                        SizedBox(height: 4 * u),
                        _Brand(u, align: MainAxisAlignment.end),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _portrait(double u, Color accent) {
    final a = award;
    if (a.kind == AwardKind.match && a.home != null) {
      Widget side(AwardTeam t) => Container(
        width: 22 * u,
        height: 22 * u,
        padding: EdgeInsets.all(3 * u),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: TeamPalette.of(t.color, null).background,
          border: Border.all(color: accent, width: 0.7 * u),
        ),
        child: _net(
          t.logo,
          size: 16 * u,
          fit: BoxFit.contain,
          fallback: Center(
            child: Text(
              AwardPerson(id: '', name: t.short).initials,
              style: _cond(7 * u),
            ),
          ),
        ),
      );
      return SizedBox(
        height: 40 * u,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            side(a.home!),
            SizedBox(width: 4 * u),
            Text(a.score, style: _cond(15 * u)),
            SizedBox(width: 4 * u),
            side(a.away!),
          ],
        ),
      );
    }
    final d = 40 * u;
    final teamColor = TeamPalette.of(a.team.color, null).background;
    final Widget fallback = a.kind == AwardKind.team
        ? Padding(
            padding: EdgeInsets.all(7 * u),
            child: _net(
              a.team.logo,
              size: d,
              fit: BoxFit.contain,
              fallback: Center(
                child: Text(
                  AwardPerson(id: '', name: a.team.short).initials,
                  style: _cond(12 * u),
                ),
              ),
            ),
          )
        : Center(child: Text(a.person?.initials ?? '?', style: _cond(15 * u)));
    return SizedBox(
      width: d + 4 * u,
      height: d + 4 * u,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: d + 4 * u,
            height: d + 4 * u,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accent, width: 0.8 * u),
              boxShadow: [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 6 * u,
                  offset: Offset(0, 3 * u),
                ),
              ],
            ),
          ),
          Container(
            width: d,
            height: d,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(shape: BoxShape.circle, color: teamColor),
            child: _net(
              a.photo,
              size: d,
              alignment: Alignment.topCenter,
              fallback: fallback,
            ),
          ),
          Positioned(
            right: -u,
            bottom: 0,
            child: Container(
              width: 12 * u,
              height: 12 * u,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent,
                border: Border.all(color: _night, width: 0.9 * u),
              ),
              child: Icon(a.kind.icon, size: 6.6 * u, color: _night),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fotoğrafın sağ kenarı eğik: üstte tam genişlik, altta %82.
class _SlantClipper extends CustomClipper<Path> {
  const _SlantClipper();

  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width * 0.82, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(_SlantClipper oldClipper) => false;
}

// ------------------------------------------------------------- haber kartı

/// Akışta ve haber detayında bülten: kaydırılan kartlar, her kart
/// Instagram'da (gönderi / hikâye) paylaşılabilir. Paylaşma herkese açık;
/// yayınlamak yalnız sorumlunun.
class WeekAwardsNewsCard extends StatefulWidget {
  const WeekAwardsNewsCard({
    super.key,
    required this.item,
    required this.meta,
    required this.loggedIn,
    required this.liked,
    required this.likeCount,
    required this.onToggleLike,
    required this.onShare,
    this.expandOnTap = false,
  });

  final NewsItem item;
  final String meta;
  final bool loggedIn;
  final bool liked;
  final int likeCount;
  final VoidCallback onToggleLike;
  final VoidCallback onShare;

  /// Haber detayında: karta dokununca kartlar tam ekranda açılır.
  final bool expandOnTap;

  @override
  State<WeekAwardsNewsCard> createState() => _WeekAwardsNewsCardState();
}

class _WeekAwardsNewsCardState extends State<WeekAwardsNewsCard> {
  late final Future<bool> _instagram = InstagramShare.isAvailable();
  final _pager = PageController();
  final _keys = <int, GlobalKey>{};
  int _page = 0;
  bool _busy = false;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  /// Haftanın Golü videosu (build'te güncellenir) ve kartın sayfa sırası.
  String _goalVideoUrl = '';
  int _goalPage = -1;

  Future<void> _shareInstagram() async {
    if (_busy) return;
    if (_page == _goalPage && _goalVideoUrl.isNotEmpty) {
      // 2 sn kart + gol videosu: hikâye olarak paylaşılır.
      final messenger = ScaffoldMessenger.of(context);
      setState(() => _busy = true);
      try {
        final r = await http.get(Uri.parse(_goalVideoUrl));
        if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
        if (!await InstagramShare.shareVideo(r.bodyBytes, story: true)) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Instagram açılamadı.')),
          );
        }
      } catch (_) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Video indirilemedi. Tekrar deneyin.')),
        );
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    final story = await askInstagramTarget(context);
    if (story == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final card = await captureCard(_keys[_page]!);
      // Gönderi 4:5 (1080×1350) olduğu gibi; hikâye 9:16 tuvale ortalanır,
      // Instagram'da büyütüp küçültmeden tam oturur.
      final png = story ? await storyCanvas(card) : card;
      final ok = await InstagramShare.share(png, story: story);
      if (!ok) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Instagram açılamadı.')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Instagram\'a aktarılamadı: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _play(WeekAward a) {
    final c = a.clip;
    if (c == null) return;
    final id = (c['video_id'] ?? '').toString();
    if (id.isEmpty) return;
    openYoutubeClip(
      context,
      videoId: id,
      startSec: (c['start'] as num?)?.toInt() ?? 0,
      endSec: (c['end'] as num?)?.toInt() ?? 0,
      title: a.person?.name ?? 'Gol',
      clipUrl: c['clip_url']?.toString(),
      storyUrl: c['story_url']?.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = WeekAwards.fromJson(widget.item.autoData!);
    final league = w.leagueName.isNotEmpty
        ? w.leagueName
        : widget.item.leagueName;
    final logo = w.leagueLogo.isNotEmpty
        ? w.leagueLogo
        : (widget.item.leagueLogoUrl ?? '');
    final week = w.week > 0 ? w.week : (widget.item.week ?? 0);
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.matchInsightsEnabled,
      builder: (context, ratings, _) {
        final cards = <Widget>[
          if (w.hasEleven)
            WeekElevenCard(
              league: league,
              leagueLogo: logo,
              week: week,
              formation: w.formation,
              slots: w.eleven,
              showRatings: ratings,
            ),
          for (final a in w.awards)
            WeekAwardCard(
              award: a,
              league: league,
              leagueLogo: logo,
              week: week,
              showRatings: ratings,
            ),
        ];
        // Kartın ödülü (11 kartında yok).
        WeekAward? awardAt(int i) {
          final k = i - (w.hasEleven ? 1 : 0);
          return k >= 0 && k < w.awards.length ? w.awards[k] : null;
        }

        void openFull(int i) => Navigator.of(context).push(
          PageRouteBuilder<void>(
            opaque: false,
            barrierColor: Colors.black,
            transitionDuration: const Duration(milliseconds: 180),
            pageBuilder: (_, _, _) => _AwardsFullScreen(
              cards: cards,
              initial: i,
              week: week,
              awardAt: awardAt,
              onPlay: _play,
            ),
            transitionsBuilder: (_, anim, _, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );

        final pages = <Widget>[
          for (final (i, c) in cards.indexed)
            GestureDetector(
              onTap: widget.expandOnTap
                  ? () => openFull(i)
                  : awardAt(i)?.kind == AwardKind.goal
                  ? () => _play(awardAt(i)!)
                  : null,
              child: c,
            ),
          // Yayından sonra eklenen Instagram gönderisi / Reels son sayfa.
          if (w.instagramUrl.isNotEmpty)
            ColoredBox(
              color: Colors.black,
              child: InstagramEmbed(url: w.instagramUrl, focused: true),
            ),
        ];
        final igPage = w.instagramUrl.isNotEmpty ? cards.length : -1;
        final videoOk =
            w.goalVideoUrl.isNotEmpty &&
            (AppSession.of(context).value.isAdmin ||
                AppSettings.goalClipMp4Enabled.value);
        _goalVideoUrl = videoOk ? w.goalVideoUrl : '';
        _goalPage = w.awards.indexWhere((a) => a.kind == AwardKind.goal) >= 0
            ? w.awards.indexWhere((a) => a.kind == AwardKind.goal) +
                  (w.hasEleven ? 1 : 0)
            : -1;
        // Görünen kart haftanın golüyse altında "Golü izle".
        final goal = _goalWithClip(awardAt(_page));
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _gold,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'HAFTANIN ENLERİ',
                        style: _cond(
                          12,
                          color: const Color(0xFF1A1404),
                        ).copyWith(letterSpacing: 0.6),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        [
                          if (week > 0) '$week. Hafta',
                          widget.meta,
                        ].where((e) => e.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ),
                    if (pages.length > 1)
                      Text(
                        '${_page + 1}/${pages.length}',
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              // Kart (4:5) alanın tamamını kaplar; en-boy oranı korunur, bu
              // yüzden alan da 4:5'tir (fotoğraf şişmez / kırpılmaz).
              AspectRatio(
                aspectRatio: 4 / 5,
                child: PageView.builder(
                  controller: _pager,
                  itemCount: pages.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) => RepaintBoundary(
                    key: _keys.putIfAbsent(i, GlobalKey.new),
                    child: pages[i],
                  ),
                ),
              ),
              if (pages.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < pages.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _page ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _page ? _gold : Colors.white24,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                    ],
                  ),
                ),
              if (goal != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: FilledButton.icon(
                    onPressed: () => _play(goal),
                    style: FilledButton.styleFrom(
                      backgroundColor: AwardKind.goal.color,
                      foregroundColor: _night,
                      minimumSize: const Size.fromHeight(42),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text(
                      'Golü izle',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              FutureBuilder<bool>(
                future: _instagram,
                builder: (context, snap) => NewsCardActions(
                  loggedIn: widget.loggedIn,
                  liked: widget.liked,
                  likeCount: widget.likeCount,
                  onToggleLike: widget.onToggleLike,
                  onShare: widget.onShare,
                  onInstagram:
                      snap.data == true &&
                          !_busy &&
                          pages.isNotEmpty &&
                          _page != igPage
                      ? _shareInstagram
                      : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Videosu olan haftanın golü; değilse null.
WeekAward? _goalWithClip(WeekAward? a) =>
    a != null &&
        a.kind == AwardKind.goal &&
        (a.clip?['video_id'] ?? '').toString().isNotEmpty
    ? a
    : null;

/// Bülten kartları tam ekranda: kaydırılır, iki parmakla yakınlaşır, aşağı
/// çekince kapanır; görünen kart tek başına paylaşılır.
class _AwardsFullScreen extends StatefulWidget {
  const _AwardsFullScreen({
    required this.cards,
    required this.initial,
    required this.week,
    required this.awardAt,
    required this.onPlay,
  });

  final List<Widget> cards;
  final int initial;
  final int week;
  final WeekAward? Function(int) awardAt;
  final void Function(WeekAward) onPlay;

  @override
  State<_AwardsFullScreen> createState() => _AwardsFullScreenState();
}

class _AwardsFullScreenState extends State<_AwardsFullScreen> {
  late final _pager = PageController(initialPage: widget.initial);
  late int _page = widget.initial;
  late final Future<bool> _instagram = InstagramShare.isAvailable();
  final _keys = <int, GlobalKey>{};
  final _zoom = <int, TransformationController>{};
  bool _zoomed = false;
  bool _busy = false;

  @override
  void dispose() {
    _pager.dispose();
    for (final c in _zoom.values) {
      c.dispose();
    }
    super.dispose();
  }

  TransformationController _zoomOf(int i) => _zoom.putIfAbsent(i, () {
    final c = TransformationController();
    c.addListener(() {
      final z = c.value.getMaxScaleOnAxis() > 1.01;
      if (i == _page && z != _zoomed) setState(() => _zoomed = z);
    });
    return c;
  });

  String get _fileName => 'haftanin_enleri_${widget.week}_${_page + 1}';

  Future<void> _run(Future<void> Function(Uint8List card) job) async {
    final key = _keys[_page];
    if (_busy || key == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await job(await captureCard(key));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Paylaşılamadı: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareInstagram() async {
    final story = await askInstagramTarget(context);
    if (story == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await _run((card) async {
      final png = story ? await storyCanvas(card) : card;
      if (!await InstagramShare.share(png, story: story)) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Instagram açılamadı.')),
        );
      }
    });
  }

  Future<void> _shareOther() => _run(
    (card) => SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(card, mimeType: 'image/png', name: '$_fileName.png'),
        ],
        fileNameOverrides: ['$_fileName.png'],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final goal = _goalWithClip(widget.awardAt(_page));
    final n = widget.cards.length;
    return Scaffold(
      backgroundColor: const Color(0xFF05080F),
      body: SafeArea(
        child: GestureDetector(
          // Yakınlaşmışken parmak fotoğrafı gezdirir; kapatmaz.
          onVerticalDragEnd: _zoomed
              ? null
              : (d) {
                  if ((d.primaryVelocity ?? 0) > 500) {
                    Navigator.of(context).maybePop();
                  }
                },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        [
                          'HAFTANIN ENLERİ',
                          if (widget.week > 0) '${widget.week}. HAFTA',
                        ].join(' · '),
                        style: _cond(15, color: _gold),
                      ),
                    ),
                    if (n > 1)
                      Text(
                        '${_page + 1}/$n',
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pager,
                  physics: _zoomed
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  itemCount: n,
                  onPageChanged: (i) => setState(() {
                    _zoom[_page]?.value = Matrix4.identity();
                    _page = i;
                    _zoomed = false;
                  }),
                  itemBuilder: (context, i) => InteractiveViewer(
                    transformationController: _zoomOf(i),
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 4 / 5,
                        child: RepaintBoundary(
                          key: _keys.putIfAbsent(i, GlobalKey.new),
                          child: widget.cards[i],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (n > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < n; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _page ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _page ? _gold : Colors.white24,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  children: [
                    if (goal != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: FilledButton.icon(
                          onPressed: () => widget.onPlay(goal),
                          style: FilledButton.styleFrom(
                            backgroundColor: AwardKind.goal.color,
                            foregroundColor: _night,
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text(
                            'Golü izle',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: FutureBuilder<bool>(
                            future: _instagram,
                            builder: (context, snap) => _GradientButton(
                              label: 'Bu kartı paylaş',
                              onPressed: snap.data == true && !_busy
                                  ? _shareInstagram
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 50,
                          height: 50,
                          child: OutlinedButton(
                            onPressed: _busy ? null : _shareOther,
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white24),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.send_rounded,
                                    semanticLabel: 'Diğer uygulamalar',
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Instagram renklerinde geniş düğme.
class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onPressed == null ? 0.5 : 1,
    child: Material(
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        height: 50,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF58529), Color(0xFFDD2A7B), Color(0xFF8134AF)],
          ),
        ),
        child: InkWell(
          onTap: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.camera_alt_outlined, color: Colors.white),
              const SizedBox(width: 8),
              Text(label, style: _cond(17)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Kartı 1080 piksel genişliğinde PNG'ye çizer.
Future<Uint8List> captureCard(GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1080 / boundary.size.width);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) throw Exception('Görsel oluşturulamadı.');
  return data.buffer.asUint8List();
}

/// Kartı 1080×1920 hikâye tuvaline ortalar: koyu zemin, kart yuvarlak
/// köşeli ve gölgeli.
Future<Uint8List> storyCanvas(Uint8List cardPng) async {
  const w = 1080.0, h = 1920.0;
  final codec = await ui.instantiateImageCodec(cardPng);
  final card = (await codec.getNextFrame()).image;
  codec.dispose();
  final rec = ui.PictureRecorder();
  final c = Canvas(rec, const Rect.fromLTWH(0, 0, w, h));
  c.drawRect(
    const Rect.fromLTWH(0, 0, w, h),
    Paint()
      ..shader = ui.Gradient.radial(
        const Offset(w / 2, h * 0.3),
        h * 0.8,
        const [Color(0xFF17324A), _night, Color(0xFF060A12)],
        const [0, 0.55, 1],
      ),
  );
  const cw = 960.0;
  final ch = cw * card.height / card.width;
  final dst = Rect.fromLTWH((w - cw) / 2, (h - ch) / 2, cw, ch);
  final r = RRect.fromRectAndRadius(dst, const Radius.circular(28));
  c.drawRRect(
    r.shift(const Offset(0, 16)),
    Paint()
      ..color = Colors.black54
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
  );
  c.save();
  c.clipRRect(r);
  c.drawImageRect(
    card,
    Rect.fromLTWH(0, 0, card.width.toDouble(), card.height.toDouble()),
    dst,
    Paint()..filterQuality = FilterQuality.high,
  );
  c.restore();
  final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) throw Exception('Görsel oluşturulamadı.');
  return data.buffer.asUint8List();
}

/// Instagram'da gönderi mi (false) hikâye mi (true); vazgeçilirse null.
Future<bool?> askInstagramTarget(
  BuildContext context,
) => showModalBottomSheet<bool>(
  context: context,
  backgroundColor: _card,
  builder: (ctx) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Instagram\'da paylaş',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Görünen kart, Instagram\'da o an açık olan hesaptan paylaşılır.',
            style: TextStyle(color: _muted, fontSize: 12.5),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.grid_on_rounded, color: Colors.white),
          title: const Text('Gönderi', style: TextStyle(color: Colors.white)),
          subtitle: const Text(
            'Açıklama yazarak',
            style: TextStyle(color: _muted),
          ),
          onTap: () => Navigator.pop(ctx, false),
        ),
        ListTile(
          leading: const Icon(Icons.amp_stories_outlined, color: Colors.white),
          title: const Text('Hikâye', style: TextStyle(color: Colors.white)),
          subtitle: const Text(
            'Müzik, çıkartma ekleyerek',
            style: TextStyle(color: _muted),
          ),
          onTap: () => Navigator.pop(ctx, true),
        ),
        const SizedBox(height: 8),
      ],
    ),
  ),
);

/// Haftanın Enleri haberinin ortak kapağı: başlık ve kazananların yuvarlak
/// fotoğrafları; altta "kaydır" ibaresi. Alt kısım haber başlığına boş
/// kalır. 6 ödüle kadar tek satırda küçülerek sığar.
class WeekAwardsCover extends StatelessWidget {
  const WeekAwardsCover({super.key, required this.data});

  final WeekAwards data;

  @override
  Widget build(BuildContext context) {
    final w = data;
    final items = <(String, String, String, String)>[
      // (etiket, fotoğraf, yedek arma, ad)
      if (w.hasEleven) ("11'İ", '', '', ''),
      for (final a in w.awards)
        (
          a.kind.title.trUpper,
          a.photo.isNotEmpty ? a.photo : (a.person?.photo ?? ''),
          a.team.logo,
          a.person?.name ?? a.team.short,
        ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        // Alt %40 haber başlığına kalır; dar/alçak kutuda küçülür.
        final u = math.min(c.maxWidth / 100, c.maxHeight / 92);
        final n = math.max(items.length, 1);
        final size = math.min(17 * u, (c.maxWidth - 8 * u) / n - 3 * u);
        Widget circle((String, String, String, String) it) {
          final fallback = it.$1 == "11'İ"
              ? Center(
                  child: Text('11', style: _cond(size * 0.42, color: _gold)),
                )
              : Padding(
                  padding: EdgeInsets.all(size * 0.16),
                  child: _crest(it.$3, it.$4, size * 0.68),
                );
          return SizedBox(
            width: size + 3 * u,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: size,
                  height: size,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _card,
                    border: Border.all(color: _gold, width: 0.6 * u),
                    boxShadow: [
                      BoxShadow(
                        color: _gold.withValues(alpha: 0.35),
                        blurRadius: 4 * u,
                      ),
                    ],
                  ),
                  child: it.$2.isEmpty
                      ? fallback
                      : _net(
                          it.$2,
                          size: size,
                          alignment: const Alignment(0, -0.6),
                          fallback: fallback,
                        ),
                ),
                SizedBox(height: 1.2 * u),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    it.$1,
                    maxLines: 1,
                    style: _cond(
                      math.min(3.2 * u, size * 0.17),
                    ).copyWith(letterSpacing: 0.3 * u),
                  ),
                ),
              ],
            ),
          );
        }

        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF13233D), Color(0xFF060B14)],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: -3 * u,
                top: 0,
                child: Text(
                  'ENLER',
                  style: _cond(
                    26 * u,
                    italic: true,
                    color: Colors.white.withValues(alpha: 0.04),
                  ),
                ),
              ),
              Positioned(
                left: 4 * u,
                right: 4 * u,
                top: 4 * u,
                child: Column(
                  children: [
                    Text(
                      [
                        if (w.leagueName.isNotEmpty) w.leagueName.trUpper,
                        if (w.week > 0) '${w.week}. HAFTA',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _cond(
                        2.8 * u,
                        color: _gold,
                      ).copyWith(letterSpacing: 0.8 * u),
                    ),
                    Text(
                      'HAFTANIN ENLERİ',
                      style: _cond(8.4 * u, italic: true),
                    ),
                    SizedBox(height: 2 * u),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [for (final it in items) circle(it)],
                    ),
                    SizedBox(height: 2 * u),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 2.8 * u,
                        vertical: 1.2 * u,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xBF060B14),
                        borderRadius: BorderRadius.circular(4 * u),
                        border: Border.all(
                          color: _gold.withValues(alpha: 0.6),
                          width: 0.3 * u,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${items.length} ÖDÜL · KAYDIR',
                            style: _cond(
                              3 * u,
                              color: _gold,
                            ).copyWith(letterSpacing: 0.3 * u),
                          ),
                          SizedBox(width: 1.2 * u),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 3.6 * u,
                            color: _gold,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
