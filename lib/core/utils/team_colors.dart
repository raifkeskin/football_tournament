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
