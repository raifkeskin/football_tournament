import 'package:flutter/painting.dart';

/// "#RRGGBB" / "RRGGBB" → Color; geçersizse null.
Color? parseHexColor(String? raw) {
  var s = (raw ?? '').trim().replaceAll('#', '');
  if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
  if (s.length != 6) return null;
  final v = int.tryParse(s, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// Color → "#RRGGBB".
String colorToHex(Color c) {
  String two(double v) =>
      (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${two(c.r)}${two(c.g)}${two(c.b)}'.toUpperCase();
}

/// Takımın iki renginden afiş / kart için türetilen palet. Koyu zemin her
/// zaman okunur kalır; vurgu rengi koyu zeminde seçilebilecek kadar açıktır.
class TeamPalette {
  const TeamPalette({
    required this.primary,
    required this.secondary,
    required this.background,
    required this.backgroundDeep,
    required this.accent,
    required this.onAccent,
  });

  /// Takımın ana ve ikinci rengi (olduğu gibi).
  final Color primary;
  final Color secondary;

  /// Afiş zemini: ana rengin koyulaştırılmış hali (üst → alt).
  final Color background;
  final Color backgroundDeep;

  /// Numara kutuları, başlık çizgileri: koyu zeminde okunur vurgu.
  final Color accent;
  final Color onAccent;

  static const _fallbackPrimary = Color(0xFF10B981);
  static const _fallbackSecondary = Color(0xFFFFFFFF);

  factory TeamPalette.of(String? firstHex, String? secondHex) {
    final p = parseHexColor(firstHex) ?? _fallbackPrimary;
    final s = parseHexColor(secondHex) ?? _fallbackSecondary;
    final hp = HSLColor.fromColor(p);

    // Zemin: ana rengin tonunda, okunacak kadar koyu.
    final bg = hp
        .withLightness(hp.lightness.clamp(0.0, 0.22))
        .withSaturation((hp.saturation * 0.9).clamp(0.0, 0.85))
        .toColor();
    final bgDeep = hp
        .withLightness(0.07)
        .withSaturation((hp.saturation * 0.7).clamp(0.0, 0.6))
        .toColor();

    // Vurgu: ana renk yeterince açıksa o, değilse ikinci renk; ikisi de
    // koyuysa ana rengin açılmış hali.
    Color pickAccent() {
      for (final c in [p, s]) {
        final l = HSLColor.fromColor(c).lightness;
        if (l >= 0.45 && _contrast(c, bg) >= 3) return c;
      }
      return hp.withLightness(0.62).toColor();
    }

    final accent = pickAccent();
    final onAccent = accent.computeLuminance() > 0.45
        ? const Color(0xFF0B1220)
        : const Color(0xFFFFFFFF);
    return TeamPalette(
      primary: p,
      secondary: s,
      background: bg,
      backgroundDeep: bgDeep,
      accent: accent,
      onAccent: onAccent,
    );
  }

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance() + 0.05;
    final lb = b.computeLuminance() + 0.05;
    return la > lb ? la / lb : lb / la;
  }
}

/// Maç başlığında iki tarafın renkleri: [home] / [away] zemin, [homeStripe] /
/// [awayStripe] alt şerit (takımın diğer rengi).
typedef MatchSideColors = ({
  Color home,
  Color homeStripe,
  Color away,
  Color awayStripe,
});

/// Sahadaki forma kuralı gibi: ev sahibi ana rengini kullanır; deplasmanın
/// ana rengi çok yakınsa ikinci rengine geçer; o da yakınsa ev sahibi ikinci
/// rengine geçer; hepsi aynıysa deplasman koyu nötr zemine döner. Renk
/// girilmemiş tarafta [fallback] kullanılır.
MatchSideColors matchSideColors({
  String? homeFirst,
  String? homeSecond,
  String? awayFirst,
  String? awaySecond,
  required Color fallback,
}) {
  final h1 = parseHexColor(homeFirst) ?? fallback;
  final h2 = parseHexColor(homeSecond);
  final a1 = parseHexColor(awayFirst) ?? fallback;
  final a2 = parseHexColor(awaySecond);
  const white = Color(0xFFFFFFFF);
  const neutral = Color(0xFF334155);

  if (!colorsClash(h1, a1)) {
    return (
      home: h1,
      homeStripe: h2 ?? white,
      away: a1,
      awayStripe: a2 ?? white,
    );
  }
  if (a2 != null && !colorsClash(h1, a2)) {
    return (home: h1, homeStripe: h2 ?? white, away: a2, awayStripe: a1);
  }
  if (h2 != null && !colorsClash(h2, a1)) {
    return (home: h2, homeStripe: h1, away: a1, awayStripe: a2 ?? white);
  }
  return (home: h1, homeStripe: h2 ?? white, away: neutral, awayStripe: a1);
}

/// İki renk yan yana ayırt edilemeyecek kadar yakın mı ("redmean" uzaklığı).
bool colorsClash(Color a, Color b) {
  final r1 = a.r * 255, g1 = a.g * 255, b1 = a.b * 255;
  final r2 = b.r * 255, g2 = b.g * 255, b2 = b.b * 255;
  final rm = (r1 + r2) / 2;
  final dr = r1 - r2, dg = g1 - g2, db = b1 - b2;
  final d2 =
      (2 + rm / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rm) / 256) * db * db;
  return d2 < 130 * 130;
}
