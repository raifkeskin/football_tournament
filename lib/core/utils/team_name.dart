// \b Türkçe harfleri (ı, ş...) tanımadığı için Unicode harf kontrolü.
final _masterWord = RegExp(
  r'(?<!\p{L})master(?:ları|leri|lar|ler)?(?!\p{L})',
  caseSensitive: false,
  unicode: true,
);

/// Dar alanlar (maç detayı üst bandı, puan durumu) için takım adı.
///
/// Bu turnuvada neredeyse her takımda geçen "Master / Masterler / Masterlar"
/// kelimesi gösterilmez; "Spor Kulübü" → SK, "Futbol Kulübü" → FK.
/// Veritabanındaki ad değişmez. Ad yalnızca bu kelimeden ibaretse olduğu
/// gibi kalır.
String shortTeamName(String raw) {
  final original = raw.trim();
  final s = original
      .replaceAll(_masterWord, ' ')
      .replaceAll(RegExp(r'Spor Kulübü', caseSensitive: false), 'SK')
      .replaceAll(RegExp(r'Futbol Kulübü', caseSensitive: false), 'FK')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return s.isEmpty ? original : s;
}

final _masterAbbr = RegExp(
  r'(?<!\p{L})master(?:ları|leri|lar|ler)(?!\p{L})',
  caseSensitive: false,
  unicode: true,
);
final _veteranAbbr = RegExp(
  r'(?<!\p{L})veteran(?:ları|lar)(?!\p{L})',
  caseSensitive: false,
  unicode: true,
);

/// Liste satırları (fikstür) için: ad [maxLength] karakterden uzunsa
/// "Masterler / Masterlar" → "M.", "Veteranlar" → "V." kısaltılır.
/// Kısa adlar olduğu gibi kalır; veritabanındaki ad değişmez.
String compactTeamName(String raw, {int maxLength = 22}) {
  final s = raw.trim();
  if (s.length <= maxLength) return s;
  return s
      .replaceAll(_masterAbbr, 'M.')
      .replaceAll(_veteranAbbr, 'V.')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
