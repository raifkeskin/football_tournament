import 'dart:ui';

/// Diziliş sahasında oyuncunun konumu (0-1 arası oran; x soldan, y üstten).
///
/// Hatlar düz çizgi değil, gerçek maçtaki gibi yerleşir:
/// - Defans: dörtlü/beşli savunmada bekler stoperlerden biraz ileride.
/// - Orta saha (tek hat): üçlüde ortadaki ön libero geride, iki orta saha
///   önde ve açıkta; beşlide kanat bekleri ileride, ortadaki geride.
/// - Hücum: üçlüde kanat forvetleri santraforun gerisinde ve çizgiye yakın.
/// - Dört hatlı dizilişlerde (4-2-3-1 vb.) ikinci orta saha hattında
///   kanatlar biraz önde.
///
/// [li]: 0 kaleci, 1 defans … [lines.length - 1] hücum; [i] hattaki sıra,
/// [n] hattaki oyuncu sayısı, [outfieldLines] saha oyuncusu hat sayısı.
Offset pitchSlot({
  required int li,
  required int i,
  required int n,
  required int outfieldLines,
}) {
  if (li == 0) return const Offset(0.5, 0.90);
  final last = outfieldLines;

  // Hat yüksekliği: defans 0.70 → hücum 0.16, eşit aralıklı.
  final baseY = last <= 1 ? 0.44 : 0.70 - (li - 1) * (0.54 / (last - 1));

  // Genişlik: kalabalık hatlar çizgiye kadar yayılır.
  final isAttack = li == last && last > 1;
  final double margin;
  if (n <= 1) {
    margin = 0.5;
  } else if (n == 2) {
    margin = isAttack ? 0.34 : 0.30;
  } else if (n == 3) {
    margin = isAttack ? 0.15 : 0.22;
  } else if (n == 4) {
    margin = 0.12;
  } else {
    margin = 0.09;
  }
  final x = n <= 1 ? 0.5 : margin + i * (1 - 2 * margin) / (n - 1);

  final outer = n >= 3 && (i == 0 || i == n - 1);
  final center = n.isOdd && i == n ~/ 2;
  var dy = 0.0; // pozitif: geride (kaleye yakın), negatif: önde
  if (li == 1 && last > 1) {
    // Savunma: bekler önde.
    if (n == 4 && outer) dy = -0.035;
    if (n >= 5 && outer) dy = -0.06;
  } else if (isAttack) {
    // Hücum: kanat forvetleri geride ve açıkta, santrafor en önde.
    if (n == 3 && outer) dy = 0.07;
    if (n >= 4 && outer) dy = 0.05;
  } else if (last == 3) {
    // Tek orta saha hattı.
    if (n == 3 && center) dy = 0.06;
    if (n == 5) {
      if (outer) dy = -0.05;
      if (center) dy = 0.04;
    }
    if (n == 4 && outer) dy = -0.02;
  } else if (li == last - 1) {
    // Dört hatlı dizilişte forvet arkası hat: kanatlar önde.
    if (n >= 3 && outer) dy = -0.03;
  }
  return Offset(x, baseY + dy);
}
